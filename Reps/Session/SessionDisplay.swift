import Foundation

// One block as the session screen shows it; built from a BlockResult by the view.
nonisolated struct BlockSnapshot: Equatable, Sendable {
    var order: Int
    var clubName: String
    var note: String?
    var done: Int
    var target: Int?
}

nonisolated enum StripChipState: Equatable, Sendable {
    case active
    case complete
    case pending
}

nonisolated struct StripChip: Identifiable, Equatable, Sendable {
    // The block's `order`; unique within a session.
    var id: Int
    var title: String
    var detail: String
    var state: StripChipState
    var isSelectable: Bool
}

nonisolated struct NextBlockPrompt: Equatable, Sendable {
    var title: String
    var message: String
}

// Copy and chip states for the session screen (Figma 03, 05, 14).
enum SessionDisplay {
    // §5.3c: the screen dims after 30 s without a touch.
    static let dimDelay: Duration = .seconds(30)

    static func title(planName: String?) -> String {
        planName ?? "Free session"
    }

    // "Range + clips · face-on"; putting shows "Putting counter" without an angle (Figma 05).
    static func subtitle(mode: PracticeMode, angle: CameraAngle) -> String {
        if mode == .putting { return "Putting counter" }
        guard let angle = angleTitle(angle) else { return mode.title }
        return "\(mode.title) · \(angle)"
    }

    static func angleTitle(_ angle: CameraAngle) -> String? {
        switch angle {
        case .faceOn: "face-on"
        case .downTheLine: "down-the-line"
        case .none: nil
        }
    }

    // Putting blocks share one club, so the strip names them by note ("6 ft", Figma 05).
    static func blockTitle(clubName: String, note: String?, mode: PracticeMode) -> String {
        guard mode == .putting, let note = trimmed(note) else { return clubName }
        return note
    }

    // Line under the big count: "of 30", putting adds the note ("of 30 · 6 ft").
    static func countDetail(done: Int, target: Int?, note: String?, mode: PracticeMode) -> String {
        guard let target else {
            let noun = mode == .putting ? "putt" : "shot"
            return done == 1 ? noun : "\(noun)s"  // PLACEHOLDER: free-session label under the count
        }
        guard mode == .putting, let note = trimmed(note) else { return "of \(target)" }
        return "of \(target) · \(note)"
    }

    static func stripChips(
        _ blocks: [BlockSnapshot], mode: PracticeMode, activeOrder: Int?, canSelect: Bool, isStrict: Bool
    ) -> [StripChip] {
        blocks.map { block in
            let isComplete = Completion.isComplete(
                BlockTally(counted: block.done, manualAdjust: 0, target: block.target))
            let state: StripChipState =
                if block.order == activeOrder {
                    .active
                } else if isComplete {
                    .complete
                } else {
                    .pending
                }
            // Mirrors SessionController.select: no jumps when order is locked or onto a finished strict block.
            let isSelectable = canSelect && state != .active && !(isStrict && isComplete)
            return StripChip(
                id: block.order,
                title: blockTitle(clubName: block.clubName, note: block.note, mode: mode),
                detail: block.target.map { "\(block.done)/\($0)" } ?? "\(block.done)",
                state: state,
                isSelectable: isSelectable
            )
        }
    }

    // F28: Next block before the target asks first (Figma 14); nil means advance straight away.
    static func nextBlockPrompt(clubName: String, done: Int, target: Int?, canComeBack: Bool) -> NextBlockPrompt? {
        guard let target, target > 0, done < target else { return nil }
        let percent = done * 100 / target
        var message = "\(clubName) will stay at \(percent)% for this session."
        if canComeBack { message += " You can come back to it from the block strip." }
        return NextBlockPrompt(title: "Move on at \(done) of \(target)?", message: message)
    }

    // Session clock in the nav: "12:40", "1:02:03".
    static func elapsed(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let secs = total % 60
        let mmss = "\(minutes < 10 && hours > 0 ? "0" : "")\(minutes):\(secs < 10 ? "0" : "")\(secs)"
        return hours > 0 ? "\(hours):\(mmss)" : mmss
    }

    // Tag chips: active tags first, then up to `limit` recent ones (newest first), trimmed and deduped.
    static func tagChoices(active: [String], recent: [String], limit: Int = 8) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in active {
            guard let tag = trimmed(tag), seen.insert(tag).inserted else { continue }
            result.append(tag)
        }
        var added = 0
        for tag in recent where added < limit {
            guard let tag = trimmed(tag), seen.insert(tag).inserted else { continue }
            result.append(tag)
            added += 1
        }
        return result
    }

    // Tapping a tag chip turns it on or off (F16).
    static func toggling(_ tag: String, in active: [String]) -> [String] {
        active.contains(tag) ? active.filter { $0 != tag } : active + [tag]
    }

    // "+ tag": nil when the name is blank or already active.
    static func adding(_ raw: String, to active: [String]) -> [String]? {
        guard let tag = trimmed(raw), !active.contains(tag) else { return nil }
        return active + [tag]
    }

    // Launch "resume?" alert body: "Wedge day · 42 shots so far."
    static func resumeMessage(title: String, done: Int, mode: PracticeMode) -> String {
        "\(title) · \(PlanSummary.reps(done, mode: mode)) so far."  // PLACEHOLDER: resume prompt copy
    }

    private static func trimmed(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
