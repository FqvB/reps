import Foundation
import SwiftData
import Testing

@testable import Reps

@MainActor
struct FreeSessionTests {
    let container: ModelContainer
    let context: ModelContext
    let log: EventLog
    let controller: SessionController

    init() throws {
        let clock = TestClock()
        let log = EventLog()
        container = try RepsStore.makeContainer(inMemory: true)
        context = container.mainContext
        controller = SessionController(context: context, now: { clock.next() })
        controller.addEventHandler { log.events.append($0) }
        self.log = log
        try controller.startFree(mode: .rangeCounter, cameraAngle: .faceOn, clubName: "7 iron", tags: ["fade"])
    }

    private func hit(_ count: Int) {
        for _ in 0..<count { controller.recordShot(source: .camera) }
    }

    @Test func startsWithOneUntargetedBlock() throws {
        let session = try #require(controller.session)
        #expect(session.plan == nil)
        #expect(session.planName == nil)
        #expect(controller.isFreeSession)
        #expect(!controller.isStrictCount)
        #expect(controller.blocks.count == 1)
        #expect(controller.activeBlock?.targetReps == nil)
        #expect(controller.activeBlock?.tags == ["fade"])
        #expect(controller.activeTags == ["fade"])
        #expect(log.events == [.blockChanged(clubName: "7 iron", target: nil, done: 0)])
        #expect(!context.hasChanges)
    }

    @Test func countsWithoutTargetOrAdvance() throws {
        hit(50)
        #expect(controller.activeBlock?.tally.done == 50)
        #expect(controller.blocks.count == 1)
        #expect(!log.events.contains { if case .targetReached = $0 { true } else { false } })
        #expect(controller.session?.completion == nil)
        #expect(!controller.isPlanComplete)
        #expect(controller.activeBlock?.shots.allSatisfy { $0.clubName == "7 iron" && $0.tags == ["fade"] } == true)
    }

    @Test func clubChangeStartsNewBlock() throws {
        hit(2)
        controller.setClub("8 iron")
        #expect(controller.blocks.map(\.clubName) == ["7 iron", "8 iron"])
        #expect(controller.blocks.map(\.order) == [0, 1])
        #expect(controller.activeBlock?.tags == ["fade"])
        #expect(log.events.last == .blockChanged(clubName: "8 iron", target: nil, done: 0))
        #expect(controller.recordShot(source: .manual)?.clubName == "8 iron")
        #expect(controller.blocks.map(\.tally.done) == [2, 1])
        #expect(controller.session?.activeBlockOrder == 1)
    }

    @Test func clubChangeOnUnusedBlockRenamesIt() throws {
        controller.setClub("8 iron")
        #expect(controller.blocks.map(\.clubName) == ["8 iron"])
        #expect(log.events.last == .blockChanged(clubName: "8 iron", target: nil, done: 0))
    }

    @Test func sameClubChangesNothing() throws {
        hit(1)
        let count = log.events.count
        controller.setClub("7 iron")
        #expect(controller.blocks.count == 1)
        #expect(log.events.count == count)
    }

    @Test func tagChangeStartsNewBlock() throws {
        hit(1)
        controller.setTags(["draw"])
        #expect(controller.blocks.map(\.clubName) == ["7 iron", "7 iron"])
        #expect(controller.blocks.map(\.tags) == [["fade"], ["draw"]])
        controller.setTags(["draw"])
        #expect(controller.blocks.count == 2)
        hit(1)
        controller.setTags(["draw", "low"])
        controller.setTags(["low", "draw"])
        #expect(controller.blocks.count == 3)
    }

    @Test func tagChangeOnUnusedBlockUpdatesIt() throws {
        controller.setTags(["draw"])
        #expect(controller.blocks.count == 1)
        #expect(controller.activeBlock?.tags == ["draw"])
        #expect(!context.hasChanges)
    }

    @Test func blockNavigationIsOff() throws {
        hit(1)
        controller.setClub("8 iron")
        controller.advance()
        #expect(controller.activeBlock?.clubName == "8 iron")
        #expect(!controller.canSelectBlocks)
        #expect(!controller.select(controller.blocks[0]))
    }

    @Test func minusOneWorksWithoutTarget() throws {
        hit(2)
        controller.minusOne()
        #expect(controller.activeBlock?.tally.done == 1)
        #expect(controller.activeBlock?.shots.count == 1)
    }

    @Test func finishWithOnlyUnusedBlocksDiscardsTheSession() throws {
        // Nothing was ever hit, so finish would otherwise save an empty finished session.
        controller.finish()
        #expect(controller.session == nil)
        #expect(try context.fetchCount(FetchDescriptor<PracticeSession>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<BlockResult>()) == 0)
    }

    @Test func finishDropsUnusedBlocks() throws {
        hit(1)
        controller.setClub("8 iron")
        let session = try #require(controller.session)
        controller.finish()
        #expect(session.status == .finished)
        let fresh = ModelContext(container)
        let saved = try #require(try fresh.fetch(FetchDescriptor<PracticeSession>()).first)
        #expect(saved.sortedBlockResults.map(\.clubName) == ["7 iron"])
        #expect(try fresh.fetchCount(FetchDescriptor<BlockResult>()) == 1)
    }

    @Test func discardedFreeSessionIsNotAnnounced() throws {
        controller.finish()
        #expect(!log.events.contains(.sessionSaved))
    }

    @Test func finishedFreeSessionIsAnnounced() throws {
        hit(1)
        controller.finish()
        #expect(log.events.last == .sessionSaved)
    }
}
