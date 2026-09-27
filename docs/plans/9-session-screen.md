# #9 Session screen (manual counting)

Goal: the live session screen. It shows a big count with +1/−1, the nav (End, plan title, mode · angle, elapsed clock), the block strip, the club chip and tag chips, and Next block with the "move on early?" prompt. It keeps the display awake and dims it after 30 s. The plans list's Start buttons open it, and a session left active by a kill gets a "Resume session?" prompt at launch. Manual counting works on its own: the camera area is a placeholder until #13.

Spec: F7 (+1/−1), F14 (free session, club chip), F16 (tags until removed), F18 (block strip jumps), F22 (strict), F28 (Next block before target asks first; only Done finishes), §5.3c ("Session screen keeps the display awake and dims after 30 s; any tap restores it."), §6 ("App killed mid-session … reopens with a 'resume?' prompt"). ADRs: 0006, 0009 (synced folders, MainActor default), 0013 (controller rules; no enum-captured `#Predicate`, so use `SessionController.activeSession(in:)`). Q25.

Figma (file `pMKE8PoWxIEotHas0rmQX1`): 03 Live session, range + clips `3:2`; 05 Putting session `4:2`; 14 Live session, next block early `13:150`. There are no Figma variables, so the values below are literals read off the layers.

**Depends on #7 being merged** (`Theme`, `PrimaryButtonStyle`, `ClubPicker`, `ClubChoices`, `PlanSummary`, `PracticeMode.title`, `PlansView(onStartPlan:onStartFreeSession:)`, `PreviewData`, `LibraryPlaceholderView`). Rebase `feat/9-session-screen` on `main` after #7 lands. If any of those names differ from `docs/plans/7-plans-screens.md`, stop and report.

