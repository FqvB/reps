# #24 Video library

Goal: replace the Library tab placeholder with the clip library of Figma 04: a 2-column grid of clips (newest first), search, filter chips (club, angle, month, ★, tags, session; all AND), and a bulk mode (long-press or "Select") to retag club, add/remove a tag, favourite, or delete, each with a 5 s Undo toast.

Spec: F15, F16, §5.3b (grid, filters, bulk, autocomplete), §5.3c (undo toast 5 s; thumbnails cached). ADRs: 0006 (clips in `Documents/clips/<sessionId>/<shotId>.mov`), 0009 (synced folders, MainActor default), 0012/0013 (schema, `ClipFileRemoving`, predicate limits). Q23 (answered here). Figma: 04 Library `3:55`.

**Base: `main` (at `6d227f6`, with #6 settings and #12 session log merged).** Branch `feat/24-video-library`. If `ClipStorage`, `ClipFileRemoving`/`NoClipFiles`, `ClipSpy`, `SessionDisplay.title/angleTitle`, `ClubChoices.names`, `UndoToast`/`undoToastTimer`, `AppSettings.angleChoices` or `PreviewData.container()` differ from what's described here, stop and report.

**How this was checked.** Every file in the appendices was written into a `git archive main` copy, formatted with the repo's swift-format (`lint --strict` clean), built by Xcode, and the **full `Unit` plan passed on both simulators: 195 tests in 23 suites on iOS 27 (A26BAE3A…) and iOS 26.5 (6D2623EF…)**, including the 26 new/extended library tests. No new compiler warnings. The views were built, not run. **Copy every file exactly.**

Out of scope: the clip player (#25; tapping a tile pushes a `TODO(#25)` placeholder), writing clips and the real `ClipFileRemoving` (#22; `NoClipFiles` until then), Save to Photos (#26), share, tempo computation (#27).

## Q23 spike result (answer)

Spiked in a scratch copy of the app with an on-disk SQLite store (`RepsStore.makeContainer(url:)`, fresh `ModelContext` so the fetch hits SQLite), on both simulators. Source kept at `scratchpad/q23-spike-final.swift` (not for the repo).

| Predicate on `ShotRecord` | iOS 27 | iOS 26.5 |
|---|---|---|
| `$0.tags.contains(captured)` / literal / `fetchCount` | **crash** (SIGSEGV in `_NSCoreDataStringSearch`) | **crash** |
| two tags ANDed, `evaluate`-composed, `tags.allSatisfy`, `tags.isEmpty` | **crash** (SIGSEGV / Obj-C exception) | **crash** |
| `clubName == captured` | OK | OK |
| `blockResult?.session?.id == capturedID` | OK | **crash** (Obj-C exception) |
| `clipFileName != nil` (+ sort by `timestamp` desc) | OK | OK |
| `ids.contains($0.id)` (captured `[UUID]`) | OK | OK |
| `$0.isFavourite` | OK | OK |

`tags` is stored as an encoded blob, so Core Data runs a string search on bytes; even where it didn't crash it would be a substring match ("fade" would match "fader"). **Answer: no tag predicates.** The library fetches `clipFileName != nil` sorted by `timestamp` (the only SQL predicate) and applies every filter, including tag AND, in memory (`LibraryFilter.matches`). A `Tag` model isn't needed at personal scale (hundreds to a few thousand clips); revisit only if the grid gets slow. Writes use `ids.contains($0.id)`, which works on both.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Favourite field | `ShotRecord.isFavourite` **already exists** in V1 (`schemaShapeIsPinned` lists it). **No schema change, no RepsSchemaV2.** | Checked `Reps/Model/ShotRecord.swift` and `RepsStoreTests`. |
| What the grid lists | Shots with a `clipFileName` (spec: "every clip"). Until #22 that's none, so the app shows the empty state; previews seed clips. | Putting/range-only shots have no video. |
| Missing file | Tile keeps the Figma grey-green fill with a `video.slash` icon (`// PLACEHOLDER`). Also used when the stored name is unsafe. | Caller brief. |
| Thumbnails | `ClipThumbnails` actor (UI layer, AVFoundation, never in ShotDetector): memory `NSCache` → `Caches/thumbnails/<shotId>.jpg` → `AVAssetImageGenerator.image(at:)` at the clip's midpoint, max 480 px, then cached. | §5.3c: "generated once… cached; the grid never decodes video" after the first time. #22 can pre-fill the same cache at export (impact frame). |
| Clip path | New `ClipStorage.clipURL(fileName:sessionID:root:)`: `root/<sessionID.uuidString>/<fileName>`, **nil unless the name is a bare `*.mov`** (no `/ \ :`, control chars, or leading `.`). | The name comes from the store and reaches the filesystem. |
| Filters | Chips as `Menu`s (Figma order: Club, Angle, Date=month, ★, Tag, Session), filled when set, plus a "Clear" link. Tag menu is multi-toggle and stays open; a clip needs **every** chosen tag. Values come from all clips (bag order for clubs, most-used tags first, newest month/session first). | Figma 04 shows value chips; menus keep the bar one row. |
| Search | Native `.searchable` (drawer, always shown), prompt "Search clubs, tags, dates". Every whitespace word must appear (`localizedStandardContains`) in club, angle, a tag, session title, or the month/weekday name. ANDed with the chips. | Figma 04 has the field; spec doesn't define it (see new Q). |
| Order / grouping | Flat grid, newest first, ties by id. No section headers. | Figma 04. |
| Bulk mode | "Select" (top right) or long-press a tile. Title becomes "N clips", leading Select All / Deselect All, trailing Done, tab bar hidden, a bottom bar: Club (menu of in-bag clubs), Tags (sheet), ★ (favourite all unless all are already, then unfavourite), Delete. Selection stays on after an edit; delete ends it. | §5.3b. No Figma frame for bulk (new Q). |
| Tag sheet | Text field + history suggestions (autocomplete, max 8, contains-match) to add; "Remove" section lists tags on the selection. One tap applies and closes, so one Undo covers it. Tags trimmed, case kept (same as the session). | §5.3b "free text with autocomplete from your history". |
| Undo for edits | Each edit saves immediately and returns `[ShotSnapshot]` (id, club, tags, favourite); Undo writes them back (`LibraryEdits.restore`, shots deleted meanwhile are skipped). | Exact, cheap. |
| **Delete + undo** | **Deferred delete.** Delete hides the ids (`pendingDelete`) and shows "Deleted N clips / Undo". Nothing is written until the undo window ends: toast expiry, a new bulk action, leaving the tab (`onDisappear`), or the app leaving `.active`. Then `LibraryEdits.delete` deletes the rows, **saves, then** calls `ClipFileRemoving.removeClip` per clip, then drops the cached thumbnails. Undo just un-hides. No confirmation alert (§5.3c: the toast is the safety net). | Undo can't lose files because nothing was touched yet; order matches ADR 0013 (save, then files). If the app is killed inside the 5 s the clips simply come back (safe direction). |
| What delete removes | The `ShotRecord` row and its file. `BlockResult.repsCounted`/`repsManualAdjust` are **not** touched, so session counts, the log and completion don't change. | Caller brief; counts are counters, not `shots.count` (ADR 0013). New Q asks the owner. |
| Retag club | Changes `ShotRecord.clubName` only; the block's `clubName` stays. | Spec §5.1 comment on ShotRecord ("retagging one shot is cheap"). |
| Save failure | Each write rolls the context back (`context.rollback()`) and rethrows; the view shows an alert (`// PLACEHOLDER: error copy (#29)`). | Keeps the main context clean. |
| Clip detail | Tap → `NavigationStack(path:)` push of `ClipDetailPlaceholderView` (`TODO(#25)`). Tap vs long-press use `onTapGesture` + `onLongPressGesture` on the tile (not a `NavigationLink`) so a long press never also navigates. | |
| Theme | `Theme.thumbnail` `#8A9A84`, `Theme.favourite` `#E6D35A` in `Theme.swift` (the hex init is fileprivate); sizes in `Reps/UI/Library/LibraryTheme.swift` (13/12 pt tile text, radius 16, gap 10, thumb 120, play 28). | Figma 04 values. |

## Security note (flag for a look)

The issue has no review label, but this is the first UI that **deletes user clips in bulk** and the first code that **turns stored names into file URLs**. Recommend running `fable-security-reviewer` (or `/security-review`) on step 2 + the delete path in `LibraryView` before merging. Points to check:
1. `ClipStorage.clipURL` validation (tests cover `..`, `/`, `\`, `:`, newline, hidden, wrong extension). The real `ClipFileRemoving` (#22) must apply the same check before deleting; note added as `TODO(#22)` in the plan's #22 hand-off (Risks).
2. Delete order: rows saved first, files after; a failed save removes no files.
3. Thumbnails of deleted clips are removed from `Caches/thumbnails` (they'd otherwise outlive the clip). Thumbnails are written with `.atomic` only, same protection class as the clips (default); #22 decides file protection for both.
4. Deferred delete: killed within 5 s = nothing deleted.

## Final layout

```
Reps/Library/LibraryFilter.swift          new: LibraryClip, LibraryMonth, LibraryFilter
Reps/Library/LibraryDisplay.swift         new: LibrarySessionOption, LibraryDisplay
Reps/Library/LibraryEdits.swift           new: LibraryClip.init?(_: ShotRecord), ShotSnapshot, LibraryUndo, LibraryEdits
Reps/Settings/ClipStorage.swift           changed: + clipURL(fileName:sessionID:root:)
Reps/UI/Theme/Theme.swift                 changed: + thumbnail, favourite
Reps/UI/Library/LibraryTheme.swift        new: library fonts/sizes, LibraryMetrics
Reps/UI/Library/ClipThumbnails.swift      new: actor ClipThumbnails
Reps/UI/Library/ClipTile.swift            new: ClipTile, ClipThumbnail (private)
Reps/UI/Library/LibraryFilterBar.swift    new: LibraryFilterBar, FilterChipLabel (private)
Reps/UI/Library/LibraryTagSheet.swift     new: LibraryTagSheet
Reps/UI/Library/LibraryBulkBar.swift      new: LibraryBulkBar
Reps/UI/Library/ClipDetailPlaceholderView.swift  new: TODO(#25)
Reps/UI/Library/LibraryView.swift         new: LibraryView, PreviewData.libraryContainer(), #Preview
Reps/UI/Library/LibraryPlaceholderView.swift     deleted
Reps/App/RootView.swift                   changed: LibraryPlaceholderView() → LibraryView()
RepsTests/LibraryDisplayTests.swift       new (14 tests)
RepsTests/LibraryEditsTests.swift         new (7 tests)
RepsTests/ClipStorageTests.swift          changed: + ClipURLTests (2 tests, 1 parameterized ×9)
docs/code-reference.md, docs/design.md, docs/open-questions.md, docs/adr/0013-session-engine-rules.md, docs/roadmap.md
```

Never edit `project.pbxproj`: folders are synced (ADR 0009); the new `Reps/Library/` folder is picked up.

## Steps

Branch `feat/24-video-library` from `main`. From the repo root:

```sh
DEST27='platform=iOS Simulator,id=A26BAE3A-CDDE-45A8-892D-2359740C877A'   # iOS 27
DEST265='platform=iOS Simulator,id=6D2623EF-0394-46F9-BFEC-022E3D2B7FE8'  # iOS 26.5
T="xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan Unit"
```

Before each commit: `xcrun swift-format format --in-place --recursive --parallel Reps RepsTests`, then `xcrun swift-format lint --strict --recursive --parallel Reps RepsTests` must print nothing.

### Step 1: filter and display logic (TDD)

1. Add `RepsTests/LibraryDisplayTests.swift` (Appendix B). `$T -destination "$DEST27" -only-testing:RepsTests/LibraryDisplayTests` fails to compile.
2. Add `Reps/Library/LibraryFilter.swift` and `Reps/Library/LibraryDisplay.swift` (Appendix A). Rerun: 14 tests pass.
3. `docs/code-reference.md`: add the two entries from "Docs" below (in the Reps/ part, after the `Reps/Log/...` entries) and the `RepsTests/LibraryDisplayTests.swift` entry (after `RepsTests/ExportTests.swift` or alphabetically where the RepsTests list is kept).
4. Commit `added library filters` / body `and filter logic with and semantics` + `Refs #24`.

### Step 2: bulk edits and clip paths (TDD)

1. Add `RepsTests/LibraryEditsTests.swift` and append `ClipURLTests` to `RepsTests/ClipStorageTests.swift` (Appendix B). They fail to compile.
2. Add `Reps/Library/LibraryEdits.swift` and the `clipURL` function in `ClipStorage.swift` (Appendix A). Run `$T -destination "$DEST27" -only-testing:RepsTests/LibraryEditsTests -only-testing:RepsTests/ClipURLTests -only-testing:RepsTests/ClipStorageTests`, then the same on `$DEST265` (these tests run the `ids.contains` / `clipFileName` predicates). All pass.
3. code-reference: `Reps/Library/LibraryEdits.swift` entry, the new `clipURL` line under ClipStorage, the two test entries.
4. Commit `added library bulk edits` / `retag, tag, favourite, delete with undo snapshots` + `Refs #24`.

### Step 3: library screen

1. Add the theme colours to `Theme.swift` and the `Reps/UI/Library/*.swift` files (Appendix A). Delete `Reps/UI/Library/LibraryPlaceholderView.swift`. In `RootView.swift` replace `LibraryPlaceholderView()` with `LibraryView()` (only change there).
2. Build and run the whole `Unit` plan on both: `$T -destination "$DEST27"` and `$T -destination "$DEST265"` (expected: 195 tests in 23 suites pass on each, if main hasn't grown).
3. Smoke check (optional, not a test): open `LibraryView.swift`'s `#Preview` or run the app: Library tab shows "No clips yet" (no clips exist before #22); in the preview, tiles show the missing-file icon, chips filter, long-press enters bulk mode, Delete hides tiles and Undo brings them back.
4. code-reference: UI/Library entries, Theme line, RootView line; remove the `LibraryPlaceholderView` entry.
5. Commit `added video library screen` / `grid, filter chips, search and bulk mode` + `Refs #24`.

### Step 4: docs

1. `docs/open-questions.md`: move Q23 to Resolved and add the new questions (text below).
2. `docs/adr/0013-session-engine-rules.md`, Consequences: append the predicate bullet (text below).
3. `docs/design.md`: table row and note (text below).
4. `docs/roadmap.md`: mark #24 done (☑) in the Phase 4 table, same style as other finished rows.
5. Commit `answered q23` / `tag predicates crash on ios 27 and 26.5; filter in memory` + `Closes #24`. PR title `added video library`, body: `Grid, AND filters, bulk retag/tag/favourite/delete with undo. Q23: in-memory tag filtering.` + `Closes #24`.

## Tests

Suite `Unit`, filtered as above; views are build-only (CLAUDE.md table).

- `LibraryDisplayTests` (14): newest-first + id tiebreak; tag AND (and "fade" ≠ "fader"); every chip ANDed (club, angle, month, session, tags, ★); search words ANDed across fields incl. month/weekday/angle; hidden (pending delete) left out; club options (bag order then alphabetical); tag options (use count, then name); month/session options newest first; free-session name; month title with/without year; tile copy (title, tempo "3.1", tag line, counts, tag chip "fade +1", undo message); tile dates ("Today 8:00 AM", "Mon 6:00 PM", "Sep 9", "Nov 20, 2025" with U+202F before AM/PM, en_US, UTC); favourite target.
- `LibraryEditsTests` (7, in-memory store): `LibraryClip` copies session id/title/angle and is nil without a clip; set club + undo (and blank club is a no-op); add/remove tag + undo in either order; favourite + undo; restore skips deleted shots; delete removes rows (incl. from `block.shots`), ignores unknown ids, reports deleted ids, removes files only for shots with a clip, never calls `removeClips`; delete leaves `repsCounted` alone.
- `ClipURLTests` (2): valid name path; 9 unsafe names rejected.

## Docs

**code-reference.md** (entries to add; keep existing format):

```
## Reps/Library/LibraryFilter.swift
Library filter model (F15, §5.3b); tags and everything else are filtered in memory (Q23).
- `LibraryClip`: plain copy of a ShotRecord with a clip (id, timestamp, club, tags, favourite, tempo, file name, session id/title/start, angle)
- `LibraryMonth(year:month:)`, `init(_:calendar:)`: month filter value, Comparable
- `LibraryFilter`: club, angle, month, sessionID, tags (all required), favouritesOnly, searchText; `hasChipFilters`; `matches(_:calendar:locale:)` ANDs every set filter and every search word (club, angle, tags, session title, month/weekday name)

## Reps/Library/LibraryDisplay.swift
Grid order, filter choices and tile copy (Figma 04); pure, unit-tested.
- `LibrarySessionOption(id:title:startedAt:)`
- `LibraryDisplay.visible(_:filter:hidden:calendar:locale:)`: filtered, newest first (ties by id), minus pending deletes
- `countTitle`, `clubOptions(_:bag:)` (bag order, then others A–Z), `tagOptions` (most used first; also autocomplete), `monthOptions`, `sessionOptions`, `sessionTitle` ("Wedge day · Sep 16"), `monthTitle` (year only when not this year), `angleOptionTitle`, `tagChipTitle` ("fade +1"), `tileTitle` ("GW · face-on"), `tileDate` (Today/weekday/date), `tempo` ("3.1"), `tagLine`, `favouriteTarget` (false only when all are favourites), `undoMessage`

## Reps/Library/LibraryEdits.swift
Bulk library writes (F15, §5.3c).
- `LibraryClip.init?(_: ShotRecord)`: nil without `clipFileName`; session title via `SessionDisplay.title`, angle from the session (`.none` without one)
- `ShotSnapshot`, `LibraryUndo(message:kind:)` (`.restore([ShotSnapshot])` / `.delete(Set<UUID>)`)
- `LibraryEdits.setClub/addTag/removeTag/setFavourite(... on:in:) throws -> [ShotSnapshot]`: save, or roll back and rethrow; blank club/tag is a no-op (`[]`)
- `restore(_:in:)`: writes snapshots back, skipping deleted shots
- `delete(ids:in:clipFiles:) throws -> [UUID]`: deletes the rows, saves, then `removeClip` per clip file (ADR 0013 order); block counters untouched

## Reps/UI/Library/LibraryView.swift
Figma 04 Library tab.
- `LibraryView(clipFiles:)`: `@Query` shots with `clipFileName != nil` by timestamp desc (the only SQL predicate, Q23); search + `LibraryFilterBar`; 2-column `LazyVGrid` of `ClipTile`; tap pushes `ClipDetailPlaceholderView`, long-press/"Select" starts bulk mode (`LibraryBulkBar`, `LibraryTagSheet`); Undo toast per bulk action; delete is hidden until the toast ends, then `LibraryEdits.delete` + thumbnail cleanup; `NoClipFiles` until #22
- `PreviewData.libraryContainer()` (DEBUG): 8 clips without files

## Reps/UI/Library/ClipTile.swift
- `ClipTile(clip:isSelecting:isSelected:)`: thumb (★, play mark, selection check), club · angle, date · tempo, tags; missing file shows `video.slash`

## Reps/UI/Library/ClipThumbnails.swift
- `ClipThumbnails` (actor, `.shared`): `image(shotID:clipURL:) async -> UIImage?` memory → `Caches/thumbnails/<id>.jpg` → middle frame via `AVAssetImageGenerator` (max 480 px), cached; nil when the file is missing; `remove(_:)` drops both caches

## Reps/UI/Library/LibraryFilterBar.swift
- `LibraryFilterBar(filter:clubs:tags:months:sessions:)`: Figma 04 chips as menus (Club, Angle, Date, ★ toggle, Tag multi-toggle, Session) + Clear

## Reps/UI/Library/LibraryTagSheet.swift
- `LibraryTagSheet(selectedCount:onSelection:suggestions:onAdd:onRemove:)`: add (field + history suggestions) or remove one tag; applies and closes

## Reps/UI/Library/LibraryBulkBar.swift
- `LibraryBulkBar(clubs:isEnabled:favouriteTarget:onClub:onTags:onFavourite:onDelete:)`: bottom bar in bulk mode (no Figma frame)

## Reps/UI/Library/ClipDetailPlaceholderView.swift
- `ClipDetailPlaceholderView(clip:)`: `TODO(#25)` player

## Reps/UI/Library/LibraryTheme.swift
Figma 04 values: `Theme.Typography.filterChip/filterChipSelected/resultCount/tileTitle/tileDetail/tileTempo/tileStar/tilePlay`, `Theme.Spacing.gridGap`, `Theme.Radius.tile`, `LibraryMetrics.thumbnailHeight/playSize`

## RepsTests/LibraryDisplayTests.swift
Filter AND semantics, ordering, options and tile copy (fixed UTC calendar, en_US).

## RepsTests/LibraryEditsTests.swift
Bulk edits, undo snapshots and delete order against an in-memory store with `ClipSpy`.
```

Also: under `## Reps/Settings/ClipStorage.swift` add `- \`ClipStorage.clipURL(fileName:sessionID:root:) -> URL?\`: \`root/<sessionID>/<fileName>\`; nil unless a bare \`.mov\` name (no separators, control chars, leading dot)`; under `## Reps/UI/Theme/Theme.swift` (or wherever the colour list is) add `thumbnail`, `favourite` (Figma 04); in the `RootView` line change nothing but "Library" now hosts `LibraryView`; add `ClipURLTests` to the `RepsTests/ClipStorageTests.swift` entry; **delete** the `## Reps/UI/Library/LibraryPlaceholderView.swift` entry.

**open-questions.md**: delete the Q23 row from Open; add to Resolved (after Q24):

`| Q23 | Can a \`#Predicate\` filter on \`tags: [String]\`? | No. Spiked on iOS 27 and 26.5 with an SQLite store: every tag predicate (\`contains\`, AND, \`isEmpty\`, \`allSatisfy\`, composed \`evaluate\`) crashes the fetch; tags are an encoded blob. The library fetches \`clipFileName != nil\` by timestamp and filters tags (AND) and everything else in memory. No Tag model needed at this scale. | ADR 0013, docs/plans/24-video-library.md |`

Add to Open, next free numbers (**Q35, Q36 if #5 has taken Q34; otherwise Q34, Q35**; no code comment refers to them):

`| Q35 | Library delete removes the ShotRecord and its file, but not the session's rep counts (so the log still says 62 shots after deleting 10 clips). Should it only remove the clip (clear \`clipFileName\`) and keep the shot for stats/export? And is Undo alone (no alert) enough for bulk delete? | – (#24 ships row delete + undo) | Clearing only the file would keep tempo/timestamps; it's a one-function change in \`LibraryEdits.delete\`. |`

`| Q36 | The library's bulk mode (bottom bar: Club, Tags, ★, Delete), tag sheet and filter menus have no Figma frame; search also matches month/weekday names. OK as built? | – (#24 ships these) | Choices in docs/plans/24-video-library.md. A Figma frame can follow after use. |`

**adr/0013-session-engine-rules.md**, Consequences, append:
`- SwiftData predicates that work on both iOS 27 and 26.5: scalar comparisons, \`optional != nil\`, captured \`[UUID]\`.contains(id). Crash on both: anything on \`tags: [String]\` (Q23). Crash on 26.5: optional-chained relationships (\`blockResult?.session?.id\`). Filter those in memory.`

**design.md**: table row `| Video library | #24 | [04 Library](…node-id=3-55) |` stays; below the table add:
`- Video library (#24): Figma 04 chips are menus (Club, Angle, Date, ★, Tag, Session), filled when set; search is the native drawer field. Bulk mode (long-press or Select) uses a bottom bar and a tag sheet, which have no frame (Q36). Colours \`Theme.thumbnail\`, \`Theme.favourite\`; sizes in \`Reps/UI/Library/LibraryTheme.swift\`.`

## Placeholders (`// PLACEHOLDER:` in code)

1. `LibraryDisplay.tagChipTitle`: filter chip copy ("Tag")
2. `LibraryDisplay.tileDate`: tile date copy ("Today …")
3. `LibraryDisplay.undoMessage`: undo toast copy ("Deleted 3 clips")
4. `LibraryFilterBar`: filter chip copy ("Club", "Angle", "Date", "Session"), clear-filters copy, empty tag menu copy
5. `LibraryTagSheet`: tag field copy
6. `LibraryBulkBar`: bulk bar design (no Figma)
7. `ClipThumbnails`: thumbnail size (480 px); middle frame stands in for the impact frame until #22
8. `ClipTile`: missing clip file tile (`video.slash`)
9. `ClipDetailPlaceholderView`: clip detail copy (+ `TODO(#25)`)
10. `LibraryView`: library empty copy, no-results copy/label, error copy (#29) ×3; `TODO(#22)` for `clipFiles`

## Risks and hand-offs

- **#22 must**: write clips as `Documents/clips/<session.id.uuidString>/<shot.id.uuidString>.mov` (uppercase UUID strings, what `clipURL` and `ClipSpy` use), set `clipFileName` to the bare name, supply the real `ClipFileRemoving` to `LibraryView(clipFiles:)` and `RootView`/`SessionLogView`, **validate names before deleting** (reuse `ClipStorage.clipURL`), and ideally pre-fill `ClipThumbnails` at the impact frame. Also remove `Caches/thumbnails/<id>.jpg` when a whole session is deleted (log delete / discard) — today only library deletes clean thumbnails (none exist before #22).
- **Performance**: the grid maps every clip to `LibraryClip` and re-filters on each render. Fine for thousands of clips; if not, move the mapping into `@State` updated on `shots` change, or add a Tag model (Q23 note).
- **Deferred delete edge**: `scenePhase` going inactive (e.g. pulling down Control Centre) commits the delete early; Undo is then gone. Acceptable; noted in Q35.
- **Session log after library delete**: the log's "N clips" and summary "clips saved" drop, counts don't (Q35).
- **`Menu` + `Picker` with optional tags** and `menuActionDismissBehavior(.disabled)` for the tag menu were built but not exercised on device; if the tag menu closes on each toggle on iOS 26.5 it still works, just less smoothly.
- The active session is never visible while the library is used (full-screen cover), so library writes don't race `SessionController`.

## Appendix A: source (copy exactly)

### `Reps/Library/LibraryFilter.swift`

```swift
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
```

### `Reps/Library/LibraryDisplay.swift`

```swift
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
```

### `Reps/Library/LibraryEdits.swift`

```swift
import Foundation
import SwiftData

extension LibraryClip {
    // nil for shots without a clip; they aren't in the library.
    init?(_ shot: ShotRecord) {
        guard let clipFileName = shot.clipFileName else { return nil }
        let session = shot.blockResult?.session
        self.init(
            id: shot.id, timestamp: shot.timestamp, clubName: shot.clubName, tags: shot.tags,
            isFavourite: shot.isFavourite, tempoRatio: shot.tempoRatio, clipFileName: clipFileName,
            sessionID: session?.id, sessionTitle: session.map { SessionDisplay.title(planName: $0.planName) },
            sessionStartedAt: session?.startedAt, angle: session?.cameraAngle ?? .none)
    }
}

// The editable fields of one shot before a bulk edit, for Undo.
nonisolated struct ShotSnapshot: Equatable, Sendable {
    let id: UUID
    let clubName: String
    let tags: [String]
    let isFavourite: Bool
}

// A toast's worth of undo (§5.3c): edits restore snapshots; deletes are only hidden until committed.
struct LibraryUndo: Identifiable {
    enum Kind {
        case restore([ShotSnapshot])
        case delete(Set<UUID>)
    }

    let id = UUID()
    let message: String
    let kind: Kind
}

// Bulk library writes (F15). Each saves, and on a failed save rolls the context back and rethrows.
enum LibraryEdits {
    static func setClub(_ club: String, on shots: [ShotRecord], in context: ModelContext) throws -> [ShotSnapshot] {
        let club = club.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !club.isEmpty else { return [] }
        return try edit(shots, in: context) { $0.clubName = club }
    }

    // Trimmed like session tags (SessionDisplay.adding); shots that already have it keep their order.
    static func addTag(_ raw: String, to shots: [ShotRecord], in context: ModelContext) throws -> [ShotSnapshot] {
        let tag = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return [] }
        return try edit(shots, in: context) { shot in
            if !shot.tags.contains(tag) { shot.tags.append(tag) }
        }
    }

    static func removeTag(_ tag: String, from shots: [ShotRecord], in context: ModelContext) throws -> [ShotSnapshot] {
        try edit(shots, in: context) { $0.tags.removeAll { $0 == tag } }
    }

    static func setFavourite(_ value: Bool, on shots: [ShotRecord], in context: ModelContext) throws
        -> [ShotSnapshot]
    {
        try edit(shots, in: context) { $0.isFavourite = value }
    }

    // Shots deleted since the snapshot are skipped.
    static func restore(_ snapshots: [ShotSnapshot], in context: ModelContext) throws {
        let byID = Dictionary(snapshots.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ids = Array(byID.keys)
        let shots = try context.fetch(FetchDescriptor<ShotRecord>(predicate: #Predicate { ids.contains($0.id) }))
        try save(context) {
            for shot in shots {
                guard let snapshot = byID[shot.id] else { continue }
                shot.clubName = snapshot.clubName
                shot.tags = snapshot.tags
                shot.isFavourite = snapshot.isFavourite
            }
        }
    }

    // Deletes the shots, saves, then removes their clip files (ADR 0013 order). Returns the ids actually deleted.
    // Shots already gone (e.g. their session was deleted from the log) are skipped.
    @discardableResult
    static func delete(ids: Set<UUID>, in context: ModelContext, clipFiles: any ClipFileRemoving) throws -> [UUID] {
        let wanted = Array(ids)
        let shots = try context.fetch(FetchDescriptor<ShotRecord>(predicate: #Predicate { wanted.contains($0.id) }))
        let files: [(fileName: String, sessionID: UUID)] = shots.compactMap { shot in
            guard let fileName = shot.clipFileName, let sessionID = shot.blockResult?.session?.id else { return nil }
            return (fileName, sessionID)
        }
        let deleted = shots.map(\.id)
        try save(context) {
            for shot in shots {
                shot.blockResult?.shots.removeAll { $0 === shot }
                context.delete(shot)
            }
        }
        for file in files { clipFiles.removeClip(fileName: file.fileName, sessionID: file.sessionID) }
        return deleted
    }

    private static func edit(_ shots: [ShotRecord], in context: ModelContext, _ change: (ShotRecord) -> Void) throws
        -> [ShotSnapshot]
    {
        let snapshots = shots.map {
            ShotSnapshot(id: $0.id, clubName: $0.clubName, tags: $0.tags, isFavourite: $0.isFavourite)
        }
        try save(context) { shots.forEach(change) }
        return snapshots
    }

    private static func save(_ context: ModelContext, _ changes: () -> Void) throws {
        changes()
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
```

### `Reps/Settings/ClipStorage.swift` (insert after `clipsDirectory`)

```swift
    // The file for a stored clip name; nil unless it's a bare "<name>.mov", since the name comes from the store.
    static func clipURL(fileName: String, sessionID: UUID, root: URL = clipsDirectory) -> URL? {
        let invalid = CharacterSet(charactersIn: "/\\:").union(.controlCharacters)
        guard !fileName.hasPrefix("."), fileName.rangeOfCharacter(from: invalid) == nil,
            fileName.lowercased().hasSuffix(".mov")
        else { return nil }
        return root.appending(path: sessionID.uuidString, directoryHint: .isDirectory)
            .appending(path: fileName, directoryHint: .notDirectory)
    }
```

### `Reps/UI/Theme/Theme.swift` (after `accentDeep`)

```swift
    static let thumbnail = Color(hex: 0x8A9A84)
    static let favourite = Color(hex: 0xE6D35A)
```

### `Reps/App/RootView.swift`

```swift
            Tab("Library", systemImage: "film.stack") {  // PLACEHOLDER: Library tab icon
                LibraryView()
            }
```

### `Reps/UI/Library/LibraryTheme.swift`

```swift
import SwiftUI

// Library values from Figma 04 (docs/design.md).
extension Theme.Typography {
    static let filterChip = Font.system(size: 13, weight: .medium)
    static let filterChipSelected = Font.system(size: 13, weight: .semibold)
    static let resultCount = Font.system(size: 13, weight: .medium)
    static let tileTitle = Font.system(size: 13, weight: .semibold)
    static let tileDetail = Font.system(size: 12)
    static let tileTempo = Font.system(size: 12, weight: .semibold)
    static let tileStar = Font.system(size: 13)
    static let tilePlay = Font.system(size: 11)
}

extension Theme.Spacing {
    static let gridGap: CGFloat = 10
}

extension Theme.Radius {
    static let tile: CGFloat = 16
}

enum LibraryMetrics {
    static let thumbnailHeight: CGFloat = 120
    static let playSize: CGFloat = 28
}
```

### `Reps/UI/Library/ClipThumbnails.swift`

```swift
import AVFoundation
import UIKit

// Tile images: memory, then Caches/thumbnails/<shotId>.jpg, then one frame decoded from the clip (§5.3c).
actor ClipThumbnails {
    static let shared = ClipThumbnails()
    static let maximumSize = CGSize(width: 480, height: 480)  // PLACEHOLDER: thumbnail size

    private let memory = NSCache<NSUUID, UIImage>()
    private let directory: URL

    init(directory: URL = URL.cachesDirectory.appending(path: "thumbnails", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    // nil when the clip file is missing or can't be decoded; the tile keeps its placeholder.
    func image(shotID: UUID, clipURL: URL) async -> UIImage? {
        if let cached = memory.object(forKey: shotID as NSUUID) { return cached }
        let file = cacheFile(shotID)
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            memory.setObject(image, forKey: shotID as NSUUID)
            return image
        }
        guard FileManager.default.fileExists(atPath: clipURL.path(percentEncoded: false)) else { return nil }
        let asset = AVURLAsset(url: clipURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = Self.maximumSize
        let duration = (try? await asset.load(.duration)) ?? .zero
        // PLACEHOLDER: the middle of the clip stands in for the impact frame until #22 stores one.
        let time = CMTimeMultiplyByRatio(duration, multiplier: 1, divisor: 2)
        guard let cgImage = try? await generator.image(at: time).image else { return nil }
        let image = UIImage(cgImage: cgImage)
        memory.setObject(image, forKey: shotID as NSUUID)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? image.jpegData(compressionQuality: 0.8)?.write(to: file, options: .atomic)
        return image
    }

    // Deleted clips must not leave frames behind in Caches.
    func remove(_ shotIDs: [UUID]) {
        for id in shotIDs {
            memory.removeObject(forKey: id as NSUUID)
            try? FileManager.default.removeItem(at: cacheFile(id))
        }
    }

    private func cacheFile(_ shotID: UUID) -> URL {
        directory.appending(path: "\(shotID.uuidString).jpg", directoryHint: .notDirectory)
    }
}
```

### `Reps/UI/Library/ClipTile.swift`

```swift
import SwiftUI

// One grid cell (Figma 04 "Clip"): thumbnail with ★ and play mark, then club · angle, date · tempo, tags.
struct ClipTile: View {
    let clip: LibraryClip
    let isSelecting: Bool
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnail
            meta
        }
        .background(Theme.card)
        .clipShape(.rect(cornerRadius: Theme.Radius.tile))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: Theme.Radius.tile).strokeBorder(Theme.accent, lineWidth: 3)
            }
        }
        .contentShape(.rect(cornerRadius: Theme.Radius.tile))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var thumbnail: some View {
        ClipThumbnail(clip: clip)
            .frame(maxWidth: .infinity)
            .frame(height: LibraryMetrics.thumbnailHeight)
            .clipped()
            .overlay(alignment: .topTrailing) {
                if clip.isFavourite {
                    Text("★")
                        .font(Theme.Typography.tileStar)
                        .foregroundStyle(Theme.favourite)
                        .padding(8)
                        .accessibilityLabel("Favourite")
                }
            }
            .overlay(alignment: .topLeading) {
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Theme.accent : .white)
                        .background(Circle().fill(isSelected ? .white : .black.opacity(0.25)))
                        .padding(8)
                }
            }
    }

    private var meta: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LibraryDisplay.tileTitle(clip))
                .font(Theme.Typography.tileTitle)
                .foregroundStyle(Theme.ink)
            HStack(spacing: 4) {
                Text(LibraryDisplay.tileDate(clip.timestamp) + (clip.tempoRatio == nil ? "" : " ·"))
                    .font(Theme.Typography.tileDetail)
                    .foregroundStyle(Theme.secondaryText)
                if let tempo = LibraryDisplay.tempo(clip.tempoRatio) {
                    Text(tempo)
                        .font(Theme.Typography.tileTempo)
                        .foregroundStyle(Theme.accent)
                }
            }
            if let tags = LibraryDisplay.tagLine(clip.tags) {
                Text(tags)
                    .font(Theme.Typography.tileDetail)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}

// Thumbnail, or the plain Figma fill while loading; a missing clip file gets a slashed icon.
private struct ClipThumbnail: View {
    let clip: LibraryClip
    @State private var image: UIImage?
    @State private var isMissing = false

    var body: some View {
        ZStack {
            Theme.thumbnail
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
            if isMissing {
                Image(systemName: "video.slash")  // PLACEHOLDER: missing clip file tile
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.8))
                    .accessibilityLabel("Clip file missing")
            } else {
                Circle()
                    .fill(.black.opacity(0.45))
                    .frame(width: LibraryMetrics.playSize, height: LibraryMetrics.playSize)
                    .overlay {
                        Text("▶")
                            .font(Theme.Typography.tilePlay)
                            .foregroundStyle(.white)
                    }
                    .accessibilityHidden(true)
            }
        }
        .task(id: clip.id) {
            guard let sessionID = clip.sessionID,
                let url = ClipStorage.clipURL(fileName: clip.clipFileName, sessionID: sessionID)
            else {
                isMissing = true
                return
            }
            image = await ClipThumbnails.shared.image(shotID: clip.id, clipURL: url)
            isMissing = image == nil
        }
    }
}
```

### `Reps/UI/Library/LibraryFilterBar.swift`

```swift
import SwiftUI

// Figma 04 "Filters": one capsule per filter, filled when set; each opens a menu (★ toggles).
struct LibraryFilterBar: View {
    @Binding var filter: LibraryFilter
    let clubs: [String]
    let tags: [String]
    let months: [LibraryMonth]
    let sessions: [LibrarySessionOption]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                clubMenu
                angleMenu
                monthMenu
                Button {
                    filter.favouritesOnly.toggle()
                } label: {
                    FilterChipLabel(title: "★", isSelected: filter.favouritesOnly)
                }
                .accessibilityLabel("Favourites")
                .accessibilityAddTraits(filter.favouritesOnly ? .isSelected : [])
                tagMenu
                sessionMenu
                if filter.hasChipFilters {
                    Button("Clear") {  // PLACEHOLDER: clear-filters copy
                        let search = filter.searchText
                        filter = LibraryFilter(searchText: search)
                    }
                    .font(Theme.Typography.filterChip)
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Theme.Spacing.gutter)
        }
        .scrollIndicators(.hidden)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var clubMenu: some View {
        Menu {
            Picker("Club", selection: $filter.club) {
                Text("All clubs").tag(String?.none)
                ForEach(clubs, id: \.self) { Text($0).tag(Optional($0)) }
            }
        } label: {
            // PLACEHOLDER: filter chip copy ("Club", "Angle", "Date", "Session")
            FilterChipLabel(title: filter.club ?? "Club", isSelected: filter.club != nil)
        }
    }

    private var angleMenu: some View {
        Menu {
            Picker("Angle", selection: $filter.angle) {
                Text("Any angle").tag(CameraAngle?.none)
                ForEach(AppSettings.angleChoices, id: \.self) {
                    Text(LibraryDisplay.angleOptionTitle($0)).tag(Optional($0))
                }
            }
        } label: {
            FilterChipLabel(
                title: filter.angle.map(LibraryDisplay.angleOptionTitle) ?? "Angle", isSelected: filter.angle != nil)
        }
    }

    private var monthMenu: some View {
        Menu {
            Picker("Date", selection: $filter.month) {
                Text("Any date").tag(LibraryMonth?.none)
                ForEach(months, id: \.self) { Text(LibraryDisplay.monthTitle($0)).tag(Optional($0)) }
            }
        } label: {
            FilterChipLabel(
                title: filter.month.map { LibraryDisplay.monthTitle($0) } ?? "Date", isSelected: filter.month != nil)
        }
    }

    // Several tags can be on; a clip must have all of them.
    private var tagMenu: some View {
        Menu {
            ForEach(tags, id: \.self) { tag in
                Toggle(
                    tag,
                    isOn: Binding(
                        get: { filter.tags.contains(tag) },
                        set: { isOn in
                            if isOn { filter.tags.insert(tag) } else { filter.tags.remove(tag) }
                        }))
            }
            if tags.isEmpty { Text("No tags yet") }  // PLACEHOLDER: empty tag menu copy
        } label: {
            FilterChipLabel(title: LibraryDisplay.tagChipTitle(filter.tags), isSelected: !filter.tags.isEmpty)
        }
        .menuActionDismissBehavior(.disabled)
    }

    private var sessionMenu: some View {
        Menu {
            Picker("Session", selection: $filter.sessionID) {
                Text("Any session").tag(UUID?.none)
                ForEach(sessions) { Text(LibraryDisplay.sessionTitle($0)).tag(Optional($0.id)) }
            }
        } label: {
            FilterChipLabel(
                title: sessions.first { $0.id == filter.sessionID }?.title ?? "Session",
                isSelected: filter.sessionID != nil)
        }
    }
}

private struct FilterChipLabel: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(isSelected ? Theme.Typography.filterChipSelected : Theme.Typography.filterChip)
            .foregroundStyle(isSelected ? Color.white : Theme.ink)
            .lineLimit(1)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(isSelected ? Theme.accent : Theme.card, in: .capsule)
            .contentShape(.capsule)
    }
}
```

### `Reps/UI/Library/LibraryTagSheet.swift`

```swift
import SwiftUI

// Bulk add/remove tag (§5.3b). One tap applies and closes, so one Undo covers it. No Figma frame.
struct LibraryTagSheet: View {
    let selectedCount: Int
    let onSelection: [String]
    let suggestions: [String]
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var newTag = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Add a tag", text: $newTag)  // PLACEHOLDER: tag field copy
                        .textInputAutocapitalization(.never)
                        .submitLabel(.done)
                        .onSubmit { add(newTag) }
                    ForEach(matchingSuggestions, id: \.self) { tag in
                        Button(tag) { add(tag) }
                            .foregroundStyle(Theme.ink)
                    }
                } header: {
                    Text("Add to \(LibraryDisplay.countTitle(selectedCount))")
                }
                if !onSelection.isEmpty {
                    Section("Remove") {
                        ForEach(onSelection, id: \.self) { tag in
                            Button(tag, role: .destructive) {
                                onRemove(tag)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // Autocomplete from history (§5.3b): prefix matches first, at most 8.
    private var matchingSuggestions: [String] {
        let typed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return Array(suggestions.prefix(8)) }
        return Array(suggestions.filter { $0.localizedStandardContains(typed) && $0 != typed }.prefix(8))
    }

    private func add(_ tag: String) {
        guard !tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onAdd(tag)
        dismiss()
    }
}
```

### `Reps/UI/Library/LibraryBulkBar.swift`

```swift
import SwiftUI

// Bulk actions under the grid while selecting (§5.3b). No Figma frame: PLACEHOLDER: bulk bar design.
struct LibraryBulkBar: View {
    let clubs: [String]
    let isEnabled: Bool
    let favouriteTarget: Bool
    let onClub: (String) -> Void
    let onTags: () -> Void
    let onFavourite: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Menu {
                ForEach(clubs, id: \.self) { club in
                    Button(club) { onClub(club) }
                }
            } label: {
                Label("Club", systemImage: "figure.golf")
            }
            Spacer()
            Button(action: onTags) {
                Label("Tags", systemImage: "tag")
            }
            Spacer()
            Button(action: onFavourite) {
                Label(
                    favouriteTarget ? "Favourite" : "Unfavourite", systemImage: favouriteTarget ? "star" : "star.slash")
            }
            Spacer()
            Button(action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .tint(Theme.danger)
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .tint(Theme.accent)
        .disabled(!isEnabled)
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(Theme.background)
        .overlay(alignment: .top) { Divider() }
    }
}
```

### `Reps/UI/Library/ClipDetailPlaceholderView.swift`

```swift
import SwiftUI

// TODO(#25): replace with the clip detail player (Figma 11).
struct ClipDetailPlaceholderView: View {
    let clip: LibraryClip

    var body: some View {
        ContentUnavailableView(
            LibraryDisplay.tileTitle(clip),
            systemImage: "play.rectangle",
            description: Text("The clip player comes in a later build.")  // PLACEHOLDER: clip detail copy
        )
        .navigationTitle(LibraryDisplay.tileDate(clip.timestamp))
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

### `Reps/UI/Library/LibraryView.swift`

```swift
import SwiftData
import SwiftUI

// Figma 04 Library (F15, F16, §5.3b).
struct LibraryView: View {
    // TODO(#22): pass the real ClipFileRemoving once clips exist.
    var clipFiles: any ClipFileRemoving = NoClipFiles()

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    // Q23: only this predicate runs in SQLite; tags, angle and the rest are filtered in memory.
    @Query(filter: #Predicate<ShotRecord> { $0.clipFileName != nil }, sort: \ShotRecord.timestamp, order: .reverse)
    private var shots: [ShotRecord]
    @Query(sort: [SortDescriptor(\BagClub.sortOrder), SortDescriptor(\BagClub.name)]) private var bag: [BagClub]
    @State private var filter = LibraryFilter()
    @State private var path: [UUID] = []
    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []
    @State private var pendingDelete: Set<UUID> = []
    @State private var lastUndo: LibraryUndo?
    @State private var isTagSheetShown = false
    @State private var errorMessage: String?

    var body: some View {
        let all = shots.compactMap(LibraryClip.init)
        let clips = LibraryDisplay.visible(all, filter: filter, hidden: pendingDelete)
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        NavigationStack(path: $path) {
            ScrollView {
                LibraryFilterBar(
                    filter: $filter,
                    clubs: LibraryDisplay.clubOptions(all, bag: bag.map(\.name)),
                    tags: LibraryDisplay.tagOptions(all),
                    months: LibraryDisplay.monthOptions(all),
                    sessions: LibraryDisplay.sessionOptions(all)
                )
                Text(LibraryDisplay.countTitle(clips.count))
                    .font(Theme.Typography.resultCount)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 4)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.gridGap), count: 2),
                    spacing: Theme.Spacing.gridGap
                ) {
                    ForEach(clips) { clip in
                        ClipTile(clip: clip, isSelecting: isSelecting, isSelected: selection.contains(clip.id))
                            .onTapGesture { tap(clip) }
                            .onLongPressGesture { startSelecting(with: clip.id) }
                    }
                }
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.top, 4)
                .padding(.bottom, 12)
            }
            .background(Theme.background)
            .overlay { emptyState(hasClips: !all.isEmpty, hasResults: !clips.isEmpty) }
            .navigationTitle(isSelecting ? LibraryDisplay.countTitle(selection.count) : "Library")
            .navigationBarTitleDisplayMode(isSelecting ? .inline : .large)
            .searchable(
                text: $filter.searchText, placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search clubs, tags, dates"
            )
            .toolbar { toolbar(visible: clips) }
            .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    if let lastUndo {
                        UndoToast(message: lastUndo.message) { undo(lastUndo) }
                            .padding(.horizontal, Theme.Spacing.gutter)
                    }
                    if isSelecting {
                        let selected = selection.compactMap { byID[$0] }
                        LibraryBulkBar(
                            clubs: ClubChoices.names(bag: bag.filter(\.isInBag).map(\.name), current: ""),
                            isEnabled: !selection.isEmpty,
                            favouriteTarget: LibraryDisplay.favouriteTarget(selected),
                            onClub: { club in apply("Moved") { try LibraryEdits.setClub(club, on: $0, in: context) } },
                            onTags: { isTagSheetShown = true },
                            onFavourite: {
                                let value = LibraryDisplay.favouriteTarget(selected)
                                apply(value ? "Favourited" : "Unfavourited") {
                                    try LibraryEdits.setFavourite(value, on: $0, in: context)
                                }
                            },
                            onDelete: deleteSelection
                        )
                    }
                }
            }
            .undoToastTimer($lastUndo)
            .navigationDestination(for: UUID.self) { id in
                if let clip = byID[id] { ClipDetailPlaceholderView(clip: clip) }
            }
            .sheet(isPresented: $isTagSheetShown) {
                let selected = selection.compactMap { byID[$0] }
                LibraryTagSheet(
                    selectedCount: selected.count,
                    onSelection: LibraryDisplay.tagOptions(selected),
                    suggestions: LibraryDisplay.tagOptions(all),
                    onAdd: { tag in apply("Tagged") { try LibraryEdits.addTag(tag, to: $0, in: context) } },
                    onRemove: { tag in apply("Untagged") { try LibraryEdits.removeTag(tag, from: $0, in: context) } }
                )
            }
            .alert(
                errorMessage ?? "",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            }
        }
        .tint(Theme.accent)
        // The toast expired (or was replaced): the hidden clips are deleted for real now.
        .onChange(of: lastUndo?.id) { _, new in
            if new == nil { commitPendingDelete() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { finishUndo() }
        }
        .onDisappear { finishUndo() }
    }

    @ToolbarContentBuilder
    private func toolbar(visible: [LibraryClip]) -> some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                let allSelected = !visible.isEmpty && Set(visible.map(\.id)).isSubset(of: selection)
                Button(allSelected ? "Deselect All" : "Select All") {
                    selection = allSelected ? [] : Set(visible.map(\.id))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { stopSelecting() }
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Select") { isSelecting = true }
                    .disabled(visible.isEmpty)
            }
        }
    }

    @ViewBuilder
    private func emptyState(hasClips: Bool, hasResults: Bool) -> some View {
        if !hasClips {
            ContentUnavailableView(
                "No clips yet",  // PLACEHOLDER: library empty copy
                systemImage: "film.stack",
                description: Text("Clips from Range + clips sessions show up here.")
            )
        } else if !hasResults {
            if filter.hasChipFilters {
                ContentUnavailableView {
                    Label("No matching clips", systemImage: "line.3.horizontal.decrease.circle")  // PLACEHOLDER
                } description: {
                    Text("Every filter has to match.")  // PLACEHOLDER: no-results copy
                } actions: {
                    Button("Clear filters") { filter = LibraryFilter(searchText: filter.searchText) }
                }
            } else {
                ContentUnavailableView.search(text: filter.searchText)
            }
        }
    }

    private func tap(_ clip: LibraryClip) {
        guard isSelecting else {
            path.append(clip.id)
            return
        }
        if selection.contains(clip.id) { selection.remove(clip.id) } else { selection.insert(clip.id) }
    }

    // §5.3b: long-press starts bulk mode with that clip selected.
    private func startSelecting(with id: UUID) {
        isSelecting = true
        selection.insert(id)
    }

    private func stopSelecting() {
        isSelecting = false
        selection = []
    }

    private func selectedShots() -> [ShotRecord] {
        shots.filter { selection.contains($0.id) && !pendingDelete.contains($0.id) }
    }

    // Runs one bulk edit on the selection and offers Undo; selection mode stays on for the next edit.
    private func apply(_ verb: String, _ edit: ([ShotRecord]) throws -> [ShotSnapshot]) {
        finishUndo()
        let targets = selectedShots()
        guard !targets.isEmpty else { return }
        do {
            let snapshots = try edit(targets)
            guard !snapshots.isEmpty else { return }
            withAnimation {
                lastUndo = LibraryUndo(
                    message: LibraryDisplay.undoMessage(verb, count: snapshots.count), kind: .restore(snapshots))
            }
        } catch {
            errorMessage = "Couldn't change the clips."  // PLACEHOLDER: error copy (#29)
        }
    }

    // Hidden now, deleted when the toast goes away without Undo (§5.3c). No alert: Undo is the safety net.
    private func deleteSelection() {
        finishUndo()
        let ids = Set(selectedShots().map(\.id))
        guard !ids.isEmpty else { return }
        pendingDelete = ids
        stopSelecting()
        withAnimation {
            lastUndo = LibraryUndo(message: LibraryDisplay.undoMessage("Deleted", count: ids.count), kind: .delete(ids))
        }
    }

    private func undo(_ undo: LibraryUndo) {
        switch undo.kind {
        case .delete:
            pendingDelete = []
        case .restore(let snapshots):
            do {
                try LibraryEdits.restore(snapshots, in: context)
            } catch {
                errorMessage = "Couldn't undo."  // PLACEHOLDER: error copy (#29)
            }
        }
        withAnimation { lastUndo = nil }
    }

    // Ends the undo window now: commits a pending delete and drops the toast.
    private func finishUndo() {
        commitPendingDelete()
        lastUndo = nil
    }

    private func commitPendingDelete() {
        guard !pendingDelete.isEmpty else { return }
        let ids = pendingDelete
        pendingDelete = []
        do {
            let deleted = try LibraryEdits.delete(ids: ids, in: context, clipFiles: clipFiles)
            Task { await ClipThumbnails.shared.remove(deleted) }
        } catch {
            errorMessage = "Couldn't delete the clips."  // PLACEHOLDER: error copy (#29)
        }
    }
}

#if DEBUG
    extension PreviewData {
        // Library sample: clips without files, so tiles show the missing-file placeholder.
        static func libraryContainer() -> ModelContainer {
            let made = container()
            let context = made.mainContext
            let session = PracticeSession(plan: nil, mode: .rangeCounterWithClips, cameraAngle: .faceOn)
            session.planName = "Wedge day"
            session.status = .finished
            context.insert(session)
            let block = BlockResult(clubName: "GW", tags: ["fade"], order: 0)
            context.insert(block)
            block.session = session
            for index in 0..<8 {
                let shot = ShotRecord(
                    timestamp: .now.addingTimeInterval(Double(-index) * 3_600 * 20), detectedBy: .camera,
                    clubName: index < 5 ? "GW" : "PW", tags: index.isMultiple(of: 3) ? ["fade"] : [])
                shot.tempoRatio = 2.9 + Double(index % 4) / 10
                shot.isFavourite = index == 0 || index == 3
                shot.clipFileName = "\(shot.id.uuidString).mov"
                context.insert(shot)
                shot.blockResult = block
            }
            return made
        }
    }

    #Preview {
        LibraryView()
            .modelContainer(PreviewData.libraryContainer())
    }
#endif
```

## Appendix B: tests

### `RepsTests/LibraryDisplayTests.swift`

```swift
import Foundation
import Testing

@testable import Reps

@MainActor
struct LibraryDisplayTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let locale = Locale(identifier: "en_US")
    // Wed 16 Sep 2026, 10:00 UTC
    private let now = Date(timeIntervalSince1970: 1_789_552_800)
    private let wedgeDay = UUID()
    private let ironsDay = UUID()

    private func clip(
        _ club: String = "GW", tags: [String] = [], favourite: Bool = false, hoursAgo: Double = 0,
        angle: CameraAngle = .faceOn, session: UUID? = nil, title: String? = "Wedge day", tempo: Double? = nil,
        id: UUID = UUID()
    ) -> LibraryClip {
        LibraryClip(
            id: id, timestamp: now.addingTimeInterval(-hoursAgo * 3_600), clubName: club, tags: tags,
            isFavourite: favourite, tempoRatio: tempo, clipFileName: "\(id.uuidString).mov",
            sessionID: session ?? wedgeDay, sessionTitle: title,
            sessionStartedAt: now.addingTimeInterval(-hoursAgo * 3_600),
            angle: angle)
    }

    private func visible(_ clips: [LibraryClip], _ filter: LibraryFilter, hidden: Set<UUID> = []) -> [LibraryClip] {
        LibraryDisplay.visible(clips, filter: filter, hidden: hidden, calendar: calendar, locale: locale)
    }

    @Test func emptyFilterKeepsEverythingNewestFirst() {
        let old = clip(hoursAgo: 5)
        let new = clip(hoursAgo: 1)
        let mid = clip(hoursAgo: 3)
        #expect(visible([old, new, mid], LibraryFilter()).map(\.id) == [new.id, mid.id, old.id])
    }

    @Test func sameTimestampSortsById() {
        let a = clip(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let b = clip(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        #expect(visible([b, a], LibraryFilter()).map(\.id) == [a.id, b.id])
    }

    @Test func tagsAreAnded() {
        let both = clip(tags: ["fade", "low"])
        let fadeOnly = clip(tags: ["fade"])
        let fader = clip(tags: ["fader", "low"])
        var filter = LibraryFilter()
        filter.tags = ["fade"]
        #expect(Set(visible([both, fadeOnly, fader], filter).map(\.id)) == [both.id, fadeOnly.id])
        filter.tags = ["fade", "low"]
        #expect(visible([both, fadeOnly, fader], filter).map(\.id) == [both.id])
    }

    @Test func everyChipFilterIsAnded() {
        let match = clip("GW", tags: ["fade"], favourite: true, angle: .faceOn, session: wedgeDay)
        let wrongClub = clip("PW", tags: ["fade"], favourite: true)
        let wrongAngle = clip(tags: ["fade"], favourite: true, angle: .downTheLine)
        let notFavourite = clip(tags: ["fade"])
        let otherSession = clip(tags: ["fade"], favourite: true, session: ironsDay)
        let lastMonth = clip(tags: ["fade"], favourite: true, hoursAgo: 24 * 20)
        var filter = LibraryFilter()
        filter.club = "GW"
        filter.angle = .faceOn
        filter.month = LibraryMonth(year: 2026, month: 9)
        filter.sessionID = wedgeDay
        filter.tags = ["fade"]
        filter.favouritesOnly = true
        #expect(filter.hasChipFilters)
        let all = [match, wrongClub, wrongAngle, notFavourite, otherSession, lastMonth]
        #expect(visible(all, filter).map(\.id) == [match.id])
    }

    @Test func searchWordsMustAllMatchSomeField() {
        let gw = clip("Gap wedge", tags: ["fade"], title: "Wedge day")
        let pw = clip("Pitching wedge", tags: ["draw"], title: "Irons")
        var filter = LibraryFilter()
        filter.searchText = "wedge"
        #expect(visible([gw, pw], filter).count == 2)
        filter.searchText = "WEDGE fade"
        #expect(visible([gw, pw], filter).map(\.id) == [gw.id])
        filter.searchText = "irons draw"
        #expect(visible([gw, pw], filter).map(\.id) == [pw.id])
        filter.searchText = "sept wednesday face-on"
        #expect(visible([gw, pw], filter).count == 2)
        filter.searchText = "october"
        #expect(visible([gw, pw], filter).isEmpty)
        #expect(!filter.hasChipFilters)
    }

    @Test func hiddenClipsAreLeftOut() {
        let a = clip()
        let b = clip(hoursAgo: 1)
        #expect(visible([a, b], LibraryFilter(), hidden: [a.id]).map(\.id) == [b.id])
    }

    @Test func clubOptionsFollowTheBagThenAlphabetical() {
        let clips = [clip("PW"), clip("Old wedge"), clip("7 iron"), clip("PW"), clip("A club")]
        #expect(
            LibraryDisplay.clubOptions(clips, bag: ["Driver", "7 iron", "PW"]) == [
                "7 iron", "PW", "A club", "Old wedge",
            ])
    }

    @Test func tagOptionsByUseThenName() {
        let clips = [clip(tags: ["low", "fade"]), clip(tags: ["fade"]), clip(tags: ["draw"]), clip(tags: ["low"])]
        #expect(LibraryDisplay.tagOptions(clips) == ["fade", "low", "draw"])
    }

    @Test func monthAndSessionOptionsNewestFirst() {
        let clips = [
            clip(hoursAgo: 24 * 20, session: ironsDay, title: "Irons"), clip(hoursAgo: 1), clip(hoursAgo: 2),
        ]
        #expect(
            LibraryDisplay.monthOptions(clips, calendar: calendar) == [
                LibraryMonth(year: 2026, month: 9), LibraryMonth(year: 2026, month: 8),
            ])
        let sessions = LibraryDisplay.sessionOptions(clips)
        #expect(sessions.map(\.id) == [wedgeDay, ironsDay])
        #expect(sessions.map(\.title) == ["Wedge day", "Irons"])
        #expect(LibraryDisplay.sessionTitle(sessions[1], calendar: calendar, locale: locale) == "Irons · Aug 27")
    }

    @Test func freeSessionOptionIsNamed() {
        #expect(LibraryDisplay.sessionOptions([clip(title: nil)]).map(\.title) == ["Free session"])
    }

    @Test func monthTitleShowsYearOnlyWhenNotThisYear() {
        #expect(
            LibraryDisplay.monthTitle(LibraryMonth(year: 2026, month: 9), now: now, calendar: calendar, locale: locale)
                == "September")
        #expect(
            LibraryDisplay.monthTitle(LibraryMonth(year: 2025, month: 12), now: now, calendar: calendar, locale: locale)
                == "December 2025")
    }

    @Test func tileCopy() {
        #expect(LibraryDisplay.tileTitle(clip("Gap wedge")) == "Gap wedge · face-on")
        #expect(LibraryDisplay.tileTitle(clip("Putter", angle: .none)) == "Putter")
        #expect(LibraryDisplay.tempo(3.06) == "3.1")
        #expect(LibraryDisplay.tempo(nil) == nil)
        #expect(LibraryDisplay.tagLine(["fade", "low"]) == "fade, low")
        #expect(LibraryDisplay.tagLine([]) == nil)
        #expect(LibraryDisplay.countTitle(1) == "1 clip")
        #expect(LibraryDisplay.countTitle(62) == "62 clips")
        #expect(LibraryDisplay.tagChipTitle([]) == "Tag")
        #expect(LibraryDisplay.tagChipTitle(["low", "fade"]) == "fade +1")
        #expect(LibraryDisplay.undoMessage("Deleted", count: 3) == "Deleted 3 clips")
    }

    @Test func tileDates() {
        func date(_ hoursAgo: Double) -> String {
            LibraryDisplay.tileDate(
                now.addingTimeInterval(-hoursAgo * 3_600), now: now, calendar: calendar, locale: locale)
        }
        #expect(date(2) == "Today 8:00\u{202F}AM")
        #expect(date(40) == "Mon 6:00\u{202F}PM")
        #expect(date(24 * 7) == "Sep 9")
        #expect(date(24 * 300) == "Nov 20, 2025")
    }

    @Test func favouriteTargetFlipsOnlyWhenAllAreFavourites() {
        #expect(LibraryDisplay.favouriteTarget([clip(favourite: true), clip()]))
        #expect(!LibraryDisplay.favouriteTarget([clip(favourite: true), clip(favourite: true)]))
    }
}
```

### `RepsTests/LibraryEditsTests.swift`

```swift
import Foundation
import SwiftData
import Testing

