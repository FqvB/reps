import Foundation
import SwiftData

// Bag writes for Settings and onboarding (F19); every write saves.
enum BagLibrary {
    enum BagError: Error, Equatable {
        case emptyName
        case duplicateName
    }

    // Bag order, as the pickers show it.
    static func all(in context: ModelContext) throws -> [BagClub] {
        try context.fetch(FetchDescriptor<BagClub>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)]))
    }

    static func club(named name: String, in clubs: [BagClub]) -> BagClub? {
        let key = BagCatalog.key(name)
        return clubs.first { BagCatalog.key($0.name) == key }
    }

    // Onboarding (#5): the common 14 when the bag table is empty. A second run, or a bag the user already has, changes nothing.
    @discardableResult
    static func seedDefaultBag(in context: ModelContext) throws -> Bool {
        guard try all(in: context).isEmpty else { return false }
        for (index, name) in BagCatalog.defaultBag.enumerated() {
            context.insert(BagClub(name: name, sortOrder: index))
        }
        try context.save()
        return true
    }

    // A chip tap. Off keeps the row (spec §5.1); on for a missing name inserts one.
    static func setInBag(_ name: String, _ isInBag: Bool, in context: ModelContext) throws {
        let trimmed = BagCatalog.trimmed(name)
        guard !trimmed.isEmpty else { throw BagError.emptyName }
        var clubs = try all(in: context)
        if let existing = club(named: trimmed, in: clubs) {
            existing.isInBag = isInBag
        } else if isInBag {
            insert(trimmed, into: &clubs, in: context)
        } else {
            return
        }
        renumber(clubs)
        try context.save()
    }

    // "Add a custom club". A hidden row with that name comes back; one already in the bag is a duplicate.
    @discardableResult
    static func addCustom(_ name: String, in context: ModelContext) throws -> BagClub {
        let trimmed = BagCatalog.trimmed(name)
        guard !trimmed.isEmpty else { throw BagError.emptyName }
        var clubs = try all(in: context)
        if let existing = club(named: trimmed, in: clubs) {
            guard !existing.isInBag else { throw BagError.duplicateName }
            existing.isInBag = true
            try context.save()
            return existing
        }
        let made = insert(trimmed, into: &clubs, in: context)
        renumber(clubs)
        try context.save()
        return made
    }

    // Only the bag row changes; plan blocks and shots keep the old name (snapshots, #4).
    static func rename(_ club: BagClub, to name: String, in context: ModelContext) throws {
        let trimmed = BagCatalog.trimmed(name)
        guard !trimmed.isEmpty else { throw BagError.emptyName }
        if let other = self.club(named: trimmed, in: try all(in: context)), other.id != club.id {
            throw BagError.duplicateName
        }
        club.name = trimmed
        try context.save()
    }

    // Plans reference clubs by name, so nothing else changes.
    static func delete(_ club: BagClub, in context: ModelContext) throws {
        let id = club.id
        context.delete(club)
        renumber(try all(in: context).filter { $0.id != id })
        try context.save()
    }

    // Offsets index the in-bag clubs in bag order (BagOrderSheet); hidden rows go after them.
    static func move(fromOffsets source: IndexSet, toOffset destination: Int, in context: ModelContext) throws {
        let clubs = try all(in: context)
        var inBag = clubs.filter(\.isInBag)
        let valid = source.filter { inBag.indices.contains($0) }
        guard !valid.isEmpty else { return }
        let moving = valid.map { inBag[$0] }
        let shift = valid.filter { $0 < destination }.count
        for index in valid.reversed() { inBag.remove(at: index) }
        inBag.insert(contentsOf: moving, at: min(max(destination - shift, 0), inBag.count))
        renumber(inBag + clubs.filter { !$0.isInBag })
        try context.save()
    }

    @discardableResult
    private static func insert(_ name: String, into clubs: inout [BagClub], in context: ModelContext) -> BagClub {
        let club = BagClub(name: name, sortOrder: clubs.count)
        context.insert(club)
        clubs.insert(club, at: BagCatalog.insertionIndex(for: name, in: clubs.map(\.name)))
        return club
    }

    private static func renumber(_ clubs: [BagClub]) {
        for (index, club) in clubs.enumerated() where club.sortOrder != index { club.sortOrder = index }
    }
}
