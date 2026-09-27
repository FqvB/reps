import Foundation

// One block as the log reads it; built from a BlockResult by the view.
nonisolated struct LogBlock: Equatable, Sendable {
    var order: Int
    var clubName: String
    var note: String?
    var tags: [String]
    var counted: Int
    var manualAdjust: Int
    var target: Int?
    var clipCount: Int

    var tally: BlockTally { BlockTally(counted: counted, manualAdjust: manualAdjust, target: target) }
}

// One finished session as the log reads it; built from a PracticeSession by the view.
nonisolated struct LogEntry: Identifiable, Equatable, Sendable {
    var id: UUID
    var planName: String?
    var mode: PracticeMode
    var cameraAngle: CameraAngle
    var startedAt: Date
    var endedAt: Date?
    var blocks: [LogBlock]
}

nonisolated struct LogRow: Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    // "Wed, Sep 16 · 9:14 AM · 48 min"
    var subtitle: String
    // "130 shots · 5 blocks · 12 clips", or the clubs in a free session.
    var detail: String
    // nil in a free session.
    var percent: String?
    var isComplete: Bool
}

nonisolated struct LogSection: Identifiable, Equatable, Sendable {
    // "September 2026"; unique because it includes the year.
    var id: String { title }
    var title: String
    var rows: [LogRow]
}

nonisolated struct LogBlockRow: Identifiable, Equatable, Sendable {
    // The block's `order`.
    var id: Int
    var title: String
    // "45 / 30", or the bare count for a block without a target.
    var detail: String
    var percent: String?
    var isOverTarget: Bool
}

nonisolated struct LogStat: Identifiable, Equatable, Sendable {
    var id: String { label }
    var value: String
    var label: String
}

nonisolated struct LogDetail: Equatable, Sendable {
    // "Wed, Sep 16, 2026 · 9:14 AM"
    var dateLine: String
    // "Range + clips · face-on"
    var modeLine: String
    // "75%", or the shot count in a free session.
    var headline: String
    // "130 of 170 shots", or "shots" in a free session.
    var caption: String
    var rows: [LogBlockRow]
    var stats: [LogStat]
}

// Grouping, sorting and copy for the session log (F8). Not designed in Figma; follows 01 Plans and 12 Summary.
enum SessionLogDisplay {
    // Newest month first, newest session first inside a month.
    static func sections(_ entries: [LogEntry], calendar: Calendar = .current, locale: Locale = .current)
        -> [LogSection]
    {
        let sorted = entries.sorted { ($0.startedAt, $0.id.uuidString) > ($1.startedAt, $1.id.uuidString) }
        let monthFormatter = formatter("yMMMM", calendar: calendar, locale: locale)
        var sections: [LogSection] = []
        var currentMonth: Date?
        for entry in sorted {
            let month = calendar.dateInterval(of: .month, for: entry.startedAt)?.start ?? entry.startedAt
            if month != currentMonth {
                sections.append(LogSection(title: monthFormatter.string(from: month), rows: []))
                currentMonth = month
            }
            sections[sections.count - 1].rows.append(row(entry, calendar: calendar, locale: locale))
        }
        return sections
    }

    static func row(_ entry: LogEntry, calendar: Calendar = .current, locale: Locale = .current) -> LogRow {
        let blocks = shownBlocks(entry)
        let total = blocks.reduce(0) { $0 + $1.tally.done }
        let clips = blocks.reduce(0) { $0 + $1.clipCount }
        var subtitle = [
            formatter("EEEMMMd", calendar: calendar, locale: locale).string(from: entry.startedAt),
            time(entry.startedAt, calendar: calendar, locale: locale),
        ]
        if let duration = duration(from: entry.startedAt, to: entry.endedAt) { subtitle.append(duration) }
        var detail = [PlanSummary.reps(total, mode: entry.mode)]
        if entry.planName == nil {
            detail.append(clubs(blocks).joined(separator: ", "))
        } else {
            detail.append(PlanSummary.blocks(blocks.count))
        }
        if clips > 0 { detail.append(clipCount(clips)) }
        let overall = overall(blocks)
        return LogRow(
            id: entry.id,
            title: SessionDisplay.title(planName: entry.planName),
            subtitle: subtitle.joined(separator: " · "),
            detail: detail.filter { !$0.isEmpty }.joined(separator: " · "),
            percent: overall.map { percent($0.fraction, isComplete: $0.isComplete) },
            isComplete: overall?.isComplete ?? false
        )
    }