@testable import Reps

@MainActor
struct LibraryEditsTests {
    private let container: ModelContainer
    private let context: ModelContext
    private let session: PracticeSession
    private let block: BlockResult

    init() throws {
        container = try RepsStore.makeContainer(inMemory: true)
        context = container.mainContext
        session = PracticeSession(plan: nil, mode: .rangeCounterWithClips, cameraAngle: .downTheLine)
        context.insert(session)
        block = BlockResult(clubName: "GW", order: 0)
        context.insert(block)
        block.session = session
        try context.save()
    }

    private func shot(_ club: String = "GW", tags: [String] = [], clip: Bool = true) throws -> ShotRecord {
        let shot = ShotRecord(detectedBy: .camera, clubName: club, tags: tags)
        if clip { shot.clipFileName = "\(shot.id.uuidString).mov" }
        context.insert(shot)
        shot.blockResult = block
        try context.save()
        return shot
    }

    private func allShots() throws -> [ShotRecord] {
        try context.fetch(FetchDescriptor<ShotRecord>())
    }

    @Test func clipCopiesSessionFields() throws {
        let withClip = try shot(tags: ["fade"])
        let clip = try #require(LibraryClip(withClip))
        #expect(clip.sessionID == session.id)
        #expect(clip.sessionTitle == "Free session")
        #expect(clip.angle == .downTheLine)
        #expect(clip.tags == ["fade"])
        #expect(LibraryClip(try shot(clip: false)) == nil)
    }

