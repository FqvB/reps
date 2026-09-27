import SwiftData
import Testing

@testable import Reps

@MainActor
struct RepsStoreTests {
    @Test func inMemoryContainerOpens() throws {
        let container = try RepsStore.makeContainer(inMemory: true)
        #expect(container.configurations.first?.isStoredInMemoryOnly == true)
    }

    @Test func schemaHasEveryModel() throws {
        let container = try RepsStore.makeContainer(inMemory: true)
        let names = Set(container.schema.entities.map(\.name))
        #expect(names == ["BagClub", "PracticePlan", "PlanBlock", "PracticeSession", "BlockResult", "ShotRecord"])
    }

    @Test func schemaIsVersionOne() {
        #expect(RepsSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(RepsMigrationPlan.schemas.count == 1)
    }
}
