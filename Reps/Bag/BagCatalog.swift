import Foundation

// Standard clubs for the bag grid (Figma 08) and the default bag (F19).
nonisolated enum BagCatalog {
    nonisolated struct Group: Identifiable, Sendable {
        let title: String
        let clubs: [String]
        var id: String { title }
    }

    static let groups: [Group] = [
        Group(title: "Woods", clubs: ["Driver", "3 wood", "5 wood", "7 wood"]),
        Group(title: "Hybrids", clubs: ["3 hybrid", "4 hybrid", "5 hybrid"]),
        Group(title: "Irons", clubs: ["2 iron", "3 iron", "4 iron", "5 iron", "6 iron", "7 iron", "8 iron", "9 iron"]),
        Group(title: "Wedges", clubs: ["PW", "GW", "SW", "LW"]),
        Group(title: "Putter", clubs: ["Putter"]),
    ]

    static let allClubs: [String] = groups.flatMap(\.clubs)

    // The common 14 (Figma 08 selection); onboarding (#5) seeds it.
    static let defaultBag: [String] = [
        "Driver", "3 wood", "5 wood", "4 hybrid", "5 iron", "6 iron", "7 iron", "8 iron", "9 iron", "PW", "GW", "SW",
        "LW", "Putter",
    ]

    static func trimmed(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Bag names match case-insensitively after trimming.
    static func key(_ name: String) -> String {
        trimmed(name).lowercased()
    }

    static func catalogIndex(of name: String) -> Int? {
        let target = key(name)
        return allClubs.firstIndex { key($0) == target }
    }

    static func isStandard(_ name: String) -> Bool {
        catalogIndex(of: name) != nil
    }

    // Where a new club goes in bag order: a standard club before the first later standard club, custom ones last.
    static func insertionIndex(for name: String, in names: [String]) -> Int {
        guard let index = catalogIndex(of: name) else { return names.count }
        return names.firstIndex { (catalogIndex(of: $0) ?? -1) > index } ?? names.count
    }
}
