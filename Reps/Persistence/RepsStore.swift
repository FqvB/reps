import SwiftData

enum RepsStore {
    // Empty until #4 adds the @Model types.
    static let models: [any PersistentModel.Type] = []

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
