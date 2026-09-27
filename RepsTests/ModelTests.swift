import Foundation
import SwiftData
import Testing

@testable import Reps

@MainActor
struct ModelTests {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        container = try RepsStore.makeContainer(inMemory: true)
        context = container.mainContext
    }

    private func makePlan() -> PracticePlan {
        let plan = PracticePlan(name: "Wedge day", mode: .rangeCounter)
        context.insert(plan)
        plan.blocks = [
            PlanBlock(clubName: "9 iron", targetReps: 30, order: 1),
            PlanBlock(clubName: "8 iron", targetReps: 40, note: "150m", order: 0),
        ]
        return plan
    }

    private func makeSession(plan: PracticePlan) -> PracticeSession {
        let session = PracticeSession(plan: plan, mode: plan.mode, cameraAngle: .faceOn)
        context.insert(session)
        session.blockResults = plan.sortedBlocks.enumerated().map { BlockResult(block: $1, order: $0) }
        let first = session.sortedBlockResults[0]
        first.shots = [ShotRecord(detectedBy: .manual, clubName: first.clubName, tags: ["fade"])]
        first.repsManualAdjust = 1
        return session
    }

    @Test func sortedBlocksFollowOrderIndex() throws {
        let plan = makePlan()
        try context.save()
        #expect(plan.sortedBlocks.map(\.clubName) == ["8 iron", "9 iron"])
    }

    @Test func blockResultSnapshotsPlanBlock() throws {
        let session = makeSession(plan: makePlan())
        try context.save()
        let results = session.sortedBlockResults
        #expect(results.map(\.clubName) == ["8 iron", "9 iron"])
        #expect(results.map(\.targetReps) == [40, 30])
        #expect(session.planName == "Wedge day")
    }

    @Test func deletingPlanCascadesBlocksAndKeepsHistory() throws {
        let plan = makePlan()
        let session = makeSession(plan: plan)
        try context.save()

        context.delete(plan)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<PracticePlan>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PlanBlock>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PracticeSession>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<BlockResult>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<ShotRecord>()) == 1)
        #expect(session.plan == nil)
        #expect(session.planName == "Wedge day")
        #expect(session.blockResults.allSatisfy { $0.block == nil })
        #expect(session.sortedBlockResults.map(\.targetReps) == [40, 30])
    }

    @Test func deletingPlanBlockKeepsResult() throws {
        let plan = makePlan()
        let session = makeSession(plan: plan)
        try context.save()

        let block = try #require(plan.sortedBlocks.first)
        context.delete(block)
        try context.save()

        #expect(plan.blocks.count == 1)
        #expect(session.blockResults.count == 2)
        #expect(session.sortedBlockResults[0].block == nil)
        #expect(session.sortedBlockResults[0].clubName == "8 iron")
    }

    @Test func deletingSessionCascadesResultsAndShots() throws {
        let plan = makePlan()
        let session = makeSession(plan: plan)
        try context.save()

        context.delete(session)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<PracticeSession>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<BlockResult>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ShotRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PlanBlock>()) == 2)
        #expect(plan.sessions.isEmpty)
    }

    @Test func enumsAndTagsPersist() throws {
        let session = PracticeSession(plan: nil, mode: .putting, cameraAngle: .none)
        context.insert(session)
        let result = BlockResult(clubName: "Putter", tags: ["gate drill"], order: 0)
        session.blockResults = [result]
        result.shots = [ShotRecord(detectedBy: .camera, clubName: "Putter", tags: ["gate drill", "3ft"])]
        session.status = .finished
        try context.save()

        let fresh = ModelContext(container)
        let fetched = try #require(try fresh.fetch(FetchDescriptor<PracticeSession>()).first)
        #expect(fetched.mode == .putting)
        #expect(fetched.status == .finished)
        #expect(fetched.cameraAngle == .none)
        #expect(fetched.plan == nil)
        #expect(fetched.blockResults.first?.tags == ["gate drill"])
        #expect(fetched.blockResults.first?.targetReps == nil)
        #expect(fetched.blockResults.first?.shots.first?.detectedBy == .camera)
        #expect(fetched.blockResults.first?.shots.first?.tags == ["gate drill", "3ft"])
    }

    @Test func activeSessionsAreFetchableByStatus() throws {
        let activeSession = PracticeSession(plan: nil, mode: .rangeCounter, cameraAngle: .faceOn)
        let done = PracticeSession(plan: nil, mode: .rangeCounter, cameraAngle: .faceOn)
        done.status = .finished
        context.insert(activeSession)
        context.insert(done)
        try context.save()

        let active = SessionStatus.active
        let descriptor = FetchDescriptor<PracticeSession>(predicate: #Predicate { $0.status == active })
        #expect(try context.fetch(descriptor).map(\.id) == [activeSession.id])
    }

    @Test func sessionCompletionUsesSnapshots() throws {
        let session = makeSession(plan: makePlan())
        let results = session.sortedBlockResults
        results[0].repsCounted = 39
        results[1].repsCounted = 30
        try context.save()
        #expect(session.completion == 1.0)
    }
}
