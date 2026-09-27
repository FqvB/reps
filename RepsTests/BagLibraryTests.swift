import Foundation
import SwiftData
import Testing

@testable import Reps

@MainActor
struct BagLibraryTests {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        container = try RepsStore.makeContainer(inMemory: true)
        context = container.mainContext
    }

    private func seed(_ names: [String]) throws {
        for (index, name) in names.enumerated() { context.insert(BagClub(name: name, sortOrder: index)) }
        try context.save()
    }

    private func names() throws -> [String] {
        try BagLibrary.all(in: context).map(\.name)
    }

    private func order() throws -> [Int] {
        try BagLibrary.all(in: context).map(\.sortOrder)
    }

    @Test func setInBagInsertsStandardClubAtCatalogPosition() throws {
        try seed(["Driver", "7 iron", "Putter"])
        try BagLibrary.setInBag("5 wood", true, in: context)
        #expect(try names() == ["Driver", "5 wood", "7 iron", "Putter"])
        #expect(try order() == [0, 1, 2, 3])
    }

    @Test func setInBagOffKeepsRow() throws {
        try seed(["Driver", "7 iron"])
        try BagLibrary.setInBag("7 iron", false, in: context)
        let all = try BagLibrary.all(in: context)
        #expect(all.count == 2)
        #expect(BagLibrary.club(named: "7 iron", in: all)?.isInBag == false)
    }

    @Test func setInBagOnRestoresHiddenRowCaseInsensitively() throws {
        try seed(["Driver", "7 iron"])
        try BagLibrary.setInBag("7 iron", false, in: context)
        try BagLibrary.setInBag("7 IRON", true, in: context)
        let all = try BagLibrary.all(in: context)
        #expect(all.count == 2)
        let club = BagLibrary.club(named: "7 iron", in: all)
        #expect(club?.isInBag == true)
        #expect(club?.name == "7 iron")
    }

    @Test func setInBagOffForMissingNameDoesNothing() throws {
        try seed(["Driver", "7 iron"])
        try BagLibrary.setInBag("Putter", false, in: context)
        #expect(try BagLibrary.all(in: context).count == 2)
    }

    @Test func setInBagRejectsBlankName() throws {
        try seed(["Driver"])
        #expect(throws: BagLibrary.BagError.emptyName) {
            try BagLibrary.setInBag("   ", true, in: context)
        }
    }

    @Test func addCustomAppendsTrimmed() throws {
        try seed(["Driver", "Putter"])
        try BagLibrary.addCustom("  Chipper ", in: context)
        #expect(try names() == ["Driver", "Putter", "Chipper"])
    }

    @Test func addCustomRejectsDuplicateInBag() throws {
        try seed(["Driver"])
        #expect(throws: BagLibrary.BagError.duplicateName) {
            try BagLibrary.addCustom("driver", in: context)
        }
    }

    @Test func addCustomRestoresHiddenRow() throws {
        context.insert(BagClub(name: "Chipper", sortOrder: 0, isInBag: false))
        try context.save()
        try BagLibrary.addCustom("chipper", in: context)
        let all = try BagLibrary.all(in: context)
        #expect(all.count == 1)
        #expect(all[0].isInBag == true)
    }

    @Test func addCustomStandardNameGoesToCatalogPosition() throws {
        try seed(["Driver", "Putter"])
        try BagLibrary.addCustom("PW", in: context)
        #expect(try names() == ["Driver", "PW", "Putter"])
    }

    @Test func renameKeepsPlanSnapshots() throws {
        try seed(["Chipper"])
        let plan = PracticePlan(name: "Short game", mode: .rangeCounter)
        context.insert(plan)
        plan.blocks = [PlanBlock(clubName: "Chipper", targetReps: 10, note: nil, order: 0)]
        try context.save()

        let club = BagLibrary.club(named: "Chipper", in: try BagLibrary.all(in: context))!
        try BagLibrary.rename(club, to: "Bump and run", in: context)

        #expect(try names() == ["Bump and run"])
        #expect(plan.blocks[0].clubName == "Chipper")
    }

    @Test func renameRejectsDuplicateButAllowsCaseChange() throws {
        try seed(["Driver", "Chipper"])
        let chipper = BagLibrary.club(named: "Chipper", in: try BagLibrary.all(in: context))!
        #expect(throws: BagLibrary.BagError.duplicateName) {
            try BagLibrary.rename(chipper, to: "driver", in: context)
        }
        try BagLibrary.rename(chipper, to: "CHIPPER", in: context)
        #expect(chipper.name == "CHIPPER")
    }

    @Test func deleteRenumbers() throws {
        try seed(["Driver", "7 iron", "Putter"])
        let club = BagLibrary.club(named: "7 iron", in: try BagLibrary.all(in: context))!
        try BagLibrary.delete(club, in: context)
        #expect(try names() == ["Driver", "Putter"])
        #expect(try order() == [0, 1])
    }

    @Test func moveReordersInBagAndPutsHiddenLast() throws {
        try seed(["Driver", "3 wood", "7 iron", "Putter"])
        try BagLibrary.setInBag("3 wood", false, in: context)
        try BagLibrary.move(fromOffsets: [2], toOffset: 0, in: context)
        #expect(try names() == ["Putter", "Driver", "7 iron", "3 wood"])
        #expect(try order() == [0, 1, 2, 3])
    }

    @Test func moveIgnoresOutOfRangeOffsets() throws {
        try seed(["Driver", "3 wood", "7 iron", "Putter"])
        let before = try names()
        try BagLibrary.move(fromOffsets: [9], toOffset: 0, in: context)
        #expect(try names() == before)
    }
}
