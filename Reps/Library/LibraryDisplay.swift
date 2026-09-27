import Foundation

nonisolated struct LibrarySessionOption: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let startedAt: Date
}

// Grid order, filter choices and tile copy for the library (Figma 04, §5.3b).
enum LibraryDisplay {
    // Filtered, newest first; `hidden` are clips waiting out a delete undo.
    static func visible(
        _ clips: [LibraryClip], filter: LibraryFilter, hidden: Set<UUID> = [], calendar: Calendar = .current,
        locale: Locale = .current
    ) -> [LibraryClip] {
        clips
            .filter { !hidden.contains($0.id) && filter.matches($0, calendar: calendar, locale: locale) }
            .sorted { ($0.timestamp, $1.id.uuidString) > ($1.timestamp, $0.id.uuidString) }
    }

    static func countTitle(_ count: Int) -> String {
        "\(count) clip\(count == 1 ? "" : "s")"
    }

    // Bag order first, then clubs no longer in the bag, alphabetically.
    static func clubOptions(_ clips: [LibraryClip], bag: [String]) -> [String] {
        let present = Set(clips.map(\.clubName))
        let inBag = bag.filter { present.contains($0) }
        let rest = present.subtracting(inBag).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        var seen = Set<String>()
        return (inBag + rest).filter { seen.insert($0).inserted }
    }

    // Most used first, ties alphabetical; also the autocomplete list for bulk tagging.
    static func tagOptions(_ clips: [LibraryClip]) -> [String] {
        var counts: [String: Int] = [:]
        for tag in clips.flatMap(\.tags) { counts[tag, default: 0] += 1 }
        return counts.keys.sorted {
            counts[$0]! != counts[$1]!
                ? counts[$0]! > counts[$1]! : $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    static func monthOptions(_ clips: [LibraryClip], calendar: Calendar = .current) -> [LibraryMonth] {
        Set(clips.map { LibraryMonth($0.timestamp, calendar: calendar) }).sorted(by: >)
    }

    static func sessionOptions(_ clips: [LibraryClip]) -> [LibrarySessionOption] {
        var byID: [UUID: LibrarySessionOption] = [:]
        for clip in clips {
            guard let id = clip.sessionID, byID[id] == nil else { continue }
            byID[id] = LibrarySessionOption(
                id: id, title: clip.sessionTitle ?? SessionDisplay.title(planName: nil),
                startedAt: clip.sessionStartedAt ?? clip.timestamp)
        }
        return byID.values.sorted { ($0.startedAt, $1.id.uuidString) > ($1.startedAt, $0.id.uuidString) }
    }

    // "Wedge day · Sep 16"
    static func sessionTitle(_ option: LibrarySessionOption, calendar: Calendar = .current, locale: Locale = .current)
        -> String
    {
        "\(option.title) · \(formatter("MMMd", calendar: calendar, locale: locale).string(from: option.startedAt))"
    }

    // "September" this year, "September 2025" otherwise.
    static func monthTitle(
        _ month: LibraryMonth, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        guard let date = calendar.date(from: DateComponents(year: month.year, month: month.month, day: 1)) else {
            return ""
        }
        let sameYear = LibraryMonth(now, calendar: calendar).year == month.year
        return formatter(sameYear ? "MMMM" : "yMMMM", calendar: calendar, locale: locale).string(from: date)
    }

    static func angleOptionTitle(_ angle: CameraAngle) -> String {
        switch angle {
        case .faceOn: "Face-on"
        case .downTheLine: "Down-the-line"
        case .none: "None"
        }
    }

    // "Tag", "fade", "fade +1"
    static func tagChipTitle(_ tags: Set<String>) -> String {
        let sorted = tags.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard let first = sorted.first else { return "Tag" }  // PLACEHOLDER: filter chip copy
        return sorted.count == 1 ? first : "\(first) +\(sorted.count - 1)"
    }

    // "Gap wedge · face-on"; putting has no angle.
    static func tileTitle(_ clip: LibraryClip) -> String {
        guard let angle = SessionDisplay.angleTitle(clip.angle) else { return clip.clubName }
        return "\(clip.clubName) · \(angle)"
    }

    // "Today 7:42 AM", "Mon 6:10 PM" within the last week, "Sep 9", "Sep 9, 2025".
    static func tileDate(_ date: Date, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current)
        -> String
    {
        let time = formatter("jmm", calendar: calendar, locale: locale).string(from: date)
        if calendar.isDate(date, inSameDayAs: now) { return "Today \(time)" }  // PLACEHOLDER: tile date copy
        let days =
            calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now))
            .day ?? .max
        if (1...6).contains(days) {
            return "\(formatter("EEE", calendar: calendar, locale: locale).string(from: date)) \(time)"
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return formatter(sameYear ? "MMMd" : "yMMMd", calendar: calendar, locale: locale).string(from: date)
    }

    // "3.1"; POSIX formatting so the decimal point doesn't follow the locale (as SummaryDisplay.tempo).
    static func tempo(_ ratio: Double?) -> String? {
        ratio.map { String(format: "%.1f", $0) }
    }

    static func tagLine(_ tags: [String]) -> String? {
        tags.isEmpty ? nil : tags.joined(separator: ", ")
    }

    // Bulk ★: favourite all unless every selected clip already is one.
    static func favouriteTarget(_ selected: [LibraryClip]) -> Bool {
        !selected.allSatisfy(\.isFavourite)
    }

    // "Favourited 3 clips", "Deleted 1 clip", …
    static func undoMessage(_ verb: String, count: Int) -> String {
        "\(verb) \(countTitle(count))"  // PLACEHOLDER: undo toast copy
    }

    private static func formatter(_ template: String, calendar: Calendar, locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }
}
