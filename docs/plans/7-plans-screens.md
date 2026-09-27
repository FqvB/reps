# #7 Plans list + plan editor

Goal: the Plans tab. It lists plans (with a free-session card), creates, edits, duplicates and deletes them, and has a plan editor with blocks, mode, "Order is mandatory" and "Strict count" toggles, drag to reorder, swipe to delete with an undo toast, and a discard alert. This is the first screen issue, so it also adds the shared UI foundation (`Reps/UI/Theme`, shared components, and the root `TabView`) that later screens reuse.

Spec: F1, F18, F19 (club picker reads the bag), F22, F24, F28 (discard alert, block-delete undo), §5.3c (plan swipe Duplicate/Delete with delete confirmation, 5 s undo toast). ADRs: 0004 (local SwiftData), 0009 (synced folders, MainActor default), 0012 (model), 0013 (no enum-captured `#Predicate`; filter enums in Swift).

Figma (file `pMKE8PoWxIEotHas0rmQX1`): 01 Plans `1:2`, 02 Plan editor `2:2`, 06 Block editor sheet `4:35`, 13 Discard alert `13:56`. The file has no variables or styles, so every value below is a literal read off the layers.

Every logic file and test in **Appendix A** was built by the planner in a scratch SwiftPM package (macOS 26, Swift 6, `defaultIsolation(MainActor)`, with the real `Reps/Model/*` and `RepsStore.swift` copied in). **24 tests in 4 suites passed**, and `swift-format lint --strict` with the repo's `.swift-format` was clean. The view files in **Appendix B** were then added, together with Appendix A, to a scratch clone of this branch. There, `xcodebuild test -testPlan Unit` on the iPhone 17 Pro simulator (iOS 26 SDK, Xcode 27) passed **109 tests in 11 suites** (85 existing + 24 new), and `swift-format lint --strict -r Reps RepsTests` was clean. The only warning was the existing `SessionControllerTests.swift:103` unused `plan`. **Copy every file in both appendices exactly.** The view code was built but not run: the manual smoke test in Step 4 is the first time anyone sees it on screen.

