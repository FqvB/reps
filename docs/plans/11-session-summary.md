# #11 Session summary + accident-proofing

Goal: End opens the session summary (Figma 12) in place of the live screen. It shows overall completion, per-block done/target with %, clips saved, average tempo and manual fixes. **Continue session** goes back to counting, and **Done** is the only thing that finishes the session. Q22 changes session completion so each block counts at most its target.

Spec: F23 ("**Session summary** on End: overall completion %, per-block done/target with %, clips saved, average tempo, manual fixes; "Keep going" returns to the session, "Done" saves"), F28 (quoted below), §5.1 completion. ADRs: 0006 (persist every shot, Done sets `finished`), 0012 (Completion), 0013 (only Done finishes). Q22 (owner: "session completion caps each block at its target (45/30 + 15/30 = 75 %). Update `Completion` + tests here."), Q25 (still open, unchanged here).

Figma (file `pMKE8PoWxIEotHas0rmQX1`): 12 Session summary `12:169`. No Figma variables, so values are literals off the layers.

**Depends on #9 being merged** (`SessionView`, `SessionDisplay.title/blockTitle/countDetail`, `SummaryPlaceholderView`, `SessionTheme.swift`). Branch `feat/11-session-summary` from `main` after #9 lands. If any #9 name used below differs from `docs/plans/9-session-screen.md`, stop and report.

