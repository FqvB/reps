import Foundation
import SwiftData
import Testing

@testable import Reps

@MainActor
struct PlanLibraryTests {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        container = try RepsStore.makeContainer(inMemory: true)
        context = container.mainContext
    }

    private func wedgeDraft() -> PlanDraft {
        PlanDraft(
            name: "  Wedge day ",
            mode: .rangeCounterWithClips,
            isOrderMandatory: true,
            blocks: [
                BlockDraft(clubName: " PW", targetReps: 40, note: "110 m"),
                BlockDraft(clubName: "GW", targetReps: 30, note: "  "),
                BlockDraft(clubName: "SW", targetReps: 20),
            ]
        )
    }

    private func summary(_ plan: PracticePlan) -> [String] {
        plan.sortedBlocks.map { "\($0.order):\($0.clubName):\($0.targetReps):\($0.note ?? "-")" }
    }

    @Test func saveCreatesPlanWithOrderedBlocks() throws {
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let plan = try PlanLibrary.save(wedgeDraft(), to: nil, in: context, now: createdAt)
        #expect(plan.name == "Wedge day")
        #expect(plan.mode == .rangeCounterWithClips)
        #expect(plan.isOrderMandatory)
        #expect(!plan.isStrictCount)
        #expect(plan.createdAt == createdAt)
        #expect(summary(plan) == ["0:PW:40:110 m", "1:GW:30:-", "2:SW:20:-"])
        #expect(try context.fetchCount(FetchDescriptor<PracticePlan>()) == 1)
    }

    @Test func draftRoundTripsWithoutChanges() throws {
        let plan = try PlanLibrary.save(wedgeDraft(), to: nil, in: context)
        let draft = PlanLibrary.draft(from: plan)
        #expect(draft.name == "Wedge day")
        #expect(draft.blocks.map(\.id) == plan.sortedBlocks.map(\.id))
        #expect(draft.blocks[1].note == "")
        try PlanLibrary.save(draft, to: plan, in: context)
        #expect(PlanLibrary.draft(from: plan) == draft)
    }

    @Test func saveEditsInPlaceAndRenumbers() throws {
        let plan = try PlanLibrary.save(wedgeDraft(), to: nil, in: context)
        let ids = plan.sortedBlocks.map(\.id)
        var draft = PlanLibrary.draft(from: plan)
        draft.name = "Wedges"
        draft.isStrictCount = true
        draft.blocks[0].targetReps = 45
        draft.moveBlocks(fromOffsets: [2], toOffset: 0)
        draft.upsert(BlockDraft(clubName: "LW", targetReps: 10))
        try PlanLibrary.save(draft, to: plan, in: context)

        #expect(plan.name == "Wedges")
        #expect(plan.isStrictCount)
        #expect(summary(plan) == ["0:SW:20:-", "1:PW:45:110 m", "2:GW:30:-", "3:LW:10:-"])
        #expect(Array(plan.sortedBlocks.map(\.id).prefix(3)) == [ids[2], ids[0], ids[1]])
        #expect(plan.sortedBlocks[3].id == draft.blocks[3].id)
        #expect(try context.fetchCount(FetchDescriptor<PracticePlan>()) == 1)
    }

    @Test func removedBlockIsDeletedAndResultsKeepTheirSnapshot() throws {
        let plan = try PlanLibrary.save(wedgeDraft(), to: nil, in: context)
        let session = PracticeSession(plan: plan, mode: plan.mode, cameraAngle: .faceOn)
        context.insert(session)
        let gw = plan.sortedBlocks[1]
        let kept = BlockResult(block: plan.sortedBlocks[0], order: 0)
        let orphaned = BlockResult(block: gw, order: 1)
        session.blockResults = [kept, orphaned]
        try context.save()

        var draft = PlanLibrary.draft(from: plan)
        _ = draft.removeBlock(id: gw.id)
        try PlanLibrary.save(draft, to: plan, in: context)

        #expect(summary(plan) == ["0:PW:40:110 m", "1:SW:20:-"])
        #expect(try context.fetchCount(FetchDescriptor<PlanBlock>()) == 2)
        #expect(orphaned.block == nil)
        #expect(orphaned.clubName == "GW")
        #expect(orphaned.targetReps == 30)
        #expect(kept.block?.clubName == "PW")
    }

    @Test func duplicateDeepCopiesBlocksInOrder() throws {
        let plan = PracticePlan(name: "Irons", mode: .putting, isOrderMandatory: true, isStrictCount: true)
        context.insert(plan)
        plan.blocks = [
            PlanBlock(clubName: "9 iron", targetReps: 30, order: 9),
            PlanBlock(clubName: "7 iron", targetReps: 20, note: "150 m", order: 0),
            PlanBlock(clubName: "8 iron", targetReps: 25, order: 5),
        ]
        let session = PracticeSession(plan: plan, mode: plan.mode, cameraAngle: .none)
        context.insert(session)
        try context.save()

        let createdAt = Date(timeIntervalSince1970: 2_000)
        let copy = try PlanLibrary.duplicate(plan, in: context, now: createdAt)

        #expect(copy.id != plan.id)
        #expect(copy.name == "Irons copy")
        #expect(copy.mode == .putting)
        #expect(copy.isOrderMandatory)
        #expect(copy.isStrictCount)
        #expect(copy.createdAt == createdAt)
        #expect(copy.sessions.isEmpty)
        #expect(summary(copy) == ["0:7 iron:20:150 m", "1:8 iron:25:-", "2:9 iron:30:-"])
        #expect(Set(copy.blocks.map(\.id)).isDisjoint(with: plan.blocks.map(\.id)))
        #expect(plan.blocks.count == 3)
        #expect(plan.sessions.count == 1)
        #expect(try context.fetchCount(FetchDescriptor<PlanBlock>()) == 6)
    }

    @Test func deleteKeepsSessionsWithTheirSnapshot() throws {
        let plan = try PlanLibrary.save(wedgeDraft(), to: nil, in: context)
        let session = PracticeSession(plan: plan, mode: plan.mode, cameraAngle: .faceOn)
        context.insert(session)
        let result = BlockResult(block: plan.sortedBlocks[0], order: 0)
        session.blockResults = [result]
        try context.save()

        try PlanLibrary.delete(plan, in: context)

        #expect(try context.fetchCount(FetchDescriptor<PracticePlan>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PlanBlock>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PracticeSession>()) == 1)
        #expect(session.plan == nil)
        #expect(session.planName == "Wedge day")
        #expect(result.block == nil)
        #expect(result.clubName == "PW")
    }

    @Test func lastDoneIsNewestFinishedSession() throws {
        let plan = try PlanLibrary.save(wedgeDraft(), to: nil, in: context)
        #expect(PlanLibrary.lastDone(plan) == nil)

        let older = PracticeSession(
            plan: plan, mode: plan.mode, cameraAngle: .faceOn, startedAt: Date(timeIntervalSince1970: 100))
        older.status = .finished
        older.endedAt = Date(timeIntervalSince1970: 200)
        let noEnd = PracticeSession(
            plan: plan, mode: plan.mode, cameraAngle: .faceOn, startedAt: Date(timeIntervalSince1970: 300))
        noEnd.status = .finished
        let active = PracticeSession(
            plan: plan, mode: plan.mode, cameraAngle: .faceOn, startedAt: Date(timeIntervalSince1970: 900))
        for session in [older, noEnd, active] { context.insert(session) }
        try context.save()

        #expect(PlanLibrary.lastDone(plan) == Date(timeIntervalSince1970: 300))
    }
}