    @Test func setClubAndUndo() throws {
        let a = try shot("GW")
        let b = try shot("PW")
        let snapshots = try LibraryEdits.setClub("  SW ", on: [a, b], in: context)
        #expect([a.clubName, b.clubName] == ["SW", "SW"])
        try LibraryEdits.restore(snapshots, in: context)
        #expect([a.clubName, b.clubName] == ["GW", "PW"])
        #expect(try LibraryEdits.setClub("  ", on: [a], in: context).isEmpty)
        #expect(a.clubName == "GW")
    }

    @Test func addAndRemoveTagWithUndo() throws {
        let a = try shot(tags: ["low"])
        let b = try shot(tags: ["fade"])
        let added = try LibraryEdits.addTag(" fade ", to: [a, b], in: context)
        #expect(a.tags == ["low", "fade"])
        #expect(b.tags == ["fade"])
        let removed = try LibraryEdits.removeTag("low", from: [a, b], in: context)
        #expect(a.tags == ["fade"])
        try LibraryEdits.restore(removed, in: context)
        #expect(a.tags == ["low", "fade"])
        try LibraryEdits.restore(added, in: context)
        #expect(a.tags == ["low"])
        #expect(b.tags == ["fade"])
        #expect(try LibraryEdits.addTag("", to: [a], in: context).isEmpty)
    }