How this was checked: `Completion.swift`, `SummaryDisplay.swift` and both test files (Appendix A) ran in a scratch SwiftPM package (Swift 6.4, `defaultIsolation(MainActor)`, with the real `ModelEnums`, `PlanSummary`, `PracticeMode+Title` and #9's `SessionDisplay`): **18 tests in 2 suites passed**. All Appendix A/B files plus the edited `SessionView` were type-checked with the whole of `Reps/` and #9's Appendix A/B files (`swiftc -typecheck`, iOS 26.0 simulator target, iPhoneSimulator 27.0 SDK, `-default-isolation MainActor`, `-DDEBUG`): clean. `swift-format lint --strict` with the repo's `.swift-format`: clean. The views have not been built by Xcode or run. **Copy every file exactly.**

## What F28 requires, and where each part lives

F28: "**Accident-proofing**: ending a session never saves until Done, and the summary has Continue session; Next block before target asks first; Cancel with unsaved plan edits asks first; deleting a clip asks first; deleting a block gets an undo toast". §5.3c adds: "Plans list: swipe a plan for Duplicate / Delete; delete asks first." and "Undo toast lasts 5 s for block deletion and bulk library actions."

| Clause | Status | Where |
|---|---|---|
| Ending never saves until Done | **#11** | End swaps `SessionView` to the summary; the session stays `.active` (ADR 0006: shots are already persisted, "save" = `finish()` sets `.finished`). Only Done calls `finish()`. A kill while the summary is up leaves an active session, so #9's launch prompt offers resume. The summary is not a sheet, so it can't be swiped away. |
| Summary has Continue session | **#11** | "Continue session" (Figma 12 label; F23 calls it "Keep going", Figma wins) returns to the live screen. |
| Next block before target asks first | done in #9 | `SessionDisplay.nextBlockPrompt` + frame 14 alert. Smoke-check only. |
| Cancel with unsaved plan edits asks first | done in #7 | `PlanEditorView` "Discard changes?" |
| Deleting a clip asks first | #25 | Figma 15 delete alert; clips don't exist yet. |
| Deleting a block gets an undo toast | done in #7 | `PlanEditorView` + `UndoToast` (5 s). |
| Plan delete asks first (§5.3c) | done in #7 | `PlansView` alert. |

Not added, because the spec doesn't ask for them: a confirm before End (the summary is the confirmation), an undo toast after −1 (−1 is itself the undo for +1), an undo after Done. The testable logic here is the summary math and copy (`SummaryDisplay`); End/Continue/Done is plain view state with no decisions to test.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Q22 | `Completion.session` sums `min(done, target)` per targeted block over the sum of targets. `Completion.block` stays uncapped (150 %). `isComplete` unchanged. | Owner answer. Callers: `PracticeSession.completion` (no UI yet) and tests. Existing controller/model tests keep their values (strict blocks can't exceed target; `ModelTests` is 70/70). Export stores no derived values (ADR 0012), so export is unaffected. |
| Summary presentation | **In place**, not a sheet: `SessionView` shows `SessionSummaryView` instead of its content while `showSummary` is true (move-from-bottom transition). Done → `controller.finish()` → session nil → #9's full-screen cover closes. | Figma 12 is a full screen, not a sheet. No nested presentation, so #9's risk ("cover closing with the summary sheet open") goes away. `SummaryPlaceholderView` is deleted. |
| Headline | Q22-capped session %, rounded, in 88 pt rounded bold accent. Figma's "112%" is the old uncapped math; with Q22 its own blocks give **100%**. The caption keeps real totals: "190 of 170 shots · every block complete". | Q22 supersedes the frame. |
| Percent rounding | `Int((fraction*100).rounded())`, but capped at 99 until the target is reached, so "100%" always means complete. | Figma: 35/30 = "117%" (rounded, not floored). |
| Caption when short | "`<done>` of `<target> shots` · N block(s) short" (placeholder). `done` sums targeted blocks uncapped. | Figma only shows the all-complete case. |
| Per-block rows | Title = `SessionDisplay.blockTitle` (putting uses the note). Right: "45 / 30" (14 regular secondary) and "150%" (14 semibold, accent when over target, ink otherwise). 6 pt track (`card`), accent fill `min(done/target, 1)`; over target, a `#1E4A36` surplus bar from `target/done` to the end. | Figma 12: Gap wedge 45/30 splits at 235/353 = 30/45. |
| Free sessions | Headline = total shots, caption "shots"/"putts" (#9's `countDetail`). Rows show the bare count, no % or bar. Unused blocks (no count, no adjust) are hidden, as `finish()` drops them. Free rows append tags ("7 iron · fade, low") because free blocks split on tag changes. Subtitle starts "Free session". | No targets, so there's no %. |
| Subtitle | "`<plan or Free session>` · `<mode.title>` · `<duration>`" ("Wedge day · Range + clips · 48 min"). Duration is now − `startedAt`, refreshed each minute by `TimelineView(.periodic(from: startedAt, by: 60))`: "under 1 min", "48 min", "1 h 12 min", "2 h". | Figma 12 (no angle there). Context7 checked `periodic(from:by:)`. |
| Stats | **clips saved** = shots with a `clipFileName` (0 until #22); **avg tempo** = mean `tempoRatio`, "3.0 : 1" via `String(format:)` (POSIX decimal point), "–" with none (until #27, and always in putting); **manual fixes** = Σ \|`repsManualAdjust`\| per block. All three always shown. | F23 lists all three. `repsManualAdjust` is net per block, so +1 then −1 counts 0; new Q30 records that. |
| Footer | Footnote "Nothing is saved until you tap Done — ended by accident? Just continue." (12, secondary, centred), then **Continue session** (new `SecondaryButtonStyle`: `card` bg, ink, 17 semibold, radius 18, 18 pt vertical padding), then **Done** (`PrimaryButtonStyle`). Pinned with `safeAreaInset(edge: .bottom)`; the body scrolls (plans can have many blocks). | Figma 12 copy verbatim. |
| Theme | `Theme.accentDeep` (0x1E4A36) added to `Theme.swift` (it needs the file-private `Color(hex:)`). Fonts/radius in new `Reps/UI/Session/SummaryTheme.swift` like #9's `SessionTheme.swift`. | Figma values. |

## Final layout

```
Reps/Model/Completion.swift                       changed: session() caps each block (Q22)
Reps/Session/SummaryDisplay.swift                 new: SummaryBlock, SummaryBar, SummaryRow, SummaryStat, SessionSummary, SummaryDisplay
Reps/UI/Session/SessionSummaryView.swift          new: SessionSummaryView, private row/bar/stat views, SummaryBlock.init(_:), #Preview
Reps/UI/Session/SummaryTheme.swift                new
Reps/UI/Components/SecondaryButtonStyle.swift     new
Reps/UI/Theme/Theme.swift                         + accentDeep
Reps/UI/Session/SessionView.swift                 changed (3 edits)
Reps/UI/Session/SummaryPlaceholderView.swift      deleted
RepsTests/CompletionTests.swift                   changed (Q22)
RepsTests/SummaryDisplayTests.swift               new (8 tests)
docs/spec/mvp-design-doc.md, docs/adr/0012-…, docs/code-reference.md, docs/design.md, docs/open-questions.md, docs/roadmap.md
```

Never edit `project.pbxproj` (synced folders, ADR 0009).

## Steps

From the repo root:

```sh
DEST27='platform=iOS Simulator,id=A26BAE3A-CDDE-45A8-892D-2359740C877A'   # iPhone 17 Pro, iOS 27
DEST265='platform=iOS Simulator,id=6D2623EF-0394-46F9-BFEC-022E3D2B7FE8'  # iPhone 17 Pro, iOS 26.5
```

Before each commit: `xcrun swift-format format --in-place --recursive --parallel Reps RepsTests`, then `xcrun swift-format lint --strict --recursive --parallel Reps RepsTests` must print nothing.

### Step 1: Q22 completion (TDD)

1. Edit `RepsTests/CompletionTests.swift` exactly as in Appendix A (rename + change two tests, add one). Run
   `xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan Unit -destination "$DEST27" -only-testing:RepsTests/CompletionTests` → **fails** (`sessionCapsEachBlockAtItsTarget` gets 1.0, `surplusDoesNotCoverASkippedBlock` 1.0, `sessionNeverExceedsOne` 95/70).
2. Replace `Reps/Model/Completion.swift` with Appendix A. Same command → passes.
3. Run the other suites that read completion: `-only-testing:RepsTests/ModelTests -only-testing:RepsTests/SessionControllerTests -only-testing:RepsTests/FreeSessionTests -only-testing:RepsTests/ExportTests` → pass unchanged. If one fails, stop and report (don't edit its expectation).
4. `git add -A && git commit -m "capped session completion per block" -m "Refs #11"`

### Step 2: summary logic (TDD)

1. Create `RepsTests/SummaryDisplayTests.swift` (Appendix A). Run with `-only-testing:RepsTests/SummaryDisplayTests` → fails to compile.
2. Create `Reps/Session/SummaryDisplay.swift` (Appendix A). Same command → **8 tests pass**.
3. `git add -A && git commit -m "added session summary logic" -m "Refs #11"`

### Step 3: summary screen

1. Add to `Reps/UI/Theme/Theme.swift`, right after the `toastAction` line: `    static let accentDeep = Color(hex: 0x1E4A36)`
2. Create `Reps/UI/Session/SummaryTheme.swift`, `Reps/UI/Components/SecondaryButtonStyle.swift`, `Reps/UI/Session/SessionSummaryView.swift` (Appendix B).
3. Apply the three `SessionView.swift` edits (Appendix B), then `git rm Reps/UI/Session/SummaryPlaceholderView.swift`.
4. Build: `xcodebuild build -project Reps.xcodeproj -scheme Reps -destination "$DEST27" -quiet` → succeeds, no new warnings.
5. Full Unit plan on **both** simulators: `xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan Unit -destination "$DEST27"` and the same with `"$DEST265"` → both `** TEST SUCCEEDED **`.
6. Manual smoke test on the iOS 27 simulator:
   - Start a plan with ≥ 3 blocks. +1 past target on block 1 (e.g. 5 of 3), skip block 2 with Next block (frame 14 alert still appears), leave block 3 short. End → summary slides up: headline is the capped %, caption "`n` of `m` shots · 2 blocks short", block 1 shows e.g. "5 / 3  167%" in accent with a dark surplus bar, the skipped block "0 / x  0%" with an empty track, stats "0 clips saved", "–", manual fixes = number of net +1s.
   - Continue session → back on the live screen, same block and count. Tap +1 → count changes. End again → numbers updated.
   - Wait ~1 minute on the summary → the duration ticks.
   - Stop the app from Xcode while the summary shows, relaunch → "Resume session?" (session was never finished).
   - Done → the cover closes, back on Plans, card shows "Last done today". Start another session → it opens on the live screen, **not** the summary (state reset).
   - Free session: +1 a few times, change club, +1 again, End → rows per club with bare counts, no %, headline = total, caption "shots". Done.
   - Free session with no shots: End → "0" / "shots", no rows. Done → closes (discarded by `finish()`).
   - Putting plan → row titles are notes ("3 ft"), caption says "putts", subtitle "… · Putting · …".
7. `git add -A && git commit -m "added session summary screen" -m "Refs #11"`

### Step 4: docs

1. `docs/spec/mvp-design-doc.md` §5.1: replace the sentence "Session completion is total done over total target, also uncapped." with "Session completion caps each block at its target before summing, so surplus on one block never covers another (45/30 + 15/30 = 75 %, Q22)."
2. `docs/adr/0012-data-model-and-export-v1.md`: at the end of the Completion bullet (line 13) append ` Amended by Q22 (#11): session sums min(done, target) per block.`
3. `docs/code-reference.md`: apply Appendix C.
4. `docs/design.md`: below the table add `- Session summary (#11): shown in place of the session screen on End, not as a sheet. Figma 12's "112%" headline predates Q22; the headline is capped per block (that frame gives 100%). Tokens in \`Reps/UI/Session/SummaryTheme.swift\` and \`Theme.accentDeep\`.`
5. `docs/open-questions.md`:
   - Q22's Resolved row: set "Recorded in" to `` `Completion.session`, spec §5.1, ADR 0012 (#11) ``.
   - Add to Open (next free number after #9's Q28/Q29): `| Q30 | "Manual fixes" on the summary is Σ \|repsManualAdjust\| per block (net, so +1 then −1 counts 0). Count every +1/−1 tap instead? | – (#11 ships net) | Counting taps needs a new stored field (schema V2). Leaning: keep net; it's what §5.1 uses for detector accuracy. |`
   - Q25: leave open; append to its Notes `#11 keeps #9's behaviour.`
6. `docs/roadmap.md`: #11 ☐ → ☑.
7. `git add -A && git commit -m "documented session summary" -m "Refs #11"`

No review (label `ui` only). Push, open a PR titled `added session summary` with body `summary on End with continue / done, completion capped per block (q22)` plus `Closes #11`.

## Tests

- `RepsTests/CompletionTests` (Unit): Q22 cap (45/30 + 15/30 = 0.75, block still 1.5), surplus doesn't cover a skipped block (0.5), session never exceeds 1; the rest unchanged.
- `RepsTests/SummaryDisplayTests` (Unit, 8 tests): Figma 12 data (subtitle, capped 100 %, caption, rows, surplus bar split, 150 %/117 %, stats incl. avg tempo and net manual fixes), short blocks (45 %, "2 blocks short", partial and empty bars, "under 1 min"), percent never 100 before target, putting (note titles, "putts", blank note falls back), free session (bare counts, tag titles, unused block hidden, "–" tempo, "1 h 5 min"), empty free session, duration, tempo formatting.
- Views: build only + smoke test (no UI test target exists; CLAUDE.md: no tests for layout).

## Placeholders (`// PLACEHOLDER:` in code)

| Where | What ships now |
|---|---|
| `SummaryDisplay.overall` | "N block(s) short" caption suffix |
| `SummaryDisplay.tempo` | "–" when there's no tempo (#27, putting) |
| `SummaryDisplay.duration` | "under 1 min" |

Free-session headline/caption reuse #9's `countDetail` placeholder ("shots"/"putts"). Figma copy used verbatim: "Session done", "Continue session", "Done", "clips saved", "avg tempo", "manual fixes", "every block complete", the footnote, "45 / 30", "3.0 : 1".

After step 3, `grep -rn "PLACEHOLDER:" Reps/Session/SummaryDisplay.swift Reps/UI/Session/SessionSummaryView.swift` lists **3 lines**, and `grep -rn "TODO(#11)\|SummaryPlaceholderView" Reps` lists nothing.

## Risks and unresolved

- **SessionView state after Done.** `showSummary` lives in `SessionView`'s `@State`. The cover's content is rebuilt on each presentation, so the next session should open on the live screen (smoke test checks it). If it opens on the summary, add `.onChange(of: controller.session == nil) { if $1 { showSummary = false } }` to `SessionView` and report.
- **Dim over the summary.** `sessionScreenGuard` wraps the whole `SessionView`, so the summary also dims after 30 s; the first tap wakes it. Accepted: Done/Continue can't fire from a dimmed tap.
- **Detection while the summary shows** (#13): camera shots would still count and the summary would update live. #13 must pause detection while `showSummary` is true (note in #13's plan).
- **Voice** (#10): nothing is spoken on End. If #10 speaks "Done. Session saved." (§5.7), hook it to Done, not End.
- **Figma 112 % vs Q22 100 %**: intentional; recorded in design.md.
- **Manual fixes is net** (Q30).
- **Q25** (decline on resume prompt) is still the owner's call; #11 doesn't change #9's "End it" = resume + finish.
- **Fixed sizes** (88 pt headline) don't scale with Dynamic Type; `minimumScaleFactor(0.5)` covers "100%" on narrow screens.

## Appendix A: logic and tests (verified, copy exactly)

### `Reps/Model/Completion.swift`

```swift
nonisolated struct BlockTally: Equatable, Sendable {
    var counted: Int
    var manualAdjust: Int
    // nil = no target (free session block).
    var target: Int?

    var done: Int { max(0, counted + manualAdjust) }
}

nonisolated enum Completion {
    // Uncapped: 45 of 30 is 1.5. nil without a positive target.
    static func block(_ tally: BlockTally) -> Double? {
        guard let target = tally.target, target > 0 else { return nil }
        return Double(tally.done) / Double(target)
    }

    static func isComplete(_ tally: BlockTally) -> Bool {
        guard let target = tally.target, target > 0 else { return false }
        return tally.done >= target
    }

    // Q22: each block counts at most its target, so surplus on one block never covers another (45/30 + 15/30 = 75 %).
    // Untargeted blocks are ignored.
    static func session(_ tallies: [BlockTally]) -> Double? {
        var done = 0
        var target = 0
        for tally in tallies {
            guard let blockTarget = tally.target, blockTarget > 0 else { continue }
            done += min(tally.done, blockTarget)
            target += blockTarget
        }
        guard target > 0 else { return nil }
        return Double(done) / Double(target)
    }
}
```

### `RepsTests/CompletionTests.swift (whole file after the edit)`

```swift
import Testing

@testable import Reps

struct CompletionTests {
    @Test(arguments: [
        (BlockTally(counted: 30, manualAdjust: 0, target: 30), 1.0),
        (BlockTally(counted: 45, manualAdjust: 0, target: 30), 1.5),
        (BlockTally(counted: 0, manualAdjust: 0, target: 30), 0.0),
        (BlockTally(counted: 28, manualAdjust: 2, target: 30), 1.0),
        (BlockTally(counted: 0, manualAdjust: 15, target: 30), 0.5),
        (BlockTally(counted: 31, manualAdjust: -1, target: 40), 0.75),
    ])
    func blockCompletion(tally: BlockTally, expected: Double) {
        #expect(Completion.block(tally) == expected)
    }

    @Test func negativeNetClampsToZero() {
        let tally = BlockTally(counted: 0, manualAdjust: -2, target: 10)
        #expect(tally.done == 0)
        #expect(Completion.block(tally) == 0)
    }

    @Test(arguments: [nil, 0, -5] as [Int?])
    func noPositiveTargetHasNoCompletion(target: Int?) {
        let tally = BlockTally(counted: 12, manualAdjust: 0, target: target)
        #expect(Completion.block(tally) == nil)
        #expect(Completion.isComplete(tally) == false)
    }

    @Test func completeAtOrOverTarget() {
        #expect(Completion.isComplete(BlockTally(counted: 29, manualAdjust: 0, target: 30)) == false)
        #expect(Completion.isComplete(BlockTally(counted: 29, manualAdjust: 1, target: 30)))
        #expect(Completion.isComplete(BlockTally(counted: 40, manualAdjust: 0, target: 30)))
    }

    // Q22: 45/30 + 15/30 is 75 %, not 100 %; surplus on one block doesn't cover another.
    @Test func sessionCapsEachBlockAtItsTarget() {
        let tallies = [
            BlockTally(counted: 45, manualAdjust: 0, target: 30),
            BlockTally(counted: 10, manualAdjust: 5, target: 30),
        ]
        #expect(Completion.session(tallies) == 0.75)
        #expect(Completion.block(tallies[0]) == 1.5)
    }

    @Test func surplusDoesNotCoverASkippedBlock() {
        let tallies = [
            BlockTally(counted: 60, manualAdjust: 0, target: 30),
            BlockTally(counted: 0, manualAdjust: 0, target: 30),
        ]
        #expect(Completion.session(tallies) == 0.5)
    }

    @Test func skippedBlockCountsAgainstSession() {
        let tallies = [
            BlockTally(counted: 30, manualAdjust: 0, target: 30),
            BlockTally(counted: 0, manualAdjust: 0, target: 10),
        ]
        #expect(Completion.session(tallies) == 0.75)
    }

    @Test func sessionNeverExceedsOne() {
        let tallies = [
            BlockTally(counted: 60, manualAdjust: 0, target: 40),
            BlockTally(counted: 35, manualAdjust: 0, target: 30),
        ]
        #expect(Completion.session(tallies) == 1.0)
    }

    @Test func untargetedBlocksAreIgnored() {
        let tallies = [
            BlockTally(counted: 20, manualAdjust: 0, target: 20),
            BlockTally(counted: 50, manualAdjust: 0, target: nil),
        ]
        #expect(Completion.session(tallies) == 1.0)
    }

    @Test func sessionWithoutTargetsHasNoCompletion() {
        #expect(Completion.session([]) == nil)
        #expect(Completion.session([BlockTally(counted: 50, manualAdjust: 0, target: nil)]) == nil)
    }
}
```

### `Reps/Session/SummaryDisplay.swift`

```swift
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
```

### `RepsTests/SummaryDisplayTests.swift`

```swift
import Foundation
import Testing

@testable import Reps

@MainActor
struct SummaryDisplayTests {
    private func block(
        _ order: Int, _ club: String, done: Int, target: Int?, manual: Int = 0, note: String? = nil,
        tags: [String] = [], clips: Int = 0, tempos: [Double] = []
    ) -> SummaryBlock {
        SummaryBlock(
            order: order, clubName: club, note: note, tags: tags, counted: done - manual, manualAdjust: manual,
            target: target, clipCount: clips, tempos: tempos)
    }

    // Figma 12's blocks: 190 of 170 shots. Q22 caps the headline at 100 %, not Figma's 112 %.
    private var wedgeDay: [SummaryBlock] {
        [
            block(0, "Pitching wedge", done: 40, target: 40, clips: 40, tempos: [3.0, 3.2]),
            block(1, "Gap wedge", done: 45, target: 30, manual: 2, clips: 45, tempos: [2.8]),
            block(2, "Sand wedge", done: 40, target: 40, manual: -1, clips: 40),
            block(3, "Lob wedge", done: 30, target: 30, clips: 30),
            block(4, "9 iron", done: 35, target: 30, clips: 35),
        ]
    }

    @Test func plannedSessionMatchesFigma() {
        let summary = SummaryDisplay.summary(
            planName: "Wedge day", mode: .rangeCounterWithClips, blocks: wedgeDay.reversed(), elapsed: 48 * 60 + 30)
        #expect(summary.subtitle == "Wedge day · Range + clips · 48 min")
        #expect(summary.headline == "100%")
        #expect(summary.caption == "190 of 170 shots · every block complete")
        #expect(summary.rows.map(\.title) == ["Pitching wedge", "Gap wedge", "Sand wedge", "Lob wedge", "9 iron"])
        #expect(summary.rows[1].detail == "45 / 30")
        #expect(summary.rows[1].percent == "150%")
        #expect(summary.rows[1].isOverTarget)
        #expect(summary.rows[1].bar == SummaryBar(fill: 1, surplusFrom: 30.0 / 45.0))
        #expect(summary.rows[4].percent == "117%")
        #expect(summary.rows[0].percent == "100%")
        #expect(!summary.rows[0].isOverTarget)
        #expect(summary.rows[0].bar == SummaryBar(fill: 1, surplusFrom: nil))
        #expect(
            summary.stats == [
                SummaryStat(value: "190", label: "clips saved"),
                SummaryStat(value: "3.0 : 1", label: "avg tempo"),
                SummaryStat(value: "3", label: "manual fixes"),
            ])
    }

    @Test func shortBlocksLowerTheHeadline() {
        let blocks = [
            block(0, "PW", done: 45, target: 30),
            block(1, "GW", done: 15, target: 30),
            block(2, "SW", done: 0, target: 40),
        ]
        let summary = SummaryDisplay.summary(planName: "Wedge day", mode: .rangeCounter, blocks: blocks, elapsed: 0)
        #expect(summary.headline == "45%")
        #expect(summary.caption == "60 of 100 shots · 2 blocks short")
        #expect(summary.rows[1].bar == SummaryBar(fill: 0.5, surplusFrom: nil))
        #expect(summary.rows[2].percent == "0%")
        #expect(summary.rows[2].bar == SummaryBar(fill: 0, surplusFrom: nil))
        #expect(summary.subtitle == "Wedge day · Range · under 1 min")
    }

    @Test func percentNeverShowsHundredBeforeTarget() {
        #expect(SummaryDisplay.percent(299.0 / 300.0, isComplete: false) == "99%")
        #expect(SummaryDisplay.percent(1.0, isComplete: true) == "100%")
        #expect(SummaryDisplay.percent(35.0 / 30.0, isComplete: true) == "117%")
        #expect(SummaryDisplay.percent(1.0 / 3.0, isComplete: false) == "33%")
        let caption = SummaryDisplay.overall([block(0, "PW", done: 29, target: 30)], mode: .rangeCounter).caption
        #expect(caption == "29 of 30 shots · 1 block short")
    }

    @Test func puttingUsesNotesAndPutts() {
        let blocks = [
            block(0, "Putter", done: 30, target: 30, note: "3 ft"),
            block(1, "Putter", done: 12, target: 30, note: " "),
        ]
        let summary = SummaryDisplay.summary(planName: "Lag", mode: .putting, blocks: blocks, elapsed: 600)
        #expect(summary.rows.map(\.title) == ["3 ft", "Putter"])
        #expect(summary.caption == "42 of 60 putts · 1 block short")
        #expect(summary.subtitle == "Lag · Putting · 10 min")
    }

    @Test func freeSessionShowsCountsWithoutTargets() {
        let blocks = [
            block(0, "7 iron", done: 12, target: nil),
            block(1, "7 iron", done: 8, target: nil, manual: 8, tags: ["fade", "low"]),
            block(2, "PW", done: 0, target: nil),
        ]
        let summary = SummaryDisplay.summary(planName: nil, mode: .rangeCounter, blocks: blocks, elapsed: 3900)
        #expect(summary.subtitle == "Free session · Range · 1 h 5 min")
        #expect(summary.headline == "20")
        #expect(summary.caption == "shots")
        #expect(summary.rows.map(\.title) == ["7 iron", "7 iron · fade, low"])
        #expect(summary.rows[0].detail == "12")
        #expect(summary.rows[0].percent == nil)
        #expect(summary.rows[0].bar == nil)
        #expect(summary.stats[1].value == "–")
        #expect(summary.stats[2].value == "8")
    }

    @Test func emptyFreeSession() {
        let summary = SummaryDisplay.summary(
            planName: nil, mode: .putting, blocks: [block(0, "Putter", done: 0, target: nil)], elapsed: 0)
        #expect(summary.headline == "0")
        #expect(summary.caption == "putts")
        #expect(summary.rows.isEmpty)
    }

    @Test func duration() {
        #expect(SummaryDisplay.duration(-5) == "under 1 min")
        #expect(SummaryDisplay.duration(59) == "under 1 min")
        #expect(SummaryDisplay.duration(60) == "1 min")
        #expect(SummaryDisplay.duration(59 * 60 + 59) == "59 min")
        #expect(SummaryDisplay.duration(2 * 3600) == "2 h")
        #expect(SummaryDisplay.duration(3600 + 12 * 60) == "1 h 12 min")
    }

    @Test func tempo() {
        #expect(SummaryDisplay.tempo([]) == "–")
        #expect(SummaryDisplay.tempo([3.0]) == "3.0 : 1")
        #expect(SummaryDisplay.tempo([2.9, 3.3]) == "3.1 : 1")
    }
}
```

## Appendix B: views (type-checked, copy exactly)

### `Reps/UI/Session/SummaryTheme.swift`

```swift
import SwiftUI

// Figma 12 values; the file has no variables.
extension Theme.Typography {
    static let summaryHeadline = Font.system(size: 88, weight: .bold, design: .rounded)
    static let summaryHeadlineTracking: CGFloat = -2.64
    static let summarySubtitle = Font.subheadline
    static let summaryCaption = Font.subheadline.weight(.medium)
    static let summaryRowTitle = Font.subheadline.weight(.semibold)
    static let summaryRowPercent = Font.system(size: 14, weight: .semibold)
    static let summaryStatValue = Font.title3.weight(.semibold)
    static let summaryStatLabel = Font.caption
}

extension Theme.Radius {
    static let stat: CGFloat = 14
}
```

### `Reps/UI/Components/SecondaryButtonStyle.swift`

```swift
import SwiftUI

// Full-width grey CTA (Continue session, Figma 12).
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.cta)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.cta))
            .contentShape(.rect(cornerRadius: Theme.Radius.cta))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
```

### `Reps/UI/Session/SessionSummaryView.swift`

```swift
import SwiftData
import SwiftUI

// Figma 12. Shown in place of the session screen on End; the session stays active until Done (F23, F28).
struct SessionSummaryView: View {
    let summary: SessionSummary
    let onContinue: () -> Void
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                overall
                if !summary.rows.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(summary.rows) { SummaryRowView(row: $0) }
                    }
                }
                HStack(alignment: .top, spacing: 10) {
                    ForEach(summary.stats) { SummaryStatView(stat: $0) }
                }
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.top, 24)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) { footer }
        .background(Theme.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(SummaryDisplay.title)
                .font(Theme.Typography.largeTitle)
                .foregroundStyle(Theme.ink)
            Text(summary.subtitle)
                .font(Theme.Typography.summarySubtitle)
                .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private var overall: some View {
        VStack(spacing: 2) {
            Text(summary.headline)
                .font(Theme.Typography.summaryHeadline)
                .tracking(Theme.Typography.summaryHeadlineTracking)
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(summary.caption)
                .font(Theme.Typography.summaryCaption)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.card))
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Text(SummaryDisplay.footnote)
                .font(Theme.Typography.summaryStatLabel)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Button("Continue session", action: onContinue)
                .buttonStyle(SecondaryButtonStyle())
            Button("Done", action: onDone)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Theme.background)
    }
}

private struct SummaryRowView: View {
    let row: SummaryRow

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title)
                    .font(Theme.Typography.summaryRowTitle)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    Text(row.detail)
                        .foregroundStyle(Theme.secondaryText)
                    if let percent = row.percent {
                        Text(percent)
                            .font(Theme.Typography.summaryRowPercent)
                            .foregroundStyle(row.isOverTarget ? Theme.accent : Theme.ink)
                    }
                }
                .font(Theme.Typography.detail)
                .monospacedDigit()
            }
            if let bar = row.bar {
                SummaryBarView(bar: bar)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// 6 pt track: accent up to the target, darker surplus past it (Figma 12).
private struct SummaryBarView: View {
    let bar: SummaryBar

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.card)
                Capsule().fill(Theme.accent).frame(width: width * bar.fill)
                if let from = bar.surplusFrom {
                    Capsule().fill(Theme.accentDeep)
                        .frame(width: width * (1 - from))
                        .offset(x: width * from)
                }
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

private struct SummaryStatView: View {
    let stat: SummaryStat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stat.value)
                .font(Theme.Typography.summaryStatValue)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(stat.label)
                .font(Theme.Typography.summaryStatLabel)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 12)
        .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.stat))
        .accessibilityElement(children: .combine)
    }
}

extension SummaryBlock {
    init(_ result: BlockResult) {
        self.init(
            order: result.order, clubName: result.clubName, note: result.block?.note, tags: result.tags,
            counted: result.repsCounted, manualAdjust: result.repsManualAdjust, target: result.targetReps,
            clipCount: result.shots.count { $0.clipFileName != nil }, tempos: result.shots.compactMap(\.tempoRatio))
    }
}

#Preview {
    SessionSummaryView(
        summary: SummaryDisplay.summary(
            planName: "Wedge day", mode: .rangeCounterWithClips,
            blocks: [
                SummaryBlock(
                    order: 0, clubName: "Pitching wedge", note: nil, tags: [], counted: 40, manualAdjust: 0,
                    target: 40, clipCount: 40, tempos: [3.0]),
                SummaryBlock(
                    order: 1, clubName: "Gap wedge", note: nil, tags: [], counted: 42, manualAdjust: 3, target: 30,
                    clipCount: 45, tempos: []),
                SummaryBlock(
                    order: 2, clubName: "9 iron", note: nil, tags: [], counted: 12, manualAdjust: 0, target: 30,
                    clipCount: 12, tempos: []),
            ],
            elapsed: 48 * 60),
        onContinue: {}, onDone: {})
}
```

### `Reps/UI/Session/SessionView.swift` (three edits to #9's file)

1. In `body`, replace

```swift
            if let session = controller.session {
                content(session)
            } else {
```

with

```swift
            if let session = controller.session {
                if showSummary {
                    summary(session)
                        .transition(.move(edge: .bottom))
                } else {
                    content(session)
                }
            } else {
```

2. Replace the whole `.sheet(isPresented: $showSummary) { SummaryPlaceholderView(...) }` modifier (the last one in `body`) with nothing, and add this method right after `body`:

```swift
    // F23/F28: End shows the summary in place; the session stays active until Done, and a kill here still resumes.
    private func summary(_ session: PracticeSession) -> some View {
        TimelineView(.periodic(from: session.startedAt, by: 60)) { context in
            SessionSummaryView(
                summary: SummaryDisplay.summary(
                    planName: session.planName, mode: session.mode, blocks: controller.blocks.map(SummaryBlock.init),
                    elapsed: context.date.timeIntervalSince(session.startedAt)),
                onContinue: { withAnimation { showSummary = false } },
                // finish() clears the session, which closes the session cover with the summary still showing.
                onDone: { controller.finish() }
            )
        }
    }
```

3. In `header(_:)`, replace `Button("End") { showSummary = true }` with `Button("End") { withAnimation { showSummary = true } }`.

## Appendix C: code-reference entries

Replace the `Completion.session` line under `Reps/Model/Completion.swift` with:

```
- `Completion.session(_:) -> Double?`: Σ min(done, target) / Σ target over targeted blocks (Q22: surplus never covers another block, max 1.0); nil if none
```

Delete the `Reps/UI/Session/SummaryPlaceholderView.swift` entry. In the `SessionView` entry, change "End → summary placeholder" to "End → summary in place (Continue session / Done)".

Add after the `Reps/Session/SessionDisplay.swift` entry:

```
## Reps/Session/SummaryDisplay.swift
Numbers and copy for the session summary (Figma 12, F23); pure values, unit-tested.
- `SummaryBlock(order:clubName:note:tags:counted:manualAdjust:target:clipCount:tempos:)`, `SummaryBar(fill:surplusFrom:)`, `SummaryRow`, `SummaryStat`, `SessionSummary(subtitle:headline:caption:rows:stats:)`
- `SummaryDisplay.summary(planName:mode:blocks:elapsed:)`: rows by order (free sessions hide unused blocks, add tags to titles); `overall(_:mode:)` (capped %, or total count without targets); `row(_:mode:isFree:)`; `percent(_:isComplete:)` (rounded, ≤ 99 % until complete); `stats(_:)` (clips, avg tempo, Σ |manualAdjust|); `tempo(_:)`; `duration(_:)`
```

Add after the `Reps/UI/Session/SessionView.swift` entry:

```
## Reps/UI/Session/SessionSummaryView.swift
Figma 12. Shown by `SessionView` on End.
- `SessionSummaryView(summary:onContinue:onDone:)`: header, overall card, block rows with target/surplus bars, three stats, footnote, Continue session / Done
- `SummaryBlock.init(_ result: BlockResult)`

## Reps/UI/Session/SummaryTheme.swift
Summary values from Figma 12: `Theme.Typography.summaryHeadline` (88 rounded bold), `summaryHeadlineTracking`, `summarySubtitle`, `summaryCaption`, `summaryRowTitle`, `summaryRowPercent`, `summaryStatValue`, `summaryStatLabel`; `Theme.Radius.stat`.

## Reps/UI/Components/SecondaryButtonStyle.swift
- `SecondaryButtonStyle`: full-width grey CTA (Continue session)
```

Add `accentDeep` (0x1E4A36, surplus bar) to the `Reps/UI/Theme/Theme.swift` entry's colour list.

Add after the last test entry:

```
## RepsTests/SummaryDisplayTests.swift
Summary headline (Q22-capped), captions, rows and bars, percent rounding, putting and free sessions, stats, duration, tempo.
```
