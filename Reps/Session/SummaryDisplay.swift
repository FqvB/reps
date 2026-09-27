import Foundation

// One block as the summary reads it; built from a BlockResult by the view.
nonisolated struct SummaryBlock: Equatable, Sendable {
    var order: Int
    var clubName: String
    var note: String?
    var tags: [String]
    var counted: Int
    var manualAdjust: Int
    var target: Int?
    var clipCount: Int
    var tempos: [Double]

    var tally: BlockTally { BlockTally(counted: counted, manualAdjust: manualAdjust, target: target) }
}

nonisolated struct SummaryBar: Equatable, Sendable {
    // Accent part of the track, 0...1.
    var fill: Double
    // Over target the track is full and a darker surplus runs from target/done to the end (Figma 12).
    var surplusFrom: Double?
}

nonisolated struct SummaryRow: Identifiable, Equatable, Sendable {
    // The block's `order`.
    var id: Int
    var title: String
    // "45 / 30", or the bare count for a block without a target.
    var detail: String
    var percent: String?
    var isOverTarget: Bool
    var bar: SummaryBar?
}

nonisolated struct SummaryStat: Identifiable, Equatable, Sendable {
    var id: String { label }
    var value: String
    var label: String
}

nonisolated struct SessionSummary: Equatable, Sendable {
    var subtitle: String
    var headline: String
    var caption: String
    var rows: [SummaryRow]
    var stats: [SummaryStat]
}

// Numbers and copy for the session summary (Figma 12, F23).
enum SummaryDisplay {
    static let title = "Session done"
    static let footnote = "Nothing is saved until you tap Done — ended by accident? Just continue."

    static func summary(
        planName: String?, mode: PracticeMode, blocks: [SummaryBlock], elapsed: TimeInterval
    ) -> SessionSummary {
        let isFree = planName == nil
        let sorted = blocks.sorted { $0.order < $1.order }
        // Mirrors SessionController.finish(): unused free-session blocks are dropped on Done.
        let shown = isFree ? sorted.filter { $0.counted != 0 || $0.manualAdjust != 0 } : sorted
        let overall = overall(sorted, mode: mode)
        return SessionSummary(
            subtitle: [SessionDisplay.title(planName: planName), mode.title, duration(elapsed)]
                .joined(separator: " · "),
            headline: overall.headline,
            caption: overall.caption,
            rows: shown.map { row($0, mode: mode, isFree: isFree) },
            stats: stats(sorted)
        )
    }

    // "100%" + "190 of 170 shots · every block complete"; without targets, the shot count.
    static func overall(_ blocks: [SummaryBlock], mode: PracticeMode) -> (headline: String, caption: String) {
        let tallies = blocks.map(\.tally)
        guard let completion = Completion.session(tallies) else {
            let total = tallies.reduce(0) { $0 + $1.done }
            return ("\(total)", SessionDisplay.countDetail(done: total, target: nil, note: nil, mode: mode))
        }
        let targeted = tallies.filter { ($0.target ?? 0) > 0 }
        let done = targeted.reduce(0) { $0 + $1.done }
        let target = targeted.reduce(0) { $0 + ($1.target ?? 0) }
        let short = targeted.filter { !Completion.isComplete($0) }.count
        // PLACEHOLDER: "blocks short" copy
        let status = short == 0 ? "every block complete" : "\(short) block\(short == 1 ? "" : "s") short"
        return (
            percent(completion, isComplete: short == 0),
            "\(done) of \(PlanSummary.reps(target, mode: mode)) · \(status)"
        )
    }

    static func row(_ block: SummaryBlock, mode: PracticeMode, isFree: Bool) -> SummaryRow {
        var title = SessionDisplay.blockTitle(clubName: block.clubName, note: block.note, mode: mode)
        // Free sessions split blocks by tag set, so the tags tell same-club rows apart.
        if isFree && !block.tags.isEmpty { title += " · " + block.tags.joined(separator: ", ") }
        let tally = block.tally
        guard let completion = Completion.block(tally), let target = tally.target else {
            return SummaryRow(
                id: block.order, title: title, detail: "\(tally.done)", percent: nil, isOverTarget: false, bar: nil)
        }
        let isOver = tally.done > target
        return SummaryRow(
            id: block.order,
            title: title,
            detail: "\(tally.done) / \(target)",
            percent: percent(completion, isComplete: Completion.isComplete(tally)),
            isOverTarget: isOver,
            bar: SummaryBar(fill: min(completion, 1), surplusFrom: isOver ? Double(target) / Double(tally.done) : nil)
        )
    }

    // Rounded like Figma (35/30 = "117%"), but never "100%" before the target is reached.
    static func percent(_ fraction: Double, isComplete: Bool) -> String {
        let value = Int((fraction * 100).rounded())
        return "\(isComplete ? value : min(value, 99))%"
    }

    static func stats(_ blocks: [SummaryBlock]) -> [SummaryStat] {
        [
            SummaryStat(value: "\(blocks.reduce(0) { $0 + $1.clipCount })", label: "clips saved"),
            SummaryStat(value: tempo(blocks.flatMap(\.tempos)), label: "avg tempo"),
            // Net +1/−1 per block (spec §5.1 keeps manual adjustments apart from detections).
            SummaryStat(value: "\(blocks.reduce(0) { $0 + abs($1.manualAdjust) })", label: "manual fixes"),
        ]
    }

    // "3.0 : 1"; POSIX formatting so the decimal point doesn't follow the locale.
    static func tempo(_ ratios: [Double]) -> String {
        guard !ratios.isEmpty else { return "–" }  // PLACEHOLDER: no tempo yet (#27) or putting
        return String(format: "%.1f : 1", ratios.reduce(0, +) / Double(ratios.count))
    }

    // "48 min", "1 h 12 min", "2 h".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds)) / 60
        if minutes < 1 { return "under 1 min" }  // PLACEHOLDER: sub-minute duration copy
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}