    @Test func favouriteAndUndo() throws {
        let a = try shot()
        a.isFavourite = true
        let b = try shot()
        let snapshots = try LibraryEdits.setFavourite(true, on: [a, b], in: context)
        #expect(a.isFavourite && b.isFavourite)
        try LibraryEdits.restore(snapshots, in: context)
        #expect(a.isFavourite && !b.isFavourite)
    }

    @Test func restoreSkipsDeletedShots() throws {
        let a = try shot("GW")
        let b = try shot("GW")
        let snapshots = try LibraryEdits.setClub("PW", on: [a, b], in: context)
        try LibraryEdits.delete(ids: [a.id], in: context, clipFiles: NoClipFiles())
        try LibraryEdits.restore(snapshots, in: context)
        #expect(try allShots().map(\.clubName) == ["GW"])
    }

    @Test func deleteRemovesRowsThenFiles() throws {
        let a = try shot()
        let b = try shot()
        let keep = try shot()
        let noClip = try shot(clip: false)
        let spy = ClipSpy()
        let deleted = try LibraryEdits.delete(ids: [a.id, b.id, noClip.id, UUID()], in: context, clipFiles: spy)
        #expect(Set(deleted) == [a.id, b.id, noClip.id])
        #expect(try allShots().map(\.id) == [keep.id])
        #expect(block.shots.map(\.id) == [keep.id])
        #expect(
            Set(spy.removedClips) == [
                "\(session.id.uuidString)/\(a.id.uuidString).mov", "\(session.id.uuidString)/\(b.id.uuidString).mov",
            ])
        #expect(spy.removedSessions.isEmpty)
    }

    @Test func deleteDoesNotChangeBlockCounts() throws {
        block.repsCounted = 2
        let a = try shot()
        _ = try shot()
        try LibraryEdits.delete(ids: [a.id], in: context, clipFiles: NoClipFiles())
        #expect(block.repsCounted == 2)
    }
}
```

### `RepsTests/ClipStorageTests.swift` (append at the end)

```swift
struct ClipURLTests {
    private let root = URL(filePath: "/clips", directoryHint: .isDirectory)
    private let session = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    @Test func bareMovNameResolvesUnderTheSessionFolder() {
        let url = ClipStorage.clipURL(fileName: "abc.mov", sessionID: session, root: root)
        #expect(url?.path(percentEncoded: false) == "/clips/11111111-2222-3333-4444-555555555555/abc.mov")
        #expect(ClipStorage.clipURL(fileName: "ABC.MOV", sessionID: session, root: root) != nil)
    }

    @Test(arguments: ["", ".mov", "../x.mov", "a/b.mov", "..", "a\\b.mov", "clip.mp4", "a:b.mov", "a\nb.mov"])
    func unsafeNamesAreRejected(_ name: String) {
        #expect(ClipStorage.clipURL(fileName: name, sessionID: session, root: root) == nil)
    }
}
```
