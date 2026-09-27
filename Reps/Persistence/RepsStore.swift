import Foundation
import SwiftData

enum RepsStore {
    static let models: [any PersistentModel.Type] = RepsSchemaCurrent.models

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: RepsSchemaCurrent.self)
        return try open(schema, ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory))
    }

    // A store at a given file; tests reopen it to simulate a relaunch after a kill.
    static func makeContainer(url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: RepsSchemaCurrent.self)
        return try open(schema, ModelConfiguration(schema: schema, url: url))
    }

    private static func open(_ schema: Schema, _ configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: schema, migrationPlan: RepsMigrationPlan.self, configurations: [configuration])
    }
}
