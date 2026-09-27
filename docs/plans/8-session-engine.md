# #8 Session engine (SessionController)

Goal: a UI-free, AVFoundation-free `SessionController` that runs planned and free sessions, counts shots from any source, applies the block rules (minimums vs strict, mandatory vs free order), saves after every change so a kill loses nothing, and resumes the active session at launch. It tells the voice layer what happened through plain `SessionEvent` values.

Spec: F2, F14, F16, F18, F21, F22, §4, §5.1, §6 (kill), §10. ADRs: 0004, 0006, 0009, 0012. Owner decisions on the issue: Q21 (−1), Q24 (snapshots). Q22 (session completion cap) stays with #11, and `Completion` is not touched here.

Every file in **Appendix A** was built and tested by the planner in a scratch copy of the repo with Xcode 27.0 (27A5252f) on the iPhone 17 Pro simulator (iOS 27, `A26BAE3A-…`). The full `Unit` plan passed (75 tests in 7 suites, 41 of them new), with zero compiler warnings, and `xcrun swift-format lint --strict -r Reps RepsTests` was clean. The tests are hosted in the app, so each run also opened the simulator's **existing on-disk store** (written by the #4 build, same `Z_UUID` before and after). SwiftData migrated it in place, adding `ZISSTRICTCOUNT`, `ZISORDERMANDATORY` and `ZACTIVEBLOCKORDER`, with no error. **Copy the file contents exactly.**

