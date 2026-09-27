import SwiftData

enum RepsStore {
    static let models: [any PersistentModel.Type] = RepsSchemaCurrent.models

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: RepsSchemaCurrent.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, migrationPlan: RepsMigrationPlan.self, configurations: [configuration])
    }
}
