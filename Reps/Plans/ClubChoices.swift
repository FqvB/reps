import Foundation

// Names for the block editor's club picker (F19).
nonisolated enum ClubChoices {
    // Bag order, blanks and duplicates dropped; a current club that isn't in the bag goes last.
    static func names(bag: [String], current: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for name in bag + [current] {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }
}
