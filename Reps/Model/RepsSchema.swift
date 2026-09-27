import SwiftData

enum RepsSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [BagClub.self, PracticePlan.self, PlanBlock.self, PracticeSession.self, BlockResult.self, ShotRecord.self]
    }
}

enum RepsMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [RepsSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

// The schema the app and store actually run. Bump when RepsSchemaV2 exists.
typealias RepsSchemaCurrent = RepsSchemaV1
