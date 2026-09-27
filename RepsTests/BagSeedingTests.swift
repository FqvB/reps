import Foundation
import SwiftData
import Testing

@testable import Reps

@MainActor
struct BagSeedingTests {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        container = try RepsStore.makeContainer(inMemory: true)
        context = container.mainContext
    }

    @Test func seedsTheDefaultBagIntoAnEmptyStore() throws {
        #expect(try BagLibrary.seedDefaultBag(in: context))
        let clubs = try BagLibrary.all(in: context)
        #expect(clubs.map(\.name) == BagCatalog.defaultBag)
        #expect(clubs.map(\.sortOrder) == Array(0..<BagCatalog.defaultBag.count))
        #expect(clubs.allSatisfy { $0.isInBag })
    }

    @Test func secondSeedIsANoOp() throws {
        try BagLibrary.seedDefaultBag(in: context)
        #expect(try BagLibrary.seedDefaultBag(in: context) == false)
        #expect(try BagLibrary.all(in: context).count == BagCatalog.defaultBag.count)
    }

    @Test func existingBagIsLeftAlone() throws {
        context.insert(BagClub(name: "Chipper", sortOrder: 0, isInBag: false))
        try context.save()
        #expect(try BagLibrary.seedDefaultBag(in: context) == false)
        let clubs = try BagLibrary.all(in: context)
        #expect(clubs.map(\.name) == ["Chipper"])
        #expect(clubs[0].isInBag == false)
    }
}
