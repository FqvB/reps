import Foundation
import SwiftData
import Testing

@testable import Reps

@MainActor
struct SessionControllerTests {
    // Keep the container alive; a context alone doesn't retain it.
    let container: ModelContainer
    let context: ModelContext
    let clock: TestClock
    let clips: ClipSpy
    let log: EventLog
    let controller: SessionController

    init() throws {
        let clock = TestClock()
        let clips = ClipSpy()
        let log = EventLog()
        container = try RepsStore.makeContainer(inMemory: true)
        context = container.mainContext
        controller = SessionController(context: context, clipFiles: clips, now: { clock.next() })
        controller.addEventHandler { log.events.append($0) }
        self.clock = clock
        self.clips = clips
        self.log = log
    }

    private func makePlan(strict: Bool = false, ordered: Bool = false, targets: [Int] = [3, 2, 2]) -> PracticePlan {
        let plan = PracticePlan(
            name: "Wedge day", mode: .rangeCounter, isOrderMandatory: ordered, isStrictCount: strict)
        context.insert(plan)
        let clubs = ["8 iron", "9 iron", "PW"]
        plan.blocks = targets.enumerated().map { PlanBlock(clubName: clubs[$0], targetReps: $1, order: $0) }
        return plan
    }

    private func start(strict: Bool = false, ordered: Bool = false, targets: [Int] = [3, 2, 2]) throws {
        try controller.start(plan: makePlan(strict: strict, ordered: ordered, targets: targets), cameraAngle: .faceOn)
        log.events = []
    }

    private func hit(_ count: Int, _ source: DetectionSource = .camera) {
        for _ in 0..<count { controller.recordShot(source: source) }
    }

    private var activeClub: String? { controller.activeBlock?.clubName }
    private var done: [Int] { controller.blocks.map(\.tally.done) }

    @Test func startCreatesOneResultPerPlanBlock() throws {
        let plan = makePlan(strict: true, ordered: true)
        try controller.start(plan: plan, cameraAngle: .downTheLine)

        let session = try #require(controller.session)
        #expect(session.status == .active)
        #expect(session.plan === plan)
        #expect(session.isStrictCount && session.isOrderMandatory)
        #expect(session.cameraAngle == .downTheLine)
        #expect(controller.blocks.map(\.clubName) == ["8 iron", "9 iron", "PW"])
        #expect(controller.blocks.map(\.targetReps) == [3, 2, 2])
        #expect(controller.blocks.map(\.order) == [0, 1, 2])
        #expect(done == [0, 0, 0])
        #expect(activeClub == "8 iron")
        #expect(session.activeBlockOrder == 0)
        #expect(log.events == [.blockChanged(clubName: "8 iron", target: 3, done: 0)])
        #expect(!context.hasChanges)
        #expect(try context.fetchCount(FetchDescriptor<BlockResult>()) == 3)
    }

    @Test func startRejectsEmptyPlan() throws {
        let plan = makePlan(targets: [])
        #expect(throws: SessionError.emptyPlan) { try controller.start(plan: plan, cameraAngle: .faceOn) }
        #expect(controller.session == nil)
        #expect(try context.fetchCount(FetchDescriptor<PracticeSession>()) == 0)
    }

