import Foundation
import SwiftData
import Testing

@testable import Reps

@MainActor
struct LibraryEditsTests {
    private let container: ModelContainer
    private let context: ModelContext
    private let session: PracticeSession
    private let block: BlockResult

    init() throws {
        container = try RepsStore.makeContainer(inMemory: true)
        context = container.mainContext
        session = PracticeSession(plan: nil, mode: .rangeCounterWithClips, cameraAngle: .downTheLine)
        context.insert(session)
        block = BlockResult(clubName: "GW", order: 0)
        context.insert(block)
        block.session = session
        try context.save()
    }

    private func shot(_ club: String = "GW", tags: [String] = [], clip: Bool = true) throws -> ShotRecord {
        let shot = ShotRecord(detectedBy: .camera, clubName: club, tags: tags)
        if clip { shot.clipFileName = "\(shot.id.uuidString).mov" }
        context.insert(shot)
        shot.blockResult = block
        try context.save()
        return shot
    }

    private func allShots() throws -> [ShotRecord] {
        try context.fetch(FetchDescriptor<ShotRecord>())
    }

    @Test func clipCopiesSessionFields() throws {
        let withClip = try shot(tags: ["fade"])
        let clip = try #require(LibraryClip(withClip))
        #expect(clip.sessionID == session.id)
        #expect(clip.sessionTitle == "Free session")
        #expect(clip.angle == .downTheLine)
        #expect(clip.tags == ["fade"])
        #expect(LibraryClip(try shot(clip: false)) == nil)
    }

    @Test func setClubAndUndo() throws {
        let a = try shot("GW")
        let b = try shot("PW")
        let snapshots = try LibraryEdits.setClub("  SW ", on: [a, b], in: context)
        #expect([a.clubName, b.clubName] == ["SW", "SW"])
        try LibraryEdits.restore(snapshots, in: context)
        #expect([a.clubName, b.clubName] == ["GW", "PW"])
        #expect(try LibraryEdits.setClub("  ", on: [a], in: context).isEmpty)
        #expect(a.clubName == "GW")
    }

    @Test func addAndRemoveTagWithUndo() throws {
        let a = try shot(tags: ["low"])
        let b = try shot(tags: ["fade"])
        let added = try LibraryEdits.addTag(" fade ", to: [a, b], in: context)
        #expect(a.tags == ["low", "fade"])
        #expect(b.tags == ["fade"])
        let removed = try LibraryEdits.removeTag("low", from: [a, b], in: context)
        #expect(a.tags == ["fade"])
        try LibraryEdits.restore(removed, in: context)
        #expect(a.tags == ["low", "fade"])
        try LibraryEdits.restore(added, in: context)
        #expect(a.tags == ["low"])
        #expect(b.tags == ["fade"])
        #expect(try LibraryEdits.addTag("", to: [a], in: context).isEmpty)
    }

    @Test func favouriteAndUndo() throws {
        let a = try shot()
        a.isFavourite = true
        let b = try shot()
        let snapshots = try LibraryEdits.setFavourite(true, on: [a, b], in: context)
        #expect(a.isFavourite && b.isFavourite)
        try LibraryEdits.restore(snapshots, in: context)
        #expect(a.isFavourite && !b.isFavourite)
    }

    @Test func restoreSkipsDeletedShots() throws {
        let a = try shot("GW")
        let b = try shot("GW")
        let snapshots = try LibraryEdits.setClub("PW", on: [a, b], in: context)
        try LibraryEdits.delete(ids: [a.id], in: context, clipFiles: NoClipFiles())
        try LibraryEdits.restore(snapshots, in: context)
        #expect(try allShots().map(\.clubName) == ["GW"])
    }

    @Test func deleteRemovesRowsThenFiles() throws {
        let a = try shot()
        let b = try shot()
        let keep = try shot()
        let noClip = try shot(clip: false)
        let spy = ClipSpy()
        let deleted = try LibraryEdits.delete(ids: [a.id, b.id, noClip.id, UUID()], in: context, clipFiles: spy)
        #expect(Set(deleted) == [a.id, b.id, noClip.id])
        #expect(try allShots().map(\.id) == [keep.id])
        #expect(block.shots.map(\.id) == [keep.id])
        #expect(
            Set(spy.removedClips) == [
                "\(session.id.uuidString)/\(a.id.uuidString).mov", "\(session.id.uuidString)/\(b.id.uuidString).mov",
            ])
        #expect(spy.removedSessions.isEmpty)
    }

    @Test func deleteNeverPassesAnInvalidClipNameToFileRemoval() throws {
        let bad = try shot()
        bad.clipFileName = "../escape.mov"
        try context.save()
        let spy = ClipSpy()
        try LibraryEdits.delete(ids: [bad.id], in: context, clipFiles: spy)
        #expect(try allShots().isEmpty)
        #expect(spy.removedClips.isEmpty)
    }

    @Test func deleteDoesNotChangeBlockCounts() throws {
        block.repsCounted = 2
        let a = try shot()
        _ = try shot()
        try LibraryEdits.delete(ids: [a.id], in: context, clipFiles: NoClipFiles())
        #expect(block.repsCounted == 2)
    }
}