Out of scope (later issues): any view, the resume prompt UI, the "Next before target?" confirmation (#9, #11); speech (#10); summary, the Keep going/Done flow and the Q22 per-block cap (#11); camera and detectors that call `recordShot` (#13, #16, #19); real clip files and their deletion (#22); library deletes (#24); error UI for `lastSaveError` (#29).

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Schema change for Q24 | **Amend `RepsSchemaV1` in place** (three new `PracticeSession` properties with defaults), update `schemaShapeIsPinned` in the same commit, and record in ADR 0013 that V1 was amended before first install. No `RepsSchemaV2`. | No store holds real data yet (Phase 1 isn't on the phone). SwiftData migrated the existing simulator store in place (verified), so a V2 would add ~150 lines of frozen V1 copies and protect nothing. |
| Snapshot fields (Q24) | `PracticeSession.isStrictCount: Bool = false`, `isOrderMandatory: Bool = false` (copied from the plan in `init`, false for free sessions), `activeBlockOrder: Int?` (the `order` of the active `BlockResult`; nil = no block left). Stored as an `Int` rather than a relationship, because `order` is unique within a session and it needs no new inverse. | Resume must work after the plan is edited or deleted. `targetReps` and `clubName` are already snapshotted on `BlockResult` (ADR 0012). |
| Free session flag | `PracticeSession.isFreeSession` is computed: `planName == nil`. | `plan` becomes nil when a plan is deleted, but `planName` is always set for a planned session (`PracticePlan.name` isn't optional). No extra column. |
| Export | `ExportSession` gains `isStrictCount` and `isOrderMandatory`. `activeBlockOrder` is not exported (it's runtime state, and finished sessions have it nil). `formatVersion` stays 1. | §10 "export without changes": a strict session's 100 % means something different. No export has ever been produced, same reasoning as the V1 amendment. |
| Shape | `@MainActor @Observable final class SessionController` in `Reps/Session/`. It owns the `ModelContext` it is given (the app passes `container.mainContext`). Its state (`session`, `activeBlock`, `activeTags`, `lastSaveError`) is `private(set)`. Everything else is computed from the models, which are observable themselves. Dependencies are `@ObservationIgnored`. | Spec §4 box. The app target defaults to MainActor (ADR 0009) and `mainContext` is `@MainActor` (Context7). |
| Injected dependencies | `init(context:clipFiles: any ClipFileRemoving = NoClipFiles(), now: @escaping () -> Date = { .now })`. | Tests use a spy and a clock that ticks 1 s per read, so shot timestamps never tie (`sortedShots` breaks ties by random UUID). |
| Input | `recordShot(source: DetectionSource) -> ShotRecord?` is the one entry point: `.manual` is the +1 button (#9), `.camera` is detectors (#16, #19). It returns the new `ShotRecord` (so #22 can attach `clipFileName`), or nil when ignored (no session, no active block, or a strict block already at target). Detectors run off-main and must hop to the MainActor to call it. | One code path for manual and camera counting. |
| Counters | Camera shot → `repsCounted += 1`. Manual +1 → `repsManualAdjust += 1`. Both create a `ShotRecord` (`detectedBy`, the block's `clubName`, current `activeTags`, `timestamp = now()`). | §5.1: `repsManualAdjust` is the "net of +1/−1 taps". This keeps `done == shots.count` in normal use. |
| −1 (Q21) | `minusOne()`: no-op when the block's `done` is 0 (never below zero). Otherwise it deletes the block's latest shot (`sortedShots.last`) if there is one, **always** decrements `repsManualAdjust`, saves, and **then** asks `ClipFileRemoving` to delete that shot's clip (the file name is read before the delete). A camera shot removed by −1 leaves `repsCounted` alone. | Owner: "deletes the latest ShotRecord … which lowers the count; with no shot, decrements repsManualAdjust". Lowering the count via `repsManualAdjust` in both cases keeps detector accuracy readable: counted 41, adjust −1 means one false detection (§5.1). The file goes only after the row delete is saved, so a failed save never orphans a row without its clip. |
| −1 target block | The active block, **except** right after a strict auto-advance (nothing else has happened since). Then −1 applies to the block that just ended and makes it active again (`countChanged` then `blockChanged`). This also works after the strict plan ended. The "just auto-advanced" marker is transient and is cleared by every other action. It isn't persisted, so it doesn't survive a kill. | Otherwise a false 10th detection in a strict drill couldn't be undone: the new block is empty, so −1 would be a no-op. |
| Minimums (F21, default) | Reaching the target emits `targetReached(isStrict: false)` once (when `done` becomes **equal** to target) and **stays on the block**. More shots keep counting past target. The user moves on with `advance()`. | F21: "a block's target is the minimum, not a cap. Keep hitting and the count goes past target". This overrides F2's "advance block automatically when target reps reached" for non-strict plans. See Q26. |
| Strict (F22) | At `done == target` it emits `targetReached(isStrict: true)`, then auto-advances to the next block (rules below), or emits `planEnded` when there's none. A strict block can never go over target: `recordShot` ignores shots while the active strict block is complete, and `select` refuses completed strict blocks. After `planEnded` all shots are ignored. | F22: "a block ends exactly at target and the voice tells you to stop". F2: "advance block automatically when target reps reached". §5.5: "block advances at target reps". |
| Next block | `advance()` (Next button, also "skip") and strict auto-advance both use `nextBlock(after:)`. **Order mandatory**: the block with the next higher `order` (even if earlier blocks were skipped), else none. **Free order**: the first *incomplete* block after the current one in order, wrapping to incomplete blocks before it, else none. "None" means `activeBlock = nil`, `activeBlockOrder = nil`, and `planEnded`. `advance()` does nothing in a free session or with no active block. | F18: mandatory "locks the sequence"; free order "lets you jump to any block … and come back later". F28's "Next block before target asks first" is UI. The controller doesn't block it, and #9 reads `Completion.isComplete(activeBlock.tally)` to decide whether to ask. |
| Jumping (F18) | `select(_:) -> Bool`: true only if the block belongs to this planned session, order isn't mandatory, it isn't already active, and (strict only) it isn't complete. In minimums mode, jumping back to a complete block and hitting more is allowed (count goes past target). `canSelectBlocks` tells #9 whether to make the strip tappable. | F18. A strict block can't be reopened past its target. |
| Last block | Minimums: the last block keeps counting past target. `advance()` from it goes to an incomplete block in free order, else `planEnded`. Strict: see above. `planEnded` never finishes the session: `status` stays `.active` until `finish()` (Done on the summary, #11). | ADR 0006: only Done sets `finished`. F28: nothing ends without Done. |
| Plan complete | `isPlanComplete`: every block with a positive target has `done ≥ target`, and there's at least one. It's computed, with no event of its own. #10 can combine it with `targetReached`. | Avoids a second end-of-plan event that would overlap with `planEnded` in strict mode. |
| Free session (F14, F16, §5.1) | `startFree(mode:cameraAngle:clubName:tags:)` creates one `BlockResult(clubName:tags:order: 0)` with no target. `setClub(_:)` and `setTags(_:)` start a **new** block (`order = max + 1`, carrying the other half of club+tags) when they change something. If the active block is still unused (no shots, `repsCounted == 0`, `repsManualAdjust == 0`) they update it in place instead. The same club, or the same tag *set* (order ignored), is a no-op. `advance`/`select` are off. `finish()` deletes unused free blocks. | §5.1: "a new one starts every time the club chip or tag set changes". In-place update avoids empty blocks from fiddling with the chip before the first shot. |
| Tags in planned sessions (F16) | `setTags` updates `activeTags` and the active block's `tags`. `activeTags` carry over to every block that becomes active (`activate` writes them onto the block), so they apply "until removed". A planned session never creates extra blocks. | F16. `BlockResult.tags` exists so resume can restore them (ADR 0012). |
| Block results at start | `start(plan:cameraAngle:)` creates one `BlockResult(block:order:)` per `plan.sortedBlocks` entry, with `order` = index 0…n−1. The first becomes active. It throws `SessionError.emptyPlan` for a plan without blocks and `.sessionInProgress` if the controller already runs a session. | The #4 plan's risk note: skipped blocks must count in session completion. |
| Per-shot persistence (§6, ADR 0006) | Every mutating method calls `context.save()` before it emits events. The snapshot (`activeBlockOrder`, `tags`) is written inside the same `activate(_:)` that changes the active block, so it's saved with it. A failed save is kept in `lastSaveError` (UI in #29) and the method carries on. | `mainContext` autosaves too (Context7: `autosaveEnabled` is true for `mainContext`), but only on events. The kill test turns autosave off to prove the explicit saves are enough. |
| Resume | `static activeSession(in:) throws -> PracticeSession?` returns the newest `.active` session (`#Predicate { $0.status == active }` with a captured local, `sortBy startedAt` reverse, `fetchLimit 1`). `resume(_:)` throws `.sessionInProgress` or `.notActive`, then restores `activeBlock` from `activeBlockOrder` and `activeTags` from that block, and emits `blockChanged` (or `planEnded` when `activeBlockOrder` is nil). The rules come from the session's snapshot, not the plan. | §6: "reopens with a resume? prompt". The prompt itself is #9/#11. |
| Output | `SessionEvent` (nonisolated, `Equatable`, `Sendable`, no model references): `countChanged(done:target:)`, `targetReached(clubName:target:isStrict:)`, `blockChanged(clubName:target:done:)`, `planEnded`. `addEventHandler(_:)` registers any number of synchronous handlers. Events go out in order after the save. Strict 10th shot: `countChanged` → `targetReached` → `blockChanged`/`planEnded`. | §5.7 needs the count after every rep and "Nine iron. Thirty reps." on a block change. F22 needs "stop". Synchronous handlers make ordering deterministic in tests. An `AsyncStream` would allow only one consumer and makes tests async. The UI observes state rather than events. |
| End | `finish()` sets `status = .finished`, `endedAt = now()`, `activeBlockOrder = nil`, drops unused free blocks, saves, and resets the controller. `discard()` deletes the session (cascade to results and shots), saves, then calls `clipFiles.removeClips(sessionID:)`. Both do nothing without a session. | #11 calls `finish()` on Done. `discard()` is for "resume? → discard" and a mistaken start (see Q25). |
| Clip deletion | `protocol ClipFileRemoving { removeClip(fileName:sessionID:); removeClips(sessionID:) }` (MainActor by default), with `NoClipFiles` as the default no-op. #22 provides the FileManager version for `Documents/clips/<sessionId>/` and goes through its fable-security review. #8 touches no files. | Keeps tests off disk and keeps file-path code out of an opus-reviewed issue. |
| Test store on disk | `RepsStore.makeContainer(url:)` opens the same schema and migration plan at a given file. The resume suite uses a temp directory per test, deleted in `deinit` (the suite is a `final class`). | Needed to simulate a kill: drop the container without `finish()`, then open a new one on the same file. |

## Final layout

```
Reps/Model/PracticeSession.swift        changed: isStrictCount, isOrderMandatory, activeBlockOrder, isFreeSession
Reps/Persistence/RepsStore.swift        changed: makeContainer(url:)
Reps/Export/ExportDocument.swift        changed: ExportSession.isStrictCount, isOrderMandatory
Reps/Export/RepsExport.swift            changed: fills the two fields
Reps/Session/SessionEvent.swift         new
Reps/Session/ClipFileRemoving.swift     new: ClipFileRemoving, NoClipFiles
Reps/Session/SessionController.swift    new: SessionError, SessionController
RepsTests/RepsStoreTests.swift          changed: pinned PracticeSession attributes
RepsTests/ExportTests.swift             changed: session keys
RepsTests/SessionTestSupport.swift      new: TestClock, ClipSpy, EventLog
RepsTests/SessionControllerTests.swift  new (27 tests)
RepsTests/FreeSessionTests.swift        new (10 tests)
RepsTests/SessionResumeTests.swift      new (4 tests)
docs/adr/0013-session-engine-rules.md   new
docs/adr/README.md, docs/code-reference.md, docs/open-questions.md, docs/roadmap.md   updated
```

`Reps/Session/` is inside the synced `Reps/` folder, so there are no `project.pbxproj` edits. `RepsApp`/`RootView` are unchanged. Wiring the controller into the app is #9.

## Types and signatures

```swift
// Reps/Session/SessionEvent.swift
nonisolated enum SessionEvent: Equatable, Sendable {
    case countChanged(done: Int, target: Int?)
    case targetReached(clubName: String, target: Int, isStrict: Bool)
    case blockChanged(clubName: String, target: Int?, done: Int)
    case planEnded
}

// Reps/Session/ClipFileRemoving.swift (MainActor by default)
protocol ClipFileRemoving { func removeClip(fileName: String, sessionID: UUID); func removeClips(sessionID: UUID) }
struct NoClipFiles: ClipFileRemoving

// Reps/Session/SessionController.swift
enum SessionError: Error, Equatable { case sessionInProgress, emptyPlan, notActive }
@MainActor @Observable final class SessionController {
    init(context: ModelContext, clipFiles: any ClipFileRemoving = NoClipFiles(), now: @escaping () -> Date = { .now })
    private(set) var session: PracticeSession?
    private(set) var activeBlock: BlockResult?
    private(set) var activeTags: [String]
    private(set) var lastSaveError: (any Error)?
    var blocks: [BlockResult]            // session.sortedBlockResults
    var isFreeSession, isStrictCount, isOrderMandatory, canSelectBlocks, isPlanComplete: Bool
    func addEventHandler(_ handler: @escaping (SessionEvent) -> Void)
    func start(plan: PracticePlan, cameraAngle: CameraAngle) throws
    func startFree(mode: PracticeMode, cameraAngle: CameraAngle, clubName: String, tags: [String] = []) throws
    static func activeSession(in context: ModelContext) throws -> PracticeSession?
    func resume(_ saved: PracticeSession) throws
    @discardableResult func recordShot(source: DetectionSource) -> ShotRecord?
    func minusOne()
    func advance()
    @discardableResult func select(_ block: BlockResult) -> Bool
    func setClub(_ clubName: String)
    func setTags(_ tags: [String])
    func finish()
    func discard()
}

// Reps/Model/PracticeSession.swift (added)
var isStrictCount: Bool = false; var isOrderMandatory: Bool = false; var activeBlockOrder: Int?
var isFreeSession: Bool { planName == nil }

// Reps/Persistence/RepsStore.swift (added)
static func makeContainer(url: URL) throws -> ModelContainer
```

## Steps

Branch `feat/8-session-engine` (already checked out). Run everything from the repo root. `DEST='platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'`. TDD: in each step, write the tests first, run the filtered suites and see them fail (a compile failure counts), then add the production code and see them pass. Before each commit, `xcrun swift-format lint --strict -r Reps RepsTests` must print nothing.

### Step 1: session rule snapshots (schema V1 amended)

1. Apply the `RepsTests/RepsStoreTests.swift` and `RepsTests/ExportTests.swift` changes (Appendix A, diffs). Run
   `xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan Unit -destination "$DEST" -only-testing:RepsTests/RepsStoreTests -only-testing:RepsTests/ExportTests` → `schemaShapeIsPinned` and `onlyFinishedSessionsAreExported` fail.
2. Apply the `PracticeSession.swift`, `ExportDocument.swift`, `RepsExport.swift` and `RepsStore.swift` changes. Same command → both suites pass.
3. `git add -A && git commit -m "added session rule snapshots" -m "Refs #8"`

### Step 2: session engine

1. Create `RepsTests/SessionTestSupport.swift`, `RepsTests/SessionControllerTests.swift`, `RepsTests/FreeSessionTests.swift` and `RepsTests/SessionResumeTests.swift`. Run
   `xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan Unit -destination "$DEST" -only-testing:RepsTests/SessionControllerTests -only-testing:RepsTests/FreeSessionTests -only-testing:RepsTests/SessionResumeTests` → fails to compile.
2. Create `Reps/Session/SessionEvent.swift`, `Reps/Session/ClipFileRemoving.swift` and `Reps/Session/SessionController.swift`. Same command → 41 tests pass.
3. Full Unit plan: `xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan Unit -destination "$DEST"` → `Test run with 75 tests in 7 suites passed`, `** TEST SUCCEEDED **`. `… 2>&1 | grep 'warning:' | grep -v appintents` prints nothing.
4. `git add -A && git commit -m "added session controller" -m "Refs #8"`

### Step 3: docs

1. `docs/adr/0013-session-engine-rules.md` (Appendix B), plus a row in `docs/adr/README.md`:
   `| [0013](0013-session-engine-rules.md) | Session engine rules, −1, snapshots; V1 amended before first install | Accepted |`
2. `docs/code-reference.md`: apply Appendix C. Replace the `PracticeSession.swift`, `RepsStore.swift` and `ExportDocument.swift` entries. Add the three `Reps/Session/*` entries after `Reps/Export/RepsExport.swift`, and the new test entries after `RepsTests/ExportTests.swift`.
3. `docs/open-questions.md`: in Resolved, set "Recorded in" for Q21 and Q24 to `ADR 0013`. Add Q25 and Q26 (Appendix D) to the Open table.
4. `docs/roadmap.md`: #8 status ☐ → ☑.
5. `git add -A && git commit -m "documented session engine" -m "Refs #8"`

Then review (`review:opus`), fix findings, push, and open a PR titled `added session engine` with a one-line body plus `Closes #8`.

## Tests

All in the `Unit` plan (`RepsTests`, Swift Testing, `@MainActor` suites). No UI, no DetectorEval. The suites hold the `ModelContainer` in a stored property (see the #4 gotcha). Most tests also assert `!context.hasChanges` after an operation, which proves the controller saved.

- `SessionControllerTests` (in-memory, plan with targets `[3, 2, 2]` for 8 iron / 9 iron / PW unless stated):
  - start: `startCreatesOneResultPerPlanBlock` (3 results, snapshots, `activeBlockOrder` 0, one `blockChanged`), `startRejectsEmptyPlan`, `startWhileRunningThrows` (both start calls).
  - counting: `cameraShotCountsAsDetection`, `manualShotCountsAsAdjustment`.
  - minimums: `minimumsKeepCountingPastTarget` (exact event list, `targetReached` once, 4/3).
  - strict: `strictAdvancesExactlyAtTarget` (event order), `strictLastBlockEndsPlanAndIgnoresShots`, `strictFreeOrderAdvancesToNextIncompleteBlock` (wraps from PW to 8 iron), `strictMandatoryOrderRunsInSequence` (skip, then `planEnded` with completion 4/7).
  - navigation: `advanceBeforeTargetSkipsTheBlock` (completion 1/7), `advancePastLastBlockEndsPlan`, `freeOrderJumpsAndComesBack`, `mandatoryOrderRefusesJumps`, `strictRefusesJumpToFinishedBlock`, `minimumsFreeOrderAdvanceFindsIncompleteBlocks` (then jump back past target).
  - Q24: `planEditsDoNotChangeRunningSession`.
  - −1: `minusOneDeletesLatestShot` (manual then camera; `repsCounted` kept), `minusOneWithoutShotsLowersAdjustment`, `minusOneNeverGoesBelowZero`, `minusOneRemovesClipFile` (spy, once only), `minusOneAfterStrictAdvanceReopensBlock`, `minusOneAfterStrictPlanEndReopensLastBlock`, `minusOneAfterNextShotStaysOnActiveBlock`.
  - tags: `tagsApplyToShotsAndCarryAcrossBlocks`.
  - end: `finishMarksSessionFinished` (skipped blocks kept, not found by `activeSession`), `discardDeletesSessionAndClips` (plan kept, spy called).
- `FreeSessionTests` (in-memory, starts free with "7 iron" + `["fade"]`): `startsWithOneUntargetedBlock`, `countsWithoutTargetOrAdvance`, `clubChangeStartsNewBlock`, `clubChangeOnUnusedBlockRenamesIt`, `sameClubChangesNothing`, `tagChangeStartsNewBlock` (set order ignored), `tagChangeOnUnusedBlockUpdatesIt`, `blockNavigationIsOff`, `minusOneWorksWithoutTarget`, `finishDropsUnusedBlocks` (checked through a fresh `ModelContext`).
- `SessionResumeTests` (`final class`, temp dir per test):
  - `resumesPlannedSessionAfterKill`: on-disk store, autosave **off**, strict + mandatory plan, tag set, 3 shots (auto-advance happens), container dropped. A new container on the same file edits then deletes the plan. `activeSession` finds it, and resume restores block 1, tags, `done [2, 1]`, targets and snapshot rules, emits one `blockChanged`, refuses `select` (mandatory), and 2 more shots end the plan.
  - `resumesFreeSessionChipAndTags`: same kill pattern with club and tag changes.
  - `activeSessionIsNewestActiveOnly`: nil when none, newest active wins over older active and finished, `resume(finished)` throws `.notActive`.
  - `resumeAfterStrictPlanEndedHasNoActiveBlock`: emits `planEnded`, ignores shots.
- `RepsStoreTests.schemaShapeIsPinned`: `PracticeSession` gains the three attributes. `ExportTests.onlyFinishedSessionsAreExported`: new keys and values.

## Verification

```sh
DEST='platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'
xcrun swift-format lint --strict -r Reps RepsTests
xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan Unit -destination "$DEST"
# while iterating:
xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan Unit -destination "$DEST" -only-testing:RepsTests/SessionControllerTests
```

The migration check comes free with the full run: the hosted app opens the simulator's existing store at launch. If the app crashes at launch with "Failed to open the SwiftData store", stop and report it. Don't delete the store to make it pass. If a run prints `Restarting after unexpected exit, crash` and then hangs, a suite dropped its `ModelContainer`: kill `xcodebuild`, fix, and rerun.

## Risks and unresolved

- **Q26, minimums vs F2.** This plan does not auto-advance non-strict blocks (F21 wins over F2). If the owner wants F2 literally, minimums would auto-advance at target and "past target" would only happen by jumping back. That's a small change in `recordShot` plus tests. Added to open questions.
- **Q25, "resume?" declined.** The engine offers both `finish()` (keep what was hit) and `discard()` (delete it and its clips). Which one "No" means is a #9/#11 UI decision. Added to open questions.
- **V1 amended, not versioned.** Safe only because no real store exists. The first change after Phase 1 is installed on the phone **must** be a proper `RepsSchemaV2` + stage (ADR 0012 procedure). ADR 0013 records this, and the pin test's failure message already says it.
- **Shot timestamp is emission time.** `recordShot` stamps `now()`, not the detector's impact time. #22 needs the impact time for the clip window and should take it from the detector's `ShotEvent`, not from `ShotRecord.timestamp`.
- **Off-main detectors.** `SessionController` is MainActor. #16/#19 must hop to the main actor for each shot (a few per minute, cheap). They must not touch `ShotRecord`s off-main (ADR 0012).
- **The −1 undo after strict auto-advance** isn't persisted: after a kill and resume, −1 on the empty next block is a no-op. Acceptable for an edge case, and noted in ADR 0013.
- **Save failures** only land in `lastSaveError`. Counting continues in memory, so a kill after a failed save loses those shots. #29 decides the UI.
- **Two active sessions.** `start` only guards the controller's own session, not the store. #9 must call `activeSession(in:)` and resolve the resume prompt before it offers Start. If two ever exist, `activeSession` returns the newest one and the other stays `.active`, hidden from the log.
- **Clip files** are never deleted until #22 supplies a real `ClipFileRemoving`. Until then no clips exist.

## Appendix A: files (verified; copy exactly)

### `Reps/Model/PracticeSession.swift` (full file)

```swift
import Foundation
import SwiftData

@Model
final class PracticeSession {
    var id: UUID = UUID()
    var plan: PracticePlan?
    // Snapshot so the log still names the plan after it's deleted.
    var planName: String?
    var mode: PracticeMode = PracticeMode.rangeCounter
    var status: SessionStatus = SessionStatus.active
    var startedAt: Date = Date()
    var endedAt: Date?
    var cameraAngle: CameraAngle = CameraAngle.none
    // Plan rules copied at start so resume survives plan edits or deletion (Q24).
    var isStrictCount: Bool = false
    var isOrderMandatory: Bool = false
    // `order` of the block being counted; nil when no block is left to run.
    var activeBlockOrder: Int?
    @Relationship(deleteRule: .cascade, inverse: \BlockResult.session)
    var blockResults: [BlockResult] = []

    init(plan: PracticePlan?, mode: PracticeMode, cameraAngle: CameraAngle, startedAt: Date = .now) {
        self.plan = plan
        self.planName = plan?.name
        self.isStrictCount = plan?.isStrictCount ?? false
        self.isOrderMandatory = plan?.isOrderMandatory ?? false
        self.mode = mode
        self.cameraAngle = cameraAngle
        self.startedAt = startedAt
    }

    // A planned session always has a planName, even after its plan is deleted.
    var isFreeSession: Bool { planName == nil }

    var sortedBlockResults: [BlockResult] {
        blockResults.sorted { ($0.order, $0.id.uuidString) < ($1.order, $1.id.uuidString) }
    }

    var completion: Double? {
        Completion.session(blockResults.map(\.tally))
    }
}
```

### `Reps/Persistence/RepsStore.swift` (full file)

```swift
import Foundation
import SwiftData

enum RepsStore {
    static let models: [any PersistentModel.Type] = RepsSchemaCurrent.models

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: RepsSchemaCurrent.self)
        return try open(schema, ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory))
    }

    // A store at a given file; tests reopen it to simulate a relaunch after a kill.
    static func makeContainer(url: URL) throws -> ModelContainer {
        let schema = Schema(versionedSchema: RepsSchemaCurrent.self)
        return try open(schema, ModelConfiguration(schema: schema, url: url))
    }

    private static func open(_ schema: Schema, _ configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: schema, migrationPlan: RepsMigrationPlan.self, configurations: [configuration])
    }
}
```

### `Reps/Export/ExportDocument.swift` (diff)

```diff
--- a/Reps/Export/ExportDocument.swift
+++ b/Reps/Export/ExportDocument.swift
@@ -45,6 +45,8 @@
     var startedAt: Date
     var endedAt: Date?
     var cameraAngle: CameraAngle
+    var isStrictCount: Bool
+    var isOrderMandatory: Bool
     var blocks: [ExportBlockResult]
 }
 
```

### `Reps/Export/RepsExport.swift` (diff)

```diff
--- a/Reps/Export/RepsExport.swift
+++ b/Reps/Export/RepsExport.swift
@@ -59,6 +59,8 @@
             startedAt: session.startedAt,
             endedAt: session.endedAt,
             cameraAngle: session.cameraAngle,
+            isStrictCount: session.isStrictCount,
+            isOrderMandatory: session.isOrderMandatory,
             blocks: session.sortedBlockResults.map(blockResult)
         )
     }
```

### `RepsTests/RepsStoreTests.swift` (diff)

```diff
--- a/RepsTests/RepsStoreTests.swift
+++ b/RepsTests/RepsStoreTests.swift
@@ -26,7 +26,10 @@
             "BagClub": ["id", "name", "sortOrder", "isInBag"],
             "PracticePlan": ["id", "name", "mode", "isOrderMandatory", "isStrictCount", "createdAt"],
             "PlanBlock": ["id", "clubName", "targetReps", "note", "order"],
-            "PracticeSession": ["id", "planName", "mode", "status", "startedAt", "endedAt", "cameraAngle"],
+            "PracticeSession": [
+                "id", "planName", "mode", "status", "startedAt", "endedAt", "cameraAngle", "isStrictCount",
+                "isOrderMandatory", "activeBlockOrder",
+            ],
             "BlockResult": [
                 "id", "order", "clubName", "targetReps", "tags", "repsCounted", "repsManualAdjust",
             ],
```

### `RepsTests/ExportTests.swift` (diff)

```diff
--- a/RepsTests/ExportTests.swift
+++ b/RepsTests/ExportTests.swift
@@ -93,9 +93,12 @@
         #expect(session["cameraAngle"] as? String == "downTheLine")
         #expect(session["planName"] as? String == "Wedge day")
         #expect(session["endedAt"] as? String == "2026-09-21T15:13:20.250Z")
+        #expect(session["isStrictCount"] as? Bool == true)
+        #expect(session["isOrderMandatory"] as? Bool == false)
         #expect(
             Set(session.keys) == [
-                "id", "planId", "planName", "mode", "status", "startedAt", "endedAt", "cameraAngle", "blocks",
+                "id", "planId", "planName", "mode", "status", "startedAt", "endedAt", "cameraAngle", "isStrictCount",
+                "isOrderMandatory", "blocks",
             ])
     }
 
```

### `Reps/Session/SessionEvent.swift`

```swift
// What the session engine tells the voice layer (#10); plain values, no models.
nonisolated enum SessionEvent: Equatable, Sendable {
    // After every counted shot and every effective −1; `done` is that block's count.
    case countChanged(done: Int, target: Int?)
    // The count just reached the target. In a strict session the block ends here.
    case targetReached(clubName: String, target: Int, isStrict: Bool)
    // A block became the one being counted.
    case blockChanged(clubName: String, target: Int?, done: Int)
    // No block is left to run; shots are ignored until one is selected or the session ends.
    case planEnded
}
```

### `Reps/Session/ClipFileRemoving.swift`

```swift
import Foundation

// Deletes clip files in Documents/clips/<sessionId>/ (ADR 0006). #22 supplies the real one.
protocol ClipFileRemoving {
    func removeClip(fileName: String, sessionID: UUID)
    func removeClips(sessionID: UUID)
}

// Until #22 no clip files exist, so there is nothing to delete.
struct NoClipFiles: ClipFileRemoving {
    func removeClip(fileName: String, sessionID: UUID) {}
    func removeClips(sessionID: UUID) {}
}
```

### `Reps/Session/SessionController.swift`

```swift
import Foundation
import Observation
import SwiftData

enum SessionError: Error, Equatable {
    case sessionInProgress
    case emptyPlan
    case notActive
}

@MainActor
@Observable
final class SessionController {
    private(set) var session: PracticeSession?
    private(set) var activeBlock: BlockResult?
    private(set) var activeTags: [String] = []
    private(set) var lastSaveError: (any Error)?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let clipFiles: any ClipFileRemoving
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var handlers: [(SessionEvent) -> Void] = []
    // Set by a strict auto-advance so an immediate −1 undoes into the block that just ended.
    @ObservationIgnored private var autoAdvancedFrom: BlockResult?

    init(context: ModelContext, clipFiles: any ClipFileRemoving = NoClipFiles(), now: @escaping () -> Date = { .now }) {
        self.context = context
        self.clipFiles = clipFiles
        self.now = now
    }

    var blocks: [BlockResult] { session?.sortedBlockResults ?? [] }
    var isFreeSession: Bool { session?.isFreeSession ?? false }
    var isStrictCount: Bool { session?.isStrictCount ?? false }
    var isOrderMandatory: Bool { session?.isOrderMandatory ?? false }
    var canSelectBlocks: Bool { session != nil && !isFreeSession && !isOrderMandatory }

    var isPlanComplete: Bool {
        let targeted = blocks.filter { ($0.targetReps ?? 0) > 0 }
        return !targeted.isEmpty && targeted.allSatisfy { Completion.isComplete($0.tally) }
    }

    func addEventHandler(_ handler: @escaping (SessionEvent) -> Void) {
        handlers.append(handler)
    }

    func start(plan: PracticePlan, cameraAngle: CameraAngle) throws {
        guard session == nil else { throw SessionError.sessionInProgress }
        let planBlocks = plan.sortedBlocks
        guard !planBlocks.isEmpty else { throw SessionError.emptyPlan }
        let newSession = PracticeSession(plan: plan, mode: plan.mode, cameraAngle: cameraAngle, startedAt: now())
        context.insert(newSession)
        // One result per plan block up front, so skipped blocks count against completion.
        newSession.blockResults = planBlocks.enumerated().map { BlockResult(block: $1, order: $0) }
        session = newSession
        activeTags = []
        activate(newSession.sortedBlockResults.first)
    }

    func startFree(mode: PracticeMode, cameraAngle: CameraAngle, clubName: String, tags: [String] = []) throws {
        guard session == nil else { throw SessionError.sessionInProgress }
        let newSession = PracticeSession(plan: nil, mode: mode, cameraAngle: cameraAngle, startedAt: now())
        context.insert(newSession)
        let block = BlockResult(clubName: clubName, tags: tags, order: 0)
        newSession.blockResults = [block]
        session = newSession
        activeTags = tags
        activate(block)
    }

    // The session to offer in the "resume?" prompt at launch: the newest active one.
    static func activeSession(in context: ModelContext) throws -> PracticeSession? {
        let active = SessionStatus.active
        var descriptor = FetchDescriptor<PracticeSession>(
            predicate: #Predicate { $0.status == active },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func resume(_ saved: PracticeSession) throws {
        guard session == nil else { throw SessionError.sessionInProgress }
        guard saved.status == .active else { throw SessionError.notActive }
        session = saved
        let block = saved.activeBlockOrder.flatMap { order in saved.blockResults.first { $0.order == order } }
        activeTags = block?.tags ?? []
        activate(block)
    }

    @discardableResult
    func recordShot(source: DetectionSource) -> ShotRecord? {
        guard let session, let block = activeBlock else { return nil }
        if session.isStrictCount && Completion.isComplete(block.tally) { return nil }
        autoAdvancedFrom = nil
        let shot = ShotRecord(timestamp: now(), detectedBy: source, clubName: block.clubName, tags: activeTags)
        context.insert(shot)
        block.shots.append(shot)
        switch source {
        case .camera: block.repsCounted += 1
        case .manual: block.repsManualAdjust += 1
        }
        save()
        let done = block.tally.done
        emit(.countChanged(done: done, target: block.targetReps))
        guard let target = block.targetReps, target > 0, done == target else { return shot }
        emit(.targetReached(clubName: block.clubName, target: target, isStrict: session.isStrictCount))
        if session.isStrictCount {
            let next = nextBlock(after: block)
            autoAdvancedFrom = block
            activate(next)
        }
        return shot
    }

    // Q21: removes the latest shot and its clip when there is one; −1 is always a manual correction.
    func minusOne() {
        guard let session, let block = autoAdvancedFrom ?? activeBlock else { return }
        autoAdvancedFrom = nil
        guard block.tally.done > 0 else { return }
        let latest = block.sortedShots.last
        let clipFileName = latest?.clipFileName
        if let latest {
            block.shots.removeAll { $0 === latest }
            context.delete(latest)
        }
        block.repsManualAdjust -= 1
        save()
        if let clipFileName {
            clipFiles.removeClip(fileName: clipFileName, sessionID: session.id)
        }
        emit(.countChanged(done: block.tally.done, target: block.targetReps))
        if block !== activeBlock {
            activate(block)
        }
    }

    // Next block; before target this is a skip (the UI confirms first, F28).
    func advance() {
        guard let session, !session.isFreeSession, let block = activeBlock else { return }
        autoAdvancedFrom = nil
        activate(nextBlock(after: block))
    }

    // Block strip jump; refused in free sessions, when order is mandatory, or onto a finished strict block.
    @discardableResult
    func select(_ block: BlockResult) -> Bool {
        guard let session, !session.isFreeSession, !session.isOrderMandatory,
            block.session === session, block !== activeBlock
        else { return false }
        if session.isStrictCount && Completion.isComplete(block.tally) { return false }
        autoAdvancedFrom = nil
        activate(block)
        return true
    }

    // Free session club chip: a new block starts unless the current one is still unused.
    func setClub(_ clubName: String) {
        guard let session, session.isFreeSession, let block = activeBlock, clubName != block.clubName else { return }
        autoAdvancedFrom = nil
        if isUnused(block) {
            block.clubName = clubName
            activate(block)
        } else {
            startFreeBlock(clubName: clubName)
        }
    }

    // Tags apply to every following shot until changed (F16) and carry across blocks.
    func setTags(_ tags: [String]) {
        guard let session, Set(tags) != Set(activeTags) else { return }
        autoAdvancedFrom = nil
        activeTags = tags
        guard let block = activeBlock else { return }
        if session.isFreeSession && !isUnused(block) {
            startFreeBlock(clubName: block.clubName)
        } else {
            block.tags = tags
            save()
        }
    }

    // Done on the summary (#11); planned sessions keep skipped blocks, free sessions drop unused ones.
    func finish() {
        guard let session else { return }
        if session.isFreeSession {
            for block in session.blockResults where isUnused(block) {
                session.blockResults.removeAll { $0 === block }
                context.delete(block)
            }
        }
        session.status = .finished
        session.endedAt = now()
        session.activeBlockOrder = nil
        save()
        reset()
    }

    func discard() {
        guard let session else { return }
        let sessionID = session.id
        context.delete(session)
        save()
        clipFiles.removeClips(sessionID: sessionID)
        reset()
    }

    private func nextBlock(after current: BlockResult) -> BlockResult? {
        let all = blocks
        let later = all.filter { $0.order > current.order }
        if isOrderMandatory { return later.first }
        let earlier = all.filter { $0.order < current.order }
        return (later + earlier).first { !Completion.isComplete($0.tally) }
    }

    private func activate(_ block: BlockResult?) {
        activeBlock = block
        session?.activeBlockOrder = block?.order
        block?.tags = activeTags
        save()
        if let block {
            emit(.blockChanged(clubName: block.clubName, target: block.targetReps, done: block.tally.done))
        } else {
            emit(.planEnded)
        }
    }

    private func startFreeBlock(clubName: String) {
        guard let session else { return }
        let order = (session.blockResults.map(\.order).max() ?? -1) + 1
        let block = BlockResult(clubName: clubName, tags: activeTags, order: order)
        session.blockResults.append(block)
        activate(block)
    }

    private func isUnused(_ block: BlockResult) -> Bool {
        block.shots.isEmpty && block.repsCounted == 0 && block.repsManualAdjust == 0
    }

    private func save() {
        do {
            try context.save()
            lastSaveError = nil
        } catch {
            lastSaveError = error
        }
    }

    private func emit(_ event: SessionEvent) {
        for handler in handlers { handler(event) }
    }

    private func reset() {
        session = nil
        activeBlock = nil
        activeTags = []
        autoAdvancedFrom = nil
    }
}
```

### `RepsTests/SessionTestSupport.swift`

```swift
import Foundation

@testable import Reps

// Each read is one second later, so shots never tie on timestamp.
@MainActor
final class TestClock {
    private(set) var date = Date(timeIntervalSince1970: 1_790_000_000)

    func next() -> Date {
        date = date.addingTimeInterval(1)
        return date
    }
}

@MainActor
final class ClipSpy: ClipFileRemoving {
    private(set) var removedClips: [String] = []
    private(set) var removedSessions: [UUID] = []

    func removeClip(fileName: String, sessionID: UUID) {
        removedClips.append("\(sessionID.uuidString)/\(fileName)")
    }

    func removeClips(sessionID: UUID) {
        removedSessions.append(sessionID)
    }
}

@MainActor
final class EventLog {
    var events: [SessionEvent] = []
}
```

### `RepsTests/SessionControllerTests.swift`

```swift
import Foundation
import SwiftData
import Testing

@testable import Reps

@MainActor
struct SessionControllerTests {
    // Keep the container alive; a context alone doesn't retain it.
    let container: ModelContainer
    let context: ModelContext
    let clock: TestClock
    let clips: ClipSpy
    let log: EventLog
    let controller: SessionController

    init() throws {
        let clock = TestClock()
        let clips = ClipSpy()
        let log = EventLog()
        container = try RepsStore.makeContainer(inMemory: true)
        context = container.mainContext
        controller = SessionController(context: context, clipFiles: clips, now: { clock.next() })
        controller.addEventHandler { log.events.append($0) }
        self.clock = clock
        self.clips = clips
        self.log = log
    }

    private func makePlan(strict: Bool = false, ordered: Bool = false, targets: [Int] = [3, 2, 2]) -> PracticePlan {
        let plan = PracticePlan(
            name: "Wedge day", mode: .rangeCounter, isOrderMandatory: ordered, isStrictCount: strict)
        context.insert(plan)
        let clubs = ["8 iron", "9 iron", "PW"]
        plan.blocks = targets.enumerated().map { PlanBlock(clubName: clubs[$0], targetReps: $1, order: $0) }
        return plan
    }

    private func start(strict: Bool = false, ordered: Bool = false, targets: [Int] = [3, 2, 2]) throws {
        try controller.start(plan: makePlan(strict: strict, ordered: ordered, targets: targets), cameraAngle: .faceOn)
        log.events = []
    }

    private func hit(_ count: Int, _ source: DetectionSource = .camera) {
        for _ in 0..<count { controller.recordShot(source: source) }
    }

    private var activeClub: String? { controller.activeBlock?.clubName }
    private var done: [Int] { controller.blocks.map(\.tally.done) }

    @Test func startCreatesOneResultPerPlanBlock() throws {
        let plan = makePlan(strict: true, ordered: true)
        try controller.start(plan: plan, cameraAngle: .downTheLine)

        let session = try #require(controller.session)
        #expect(session.status == .active)
        #expect(session.plan === plan)
        #expect(session.isStrictCount && session.isOrderMandatory)
        #expect(session.cameraAngle == .downTheLine)
        #expect(controller.blocks.map(\.clubName) == ["8 iron", "9 iron", "PW"])
        #expect(controller.blocks.map(\.targetReps) == [3, 2, 2])
        #expect(controller.blocks.map(\.order) == [0, 1, 2])
        #expect(done == [0, 0, 0])
        #expect(activeClub == "8 iron")
        #expect(session.activeBlockOrder == 0)
        #expect(log.events == [.blockChanged(clubName: "8 iron", target: 3, done: 0)])
        #expect(!context.hasChanges)
        #expect(try context.fetchCount(FetchDescriptor<BlockResult>()) == 3)
    }

    @Test func startRejectsEmptyPlan() throws {
        let plan = makePlan(targets: [])
        #expect(throws: SessionError.emptyPlan) { try controller.start(plan: plan, cameraAngle: .faceOn) }
        #expect(controller.session == nil)
        #expect(try context.fetchCount(FetchDescriptor<PracticeSession>()) == 0)
    }

    @Test func startWhileRunningThrows() throws {
        try start()
        #expect(throws: SessionError.sessionInProgress) {
            try controller.start(plan: makePlan(), cameraAngle: .faceOn)
        }
        #expect(throws: SessionError.sessionInProgress) {
            try controller.startFree(mode: .rangeCounter, cameraAngle: .faceOn, clubName: "7 iron")
        }
        #expect(try context.fetchCount(FetchDescriptor<PracticeSession>()) == 1)
    }

    @Test func cameraShotCountsAsDetection() throws {
        try start()
        let shot = try #require(controller.recordShot(source: .camera))
        let block = try #require(controller.activeBlock)
        #expect(block.repsCounted == 1)
        #expect(block.repsManualAdjust == 0)
        #expect(block.shots.map(\.id) == [shot.id])
        #expect(shot.detectedBy == .camera)
        #expect(shot.clubName == "8 iron")
        #expect(shot.timestamp == clock.date)
        #expect(log.events == [.countChanged(done: 1, target: 3)])
        #expect(!context.hasChanges)
    }

    @Test func manualShotCountsAsAdjustment() throws {
        try start()
        let shot = try #require(controller.recordShot(source: .manual))
        let block = try #require(controller.activeBlock)
        #expect(block.repsCounted == 0)
        #expect(block.repsManualAdjust == 1)
        #expect(shot.detectedBy == .manual)
        #expect(try context.fetchCount(FetchDescriptor<ShotRecord>()) == 1)
    }

    @Test func minimumsKeepCountingPastTarget() throws {
        try start()
        hit(4)
        #expect(activeClub == "8 iron")
        #expect(done == [4, 0, 0])
        #expect(Completion.block(controller.blocks[0].tally) == 4.0 / 3.0)
        #expect(
            log.events == [
                .countChanged(done: 1, target: 3), .countChanged(done: 2, target: 3), .countChanged(done: 3, target: 3),
                .targetReached(clubName: "8 iron", target: 3, isStrict: false), .countChanged(done: 4, target: 3),
            ])
    }

    @Test func strictAdvancesExactlyAtTarget() throws {
        try start(strict: true)
        hit(3)
        #expect(activeClub == "9 iron")
        #expect(controller.session?.activeBlockOrder == 1)
        #expect(
            log.events.suffix(3) == [
                .countChanged(done: 3, target: 3),
                .targetReached(clubName: "8 iron", target: 3, isStrict: true),
                .blockChanged(clubName: "9 iron", target: 2, done: 0),
            ])
        hit(1)
        #expect(done == [3, 1, 0])
    }

    @Test func strictLastBlockEndsPlanAndIgnoresShots() throws {
        try start(strict: true, targets: [1, 1])
        hit(2)
        #expect(controller.activeBlock == nil)
        #expect(controller.session?.activeBlockOrder == nil)
        #expect(log.events.last == .planEnded)
        #expect(controller.isPlanComplete)
        #expect(controller.recordShot(source: .camera) == nil)
        #expect(controller.recordShot(source: .manual) == nil)
        #expect(done == [1, 1])
        #expect(try context.fetchCount(FetchDescriptor<ShotRecord>()) == 2)
    }

    @Test func strictFreeOrderAdvancesToNextIncompleteBlock() throws {
        try start(strict: true, targets: [1, 1, 1])
        #expect(controller.select(controller.blocks[2]))
        hit(1)
        #expect(activeClub == "8 iron")
        hit(1)
        #expect(activeClub == "9 iron")
        hit(1)
        #expect(controller.activeBlock == nil)
        #expect(log.events.last == .planEnded)
    }

    @Test func strictMandatoryOrderRunsInSequence() throws {
        try start(strict: true, ordered: true)
        controller.advance()
        #expect(activeClub == "9 iron")
        hit(2)
        #expect(activeClub == "PW")
        hit(2)
        #expect(controller.activeBlock == nil)
        #expect(log.events.last == .planEnded)
        #expect(!controller.isPlanComplete)
        #expect(controller.session?.completion == 4.0 / 7.0)
    }

    @Test func advanceBeforeTargetSkipsTheBlock() throws {
        try start()
        hit(1)
        controller.advance()
        #expect(activeClub == "9 iron")
        #expect(done == [1, 0, 0])
        #expect(controller.session?.completion == 1.0 / 7.0)
        #expect(log.events.last == .blockChanged(clubName: "9 iron", target: 2, done: 0))
    }

    @Test func advancePastLastBlockEndsPlan() throws {
        try start(ordered: true)
        controller.advance()
        controller.advance()
        controller.advance()
        #expect(controller.activeBlock == nil)
        #expect(log.events.last == .planEnded)
        #expect(controller.recordShot(source: .manual) == nil)
        let count = log.events.count
        controller.advance()
        #expect(log.events.count == count)
    }

    @Test func freeOrderJumpsAndComesBack() throws {
        try start()
        #expect(controller.select(controller.blocks[2]))
        #expect(log.events == [.blockChanged(clubName: "PW", target: 2, done: 0)])
        hit(1)
        #expect(controller.select(controller.blocks[0]))
        hit(1)
        #expect(done == [1, 0, 1])
        #expect(!controller.select(controller.blocks[0]))
    }

    @Test func mandatoryOrderRefusesJumps() throws {
        try start(ordered: true)
        #expect(!controller.canSelectBlocks)
        #expect(!controller.select(controller.blocks[1]))
        #expect(activeClub == "8 iron")
        #expect(log.events.isEmpty)
    }

    @Test func strictRefusesJumpToFinishedBlock() throws {
        try start(strict: true, targets: [1, 2])
        hit(1)
        #expect(activeClub == "9 iron")
        #expect(!controller.select(controller.blocks[0]))
        #expect(activeClub == "9 iron")
    }

    @Test func minimumsFreeOrderAdvanceFindsIncompleteBlocks() throws {
        try start(targets: [1, 1, 1])
        hit(1)
        #expect(activeClub == "8 iron")
        #expect(controller.select(controller.blocks[2]))
        hit(1)
        controller.advance()
        #expect(activeClub == "9 iron")
        hit(1)
        #expect(controller.isPlanComplete)
        controller.advance()
        #expect(controller.activeBlock == nil)
        #expect(log.events.last == .planEnded)
        #expect(controller.select(controller.blocks[0]))
        hit(1)
        #expect(done == [2, 1, 1])
    }

    @Test func planEditsDoNotChangeRunningSession() throws {
        let plan = makePlan(strict: true, targets: [2, 2])
        try controller.start(plan: plan, cameraAngle: .faceOn)
        plan.isStrictCount = false
        plan.isOrderMandatory = true
        plan.sortedBlocks[0].targetReps = 10
        try context.save()
        hit(2)
        #expect(activeClub == "9 iron")
        #expect(controller.canSelectBlocks)
    }

    @Test func minusOneDeletesLatestShot() throws {
        try start()
        hit(2)
        hit(1, .manual)
        controller.minusOne()
        var block = try #require(controller.activeBlock)
        #expect(block.shots.map(\.detectedBy) == [.camera, .camera])
        #expect(block.repsCounted == 2)
        #expect(block.repsManualAdjust == 0)
        #expect(log.events.last == .countChanged(done: 2, target: 3))

        controller.minusOne()
        block = try #require(controller.activeBlock)
        #expect(block.shots.count == 1)
        #expect(block.repsCounted == 2)
        #expect(block.repsManualAdjust == -1)
        #expect(block.tally.done == 1)
        #expect(try context.fetchCount(FetchDescriptor<ShotRecord>()) == 1)
        #expect(!context.hasChanges)
    }

    @Test func minusOneWithoutShotsLowersAdjustment() throws {
        try start()
        let block = try #require(controller.activeBlock)
        block.repsCounted = 2
        try context.save()
        controller.minusOne()
        #expect(block.repsManualAdjust == -1)
        #expect(block.tally.done == 1)
        #expect(log.events == [.countChanged(done: 1, target: 3)])
    }

    @Test func minusOneNeverGoesBelowZero() throws {
        try start()
        controller.minusOne()
        #expect(controller.activeBlock?.repsManualAdjust == 0)
        #expect(log.events.isEmpty)
        hit(1)
        controller.minusOne()
        controller.minusOne()
        #expect(controller.activeBlock?.tally.done == 0)
        #expect(controller.activeBlock?.repsManualAdjust == -1)
        #expect(log.events == [.countChanged(done: 1, target: 3), .countChanged(done: 0, target: 3)])
    }

    @Test func minusOneRemovesClipFile() throws {
        try start()
        hit(1)
        let shot = try #require(controller.recordShot(source: .camera))
        shot.clipFileName = "\(shot.id.uuidString).mov"
        try context.save()
        let sessionID = try #require(controller.session?.id)
        controller.minusOne()
        #expect(clips.removedClips == ["\(sessionID.uuidString)/\(shot.id.uuidString).mov"])
        controller.minusOne()
        #expect(clips.removedClips.count == 1)
    }

    @Test func minusOneAfterStrictAdvanceReopensBlock() throws {
        try start(strict: true, targets: [2, 2])
        hit(2)
        #expect(activeClub == "9 iron")
        controller.minusOne()
        #expect(activeClub == "8 iron")
        #expect(done == [1, 0])
        #expect(
            log.events.suffix(2) == [
                .countChanged(done: 1, target: 2), .blockChanged(clubName: "8 iron", target: 2, done: 1),
            ])
        hit(1)
        #expect(activeClub == "9 iron")
        #expect(done == [2, 0])
    }

    @Test func minusOneAfterStrictPlanEndReopensLastBlock() throws {
        try start(strict: true, targets: [1])
        hit(1)
        #expect(controller.activeBlock == nil)
        controller.minusOne()
        #expect(activeClub == "8 iron")
        #expect(done == [0])
        #expect(controller.recordShot(source: .camera) != nil)
    }

    @Test func minusOneAfterNextShotStaysOnActiveBlock() throws {
        try start(strict: true, targets: [1, 2])
        hit(2)
        controller.minusOne()
        #expect(activeClub == "9 iron")
        #expect(done == [1, 0])
    }

    @Test func tagsApplyToShotsAndCarryAcrossBlocks() throws {
        try start()
        controller.setTags(["fade"])
        #expect(controller.activeBlock?.tags == ["fade"])
        let first = try #require(controller.recordShot(source: .camera))
        #expect(first.tags == ["fade"])
        controller.advance()
        #expect(controller.activeBlock?.tags == ["fade"])
        #expect(controller.recordShot(source: .manual)?.tags == ["fade"])
        controller.setTags([])
        #expect(controller.recordShot(source: .camera)?.tags == [])
        #expect(controller.blocks.count == 3)
        #expect(!context.hasChanges)
    }

    @Test func finishMarksSessionFinished() throws {
        try start()
        hit(1)
        let session = try #require(controller.session)
        controller.finish()
        #expect(session.status == .finished)
        #expect(session.endedAt == clock.date)
        #expect(session.activeBlockOrder == nil)
        #expect(session.blockResults.count == 3)
        #expect(controller.session == nil)
        #expect(controller.activeBlock == nil)
        #expect(controller.recordShot(source: .camera) == nil)
        #expect(try SessionController.activeSession(in: ModelContext(container)) == nil)
    }

    @Test func discardDeletesSessionAndClips() throws {
        try start()
        hit(2)
        let sessionID = try #require(controller.session?.id)
        controller.discard()
        #expect(controller.session == nil)
        #expect(try context.fetchCount(FetchDescriptor<PracticeSession>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<BlockResult>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ShotRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PracticePlan>()) == 1)
        #expect(clips.removedSessions == [sessionID])
    }
}
```

### `RepsTests/FreeSessionTests.swift`

```swift
import Foundation
import SwiftData
import Testing

@testable import Reps

@MainActor
struct FreeSessionTests {
    let container: ModelContainer
    let context: ModelContext
    let log: EventLog
    let controller: SessionController

    init() throws {
        let clock = TestClock()
        let log = EventLog()
        container = try RepsStore.makeContainer(inMemory: true)
        context = container.mainContext
        controller = SessionController(context: context, now: { clock.next() })
        controller.addEventHandler { log.events.append($0) }
        self.log = log
        try controller.startFree(mode: .rangeCounter, cameraAngle: .faceOn, clubName: "7 iron", tags: ["fade"])
    }

    private func hit(_ count: Int) {
        for _ in 0..<count { controller.recordShot(source: .camera) }
    }

    @Test func startsWithOneUntargetedBlock() throws {
        let session = try #require(controller.session)
        #expect(session.plan == nil)
        #expect(session.planName == nil)
        #expect(controller.isFreeSession)
        #expect(!controller.isStrictCount)
        #expect(controller.blocks.count == 1)
        #expect(controller.activeBlock?.targetReps == nil)
        #expect(controller.activeBlock?.tags == ["fade"])
        #expect(controller.activeTags == ["fade"])
        #expect(log.events == [.blockChanged(clubName: "7 iron", target: nil, done: 0)])
        #expect(!context.hasChanges)
    }

    @Test func countsWithoutTargetOrAdvance() throws {
        hit(50)
        #expect(controller.activeBlock?.tally.done == 50)
        #expect(controller.blocks.count == 1)
        #expect(!log.events.contains { if case .targetReached = $0 { true } else { false } })
        #expect(controller.session?.completion == nil)
        #expect(!controller.isPlanComplete)
        #expect(controller.activeBlock?.shots.allSatisfy { $0.clubName == "7 iron" && $0.tags == ["fade"] } == true)
    }

    @Test func clubChangeStartsNewBlock() throws {
        hit(2)
        controller.setClub("8 iron")
        #expect(controller.blocks.map(\.clubName) == ["7 iron", "8 iron"])
        #expect(controller.blocks.map(\.order) == [0, 1])
        #expect(controller.activeBlock?.tags == ["fade"])
        #expect(log.events.last == .blockChanged(clubName: "8 iron", target: nil, done: 0))
        #expect(controller.recordShot(source: .manual)?.clubName == "8 iron")
        #expect(controller.blocks.map(\.tally.done) == [2, 1])
        #expect(controller.session?.activeBlockOrder == 1)
    }

    @Test func clubChangeOnUnusedBlockRenamesIt() throws {
        controller.setClub("8 iron")
        #expect(controller.blocks.map(\.clubName) == ["8 iron"])
        #expect(log.events.last == .blockChanged(clubName: "8 iron", target: nil, done: 0))
    }

    @Test func sameClubChangesNothing() throws {
        hit(1)
        let count = log.events.count
        controller.setClub("7 iron")
        #expect(controller.blocks.count == 1)
        #expect(log.events.count == count)
    }

    @Test func tagChangeStartsNewBlock() throws {
        hit(1)
        controller.setTags(["draw"])
        #expect(controller.blocks.map(\.clubName) == ["7 iron", "7 iron"])
        #expect(controller.blocks.map(\.tags) == [["fade"], ["draw"]])
        controller.setTags(["draw"])
        #expect(controller.blocks.count == 2)
        hit(1)
        controller.setTags(["draw", "low"])
        controller.setTags(["low", "draw"])
        #expect(controller.blocks.count == 3)
    }

    @Test func tagChangeOnUnusedBlockUpdatesIt() throws {
        controller.setTags(["draw"])
        #expect(controller.blocks.count == 1)
        #expect(controller.activeBlock?.tags == ["draw"])
        #expect(!context.hasChanges)
    }

    @Test func blockNavigationIsOff() throws {
        hit(1)
        controller.setClub("8 iron")
        controller.advance()
        #expect(controller.activeBlock?.clubName == "8 iron")
        #expect(!controller.canSelectBlocks)
        #expect(!controller.select(controller.blocks[0]))
    }

    @Test func minusOneWorksWithoutTarget() throws {
        hit(2)
        controller.minusOne()
        #expect(controller.activeBlock?.tally.done == 1)
        #expect(controller.activeBlock?.shots.count == 1)
    }

    @Test func finishDropsUnusedBlocks() throws {
        hit(1)
        controller.setClub("8 iron")
        let session = try #require(controller.session)
        controller.finish()
        #expect(session.status == .finished)
        let fresh = ModelContext(container)
        let saved = try #require(try fresh.fetch(FetchDescriptor<PracticeSession>()).first)
        #expect(saved.sortedBlockResults.map(\.clubName) == ["7 iron"])
        #expect(try fresh.fetchCount(FetchDescriptor<BlockResult>()) == 1)
    }
}
```

### `RepsTests/SessionResumeTests.swift`

```swift
import Foundation
import SwiftData
import Testing

@testable import Reps

// On-disk store in a temp folder; dropping a container without finish() stands in for a kill.
@MainActor
final class SessionResumeTests {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(
            path: "reps-resume-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private var storeURL: URL { directory.appending(path: "reps.store") }

    @Test func resumesPlannedSessionAfterKill() throws {
        let clock = TestClock()
        var sessionID: UUID?
        do {
            let container = try RepsStore.makeContainer(url: storeURL)
            let context = container.mainContext
            // Only the controller's explicit saves may reach disk.
            context.autosaveEnabled = false
            let plan = PracticePlan(name: "Putting test", mode: .putting, isOrderMandatory: true, isStrictCount: true)
            context.insert(plan)
            plan.blocks = [
                PlanBlock(clubName: "Putter", targetReps: 2, order: 0),
                PlanBlock(clubName: "Putter", targetReps: 3, note: "6ft", order: 1),
            ]
            let controller = SessionController(context: context, now: { clock.next() })
            try controller.start(plan: plan, cameraAngle: .none)
            controller.setTags(["gate"])
            controller.recordShot(source: .camera)
            controller.recordShot(source: .manual)
            controller.recordShot(source: .camera)
            sessionID = controller.session?.id
        }

        let container = try RepsStore.makeContainer(url: storeURL)
        let context = container.mainContext
        let plan = try #require(try context.fetch(FetchDescriptor<PracticePlan>()).first)
        plan.isStrictCount = false
        plan.isOrderMandatory = false
        context.delete(plan)
        try context.save()

        let saved = try #require(try SessionController.activeSession(in: context))
        #expect(saved.id == sessionID)
        #expect(saved.plan == nil)
        let log = EventLog()
        let controller = SessionController(context: context, now: { clock.next() })
        controller.addEventHandler { log.events.append($0) }
        try controller.resume(saved)

        #expect(controller.activeBlock?.order == 1)
        #expect(controller.activeTags == ["gate"])
        #expect(controller.isStrictCount && controller.isOrderMandatory)
        #expect(controller.blocks.map(\.tally.done) == [2, 1])
        #expect(controller.blocks.map(\.targetReps) == [2, 3])
        #expect(controller.blocks[0].shots.count == 2)
        #expect(controller.blocks[1].shots.first?.tags == ["gate"])
        #expect(log.events == [.blockChanged(clubName: "Putter", target: 3, done: 1)])
        #expect(!controller.select(controller.blocks[0]))

        controller.recordShot(source: .camera)
        controller.recordShot(source: .camera)
        #expect(log.events.last == .planEnded)
    }

    @Test func resumesFreeSessionChipAndTags() throws {
        let clock = TestClock()
        do {
            let container = try RepsStore.makeContainer(url: storeURL)
            container.mainContext.autosaveEnabled = false
            let controller = SessionController(context: container.mainContext, now: { clock.next() })
            try controller.startFree(mode: .rangeCounterWithClips, cameraAngle: .downTheLine, clubName: "7 iron")
            controller.recordShot(source: .camera)
            controller.setClub("PW")
            controller.setTags(["low"])
        }

        let container = try RepsStore.makeContainer(url: storeURL)
        let saved = try #require(try SessionController.activeSession(in: container.mainContext))
        let controller = SessionController(context: container.mainContext, now: { clock.next() })
        try controller.resume(saved)
        #expect(controller.isFreeSession)
        #expect(controller.activeBlock?.clubName == "PW")
        #expect(controller.activeTags == ["low"])
        #expect(controller.blocks.map(\.tally.done) == [1, 0])
        #expect(controller.recordShot(source: .camera)?.tags == ["low"])
    }

    @Test func activeSessionIsNewestActiveOnly() throws {
        let container = try RepsStore.makeContainer(inMemory: true)
        let context = container.mainContext
        #expect(try SessionController.activeSession(in: context) == nil)

        let t0 = Date(timeIntervalSince1970: 1_790_000_000)
        let finished = PracticeSession(plan: nil, mode: .rangeCounter, cameraAngle: .faceOn, startedAt: t0)
        finished.status = .finished
        let older = PracticeSession(plan: nil, mode: .rangeCounter, cameraAngle: .faceOn, startedAt: t0 + 10)
        let newer = PracticeSession(plan: nil, mode: .putting, cameraAngle: .none, startedAt: t0 + 20)
        for session in [finished, older, newer] { context.insert(session) }
        try context.save()

        #expect(try SessionController.activeSession(in: context)?.id == newer.id)
        let controller = SessionController(context: context)
        #expect(throws: SessionError.notActive) { try controller.resume(finished) }
    }

    @Test func resumeAfterStrictPlanEndedHasNoActiveBlock() throws {
        let container = try RepsStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let plan = PracticePlan(name: "Test", mode: .putting, isStrictCount: true)
        context.insert(plan)
        plan.blocks = [PlanBlock(clubName: "Putter", targetReps: 1, order: 0)]
        let first = SessionController(context: context)
        try first.start(plan: plan, cameraAngle: .none)
        first.recordShot(source: .camera)

        let saved = try #require(try SessionController.activeSession(in: context))
        let log = EventLog()
        let second = SessionController(context: context)
        second.addEventHandler { log.events.append($0) }
        try second.resume(saved)
        #expect(second.activeBlock == nil)
        #expect(log.events == [.planEnded])
        #expect(second.recordShot(source: .camera) == nil)
    }
}
```

## Appendix B: `docs/adr/0013-session-engine-rules.md`

```markdown
# 0013 — Session engine rules, −1, snapshots; V1 amended before first install

- Status: Accepted (extends 0006, 0012)
- Date: 2026-09-27

## Context
F2 says blocks advance at target, F21 says targets are minimums, and F22 adds a strict mode. F18 adds mandatory or free order. §6 needs kill-safe resume, including after the plan is edited or deleted (Q24). Q21 settles −1.

## Decision
- `SessionController` (MainActor, @Observable) is the only writer during a session. It saves after every change and reports to the voice layer through `SessionEvent` values.
- Minimums (default): reaching the target announces it and stays on the block; the user moves on. Strict: the block ends exactly at target and auto-advances; extra shots are ignored.
- Next block: mandatory order takes the next block in sequence; free order takes the next incomplete block, wrapping. With none left, no block is active until the user picks one or ends the session. Only Done finishes a session.
- One BlockResult per plan block is created at start. Free sessions start a new block when the club or tag set changes, unless the current block is unused.
- +1 counts as a manual adjustment and camera shots as detections, and both create a ShotRecord. −1 deletes the latest ShotRecord and its clip when there is one and always lowers `repsManualAdjust`, never below zero. Right after a strict auto-advance, −1 reopens the block that just ended (not persisted).
- The session snapshots `isStrictCount`, `isOrderMandatory` and `activeBlockOrder`. `RepsSchemaV1` was amended in place to add them, before any real store existed; the next schema change must be RepsSchemaV2 with a migration stage. Export format v1 gains the two rule flags.

## Consequences
Resume never depends on the plan. Detector accuracy stays readable from `repsCounted` vs `repsManualAdjust`. Clip deletion is behind `ClipFileRemoving` until #22.
```

## Appendix C: `docs/code-reference.md` entries

Replace the `Reps/Model/PracticeSession.swift` entry with:

```markdown
## Reps/Model/PracticeSession.swift
- `PracticeSession(plan:mode:cameraAngle:startedAt:)`: one run (plan nil = free session); copies `planName`, `isStrictCount`, `isOrderMandatory`; `status` starts `.active`; `blockResults` cascade
- `activeBlockOrder`: `order` of the active block for resume; nil when no block is left (Q24, ADR 0013)
- `isFreeSession`: `planName == nil`
- `sortedBlockResults`: by `(order, id)`; `completion`: `Completion.session` over the results
```

Replace the `Reps/Persistence/RepsStore.swift` entry with:

```markdown
## Reps/Persistence/RepsStore.swift
Builds the SwiftData container for the app and tests.
- `RepsStore.models`: the `@Model` types (`RepsSchemaCurrent.models`)
- `RepsStore.makeContainer(inMemory:) throws -> ModelContainer`: container over `RepsSchemaCurrent` with `RepsMigrationPlan`; `inMemory: true` for tests
- `RepsStore.makeContainer(url:) throws -> ModelContainer`: same, at a given store file (tests reopen it to simulate a kill)
```

Replace the `Reps/Export/ExportDocument.swift` entry's second bullet with:

```markdown
- `ExportClub`, `ExportPlan`, `ExportPlanBlock`, `ExportSession` (with the `isStrictCount`/`isOrderMandatory` snapshot), `ExportBlockResult`, `ExportShot`: raw stored fields, ids for cross references
```

Add after `Reps/Export/RepsExport.swift`:

```markdown
## Reps/Session/SessionEvent.swift
What the session engine tells the voice layer (#10); plain values, nonisolated.
- `countChanged(done:target:)`: after every counted shot and every effective −1
- `targetReached(clubName:target:isStrict:)`: done just became equal to the target; strict blocks end here
- `blockChanged(clubName:target:done:)`: a block became active (start, resume, next, strip jump, strict auto-advance, club/tag change, −1 reopening a block)
- `planEnded`: no block left to run; shots are ignored until a block is selected or the session ends

## Reps/Session/ClipFileRemoving.swift
- `ClipFileRemoving`: `removeClip(fileName:sessionID:)`, `removeClips(sessionID:)` for `Documents/clips/<sessionId>/`; #22 supplies the real one
- `NoClipFiles`: no-op default

## Reps/Session/SessionController.swift
The session engine (spec §4, F2, F14, F16, F18, F21, F22, §6; ADR 0013). MainActor, `@Observable`, saves after every change, then emits events.
- `SessionController(context:clipFiles:now:)`: clip remover and clock are injectable
- State: `session`, `activeBlock`, `activeTags`, `lastSaveError`; computed `blocks`, `isFreeSession`, `isStrictCount`, `isOrderMandatory`, `canSelectBlocks`, `isPlanComplete`
- `addEventHandler(_:)`: synchronous handlers, called in order after the save
- `start(plan:cameraAngle:) throws`: one BlockResult per plan block, first active; `SessionError.emptyPlan`, `.sessionInProgress`
- `startFree(mode:cameraAngle:clubName:tags:) throws`: one untargeted block
- `activeSession(in:) throws -> PracticeSession?`: newest `.active` session, for the resume prompt
- `resume(_:) throws`: restores the active block and tags from the snapshot; `.sessionInProgress`, `.notActive`
- `recordShot(source:) -> ShotRecord?`: camera → `repsCounted`, manual (+1) → `repsManualAdjust`; nil when ignored; strict auto-advances at target
- `minusOne()`: deletes the latest shot and its clip if any, lowers `repsManualAdjust`, never below zero; right after a strict auto-advance, reopens the block that ended
- `advance()`: next block (mandatory: next in order; free: next incomplete, wrapping), or `planEnded`
- `select(_:) -> Bool`: block strip jump; false in free sessions, with mandatory order, or onto a complete strict block
- `setClub(_:)`, `setTags(_:)`: free sessions start a new block unless the current one is unused; planned sessions carry tags across blocks
- `finish()`: `finished` + `endedAt`, drops unused free blocks; `discard()`: deletes the session and its clips
```

Add after `RepsTests/ExportTests.swift`:

```markdown
## RepsTests/SessionTestSupport.swift
- `TestClock` (1 s per read), `ClipSpy` (records clip removals), `EventLog` (collects `SessionEvent`s)

## RepsTests/SessionControllerTests.swift
Planned sessions: start, counting, minimums vs strict, mandatory vs free order, skip, last block, plan edits, −1 (Q21), tags, finish, discard.

## RepsTests/FreeSessionTests.swift
Free sessions: untargeted blocks, club/tag changes start blocks (in place when unused), navigation off, finish drops unused blocks.

## RepsTests/SessionResumeTests.swift
On-disk kill and resume (autosave off), newest-active lookup, resume after a strict plan ended.
```

## Appendix D: `docs/open-questions.md` rows (Open table)

```markdown
| Q25 | When the launch "resume?" prompt is declined, keep the session (`finish`) or delete it (`discard`)? | #9, #11 | Leaning: keep (finish), since ADR 0006 already saved every shot; offer delete only from the log. #8 provides both. |
| Q26 | F2 says blocks advance automatically at target; F21 says targets are minimums and the count goes past. Should non-strict blocks auto-advance? | – (decided in #8, confirm) | #8: no. Minimums announce the target and stay; strict auto-advances (ADR 0013). Flip it in `recordShot` if the owner prefers F2 literally. |
```
