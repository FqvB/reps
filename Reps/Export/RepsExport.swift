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
            bag: clubs.sorted { ($0.sortOrder, $0.name, $0.id.uuidString) < ($1.sortOrder, $1.name, $1.id.uuidString) }
                .map(club),
            plans: plans.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }.map(plan),
            sessions: sessions.filter { $0.status == .finished }
                .sorted { ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString) }
                .map(session)
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
            isStrictCount: session.isStrictCount,
            isOrderMandatory: session.isOrderMandatory,
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
    // Whole-second ISO 8601 UTC ("...ssZ"); milliseconds are spliced in
    // ourselves. Date.ISO8601FormatStyle's own fractional-seconds mode goes
    // through a float that truncates (…20.123 -> ".122Z"), so we never use it.
    private static let wholeSecondStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: false)

    static func encode(_ document: ExportDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(encodeDate(date))
        }
        return try encoder.encode(document)
    }

    static func decode(_ data: Data) throws -> ExportDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            return try decodeDate(string)
        }
        return try decoder.decode(ExportDocument.self, from: data)
    }

    static func encodeDate(_ date: Date) -> String {
        let totalMs = Int64((date.timeIntervalSince1970 * 1000).rounded())
        var seconds = totalMs / 1000
        var remainderMs = totalMs % 1000
        if remainderMs < 0 {
            remainderMs += 1000
            seconds -= 1
        }
        let whole = Date(timeIntervalSince1970: Double(seconds)).formatted(wholeSecondStyle)
        return "\(whole.dropLast()).\(String(format: "%03d", remainderMs))Z"
    }

    static func decodeDate(_ string: String) throws -> Date {
        guard string.hasSuffix("Z"), let dotIndex = string.lastIndex(of: ".") else {
            throw invalidDate(string)
        }
        let secondsPart = string[..<dotIndex]
        let msPart = string[string.index(after: dotIndex)..<string.index(before: string.endIndex)]
        guard msPart.count == 3, let ms = Int(msPart) else {
            throw invalidDate(string)
        }
        let whole = try wholeSecondStyle.parse(String(secondsPart) + "Z")
        let exact = whole.timeIntervalSince1970 + Double(ms) / 1000
        return Date(timeIntervalSince1970: (exact * 1000).rounded() / 1000)
    }

    private static func invalidDate(_ string: String) -> DecodingError {
        DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid ISO 8601 date: \(string)"))
    }
}
