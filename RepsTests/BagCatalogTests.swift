import Foundation
import Testing

@testable import Reps

struct BagCatalogTests {
    @Test func defaultBagIsFourteenCatalogClubs() {
        #expect(BagCatalog.defaultBag.count == 14)
        #expect(BagCatalog.defaultBag.allSatisfy(BagCatalog.isStandard))
        #expect(Set(BagCatalog.defaultBag.map(BagCatalog.key)).count == BagCatalog.defaultBag.count)
    }

    @Test func catalogHasUniqueKeys() {
        #expect(Set(BagCatalog.allClubs.map(BagCatalog.key)).count == BagCatalog.allClubs.count)
    }

    @Test func keyTrimsAndIgnoresCase() {
        #expect(BagCatalog.key(" 7 IRON ") == "7 iron")
        #expect(BagCatalog.isStandard("pw"))
        #expect(!BagCatalog.isStandard("Chipper"))
    }

    @Test func insertionIndex() {
        let names = ["Driver", "7 iron", "Putter"]
        #expect(BagCatalog.insertionIndex(for: "5 wood", in: names) == 1)
        #expect(BagCatalog.insertionIndex(for: "LW", in: names) == 2)
        #expect(BagCatalog.insertionIndex(for: "Putter", in: ["Driver", "Chipper"]) == 2)
        #expect(BagCatalog.insertionIndex(for: "Chipper", in: names) == 3)
        #expect(BagCatalog.insertionIndex(for: "5 wood", in: []) == 0)
        #expect(BagCatalog.insertionIndex(for: "3 wood", in: ["Chipper", "Driver"]) == 2)
    }
}