How this was checked: `SessionDisplay` and its tests (Appendix A) were built in a scratch SwiftPM package (Swift 6.4, `defaultIsolation(MainActor)`, with the real `ModelEnums.swift`, `Completion.swift` and #7's `PlanSummary` and `PracticeMode+Title`). **10 tests in 1 suite passed.** Every file in Appendix A and B was then type-checked together with the real `Reps/Model`, `Reps/Persistence`, `Reps/Session` and all of #7's Appendix A/B files (`swiftc -typecheck`, iOS 26.0 simulator target, iPhoneSimulator 27.0 SDK, `-default-isolation MainActor`, `-DDEBUG`), and the result was clean. `swift-format lint --strict` with the repo's `.swift-format` was also clean. The views have not been built by Xcode or run. **Copy every file exactly.**

Out of scope: voice (#10: `TODO(#10)` where the speaker subscribes), the summary and the rest of accident-proofing (#11: End opens a placeholder with Done / Keep going), camera preview and detection (#13/#15), clips (#22), tempo (#27), default angle and Settings (#6), error UI beyond one alert (#29).

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Controller ownership | `RootView` makes one `SessionController(context: modelContext)` lazily, the first time a session starts or resumes, and keeps it in `@State`. The controller holds at most one session, and `finish()`/`discard()` reset it. | One writer for the whole app (ADR 0013). The voice layer (#10) subscribes to it in one place. |
| Presentation | `RootView` shows `.fullScreenCover` while `controller.session != nil`. It reads the value in `body` and passes `Binding(get: { isInSession }, set: { _ in })`. Nothing dismisses the cover directly: Done calls `finish()`, which clears `session`, and the cover closes. | A full-screen cover can't be swiped away. The session state is the only source of truth, so the cover and the store can't disagree. |
| Start hooks (#7) | `onStartPlan` → `controller.start(plan:cameraAngle: .faceOn)`. `onStartFreeSession` → `startFree(mode: .rangeCounter, cameraAngle: .faceOn, clubName: <first in-bag club, else "7 iron">)`. A throw (for example `.sessionInProgress`) shows the alert "Couldn't start the session." | #6 owns the default angle (`TODO(#6)`). Nothing chooses a free-session mode yet, so Range is a placeholder (new Q28). |
| Resume at launch (§6, Q25) | `RootView.task` → `SessionController.activeSession(in:)`. If one is found, the alert "Resume session?" shows "`<title>` · `<n> shots` so far." with **Resume** (`resume`, the cover opens) and **End it** (`resume` then `finish` = **Q25 planner default: keep the session**, marked in code). Only on the first appearance of `RootView`. | §6 requires the prompt, and without it `start` would throw `.sessionInProgress` forever after a kill. The Q25 default follows the leaning in open-questions (ADR 0006 already saved every shot). |
| End | "End" opens `SummaryPlaceholderView` as a sheet (`interactiveDismissDisabled`). **Done** → `controller.finish()`. **Keep going** closes the sheet. | F23/F28 say only Done saves. #11 replaces the placeholder (`TODO(#11)`). |
| Next block (Figma 14, F28) | Shown only in planned sessions with an active block. If `done < target`, a native `.alert` titled "Move on at 12 of 30?" shows "`<club>` will stay at 40% for this session." plus " You can come back to it from the block strip." when `canSelectBlocks`. The buttons are **Stay** (cancel) and **Next block** (`advance()`, `.keyboardShortcut(.defaultAction)` so it's the bold preferred action as in Figma). At or past target, it calls `advance()` directly. The percentage uses integer floor (`done*100/target`). | Frame 14 is assigned to #9 in `docs/design.md`, and `SessionController.advance` says "the UI confirms first". This is the only F28 piece built here. It is contained in `requestNextBlock()` and the first `.alert` in `SessionView`, so it's easy to move to #11 if the owner wants. |
| Block strip (F18) | Planned sessions only. Chip states: **active** (accent bg, white title, `onAccentSecondary` detail), **complete** (`fill` bg, both texts `secondaryText`), **pending** (`card` bg, `ink` title, `secondaryText` detail). The detail is `done/target`. A chip is tappable only when `SessionDisplay` says so, which mirrors `SessionController.select`: the session isn't free, the order isn't mandatory, it isn't the active chip, and it isn't a finished strict block. Non-selectable chips use `.allowsHitTesting(false)` rather than `.disabled`, so the active chip isn't greyed out. The strip scrolls horizontally and centres the active chip. | Figma 03/05. |
| Strip titles | The chip uses `clubName`, except in putting, where it uses the block's note when there is one ("3 ft", "6 ft", "9 ft" in Figma 05, where all blocks are "Putter"). The note comes from `BlockResult.block?.note`, so it's lost if the plan block was deleted. | Figma 05. |
| Chip row (F14, F16) | Range modes only (Figma 05 has no chip row). It shows: the club chip (filled; tappable only in a free session, where it opens `FreeClubSheet` → `setClub`), then the tag chips (active ones filled, others outlined) from `SessionDisplay.tagChoices(active:recent:)`, then "+ tag" (outlined) → an alert with a TextField → `SessionDisplay.adding` → `setTags`. Tapping a tag toggles it (`SessionDisplay.toggling` → `setTags`). Recent tags come from the 20 newest sessions (`@Query` sorted by `startedAt` desc, blocks newest first), capped at 8. | Figma 03 shows "Gap wedge" filled and "fade" / "+ tag" outlined. Tags last until removed (F16), and the controller carries them across blocks. |
| Count area | The big count is `block.tally.done` in SF Pro Rounded bold 132 with tracking −5.28, `monospacedDigit`, `.numericText` transition. Below it, `SessionDisplay.countDetail`: "of 30", putting adds the note ("of 30 · 6 ft"), and a free block (no target) shows "shot"/"shots"/"putts" (placeholder). The tempo line from Figma 03 is `TODO(#27)`. With no active block (the plan has ended), it shows "All blocks done" / "Pick a block from the strip, or tap End." (placeholders). | Figma 03/05. |
| +1 / −1 (F7) | `recordShot(source: .manual)` / `minusOne()`. +1 is disabled when there's no active block. −1 is always enabled because the controller no-ops at zero and can undo into a block that just auto-advanced. Both are 64 pt tall `fill` buttons with radius 18, 28 pt semibold. | Figma 03. The controller owns every rule. |
| Nav | A custom header, not a navigation bar. "End" on the left (16 regular, secondary, 44 pt target). Centre: title (plan name or "Free session") in 16 semibold, and the subtitle `SessionDisplay.subtitle` ("Range + clips · face-on", "Range · down-the-line", "Putting counter") in 12. Right: elapsed time since `startedAt` ("12:40", "1:02:03") from a 1 s `TimelineView`. | Figma 03/05. "12:40" and "19:05" next to a 9:41 status bar can only be elapsed time. |
| Camera area | `// PLACEHOLDER: camera preview (#13)`: a `fill` rounded rect (radius 20) with a "Camera" label, 190 pt tall in range modes and 150 in putting, with 20 pt side padding. | The frame's size, but not its green mock. |
| Keep awake (§5.3c) | `UIApplication.shared.isIdleTimerDisabled = true` in `onAppear` of the session screen, `false` in `onDisappear`. | Context7 (UIKit docs): not deprecated. |
| Dim (§5.3c) | The spec says: "Session screen keeps the display awake and dims after 30 s; any tap restores it." This plan uses an **in-app black overlay at 0.8 opacity** after 30 s without a tap (`SessionDisplay.dimDelay`). The first tap on the overlay only wakes the screen (it never reaches +1), and every tap restarts the 30 s timer (`simultaneousGesture(TapGesture())` on the screen). System brightness (`UIScreen.brightness`) is **not** touched. | Context7 (UIKit): `brightness` is still settable, but `UIScreen.main` is deprecated, and "brightness changes remain in effect until the person locks their device, even if the person closes your app". So a crash or kill would leave the phone dim. On the OLED iPhone 17 Pro, black pixels save power anyway. §5.6's "brightness low" belongs to #28 (thermal/battery). New Q29 records this. |
| View model | `SessionDisplay` (Appendix A) turns plain values (`BlockSnapshot`) into copy, chip states and prompts, and it is unit-tested. The views only read the controller and call its methods. | CLAUDE.md: test logic, not layout. |
| Theme | New values go in `Reps/UI/Session/SessionTheme.swift` as extensions on `Theme.Typography` / `Theme.Radius`, so #7's `Theme.swift` isn't touched: `count` (132 rounded bold), `countTracking` −5.28, `countDetail` (`.body`, 17), `manualButton` (28 semibold), `stripTitle` (`.subheadline` semibold, 15), `stripDetail` (`.caption2` medium, 11), `navSubtitle` (`.caption`, 12); `Radius.stripChip` 14, `Radius.preview` 20. Everything else reuses #7 tokens (`rowTitle` 16 semibold, `body` 16, `chip`/`chipSelected` 14, `Radius.cta` 18, `Spacing.gutter` 20, `rowGap` 8). | Figma values. The file has no variables. |

## Figma geometry (for the smoke test)

Frames 03/05 top to bottom: nav `px 20, py 6`; block strip `pt 10, pb 4` (putting `py 10`), gap 8, chip `px 14, py 8`, radius 14, VStack spacing 1; chip row `pt 6, pb 10`, gap 8, capsule chip `px 14, py 9`, outline 1.5 pt `#D9D8D3`; preview 190 (putting 150) × full width minus 40, radius 20; count area fills the rest, centred; manual buttons `gap 12, pb 12`, 64 tall, radius 18; footer CTA `px 20`, 18 pt vertical padding (from `PrimaryButtonStyle`), then the safe area. Frame 14: a native alert with Stay | **Next block**, both in accent.

## Final layout

```
Reps/Session/SessionDisplay.swift             new: BlockSnapshot, StripChipState, StripChip, NextBlockPrompt, SessionDisplay
Reps/UI/Session/SessionTheme.swift            new: Theme.Typography / Theme.Radius extensions
Reps/UI/Session/SessionView.swift             new: SessionView, ManualCountButtonStyle (private), BlockSnapshot.init(_:), #Preview
Reps/UI/Session/BlockStrip.swift              new: BlockStrip, StripChipLabel (private)
Reps/UI/Session/SessionScreenGuard.swift      new: keep-awake + dim modifier, View.sessionScreenGuard()
Reps/UI/Session/FreeClubSheet.swift           new
Reps/UI/Session/SummaryPlaceholderView.swift  new (TODO(#11))
Reps/UI/Components/CapsuleChip.swift          new
Reps/App/RootView.swift                       replaced: controller, Start hooks, session cover, resume prompt
RepsTests/SessionDisplayTests.swift           new (10 tests)
docs/code-reference.md, docs/design.md, docs/open-questions.md, docs/roadmap.md   updated
```

Never edit `project.pbxproj`: the folders are synced (ADR 0009), so new files are picked up.

## Steps

Branch `feat/9-session-screen` from `main` after #7 is merged. Run everything from the repo root:

```sh
DEST27='platform=iOS Simulator,id=A26BAE3A-CDDE-45A8-892D-2359740C877A'   # iPhone 17 Pro, iOS 27
DEST265='platform=iOS Simulator,id=6D2623EF-0394-46F9-BFEC-022E3D2B7FE8'  # iPhone 17 Pro, iOS 26.5
```

Before each commit, run `xcrun swift-format format --in-place --recursive --parallel Reps RepsTests`. After it, `xcrun swift-format lint --strict --recursive --parallel Reps RepsTests` must print nothing.

### Step 1: display logic (TDD)

1. Create `RepsTests/SessionDisplayTests.swift` (Appendix A). Run
   `xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan Unit -destination "$DEST27" -only-testing:RepsTests/SessionDisplayTests` → it fails to compile.
2. Create `Reps/Session/SessionDisplay.swift` (Appendix A). Run the same command → **10 tests in 1 suite pass**.
3. `git add -A && git commit -m "added session display logic" -m "Refs #9"`

### Step 2: session components

1. Create `SessionTheme.swift`, `BlockStrip.swift`, `SessionScreenGuard.swift`, `FreeClubSheet.swift`, `SummaryPlaceholderView.swift` (in `Reps/UI/Session/`) and `Reps/UI/Components/CapsuleChip.swift` (Appendix B).
2. Build: `xcodebuild build -project Reps.xcodeproj -scheme Reps -destination "$DEST27" -quiet` → succeeds with no new warnings.
3. `git add -A && git commit -m "added session screen components" -m "Refs #9"`

### Step 3: session screen and wiring

1. Create `Reps/UI/Session/SessionView.swift` and replace `Reps/App/RootView.swift` (Appendix B). The new `RootView` keeps #7's tabs, tab icons and `// PLACEHOLDER` comments unchanged, and replaces the two `TODO(#9)` closures.
2. Build (same command). Then run the full Unit plan on **both** simulators:
   `xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan Unit -destination "$DEST27"` and the same with `"$DEST265"` → both `** TEST SUCCEEDED **`, with #7's count + 10 tests. The iOS 26.5 run matters because `activeSession(in:)` and the `@Query`s run there (ADR 0013).
3. Manual smoke test on the iOS 27 simulator (the views are new and have never been run):
   - Start "Wedge day" (or any plan with ≥ 3 blocks). The screen matches Figma 03 (apart from the camera placeholder). Tap +1 three times and −1 once → 2.
   - Tap Next block before target → the frame 14 alert. Stay keeps the block. Next block moves on and the strip highlights the next chip. Tap the earlier chip → it's active again (free order).
   - Add a tag with "+ tag", then toggle it off and on. Tag chips fill and outline.
   - Wait 30 s without touching → the screen dims. The first tap only wakes it (the count doesn't change). Tap +1 → it counts. Check that tapping +1 restarts the 30 s timer (see Risks).
   - End → placeholder → Keep going returns. End → Done → back on the Plans tab, and "Last done today" on the card.
   - Free session → a club chip with the first bag club. Tap it → the sheet → pick a club → the chip changes. No strip, no Next block, "shots" under the count.
   - Putting plan → Figma 05: no chip row, strip titles from notes, "of 30 · 6 ft".
   - Start a session, add a few shots, stop the app in Xcode and relaunch → "Resume session?" with the right count. Resume → same block and count. Repeat and choose **End it** → no cover, and the plan card shows "Last done today".
   - Strict plan: reach the target → it auto-advances, and the finished chip can't be tapped.
4. `git add -A && git commit -m "added session screen" -m "Refs #9"`

### Step 4: docs

1. `docs/code-reference.md`: apply Appendix C. Replace the `Reps/App/RootView.swift` entry. Add the `Reps/Session/SessionDisplay.swift` entry after `Reps/Session/SessionEvent.swift` (or wherever the Session entries end), and the `Reps/UI/Session/*` and `CapsuleChip` entries after #7's UI entries. Add the test entry after the last test entry.
2. `docs/design.md`: under the Session (live) row's section, add below the table: `- Session screen (#9): tokens in \`Reps/UI/Session/SessionTheme.swift\`; dim is an in-app black overlay (0.8) after 30 s, not system brightness (Q29). Camera area is a placeholder until #13.`
3. `docs/open-questions.md`: add to the Open table (use the next free numbers; Q27 is #7's):
   - `| Q28 | Free session start: which mode (and club) does "Free session" start in? #9 starts Range with the first bag club. | – (#9 ships Range) | Options: a small mode sheet before start, or the last-used mode. Leaning: last-used mode, stored in Settings (#6). |`
   - `| Q29 | Dim (§5.3c): in-app black overlay (shipped in #9) or lower system brightness (§5.6 "brightness low")? | #28 | System brightness persists after the app closes until the phone locks (UIKit docs), so it must be restored on background/kill. Leaning: keep the overlay; revisit in #28 if battery tests say otherwise. |`
   - In Q25's row, append to Notes: `#9 ships the leaning: "End it" in the launch prompt calls resume + finish.`
4. `docs/roadmap.md`: #9 status ☐ → ☑ (in the PR commit, when the issue closes).
5. `git add -A && git commit -m "documented session screen" -m "Refs #9"`

No review (the issue has neither review label). Push, then open a PR titled `added session screen` with a one-line body (`manual counting, block strip, tags, keep awake + dim, resume prompt`) plus `Closes #9`.

## Tests

`Unit` plan, `RepsTests/SessionDisplayTests` (Appendix A, 10 tests): title/subtitle (free, the angles, putting), count detail (target, putting note, blank note, free singular/plural, putts), strip chips (states, details, selectability in free order / strict / locked / plan ended, putting note titles), Next block prompt (copy, the locked-order message, floor %, nil at/over target, nil without a target or with target 0), elapsed formatting (0, sub-second, mm:ss, h:mm:ss, negative), tag choices (active first, trim, dedupe, limit), toggling/adding tags, resume message.

Controller behaviour is already covered by #8's `SessionControllerTests`, `FreeSessionTests` and `SessionResumeTests`. Views, dim and keep-awake: build only plus the smoke test (CLAUDE.md: session-flow UI tests are for accident-proofing, which is #11).

## Placeholders (`// PLACEHOLDER:` in code)

| Where | What ships now |
|---|---|
| `SessionView` camera area | `fill` rounded rect with "Camera" (#13) |
| `SessionDisplay.countDetail`, free block | "shot" / "shots" / "putt" / "putts" |
| `SessionView`, no active block | "All blocks done" and "Pick a block from the strip, or tap End." |
| `SessionView` new-tag alert | title "New tag", field "e.g. fade", buttons Cancel / Add |
| `SessionScreenGuard.dimOpacity` | 0.8 black overlay |
| `FreeClubSheet` title | "Club" |
| `FreeClubSheet` custom club alert | "Club name" / Cancel / Use (same as #7) |
| `SummaryPlaceholderView` | `ContentUnavailableView("Session summary", …, "The full summary is coming.")` with Done / Keep going (#11) |
| `RootView` resume alert | "Resume session?" and message `SessionDisplay.resumeMessage` ("Wedge day · 42 shots so far."), buttons Resume / "End it" |
| `RootView` start error | "Couldn't start the session." / OK (#29) |
| `RootView` free-session start | Range mode (Q28), first in-bag club, else "7 iron" |
| `RootView` tab icons | unchanged from #7 (2 lines) |

Figma copy used verbatim: End, "Range + clips · face-on", "Putting counter", "of 30", "of 30 · 6 ft", −1, +1, Next block, "+ tag", "Move on at 12 of 30?", "`<club>` will stay at 40% for this session. You can come back to it from the block strip.", Stay. "Free session" comes from #7's card. "Keep going" and "Done" come from F23.

`grep -rn "PLACEHOLDER:" Reps/UI/Session Reps/UI/Components/CapsuleChip.swift Reps/Session Reps/App/RootView.swift` should list **17 lines** (15 new, plus #7's 2 tab icons). `grep -rn "TODO(#" Reps/App Reps/UI/Session` should list `TODO(#10)`, `TODO(#22)`, `TODO(#6)` ×2, `TODO(#11)` and `TODO(#27)`, and no `TODO(#9)`.

## Risks and unresolved

- **Tap-to-reset the dim timer.** `simultaneousGesture(TapGesture())` on the whole screen should fire alongside button taps. If the smoke test shows that +1/−1 taps don't restart the timer, the screen will dim 30 s after the last *non-button* tap. Then report it. Don't add per-button hooks without asking.
- **`.keyboardShortcut(.defaultAction)` in an alert** should make "Next block" the bold preferred action. If it doesn't show bold on iOS 26/27, accept the system look.
- **"End it" in the resume prompt** calls `resume` then `finish`. Once #10 subscribes the speaker, `resume` emits `.blockChanged`, which would be spoken just before the session ends. #10 must either ignore events while no session screen is visible or get a `finish`-without-resume path in the controller. This is noted for #10.
- **The cover closing with the summary sheet open.** Done → `finish()` closes the full-screen cover while its sheet is still presented. SwiftUI normally tears both down. If it logs "attempt to dismiss while presenting" or leaves a blank sheet, set `showSummary = false` first and call `finish()` in the sheet's `onDismiss`.
- **The Next-block alert is built here (Figma 14 is mapped to #9), although F28 is otherwise #11.** The caller asked to leave accident-proofing out, so if the owner prefers it in #11, delete the first `.alert` and call `controller.advance()` directly in `requestNextBlock()`. The `SessionDisplay.nextBlockPrompt` tests stay useful either way.
- **Putting has no chip row** (Figma 05), so there are no tags in putting sessions. F16 says "while recording", and putting doesn't record. Add it back if the owner wants putting tags.
- **Club chip vs strip names.** Figma shows "Gap wedge" in the chip and "GW" in the strip. Both use `clubName` here, so they show whatever the plan stored.
- **Recent tags** read the 20 newest sessions via `@Query` (all sessions are fetched, then `prefix(20)`). That's fine at personal scale. #24 may replace it with Q23's tag model.
- **Fixed sizes** (132, 28, 14) don't scale with Dynamic Type. The count uses `minimumScaleFactor(0.5)` for 3-digit counts on small screens.
- `lastSaveError` from the controller isn't shown (#29).

## Appendix A: logic and tests (verified, copy exactly)

### `Reps/Session/SessionDisplay.swift`

```swift
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
```

### `RepsTests/SessionDisplayTests.swift`

```swift
import Foundation
import Testing

@testable import Reps

@MainActor
struct SessionDisplayTests {
    @Test func titleAndSubtitle() {
        #expect(SessionDisplay.title(planName: "Wedge day") == "Wedge day")
        #expect(SessionDisplay.title(planName: nil) == "Free session")
        #expect(SessionDisplay.subtitle(mode: .rangeCounterWithClips, angle: .faceOn) == "Range + clips · face-on")
        #expect(SessionDisplay.subtitle(mode: .rangeCounter, angle: .downTheLine) == "Range · down-the-line")
        #expect(SessionDisplay.subtitle(mode: .rangeCounter, angle: .none) == "Range")
        #expect(SessionDisplay.subtitle(mode: .putting, angle: .faceOn) == "Putting counter")
    }

    @Test func countDetail() {
        #expect(SessionDisplay.countDetail(done: 12, target: 30, note: "95 m", mode: .rangeCounterWithClips) == "of 30")
        #expect(SessionDisplay.countDetail(done: 17, target: 30, note: "6 ft", mode: .putting) == "of 30 · 6 ft")
        #expect(SessionDisplay.countDetail(done: 17, target: 30, note: "  ", mode: .putting) == "of 30")
        #expect(SessionDisplay.countDetail(done: 17, target: 30, note: nil, mode: .putting) == "of 30")
        #expect(SessionDisplay.countDetail(done: 1, target: nil, note: nil, mode: .rangeCounter) == "shot")
        #expect(SessionDisplay.countDetail(done: 0, target: nil, note: nil, mode: .rangeCounter) == "shots")
        #expect(SessionDisplay.countDetail(done: 3, target: nil, note: nil, mode: .putting) == "putts")
    }

    private let wedgeDay = [
        BlockSnapshot(order: 0, clubName: "PW", note: "110 m", done: 40, target: 40),
        BlockSnapshot(order: 1, clubName: "GW", note: nil, done: 12, target: 30),
        BlockSnapshot(order: 2, clubName: "SW", note: nil, done: 0, target: 40),
        BlockSnapshot(order: 3, clubName: "9i", note: nil, done: 45, target: 30),
    ]

    @Test func stripChipsFreeOrder() {
        let chips = SessionDisplay.stripChips(
            wedgeDay, mode: .rangeCounterWithClips, activeOrder: 1, canSelect: true, isStrict: false)
        #expect(chips.map(\.id) == [0, 1, 2, 3])
        #expect(chips.map(\.title) == ["PW", "GW", "SW", "9i"])
        #expect(chips.map(\.detail) == ["40/40", "12/30", "0/40", "45/30"])
        #expect(chips.map(\.state) == [.complete, .active, .pending, .complete])
        #expect(chips.map(\.isSelectable) == [true, false, true, true])
    }

    @Test func stripChipsStrictAndLocked() {
        let strict = SessionDisplay.stripChips(
            wedgeDay, mode: .rangeCounter, activeOrder: 1, canSelect: true, isStrict: true)
        #expect(strict.map(\.isSelectable) == [false, false, true, false])
        let locked = SessionDisplay.stripChips(
            wedgeDay, mode: .rangeCounter, activeOrder: 1, canSelect: false, isStrict: false)
        #expect(locked.allSatisfy { !$0.isSelectable })
        let ended = SessionDisplay.stripChips(
            wedgeDay, mode: .rangeCounter, activeOrder: nil, canSelect: true, isStrict: false)
        #expect(!ended.contains { $0.state == .active })
        #expect(ended.map(\.isSelectable) == [true, true, true, true])
    }

    @Test func stripChipsPuttingUseNotes() {
        let blocks = [
            BlockSnapshot(order: 0, clubName: "Putter", note: "3 ft", done: 30, target: 30),
            BlockSnapshot(order: 1, clubName: "Putter", note: " ", done: 17, target: 30),
        ]
        let chips = SessionDisplay.stripChips(blocks, mode: .putting, activeOrder: 1, canSelect: true, isStrict: false)
        #expect(chips.map(\.title) == ["3 ft", "Putter"])
        #expect(SessionDisplay.blockTitle(clubName: "GW", note: "95 m", mode: .rangeCounter) == "GW")
    }

    @Test func nextBlockPrompt() {
        let prompt = SessionDisplay.nextBlockPrompt(clubName: "Gap wedge", done: 12, target: 30, canComeBack: true)
        #expect(prompt?.title == "Move on at 12 of 30?")
        #expect(
            prompt?.message
                == "Gap wedge will stay at 40% for this session. You can come back to it from the block strip.")
        let locked = SessionDisplay.nextBlockPrompt(clubName: "GW", done: 29, target: 30, canComeBack: false)
        #expect(locked?.message == "GW will stay at 96% for this session.")
        #expect(SessionDisplay.nextBlockPrompt(clubName: "GW", done: 30, target: 30, canComeBack: true) == nil)
        #expect(SessionDisplay.nextBlockPrompt(clubName: "GW", done: 45, target: 30, canComeBack: true) == nil)
        #expect(SessionDisplay.nextBlockPrompt(clubName: "GW", done: 3, target: nil, canComeBack: true) == nil)
        #expect(SessionDisplay.nextBlockPrompt(clubName: "GW", done: 0, target: 0, canComeBack: true) == nil)
    }

    @Test func elapsed() {
        #expect(SessionDisplay.elapsed(0) == "0:00")
        #expect(SessionDisplay.elapsed(59.9) == "0:59")
        #expect(SessionDisplay.elapsed(760) == "12:40")
        #expect(SessionDisplay.elapsed(3723) == "1:02:03")
        #expect(SessionDisplay.elapsed(36000) == "10:00:00")
        #expect(SessionDisplay.elapsed(-5) == "0:00")
    }

    @Test func tagChoices() {
        let choices = SessionDisplay.tagChoices(
            active: ["fade", " fade "], recent: ["gate drill", "fade", " ", "draw", "gate drill"])
        #expect(choices == ["fade", "gate drill", "draw"])
        let capped = SessionDisplay.tagChoices(active: ["low"], recent: ["a", "b", "c", "d"], limit: 2)
        #expect(capped == ["low", "a", "b"])
    }

    @Test func togglingAndAddingTags() {
        #expect(SessionDisplay.toggling("fade", in: ["fade", "draw"]) == ["draw"])
        #expect(SessionDisplay.toggling("low", in: ["fade"]) == ["fade", "low"])
        #expect(SessionDisplay.adding("  low ", to: ["fade"]) == ["fade", "low"])
        #expect(SessionDisplay.adding("fade", to: ["fade"]) == nil)
        #expect(SessionDisplay.adding("   ", to: []) == nil)
    }

    @Test func resumeMessage() {
        #expect(
            SessionDisplay.resumeMessage(title: "Wedge day", done: 42, mode: .rangeCounter)
                == "Wedge day · 42 shots so far.")
        #expect(
            SessionDisplay.resumeMessage(title: "Free session", done: 1, mode: .putting)
                == "Free session · 1 putt so far.")
    }
}
```

## Appendix B: views (type-checked, copy exactly)

### `Reps/UI/Session/SessionTheme.swift`

```swift
import SwiftUI

// Session screen values from Figma 03, 05 and 14.
extension Theme.Typography {
    static let count = Font.system(size: 132, weight: .bold, design: .rounded)
    static let countTracking: CGFloat = -5.28
    static let countDetail = Font.body
    static let manualButton = Font.system(size: 28, weight: .semibold)
    static let stripTitle = Font.subheadline.weight(.semibold)
    static let stripDetail = Font.caption2.weight(.medium)
    static let navSubtitle = Font.caption
}

extension Theme.Radius {
    static let stripChip: CGFloat = 14
    static let preview: CGFloat = 20
}
```

### `Reps/UI/Components/CapsuleChip.swift`

```swift
import SwiftUI

// Capsule chip for the session club and tags (Figma 03); filled when selected, read-only without an action.
struct CapsuleChip: View {
    let title: String
    let isSelected: Bool
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { label }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            label
        }
    }

    private var label: some View {
        Text(title)
            .font(isSelected ? Theme.Typography.chipSelected : Theme.Typography.chip)
            .foregroundStyle(isSelected ? Color.white : Theme.secondaryText)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                if isSelected {
                    Capsule().fill(Theme.accent)
                } else {
                    Capsule().strokeBorder(Theme.hairline, lineWidth: 1.5)
                }
            }
            .contentShape(.capsule)
    }
}
```

### `Reps/UI/Session/BlockStrip.swift`

```swift
import SwiftUI

// Horizontal block chips under the nav (Figma 03, 05); tapping a selectable chip jumps to that block (F18).
struct BlockStrip: View {
    let chips: [StripChip]
    let onSelect: (Int) -> Void

    private var activeID: Int? { chips.first { $0.state == .active }?.id }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.rowGap) {
                    ForEach(chips) { chip in
                        Button {
                            onSelect(chip.id)
                        } label: {
                            StripChipLabel(chip: chip)
                        }
                        .buttonStyle(.plain)
                        // Not .disabled: that would grey out the active chip.
                        .allowsHitTesting(chip.isSelectable)
                        .accessibilityAddTraits(chip.state == .active ? .isSelected : [])
                        .id(chip.id)
                    }
                }
                .padding(.horizontal, Theme.Spacing.gutter)
            }
            .onChange(of: activeID, initial: true) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }
}

private struct StripChipLabel: View {
    let chip: StripChip

    var body: some View {
        VStack(spacing: 1) {
            Text(chip.title)
                .font(Theme.Typography.stripTitle)
                .foregroundStyle(titleColor)
            Text(chip.detail)
                .font(Theme.Typography.stripDetail)
                .foregroundStyle(detailColor)
                .monospacedDigit()
        }
        .lineLimit(1)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(background, in: .rect(cornerRadius: Theme.Radius.stripChip))
        .accessibilityElement(children: .combine)
    }

    private var background: Color {
        switch chip.state {
        case .active: Theme.accent
        case .complete: Theme.fill
        case .pending: Theme.card
        }
    }

    private var titleColor: Color {
        switch chip.state {
        case .active: .white
        case .complete: Theme.secondaryText
        case .pending: Theme.ink
        }
    }

    private var detailColor: Color {
        chip.state == .active ? Theme.onAccentSecondary : Theme.secondaryText
    }
}
```

### `Reps/UI/Session/SessionScreenGuard.swift`

```swift
import SwiftUI
import UIKit

// §5.3c: keeps the display awake while the session screen is up and dims it after 30 s without a touch.
// The first tap on a dimmed screen only wakes it, so a gloved tap can't hit +1 by accident.
private struct SessionScreenGuard: ViewModifier {
    // PLACEHOLDER: dim strength (black overlay; the spec gives no level)
    static let dimOpacity = 0.8

    @State private var isDimmed = false
    @State private var touches = 0

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(TapGesture().onEnded { touches += 1 })
            .overlay {
                if isDimmed {
                    Color.black
                        .opacity(Self.dimOpacity)
                        .ignoresSafeArea()
                        .contentShape(.rect)
                        .onTapGesture { wake() }
                        .accessibilityLabel("Screen dimmed")
                        .accessibilityHint("Tap to wake")
                        .accessibilityAddTraits(.isButton)
                        .transition(.opacity)
                }
            }
            .task(id: touches) {
                try? await Task.sleep(for: SessionDisplay.dimDelay)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.6)) { isDimmed = true }
            }
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func wake() {
        withAnimation(.easeInOut(duration: 0.2)) { isDimmed = false }
        touches += 1
    }
}

extension View {
    func sessionScreenGuard() -> some View {
        modifier(SessionScreenGuard())
    }
}
```

### `Reps/UI/Session/FreeClubSheet.swift`

```swift
import SwiftData
import SwiftUI

// F14: the free session's club chip. Picking a club closes the sheet; the controller starts a new block.
struct FreeClubSheet: View {
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\BagClub.sortOrder), SortDescriptor(\BagClub.name)]) private var clubs: [BagClub]
    @State private var selection: String
    @State private var askCustomClub = false
    @State private var customClubName = ""

    init(current: String, onPick: @escaping (String) -> Void) {
        self.onPick = onPick
        _selection = State(initialValue: current)
    }

    private var bagNames: [String] { clubs.filter(\.isInBag).map(\.name) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.sheetGap) {
                Text("Club")  // PLACEHOLDER: free-session club sheet title
                    .font(Theme.Typography.sheetTitle)
                    .foregroundStyle(Theme.ink)
                ClubPicker(
                    names: ClubChoices.names(bag: bagNames, current: selection),
                    selection: $selection,
                    onCustom: {
                        customClubName = ""
                        askCustomClub = true
                    }
                )
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.top, 20)
        }
        .onChange(of: selection) { _, club in
            onPick(club)
            dismiss()
        }
        .alert("Club name", isPresented: $askCustomClub) {  // PLACEHOLDER: custom club alert copy (same as #7)
            TextField("Club name", text: $customClubName)
            Button("Cancel", role: .cancel) {}
            Button("Use") {
                let name = customClubName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { selection = name }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.sheet)
        .presentationCornerRadius(Theme.Radius.sheet)
    }
}
```

### `Reps/UI/Session/SummaryPlaceholderView.swift`

```swift
import SwiftUI

// TODO(#11): replace with the session summary (Figma 12, F23). Only Done finishes the session (F28).
struct SummaryPlaceholderView: View {
    let onKeepGoing: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.sectionGap) {
            ContentUnavailableView(
                "Session summary",
                systemImage: "checkmark.circle",
                description: Text("The full summary is coming.")  // PLACEHOLDER: summary screen (#11)
            )
            .frame(maxHeight: .infinity)
            Button("Done", action: onDone)
                .buttonStyle(PrimaryButtonStyle())
            Button("Keep going", action: onKeepGoing)
                .font(Theme.Typography.cta)
                .foregroundStyle(Theme.accent)
                .padding(.vertical, 12)
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.bottom, 8)
        .background(Theme.background)
        .interactiveDismissDisabled()
    }
}
```

### `Reps/UI/Session/SessionView.swift`

```swift
import SwiftData
import SwiftUI

// Figma 03 (range), 05 (putting), 14 (next block early). Manual counting only; the camera arrives with #13.
struct SessionView: View {
    let controller: SessionController

    @Query(sort: \PracticeSession.startedAt, order: .reverse) private var sessions: [PracticeSession]
    @State private var nextPrompt: NextBlockPrompt?
    @State private var showSummary = false
    @State private var pickingClub = false
    @State private var askNewTag = false
    @State private var newTag = ""

    var body: some View {
        Group {
            // Nil for a moment while the cover animates away after finish().
            if let session = controller.session {
                content(session)
            } else {
                Theme.background.ignoresSafeArea()
            }
        }
        .sessionScreenGuard()
        .alert(
            nextPrompt?.title ?? "",
            isPresented: Binding(get: { nextPrompt != nil }, set: { if !$0 { nextPrompt = nil } }),
            presenting: nextPrompt
        ) { _ in
            Button("Stay", role: .cancel) {}
            Button("Next block") { controller.advance() }
                .keyboardShortcut(.defaultAction)
        } message: { prompt in
            Text(prompt.message)
        }
        .alert("New tag", isPresented: $askNewTag) {  // PLACEHOLDER: new-tag alert copy
            TextField("e.g. fade", text: $newTag)
            Button("Cancel", role: .cancel) {}
            Button("Add") {
                if let tags = SessionDisplay.adding(newTag, to: controller.activeTags) { controller.setTags(tags) }
            }
        }
        .sheet(isPresented: $pickingClub) {
            FreeClubSheet(current: controller.activeBlock?.clubName ?? "") { controller.setClub($0) }
        }
        .sheet(isPresented: $showSummary) {
            SummaryPlaceholderView(
                onKeepGoing: { showSummary = false },
                // finish() clears the session, which closes the session cover and this sheet with it.
                onDone: { controller.finish() }
            )
        }
    }

    private func content(_ session: PracticeSession) -> some View {
        VStack(spacing: 0) {
            header(session)
            if !controller.isFreeSession {
                BlockStrip(chips: stripChips(session), onSelect: select)
                    .padding(.top, 10)
                    .padding(.bottom, showsChipRow(session) ? 4 : 10)
            }
            if showsChipRow(session) {
                chipRow
                    .padding(.top, controller.isFreeSession ? 10 : 6)
                    .padding(.bottom, 10)
            }
            // PLACEHOLDER: camera preview (#13)
            RoundedRectangle(cornerRadius: Theme.Radius.preview)
                .fill(Theme.fill)
                .overlay {
                    Label("Camera", systemImage: "camera")
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(height: session.mode == .putting ? 150 : 190)
                .padding(.horizontal, Theme.Spacing.gutter)
            count(session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            manualControls
            if !controller.isFreeSession && controller.activeBlock != nil {
                Button("Next block", action: requestNextBlock)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, Theme.Spacing.gutter)
                    .padding(.bottom, 8)
            }
        }
        .background(Theme.background)
    }

    private func header(_ session: PracticeSession) -> some View {
        ZStack {
            VStack(spacing: 1) {
                Text(SessionDisplay.title(planName: session.planName))
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.ink)
                Text(SessionDisplay.subtitle(mode: session.mode, angle: session.cameraAngle))
                    .font(Theme.Typography.navSubtitle)
                    .foregroundStyle(Theme.secondaryText)
            }
            .lineLimit(1)
            .padding(.horizontal, 72)
            HStack {
                Button("End") { showSummary = true }
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.secondaryText)
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .contentShape(.rect)
                Spacer()
                TimelineView(.periodic(from: session.startedAt, by: 1)) { context in
                    Text(SessionDisplay.elapsed(context.date.timeIntervalSince(session.startedAt)))
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.secondaryText)
                        .monospacedDigit()
                }
                .accessibilityLabel("Elapsed time")
            }
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.vertical, 6)
    }

    // Figma 05 has no chip row: putting uses one club and records no clips.
    private func showsChipRow(_ session: PracticeSession) -> Bool {
        session.mode != .putting
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.rowGap) {
                if let block = controller.activeBlock {
                    CapsuleChip(
                        title: block.clubName,
                        isSelected: true,
                        action: controller.isFreeSession ? { pickingClub = true } : nil
                    )
                }
                ForEach(SessionDisplay.tagChoices(active: controller.activeTags, recent: recentTags), id: \.self) {
                    tag in
                    CapsuleChip(title: tag, isSelected: controller.activeTags.contains(tag)) {
                        controller.setTags(SessionDisplay.toggling(tag, in: controller.activeTags))
                    }
                }
                CapsuleChip(title: "+ tag", isSelected: false) {
                    newTag = ""
                    askNewTag = true
                }
            }
            .padding(.horizontal, Theme.Spacing.gutter)
        }
    }

    @ViewBuilder
    private func count(_ session: PracticeSession) -> some View {
        if let block = controller.activeBlock {
            let done = block.tally.done
            VStack(spacing: 0) {
                Text("\(done)")
                    .font(Theme.Typography.count)
                    .tracking(Theme.Typography.countTracking)
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: done)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(
                    SessionDisplay.countDetail(
                        done: done, target: block.targetReps, note: block.block?.note, mode: session.mode)
                )
                .font(Theme.Typography.countDetail)
                .foregroundStyle(Theme.secondaryText)
                // TODO(#27): tempo row ("tempo 3.1 : 1", Figma 03) goes here, 14 pt below the detail line.
            }
            .accessibilityElement(children: .combine)
        } else {
            VStack(spacing: 6) {
                Text("All blocks done")  // PLACEHOLDER: no block left to run
                    .font(Theme.Typography.value)
                    .foregroundStyle(Theme.ink)
                Text("Pick a block from the strip, or tap End.")  // PLACEHOLDER: no block left hint
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private var manualControls: some View {
        HStack(spacing: 12) {
            Button("−1") { controller.minusOne() }
                .accessibilityLabel("Minus one")
            Button("+1") { controller.recordShot(source: .manual) }
                .accessibilityLabel("Plus one")
                .disabled(controller.activeBlock == nil)
        }
        .buttonStyle(ManualCountButtonStyle())
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.bottom, 12)
    }

    private var recentTags: [String] {
        sessions.prefix(20).flatMap { $0.sortedBlockResults.reversed().flatMap(\.tags) }
    }

    private func stripChips(_ session: PracticeSession) -> [StripChip] {
        SessionDisplay.stripChips(
            controller.blocks.map(BlockSnapshot.init),
            mode: session.mode,
            activeOrder: controller.activeBlock?.order,
            canSelect: controller.canSelectBlocks,
            isStrict: controller.isStrictCount
        )
    }

    private func select(order: Int) {
        guard let block = controller.blocks.first(where: { $0.order == order }) else { return }
        controller.select(block)
    }

    private func requestNextBlock() {
        guard let block = controller.activeBlock else { return }
        if let prompt = SessionDisplay.nextBlockPrompt(
            clubName: block.clubName, done: block.tally.done, target: block.targetReps,
            canComeBack: controller.canSelectBlocks)
        {
            nextPrompt = prompt
        } else {
            controller.advance()
        }
    }
}

// Big grey −1 / +1 (Figma 03: 64 pt tall, radius 18).
private struct ManualCountButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.manualButton)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(Theme.fill, in: .rect(cornerRadius: Theme.Radius.cta))
            .contentShape(.rect(cornerRadius: Theme.Radius.cta))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}

extension BlockSnapshot {
    init(_ result: BlockResult) {
        self.init(
            order: result.order, clubName: result.clubName, note: result.block?.note, done: result.tally.done,
            target: result.targetReps)
    }
}

#if DEBUG
    #Preview {
        let container = PreviewData.container()
        let controller = SessionController(context: container.mainContext)
        let plan = try! container.mainContext.fetch(FetchDescriptor<PracticePlan>()).first { $0.name == "Wedge day" }!
        try! controller.start(plan: plan, cameraAngle: .faceOn)
        return SessionView(controller: controller)
            .modelContainer(container)
    }
#endif
```

### `Reps/App/RootView.swift`

```swift
import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\BagClub.sortOrder), SortDescriptor(\BagClub.name)]) private var clubs: [BagClub]
    @State private var sessions: SessionController?
    @State private var pendingResume: PracticeSession?
    @State private var startFailed = false

    var body: some View {
        let isInSession = sessions?.session != nil
        TabView {
            Tab("Plans", systemImage: "list.bullet.rectangle") {  // PLACEHOLDER: Plans tab icon
                PlansView(onStartPlan: start(plan:), onStartFreeSession: startFree)
            }
            Tab("Library", systemImage: "film.stack") {  // PLACEHOLDER: Library tab icon
                LibraryPlaceholderView()
            }
        }
        .tint(Theme.accent)
        // Driven by the controller: finish() or discard() clears the session and closes the cover.
        .fullScreenCover(isPresented: Binding(get: { isInSession }, set: { _ in })) {
            if let sessions { SessionView(controller: sessions) }
        }
        .task { offerResume() }
        .alert(
            "Resume session?",  // PLACEHOLDER: resume prompt copy
            isPresented: Binding(get: { pendingResume != nil }, set: { if !$0 { pendingResume = nil } }),
            presenting: pendingResume
        ) { saved in
            Button("Resume") { resume(saved) }
            Button("End it") { endWithoutResuming(saved) }  // PLACEHOLDER: decline button copy
        } message: { saved in
            Text(
                SessionDisplay.resumeMessage(
                    title: SessionDisplay.title(planName: saved.planName),
                    done: saved.blockResults.reduce(0) { $0 + $1.tally.done },
                    mode: saved.mode))
        }
        .alert("Couldn't start the session.", isPresented: $startFailed) {  // PLACEHOLDER: start error copy (#29)
            Button("OK", role: .cancel) {}
        }
    }

    // One controller for the app's lifetime; it holds at most one session at a time.
    private func controller() -> SessionController {
        if let sessions { return sessions }
        let made = SessionController(context: modelContext)
        // TODO(#10): subscribe the speaker here, e.g. made.addEventHandler { speaker.handle($0) }.
        // TODO(#22): pass the real ClipFileRemoving once clips exist.
        sessions = made
        return made
    }

    private func start(plan: PracticePlan) {
        do {
            // TODO(#6): use the default camera angle from Settings.
            try controller().start(plan: plan, cameraAngle: .faceOn)
        } catch {
            startFailed = true
        }
    }

    private func startFree() {
        let club = clubs.first(where: \.isInBag)?.name ?? "7 iron"  // PLACEHOLDER: free-session club with an empty bag
        do {
            // PLACEHOLDER: free sessions start in Range mode until there's a mode choice (Q28). TODO(#6): default angle.
            try controller().startFree(mode: .rangeCounter, cameraAngle: .faceOn, clubName: club)
        } catch {
            startFailed = true
        }
    }

    // §6: an active session found at launch (the app was killed) gets a "resume?" prompt.
    private func offerResume() {
        guard sessions?.session == nil else { return }
        pendingResume = try? SessionController.activeSession(in: modelContext)
    }

    private func resume(_ saved: PracticeSession) {
        do {
            try controller().resume(saved)
        } catch {
            startFailed = true
        }
    }

    // Q25 (planner default, unconfirmed): declining keeps the session as finished; delete it from the log later.
    private func endWithoutResuming(_ saved: PracticeSession) {
        let controller = controller()
        do {
            try controller.resume(saved)
            controller.finish()
        } catch {
            startFailed = true
        }
    }
}

#Preview {
    RootView()
        .modelContainer(PreviewData.container())
}
```

## Appendix C: code-reference entries

Replace the `Reps/App/RootView.swift` entry with:

```
## Reps/App/RootView.swift
Root TabView (Plans, Library) and the session host.
- `RootView`: owns one `SessionController` (made on first use); Start hooks call `start(plan:cameraAngle:)` / `startFree(...)`; full-screen `SessionView` while `controller.session != nil`; launch "Resume session?" via `activeSession(in:)` (Resume, or "End it" = resume + finish, Q25 default); voice hook is `TODO(#10)`
```

Add after the last `Reps/Session/*` entry:

```
## Reps/Session/SessionDisplay.swift
Copy and chip states for the session screen; pure values, unit-tested.
- `BlockSnapshot(order:clubName:note:done:target:)`, `StripChip` (`id` = block order, `state` active/complete/pending, `isSelectable`), `NextBlockPrompt(title:message:)`
- `SessionDisplay`: `dimDelay` (30 s), `title(planName:)`, `subtitle(mode:angle:)`, `angleTitle(_:)`, `blockTitle(clubName:note:mode:)` (putting uses the note), `countDetail(done:target:note:mode:)`, `stripChips(_:mode:activeOrder:canSelect:isStrict:)` (mirrors `SessionController.select`), `nextBlockPrompt(clubName:done:target:canComeBack:)` (nil at/over target), `elapsed(_:)`, `tagChoices(active:recent:limit:)`, `toggling(_:in:)`, `adding(_:to:)`, `resumeMessage(title:done:mode:)`
```

Add after #7's UI entries:

```
## Reps/UI/Session/SessionView.swift
Figma 03, 05, 14. The live session; reads and drives a `SessionController`.
- `SessionView(controller:)`: nav (End → summary placeholder, title, mode · angle, elapsed), block strip (planned), club + tag chips (range modes), camera placeholder (#13), big count, −1/+1, Next block (asks first before target)
- `BlockSnapshot.init(_ result: BlockResult)`

## Reps/UI/Session/BlockStrip.swift
- `BlockStrip(chips:onSelect:)`: horizontal block chips, centres the active one; only selectable chips take taps

## Reps/UI/Session/SessionScreenGuard.swift
- `View.sessionScreenGuard()`: idle timer off while visible; black overlay after 30 s without a tap, first tap only wakes (§5.3c)

## Reps/UI/Session/FreeClubSheet.swift
- `FreeClubSheet(current:onPick:)`: bag club grid (`ClubPicker`) plus Other…; a pick closes the sheet (F14)

## Reps/UI/Session/SummaryPlaceholderView.swift
- `SummaryPlaceholderView(onKeepGoing:onDone:)`: stand-in until #11; Done finishes the session

## Reps/UI/Session/SessionTheme.swift
Session values from Figma: `Theme.Typography.count` (132 rounded bold), `countTracking`, `countDetail`, `manualButton`, `stripTitle`, `stripDetail`, `navSubtitle`; `Theme.Radius.stripChip`, `preview`.

## Reps/UI/Components/CapsuleChip.swift
- `CapsuleChip(title:isSelected:action:)`: capsule chip, filled when selected, read-only without an action (session club and tags)
```

Add after the last test entry:

```
## RepsTests/SessionDisplayTests.swift
Session copy, strip chip states and selectability, Next block prompt, elapsed clock, tag choices, resume message.
```
