import Foundation
import SwiftData
import Testing

@testable import Reps

@MainActor
struct SessionLogTests {
    // Keep the container alive; a context alone doesn't retain it.
    let container: ModelContainer
    let context: ModelContext
    let clips = ClipSpy()

    init() throws {
        container = try RepsStore.makeContainer(inMemory: true)
        context = container.mainContext
    }

    private func makeSession(status: SessionStatus) throws -> PracticeSession {
        let plan = PracticePlan(name: "Wedge day", mode: .rangeCounter)
        context.insert(plan)
        plan.blocks = [PlanBlock(clubName: "PW", targetReps: 30, order: 0)]
        let session = PracticeSession(plan: plan, mode: .rangeCounter, cameraAngle: .faceOn)
        context.insert(session)
        let result = BlockResult(block: plan.blocks[0], order: 0)
        session.blockResults.append(result)
        result.shots.append(ShotRecord(detectedBy: .manual, clubName: "PW"))
        result.repsManualAdjust = 1
        session.status = status
        try context.save()
        return session
    }

    @Test func deleteRemovesSessionResultsShotsAndClips() throws {
        let session = try makeSession(status: .finished)
        let id = session.id
        try SessionLog.delete(session, in: context, clipFiles: clips)
        #expect(try context.fetchCount(FetchDescriptor<PracticeSession>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<BlockResult>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ShotRecord>()) == 0)
        #expect(clips.removedSessions == [id])
        // The plan and its blocks stay.
        #expect(try context.fetchCount(FetchDescriptor<PracticePlan>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<PlanBlock>()) == 1)
    }

    @Test func deleteRefusesAnActiveSession() throws {
        let session = try makeSession(status: .active)
        #expect(throws: SessionLogError.notFinished) {
            try SessionLog.delete(session, in: context, clipFiles: clips)
        }
        #expect(try context.fetchCount(FetchDescriptor<PracticeSession>()) == 1)
        #expect(clips.removedSessions.isEmpty)
    }
}
