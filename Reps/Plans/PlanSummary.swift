import Foundation

// Copy for plan cards and block rows.
nonisolated enum PlanSummary {
    static func reps(_ count: Int, mode: PracticeMode) -> String {
        let noun = mode == .putting ? "putt" : "shot"
        return "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    static func blocks(_ count: Int) -> String { "\(count) block\(count == 1 ? "" : "s")" }

    // "5 blocks · 170 shots"
    static func totals(blockCount: Int, totalReps: Int, mode: PracticeMode) -> String {
        "\(blocks(blockCount)) · \(reps(totalReps, mode: mode))"
    }

    // "5 blocks · 170 shots · any order"
    static func subtitle(blockCount: Int, totalReps: Int, mode: PracticeMode, isOrderMandatory: Bool) -> String {
        "\(totals(blockCount: blockCount, totalReps: totalReps, mode: mode)) · \(isOrderMandatory ? "in order" : "any order")"
    }

    // "40 shots · 110 m"
    static func blockDetail(targetReps: Int, note: String?, mode: PracticeMode) -> String {
        let base = reps(targetReps, mode: mode)
        guard let note, !note.isEmpty else { return base }
        return "\(base) · \(note)"
    }

    // "Last done today" / "Last done Mon" (within 6 days) / "Last done Sep 9" / "Last done Sep 9, 2025"
    static func lastDone(_ date: Date?, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        guard let date else { return "Not done yet" }  // PLACEHOLDER: copy for a plan never run
        let days =
            calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day
            ?? 0
        if days <= 0 { return "Last done today" }
        let template: String
        if days <= 6 {
            template = "EEE"
        } else if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            template = "MMMd"
        } else {
            template = "yMMMd"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        return "Last done \(formatter.string(from: date))"
    }
}
