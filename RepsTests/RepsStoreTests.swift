import SwiftData
import Testing

@testable import Reps

@MainActor
struct RepsStoreTests {
    @Test func inMemoryContainerOpens() throws {
        let container = try RepsStore.makeContainer(inMemory: true)
        #expect(container.configurations.first?.isStoredInMemoryOnly == true)
    }
}
