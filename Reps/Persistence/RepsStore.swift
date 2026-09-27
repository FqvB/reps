import SwiftData

enum RepsStore {
    static let models: [any PersistentModel.Type] = RepsSchemaV1.models

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: RepsSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, migrationPlan: RepsMigrationPlan.self, configurations: [configuration])
    }
}
