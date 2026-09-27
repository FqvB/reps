import Foundation
import SwiftData
import Testing

@testable import Reps

@MainActor
struct ExportTests {
    // Keep the container alive; a context alone doesn't retain it.
    let container: ModelContainer
    let context: ModelContext
    let t0 = Date(timeIntervalSince1970: 1_790_000_000.25)

    init() throws {
        container = try RepsStore.makeContainer(inMemory: true)
        context = container.mainContext
    }

    // One plan with two blocks, one finished session using it, one active free session.
    private func seed() throws {
        context.insert(BagClub(name: "9 iron", sortOrder: 1))
        context.insert(BagClub(name: "8 iron", sortOrder: 0, isInBag: false))

        let plan = PracticePlan(name: "Wedge day", mode: .rangeCounterWithClips, isStrictCount: true, createdAt: t0)
        context.insert(plan)
        plan.blocks = [
            PlanBlock(clubName: "9 iron", targetReps: 30, order: 1),
            PlanBlock(clubName: "8 iron", targetReps: 40, note: "150m, fade", order: 0),
        ]

        let finished = PracticeSession(plan: plan, mode: plan.mode, cameraAngle: .downTheLine, startedAt: t0)
        context.insert(finished)
        finished.blockResults = plan.sortedBlocks.enumerated().map { BlockResult(block: $1, order: $0) }
        let first = finished.sortedBlockResults[0]
        first.tags = ["fade"]
        first.repsCounted = 1
        first.repsManualAdjust = 1
        let late = ShotRecord(timestamp: t0.addingTimeInterval(20.5), detectedBy: .manual, clubName: "8 iron")
        let early = ShotRecord(
            timestamp: t0.addingTimeInterval(10), detectedBy: .camera, clubName: "8 iron", tags: ["fade"])
        early.clipFileName = "clips/abc/\(early.id.uuidString).mov"
        early.tempoRatio = 3.1
        early.isFavourite = true
        first.shots = [late, early]
        finished.status = .finished
        finished.endedAt = t0.addingTimeInterval(3600)

        let active = PracticeSession(
            plan: nil, mode: .putting, cameraAngle: .none, startedAt: t0.addingTimeInterval(7200))
        context.insert(active)
        try context.save()
    }

    private func json() throws -> [String: Any] {
        try seed()
        let document = try RepsExport.document(from: context, exportedAt: t0)
        let data = try ExportCoding.encode(document)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func topLevelShape() throws {
        let root = try json()
        #expect(Set(root.keys) == ["formatVersion", "exportedAt", "bag", "plans", "sessions"])
        #expect(root["formatVersion"] as? Int == 1)
        #expect(root["exportedAt"] as? String == "2026-09-21T14:13:20.250Z")
    }

    @Test func bagIsSortedBySortOrder() throws {
        let bag = try #require(try json()["bag"] as? [[String: Any]])
        #expect(bag.map { $0["name"] as? String } == ["8 iron", "9 iron"])
        #expect(Set(bag[0].keys) == ["id", "name", "sortOrder", "isInBag"])
        #expect(bag[0]["isInBag"] as? Bool == false)
    }

    @Test func planShape() throws {
        let plans = try #require(try json()["plans"] as? [[String: Any]])
        let plan = try #require(plans.first)
        #expect(
            Set(plan.keys) == ["id", "name", "mode", "isOrderMandatory", "isStrictCount", "createdAt", "blocks"])
        #expect(plan["mode"] as? String == "rangeCounterWithClips")
        #expect(plan["isStrictCount"] as? Bool == true)
        let blocks = try #require(plan["blocks"] as? [[String: Any]])
        #expect(blocks.map { $0["clubName"] as? String } == ["8 iron", "9 iron"])
        #expect(Set(blocks[0].keys) == ["id", "order", "clubName", "targetReps", "note"])
        #expect(Set(blocks[1].keys) == ["id", "order", "clubName", "targetReps"])
    }

    @Test func onlyFinishedSessionsAreExported() throws {
        let sessions = try #require(try json()["sessions"] as? [[String: Any]])
        #expect(sessions.count == 1)
        let session = try #require(sessions.first)
        #expect(session["status"] as? String == "finished")
        #expect(session["cameraAngle"] as? String == "downTheLine")
        #expect(session["planName"] as? String == "Wedge day")
        #expect(session["endedAt"] as? String == "2026-09-21T15:13:20.250Z")
        #expect(
            Set(session.keys) == [
                "id", "planId", "planName", "mode", "status", "startedAt", "endedAt", "cameraAngle", "blocks",
            ])
    }

    @Test func blockResultsAndShots() throws {
        let sessions = try #require(try json()["sessions"] as? [[String: Any]])
        let blocks = try #require(sessions.first?["blocks"] as? [[String: Any]])
        #expect(blocks.map { $0["order"] as? Int } == [0, 1])
        let first = blocks[0]
        #expect(
            Set(first.keys) == [
                "id", "order", "planBlockId", "clubName", "targetReps", "tags", "repsCounted", "repsManualAdjust",
                "shots",
            ])
        #expect(first["targetReps"] as? Int == 40)
        #expect(first["repsManualAdjust"] as? Int == 1)
        let shots = try #require(first["shots"] as? [[String: Any]])
        #expect(shots.map { $0["detectedBy"] as? String } == ["camera", "manual"])
        #expect(shots[0]["timestamp"] as? String == "2026-09-21T14:13:30.250Z")
        #expect(shots[0]["tempoRatio"] as? Double == 3.1)
        #expect(Set(shots[1].keys) == ["id", "timestamp", "detectedBy", "clubName", "tags", "isFavourite"])
    }

    @Test func clipIsReferencedByFileNameOnly() throws {
        let sessions = try #require(try json()["sessions"] as? [[String: Any]])
        let blocks = try #require(sessions.first?["blocks"] as? [[String: Any]])
        let shots = try #require(blocks.first?["shots"] as? [[String: Any]])
        let id = try #require(shots[0]["id"] as? String)
        #expect(shots[0]["clipFileName"] as? String == "\(id).mov")
    }

    @Test func freeSessionHasNoPlanKeys() throws {
        let session = PracticeSession(plan: nil, mode: .putting, cameraAngle: .none, startedAt: t0)
        session.status = .finished
        context.insert(session)
        session.blockResults = [BlockResult(clubName: "Putter", order: 0)]
        try context.save()
        let data = try ExportCoding.encode(try RepsExport.document(from: context, exportedAt: t0))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let exported = try #require((root["sessions"] as? [[String: Any]])?.first)
        #expect(exported["planId"] == nil)
        #expect(exported["planName"] == nil)
        #expect(exported["cameraAngle"] as? String == "none")
        let block = try #require((exported["blocks"] as? [[String: Any]])?.first)
        #expect(block["planBlockId"] == nil)
        #expect(block["targetReps"] == nil)
    }

    @Test func roundTripsAndIsDeterministic() throws {
        try seed()
        let document = try RepsExport.document(from: context, exportedAt: t0)
        let data = try ExportCoding.encode(document)
        #expect(try ExportCoding.decode(data) == document)
        #expect(try ExportCoding.encode(document) == data)
    }

    @Test(arguments: [
        ("abc.mov", "abc.mov"),
        ("clips/s1/abc.mov", "abc.mov"),
        ("/var/mobile/Documents/clips/s1/abc.mov", "abc.mov"),
        ("", ""),
    ])
    func bareFileName(path: String, expected: String) {
        #expect(RepsExport.bareFileName(path) == expected)
    }
}
