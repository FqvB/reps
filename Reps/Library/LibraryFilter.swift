import Foundation

// Plain copy of a ShotRecord that has a clip (built by `LibraryClip.init?(_:)` in LibraryEdits.swift).
nonisolated struct LibraryClip: Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let clubName: String
    let tags: [String]
    let isFavourite: Bool
    let tempoRatio: Double?
    let clipFileName: String
    let sessionID: UUID?
    let sessionTitle: String?
    let sessionStartedAt: Date?
    let angle: CameraAngle
}

nonisolated struct LibraryMonth: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    init(_ date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        self.init(year: parts.year ?? 0, month: parts.month ?? 0)
    }

    static func < (lhs: LibraryMonth, rhs: LibraryMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

// Library filters (§5.3b): every set filter must match (AND), and so must every tag and search word.
struct LibraryFilter: Equatable {
    var club: String?
    var angle: CameraAngle?
    var month: LibraryMonth?
    var sessionID: UUID?
    var tags: Set<String> = []
    var favouritesOnly = false
    var searchText = ""

    // The chips only; search has its own empty state.
    var hasChipFilters: Bool {
        club != nil || angle != nil || month != nil || sessionID != nil || !tags.isEmpty || favouritesOnly
    }

    func matches(_ clip: LibraryClip, calendar: Calendar = .current, locale: Locale = .current) -> Bool {
        if let club, clip.clubName != club { return false }
        if let angle, clip.angle != angle { return false }
        if let month, LibraryMonth(clip.timestamp, calendar: calendar) != month { return false }
        if let sessionID, clip.sessionID != sessionID { return false }
        if !tags.isSubset(of: clip.tags) { return false }
        if favouritesOnly, !clip.isFavourite { return false }
        return matchesSearch(clip, calendar: calendar, locale: locale)
    }

    // Each word must appear in the club, angle, a tag, the session title, or the month/weekday name.
    private func matchesSearch(_ clip: LibraryClip, calendar: Calendar, locale: Locale) -> Bool {
        let words = searchText.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return true }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateFormat = "MMMM EEEE"
        var fields = [clip.clubName, formatter.string(from: clip.timestamp)] + clip.tags
        if let angle = SessionDisplay.angleTitle(clip.angle) { fields.append(angle) }
        if let title = clip.sessionTitle { fields.append(title) }
        return words.allSatisfy { word in fields.contains { $0.localizedStandardContains(word) } }
    }
}
