import Foundation
import SwiftData
import Testing

@testable import Reps

// On-disk store in a temp folder; dropping a container without finish() stands in for a kill.
@MainActor
final class SessionResumeTests {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(
            path: "reps-resume-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private var storeURL: URL { directory.appending(path: "reps.store") }

    @Test func resumesPlannedSessionAfterKill() throws {
        let clock = TestClock()
        var sessionID: UUID?
        do {
            let container = try RepsStore.makeContainer(url: storeURL)
            let context = container.mainContext
            // Only the controller's explicit saves may reach disk.
            context.autosaveEnabled = false
            let plan = PracticePlan(name: "Putting test", mode: .putting, isOrderMandatory: true, isStrictCount: true)
            context.insert(plan)
            plan.blocks = [
                PlanBlock(clubName: "Putter", targetReps: 2, order: 0),
                PlanBlock(clubName: "Putter", targetReps: 3, note: "6ft", order: 1),
            ]
            let controller = SessionController(context: context, now: { clock.next() })
            try controller.start(plan: plan, cameraAngle: .none)
            controller.setTags(["gate"])
            controller.recordShot(source: .camera)
            controller.recordShot(source: .manual)
            controller.recordShot(source: .camera)
            sessionID = controller.session?.id
        }

        let container = try RepsStore.makeContainer(url: storeURL)
        let context = container.mainContext
        let plan = try #require(try context.fetch(FetchDescriptor<PracticePlan>()).first)
        plan.isStrictCount = false
        plan.isOrderMandatory = false
        context.delete(plan)
        try context.save()

        let saved = try #require(try SessionController.activeSession(in: context))
        #expect(saved.id == sessionID)
        #expect(saved.plan == nil)
        let log = EventLog()
        let controller = SessionController(context: context, now: { clock.next() })
        controller.addEventHandler { log.events.append($0) }
        try controller.resume(saved)

        #expect(controller.activeBlock?.order == 1)
        #expect(controller.activeTags == ["gate"])
        #expect(controller.isStrictCount && controller.isOrderMandatory)
        #expect(controller.blocks.map(\.tally.done) == [2, 1])
        #expect(controller.blocks.map(\.targetReps) == [2, 3])
        #expect(controller.blocks[0].shots.count == 2)
        #expect(controller.blocks[1].shots.first?.tags == ["gate"])
        #expect(log.events == [.blockChanged(clubName: "Putter", target: 3, done: 1)])
        #expect(!controller.select(controller.blocks[0]))

        controller.recordShot(source: .camera)
        controller.recordShot(source: .camera)
        #expect(log.events.last == .planEnded)
    }

    @Test func resumesFreeSessionChipAndTags() throws {
        let clock = TestClock()
        do {
            let container = try RepsStore.makeContainer(url: storeURL)
            container.mainContext.autosaveEnabled = false
            let controller = SessionController(context: container.mainContext, now: { clock.next() })
            try controller.startFree(mode: .rangeCounterWithClips, cameraAngle: .downTheLine, clubName: "7 iron")
            controller.recordShot(source: .camera)
            controller.setClub("PW")
            controller.setTags(["low"])
        }

        let container = try RepsStore.makeContainer(url: storeURL)
        let saved = try #require(try SessionController.activeSession(in: container.mainContext))
        let controller = SessionController(context: container.mainContext, now: { clock.next() })
        try controller.resume(saved)
        #expect(controller.isFreeSession)
        #expect(controller.activeBlock?.clubName == "PW")
        #expect(controller.activeTags == ["low"])
        #expect(controller.blocks.map(\.tally.done) == [1, 0])
        #expect(controller.recordShot(source: .camera)?.tags == ["low"])
    }

    @Test func activeSessionIsNewestActiveOnly() throws {
        let container = try RepsStore.makeContainer(inMemory: true)
        let context = container.mainContext
        #expect(try SessionController.activeSession(in: context) == nil)

        let t0 = Date(timeIntervalSince1970: 1_790_000_000)
        let finished = PracticeSession(plan: nil, mode: .rangeCounter, cameraAngle: .faceOn, startedAt: t0)
        finished.status = .finished
        let older = PracticeSession(plan: nil, mode: .rangeCounter, cameraAngle: .faceOn, startedAt: t0 + 10)
        let newer = PracticeSession(plan: nil, mode: .putting, cameraAngle: .none, startedAt: t0 + 20)
        for session in [finished, older, newer] { context.insert(session) }
        try context.save()

        #expect(try SessionController.activeSession(in: context)?.id == newer.id)
        let controller = SessionController(context: context)
        #expect(throws: SessionError.notActive) { try controller.resume(finished) }
    }

    @Test func resumeAfterStrictPlanEndedHasNoActiveBlock() throws {
        let container = try RepsStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let plan = PracticePlan(name: "Test", mode: .putting, isStrictCount: true)
        context.insert(plan)
        plan.blocks = [PlanBlock(clubName: "Putter", targetReps: 1, order: 0)]
        let first = SessionController(context: context)
        try first.start(plan: plan, cameraAngle: .none)
        first.recordShot(source: .camera)

        let saved = try #require(try SessionController.activeSession(in: context))
        let log = EventLog()
        let second = SessionController(context: context)
        second.addEventHandler { log.events.append($0) }
        try second.resume(saved)
        #expect(second.activeBlock == nil)
        #expect(log.events == [.planEnded])
        #expect(second.recordShot(source: .camera) == nil)
    }
}
