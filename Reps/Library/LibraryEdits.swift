import Foundation
import SwiftData

extension LibraryClip {
    // nil for shots without a clip; they aren't in the library.
    init?(_ shot: ShotRecord) {
        guard let clipFileName = shot.clipFileName else { return nil }
        let session = shot.blockResult?.session
        self.init(
            id: shot.id, timestamp: shot.timestamp, clubName: shot.clubName, tags: shot.tags,
            isFavourite: shot.isFavourite, tempoRatio: shot.tempoRatio, clipFileName: clipFileName,
            sessionID: session?.id, sessionTitle: session.map { SessionDisplay.title(planName: $0.planName) },
            sessionStartedAt: session?.startedAt, angle: session?.cameraAngle ?? .none)
    }
}

// The editable fields of one shot before a bulk edit, for Undo.
nonisolated struct ShotSnapshot: Equatable, Sendable {
    let id: UUID
    let clubName: String
    let tags: [String]
    let isFavourite: Bool
}

// A toast's worth of undo (§5.3c): edits restore snapshots; deletes are only hidden until committed.
struct LibraryUndo: Identifiable {
    enum Kind {
        case restore([ShotSnapshot])
        case delete(Set<UUID>)
    }

    let id = UUID()
    let message: String
    let kind: Kind
}

// Bulk library writes (F15). Each saves, and on a failed save rolls the context back and rethrows.
enum LibraryEdits {
    static func setClub(_ club: String, on shots: [ShotRecord], in context: ModelContext) throws -> [ShotSnapshot] {
        let club = club.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !club.isEmpty else { return [] }
        return try edit(shots, in: context) { $0.clubName = club }
    }

    // Trimmed like session tags (SessionDisplay.adding); shots that already have it keep their order.
    static func addTag(_ raw: String, to shots: [ShotRecord], in context: ModelContext) throws -> [ShotSnapshot] {
        let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return [] }
        return try edit(shots, in: context) { shot in
            if !shot.tags.contains(tag) { shot.tags.append(tag) }
        }
    }

    static func removeTag(_ tag: String, from shots: [ShotRecord], in context: ModelContext) throws -> [ShotSnapshot] {
        try edit(shots, in: context) { $0.tags.removeAll { $0 == tag } }
    }

    static func setFavourite(_ value: Bool, on shots: [ShotRecord], in context: ModelContext) throws
        -> [ShotSnapshot]
    {
        try edit(shots, in: context) { $0.isFavourite = value }
    }

    // Shots deleted since the snapshot are skipped.
    static func restore(_ snapshots: [ShotSnapshot], in context: ModelContext) throws {
        let byID = Dictionary(snapshots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ids = Array(byID.keys)
        let shots = try context.fetch(FetchDescriptor<ShotRecord>(predicate: #Predicate { ids.contains($0.id) }))
        try save(context) {
            for shot in shots {
                guard let snapshot = byID[shot.id] else { continue }
                shot.clubName = snapshot.clubName
                shot.tags = snapshot.tags
                shot.isFavourite = snapshot.isFavourite
            }
        }
    }

    // Deletes the shots, saves, then removes their clip files (ADR 0013 order). Returns the ids actually deleted.
    // Shots already gone (e.g. their session was deleted from the log) are skipped.
    @discardableResult
    static func delete(ids: Set<UUID>, in context: ModelContext, clipFiles: any ClipFileRemoving) throws -> [UUID] {
        let wanted = Array(ids)
        let shots = try context.fetch(FetchDescriptor<ShotRecord>(predicate: #Predicate { wanted.contains($0.id) }))
        let files: [(fileName: String, sessionID: UUID)] = shots.compactMap { shot in
            guard let fileName = shot.clipFileName, let sessionID = shot.blockResult?.session?.id else { return nil }
            return (fileName, sessionID)
        }
        let deleted = shots.map(\.id)
        try save(context) {
            for shot in shots {
                shot.blockResult?.shots.removeAll { $0 === shot }
                context.delete(shot)
            }
        }
        for file in files { clipFiles.removeClip(fileName: file.fileName, sessionID: file.sessionID) }
        return deleted
    }

    private static func edit(_ shots: [ShotRecord], in context: ModelContext, _ change: (ShotRecord) -> Void) throws
        -> [ShotSnapshot]
    {
        let snapshots = shots.map {
            ShotSnapshot(id: $0.id, clubName: $0.clubName, tags: $0.tags, isFavourite: $0.isFavourite)
        }
        try save(context) { shots.forEach(change) }
        return snapshots
    }

    private static func save(_ context: ModelContext, _ changes: () -> Void) throws {
        changes()
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
