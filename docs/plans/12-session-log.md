# #12 Session log

Goal: a list of finished sessions (newest first, grouped by month) and a detail screen per session with its per-block results. The log opens from the Plans tab, and a finished session can be deleted from it.

Spec: F8 ("Session log: date, plan, per-block reps, duration, clips"), §4 (SessionLog is a peer of PlanEditor and SessionScreen, not a tab), §5.1 (completion, `repsManualAdjust` kept apart). ADRs: 0006 (the log shows `finished` sessions only), 0009 (synced folders, MainActor default), 0013 (no enum-captured `#Predicate`: filter `status` in memory). Q22 (session completion caps per block, lands in #11), Q25 (leaning: "offer delete only from the log").

Figma: **no frame for this screen** (`docs/design.md`: "not designed; follow the Plans list and summary styles"). Style was taken from 01 Plans `1:2` (cards) and 12 Session summary `12:169` (headline card, block rows, stat tiles). New Q31 asks the owner to review the choices below.

**Base: `main` after #11 is merged** (roadmap order #11 → #12). Nothing here uses #11's code: the log calls `Completion.session`/`Completion.block` and gets whatever #11 leaves there (capped per block after Q22). The test numbers were picked so that they hold with or without the Q22 cap. If `Completion`, `SessionDisplay.title/subtitle/blockTitle/countDetail`, `PlanSummary.reps/blocks`, `NoClipFiles`, `ClipSpy` or `PreviewData.container()` differ from what's on `main` today, stop and report.

How this was checked: `SessionLogDisplay.swift` and its tests ran in a scratch SwiftPM package (Swift 6.4, `defaultIsolation(MainActor)`, with the real `ModelEnums`, `Completion`, `PlanSummary`, `SessionDisplay`, `PracticeMode+Title`): **11 tests in 1 suite passed**. All new and changed files in Appendix A/B were type-checked with the whole of `Reps/` on today's `main` (`swiftc -typecheck`, iOS 26.0 simulator target, iPhoneSimulator SDK, `-default-isolation MainActor`, `-DDEBUG`): clean. Both test files were type-checked against that module with Swift Testing: clean. `swift-format lint --strict` with the repo's `.swift-format`: clean. `SessionLogTests` (SwiftData) and the views have **not run**; Xcode hasn't built them. **Copy every file exactly.**

Out of scope: clip lists, thumbnails and playback from the log (#24/#25: `TODO(#24)`), Save to Photos per clip (§5.8, #26: `TODO(#26)`), real clip deletion (#22: `NoClipFiles` until then), per-plan history from a plan card (Q31), editing a past session, export UI.

## Design choices (for the owner to review, Q31)

| Topic | Choice | Why |
|---|---|---|
| Where it lives | A **"Log"** text button at the leading side of the Plans nav bar (Settings is trailing). It **pushes** "Session log" onto the Plans `NavigationStack`, and a row pushes the detail. No third tab. | §4 lists SessionLog as a screen beside PlanEditor and SessionScreen. F8 doesn't ask for a tab, and Figma's tab bar has two (Plans, Library). The log is plan history, so it sits with plans. A push gives a back button for free. |
| List | Plain `List` with **month sections** ("September 2026", footnote medium, secondary, not uppercased), newest first. Each row is a **card like 01 Plans'** `PlanCard`: `card` background, radius 20, 20/16/18 padding, 12 pt gap. | Same visual language as the only list screen that is designed. |
| Row content (F8) | Title: plan name (snapshot, survives plan deletion) or "Free session" (18 semibold). Line 2: "Wed, Sep 16 · 9:14 AM · 48 min" (14, secondary). Line 3: "62 shots · 3 blocks · 60 clips"; clips are left out at 0; free sessions list their clubs instead of a block count ("15 putts · Putter"). Right: session % in `value` (title2 semibold), **accent when every block is complete**, ink otherwise; free sessions show no %. Then a hairline chevron like `BlockRow`. | Covers date, plan, duration and clips on the row. Per-block reps go in the detail. The % is what the summary headline showed on Done. |
| Detail | Large title = plan name, `navigationSubtitle` = "Wed, Sep 16, 2026 · 9:14 AM". Then, as in Figma 12: a **headline card** (`card`, radius 20, padding 20) with the % in 64 pt rounded bold accent (the summary uses 88; smaller because this isn't the moment of finishing), the caption "62 of 100 shots" (15 medium), and "Range + clips · face-on" (15, secondary). Then **block rows**: title 15 semibold, right "22 / 30" (14 secondary) and "73%" (14 semibold, accent when over target), 14 pt apart, **no progress bars**. Then **three stat tiles** as in Figma 12 (`card`, radius 14): duration, clips saved, manual fixes. | F8 wants per-block reps. Reusing the summary's layout means one look for "results". The bars and a shared row view are #11 code, so they're a follow-up and not a dependency here. Avg tempo is left out until #27. |
| Free sessions | Headline = total count, caption "shots"/"putts" (#9's `countDetail`). Rows show the bare count with no %. Tags are added to the title ("7 iron · fade, low"), because free blocks split on tag changes. Unused blocks are hidden. | Same rules as #11's summary. |
| Planned sessions | Skipped blocks stay visible as "0 / 30  0%". | They count against completion (§5.1). |
| Percent | Rounded, but never "100%" before the target is reached (199/200 = "99%"). | Same rule as #11, so the log and the summary agree. |
| Delete | Swipe a row → **Delete** (danger tint, no destructive role, like the plans list) → alert "Delete this session?" / "Its shots and clips are deleted too." → `SessionLog.delete`, which cascades to results and shots, then removes the clip folder after the save succeeds. Active sessions are refused. There's no undo. | Q25's leaning and `RootView`'s comment ("delete it from the log later") both point here. It follows the plan-delete pattern (asks first, §5.3c). If the owner doesn't want delete in #12, drop step 3 and the swipe action. |
| Empty | `ContentUnavailableView` "No sessions yet" / "Finished sessions show up here." (placeholder copy). | |
| Query | `@Query(sort: \PracticeSession.startedAt, order: .reverse)`, then `status == .finished` filtered in Swift. | ADR 0013: an enum-captured `#Predicate` throws on iOS 26.5. A personal log is at most a few hundred sessions. |

## Final layout

```
Reps/Log/SessionLogDisplay.swift        new: LogBlock, LogEntry, LogRow, LogSection, LogBlockRow, LogStat, LogDetail, SessionLogDisplay
Reps/Log/SessionLog.swift               new: SessionLogError, SessionLog.delete(_:in:clipFiles:)
Reps/UI/Log/LogTheme.swift              new: Theme.Typography / Theme.Radius extensions (log* names)
Reps/UI/Log/SessionLogView.swift        new: SessionLogView, LogCard (private), LogEntry.init(_:), LogBlock.init(_:), PreviewData.logContainer(), #Preview
Reps/UI/Log/SessionLogDetailView.swift  new: SessionLogDetailView, LogBlockLine / LogStatTile (private), #Preview
Reps/UI/Plans/PlansView.swift           changed: "Log" toolbar button + navigationDestination (3 edits)
RepsTests/SessionLogDisplayTests.swift  new (11 tests)
RepsTests/SessionLogTests.swift         new (2 tests, in-memory store)
docs/code-reference.md, docs/design.md, docs/open-questions.md, docs/roadmap.md
```

Never edit `project.pbxproj`: the folders are synced (ADR 0009), and the new `Reps/Log/` and `Reps/UI/Log/` folders are picked up.

## Steps

Branch `feat/12-session-log` from `main` (after #11 is merged). From the repo root:

```sh
DEST27='platform=iOS Simulator,id=A26BAE3A-CDDE-45A8-892D-2359740C877A'   # iPhone 17 Pro, iOS 27
DEST265='platform=iOS Simulator,id=6D2623EF-0394-46F9-BFEC-022E3D2B7FE8'  # iPhone 17 Pro, iOS 26.5
T="xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan Unit"
```

Before each commit, run `xcrun swift-format format --in-place --recursive --parallel Reps RepsTests`, then `xcrun swift-format lint --strict --recursive --parallel Reps RepsTests`, which must print nothing.

### Step 1: log logic (TDD)

1. Create `RepsTests/SessionLogDisplayTests.swift` (Appendix A). Run `$T -destination "$DEST27" -only-testing:RepsTests/SessionLogDisplayTests`. It **fails to compile**.
2. Create `Reps/Log/SessionLogDisplay.swift` (Appendix A). Run the same command. **11 tests pass.** The time strings contain U+202F (narrow no-break space) before "AM", which is what current ICU produces for `en_US`. If only those asserts fail on a simulator, report the actual string. Don't loosen the test.
3. `git add -A && git commit -m "added session log logic" -m "Refs #12"`

### Step 2: session delete (TDD)

1. Create `RepsTests/SessionLogTests.swift` (Appendix A). Run `$T -destination "$DEST27" -only-testing:RepsTests/SessionLogTests`. It fails to compile.
2. Create `Reps/Log/SessionLog.swift` (Appendix A). Run the same command, then the same with `"$DEST265"`. **2 tests pass on both.**
3. `git add -A && git commit -m "added session delete for the log" -m "Refs #12"`

### Step 3: log screens

1. Create `Reps/UI/Log/LogTheme.swift`, `Reps/UI/Log/SessionLogView.swift` and `Reps/UI/Log/SessionLogDetailView.swift` (Appendix B).
2. Apply the three `PlansView.swift` edits (Appendix B).
3. Build: `xcodebuild build -project Reps.xcodeproj -scheme Reps -destination "$DEST27" -quiet`. It must succeed with no new warnings.
4. Run the full Unit plan on **both** simulators: `$T -destination "$DEST27"`, then `$T -destination "$DEST265"`. Both must print `** TEST SUCCEEDED **`.
5. Manual smoke test on the iOS 27 simulator. There are no UI tests, and CLAUDE.md asks only for a build for screens without logic.
   - Plans → **Log** (top left) → "No sessions yet".
   - Back. Start a plan with ≥ 3 blocks, go over target on block 1, skip block 2, leave block 3 short, End → Done. Log → one "September 2026"-style section with one card: plan name, "<weekday>, <month> <day> · <time> · under 1 min", "`n` shots · 3 blocks", a % in ink (not every block complete).
   - Tap the card → the detail: large title plan name, date subtitle, headline % + "`done` of `target` shots" + "Range · face-on", three rows (block 1 in accent with >100 %, skipped "0 / x  0%"), tiles "under 1 min", "0", manual fixes = net +1s. Back.
   - Free session: +1 twice, change club, +1, End → Done. The log shows it on top as "Free session", "3 shots · 7 iron, PW"-style, with no %. Its detail headline is "3" / "shots", with a row per club.
   - Rename or delete the plan in Plans → the log still shows the old name ("Its sessions stay in the log.").
   - Swipe a card → Delete → alert → Cancel keeps it; Delete removes it. Plans card "Last done" updates.
   - Kill the app mid-session (an active session) → relaunch → the resume prompt; the active session does **not** appear in the log until it's finished.
   - Previews: `SessionLogView` and `SessionLogDetailView` render in Xcode's canvas with sample sessions.
6. `git add -A && git commit -m "added session log screens" -m "Refs #12"`

### Step 4: docs

1. `docs/code-reference.md`: apply Appendix C.
2. `docs/design.md`: change the table row `| Session log | #12 | not designed; follow the Plans list and summary styles |` to `| Session log | #12 | not designed; built from 01 Plans (cards) and 12 Session summary (detail), see Q31 |`, and below the table (after the #11 line if present) add `- Session log (#12): "Log" at the top left of Plans pushes the log; month sections of Plans-style cards; the detail reuses the summary's headline card, block rows (no bars yet) and stat tiles. Tokens in \`Reps/UI/Log/LogTheme.swift\`.`
3. `docs/open-questions.md`, Open table. Use the next free number (Q31 if #11 added Q30; otherwise renumber here and in the code comment in `SessionLogView.swift`):
   `| Q31 | The session log (#12) was designed without a Figma frame. OK as built: "Log" at the top left of Plans, month sections of plan-style cards, a detail like the summary (no bars), swipe to delete? Also: should a plan card open that plan's history? | – (#12 ships this) | Choices listed in docs/plans/12-session-log.md. A Figma frame can follow once the owner has used it; per-plan history would reuse SessionLogView with a plan filter. |`
   Append to Q25's Notes: `#12 adds delete from the log (swipe, asks first).`
4. `docs/roadmap.md`: #12 ☐ → ☑.
5. `git add -A && git commit -m "documented session log" -m "Refs #12"`

There's no review (label `ui` only). Push and open a PR titled `added session log` with the body `finished sessions by month with per-block detail and delete` plus `Closes #12`.

## Tests

- `RepsTests/SessionLogDisplayTests` (Unit, 11 tests): month grouping and order across years, stable tie order, planned row copy (date, time, duration, shots/blocks/clips, %), complete row (100 %, accent flag, no clips, "1 h 12 min"), % never 100 before target, free row (clubs, hidden unused block, no %, no duration without an end), planned detail (date line, mode line, headline, caption, rows including a skipped block, stats), over-target row (150 %), putting (note titles, blank note falls back, "putts", net manual fixes), free detail (count headline, tag titles, "under 1 min"), duration formats.
- `RepsTests/SessionLogTests` (Unit, 2 tests, in-memory store): delete cascades session → results → shots, keeps the plan and its blocks, and calls `removeClips(sessionID:)`. An active session is refused, and nothing is deleted.
- Views: build only, plus the smoke test.

## Placeholders (`// PLACEHOLDER:` in code)

| Where | What ships now |
|---|---|
| `SessionLogDisplay.duration` | "under 1 min" |
| `SessionLogView` empty state | "No sessions yet" / "Finished sessions show up here." |
| `SessionLogView` delete alert message | "Its shots and clips are deleted too." |
| `SessionLogView` delete error | "Couldn't delete the session." (#29) |
| `PlansView` toolbar | "Log" label |

Other copy that isn't from Figma and is worth the owner's eye: "Session log" (title), "Delete this session?", "duration" / "clips saved" / "manual fixes" (the last two are Figma 12's), the month header format. Also `TODO(#22)` (real clip remover), `TODO(#24)`/`TODO(#26)` (clips from the detail), `TODO(#11 follow-up)` (shared row with bars).

After step 3, `grep -rn "PLACEHOLDER:" Reps/Log Reps/UI/Log` lists **4 lines**, and `grep -n "PLACEHOLDER: session log" Reps/UI/Plans/PlansView.swift` lists 1.

## Follow-ups (not in this issue)

- **Share the result row with the summary.** Once #11 and #12 are both merged, the detail's `LogBlockLine`/`LogStatTile` and #11's summary row (with its surplus bar) and stat tile should be one component in `Reps/UI/Components/`. `SessionLogDisplay.percent`/`duration` and `SummaryDisplay.percent`/`duration` should become one helper. They're duplicated on purpose here, so #12 doesn't depend on unmerged code. Open an issue after merge.
- Per-plan history from a plan card (Q31).
- Clips from the detail (#24), Save to Photos (#26).

## Risks and unresolved

- **Q22 timing.** If #12 lands before #11, the headline is the uncapped % (it can read 112 %). The code doesn't change either way, and the tests avoid over-target sessions so they pass both ways.
- **Deleting is permanent** and, after #22, removes clip files. It goes through `ClipFileRemoving` (the same path as `SessionController.discard`), so no file paths are built here. It asks first, but there's no undo. If the owner wants an undo toast, add it later with the 5 s `UndoToast`.
- **Deleting a session opened in the detail**: not possible, because delete is only offered on the list.
- **`navigationDestination(item:)` with a SwiftData model**: `PracticeSession` is `Hashable` through `PersistentModel`. Context7 confirms the modifier must sit outside the lazy `List` content, and it does (on the `List`).
- **Large logs**: the whole finished list is mapped on each body pass. That's fine for hundreds of sessions. Revisit with `fetchLimit` or paging only if it's slow.
- **Locale**: dates and times follow the device locale (templates `EEEMMMd`, `yMMMEd`, `jmm`, `yMMMM`). Tests pin `en_US` and UTC.
- **Parallel #11 file**: the #11 planner left an untracked `docs/plans/11-session-summary.md` in the working tree. #12 doesn't touch it.

## Appendix A: logic and tests (verified, copy exactly)

### `Reps/Log/SessionLogDisplay.swift`

```swift
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
```

### `RepsTests/SessionLogDisplayTests.swift`

```swift
import Foundation
import Testing

@testable import Reps

@MainActor
struct SessionLogDisplayTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let locale = Locale(identifier: "en_US")
    // Wednesday 16 September 2026, 10:00 UTC
    private let wednesday = Date(timeIntervalSince1970: 1_789_552_800)

    private func block(
        _ order: Int, _ club: String, counted: Int, adjust: Int = 0, target: Int?, note: String? = nil,
        tags: [String] = [], clips: Int = 0
    ) -> LogBlock {
        LogBlock(
            order: order, clubName: club, note: note, tags: tags, counted: counted, manualAdjust: adjust,
            target: target, clipCount: clips)
    }

    private func entry(
        _ planName: String?, mode: PracticeMode = .rangeCounter, angle: CameraAngle = .faceOn, start: Date,
        minutes: Double? = 48, blocks: [LogBlock], id: UUID = UUID()
    ) -> LogEntry {
        LogEntry(
            id: id, planName: planName, mode: mode, cameraAngle: angle, startedAt: start,
            endedAt: minutes.map { start.addingTimeInterval($0 * 60) }, blocks: blocks)
    }

    // No block over target, so the numbers hold with or without the Q22 cap (#11).
    private var wedgeDay: LogEntry {
        entry(
            "Wedge day", mode: .rangeCounterWithClips, start: wednesday,
            blocks: [
                block(1, "GW", counted: 20, adjust: 2, target: 30, clips: 20),
                block(0, "PW", counted: 40, target: 40, clips: 40),
                block(2, "SW", counted: 0, target: 30),
            ])
    }

    @Test func sectionsGroupByMonthNewestFirst() {
        let august = wednesday.addingTimeInterval(-30 * 86_400)
        let lastYear = wednesday.addingTimeInterval(-365 * 86_400)
        let a = entry("A", start: wednesday.addingTimeInterval(-86_400), blocks: [])
        let b = entry("B", start: wednesday, blocks: [])
        let c = entry("C", start: august, blocks: [])
        let d = entry("D", start: lastYear, blocks: [])
        let sections = SessionLogDisplay.sections([c, a, d, b], calendar: calendar, locale: locale)
        #expect(sections.map(\.title) == ["September 2026", "August 2026", "September 2025"])
        #expect(sections.map { $0.rows.map(\.title) } == [["B", "A"], ["C"], ["D"]])
        #expect(SessionLogDisplay.sections([], calendar: calendar, locale: locale).isEmpty)
    }

    @Test func sameStartTimeSortsStably() {
        let low = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let high = UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001")!
        let first = entry("Low", start: wednesday, blocks: [], id: low)
        let second = entry("High", start: wednesday, blocks: [], id: high)
        let rows = SessionLogDisplay.sections([first, second], calendar: calendar, locale: locale)[0].rows
        #expect(rows.map(\.title) == ["High", "Low"])
    }

    @Test func plannedRow() {
        let row = SessionLogDisplay.row(wedgeDay, calendar: calendar, locale: locale)
        #expect(row.title == "Wedge day")
        #expect(row.subtitle == "Wed, Sep 16 · 10:00\u{202F}AM · 48 min")
        #expect(row.detail == "62 shots · 3 blocks · 60 clips")
        #expect(row.percent == "62%")
        #expect(!row.isComplete)
    }

    @Test func completeRowShows100AndNoClips() {
        let done = entry(
            "Irons", start: wednesday, minutes: 72,
            blocks: [
                block(0, "7 iron", counted: 30, target: 30), block(1, "6 iron", counted: 29, adjust: 1, target: 30),
            ])
        let row = SessionLogDisplay.row(done, calendar: calendar, locale: locale)
        #expect(row.percent == "100%")
        #expect(row.isComplete)
        #expect(row.detail == "60 shots · 2 blocks")
        #expect(row.subtitle.hasSuffix(" · 1 h 12 min"))
    }

    @Test func percentNeverShows100BeforeTarget() {
        let almost = entry("Long", start: wednesday, blocks: [block(0, "PW", counted: 199, target: 200)])
        #expect(SessionLogDisplay.row(almost, calendar: calendar, locale: locale).percent == "99%")
        #expect(SessionLogDisplay.percent(0.996, isComplete: false) == "99%")
        #expect(SessionLogDisplay.percent(1.5, isComplete: true) == "150%")
        #expect(SessionLogDisplay.percent(1.0 / 3.0, isComplete: false) == "33%")
    }

    @Test func freeRowListsClubsAndHidesUnusedBlocks() {
        let free = entry(
            nil, mode: .putting, angle: .none, start: wednesday, minutes: nil,
            blocks: [
                block(0, "Putter", counted: 12, target: nil),
                block(1, "7 iron", counted: 0, target: nil),
                block(2, "Putter", counted: 0, adjust: 3, target: nil, tags: ["lag"]),
            ])
        let row = SessionLogDisplay.row(free, calendar: calendar, locale: locale)
        #expect(row.title == "Free session")
        #expect(row.subtitle == "Wed, Sep 16 · 10:00\u{202F}AM")
        #expect(row.detail == "15 putts · Putter")
        #expect(row.percent == nil)
        #expect(!row.isComplete)
    }

    @Test func plannedDetail() {
        let detail = SessionLogDisplay.detail(wedgeDay, calendar: calendar, locale: locale)
        #expect(detail.dateLine == "Wed, Sep 16, 2026 · 10:00\u{202F}AM")
        #expect(detail.modeLine == "Range + clips · face-on")
        #expect(detail.headline == "62%")
        #expect(detail.caption == "62 of 100 shots")
        #expect(
            detail.rows == [
                LogBlockRow(id: 0, title: "PW", detail: "40 / 40", percent: "100%", isOverTarget: false),
                LogBlockRow(id: 1, title: "GW", detail: "22 / 30", percent: "73%", isOverTarget: false),
                LogBlockRow(id: 2, title: "SW", detail: "0 / 30", percent: "0%", isOverTarget: false),
            ])
        #expect(detail.stats.map(\.value) == ["48 min", "60", "2"])
        #expect(detail.stats.map(\.label) == ["duration", "clips saved", "manual fixes"])
    }

    @Test func overTargetBlockRow() {
        let row = SessionLogDisplay.blockRow(
            block(0, "GW", counted: 45, target: 30), mode: .rangeCounter, isFree: false)
        #expect(row.detail == "45 / 30")
        #expect(row.percent == "150%")
        #expect(row.isOverTarget)
    }

    @Test func puttingDetailUsesNotes() {
        let putting = entry(
            "Putting 3-6-9", mode: .putting, angle: .none, start: wednesday,
            blocks: [
                block(0, "Putter", counted: 30, target: 30, note: "3 ft"),
                block(1, "Putter", counted: 10, adjust: -1, target: 30, note: " "),
            ])
        let detail = SessionLogDisplay.detail(putting, calendar: calendar, locale: locale)
        #expect(detail.modeLine == "Putting counter")
        #expect(detail.caption == "39 of 60 putts")
        #expect(detail.rows.map(\.title) == ["3 ft", "Putter"])
        #expect(detail.stats[2].value == "1")
    }

    @Test func freeDetail() {
        let free = entry(
            nil, start: wednesday, minutes: 0.5,
            blocks: [
                block(0, "7 iron", counted: 0, adjust: 20, target: nil),
                block(1, "7 iron", counted: 0, adjust: 5, target: nil, tags: ["fade", "low"]),
                block(2, "PW", counted: 0, target: nil),
            ])
        let detail = SessionLogDisplay.detail(free, calendar: calendar, locale: locale)
        #expect(detail.headline == "25")
        #expect(detail.caption == "shots")
        #expect(detail.rows.map(\.title) == ["7 iron", "7 iron · fade, low"])
        #expect(detail.rows.map(\.detail) == ["20", "5"])
        #expect(detail.rows.allSatisfy { $0.percent == nil })
        #expect(detail.stats.map(\.value) == ["under 1 min", "0", "25"])
    }

    @Test func durationFormats() {
        let start = wednesday
        func after(_ minutes: Double) -> String? {
            SessionLogDisplay.duration(from: start, to: start.addingTimeInterval(minutes * 60))
        }
        #expect(SessionLogDisplay.duration(from: start, to: nil) == nil)
        #expect(after(0.9) == "under 1 min")
        #expect(after(-5) == "under 1 min")
        #expect(after(48.7) == "48 min")
        #expect(after(60) == "1 h")
        #expect(after(125) == "2 h 5 min")
    }
}
```

### `Reps/Log/SessionLog.swift`

```swift
import Foundation
import SwiftData

enum SessionLogError: Error, Equatable {
    case notFinished
}

// Session log writes (F8, Q25).
enum SessionLog {
    // Deletes a finished session with its blocks and shots (cascade), then its clip folder once the save succeeds.
    // An active session belongs to SessionController and is refused.
    static func delete(_ session: PracticeSession, in context: ModelContext, clipFiles: any ClipFileRemoving)
        throws
    {
        guard session.status == .finished else { throw SessionLogError.notFinished }
        let sessionID = session.id
        context.delete(session)
        try context.save()
        clipFiles.removeClips(sessionID: sessionID)
    }
}
```

### `RepsTests/SessionLogTests.swift`

```swift
import Foundation
import SwiftData
import Testing

@testable import Reps

@MainActor
struct SessionLogTests {
    // Keep the container alive; a context alone doesn't retain it.
    let container: ModelContainer
    let context: ModelContext
    let clips = ClipSpy()

    init() throws {
        container = try RepsStore.makeContainer(inMemory: true)
        context = container.mainContext
    }

    private func makeSession(status: SessionStatus) throws -> PracticeSession {
        let plan = PracticePlan(name: "Wedge day", mode: .rangeCounter)
        context.insert(plan)
        plan.blocks = [PlanBlock(clubName: "PW", targetReps: 30, order: 0)]
        let session = PracticeSession(plan: plan, mode: .rangeCounter, cameraAngle: .faceOn)
        context.insert(session)
        let result = BlockResult(block: plan.blocks[0], order: 0)
        session.blockResults.append(result)
        result.shots.append(ShotRecord(detectedBy: .manual, clubName: "PW"))
        result.repsManualAdjust = 1
        session.status = status
        try context.save()
        return session
    }

    @Test func deleteRemovesSessionResultsShotsAndClips() throws {
        let session = try makeSession(status: .finished)
        let id = session.id
        try SessionLog.delete(session, in: context, clipFiles: clips)
        #expect(try context.fetchCount(FetchDescriptor<PracticeSession>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<BlockResult>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ShotRecord>()) == 0)
        #expect(clips.removedSessions == [id])
        // The plan and its blocks stay.
        #expect(try context.fetchCount(FetchDescriptor<PracticePlan>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<PlanBlock>()) == 1)
    }

    @Test func deleteRefusesAnActiveSession() throws {
        let session = try makeSession(status: .active)
        #expect(throws: SessionLogError.notFinished) {
            try SessionLog.delete(session, in: context, clipFiles: clips)
        }
        #expect(try context.fetchCount(FetchDescriptor<PracticeSession>()) == 1)
        #expect(clips.removedSessions.isEmpty)
    }
}
```

## Appendix B: views (type-checked, copy exactly)

### `Reps/UI/Log/LogTheme.swift`

```swift
import SwiftUI

// Session log sizes. No Figma frame: values follow 12 Session summary (docs/design.md).
extension Theme.Typography {
    static let logHeadline = Font.system(size: 64, weight: .bold, design: .rounded)
    static let logHeadlineTracking: CGFloat = -1.92
    static let logCaption = Font.system(size: 15, weight: .medium)
    static let logModeLine = Font.system(size: 15)
    static let logRowTitle = Font.system(size: 15, weight: .semibold)
    static let logRowDetail = Font.system(size: 14)
    static let logRowPercent = Font.system(size: 14, weight: .semibold)
    static let logStatValue = Font.system(size: 20, weight: .semibold)
    static let logStatLabel = Font.system(size: 12)
}

extension Theme.Radius {
    static let logStat: CGFloat = 14
}
```

### `Reps/UI/Log/SessionLogView.swift`

```swift
import SwiftData
import SwiftUI

// Session log (F8). No Figma frame: cards follow 01 Plans, the detail follows 12 Summary (Q31).
struct SessionLogView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PracticeSession.startedAt, order: .reverse) private var sessions: [PracticeSession]
    @State private var selected: PracticeSession?
    @State private var sessionToDelete: PracticeSession?
    @State private var errorMessage: String?

    var body: some View {
        // ADR 0006: finished sessions only; the enum is filtered in memory (ADR 0013).
        let finished = sessions.filter { $0.status == .finished }
        let byID = Dictionary(finished.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let sections = SessionLogDisplay.sections(finished.map(LogEntry.init))
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        LogCard(row: row) { selected = byID[row.id] }
                            .logRow()
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                // No destructive role: the row must stay until the alert is confirmed.
                                Button("Delete") { sessionToDelete = byID[row.id] }
                                    .tint(Theme.danger)
                            }
                    }
                } header: {
                    Text(section.title)
                        .font(Theme.Typography.footnoteMedium)
                        .foregroundStyle(Theme.secondaryText)
                        .textCase(nil)
                }
                .listSectionSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .overlay {
            if sections.isEmpty {
                ContentUnavailableView(
                    "No sessions yet",  // PLACEHOLDER: empty log copy
                    systemImage: "clock",
                    description: Text("Finished sessions show up here.")
                )
            }
        }
        .navigationTitle("Session log")
        .navigationDestination(item: $selected) { session in
            SessionLogDetailView(session: session)
        }
        .alert(
            "Delete this session?",
            isPresented: Binding(get: { sessionToDelete != nil }, set: { if !$0 { sessionToDelete = nil } }),
            presenting: sessionToDelete
        ) { session in
            Button("Delete", role: .destructive) { delete(session) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its shots and clips are deleted too.")  // PLACEHOLDER: delete-session alert copy
        }
        .alert(
            errorMessage ?? "",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        }
    }

    private func delete(_ session: PracticeSession) {
        do {
            // TODO(#22): pass the real ClipFileRemoving once clips exist.
            try SessionLog.delete(session, in: context, clipFiles: NoClipFiles())
        } catch {
            errorMessage = "Couldn't delete the session."  // PLACEHOLDER: error copy (#29)
        }
    }
}

private struct LogCard: View {
    let row: LogRow
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.title)
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(Theme.ink)
                    Text(row.subtitle)
                        .font(Theme.Typography.detail)
                        .foregroundStyle(Theme.secondaryText)
                    Text(row.detail)
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                if let percent = row.percent {
                    Text(percent)
                        .font(Theme.Typography.value)
                        .monospacedDigit()
                        .foregroundStyle(row.isComplete ? Theme.accent : Theme.ink)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.hairline)
            }
            .padding(.leading, 20)
            .padding(.trailing, 16)
            .padding(.vertical, 18)
            .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.card))
            .contentShape(.rect(cornerRadius: Theme.Radius.card))
        }
        .buttonStyle(.plain)
    }
}

extension LogEntry {
    init(_ session: PracticeSession) {
        self.init(
            id: session.id,
            planName: session.planName,
            mode: session.mode,
            cameraAngle: session.cameraAngle,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            blocks: session.blockResults.map(LogBlock.init)
        )
    }
}

extension LogBlock {
    init(_ result: BlockResult) {
        self.init(
            order: result.order,
            clubName: result.clubName,
            note: result.block?.note,
            tags: result.tags,
            counted: result.repsCounted,
            manualAdjust: result.repsManualAdjust,
            target: result.targetReps,
            clipCount: result.shots.filter { $0.clipFileName != nil }.count
        )
    }
}

extension View {
    // Same card-row insets as the plans list.
    fileprivate func logRow() -> some View {
        listRowInsets(
            EdgeInsets(
                top: Theme.Spacing.cardGap / 2, leading: Theme.Spacing.gutter,
                bottom: Theme.Spacing.cardGap / 2, trailing: Theme.Spacing.gutter)
        )
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

#if DEBUG
    extension PreviewData {
        // The plans container plus one finished session per plan, a few days apart.
        static func logContainer() -> ModelContainer {
            let made = container()
            let context = made.mainContext
            let plans = (try? context.fetch(FetchDescriptor<PracticePlan>())) ?? []
            for (index, plan) in plans.enumerated() {
                let start = Date.now.addingTimeInterval(-Double(index + 1) * 3 * 86_400)
                let angle: CameraAngle = plan.mode == .putting ? .none : .faceOn
                let session = PracticeSession(plan: plan, mode: plan.mode, cameraAngle: angle, startedAt: start)
                context.insert(session)
                for block in plan.sortedBlocks {
                    let result = BlockResult(block: block, order: block.order)
                    result.repsManualAdjust = max(0, block.targetReps - 5 * block.order)
                    session.blockResults.append(result)
                }
                session.status = .finished
                session.endedAt = start.addingTimeInterval(48 * 60)
            }
            return made
        }
    }

    #Preview {
        NavigationStack { SessionLogView() }
            .modelContainer(PreviewData.logContainer())
    }
#endif
```

### `Reps/UI/Log/SessionLogDetailView.swift`

```swift
import SwiftData
import SwiftUI

// One finished session: overall completion, per-block results, stats (F8). Styled after Figma 12.
struct SessionLogDetailView: View {
    let session: PracticeSession

    var body: some View {
        let detail = SessionLogDisplay.detail(LogEntry(session))
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 2) {
                    Text(detail.headline)
                        .font(Theme.Typography.logHeadline)
                        .tracking(Theme.Typography.logHeadlineTracking)
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(detail.caption)
                        .font(Theme.Typography.logCaption)
                        .foregroundStyle(Theme.ink)
                    Text(detail.modeLine)
                        .font(Theme.Typography.logModeLine)
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.card))
                // TODO(#11 follow-up): reuse the summary's block row with its progress bar.
                VStack(spacing: 14) {
                    ForEach(detail.rows) { row in
                        LogBlockLine(row: row)
                    }
                }
                HStack(spacing: 10) {
                    ForEach(detail.stats) { stat in
                        LogStatTile(stat: stat)
                    }
                }
                // TODO(#24): open this session's clips in the library. TODO(#26): Save to Photos per clip (§5.8).
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle(SessionDisplay.title(planName: session.planName))
        .navigationSubtitle(detail.dateLine)
    }
}

private struct LogBlockLine: View {
    let row: LogBlockRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(row.title)
                .font(Theme.Typography.logRowTitle)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(row.detail)
                .font(Theme.Typography.logRowDetail)
                .foregroundStyle(Theme.secondaryText)
            if let percent = row.percent {
                Text(percent)
                    .font(Theme.Typography.logRowPercent)
                    .foregroundStyle(row.isOverTarget ? Theme.accent : Theme.ink)
            }
        }
        .monospacedDigit()
    }
}

private struct LogStatTile: View {
    let stat: LogStat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stat.value)
                .font(Theme.Typography.logStatValue)
                .foregroundStyle(Theme.ink)
            Text(stat.label)
                .font(Theme.Typography.logStatLabel)
                .foregroundStyle(Theme.secondaryText)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 12)
        .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.logStat))
    }
}

#if DEBUG
    #Preview {
        let container = PreviewData.logContainer()
        let session = try! container.mainContext.fetch(FetchDescriptor<PracticeSession>()).first!
        return NavigationStack { SessionLogDetailView(session: session) }
            .modelContainer(container)
    }
#endif
```

### `Reps/UI/Plans/PlansView.swift` (3 edits)

1. After `@State private var errorMessage: String?` add:

```swift
    @State private var showsLog = false
```

2. Inside `.toolbar {`, before the existing `ToolbarItem(placement: .topBarTrailing) {` (Settings), add:

```swift
                ToolbarItem(placement: .topBarLeading) {
                    Button("Log") { showsLog = true }  // PLACEHOLDER: session log entry label
                        .tint(Theme.accent)
                }
```

3. Directly before `.fullScreenCover(item: $editing) { target in` add:

```swift
            .navigationDestination(isPresented: $showsLog) {
                SessionLogView()
            }
```

Resulting diff against today's `main`:

```diff
@@ -27,6 +27,7 @@
     @State private var editing: PlanEditorTarget?
     @State private var planToDelete: PracticePlan?
     @State private var errorMessage: String?
+    @State private var showsLog = false
 
     var body: some View {
         NavigationStack {
@@ -57,11 +58,18 @@
             .navigationTitle("Plans")
             .navigationSubtitle(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
             .toolbar {
+                ToolbarItem(placement: .topBarLeading) {
+                    Button("Log") { showsLog = true }  // PLACEHOLDER: session log entry label
+                        .tint(Theme.accent)
+                }
                 ToolbarItem(placement: .topBarTrailing) {
                     Button("Settings") {}  // TODO(#6): open Settings
                         .tint(Theme.accent)
                 }
             }
+            .navigationDestination(isPresented: $showsLog) {
+                SessionLogView()
+            }
             .fullScreenCover(item: $editing) { target in
                 PlanEditorView(plan: target.plan)
             }
```

## Appendix C: docs/code-reference.md

Add after the `## Reps/Plans/PlanLibrary.swift` section:

```
## Reps/Log/SessionLogDisplay.swift
Grouping, sorting and copy for the session log (F8); values in, strings out.
- `LogBlock` / `LogEntry`: plain copies of a BlockResult / finished PracticeSession (built in `SessionLogView.swift`)
- `SessionLogDisplay.sections(_:calendar:locale:) -> [LogSection]`: month sections ("September 2026"), newest month and session first, ties by id
- `row(_:calendar:locale:) -> LogRow`: title, "Wed, Sep 16 · 9:14 AM · 48 min", "62 shots · 3 blocks · 60 clips" (free: clubs), session % (nil when free), `isComplete`
- `detail(_:calendar:locale:) -> LogDetail`: date line, mode line, headline % or count, caption, block rows, stats (duration, clips saved, manual fixes)
- `blockRow(_:mode:isFree:) -> LogBlockRow`: title (putting note, free tags), "45 / 30", block %, over-target flag
- `percent(_:isComplete:)`: rounded, capped at 99 until complete; `duration(from:to:)`: "48 min", "1 h 12 min", nil without an end
- `shownBlocks(_:)`: by order; free sessions drop unused blocks

## Reps/Log/SessionLog.swift
- `SessionLog.delete(_:in:clipFiles:) throws`: deletes a finished session (cascade to results and shots), saves, then `removeClips(sessionID:)`; throws `SessionLogError.notFinished` for an active one
```

Add after the `## Reps/UI/Library/LibraryPlaceholderView.swift` section:

```
## Reps/UI/Log/SessionLogView.swift
No Figma frame (Q31); cards follow 01 Plans.
- `SessionLogView`: `@Query` sessions by `startedAt` desc, finished only (filtered in memory, ADR 0013); month sections of cards → detail push; swipe Delete asks first → `SessionLog.delete` (`NoClipFiles` until #22); empty state
- `LogEntry.init(_:)`, `LogBlock.init(_:)`: model → value copies (clip count = shots with a `clipFileName`)
- `PreviewData.logContainer()` (DEBUG): preview store with one finished session per sample plan

## Reps/UI/Log/SessionLogDetailView.swift
Styled after Figma 12.
- `SessionLogDetailView(session:)`: title + date subtitle, headline card (% or count, caption, mode line), block rows, stat tiles; clips are `TODO(#24)`

## Reps/UI/Log/LogTheme.swift
- `Theme.Typography.log*`, `Theme.Radius.logStat`: log sizes from Figma 12
```

In `## Reps/UI/Plans/PlansView.swift`, change "Settings is `TODO(#6)`" to "Log (top left) pushes `SessionLogView`; Settings is `TODO(#6)`".

Add after `## RepsTests/SessionDisplayTests.swift`:

```
## RepsTests/SessionLogDisplayTests.swift
Log sections and order, row and detail copy (planned, putting, free), percent cap, durations (en_US, UTC).

## RepsTests/SessionLogTests.swift
In-memory store: delete cascades and removes clips; active sessions are refused.
```