Out of scope: starting a session (the Start buttons call closures, and `RootView` leaves `TODO(#9)`), Settings (`TODO(#6)`), bag management and the default bag (#5, #6), the Library tab (placeholder until #24), the session block strip (#9), and error UI beyond a simple alert (#29).

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Editing model | The editor works on a value-type `PlanDraft` (with `BlockDraft` rows). Nothing touches SwiftData until **Save plan**, which calls `PlanLibrary.save(_:to:in:)`. Cancel just dismisses. | Discard, undo and reorder become pure value logic that can be tested. A half-edited plan is never visible to a running session. |
| Discard detection (F28) | `hasChanges = draft != original`, where `original` is the draft built when the editor opened. It uses `Equatable` on the draft, with no flags. Moving a block and moving it back, or removing and undoing, counts as unchanged. | This is the simplest correct rule. It's tested in `changesAreDetected`. |
| Block delete + undo (F24, §5.3c) | Swipe → `draft.removeBlock(id:)` returns a `RemovedBlock(block, index)` that is held in `@State lastRemoved`. A custom `UndoToast` shows "`<club>` removed · Undo" for **5 s** (`UndoToast.duration`). Undo calls `draft.restore(_:)`, which reinserts the block at its old index, clamped. A newer delete replaces the toast, and the older one stays deleted. The block-sheet **Remove** button uses the same path. | iOS has no system "undo toast", and the Figma frame 02 draws one (node `13:342`). Because the draft isn't saved, undo needs no `UndoManager` and nothing reaches the store. |
| Reorder (F1) | `ForEach(draft.blocks).onMove { draft.moveBlocks(fromOffsets:toOffset:) }` in a plain `List`. Long-press drag works without edit mode. The "≡" in Figma is a visual handle only. `moveBlocks` copies SwiftUI's semantics but is written without SwiftUI so the draft stays `nonisolated` and testable. | `Array.move(fromOffsets:)` lives in SwiftUI. It isn't in Foundation (checked). |
| Persisting order | `PlanLibrary.save` renumbers `order` as `0..<n` from the draft's array order. Kept blocks keep their `id` and `PlanBlock` object, so `BlockResult.block` links survive edits. New blocks get the draft's `id`. Removed blocks are `context.delete`d, and their results keep the club/target snapshot (nullify, ADR 0012). | Tested: `saveEditsInPlaceAndRenumbers`, `removedBlockIsDeletedAndResultsKeepTheirSnapshot`. |
| Save validity | `canSave`: the trimmed name is non-empty, there is **at least one block**, and every block has a non-blank club and `targetReps` in `1...999`. The Save and Done buttons are disabled otherwise. The name and club are trimmed on save, and a blank note is saved as `nil`. | `SessionController.start` throws `.emptyPlan` for a plan without blocks, so an empty plan can't be started. |
| Duplicate (§5.3c) | `PlanLibrary.duplicate(_:in:now:)` makes a new plan named `"<name> copy"`, with the same mode and flags and `createdAt = now`. Its blocks are new objects (new ids), copied from `sortedBlocks` and renumbered `0..<n`. Sessions aren't copied. It saves immediately. | Tested: `duplicateDeepCopiesBlocksInOrder` (including gappy orders 0/5/9). The name suffix is a placeholder (see list). |
| Delete plan (§5.3c) | Swipe → **Delete** sets `planToDelete`, then an `.alert` asks "Delete `<name>`?". On confirm, `PlanLibrary.delete`. Sessions survive with `planName` (nullify), and blocks cascade. The swipe button has **no** `.destructive` role and uses `.tint(Theme.danger)`. | A destructive-role swipe button starts the row-removal animation before the confirmation. The tint gives the same red. |
| Plans list order | `@Query(sort: \PracticePlan.createdAt)`, oldest first. A duplicate lands at the bottom. | Figma doesn't say. See Q27. |
| "Last done" | `PlanLibrary.lastDone(plan)` returns the newest `endedAt ?? startedAt` of the plan's **finished** sessions, filtered in Swift (ADR 0013). `PlanSummary.lastDone` formats it: `Last done today` / `Last done Mon` (1–6 days ago) / `Last done Sep 9` (same year) / `Last done Sep 9, 2025`. If there's none, the placeholder `Not done yet`. It uses the device locale and `.current` calendar. | Matches Figma ("Last done Mon", "Last done Sep 9"). |
| Editor presentation | `.fullScreenCover(item:)` from the list: tapping a plan card's text opens it for editing, and "New plan" opens it empty. Inside is a `NavigationStack` with an inline title ("Edit plan" / "New plan"), a text **Cancel** in `.cancellationAction`, and **Save plan** as the footer CTA. | Frame 02 is full screen with Cancel/title chrome and no sheet card. A full-screen cover can't be swiped away, so the discard alert is the only way out with changes. |
| Block editor | `.sheet(item: $editingBlock)` with `.presentationDetents([.large])`, `.presentationDragIndicator(.visible)`, `.presentationBackground(Theme.sheet)` and `.presentationCornerRadius(32)`. It edits a local copy. **Done** hands it back through `draft.upsert`. Dragging it down drops that block's edits, with no alert (the plan-level alert still guards the plan). A new block exists only after Done. | Frame 06 (sheet, grabber, radius 32, `#F6F5F2`). |
| Club picker (F19) | A 4-column `LazyVGrid` of `Chip`s over `ClubChoices.names(bag:current:)`. The bag is `@Query` `BagClub` sorted by `sortOrder, name`, then filtered `isInBag` in Swift. A club that isn't in the bag (custom, or removed later) is shown as an extra chip. The last chip, **Other…**, opens an `.alert` with a `TextField` for a custom-named club. With an empty bag, a one-line hint appears above the chips. | F19: "only these clubs, plus custom-named clubs". Bag setup is #5/#6. |
| Reps stepper | −10 / value / +10 big buttons, then −5 −1 +1 +5 outline pills, each calling `BlockDraft.adjustReps(by:)` (clamped to `1...999`). A button is disabled when it can't move the value. A new block defaults to 30 reps and an empty club. | Frame 06. |
| Native vs custom | Native: `TabView`/`Tab`, the navigation bar (large title "Plans", `navigationSubtitle` date, "Settings" toolbar button), segmented `Picker` for the mode, `Toggle`, `List` swipe actions, `.alert`s (discard, delete, custom club, save error). Custom: plan cards, the free-session card, block rows, dashed add buttons, chips, the stepper, the footer CTA, the toast. | figma-swiftui guidance: use system controls when the design is clearly one. The Figma segmented control, toggles, alert and tab bar are the stock patterns redrawn. Liquid Glass defaults are fine. |
| Start hooks | `PlansView(onStartPlan: (PracticePlan) -> Void, onStartFreeSession: () -> Void)`. `RootView` passes closures whose bodies are `// TODO(#9): start a session`. Start is disabled for a plan with no blocks. | #9 owns the session screen. |
| Theme | `Reps/UI/Theme/Theme.swift`: colours, fonts, spacing and radii as static members (below). Fonts use Dynamic Type text styles wherever the Figma size equals the default text-style size (34/22/20/17/16/15/13/12). Only 18, 14 and 64 are fixed. | The design stays exact at the default size, and most text still scales. |

## Theme values (from Figma)

Colours (hex, sRGB, opaque):

| Token | Hex | Used for |
|---|---|---|
| `Theme.background` | `#FFFFFF` | screen background |
| `Theme.ink` | `#17181A` | primary text; toast background |
| `Theme.secondaryText` | `#6F7175` | subtitles, labels, Cancel, unselected segment |
| `Theme.accent` | `#2F6B4F` | brand green: free-session card, CTAs, selected chip, block count, links, tab tint |
| `Theme.onAccentSecondary` | `#CFE3D8` | free-session card subtitle |
| `Theme.card` | `#F2F2F0` | plan cards, block rows, fields, toggle rows, unselected chips |
| `Theme.fill` | `#E9E8E3` | Start pill on plan cards, segment track, big stepper buttons |
| `Theme.hairline` | `#D9D8D3` | dashed borders, outline pills, "≡" and "›" glyphs, grabber, alert dividers |
| `Theme.sheet` | `#F6F5F2` | block editor sheet background |
| `Theme.danger` | `#D0463D` | swipe Delete, alert Discard |
| `Theme.dangerText` | `#B3413A` | "Remove" link in the block sheet |
| `Theme.toastAction` | `#9FD3B7` | toast "Undo" |

Also in Figma, but not tokens: the sheet dim `rgba(23,24,26,0.35)` and alert dim `rgba(0,0,0,0.35)`, both drawn by the system.

Type (`Theme.Typography`; the size is SF Pro at the default Dynamic Type size):

| Token | Definition | Figma use |
|---|---|---|
| `largeTitle` | `.largeTitle.bold()` (34) | "Plans" (drawn by the nav bar) |
| `value` | `.title2.weight(.semibold)` (22) | plan name field value, block row count |
| `sheetTitle` | `.title3.bold()` (20) | "Block 2" |
| `cardTitleLarge` | `.title3.weight(.semibold)` (20) | "Free session" |
| `cardTitle` | `.system(size: 18, weight: .semibold)` | plan card name |
| `cta` | `.headline` (17 semibold) | Save plan / Done |
| `rowTitle` | `.callout.weight(.semibold)` (16) | block club, toggle titles |
| `body` | `.callout` (16) | note value |
| `pill` | `.subheadline.weight(.semibold)` (15) | Start pills, Remove, swipe labels |
| `detail` | `.system(size: 14)` | card subtitles |
| `chip` | `.system(size: 14, weight: .medium)` | club chips, fine-step pills, toast message |
| `chipSelected` | `.system(size: 14, weight: .semibold)` | selected chip, toast Undo |
| `footnote` | `.footnote` (13) | block row detail, toggle subtitles, "Last done" |
| `footnoteMedium` | `.footnote.weight(.medium)` (13) | "Blocks" header, "Club"/"Shots" labels |
| `label` | `.caption.weight(.medium)` (12) | "Plan name", "Note (optional)" field labels |
| `stepperValue` | `.system(size: 64, weight: .bold, design: .rounded)`, tracking `-1.92` | reps value |
| `stepperButton` | `.title2.weight(.semibold)` (22) | −10 / +10 |

Spacing (`Theme.Spacing`): `gutter 20` (screen side padding), `cardGap 12` (plans list), `sectionGap 14` (editor), `rowGap 8` (block rows, chips), `sheetGap 18` (block sheet sections), `cardPadding 16` (fields and toggle rows, horizontal).

Radii (`Theme.Radius`): `card 20` (plan and free-session cards), `row 16` (block rows, fields, toggle rows, add-block dashed), `cta 18` (footer CTA, new-plan dashed, big stepper buttons), `toast 14`, `chip 12`, `sheet 32`. Pills are `Capsule()`.

Component geometry from Figma: plan card padding leading 20 / trailing 16 / vertical 18; free-session card leading 20 / trailing 18 / vertical 18; block row leading 14 / trailing 16 / vertical 14, HStack spacing 12; Start pill 16×10; CTA vertical padding 18; dashed border 1.5 pt; chip 12×10; fine-step pill 16×8 with a 1.5 pt `hairline` stroke; big stepper button 96×64; toast 16×12.

## Final layout

```
Reps/App/RootView.swift                      replaced: TabView (Plans, Library)
Reps/Plans/PlanDraft.swift                   new: BlockDraft, RemovedBlock, PlanDraft (nonisolated)
Reps/Plans/PlanSummary.swift                 new: card/row copy, lastDone formatting (nonisolated)
Reps/Plans/ClubChoices.swift                 new: picker names (nonisolated)
Reps/Plans/PlanLibrary.swift                 new: draft(from:), save, duplicate, delete, lastDone (MainActor)
Reps/UI/Theme/Theme.swift                    new
Reps/UI/Components/PrimaryButtonStyle.swift  new: PrimaryButtonStyle, FooterCTA
Reps/UI/Components/PillButtonStyle.swift     new
Reps/UI/Components/Chip.swift                new
Reps/UI/Components/DashedAddButton.swift     new
Reps/UI/Components/ToggleRow.swift           new
Reps/UI/Components/FieldCard.swift           new
Reps/UI/Components/BlockRow.swift            new
Reps/UI/Components/UndoToast.swift           new
Reps/UI/Plans/PracticeMode+Title.swift       new
Reps/UI/Plans/PlansView.swift                new: PlansView, PlanEditorTarget
Reps/UI/Plans/PlanCard.swift                 new: PlanCard, FreeSessionCard
Reps/UI/Plans/PlanEditorView.swift           new
Reps/UI/Plans/BlockEditorSheet.swift         new: BlockEditorSheet, ClubPicker, RepsStepper
Reps/UI/Library/LibraryPlaceholderView.swift new
Reps/UI/PreviewData.swift                    new, #if DEBUG: seeded in-memory container for #Previews
RepsTests/PlanDraftTests.swift               new (11 tests)
RepsTests/PlanSummaryTests.swift             new (4 tests)
RepsTests/ClubChoicesTests.swift             new (2 tests)
RepsTests/PlanLibraryTests.swift             new (7 tests)
docs/code-reference.md, docs/design.md, docs/open-questions.md, docs/roadmap.md   updated
```

## Steps

Branch `feat/7-plans-screens` (already checked out). Run everything from the repo root with `DEST='platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'`. Before each commit, `xcrun swift-format format --in-place --recursive --parallel Reps RepsTests` and then `xcrun swift-format lint --strict --recursive --parallel Reps RepsTests` must print nothing. Never edit `project.pbxproj`, because the folders are synced (ADR 0009).

### Step 1: plan logic (TDD)

1. Create the four `RepsTests/*` files from Appendix A. Run
   `xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan Unit -destination "$DEST" -only-testing:RepsTests/PlanDraftTests -only-testing:RepsTests/PlanSummaryTests -only-testing:RepsTests/ClubChoicesTests -only-testing:RepsTests/PlanLibraryTests` → fails to compile.
2. Create `Reps/Plans/PlanDraft.swift`, `PlanSummary.swift`, `ClubChoices.swift` and `PlanLibrary.swift` from Appendix A. Run the same command → **24 tests in 4 suites pass**. If `lastDoneFormats` fails only on the weekday/month text, the simulator's ICU differs: report it, and don't loosen the test.
3. `git add -A && git commit -m "added plan draft and library" -m "Refs #7"`

### Step 2: theme and shared components

1. Create `Reps/UI/Theme/Theme.swift` and every `Reps/UI/Components/*` file from Appendix B.
2. Build: `xcodebuild build -project Reps.xcodeproj -scheme Reps -destination "$DEST" -quiet` → succeeds with no new warnings.
3. `git add -A && git commit -m "added theme and shared components" -m "Refs #7"`

### Step 3: plans list, tab root, library placeholder

1. Create `PracticeMode+Title.swift`, `PlanCard.swift`, `PlansView.swift`, `LibraryPlaceholderView.swift` and `PreviewData.swift`, and replace `RootView.swift` (Appendix B). `PlansView` references `PlanEditorView`, so in this step also create `Reps/UI/Plans/PlanEditorView.swift` as a stub: `struct PlanEditorView: View { init(plan: PracticePlan?) {}; var body: some View { Text("Edit plan") } }`. Step 4 replaces it.
2. Build (same command).
3. `git add -A && git commit -m "added plans list and tab root" -m "Refs #7"`

### Step 4: plan editor and block sheet

1. Replace the stub with the real `PlanEditorView.swift` and create `BlockEditorSheet.swift` (Appendix B).
2. Build. Then run the full Unit plan once to make sure nothing regressed: `xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan Unit -destination "$DEST"` → `Test run with 109 tests in 11 suites passed`, `** TEST SUCCEEDED **`.
3. Manual smoke test in the simulator (no UI tests, since the table in CLAUDE.md gives screens without flow logic a build only): create a plan with 3 blocks, reorder by long-press drag, swipe-delete one and tap Undo within 5 s, Save; edit it, change a toggle, Cancel → the discard alert; duplicate it and delete it (confirmation). Check against the Figma screenshots.
4. `git add -A && git commit -m "added plan editor" -m "Refs #7"`

### Step 5: docs

1. `docs/code-reference.md`: apply Appendix C. Replace the `Reps/App/RootView.swift` entry and add the new entries after `Reps/Session/SessionController.swift` (app files) and after `RepsTests/SessionResumeTests.swift` (tests).
2. `docs/design.md`: under the Theme bullet, add: `- Tokens: \`Reps/UI/Theme/Theme.swift\` (values read from frames 01, 02, 06, 13). Shared components live in \`Reps/UI/Components/\`: footer CTA, pill, chip, dashed add button, toggle row, field card, block row, undo toast. Alerts use native \`.alert\`.`
3. `docs/open-questions.md`: add Q27 to the Open table:
   `| Q27 | Plans list order: creation date (now), most recently done, or manual drag order? | – (#7 ships creation order) | Manual order would need a \`sortOrder\` on PracticePlan (schema V2). Leaning: keep creation order unless it annoys in use. |`
4. `docs/roadmap.md`: #7 status ☐ → ☑ (in the PR commit, when the issue closes).
5. `git add -A && git commit -m "documented plans screens" -m "Refs #7"`

No review (the issue has neither review label). Push, then open a PR titled `added plans list and plan editor` with a one-line body plus `Closes #7`.

## Tests

`Unit` plan, filtered to the four new suites (all of Appendix A):

- `PlanDraftTests`: save validity, reps clamping, note trimming, upsert, move semantics (down, up, several, in place, out of range), remove/restore (index, clamp, duplicate restore), **discard detection** (`changesAreDetected`: every field, move and move back, remove and undo).
- `PlanSummaryTests`: singular/plural, putts, subtitle/totals, block detail, `lastDone` (nil, today, future, 2 and 6 days, 7 days, another year). A fixed `en_US` locale and UTC calendar.
- `ClubChoicesTests`: bag order, dedupe, blanks, an off-bag current club appended.
- `PlanLibraryTests` (in-memory store): create with trimmed and ordered blocks, round trip, edit in place (ids kept, renumbered, new block uses the draft id), removed block deleted with its result snapshot intact, **duplicate deep copy** (new ids, order renumbered from gappy orders, flags copied, no sessions, original untouched), delete keeps sessions and `planName`, `lastDone` ignores active sessions and falls back to `startedAt`.

Views: build only (CLAUDE.md: UI without logic). No UI tests. The discard and undo logic that matters is covered in `PlanDraftTests`.

## Placeholders (`// PLACEHOLDER:` in code; the owner supplies real content)

| Where | What ships now |
|---|---|
| `RootView` Plans tab icon | SF Symbol `list.bullet.rectangle` (Figma: a filled ellipse) |
| `RootView` Library tab icon | SF Symbol `film.stack` (Figma: a grey ellipse) |
| `LibraryPlaceholderView` | `ContentUnavailableView("Library", systemImage: "film.stack", description: Text("Your clips will show up here."))` |
| `BlockRow` drag handle | SF Symbol `line.3.horizontal` (Figma: "≡" glyph) |
| `PlanSummary.lastDone` nil | "Not done yet" |
| `PlanLibrary.duplicate` | name suffix " copy" |
| `PlanEditorView` title for a new plan | "New plan" (Figma only shows "Edit plan") |
| `PlanEditorView` name prompt | "e.g. Wedge day" |
| Order toggle, **on** subtitle | "On — blocks run in the order below" (the off copy is from Figma) |
| Strict toggle, **on** subtitle | "On — each block stops exactly at its target" (the off copy is from Figma) |
| Block sheet title for a new block | "New block" |
| Club picker custom chip | "Other…", with the alert "Club name" / TextField "Club name" / buttons "Cancel", "Use" |
| Club picker empty-bag hint | "Your bag is empty. Add clubs in Settings, or use Other…" |
| Note prompt | "e.g. 95 m, half swing" |
| Delete-plan alert message | "Its sessions stay in the log." |
| Error alerts | "Couldn't save the plan.", "Couldn't duplicate the plan.", "Couldn't delete the plan." with OK (real error UI is #29) |

Figma copy used verbatim (not placeholders): Plans, Settings, Free session, "Count and record without a plan", Start, "+  New plan", Cancel, Edit plan, Plan name, Range / Range + clips / Putting, Order is mandatory, "Off — jump to any block during the session", Strict count, "Off — targets are minimums, keep hitting past them", Blocks, "+  Add block", Save plan, "`<club>` removed", Undo, Block N, Remove, Club, Shots, Note (optional), Done, "Discard changes?", "`<name>` has unsaved changes.", Keep editing, Discard. "Putts" replaces "Shots" as the stepper label in putting plans.

`grep -rn "PLACEHOLDER:" Reps` should list 19 lines, which cover the rows above. `grep -rn "TODO(#" Reps/UI Reps/App` should list `TODO(#9)` twice (RootView) and `TODO(#6)` once (PlansView Settings) and `TODO(#24)` once (LibraryPlaceholderView).

## Risks and unresolved

- **Swipe on custom-background rows.** Cards and block rows draw their own rounded background as row *content* (`listRowBackground(Color.clear)`, separators hidden, insets set), so the card slides with the swipe and the action shows in the gap, as in Figma 02. If the swipe action draws square instead of rounded, accept the system look. Don't hand-roll a swipe gesture.
- **Buttons inside List rows.** A row with two tappable areas (card text → edit, Start pill) needs both to be non-default-styled buttons (`.buttonStyle(.plain)` and `PillButtonStyle`). Otherwise a tap anywhere fires both. Check it in the smoke test.
- **Drag reorder without edit mode.** `onMove` in a plain `List` gives long-press drag on iOS 16+, with no Edit button. If long-press drag doesn't start in the smoke test, report it rather than adding an Edit mode (the design has none).
- **Discard alert only on Cancel.** A full-screen cover can't be swiped away, so nothing else can lose edits. The block sheet can be swiped away and drops only that block's unsaved edits (accepted).
- **Editing a plan during an active session** is safe, because the session snapshots its rules and block results (ADR 0013, Q24). Deleting a plan with an active session leaves the session running with `plan == nil` and `planName` set.
- **`navigationSubtitle` date** uses the device locale (`Wednesday, September 16` in en_US, `Wednesday 16 September` in en_GB, as in Figma).
- **Fixed font sizes** 18/14/64 don't scale with Dynamic Type. Accepted for a personal app.
- Q27 (list order) is recorded as open.

## Appendix A: logic and tests (verified, copy exactly)

### `Reps/Plans/PlanDraft.swift`

```swift
import Foundation

nonisolated struct BlockDraft: Identifiable, Equatable, Sendable {
    static let repsRange = 1...999
    static let defaultReps = 30

    var id: UUID
    var clubName: String
    var targetReps: Int
    var note: String

    init(id: UUID = UUID(), clubName: String, targetReps: Int = BlockDraft.defaultReps, note: String = "") {
        self.id = id
        self.clubName = clubName
        self.targetReps = targetReps
        self.note = note
    }

    var trimmedClubName: String { clubName.trimmingCharacters(in: .whitespacesAndNewlines) }

    // Blank notes are stored as nil.
    var storedNote: String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var isValid: Bool { !trimmedClubName.isEmpty && Self.repsRange.contains(targetReps) }

    mutating func adjustReps(by delta: Int) {
        targetReps = min(max(targetReps + delta, Self.repsRange.lowerBound), Self.repsRange.upperBound)
    }
}

nonisolated struct RemovedBlock: Identifiable, Equatable, Sendable {
    let block: BlockDraft
    let index: Int

    var id: UUID { block.id }
}

// The editor's working copy; nothing touches SwiftData until PlanLibrary.save.
nonisolated struct PlanDraft: Equatable, Sendable {
    var name: String
    var mode: PracticeMode
    var isOrderMandatory: Bool
    var isStrictCount: Bool
    var blocks: [BlockDraft]

    init(
        name: String = "",
        mode: PracticeMode = .rangeCounter,
        isOrderMandatory: Bool = false,
        isStrictCount: Bool = false,
        blocks: [BlockDraft] = []
    ) {
        self.name = name
        self.mode = mode
        self.isOrderMandatory = isOrderMandatory
        self.isStrictCount = isStrictCount
        self.blocks = blocks
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var totalReps: Int { blocks.reduce(0) { $0 + $1.targetReps } }
    var canSave: Bool { !trimmedName.isEmpty && !blocks.isEmpty && blocks.allSatisfy(\.isValid) }

    func index(of id: UUID) -> Int? { blocks.firstIndex { $0.id == id } }

    // Replaces the block with the same id, or appends it.
    mutating func upsert(_ block: BlockDraft) {
        if let index = index(of: block.id) {
            blocks[index] = block
        } else {
            blocks.append(block)
        }
    }

    mutating func removeBlock(id: UUID) -> RemovedBlock? {
        guard let index = index(of: id) else { return nil }
        return RemovedBlock(block: blocks.remove(at: index), index: index)
    }

    // Puts it back where it was, clamped if the list has shrunk since.
    mutating func restore(_ removed: RemovedBlock) {
        guard index(of: removed.block.id) == nil else { return }
        blocks.insert(removed.block, at: min(removed.index, blocks.count))
    }

    // Same semantics as SwiftUI's move(fromOffsets:toOffset:), without importing SwiftUI.
    mutating func moveBlocks(fromOffsets source: IndexSet, toOffset destination: Int) {
        let valid = source.filter { blocks.indices.contains($0) }
        guard !valid.isEmpty else { return }
        let moving = valid.map { blocks[$0] }
        let shift = valid.filter { $0 < destination }.count
        for index in valid.reversed() { blocks.remove(at: index) }
        blocks.insert(contentsOf: moving, at: min(max(destination - shift, 0), blocks.count))
    }
}
```

### `Reps/Plans/PlanSummary.swift`

```swift
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
```

### `Reps/Plans/ClubChoices.swift`

```swift
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
```

### `Reps/Plans/PlanLibrary.swift`

```swift
import Foundation
import SwiftData

// Plan writes for the plans list and editor.
enum PlanLibrary {
    static func draft(from plan: PracticePlan) -> PlanDraft {
        PlanDraft(
            name: plan.name,
            mode: plan.mode,
            isOrderMandatory: plan.isOrderMandatory,
            isStrictCount: plan.isStrictCount,
            blocks: plan.sortedBlocks.map {
                BlockDraft(id: $0.id, clubName: $0.clubName, targetReps: $0.targetReps, note: $0.note ?? "")
            }
        )
    }

    // Creates the plan when `plan` is nil. Blocks keep their ids, so session results stay linked;
    // removed blocks are deleted (their results keep the snapshot). Order is renumbered 0..<n.
    @discardableResult
    static func save(_ draft: PlanDraft, to plan: PracticePlan?, in context: ModelContext, now: Date = .now) throws
        -> PracticePlan
    {
        let target: PracticePlan
        if let plan {
            target = plan
        } else {
            target = PracticePlan(name: draft.trimmedName, mode: draft.mode, createdAt: now)
            context.insert(target)
        }
        target.name = draft.trimmedName
        target.mode = draft.mode
        target.isOrderMandatory = draft.isOrderMandatory
        target.isStrictCount = draft.isStrictCount

        let keptIDs = Set(draft.blocks.map(\.id))
        let removed = target.blocks.filter { !keptIDs.contains($0.id) }
        target.blocks.removeAll { !keptIDs.contains($0.id) }
        for block in removed { context.delete(block) }

        let existing = Dictionary(uniqueKeysWithValues: target.blocks.map { ($0.id, $0) })
        for (order, item) in draft.blocks.enumerated() {
            if let block = existing[item.id] {
                block.clubName = item.trimmedClubName
                block.targetReps = item.targetReps
                block.note = item.storedNote
                block.order = order
            } else {
                let block = PlanBlock(
                    clubName: item.trimmedClubName, targetReps: item.targetReps, note: item.storedNote, order: order)
                block.id = item.id
                target.blocks.append(block)
            }
        }
        try context.save()
        return target
    }

    // Deep copy: new plan and block ids, same order, no sessions.
    @discardableResult
    static func duplicate(_ plan: PracticePlan, in context: ModelContext, now: Date = .now) throws -> PracticePlan {
        let copy = PracticePlan(
            name: "\(plan.name) copy",  // PLACEHOLDER: duplicate naming
            mode: plan.mode,
            isOrderMandatory: plan.isOrderMandatory,
            isStrictCount: plan.isStrictCount,
            createdAt: now
        )
        context.insert(copy)
        copy.blocks = plan.sortedBlocks.enumerated().map { order, block in
            PlanBlock(clubName: block.clubName, targetReps: block.targetReps, note: block.note, order: order)
        }
        try context.save()
        return copy
    }

    // Sessions keep their planName snapshot (nullify).
    static func delete(_ plan: PracticePlan, in context: ModelContext) throws {
        context.delete(plan)
        try context.save()
    }

    // Newest finished session's end; enum filtered in Swift (ADR 0013).
    static func lastDone(_ plan: PracticePlan) -> Date? {
        plan.sessions.filter { $0.status == .finished }.map { $0.endedAt ?? $0.startedAt }.max()
    }
}
```

### `RepsTests/PlanDraftTests.swift`

```swift
import Foundation
import Testing

@testable import Reps

struct PlanDraftTests {
    private let a = BlockDraft(clubName: "PW", targetReps: 40)
    private let b = BlockDraft(clubName: "GW", targetReps: 30)
    private let c = BlockDraft(clubName: "SW", targetReps: 20)

    private func draft() -> PlanDraft {
        PlanDraft(name: "Wedge day", blocks: [a, b, c])
    }

    private func clubs(_ draft: PlanDraft) -> [String] { draft.blocks.map(\.clubName) }

    @Test func emptyDraftCannotSave() {
        #expect(!PlanDraft().canSave)
        #expect(!PlanDraft(name: "   ", blocks: [a]).canSave)
        #expect(!PlanDraft(name: "Wedge day").canSave)
        #expect(!PlanDraft(name: "Wedge day", blocks: [BlockDraft(clubName: "  ")]).canSave)
        #expect(!PlanDraft(name: "Wedge day", blocks: [BlockDraft(clubName: "PW", targetReps: 0)]).canSave)
    }

    @Test func namedDraftWithValidBlocksCanSave() {
        #expect(draft().canSave)
        #expect(draft().totalReps == 90)
    }

    @Test func adjustRepsClampsToRange() {
        var block = BlockDraft(clubName: "PW", targetReps: 3)
        block.adjustReps(by: -10)
        #expect(block.targetReps == 1)
        block.adjustReps(by: 5)
        #expect(block.targetReps == 6)
        block.targetReps = 995
        block.adjustReps(by: 10)
        #expect(block.targetReps == 999)
    }

    @Test func storedNoteTrimsAndDropsBlank() {
        #expect(BlockDraft(clubName: "PW", note: "  110 m ").storedNote == "110 m")
        #expect(BlockDraft(clubName: "PW", note: " \n ").storedNote == nil)
    }

    @Test func upsertReplacesByIDOrAppends() {
        var draft = draft()
        var edited = b
        edited.targetReps = 50
        draft.upsert(edited)
        #expect(draft.blocks[1].targetReps == 50)
        #expect(draft.blocks.count == 3)
        let added = BlockDraft(clubName: "LW")
        draft.upsert(added)
        #expect(draft.blocks.last == added)
    }

    @Test func moveBlocksMatchesListSemantics() {
        var down = draft()
        down.moveBlocks(fromOffsets: [0], toOffset: 3)
        #expect(clubs(down) == ["GW", "SW", "PW"])
        var up = draft()
        up.moveBlocks(fromOffsets: [2], toOffset: 0)
        #expect(clubs(up) == ["SW", "PW", "GW"])
        var several = draft()
        several.moveBlocks(fromOffsets: [0, 2], toOffset: 2)
        #expect(clubs(several) == ["GW", "PW", "SW"])
        var inPlace = draft()
        inPlace.moveBlocks(fromOffsets: [1], toOffset: 1)
        #expect(inPlace == draft())
    }

    @Test func moveBlocksIgnoresOffsetsOutOfRange() {
        var draft = draft()
        draft.moveBlocks(fromOffsets: [7], toOffset: 0)
        #expect(draft == self.draft())
    }

    @Test func removeThenRestorePutsBlockBack() throws {
        var draft = draft()
        let taken = draft.removeBlock(id: b.id)
        let removed = try #require(taken)
        #expect(removed.index == 1)
        #expect(clubs(draft) == ["PW", "SW"])
        draft.restore(removed)
        #expect(draft == self.draft())
        let missing = draft.removeBlock(id: UUID())
        #expect(missing == nil)
    }

    @Test func restoreClampsWhenListShrank() throws {
        var draft = draft()
        let taken = draft.removeBlock(id: c.id)
        let removed = try #require(taken)
        _ = draft.removeBlock(id: b.id)
        draft.restore(removed)
        #expect(clubs(draft) == ["PW", "SW"])
    }

    @Test func restoreIgnoresABlockAlreadyPresent() throws {
        var draft = draft()
        let taken = draft.removeBlock(id: a.id)
        let removed = try #require(taken)
        draft.restore(removed)
        draft.restore(removed)
        #expect(draft.blocks.count == 3)
    }

    @Test func changesAreDetected() throws {
        let original = draft()
        var edited = original
        #expect(edited == original)

        edited.name = "Wedges"
        #expect(edited != original)
        edited = original
        edited.isStrictCount = true
        #expect(edited != original)
        edited = original
        edited.mode = .putting
        #expect(edited != original)
        edited = original
        edited.blocks[0].adjustReps(by: 1)
        #expect(edited != original)
        edited = original
        edited.blocks[2].note = "80 m"
        #expect(edited != original)

        edited = original
        edited.moveBlocks(fromOffsets: [0], toOffset: 2)
        #expect(edited != original)
        edited.moveBlocks(fromOffsets: [1], toOffset: 0)
        #expect(edited == original)

        edited = original
        let taken = edited.removeBlock(id: a.id)
        let removed = try #require(taken)
        #expect(edited != original)
        edited.restore(removed)
        #expect(edited == original)
    }
}
```

### `RepsTests/PlanSummaryTests.swift`

```swift
import Foundation
import Testing

@testable import Reps

struct PlanSummaryTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let locale = Locale(identifier: "en_US")
    // Wednesday 16 September 2026, 10:00 UTC
    private let now = Date(timeIntervalSince1970: 1_789_552_800)

    private func lastDone(daysAgo days: Double) -> String {
        PlanSummary.lastDone(now.addingTimeInterval(-days * 86_400), now: now, calendar: calendar, locale: locale)
    }

    @Test func repsUseSingularPluralAndPutts() {
        #expect(PlanSummary.reps(1, mode: .rangeCounter) == "1 shot")
        #expect(PlanSummary.reps(170, mode: .rangeCounterWithClips) == "170 shots")
        #expect(PlanSummary.reps(90, mode: .putting) == "90 putts")
        #expect(PlanSummary.blocks(1) == "1 block")
    }

    @Test func subtitleAndTotals() {
        #expect(
            PlanSummary.subtitle(blockCount: 5, totalReps: 170, mode: .rangeCounter, isOrderMandatory: false)
                == "5 blocks · 170 shots · any order")
        #expect(
            PlanSummary.subtitle(blockCount: 3, totalReps: 90, mode: .putting, isOrderMandatory: true)
                == "3 blocks · 90 putts · in order")
        #expect(PlanSummary.totals(blockCount: 0, totalReps: 0, mode: .rangeCounter) == "0 blocks · 0 shots")
    }

    @Test func blockDetailAddsNote() {
        #expect(PlanSummary.blockDetail(targetReps: 40, note: "110 m", mode: .rangeCounter) == "40 shots · 110 m")
        #expect(PlanSummary.blockDetail(targetReps: 40, note: nil, mode: .rangeCounter) == "40 shots")
        #expect(PlanSummary.blockDetail(targetReps: 10, note: "", mode: .putting) == "10 putts")
    }

    @Test func lastDoneFormats() {
        #expect(PlanSummary.lastDone(nil, now: now, calendar: calendar, locale: locale) == "Not done yet")
        #expect(lastDone(daysAgo: 0.3) == "Last done today")
        #expect(lastDone(daysAgo: -1) == "Last done today")
        #expect(lastDone(daysAgo: 2) == "Last done Mon")
        #expect(lastDone(daysAgo: 6) == "Last done Thu")
        #expect(lastDone(daysAgo: 7) == "Last done Sep 9")
        #expect(lastDone(daysAgo: 372) == "Last done Sep 9, 2025")
    }
}
```

### `RepsTests/ClubChoicesTests.swift`

```swift
import Testing

@testable import Reps

struct ClubChoicesTests {
    @Test func keepsBagOrderAndDropsDuplicatesAndBlanks() {
        #expect(ClubChoices.names(bag: ["Driver", "7 iron", "Driver", " "], current: "") == ["Driver", "7 iron"])
    }

    @Test func appendsCurrentClubMissingFromBag() {
        #expect(ClubChoices.names(bag: ["Driver"], current: "Chipper") == ["Driver", "Chipper"])
        #expect(ClubChoices.names(bag: ["Driver"], current: "Driver") == ["Driver"])
        #expect(ClubChoices.names(bag: [], current: "") == [])
    }
}
```

### `RepsTests/PlanLibraryTests.swift`

```swift
import Foundation
import SwiftData
import Testing

@testable import Reps

@MainActor
struct PlanLibraryTests {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        container = try RepsStore.makeContainer(inMemory: true)
        context = container.mainContext
    }

    private func wedgeDraft() -> PlanDraft {
        PlanDraft(
            name: "  Wedge day ",
            mode: .rangeCounterWithClips,
            isOrderMandatory: true,
            blocks: [
                BlockDraft(clubName: " PW", targetReps: 40, note: "110 m"),
                BlockDraft(clubName: "GW", targetReps: 30, note: "  "),
                BlockDraft(clubName: "SW", targetReps: 20),
            ]
        )
    }

    private func summary(_ plan: PracticePlan) -> [String] {
        plan.sortedBlocks.map { "\($0.order):\($0.clubName):\($0.targetReps):\($0.note ?? "-")" }
    }

    @Test func saveCreatesPlanWithOrderedBlocks() throws {
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let plan = try PlanLibrary.save(wedgeDraft(), to: nil, in: context, now: createdAt)
        #expect(plan.name == "Wedge day")
        #expect(plan.mode == .rangeCounterWithClips)
        #expect(plan.isOrderMandatory)
        #expect(!plan.isStrictCount)
        #expect(plan.createdAt == createdAt)
        #expect(summary(plan) == ["0:PW:40:110 m", "1:GW:30:-", "2:SW:20:-"])
        #expect(try context.fetchCount(FetchDescriptor<PracticePlan>()) == 1)
    }

    @Test func draftRoundTripsWithoutChanges() throws {
        let plan = try PlanLibrary.save(wedgeDraft(), to: nil, in: context)
        let draft = PlanLibrary.draft(from: plan)
        #expect(draft.name == "Wedge day")
        #expect(draft.blocks.map(\.id) == plan.sortedBlocks.map(\.id))
        #expect(draft.blocks[1].note == "")
        try PlanLibrary.save(draft, to: plan, in: context)
        #expect(PlanLibrary.draft(from: plan) == draft)
    }

    @Test func saveEditsInPlaceAndRenumbers() throws {
        let plan = try PlanLibrary.save(wedgeDraft(), to: nil, in: context)
        let ids = plan.sortedBlocks.map(\.id)
        var draft = PlanLibrary.draft(from: plan)
        draft.name = "Wedges"
        draft.isStrictCount = true
        draft.blocks[0].targetReps = 45
        draft.moveBlocks(fromOffsets: [2], toOffset: 0)
        draft.upsert(BlockDraft(clubName: "LW", targetReps: 10))
        try PlanLibrary.save(draft, to: plan, in: context)

        #expect(plan.name == "Wedges")
        #expect(plan.isStrictCount)
        #expect(summary(plan) == ["0:SW:20:-", "1:PW:45:110 m", "2:GW:30:-", "3:LW:10:-"])
        #expect(Array(plan.sortedBlocks.map(\.id).prefix(3)) == [ids[2], ids[0], ids[1]])
        #expect(plan.sortedBlocks[3].id == draft.blocks[3].id)
        #expect(try context.fetchCount(FetchDescriptor<PracticePlan>()) == 1)
    }

    @Test func removedBlockIsDeletedAndResultsKeepTheirSnapshot() throws {
        let plan = try PlanLibrary.save(wedgeDraft(), to: nil, in: context)
        let session = PracticeSession(plan: plan, mode: plan.mode, cameraAngle: .faceOn)
        context.insert(session)
        let gw = plan.sortedBlocks[1]
        let kept = BlockResult(block: plan.sortedBlocks[0], order: 0)
        let orphaned = BlockResult(block: gw, order: 1)
        session.blockResults = [kept, orphaned]
        try context.save()

        var draft = PlanLibrary.draft(from: plan)
        _ = draft.removeBlock(id: gw.id)
        try PlanLibrary.save(draft, to: plan, in: context)

        #expect(summary(plan) == ["0:PW:40:110 m", "1:SW:20:-"])
        #expect(try context.fetchCount(FetchDescriptor<PlanBlock>()) == 2)
        #expect(orphaned.block == nil)
        #expect(orphaned.clubName == "GW")
        #expect(orphaned.targetReps == 30)
        #expect(kept.block?.clubName == "PW")
    }

    @Test func duplicateDeepCopiesBlocksInOrder() throws {
        let plan = PracticePlan(name: "Irons", mode: .putting, isOrderMandatory: true, isStrictCount: true)
        context.insert(plan)
        plan.blocks = [
            PlanBlock(clubName: "9 iron", targetReps: 30, order: 9),
            PlanBlock(clubName: "7 iron", targetReps: 20, note: "150 m", order: 0),
            PlanBlock(clubName: "8 iron", targetReps: 25, order: 5),
        ]
        let session = PracticeSession(plan: plan, mode: plan.mode, cameraAngle: .none)
        context.insert(session)
        try context.save()

        let createdAt = Date(timeIntervalSince1970: 2_000)
        let copy = try PlanLibrary.duplicate(plan, in: context, now: createdAt)

        #expect(copy.id != plan.id)
        #expect(copy.name == "Irons copy")
        #expect(copy.mode == .putting)
        #expect(copy.isOrderMandatory)
        #expect(copy.isStrictCount)
        #expect(copy.createdAt == createdAt)
        #expect(copy.sessions.isEmpty)
        #expect(summary(copy) == ["0:7 iron:20:150 m", "1:8 iron:25:-", "2:9 iron:30:-"])
        #expect(Set(copy.blocks.map(\.id)).isDisjoint(with: plan.blocks.map(\.id)))
        #expect(plan.blocks.count == 3)
        #expect(plan.sessions.count == 1)
        #expect(try context.fetchCount(FetchDescriptor<PlanBlock>()) == 6)
    }

    @Test func deleteKeepsSessionsWithTheirSnapshot() throws {
        let plan = try PlanLibrary.save(wedgeDraft(), to: nil, in: context)
        let session = PracticeSession(plan: plan, mode: plan.mode, cameraAngle: .faceOn)
        context.insert(session)
        let result = BlockResult(block: plan.sortedBlocks[0], order: 0)
        session.blockResults = [result]
        try context.save()

        try PlanLibrary.delete(plan, in: context)

        #expect(try context.fetchCount(FetchDescriptor<PracticePlan>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PlanBlock>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PracticeSession>()) == 1)
        #expect(session.plan == nil)
        #expect(session.planName == "Wedge day")
        #expect(result.block == nil)
        #expect(result.clubName == "PW")
    }

    @Test func lastDoneIsNewestFinishedSession() throws {
        let plan = try PlanLibrary.save(wedgeDraft(), to: nil, in: context)
        #expect(PlanLibrary.lastDone(plan) == nil)

        let older = PracticeSession(
            plan: plan, mode: plan.mode, cameraAngle: .faceOn, startedAt: Date(timeIntervalSince1970: 100))
        older.status = .finished
        older.endedAt = Date(timeIntervalSince1970: 200)
        let noEnd = PracticeSession(
            plan: plan, mode: plan.mode, cameraAngle: .faceOn, startedAt: Date(timeIntervalSince1970: 300))
        noEnd.status = .finished
        let active = PracticeSession(
            plan: plan, mode: plan.mode, cameraAngle: .faceOn, startedAt: Date(timeIntervalSince1970: 900))
        for session in [older, noEnd, active] { context.insert(session) }
        try context.save()

        #expect(PlanLibrary.lastDone(plan) == Date(timeIntervalSince1970: 300))
    }
}
```

## Appendix B: theme, components, screens (built, copy exactly)

### `Reps/UI/Theme/Theme.swift`

```swift
import SwiftUI

// Literal values from the Figma frames (no Figma variables exist); see docs/design.md.
enum Theme {
    static let background = Color(hex: 0xFFFFFF)
    static let ink = Color(hex: 0x17181A)
    static let secondaryText = Color(hex: 0x6F7175)
    static let accent = Color(hex: 0x2F6B4F)
    static let onAccentSecondary = Color(hex: 0xCFE3D8)
    static let card = Color(hex: 0xF2F2F0)
    static let fill = Color(hex: 0xE9E8E3)
    static let hairline = Color(hex: 0xD9D8D3)
    static let sheet = Color(hex: 0xF6F5F2)
    static let danger = Color(hex: 0xD0463D)
    static let dangerText = Color(hex: 0xB3413A)
    static let toastAction = Color(hex: 0x9FD3B7)

    enum Typography {
        static let largeTitle = Font.largeTitle.bold()
        static let value = Font.title2.weight(.semibold)
        static let sheetTitle = Font.title3.bold()
        static let cardTitleLarge = Font.title3.weight(.semibold)
        static let cardTitle = Font.system(size: 18, weight: .semibold)
        static let cta = Font.headline
        static let rowTitle = Font.callout.weight(.semibold)
        static let body = Font.callout
        static let pill = Font.subheadline.weight(.semibold)
        static let detail = Font.system(size: 14)
        static let chip = Font.system(size: 14, weight: .medium)
        static let chipSelected = Font.system(size: 14, weight: .semibold)
        static let footnote = Font.footnote
        static let footnoteMedium = Font.footnote.weight(.medium)
        static let label = Font.caption.weight(.medium)
        static let stepperValue = Font.system(size: 64, weight: .bold, design: .rounded)
        static let stepperValueTracking: CGFloat = -1.92
        static let stepperButton = Font.title2.weight(.semibold)
    }

    enum Spacing {
        static let gutter: CGFloat = 20
        static let cardGap: CGFloat = 12
        static let sectionGap: CGFloat = 14
        static let rowGap: CGFloat = 8
        static let sheetGap: CGFloat = 18
        static let cardPadding: CGFloat = 16
    }

    enum Radius {
        static let card: CGFloat = 20
        static let row: CGFloat = 16
        static let cta: CGFloat = 18
        static let toast: CGFloat = 14
        static let chip: CGFloat = 12
        static let sheet: CGFloat = 32
    }
}

extension Color {
    fileprivate init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
```

### `Reps/UI/Components/PrimaryButtonStyle.swift`

```swift
import SwiftUI

// Full-width green CTA (Save plan, Done).
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label(configuration: configuration)
    }

    private struct Label: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(Theme.Typography.cta)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Theme.accent, in: .rect(cornerRadius: Theme.Radius.cta))
                .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
        }
    }
}

// Footer area for `.safeAreaInset(edge: .bottom)`; `accessory` sits above the button (e.g. the undo toast).
struct FooterCTA<Accessory: View>: View {
    let title: String
    var isEnabled = true
    let action: () -> Void
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(spacing: Theme.Spacing.rowGap) {
            accessory
            Button(title, action: action)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!isEnabled)
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Theme.background)
    }
}

extension FooterCTA where Accessory == EmptyView {
    init(title: String, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.init(title: title, isEnabled: isEnabled, action: action) { EmptyView() }
    }
}
```

### `Reps/UI/Components/PillButtonStyle.swift`

```swift
import SwiftUI

// Small capsule "Start" button on cards.
struct PillButtonStyle: ButtonStyle {
    enum Kind {
        case onAccent
        case neutral
    }

    var kind: Kind = .neutral

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.pill)
            .foregroundStyle(kind == .onAccent ? Theme.accent : Theme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(kind == .onAccent ? Color.white : Theme.fill, in: .capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
```

### `Reps/UI/Components/Chip.swift`

```swift
import SwiftUI

// Selectable grid chip (club picker); later screens reuse it for tags.
struct Chip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(isSelected ? Theme.Typography.chipSelected : Theme.Typography.chip)
                .foregroundStyle(isSelected ? Color.white : Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(isSelected ? Theme.accent : Theme.card, in: .rect(cornerRadius: Theme.Radius.chip))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
```

### `Reps/UI/Components/DashedAddButton.swift`

```swift
import SwiftUI

// "+  New plan" / "+  Add block".
struct DashedAddButton: View {
    let title: String
    var font: Font = Theme.Typography.rowTitle
    var verticalPadding: CGFloat = 18
    var cornerRadius: CGFloat = Theme.Radius.cta
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("+  \(title)")
                .font(font)
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, verticalPadding)
                .contentShape(.rect(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }
        }
        .buttonStyle(.plain)
    }
}
```

### `Reps/UI/Components/ToggleRow.swift`

```swift
import SwiftUI

// Card with a title, a subtitle and a switch (plan rules; Settings reuses it).
struct ToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .tint(Theme.accent)
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.vertical, 14)
        .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.row))
    }
}
```

### `Reps/UI/Components/FieldCard.swift`

```swift
import SwiftUI

// Grey card with a small label over an input ("Plan name", "Note (optional)").
struct FieldCard<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.secondaryText)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.vertical, 12)
        .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.row))
    }
}
```

### `Reps/UI/Components/BlockRow.swift`

```swift
import SwiftUI

// One plan block: handle, club, detail, target, chevron.
struct BlockRow: View {
    let clubName: String
    let detail: String
    let targetReps: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")  // PLACEHOLDER: drag handle glyph (Figma "≡")
                .font(.system(size: 17))
                .foregroundStyle(Theme.hairline)
            VStack(alignment: .leading, spacing: 2) {
                Text(clubName)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            Text("\(targetReps)")
                .font(Theme.Typography.value)
                .foregroundStyle(Theme.accent)
            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.hairline)
        }
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .padding(.vertical, 14)
        .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.row))
        .contentShape(.rect(cornerRadius: Theme.Radius.row))
    }
}
```

### `Reps/UI/Components/UndoToast.swift`

```swift
import SwiftUI

// Dark toast with an Undo action (F24, §5.3c).
struct UndoToast: View {
    static let duration: Duration = .seconds(5)

    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack {
            Text(message)
                .font(Theme.Typography.chip)
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 12)
            Button("Undo", action: onUndo)
                .font(Theme.Typography.chipSelected)
                .foregroundStyle(Theme.toastAction)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.ink, in: .rect(cornerRadius: Theme.Radius.toast))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

extension View {
    // Clears `item` after UndoToast.duration; a new item restarts the timer.
    func undoToastTimer<Item: Identifiable>(_ item: Binding<Item?>) -> some View {
        task(id: item.wrappedValue?.id) {
            guard item.wrappedValue != nil else { return }
            try? await Task.sleep(for: UndoToast.duration)
            guard !Task.isCancelled else { return }
            withAnimation { item.wrappedValue = nil }
        }
    }
}
```

### `Reps/UI/Plans/PracticeMode+Title.swift`

```swift
extension PracticeMode {
    // Segment labels from Figma 02.
    var title: String {
        switch self {
        case .rangeCounter: "Range"
        case .rangeCounterWithClips: "Range + clips"
        case .putting: "Putting"
        }
    }
}
```

### `Reps/UI/Plans/PlanCard.swift`

```swift
import SwiftUI

struct PlanCard: View {
    let plan: PracticePlan
    let onOpen: () -> Void
    let onStart: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.name)
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(Theme.ink)
                    Text(
                        PlanSummary.subtitle(
                            blockCount: plan.blocks.count,
                            totalReps: plan.blocks.reduce(0) { $0 + $1.targetReps },
                            mode: plan.mode,
                            isOrderMandatory: plan.isOrderMandatory
                        )
                    )
                    .font(Theme.Typography.detail)
                    .foregroundStyle(Theme.secondaryText)
                    Text(PlanSummary.lastDone(PlanLibrary.lastDone(plan), now: .now))
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Button("Start", action: onStart)
                .buttonStyle(PillButtonStyle(kind: .neutral))
                .disabled(plan.blocks.isEmpty)
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .padding(.vertical, 18)
        .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.card))
    }
}

struct FreeSessionCard: View {
    let onStart: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Free session")
                    .font(Theme.Typography.cardTitleLarge)
                    .foregroundStyle(.white)
                Text("Count and record without a plan")
                    .font(Theme.Typography.detail)
                    .foregroundStyle(Theme.onAccentSecondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Start", action: onStart)
                .buttonStyle(PillButtonStyle(kind: .onAccent))
        }
        .padding(.leading, 20)
        .padding(.trailing, 18)
        .padding(.vertical, 18)
        .background(Theme.accent, in: .rect(cornerRadius: Theme.Radius.card))
    }
}
```

### `Reps/UI/Plans/PlansView.swift`

```swift
import SwiftData
import SwiftUI

enum PlanEditorTarget: Identifiable {
    case new
    case edit(PracticePlan)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let plan): plan.id.uuidString
        }
    }

    var plan: PracticePlan? {
        if case .edit(let plan) = self { plan } else { nil }
    }
}

// Figma 01 Plans.
struct PlansView: View {
    let onStartPlan: (PracticePlan) -> Void
    let onStartFreeSession: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \PracticePlan.createdAt) private var plans: [PracticePlan]
    @State private var editing: PlanEditorTarget?
    @State private var planToDelete: PracticePlan?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                FreeSessionCard(onStart: onStartFreeSession)
                    .plansRow()
                ForEach(plans) { plan in
                    PlanCard(
                        plan: plan,
                        onOpen: { editing = .edit(plan) },
                        onStart: { onStartPlan(plan) }
                    )
                    .plansRow()
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        // No destructive role: the row must stay until the alert is confirmed.
                        Button("Delete") { planToDelete = plan }
                            .tint(Theme.danger)
                        Button("Duplicate") { duplicate(plan) }
                            .tint(Theme.accent)
                    }
                }
                DashedAddButton(title: "New plan") { editing = .new }
                    .plansRow()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Plans")
            .navigationSubtitle(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings") {}  // TODO(#6): open Settings
                        .tint(Theme.accent)
                }
            }
            .fullScreenCover(item: $editing) { target in
                PlanEditorView(plan: target.plan)
            }
            .alert(
                "Delete \(planToDelete?.name ?? "plan")?",
                isPresented: Binding(get: { planToDelete != nil }, set: { if !$0 { planToDelete = nil } }),
                presenting: planToDelete
            ) { plan in
                Button("Delete", role: .destructive) { delete(plan) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Its sessions stay in the log.")  // PLACEHOLDER: delete-plan alert copy
            }
            .alert(
                errorMessage ?? "",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private func duplicate(_ plan: PracticePlan) {
        do {
            try PlanLibrary.duplicate(plan, in: context)
        } catch {
            errorMessage = "Couldn't duplicate the plan."  // PLACEHOLDER: error copy (#29)
        }
    }

    private func delete(_ plan: PracticePlan) {
        do {
            try PlanLibrary.delete(plan, in: context)
        } catch {
            errorMessage = "Couldn't delete the plan."  // PLACEHOLDER: error copy (#29)
        }
    }
}

extension View {
    // Card rows draw their own background so they slide with the swipe.
    fileprivate func plansRow() -> some View {
        listRowInsets(
            EdgeInsets(
                top: Theme.Spacing.cardGap / 2, leading: Theme.Spacing.gutter,
                bottom: Theme.Spacing.cardGap / 2, trailing: Theme.Spacing.gutter)
        )
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

#Preview {
    PlansView(onStartPlan: { _ in }, onStartFreeSession: {})
        .modelContainer(PreviewData.container())
}
```

### `Reps/UI/Plans/PlanEditorView.swift`

```swift
import SwiftData
import SwiftUI

// Figma 02 Plan editor + 13 discard alert. Edits a PlanDraft; only Save writes to the store.
struct PlanEditorView: View {
    private let plan: PracticePlan?
    private let original: PlanDraft

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PlanDraft
    @State private var editingBlock: BlockDraft?
    @State private var lastRemoved: RemovedBlock?
    @State private var confirmDiscard = false
    @State private var saveFailed = false

    init(plan: PracticePlan?) {
        self.plan = plan
        let draft = plan.map(PlanLibrary.draft(from:)) ?? PlanDraft()
        original = draft
        _draft = State(initialValue: draft)
    }

    private var hasChanges: Bool { draft != original }
    private var displayName: String { draft.trimmedName.isEmpty ? "This plan" : draft.trimmedName }

    var body: some View {
        NavigationStack {
            List {
                Group {
                    FieldCard(label: "Plan name") {
                        TextField("e.g. Wedge day", text: $draft.name)  // PLACEHOLDER: name prompt
                            .font(Theme.Typography.value)
                            .foregroundStyle(Theme.ink)
                            .submitLabel(.done)
                    }
                    Picker("Mode", selection: $draft.mode) {
                        ForEach(PracticeMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    ToggleRow(
                        title: "Order is mandatory",
                        subtitle: draft.isOrderMandatory
                            ? "On — blocks run in the order below"  // PLACEHOLDER: order on copy
                            : "Off — jump to any block during the session",
                        isOn: $draft.isOrderMandatory
                    )
                    ToggleRow(
                        title: "Strict count",
                        subtitle: draft.isStrictCount
                            ? "On — each block stops exactly at its target"  // PLACEHOLDER: strict on copy
                            : "Off — targets are minimums, keep hitting past them",
                        isOn: $draft.isStrictCount
                    )
                    HStack {
                        Text("Blocks")
                        Spacer()
                        Text(
                            PlanSummary.totals(
                                blockCount: draft.blocks.count, totalReps: draft.totalReps, mode: draft.mode))
                    }
                    .font(Theme.Typography.footnoteMedium)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 4)
                    .padding(.top, 6)
                }
                .editorRow(gap: Theme.Spacing.sectionGap)

                ForEach(draft.blocks) { block in
                    Button {
                        editingBlock = block
                    } label: {
                        BlockRow(
                            clubName: block.trimmedClubName,
                            detail: PlanSummary.blockDetail(
                                targetReps: block.targetReps, note: block.storedNote, mode: draft.mode),
                            targetReps: block.targetReps
                        )
                    }
                    .buttonStyle(.plain)
                    .editorRow(gap: Theme.Spacing.rowGap)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Delete", role: .destructive) { remove(block.id) }
                            .tint(Theme.danger)
                    }
                }
                .onMove { draft.moveBlocks(fromOffsets: $0, toOffset: $1) }

                DashedAddButton(
                    title: "Add block",
                    font: Theme.Typography.pill,
                    verticalPadding: 16,
                    cornerRadius: Theme.Radius.row
                ) {
                    editingBlock = BlockDraft(clubName: "")
                }
                .editorRow(gap: Theme.Spacing.sectionGap)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle(plan == nil ? "New plan" : "Edit plan")  // PLACEHOLDER: "New plan" title
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges { confirmDiscard = true } else { dismiss() }
                    }
                    .tint(Theme.secondaryText)
                }
            }
            .safeAreaInset(edge: .bottom) {
                FooterCTA(title: "Save plan", isEnabled: draft.canSave, action: save) {
                    if let removed = lastRemoved {
                        UndoToast(message: "\(removed.block.trimmedClubName) removed") {
                            withAnimation {
                                draft.restore(removed)
                                lastRemoved = nil
                            }
                        }
                    }
                }
            }
            .undoToastTimer($lastRemoved)
            .sheet(item: $editingBlock) { block in
                let index = draft.index(of: block.id)
                BlockEditorSheet(
                    block: block,
                    mode: draft.mode,
                    title: index.map { "Block \($0 + 1)" } ?? "New block",  // PLACEHOLDER: "New block" title
                    isNew: index == nil,
                    onDone: { draft.upsert($0) },
                    onRemove: { remove($0.id) }
                )
            }
            .alert("Discard changes?", isPresented: $confirmDiscard) {
                Button("Keep editing", role: .cancel) {}
                Button("Discard", role: .destructive) { dismiss() }
            } message: {
                Text("\(displayName) has unsaved changes.")
            }
            .alert("Couldn't save the plan.", isPresented: $saveFailed) {  // PLACEHOLDER: save error copy (#29)
                Button("OK", role: .cancel) {}
            }
        }
    }

    private func remove(_ id: UUID) {
        withAnimation {
            if let removed = draft.removeBlock(id: id) { lastRemoved = removed }
        }
    }

    private func save() {
        do {
            try PlanLibrary.save(draft, to: plan, in: context)
            dismiss()
        } catch {
            saveFailed = true
        }
    }
}

extension View {
    fileprivate func editorRow(gap: CGFloat) -> some View {
        listRowInsets(
            EdgeInsets(top: gap / 2, leading: Theme.Spacing.gutter, bottom: gap / 2, trailing: Theme.Spacing.gutter)
        )
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

#Preview {
    let container = PreviewData.container()
    let plan = try? container.mainContext.fetch(FetchDescriptor<PracticePlan>()).first
    PlanEditorView(plan: plan)
        .modelContainer(container)
}
```

### `Reps/UI/Plans/BlockEditorSheet.swift`

```swift
import SwiftData
import SwiftUI

// Figma 06 Block editor (sheet). Edits a copy; Done hands it back.
struct BlockEditorSheet: View {
    let mode: PracticeMode
    let title: String
    let isNew: Bool
    let onDone: (BlockDraft) -> Void
    let onRemove: (BlockDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\BagClub.sortOrder), SortDescriptor(\BagClub.name)]) private var clubs: [BagClub]
    @State private var working: BlockDraft
    @State private var askCustomClub = false
    @State private var customClubName = ""

    init(
        block: BlockDraft, mode: PracticeMode, title: String, isNew: Bool,
        onDone: @escaping (BlockDraft) -> Void, onRemove: @escaping (BlockDraft) -> Void
    ) {
        self.mode = mode
        self.title = title
        self.isNew = isNew
        self.onDone = onDone
        self.onRemove = onRemove
        _working = State(initialValue: block)
    }

    private var bagNames: [String] { clubs.filter(\.isInBag).map(\.name) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.sheetGap) {
                HStack {
                    Text(title)
                        .font(Theme.Typography.sheetTitle)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    if !isNew {
                        Button("Remove") {
                            onRemove(working)
                            dismiss()
                        }
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.dangerText)
                        .buttonStyle(.plain)
                    }
                }
                sectionLabel("Club")
                if bagNames.isEmpty {
                    Text("Your bag is empty. Add clubs in Settings, or use Other…")  // PLACEHOLDER: empty-bag hint
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                ClubPicker(
                    names: ClubChoices.names(bag: bagNames, current: working.clubName),
                    selection: $working.clubName,
                    onCustom: {
                        customClubName = ""
                        askCustomClub = true
                    }
                )
                sectionLabel(mode == .putting ? "Putts" : "Shots")
                RepsStepper(block: $working)
                FieldCard(label: "Note (optional)") {
                    TextField("e.g. 95 m, half swing", text: $working.note)  // PLACEHOLDER: note prompt
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.ink)
                }
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.top, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            FooterCTA(title: "Done", isEnabled: working.isValid) {
                onDone(working)
                dismiss()
            }
            .background(Theme.sheet)
        }
        .alert("Club name", isPresented: $askCustomClub) {  // PLACEHOLDER: custom club alert copy
            TextField("Club name", text: $customClubName)
            Button("Cancel", role: .cancel) {}
            Button("Use") {
                let name = customClubName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { working.clubName = name }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.sheet)
        .presentationCornerRadius(Theme.Radius.sheet)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.footnoteMedium)
            .foregroundStyle(Theme.secondaryText)
    }
}

struct ClubPicker: View {
    let names: [String]
    @Binding var selection: String
    let onCustom: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.rowGap), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.rowGap) {
            ForEach(names, id: \.self) { name in
                Chip(title: name, isSelected: name == selection) { selection = name }
            }
            Chip(title: "Other…", isSelected: false, action: onCustom)  // PLACEHOLDER: custom club chip label
        }
    }
}

struct RepsStepper: View {
    @Binding var block: BlockDraft

    var body: some View {
        VStack(spacing: Theme.Spacing.sheetGap) {
            HStack(spacing: 12) {
                bigStep(-10)
                Text("\(block.targetReps)")
                    .font(Theme.Typography.stepperValue)
                    .tracking(Theme.Typography.stepperValueTracking)
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                bigStep(10)
            }
            HStack(spacing: Theme.Spacing.rowGap) {
                ForEach([-5, -1, 1, 5], id: \.self) { fineStep($0) }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .contain)
    }

    private func label(_ delta: Int) -> String { delta < 0 ? "−\(-delta)" : "+\(delta)" }

    private func canStep(_ delta: Int) -> Bool {
        var copy = block
        copy.adjustReps(by: delta)
        return copy.targetReps != block.targetReps
    }

    private func step(_ delta: Int) {
        withAnimation { block.adjustReps(by: delta) }
    }

    private func bigStep(_ delta: Int) -> some View {
        Button(label(delta)) { step(delta) }
            .font(Theme.Typography.stepperButton)
            .foregroundStyle(Theme.ink)
            .frame(width: 96, height: 64)
            .background(Theme.fill, in: .rect(cornerRadius: Theme.Radius.cta))
            .buttonStyle(.plain)
            .disabled(!canStep(delta))
    }

    private func fineStep(_ delta: Int) -> some View {
        Button(label(delta)) { step(delta) }
            .font(Theme.Typography.chip)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .overlay { Capsule().strokeBorder(Theme.hairline, lineWidth: 1.5) }
            .contentShape(.capsule)
            .buttonStyle(.plain)
            .disabled(!canStep(delta))
    }
}
```

### `Reps/UI/Library/LibraryPlaceholderView.swift`

```swift
import SwiftUI

// TODO(#24): replace with the video library.
struct LibraryPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Library",
                systemImage: "film.stack",
                description: Text("Your clips will show up here.")  // PLACEHOLDER: library empty copy
            )
            .navigationTitle("Library")
        }
    }
}
```

### `Reps/UI/PreviewData.swift`

```swift
#if DEBUG
    import SwiftData

    // Seeded in-memory store for #Previews only (sample content from the Figma frames).
    enum PreviewData {
        static func container() -> ModelContainer {
            let container = try! RepsStore.makeContainer(inMemory: true)
            let context = container.mainContext
            let bag = [
                "Driver", "3 wood", "5 wood", "4 hybrid", "5 iron", "6 iron", "7 iron", "8 iron", "9 iron", "PW", "GW",
                "SW", "LW", "Putter",
            ]
            for (index, name) in bag.enumerated() { context.insert(BagClub(name: name, sortOrder: index)) }
            let plans: [(String, PracticeMode, Bool, [(String, Int, String?)])] = [
                (
                    "Wedge day", .rangeCounterWithClips, false,
                    [
                        ("PW", 40, "110 m"), ("GW", 30, "95 m, half swing"), ("SW", 40, "80 m"),
                        ("LW", 30, "60 m, flop"), ("PW", 30, nil),
                    ]
                ),
                ("Irons ladder", .rangeCounter, true, [("5 iron", 30, nil), ("6 iron", 30, nil), ("7 iron", 30, nil)]),
                (
                    "Putting 3-6-9", .putting, true,
                    [("Putter", 30, "3 ft"), ("Putter", 30, "6 ft"), ("Putter", 30, "9 ft")]
                ),
            ]
            for (name, mode, ordered, blocks) in plans {
                let plan = PracticePlan(name: name, mode: mode, isOrderMandatory: ordered)
                context.insert(plan)
                plan.blocks = blocks.enumerated().map {
                    PlanBlock(clubName: $1.0, targetReps: $1.1, note: $1.2, order: $0)
                }
            }
            return container
        }
    }
#endif
```

### `Reps/App/RootView.swift`

```swift
import SwiftData
import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Plans", systemImage: "list.bullet.rectangle") {  // PLACEHOLDER: Plans tab icon
                PlansView(
                    onStartPlan: { _ in
                        // TODO(#9): start a session for this plan
                    },
                    onStartFreeSession: {
                        // TODO(#9): start a free session
                    }
                )
            }
            Tab("Library", systemImage: "film.stack") {  // PLACEHOLDER: Library tab icon
                LibraryPlaceholderView()
            }
        }
        .tint(Theme.accent)
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
Root TabView: Plans and Library (placeholder until #24).
- `RootView`: tabs tinted `Theme.accent`; the Start closures are `TODO(#9)`
```

Add after `Reps/Session/SessionController.swift`:

```
## Reps/Plans/PlanDraft.swift
The plan editor's working copy (spec F1, F24, F28); nonisolated values, nothing persisted.
- `BlockDraft(id:clubName:targetReps:note:)`: `repsRange` 1...999, `defaultReps` 30; `trimmedClubName`, `storedNote` (trimmed, nil if blank), `isValid`, `adjustReps(by:)` clamps
- `RemovedBlock`: a removed block and its former index, for the undo toast; `id` is the block's
- `PlanDraft(name:mode:isOrderMandatory:isStrictCount:blocks:)`: `Equatable` (the editor compares it to the opening draft to detect changes); `trimmedName`, `totalReps`, `canSave` (name, ≥1 block, all blocks valid)
- `index(of:)`, `upsert(_:)` (replace by id or append), `removeBlock(id:) -> RemovedBlock?`, `restore(_:)` (old index, clamped; ignores duplicates), `moveBlocks(fromOffsets:toOffset:)` (SwiftUI move semantics without SwiftUI)

## Reps/Plans/PlanSummary.swift
Copy for plan cards and block rows; nonisolated.
- `reps(_:mode:)` ("1 shot", "90 putts"), `blocks(_:)`, `totals(blockCount:totalReps:mode:)`, `subtitle(blockCount:totalReps:mode:isOrderMandatory:)` (adds "in order"/"any order"), `blockDetail(targetReps:note:mode:)`
- `lastDone(_:now:calendar:locale:)`: today / weekday within 6 days / "Sep 9" / "Sep 9, 2025"; nil → placeholder "Not done yet"

## Reps/Plans/ClubChoices.swift
- `ClubChoices.names(bag:current:)`: picker names in bag order, trimmed, deduped; an off-bag current club goes last (F19)

## Reps/Plans/PlanLibrary.swift
Plan writes for the list and editor; MainActor; every write saves.
- `draft(from:) -> PlanDraft`: blocks in `sortedBlocks` order, ids kept, nil note → ""
- `save(_:to:in:now:) throws -> PracticePlan`: creates when `to` is nil; keeps block objects by id (results stay linked), inserts new ones with the draft id, deletes removed ones (results keep their snapshot), renumbers `order` 0..<n, trims name/club
- `duplicate(_:in:now:) throws -> PracticePlan`: "<name> copy", new block objects in order 0..<n, no sessions
- `delete(_:in:) throws`: sessions keep `planName` (nullify), blocks cascade
- `lastDone(_:) -> Date?`: newest `endedAt ?? startedAt` of finished sessions, filtered in Swift (ADR 0013)

## Reps/UI/Theme/Theme.swift
Literal Figma values (docs/design.md): colours (`ink`, `secondaryText`, `accent`, `card`, `fill`, `hairline`, `sheet`, `danger`…), `Typography` (text styles where Figma matches their default size), `Spacing`, `Radius`.

## Reps/UI/Components/*.swift
Shared by every screen.
- `PrimaryButtonStyle`: full-width green CTA, dimmed when disabled; `FooterCTA(title:isEnabled:action:accessory:)`: bottom inset with the CTA and an optional view above it (the undo toast)
- `PillButtonStyle(kind:)`: capsule "Start" (`.onAccent` white on green, `.neutral` on `fill`)
- `Chip(title:isSelected:action:)`: grid chip (clubs; tags later)
- `DashedAddButton(title:font:verticalPadding:cornerRadius:action:)`: "+  New plan" / "+  Add block"
- `ToggleRow(title:subtitle:isOn:)`, `FieldCard(label:content:)`: grey cards for switches and inputs
- `BlockRow(clubName:detail:targetReps:)`: handle, club, detail, green target, chevron
- `UndoToast(message:onUndo:)`, `UndoToast.duration` (5 s, §5.3c); `View.undoToastTimer(_:)` clears the bound item after the duration

## Reps/UI/Plans/PracticeMode+Title.swift
- `PracticeMode.title`: "Range", "Range + clips", "Putting"

## Reps/UI/Plans/PlansView.swift
Figma 01 Plans.
- `PlansView(onStartPlan:onStartFreeSession:)`: `@Query` plans by `createdAt`; free-session card, plan cards (tap → editor, Start → closure), swipe Duplicate / Delete (delete asks first), "New plan"; editor in a full-screen cover; Settings is `TODO(#6)`
- `PlanEditorTarget`: `.new` / `.edit(plan)` for the cover

## Reps/UI/Plans/PlanCard.swift
- `PlanCard(plan:onOpen:onStart:)`: name, `PlanSummary.subtitle`, last done, Start (disabled without blocks)
- `FreeSessionCard(onStart:)`

## Reps/UI/Plans/PlanEditorView.swift
Figma 02 + 13. Edits a `PlanDraft`; only Save writes.
- `PlanEditorView(plan:)`: nil = new plan; name, mode segments, order/strict toggles, blocks (tap → sheet, long-press drag to reorder, swipe delete → 5 s undo toast), Add block, Save plan (disabled until `canSave`); Cancel with changes → "Discard changes?"

## Reps/UI/Plans/BlockEditorSheet.swift
Figma 06.
- `BlockEditorSheet(block:mode:title:isNew:onDone:onRemove:)`: edits a copy; club grid from the bag (`BagClub.isInBag`) plus "Other…" (custom name alert); reps stepper; note; Done hands back, Remove (existing blocks only) removes with undo
- `ClubPicker(names:selection:onCustom:)`: 4-column chip grid
- `RepsStepper(block:)`: ±10 big buttons, ±5/±1 pills, disabled at the 1...999 bounds

## Reps/UI/Library/LibraryPlaceholderView.swift
- `LibraryPlaceholderView`: `ContentUnavailableView` until #24

## Reps/UI/PreviewData.swift
- `PreviewData.container()` (DEBUG): in-memory store with the Figma sample bag and plans, for `#Preview`s only
```

Add after `RepsTests/SessionResumeTests.swift`:

```
## RepsTests/PlanDraftTests.swift
Save validity, reps clamping, notes, upsert, move semantics, remove/restore, change detection (discard alert).

## RepsTests/PlanSummaryTests.swift
Reps nouns, subtitles, block detail, "last done" formatting (en_US, UTC).

## RepsTests/ClubChoicesTests.swift
Bag order, dedupe, off-bag current club.

## RepsTests/PlanLibraryTests.swift
In-memory store: create, round trip, edit in place with renumbering, removed blocks keep result snapshots, duplicate deep copy, delete keeps sessions, last done.
```