    static func detail(_ entry: LogEntry, calendar: Calendar = .current, locale: Locale = .current) -> LogDetail {
        let blocks = shownBlocks(entry)
        let isFree = entry.planName == nil
        let tallies = blocks.map(\.tally)
        let headline: String
        let caption: String
        if let overall = overall(blocks) {
            let targeted = tallies.filter { ($0.target ?? 0) > 0 }
            let done = targeted.reduce(0) { $0 + $1.done }
            let target = targeted.reduce(0) { $0 + ($1.target ?? 0) }
            headline = percent(overall.fraction, isComplete: overall.isComplete)
            caption = "\(done) of \(PlanSummary.reps(target, mode: entry.mode))"
        } else {
            let total = tallies.reduce(0) { $0 + $1.done }
            headline = "\(total)"
            caption = SessionDisplay.countDetail(done: total, target: nil, note: nil, mode: entry.mode)
        }
        let dateLine = [
            formatter("yMMMEd", calendar: calendar, locale: locale).string(from: entry.startedAt),
            time(entry.startedAt, calendar: calendar, locale: locale),
        ]
        return LogDetail(
            dateLine: dateLine.joined(separator: " · "),
            modeLine: SessionDisplay.subtitle(mode: entry.mode, angle: entry.cameraAngle),
            headline: headline,
            caption: caption,
            rows: blocks.map { blockRow($0, mode: entry.mode, isFree: isFree) },
            stats: [
                LogStat(value: duration(from: entry.startedAt, to: entry.endedAt) ?? "–", label: "duration"),
                LogStat(value: "\(blocks.reduce(0) { $0 + $1.clipCount })", label: "clips saved"),
                // Net +1/−1 per block, as on the summary (#11).
                LogStat(value: "\(blocks.reduce(0) { $0 + abs($1.manualAdjust) })", label: "manual fixes"),
            ]
        )
    }

    static func blockRow(_ block: LogBlock, mode: PracticeMode, isFree: Bool) -> LogBlockRow {
        var title = SessionDisplay.blockTitle(clubName: block.clubName, note: block.note, mode: mode)
        // Free sessions split blocks by tag set, so the tags tell same-club rows apart.
        if isFree && !block.tags.isEmpty { title += " · " + block.tags.joined(separator: ", ") }
        let tally = block.tally
        guard let completion = Completion.block(tally), let target = tally.target else {
            return LogBlockRow(
                id: block.order, title: title, detail: "\(tally.done)", percent: nil, isOverTarget: false)
        }
        return LogBlockRow(
            id: block.order,
            title: title,
            detail: "\(tally.done) / \(target)",
            percent: percent(completion, isComplete: Completion.isComplete(tally)),
            isOverTarget: tally.done > target
        )
    }

    // Rounded, but never "100%" before the target is reached (same rule as the summary, #11).
    static func percent(_ fraction: Double, isComplete: Bool) -> String {
        let value = Int((fraction * 100).rounded())
        return "\(isComplete ? value : min(value, 99))%"
    }

    // "48 min", "1 h 12 min", "2 h"; nil without an end.
    static func duration(from start: Date, to end: Date?) -> String? {
        guard let end else { return nil }
        let minutes = max(0, Int(end.timeIntervalSince(start))) / 60
        if minutes < 1 { return "under 1 min" }  // PLACEHOLDER: sub-minute duration copy
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }

    // Planned sessions keep skipped blocks (0 / 30); free sessions hide unused ones, as finish() does.
    static func shownBlocks(_ entry: LogEntry) -> [LogBlock] {
        let sorted = entry.blocks.sorted { $0.order < $1.order }
        guard entry.planName == nil else { return sorted }
        return sorted.filter { $0.counted != 0 || $0.manualAdjust != 0 }
    }

    // Session completion from Completion.session; nil when no block has a target.
    private static func overall(_ blocks: [LogBlock]) -> (fraction: Double, isComplete: Bool)? {
        let tallies = blocks.map(\.tally)
        guard let fraction = Completion.session(tallies) else { return nil }
        let isComplete = tallies.filter { ($0.target ?? 0) > 0 }.allSatisfy(Completion.isComplete)
        return (fraction, isComplete)
    }

    // Distinct clubs in block order: "7 iron, PW".
    private static func clubs(_ blocks: [LogBlock]) -> [String] {
        var seen = Set<String>()
        return blocks.map(\.clubName).filter { seen.insert($0).inserted }
    }

    private static func clipCount(_ count: Int) -> String { "\(count) clip\(count == 1 ? "" : "s")" }

    private static func time(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        formatter("jmm", calendar: calendar, locale: locale).string(from: date)
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