    @Test func startWhileRunningThrows() throws {
        try start()
        #expect(throws: SessionError.sessionInProgress) {
            try controller.start(plan: makePlan(), cameraAngle: .faceOn)
        }
        #expect(throws: SessionError.sessionInProgress) {
            try controller.startFree(mode: .rangeCounter, cameraAngle: .faceOn, clubName: "7 iron")
        }
        #expect(try context.fetchCount(FetchDescriptor<PracticeSession>()) == 1)
    }

    @Test func startRefusesWhenAnotherSessionIsActiveInStore() throws {
        try start()
        // A fresh controller instance has no in-memory session, but one is already active in the store.
        let other = SessionController(context: context, clipFiles: clips, now: { clock.next() })
        #expect(throws: SessionError.sessionInProgress) {
            try other.start(plan: makePlan(), cameraAngle: .faceOn)
        }
        #expect(throws: SessionError.sessionInProgress) {
            try other.startFree(mode: .rangeCounter, cameraAngle: .faceOn, clubName: "7 iron")
        }
        #expect(try context.fetchCount(FetchDescriptor<PracticeSession>()) == 1)
    }

    @Test func startReownsAPlanFetchedFromAnotherContext() throws {
        let plan = makePlan()
        try context.save()
        let otherContext = ModelContext(container)
        let fetchedPlan = try #require(try otherContext.fetch(FetchDescriptor<PracticePlan>()).first)
        try controller.start(plan: fetchedPlan, cameraAngle: .faceOn)
        #expect(controller.session != nil)
        controller.recordShot(source: .camera)
        #expect(try context.fetchCount(FetchDescriptor<ShotRecord>()) == 1)
    }

    @Test func cameraShotCountsAsDetection() throws {
        try start()
        let shot = try #require(controller.recordShot(source: .camera))
        let block = try #require(controller.activeBlock)
        #expect(block.repsCounted == 1)
        #expect(block.repsManualAdjust == 0)
        #expect(block.shots.map(\.id) == [shot.id])
        #expect(shot.detectedBy == .camera)
        #expect(shot.clubName == "8 iron")
        #expect(shot.timestamp == clock.date)
        #expect(log.events == [.countChanged(done: 1, target: 3)])
        #expect(!context.hasChanges)
    }

    @Test func manualShotCountsAsAdjustment() throws {
        try start()
        let shot = try #require(controller.recordShot(source: .manual))
        let block = try #require(controller.activeBlock)
        #expect(block.repsCounted == 0)
        #expect(block.repsManualAdjust == 1)
        #expect(shot.detectedBy == .manual)
        #expect(try context.fetchCount(FetchDescriptor<ShotRecord>()) == 1)
    }

    @Test func minimumsKeepCountingPastTarget() throws {
        try start()
        hit(4)
        #expect(activeClub == "8 iron")
        #expect(done == [4, 0, 0])
        #expect(Completion.block(controller.blocks[0].tally) == 4.0 / 3.0)
        #expect(
            log.events == [
                .countChanged(done: 1, target: 3), .countChanged(done: 2, target: 3), .countChanged(done: 3, target: 3),
                .targetReached(clubName: "8 iron", target: 3, isStrict: false), .countChanged(done: 4, target: 3),
            ])
    }

    @Test func strictAdvancesExactlyAtTarget() throws {
        try start(strict: true)
        hit(3)
        #expect(activeClub == "9 iron")
        #expect(controller.session?.activeBlockOrder == 1)
        #expect(
            log.events.suffix(3) == [
                .countChanged(done: 3, target: 3),
                .targetReached(clubName: "8 iron", target: 3, isStrict: true),
                .blockChanged(clubName: "9 iron", target: 2, done: 0),
            ])
        hit(1)
        #expect(done == [3, 1, 0])
    }

    @Test func strictLastBlockEndsPlanAndIgnoresShots() throws {
        try start(strict: true, targets: [1, 1])
        hit(2)
        #expect(controller.activeBlock == nil)
        #expect(controller.session?.activeBlockOrder == nil)
        #expect(log.events.last == .planEnded)
        #expect(controller.isPlanComplete)
        #expect(controller.recordShot(source: .camera) == nil)
        #expect(controller.recordShot(source: .manual) == nil)
        #expect(done == [1, 1])
        #expect(try context.fetchCount(FetchDescriptor<ShotRecord>()) == 2)
    }

    @Test func strictFreeOrderAdvancesToNextIncompleteBlock() throws {
        try start(strict: true, targets: [1, 1, 1])
        #expect(controller.select(controller.blocks[2]))
        hit(1)
        #expect(activeClub == "8 iron")
        hit(1)
        #expect(activeClub == "9 iron")
        hit(1)
        #expect(controller.activeBlock == nil)
        #expect(log.events.last == .planEnded)
    }

    @Test func strictMandatoryOrderRunsInSequence() throws {
        try start(strict: true, ordered: true)
        controller.advance()
        #expect(activeClub == "9 iron")
        hit(2)
        #expect(activeClub == "PW")
        hit(2)
        #expect(controller.activeBlock == nil)
        #expect(log.events.last == .planEnded)
        #expect(!controller.isPlanComplete)
        #expect(controller.session?.completion == 4.0 / 7.0)
    }

    @Test func advanceBeforeTargetSkipsTheBlock() throws {
        try start()
        hit(1)
        controller.advance()
        #expect(activeClub == "9 iron")
        #expect(done == [1, 0, 0])
        #expect(controller.session?.completion == 1.0 / 7.0)
        #expect(log.events.last == .blockChanged(clubName: "9 iron", target: 2, done: 0))
    }

    @Test func advancePastLastBlockEndsPlan() throws {
        try start(ordered: true)
        controller.advance()
        controller.advance()
        controller.advance()
        #expect(controller.activeBlock == nil)
        #expect(log.events.last == .planEnded)
        #expect(controller.recordShot(source: .manual) == nil)
        let count = log.events.count
        controller.advance()
        #expect(log.events.count == count)
    }

    @Test func freeOrderJumpsAndComesBack() throws {
        try start()
        #expect(controller.select(controller.blocks[2]))
        #expect(log.events == [.blockChanged(clubName: "PW", target: 2, done: 0)])
        hit(1)
        #expect(controller.select(controller.blocks[0]))
        hit(1)
        #expect(done == [1, 0, 1])
        #expect(!controller.select(controller.blocks[0]))
    }

    @Test func mandatoryOrderRefusesJumps() throws {
        try start(ordered: true)
        #expect(!controller.canSelectBlocks)
        #expect(!controller.select(controller.blocks[1]))
        #expect(activeClub == "8 iron")
        #expect(log.events.isEmpty)
    }

    @Test func strictRefusesJumpToFinishedBlock() throws {
        try start(strict: true, targets: [1, 2])
        hit(1)
        #expect(activeClub == "9 iron")
        #expect(!controller.select(controller.blocks[0]))
        #expect(activeClub == "9 iron")
    }

    @Test func minimumsFreeOrderAdvanceFindsIncompleteBlocks() throws {
        try start(targets: [1, 1, 1])
        hit(1)
        #expect(activeClub == "8 iron")
        #expect(controller.select(controller.blocks[2]))
        hit(1)
        controller.advance()
        #expect(activeClub == "9 iron")
        hit(1)
        #expect(controller.isPlanComplete)
        controller.advance()
        #expect(controller.activeBlock == nil)
        #expect(log.events.last == .planEnded)
        #expect(controller.select(controller.blocks[0]))
        hit(1)
        #expect(done == [2, 1, 1])
    }

    @Test func freeOrderAdvanceSkipsZeroTargetBlocks() throws {
        try start(targets: [1, 0, 1])
        hit(1)
        #expect(activeClub == "8 iron")
        controller.advance()
        // The middle block has no target, so it can never complete; free order skips straight past it.
        #expect(activeClub == "PW")
        hit(1)
        #expect(controller.isPlanComplete)
        // Both targeted blocks are complete; without the fix this would loop back onto the zero-target block.
        controller.advance()
        #expect(controller.activeBlock == nil)
        #expect(log.events.last == .planEnded)
    }

    @Test func planEditsDoNotChangeRunningSession() throws {
        let plan = makePlan(strict: true, targets: [2, 2])
        try controller.start(plan: plan, cameraAngle: .faceOn)
        plan.isStrictCount = false
        plan.isOrderMandatory = true
        plan.sortedBlocks[0].targetReps = 10
        try context.save()
        hit(2)
        #expect(activeClub == "9 iron")
        #expect(controller.canSelectBlocks)
    }

    @Test func minusOneDeletesLatestShot() throws {
        try start()
        hit(2)
        hit(1, .manual)
        controller.minusOne()
        var block = try #require(controller.activeBlock)
        #expect(block.shots.map(\.detectedBy) == [.camera, .camera])
        #expect(block.repsCounted == 2)
        #expect(block.repsManualAdjust == 0)
        #expect(log.events.last == .countChanged(done: 2, target: 3))

        controller.minusOne()
        block = try #require(controller.activeBlock)
        #expect(block.shots.count == 1)
        #expect(block.repsCounted == 2)
        #expect(block.repsManualAdjust == -1)
        #expect(block.tally.done == 1)
        #expect(try context.fetchCount(FetchDescriptor<ShotRecord>()) == 1)
        #expect(!context.hasChanges)
    }

    @Test func minusOneWithoutShotsLowersAdjustment() throws {
        try start()
        let block = try #require(controller.activeBlock)
        block.repsCounted = 2
        try context.save()
        controller.minusOne()
        #expect(block.repsManualAdjust == -1)
        #expect(block.tally.done == 1)
        #expect(log.events == [.countChanged(done: 1, target: 3)])
    }

    @Test func minusOneNeverGoesBelowZero() throws {
        try start()
        controller.minusOne()
        #expect(controller.activeBlock?.repsManualAdjust == 0)
        #expect(log.events.isEmpty)
        hit(1)
        controller.minusOne()
        controller.minusOne()
        #expect(controller.activeBlock?.tally.done == 0)
        #expect(controller.activeBlock?.repsManualAdjust == -1)
        #expect(log.events == [.countChanged(done: 1, target: 3), .countChanged(done: 0, target: 3)])
    }

    @Test func minusOneSkipsClipRemovalWhenSaveFails() throws {
        var shouldFail = false
        let controller = SessionController(
            context: context, clipFiles: clips, now: { clock.next() },
            saveHook: {
                if shouldFail { throw TestSaveError() }
                try context.save()
            })
        try controller.start(plan: makePlan(), cameraAngle: .faceOn)
        let shot = try #require(controller.recordShot(source: .camera))
        shot.clipFileName = "\(shot.id.uuidString).mov"
        try context.save()

        shouldFail = true
        controller.minusOne()
        #expect(clips.removedClips.isEmpty)
        #expect(controller.lastSaveError != nil)
    }

    @Test func discardSkipsClipRemovalWhenSaveFails() throws {
        var shouldFail = false
        let controller = SessionController(
            context: context, clipFiles: clips, now: { clock.next() },
            saveHook: {
                if shouldFail { throw TestSaveError() }
                try context.save()
            })
        try controller.start(plan: makePlan(), cameraAngle: .faceOn)
        controller.recordShot(source: .camera)

        shouldFail = true
        controller.discard()
        #expect(clips.removedSessions.isEmpty)
        #expect(controller.lastSaveError != nil)
    }

    @Test func minusOneRemovesClipFile() throws {
        try start()
        hit(1)
        let shot = try #require(controller.recordShot(source: .camera))
        shot.clipFileName = "\(shot.id.uuidString).mov"
        try context.save()
        let sessionID = try #require(controller.session?.id)
        controller.minusOne()
        #expect(clips.removedClips == ["\(sessionID.uuidString)/\(shot.id.uuidString).mov"])
        controller.minusOne()
        #expect(clips.removedClips.count == 1)
    }

    @Test func minusOneAfterStrictAdvanceReopensBlock() throws {
        try start(strict: true, targets: [2, 2])
        hit(2)
        #expect(activeClub == "9 iron")
        controller.minusOne()
        #expect(activeClub == "8 iron")
        #expect(done == [1, 0])
        #expect(
            log.events.suffix(2) == [
                .countChanged(done: 1, target: 2), .blockChanged(clubName: "8 iron", target: 2, done: 1),
            ])
        hit(1)
        #expect(activeClub == "9 iron")
        #expect(done == [2, 0])
    }

    @Test func minusOneAfterStrictPlanEndReopensLastBlock() throws {
        try start(strict: true, targets: [1])
        hit(1)
        #expect(controller.activeBlock == nil)
        controller.minusOne()
        #expect(activeClub == "8 iron")
        #expect(done == [0])
        #expect(controller.recordShot(source: .camera) != nil)
    }

    @Test func minusOneAfterNextShotStaysOnActiveBlock() throws {
        try start(strict: true, targets: [1, 2])
        hit(2)
        controller.minusOne()
        #expect(activeClub == "9 iron")
        #expect(done == [1, 0])
    }

    @Test func tagsApplyToShotsAndCarryAcrossBlocks() throws {
        try start()
        controller.setTags(["fade"])
        #expect(controller.activeBlock?.tags == ["fade"])
        let first = try #require(controller.recordShot(source: .camera))
        #expect(first.tags == ["fade"])
        controller.advance()
        #expect(controller.activeBlock?.tags == ["fade"])
        #expect(controller.recordShot(source: .manual)?.tags == ["fade"])
        controller.setTags([])
        #expect(controller.recordShot(source: .camera)?.tags == [])
        #expect(controller.blocks.count == 3)
        #expect(!context.hasChanges)
    }

    @Test func finishMarksSessionFinished() throws {
        try start()
        hit(1)
        let session = try #require(controller.session)
        controller.finish()
        #expect(session.status == .finished)
        #expect(session.endedAt == clock.date)
        #expect(session.activeBlockOrder == nil)
        #expect(session.blockResults.count == 3)
        #expect(controller.session == nil)
        #expect(controller.activeBlock == nil)
        #expect(controller.recordShot(source: .camera) == nil)
        #expect(try SessionController.activeSession(in: ModelContext(container)) == nil)
    }

    @Test func discardDeletesSessionAndClips() throws {
        try start()
        hit(2)
        let sessionID = try #require(controller.session?.id)
        controller.discard()
        #expect(controller.session == nil)
        #expect(try context.fetchCount(FetchDescriptor<PracticeSession>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<BlockResult>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ShotRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PracticePlan>()) == 1)
        #expect(clips.removedSessions == [sessionID])
    }
}
