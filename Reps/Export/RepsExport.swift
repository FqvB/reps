import Foundation
import SwiftData

enum RepsExport {
    // Finished sessions only; active ones are still being written (ADR 0006).
    static func document(
        clubs: [BagClub],
        plans: [PracticePlan],
        sessions: [PracticeSession],
        exportedAt: Date
    ) -> ExportDocument {
        ExportDocument(
            formatVersion: ExportDocument.currentFormatVersion,
            exportedAt: exportedAt,
            bag: clubs.sorted { $0.sortOrder < $1.sortOrder }.map(club),
            plans: plans.sorted { $0.createdAt < $1.createdAt }.map(plan),
            sessions: sessions.filter { $0.status == .finished }.sorted { $0.startedAt < $1.startedAt }.map(session)
        )
    }

    static func document(from context: ModelContext, exportedAt: Date) throws -> ExportDocument {
        document(
            clubs: try context.fetch(FetchDescriptor<BagClub>()),
            plans: try context.fetch(FetchDescriptor<PracticePlan>()),
            sessions: try context.fetch(FetchDescriptor<PracticeSession>()),
            exportedAt: exportedAt
        )
    }

    private static func club(_ club: BagClub) -> ExportClub {
        ExportClub(id: club.id, name: club.name, sortOrder: club.sortOrder, isInBag: club.isInBag)
    }

    private static func plan(_ plan: PracticePlan) -> ExportPlan {
        ExportPlan(
            id: plan.id,
            name: plan.name,
            mode: plan.mode,
            isOrderMandatory: plan.isOrderMandatory,
            isStrictCount: plan.isStrictCount,
            createdAt: plan.createdAt,
            blocks: plan.sortedBlocks.map {
                ExportPlanBlock(
                    id: $0.id, order: $0.order, clubName: $0.clubName, targetReps: $0.targetReps, note: $0.note)
            }
        )
    }

    private static func session(_ session: PracticeSession) -> ExportSession {
        ExportSession(
            id: session.id,
            planId: session.plan?.id,
            planName: session.planName,
            mode: session.mode,
            status: session.status,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            cameraAngle: session.cameraAngle,
            blocks: session.sortedBlockResults.map(blockResult)
        )
    }

    private static func blockResult(_ result: BlockResult) -> ExportBlockResult {
        ExportBlockResult(
            id: result.id,
            order: result.order,
            planBlockId: result.block?.id,
            clubName: result.clubName,
            targetReps: result.targetReps,
            tags: result.tags,
            repsCounted: result.repsCounted,
            repsManualAdjust: result.repsManualAdjust,
            shots: result.sortedShots.map(shot)
        )
    }

    private static func shot(_ shot: ShotRecord) -> ExportShot {
        ExportShot(
            id: shot.id,
            timestamp: shot.timestamp,
            detectedBy: shot.detectedBy,
            clubName: shot.clubName,
            tags: shot.tags,
            isFavourite: shot.isFavourite,
            tempoRatio: shot.tempoRatio,
            clipFileName: shot.clipFileName.map(bareFileName)
        )
    }

    // Never export a directory or absolute path, only the file name.
    nonisolated static func bareFileName(_ path: String) -> String {
        String(path.split(separator: "/", omittingEmptySubsequences: true).last ?? "")
    }
}

nonisolated enum ExportCoding {
    private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static func encode(_ document: ExportDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(dateStyle))
        }
        return try encoder.encode(document)
    }

    static func decode(_ data: Data) throws -> ExportDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            return try dateStyle.parse(string)
        }
        return try decoder.decode(ExportDocument.self, from: data)
    }
}
