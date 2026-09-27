import Foundation

// JSON export shape v1. Property names are the JSON keys; renaming one is a format change.
nonisolated struct ExportDocument: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    var formatVersion: Int
    var exportedAt: Date
    var bag: [ExportClub]
    var plans: [ExportPlan]
    var sessions: [ExportSession]
}

nonisolated struct ExportClub: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var sortOrder: Int
    var isInBag: Bool
}

nonisolated struct ExportPlan: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var mode: PracticeMode
    var isOrderMandatory: Bool
    var isStrictCount: Bool
    var createdAt: Date
    var blocks: [ExportPlanBlock]
}

nonisolated struct ExportPlanBlock: Codable, Equatable, Sendable {
    var id: UUID
    var order: Int
    var clubName: String
    var targetReps: Int
    var note: String?
}

nonisolated struct ExportSession: Codable, Equatable, Sendable {
    var id: UUID
    var planId: UUID?
    var planName: String?
    var mode: PracticeMode
    var status: SessionStatus
    var startedAt: Date
    var endedAt: Date?
    var cameraAngle: CameraAngle
    var isStrictCount: Bool
    var isOrderMandatory: Bool
    var blocks: [ExportBlockResult]
}

nonisolated struct ExportBlockResult: Codable, Equatable, Sendable {
    var id: UUID
    var order: Int
    var planBlockId: UUID?
    var clubName: String
    var targetReps: Int?
    var tags: [String]
    var repsCounted: Int
    var repsManualAdjust: Int
    var shots: [ExportShot]
}

nonisolated struct ExportShot: Codable, Equatable, Sendable {
    var id: UUID
    var timestamp: Date
    var detectedBy: DetectionSource
    var clubName: String
    var tags: [String]
    var isFavourite: Bool
    var tempoRatio: Double?
    var clipFileName: String?
}
