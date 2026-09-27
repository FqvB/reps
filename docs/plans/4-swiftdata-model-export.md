# #4 SwiftData model + JSON export

Goal: the six SwiftData models from spec §5.1 (with the ADR 0006 changes), pure completion math, and a versioned Codable JSON export shape with a pure encoder (`Data` out). Nothing is written to disk and nothing leaves the device in this issue.

Spec: §5.1, §10 (export without changes), F1, F2, F8, F14, F16, F18, F19, F21, F22, F23, §5.3b, §5.8, §6 (kill-safe). ADRs: 0004, 0006, 0009. Owner comment: `status` active/finished, no uncertainty flag, UUID clip file names.

Every file in **Appendix A** was built and tested by the planner in a scratch copy of the repo with Xcode 27.0 (27A5252f) on the iPhone 17 Pro simulator: full `Unit` plan passed (30 tests in 4 suites), zero compiler warnings, `xcrun swift-format lint --strict -r Reps RepsTests` clean. The Unit tests are hosted in the app, so each run also opened the **on-disk** store through the new migration plan (and upgraded the simulator's existing empty-schema store from #1 without error). **Copy the file contents exactly.**

Out of scope (later issues): writing the export to a file, the share sheet or any UI that sends data off the device (needs the Fable security path; no issue yet), the default 14-club bag and seeding (#5), plan editing UI (#7), session creation, +1/−1 and block advance logic (#8), clip files and their deletion (#22), library queries and bulk retag (#24).

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Where things live | `Reps/Model/` (models, enums, completion math, schema), `Reps/Export/` (export DTOs and encoder), `Reps/Persistence/RepsStore.swift` (container). App target, synced folders, so no pbxproj edits. | Keeps persistence types together; export is separable for the later share issue. |
| Isolation | App target defaults to MainActor (ADR 0009), so `@Model` classes and `RepsExport.document(...)` are MainActor, which matches `mainContext` and the future `SessionController`. The four enums, `BlockTally`, `Completion`, all `Export*` structs and `ExportCoding` are marked `nonisolated` (and `Sendable`) so their `Codable`/`Equatable` conformances aren't MainActor-isolated: SwiftData encodes attribute values off the main actor, the pure math is callable from anywhere, and encoding can move to a background task later. | Verified: builds with zero warnings; tests call the pure code from non-isolated suites. |
| IDs | Every model has `var id: UUID = UUID()`. | Export needs stable ids across devices/exports (§10). ADR 0006 needs `sessionId` and `shotUUID` for clip paths. |
| Uniqueness / indexes | No `#Unique`, no `#Index`, no `@Attribute(.unique)`. | `#Unique` upserts silently on conflict (a duplicate club name would overwrite, not fail) and blocks a later CloudKit move (§10). Bag name uniqueness is a UI rule for #5/#6. Indexes go in with the queries that need them (#24). |
| Default values | Every stored non-optional property has a default value at the declaration (`= ""`, `= 0`, `= UUID()`, `= Date()`, enum case, `= []`). Enum defaults are written with the type (`PracticeMode.rangeCounter`), not `.rangeCounter`. | Lightweight migrations of later added properties and a CloudKit move both want defaults; the explicitly typed form is what was verified. |
| Enums | `String` raw values, `Codable`, raw value = case name: `PracticeMode {rangeCounter, rangeCounterWithClips, putting}`, `CameraAngle {faceOn, downTheLine, none}`, `DetectionSource {camera, manual}`, `SessionStatus {active, finished}`. Stored directly as model attributes. | Stored and exported as the raw string; the raw values are frozen (renaming = migration + export version bump). `.none` follows the spec; `cameraAngle` is never optional so there's no `Optional.none` ambiguity. Predicates on enums work (verified: `#Predicate { $0.status == activeRaw }` with a captured local). |
| Relationships and delete rules | `PracticePlan.blocks` ↔ `PlanBlock.plan`: **cascade**. `PracticePlan.sessions` ↔ `PracticeSession.plan`: **nullify** (history outlives plans). `PlanBlock.results` ↔ `BlockResult.block`: **nullify** (editing a plan never touches history). `PracticeSession.blockResults` ↔ `BlockResult.session`: **cascade**. `BlockResult.shots` ↔ `ShotRecord.blockResult`: **cascade**. `@Relationship(deleteRule:inverse:)` is declared on the to-many side only; the to-one side is a plain optional. | Verified by in-memory tests. Cascades apply on `save()`; tests save before counting. |
| Ordering | Relationship arrays are unordered in the store. `PlanBlock.order` and `BlockResult.order` are explicit `Int` indexes; read through `PracticePlan.sortedBlocks`, `PracticeSession.sortedBlockResults`; shots through `BlockResult.sortedShots` (by `timestamp`). Never rely on array order. | Spec §5.1 says "ordered"; SwiftData doesn't keep it. |
| BagClub | No relationship to anything. Blocks, results and shots reference clubs by **name** (`clubName: String`). `isInBag = false` hides a club; deleting a `BagClub` touches nothing else. | Spec §5.1 (`isInBag` keeps old plans resolving), §5.3b (club on every shot for one-predicate filters). Renaming a bag club does not rename existing blocks/shots; that's #6's call. |
| Snapshots for history | `PracticeSession.planName: String?` (copied from the plan at init), `PracticeSession.mode` (free sessions have no plan), `BlockResult.clubName` and **`BlockResult.targetReps: Int?`** (copied from the `PlanBlock`, `nil` in a free session), `ShotRecord.clubName`. | The log (F8), summary (F23) and export must show the same numbers after the plan is edited or deleted. `targetReps` on the result is not in the spec's §5.1 sketch; without it completion history changes whenever the plan is edited. |
| `BlockResult.tags: [String]` | Added (not in §5.1). The active tag set of the block. | §5.1: a free-session block starts whenever the club *or tag set* changes; storing it lets #8 restore chip + tags on resume after a kill (§6) even before the first shot. |
| Status | `PracticeSession.status: SessionStatus = .active`. No uncertainty flag or confidence on `ShotRecord`. | ADR 0006. |
| Clip reference | `ShotRecord.clipFileName: String?` holds the bare file name `<shot.id>.mov`; the directory `Documents/clips/<session.id>/` is implied. #22 sets it. Export always strips any directory part (`RepsExport.bareFileName`). | ADR 0006: no user text in paths; export never leaks device paths. |
| `repsCounted` vs shots | Stored as in the spec. Invariant for #8 (not enforced here): `repsCounted` = camera detections in the block, `repsManualAdjust` = net +1/−1. | Spec §5.1 keeps them apart for accuracy tracking. |
| Completion math | Pure: `BlockTally(counted:manualAdjust:target:)`, `done = max(0, counted + manualAdjust)`. `Completion.block(_:) -> Double?` = done/target, uncapped, `nil` when target is `nil` or ≤ 0. `Completion.isComplete(_:) -> Bool` = done ≥ target (false without a positive target). `Completion.session(_:) -> Double?` = Σdone / Σtarget over blocks with a positive target, uncapped; untargeted (free) blocks are ignored; `nil` if no targeted block. Fractions (1.5 = 150 %); formatting to a percent is UI (#11/#12). Models expose `BlockResult.tally` and `PracticeSession.completion`. | Spec §5.1, F21. A skipped block (result with 0 reps) counts its full target against the session; #8 must therefore create one `BlockResult` per plan block at session start. Over-target on one block offsets a shortfall on another (spec literal, see Q22). |
| Schema versioning | `RepsSchemaV1: VersionedSchema` (1.0.0) listing the six top-level model types, and `RepsMigrationPlan: SchemaMigrationPlan` with `[RepsSchemaV1.self]` and no stages. `RepsStore.makeContainer` uses `Schema(versionedSchema:)` and `ModelContainer(for:migrationPlan:configurations:)`. | Phase 1 goes on the phone and real sessions get logged from week two, so the first schema change must not lose data. Declaring V1 now costs ~15 lines and fixes the store's version identity. Models stay top-level (not nested in the enum) for readability; when V2 is needed, copy the V1 classes verbatim into `RepsSchemaV1` as nested types, then add `RepsSchemaV2` and a stage. |
| Export shape | `ExportDocument { formatVersion: 1, exportedAt, bag: [ExportClub], plans: [ExportPlan], sessions: [ExportSession] }`; sessions nest `blocks: [ExportBlockResult]`, which nest `shots: [ExportShot]`. Swift property names are the JSON keys (camelCase, no key strategy). Relationships to other top-level items are ids (`planId`, `planBlockId`). Raw stored values only, no derived fields (no `done`, no completion %): a consumer recomputes with §5.1's formula. `nil` optionals are omitted (synthesized `encodeIfPresent`). | §10: "export as JSON without changes". Raw data can't disagree with a later math change. Key names are guarded by tests that assert exact key sets. |
| Export content | All bag clubs (by `sortOrder`), all plans (by `createdAt`, blocks by `order`), **finished sessions only** (by `startedAt`, results by `order`, shots by `timestamp`). | Active sessions are still being written (ADR 0006); the log also shows only finished ones. |
| Encoding | `ExportCoding.encode(_:) throws -> Data`: `.prettyPrinted, .sortedKeys, .withoutEscapingSlashes`, dates as ISO 8601 UTC with milliseconds (`2026-09-21T14:13:20.250Z`) via `Date.ISO8601FormatStyle(includingFractionalSeconds: true)` in a `.custom` strategy. `ExportCoding.decode(_:)` is the exact inverse (used by the round-trip test, and by a future import). | Deterministic bytes (verified: encoding twice gives equal `Data`). Plain `.iso8601` drops sub-second precision; two manual taps can land in the same second. |
| Tests | Swift Testing, `Unit` plan, `RepsTests`. Pure math in a non-isolated suite; SwiftData suites are `@MainActor` and use `RepsStore.makeContainer(inMemory: true)`. **A suite must hold the `ModelContainer` in a stored property**, not just its `mainContext`: the context doesn't retain the container and the test process crashes (hit while prototyping). | TDD per CLAUDE.md for completion math and export. |

## Final layout

```
Reps/Model/ModelEnums.swift        new: PracticeMode, CameraAngle, DetectionSource, SessionStatus
Reps/Model/Completion.swift        new: BlockTally, Completion
Reps/Model/BagClub.swift           new
Reps/Model/PracticePlan.swift      new
Reps/Model/PlanBlock.swift         new
Reps/Model/PracticeSession.swift   new
Reps/Model/BlockResult.swift       new
Reps/Model/ShotRecord.swift        new
Reps/Model/RepsSchema.swift        new: RepsSchemaV1, RepsMigrationPlan
Reps/Persistence/RepsStore.swift   changed: models from V1, container with migration plan
Reps/Export/ExportDocument.swift   new: ExportDocument + 6 nested Codable structs
Reps/Export/RepsExport.swift       new: RepsExport (models → document), ExportCoding (Data out)
RepsTests/CompletionTests.swift    new
RepsTests/ModelTests.swift         new
RepsTests/RepsStoreTests.swift     changed: + 2 tests
RepsTests/ExportTests.swift        new
docs/adr/0012-data-model-and-export-v1.md   new
docs/adr/README.md, docs/code-reference.md, docs/roadmap.md, docs/open-questions.md   updated
```

`Reps/App/RepsApp.swift` and `RootView.swift` are unchanged (`makeContainer()` keeps its signature).

## Types and signatures

```swift
// Reps/Model/ModelEnums.swift — all `nonisolated enum X: String, Codable, CaseIterable, Sendable`
PracticeMode { rangeCounter, rangeCounterWithClips, putting }
CameraAngle { faceOn, downTheLine, none }
DetectionSource { camera, manual }
SessionStatus { active, finished }

// Reps/Model/Completion.swift
nonisolated struct BlockTally: Equatable, Sendable { var counted: Int; var manualAdjust: Int; var target: Int?; var done: Int { get } }
nonisolated enum Completion {
    static func block(_ tally: BlockTally) -> Double?
    static func isComplete(_ tally: BlockTally) -> Bool
    static func session(_ tallies: [BlockTally]) -> Double?
}

// @Model final classes (MainActor by default)
BagClub(name:sortOrder:isInBag: = true)               id, name, sortOrder, isInBag
PracticePlan(name:mode:isOrderMandatory: = false, isStrictCount: = false, createdAt: = .now)
    id, name, mode, isOrderMandatory, isStrictCount, createdAt, blocks (cascade), sessions (nullify), sortedBlocks
PlanBlock(clubName:targetReps:note: = nil, order:)    id, clubName, targetReps, note, order, plan, results (nullify)
PracticeSession(plan:mode:cameraAngle:startedAt: = .now)
    id, plan, planName (copied from plan), mode, status (.active), startedAt, endedAt, cameraAngle,
    blockResults (cascade), sortedBlockResults, completion: Double?
BlockResult(block:order:)                             copies clubName + targetReps from the block
BlockResult(clubName:tags: = [], order:)              free-session block, targetReps nil
    id, session, block, order, clubName, targetReps, tags, repsCounted, repsManualAdjust, shots (cascade), tally, sortedShots
ShotRecord(timestamp: = .now, detectedBy:clubName:tags: = [])
    id, blockResult, timestamp, detectedBy, clubName, tags, isFavourite, tempoRatio, clipFileName

// Reps/Model/RepsSchema.swift
enum RepsSchemaV1: VersionedSchema  // versionIdentifier 1.0.0, models = the six types
enum RepsMigrationPlan: SchemaMigrationPlan  // schemas [RepsSchemaV1.self], stages []

// Reps/Persistence/RepsStore.swift
RepsStore.models: [any PersistentModel.Type]  // = RepsSchemaV1.models
RepsStore.makeContainer(inMemory: Bool = false) throws -> ModelContainer

// Reps/Export
nonisolated struct ExportDocument: Codable, Equatable, Sendable  // static currentFormatVersion = 1
ExportClub, ExportPlan, ExportPlanBlock, ExportSession, ExportBlockResult, ExportShot  // same conformances
enum RepsExport {  // MainActor
    static func document(clubs:plans:sessions:exportedAt:) -> ExportDocument
    static func document(from context: ModelContext, exportedAt: Date) throws -> ExportDocument
    nonisolated static func bareFileName(_ path: String) -> String
}
nonisolated enum ExportCoding {
    static func encode(_ document: ExportDocument) throws -> Data
    static func decode(_ data: Data) throws -> ExportDocument
}
```

Example output (shape only; ids shortened):

```json
{
  "bag" : [ { "id" : "…", "isInBag" : false, "name" : "8 iron", "sortOrder" : 0 } ],
  "exportedAt" : "2026-09-21T14:13:20.250Z",
  "formatVersion" : 1,
  "plans" : [ { "blocks" : [ { "clubName" : "8 iron", "id" : "…", "note" : "150m, fade", "order" : 0, "targetReps" : 40 } ],
               "createdAt" : "…", "id" : "…", "isOrderMandatory" : false, "isStrictCount" : true,
               "mode" : "rangeCounterWithClips", "name" : "Wedge day" } ],
  "sessions" : [ { "blocks" : [ { "clubName" : "8 iron", "id" : "…", "order" : 0, "planBlockId" : "…",
                                  "repsCounted" : 1, "repsManualAdjust" : 1, "tags" : [ "fade" ], "targetReps" : 40,
                                  "shots" : [ { "clipFileName" : "<shot id>.mov", "clubName" : "8 iron", "detectedBy" : "camera",
                                                "id" : "…", "isFavourite" : true, "tags" : [ "fade" ], "tempoRatio" : 3.1,
                                                "timestamp" : "2026-09-21T14:13:30.250Z" } ] } ],
                   "cameraAngle" : "downTheLine", "endedAt" : "…", "id" : "…", "mode" : "rangeCounterWithClips",
                   "planId" : "…", "planName" : "Wedge day", "startedAt" : "…", "status" : "finished" } ]
}
```

## Steps

Branch `feat/4-swiftdata-model-export` (already checked out). Run everything from the repo root. `DEST='platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'`. Follow TDD in steps 1–3: create the test file first, run the filtered suite and see it fail (a compile failure counts), then add the production files and see it pass. Before each commit run `xcrun swift-format lint --strict -r Reps RepsTests` (must print nothing).

### Step 1 — enums and completion math

1. Create `RepsTests/CompletionTests.swift` (Appendix A). Run
   `xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan Unit -destination "$DEST" -only-testing:RepsTests/CompletionTests` → fails to compile.
2. Create `Reps/Model/ModelEnums.swift` and `Reps/Model/Completion.swift`. Same command → `CompletionTests` passes (9 tests, 16 cases).
3. `git add -A && git commit -m "added completion math" -m "Refs #4"`

### Step 2 — models, schema, container

1. Replace `RepsTests/RepsStoreTests.swift` and create `RepsTests/ModelTests.swift` (Appendix A). Run with `-only-testing:RepsTests/ModelTests -only-testing:RepsTests/RepsStoreTests` → fails to compile.
2. Create the six model files and `Reps/Model/RepsSchema.swift`; replace `Reps/Persistence/RepsStore.swift`. Same command → both suites pass (9 + 3 tests).
3. `git add -A && git commit -m "added swiftdata models" -m "Refs #4"`

### Step 3 — export shape and encoder

1. Create `RepsTests/ExportTests.swift`. Run with `-only-testing:RepsTests/ExportTests` → fails to compile.
2. Create `Reps/Export/ExportDocument.swift` and `Reps/Export/RepsExport.swift`. Same command → passes (9 tests, 12 cases).
3. Full Unit plan: `xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan Unit -destination "$DEST"` → `Test run with 30 tests in 4 suites passed`, `** TEST SUCCEEDED **`. Check there are no compiler warnings from `Reps/` or `RepsTests/`: `… 2>&1 | grep 'warning:' | grep -v appintents` prints nothing.
4. `git add -A && git commit -m "added json export shape" -m "Refs #4"`

### Step 4 — docs

1. `docs/adr/0012-data-model-and-export-v1.md` (Appendix B) and a row in `docs/adr/README.md`:
   `| [0012](0012-data-model-and-export-v1.md) | Data model snapshots, VersionedSchema V1, JSON export format v1 | Accepted |`
2. `docs/code-reference.md`: replace the `RepsStore.swift` entry and the `RepsStoreTests.swift` entry, and add the new entries from Appendix C (place the `Reps/Model/*` and `Reps/Export/*` entries after `Reps/App/RootView.swift`, the test entries after `RepsStoreTests.swift`).
3. `docs/open-questions.md`: add Q21 and Q22 (Appendix D) to the Open table.
4. `docs/roadmap.md`: #4 status ☐ → ☑.
5. `git add -A && git commit -m "documented data model and export" -m "Refs #4"`

Then review (`review:opus`), fix findings, push, PR titled `added swiftdata model and json export`, body one line + `Closes #4`.

## Tests

All in the `Unit` plan (`RepsTests`, Swift Testing). No UI, no DetectorEval.

- `CompletionTests` (pure, non-isolated): `blockCompletion(tally:expected:)` (30/30 → 1, 45/30 → 1.5, 0/30 → 0, 28+2/30 → 1, 0+15/30 → 0.5, 31−1/40 → 0.75), `negativeNetClampsToZero`, `noPositiveTargetHasNoCompletion(target:)` (nil, 0, −5), `completeAtOrOverTarget`, `sessionIsTotalDoneOverTotalTarget`, `skippedBlockCountsAgainstSession`, `sessionCanExceedOne`, `untargetedBlocksAreIgnored`, `sessionWithoutTargetsHasNoCompletion`.
- `ModelTests` (`@MainActor`, in-memory): `sortedBlocksFollowOrderIndex`, `blockResultSnapshotsPlanBlock`, `deletingPlanCascadesBlocksAndKeepsHistory`, `deletingPlanBlockKeepsResult`, `deletingSessionCascadesResultsAndShots`, `deletingBagClubLeavesPlansAndShots`, `enumsAndTagsPersist` (re-fetched through a fresh `ModelContext`), `activeSessionsAreFetchableByStatus` (enum predicate, what #8's resume prompt needs), `sessionCompletionUsesSnapshots`.
- `RepsStoreTests`: existing `inMemoryContainerOpens`, plus `schemaHasEveryModel`, `schemaIsVersionOne`.
- `ExportTests` (`@MainActor`, in-memory): `topLevelShape`, `bagIsSortedBySortOrder`, `planShape` (note omitted when nil), `onlyFinishedSessionsAreExported`, `blockResultsAndShots` (order, ISO dates with ms, enum raw strings, nil keys omitted), `clipIsReferencedByFileNameOnly`, `freeSessionHasNoPlanKeys`, `roundTripsAndIsDeterministic`, `bareFileName(path:expected:)`.

Fixture dates use `Date(timeIntervalSince1970: 1_790_000_000.25)` (= `2026-09-21T14:13:20.250Z`): whole milliseconds, so the round trip is exact.

## Verification

```sh
DEST='platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'
xcrun swift-format lint --strict -r Reps RepsTests
xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan Unit -destination "$DEST"
# single suites while iterating:
xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan Unit -destination "$DEST" -only-testing:RepsTests/ExportTests
```

If a run prints `Restarting after unexpected exit, crash` and then hangs, a suite dropped its `ModelContainer`; kill `xcodebuild`, fix, rerun.

## Risks and unresolved

- **Data leaving the device.** Nothing in the spec puts file writing, sharing or upload in #4, and this plan has none: `ExportCoding.encode` returns `Data`. Whoever adds a "Export JSON" button/share sheet must go through the Fable planner + `fable-security` review (the export contains all practice history, tags as free text, and clip names). There is no issue for it yet; spec §10 only asks that the model *can* be exported.
- **Session completion lets surplus cover a shortfall** (45/30 + 15/30 = 100 %). This is the spec's literal "total done over total target". Q22 asks whether per-block contributions should be capped at 100 % for the session number; changing it later is a one-line change in `Completion.session` plus tests.
- **−1 semantics are #8's call** (Q21): does −1 delete the latest `ShotRecord` or only decrement `repsManualAdjust`? The model supports both. Likewise #8 must create one `BlockResult` per plan block at session start, or skipped blocks drop out of the session completion.
- **Deleting a session or shot leaves clip files on disk.** Cascade deletes only SwiftData rows. #22/#24 must delete `Documents/clips/<sessionId>/` (or the shot's file) alongside the row. Deleting a `ShotRecord` also doesn't adjust `repsCounted`; #24 decides.
- **Tags as `[String]`**: stored as a Codable array attribute. `#Predicate` support for `tags.contains(x)` on array attributes is limited; #24 may need to filter in memory or move tags to a model. Retagging shots does not change `BlockResult.tags`.
- **Renaming a bag club** doesn't rename plan blocks or shots (names are copied). #6 decides whether a rename propagates.
- **VersionedSchema with top-level models**: before the first V2, the V1 class definitions must be copied, unchanged, into `RepsSchemaV1` as nested types; otherwise the migration plan can't describe the old store. Noted in ADR 0012.
- **Export format stability**: JSON keys are Swift property names. Renaming a property on an `Export*` struct changes the format; the key-set tests fail if that happens, and any intentional change bumps `currentFormatVersion`.
- **No CloudKit readiness beyond defaults**: relationships are non-optional arrays and there's no `@Attribute(.externalStorage)` thinking; a CloudKit move (§10) would need a schema version.

## Appendix A — files (verified; copy exactly)

### `Reps/Model/ModelEnums.swift`

```swift
// Raw values are persisted and exported; never rename them.
nonisolated enum PracticeMode: String, Codable, CaseIterable, Sendable {
    case rangeCounter
    case rangeCounterWithClips
    case putting
}

nonisolated enum CameraAngle: String, Codable, CaseIterable, Sendable {
    case faceOn
    case downTheLine
    case none
}

nonisolated enum DetectionSource: String, Codable, CaseIterable, Sendable {
    case camera
    case manual
}

nonisolated enum SessionStatus: String, Codable, CaseIterable, Sendable {
    case active
    case finished
}
```

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

    // Total done over total target across targeted blocks; untargeted blocks are ignored.
    static func session(_ tallies: [BlockTally]) -> Double? {
        let targeted = tallies.filter { ($0.target ?? 0) > 0 }
        let target = targeted.reduce(0) { $0 + ($1.target ?? 0) }
        guard target > 0 else { return nil }
        let done = targeted.reduce(0) { $0 + $1.done }
        return Double(done) / Double(target)
    }
}
```

### `RepsTests/CompletionTests.swift`

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

    @Test func sessionIsTotalDoneOverTotalTarget() {
        let tallies = [
            BlockTally(counted: 45, manualAdjust: 0, target: 30),
            BlockTally(counted: 10, manualAdjust: 5, target: 30),
        ]
        #expect(Completion.session(tallies) == 1.0)
    }

    @Test func skippedBlockCountsAgainstSession() {
        let tallies = [
            BlockTally(counted: 30, manualAdjust: 0, target: 30),
            BlockTally(counted: 0, manualAdjust: 0, target: 10),
        ]
        #expect(Completion.session(tallies) == 0.75)
    }

    @Test func sessionCanExceedOne() {
        let tallies = [BlockTally(counted: 60, manualAdjust: 0, target: 40)]
        #expect(Completion.session(tallies) == 1.5)
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

### `Reps/Model/BagClub.swift`

```swift
import Foundation
import SwiftData

@Model
final class BagClub {
    var id: UUID = UUID()
    var name: String = ""
    var sortOrder: Int = 0
    // false hides it from pickers; plans keep referencing clubs by name.
    var isInBag: Bool = true

    init(name: String, sortOrder: Int, isInBag: Bool = true) {
        self.name = name
        self.sortOrder = sortOrder
        self.isInBag = isInBag
    }
}
```

### `Reps/Model/PracticePlan.swift`

```swift
import Foundation
import SwiftData

@Model
final class PracticePlan {
    var id: UUID = UUID()
    var name: String = ""
    var mode: PracticeMode = PracticeMode.rangeCounter
    var isOrderMandatory: Bool = false
    var isStrictCount: Bool = false
    var createdAt: Date = Date()
    // Unordered in the store; read through sortedBlocks.
    @Relationship(deleteRule: .cascade, inverse: \PlanBlock.plan)
    var blocks: [PlanBlock] = []
    // Sessions outlive their plan.
    @Relationship(deleteRule: .nullify, inverse: \PracticeSession.plan)
    var sessions: [PracticeSession] = []

    init(
        name: String,
        mode: PracticeMode,
        isOrderMandatory: Bool = false,
        isStrictCount: Bool = false,
        createdAt: Date = .now
    ) {
        self.name = name
        self.mode = mode
        self.isOrderMandatory = isOrderMandatory
        self.isStrictCount = isStrictCount
        self.createdAt = createdAt
    }

    var sortedBlocks: [PlanBlock] {
        blocks.sorted { $0.order < $1.order }
    }
}
```

### `Reps/Model/PlanBlock.swift`

```swift
import Foundation
import SwiftData

@Model
final class PlanBlock {
    var id: UUID = UUID()
    var clubName: String = ""
    var targetReps: Int = 0
    var note: String?
    var order: Int = 0
    var plan: PracticePlan?
    // Results keep their snapshot when the block is deleted.
    @Relationship(deleteRule: .nullify, inverse: \BlockResult.block)
    var results: [BlockResult] = []

    init(clubName: String, targetReps: Int, note: String? = nil, order: Int) {
        self.clubName = clubName
        self.targetReps = targetReps
        self.note = note
        self.order = order
    }
}
```

### `Reps/Model/PracticeSession.swift`

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
    @Relationship(deleteRule: .cascade, inverse: \BlockResult.session)
    var blockResults: [BlockResult] = []

    init(plan: PracticePlan?, mode: PracticeMode, cameraAngle: CameraAngle, startedAt: Date = .now) {
        self.plan = plan
        self.planName = plan?.name
        self.mode = mode
        self.cameraAngle = cameraAngle
        self.startedAt = startedAt
    }

    var sortedBlockResults: [BlockResult] {
        blockResults.sorted { $0.order < $1.order }
    }

    var completion: Double? {
        Completion.session(blockResults.map(\.tally))
    }
}
```

### `Reps/Model/BlockResult.swift`

```swift
import Foundation
import SwiftData

@Model
final class BlockResult {
    var id: UUID = UUID()
    var session: PracticeSession?
    var block: PlanBlock?
    var order: Int = 0
    var clubName: String = ""
    // Snapshot of the plan block's target; nil in a free session.
    var targetReps: Int?
    // Active tag set for this block, restored on resume.
    var tags: [String] = []
    var repsCounted: Int = 0
    // Net of +1/−1 taps, kept apart from detections (spec §5.1).
    var repsManualAdjust: Int = 0
    @Relationship(deleteRule: .cascade, inverse: \ShotRecord.blockResult)
    var shots: [ShotRecord] = []

    init(block: PlanBlock, order: Int) {
        self.block = block
        self.order = order
        self.clubName = block.clubName
        self.targetReps = block.targetReps
    }

    init(clubName: String, tags: [String] = [], order: Int) {
        self.clubName = clubName
        self.tags = tags
        self.order = order
    }

    var tally: BlockTally {
        BlockTally(counted: repsCounted, manualAdjust: repsManualAdjust, target: targetReps)
    }

    var sortedShots: [ShotRecord] {
        shots.sorted { $0.timestamp < $1.timestamp }
    }
}
```

### `Reps/Model/ShotRecord.swift`

```swift
import Foundation
import SwiftData

@Model
final class ShotRecord {
    var id: UUID = UUID()
    var blockResult: BlockResult?
    var timestamp: Date = Date()
    var detectedBy: DetectionSource = DetectionSource.manual
    // Copied from the block so retagging one shot is cheap (spec §5.1).
    var clubName: String = ""
    var tags: [String] = []
    var isFavourite: Bool = false
    var tempoRatio: Double?
    // Bare file name "<id>.mov" under Documents/clips/<sessionId>/ (ADR 0006).
    var clipFileName: String?

    init(timestamp: Date = .now, detectedBy: DetectionSource, clubName: String, tags: [String] = []) {
        self.timestamp = timestamp
        self.detectedBy = detectedBy
        self.clubName = clubName
        self.tags = tags
    }
}
```

### `Reps/Model/RepsSchema.swift`

```swift
import SwiftData

enum RepsSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [BagClub.self, PracticePlan.self, PlanBlock.self, PracticeSession.self, BlockResult.self, ShotRecord.self]
    }
}

enum RepsMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [RepsSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
```

### `Reps/Persistence/RepsStore.swift`

```swift
import SwiftData

enum RepsStore {
    static let models: [any PersistentModel.Type] = RepsSchemaV1.models

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: RepsSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, migrationPlan: RepsMigrationPlan.self, configurations: [configuration])
    }
}
```

### `RepsTests/RepsStoreTests.swift`

```swift
import SwiftData
import Testing

@testable import Reps

@MainActor
struct RepsStoreTests {
    @Test func inMemoryContainerOpens() throws {
        let container = try RepsStore.makeContainer(inMemory: true)
        #expect(container.configurations.first?.isStoredInMemoryOnly == true)
    }

    @Test func schemaHasEveryModel() throws {
        let container = try RepsStore.makeContainer(inMemory: true)
        let names = Set(container.schema.entities.map(\.name))
        #expect(names == ["BagClub", "PracticePlan", "PlanBlock", "PracticeSession", "BlockResult", "ShotRecord"])
    }

    @Test func schemaIsVersionOne() {
        #expect(RepsSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
        #expect(RepsMigrationPlan.schemas.count == 1)
    }
}
```

### `RepsTests/ModelTests.swift`

```swift
import Foundation
import SwiftData
import Testing

@testable import Reps

@MainActor
struct ModelTests {
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        container = try RepsStore.makeContainer(inMemory: true)
        context = container.mainContext
    }

    private func makePlan() -> PracticePlan {
        let plan = PracticePlan(name: "Wedge day", mode: .rangeCounter)
        context.insert(plan)
        plan.blocks = [
            PlanBlock(clubName: "9 iron", targetReps: 30, order: 1),
            PlanBlock(clubName: "8 iron", targetReps: 40, note: "150m", order: 0),
        ]
        return plan
    }

    private func makeSession(plan: PracticePlan) -> PracticeSession {
        let session = PracticeSession(plan: plan, mode: plan.mode, cameraAngle: .faceOn)
        context.insert(session)
        session.blockResults = plan.sortedBlocks.enumerated().map { BlockResult(block: $1, order: $0) }
        let first = session.sortedBlockResults[0]
        first.shots = [ShotRecord(detectedBy: .manual, clubName: first.clubName, tags: ["fade"])]
        first.repsManualAdjust = 1
        return session
    }

    @Test func sortedBlocksFollowOrderIndex() throws {
        let plan = makePlan()
        try context.save()
        #expect(plan.sortedBlocks.map(\.clubName) == ["8 iron", "9 iron"])
    }

    @Test func blockResultSnapshotsPlanBlock() throws {
        let session = makeSession(plan: makePlan())
        try context.save()
        let results = session.sortedBlockResults
        #expect(results.map(\.clubName) == ["8 iron", "9 iron"])
        #expect(results.map(\.targetReps) == [40, 30])
        #expect(session.planName == "Wedge day")
    }

    @Test func deletingPlanCascadesBlocksAndKeepsHistory() throws {
        let plan = makePlan()
        let session = makeSession(plan: plan)
        try context.save()

        context.delete(plan)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<PracticePlan>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PlanBlock>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PracticeSession>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<BlockResult>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<ShotRecord>()) == 1)
        #expect(session.plan == nil)
        #expect(session.planName == "Wedge day")
        #expect(session.blockResults.allSatisfy { $0.block == nil })
        #expect(session.sortedBlockResults.map(\.targetReps) == [40, 30])
    }

    @Test func deletingPlanBlockKeepsResult() throws {
        let plan = makePlan()
        let session = makeSession(plan: plan)
        try context.save()

        let block = try #require(plan.sortedBlocks.first)
        context.delete(block)
        try context.save()

        #expect(plan.blocks.count == 1)
        #expect(session.blockResults.count == 2)
        #expect(session.sortedBlockResults[0].block == nil)
        #expect(session.sortedBlockResults[0].clubName == "8 iron")
    }

    @Test func deletingSessionCascadesResultsAndShots() throws {
        let plan = makePlan()
        let session = makeSession(plan: plan)
        try context.save()

        context.delete(session)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<PracticeSession>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<BlockResult>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ShotRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PlanBlock>()) == 2)
        #expect(plan.sessions.isEmpty)
    }

    @Test func deletingBagClubLeavesPlansAndShots() throws {
        let club = BagClub(name: "8 iron", sortOrder: 0)
        context.insert(club)
        _ = makeSession(plan: makePlan())
        try context.save()

        context.delete(club)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<PlanBlock>()) == 2)
        let shot = try #require(try context.fetch(FetchDescriptor<ShotRecord>()).first)
        #expect(shot.clubName == "8 iron")
    }

    @Test func enumsAndTagsPersist() throws {
        let session = PracticeSession(plan: nil, mode: .putting, cameraAngle: .none)
        context.insert(session)
        let result = BlockResult(clubName: "Putter", tags: ["gate drill"], order: 0)
        session.blockResults = [result]
        result.shots = [ShotRecord(detectedBy: .camera, clubName: "Putter", tags: ["gate drill", "3ft"])]
        session.status = .finished
        try context.save()

        let fresh = ModelContext(container)
        let fetched = try #require(try fresh.fetch(FetchDescriptor<PracticeSession>()).first)
        #expect(fetched.mode == .putting)
        #expect(fetched.status == .finished)
        #expect(fetched.cameraAngle == .none)
        #expect(fetched.plan == nil)
        #expect(fetched.blockResults.first?.tags == ["gate drill"])
        #expect(fetched.blockResults.first?.targetReps == nil)
        #expect(fetched.blockResults.first?.shots.first?.detectedBy == .camera)
        #expect(fetched.blockResults.first?.shots.first?.tags == ["gate drill", "3ft"])
    }

    @Test func activeSessionsAreFetchableByStatus() throws {
        let active = PracticeSession(plan: nil, mode: .rangeCounter, cameraAngle: .faceOn)
        let done = PracticeSession(plan: nil, mode: .rangeCounter, cameraAngle: .faceOn)
        done.status = .finished
        context.insert(active)
        context.insert(done)
        try context.save()

        let activeRaw = SessionStatus.active
        let descriptor = FetchDescriptor<PracticeSession>(predicate: #Predicate { $0.status == activeRaw })
        #expect(try context.fetch(descriptor).map(\.id) == [active.id])
    }

    @Test func sessionCompletionUsesSnapshots() throws {
        let session = makeSession(plan: makePlan())
        let results = session.sortedBlockResults
        results[0].repsCounted = 39
        results[1].repsCounted = 30
        try context.save()
        #expect(session.completion == 1.0)
    }
}
```

### `Reps/Export/ExportDocument.swift`

```swift
import Foundation

// JSON export shape v1. Property names are the JSON keys; renaming one is a format change.
nonisolated struct ExportDocument: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1

    var formatVersion: Int
    var exportedAt: Date
    var bag: [ExportClub]
    var plans: [ExportPlan]
    var sessions: [ExportSession]
}

nonisolated struct ExportClub: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var sortOrder: Int
    var isInBag: Bool
}

nonisolated struct ExportPlan: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var mode: PracticeMode
    var isOrderMandatory: Bool
    var isStrictCount: Bool
    var createdAt: Date
    var blocks: [ExportPlanBlock]
}

nonisolated struct ExportPlanBlock: Codable, Equatable, Sendable {
    var id: UUID
    var order: Int
    var clubName: String
    var targetReps: Int
    var note: String?
}

nonisolated struct ExportSession: Codable, Equatable, Sendable {
    var id: UUID
    var planId: UUID?
    var planName: String?
    var mode: PracticeMode
    var status: SessionStatus
    var startedAt: Date
    var endedAt: Date?
    var cameraAngle: CameraAngle
    var blocks: [ExportBlockResult]
}

nonisolated struct ExportBlockResult: Codable, Equatable, Sendable {
    var id: UUID
    var order: Int
    var planBlockId: UUID?
    var clubName: String
    var targetReps: Int?
    var tags: [String]
    var repsCounted: Int
    var repsManualAdjust: Int
    var shots: [ExportShot]
}

nonisolated struct ExportShot: Codable, Equatable, Sendable {
    var id: UUID
    var timestamp: Date
    var detectedBy: DetectionSource
    var clubName: String
    var tags: [String]
    var isFavourite: Bool
    var tempoRatio: Double?
    var clipFileName: String?
}
```

### `Reps/Export/RepsExport.swift`

```swift
import Foundation
import SwiftData

enum RepsExport {
    // Finished sessions only; active ones are still being written (ADR 0006).
    static func document(
        clubs: [BagClub],
        plans: [PracticePlan],
        sessions: [PracticeSession],
        exportedAt: Date
    ) -> ExportDocument {
        ExportDocument(
            formatVersion: ExportDocument.currentFormatVersion,
            exportedAt: exportedAt,
            bag: clubs.sorted { $0.sortOrder < $1.sortOrder }.map(club),
            plans: plans.sorted { $0.createdAt < $1.createdAt }.map(plan),
            sessions: sessions.filter { $0.status == .finished }.sorted { $0.startedAt < $1.startedAt }.map(session)
        )
    }

    static func document(from context: ModelContext, exportedAt: Date) throws -> ExportDocument {
        document(
            clubs: try context.fetch(FetchDescriptor<BagClub>()),
            plans: try context.fetch(FetchDescriptor<PracticePlan>()),
            sessions: try context.fetch(FetchDescriptor<PracticeSession>()),
            exportedAt: exportedAt
        )
    }

    private static func club(_ club: BagClub) -> ExportClub {
        ExportClub(id: club.id, name: club.name, sortOrder: club.sortOrder, isInBag: club.isInBag)
    }

    private static func plan(_ plan: PracticePlan) -> ExportPlan {
        ExportPlan(
            id: plan.id,
            name: plan.name,
            mode: plan.mode,
            isOrderMandatory: plan.isOrderMandatory,
            isStrictCount: plan.isStrictCount,
            createdAt: plan.createdAt,
            blocks: plan.sortedBlocks.map {
                ExportPlanBlock(
                    id: $0.id, order: $0.order, clubName: $0.clubName, targetReps: $0.targetReps, note: $0.note)
            }
        )
    }

    private static func session(_ session: PracticeSession) -> ExportSession {
        ExportSession(
            id: session.id,
            planId: session.plan?.id,
            planName: session.planName,
            mode: session.mode,
            status: session.status,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            cameraAngle: session.cameraAngle,
            blocks: session.sortedBlockResults.map(blockResult)
        )
    }

    private static func blockResult(_ result: BlockResult) -> ExportBlockResult {
        ExportBlockResult(
            id: result.id,
            order: result.order,
            planBlockId: result.block?.id,
            clubName: result.clubName,
            targetReps: result.targetReps,
            tags: result.tags,
            repsCounted: result.repsCounted,
            repsManualAdjust: result.repsManualAdjust,
            shots: result.sortedShots.map(shot)
        )
    }

    private static func shot(_ shot: ShotRecord) -> ExportShot {
        ExportShot(
            id: shot.id,
            timestamp: shot.timestamp,
            detectedBy: shot.detectedBy,
            clubName: shot.clubName,
            tags: shot.tags,
            isFavourite: shot.isFavourite,
            tempoRatio: shot.tempoRatio,
            clipFileName: shot.clipFileName.map(bareFileName)
        )
    }

    // Never export a directory or absolute path, only the file name.
    nonisolated static func bareFileName(_ path: String) -> String {
        String(path.split(separator: "/", omittingEmptySubsequences: true).last ?? "")
    }
}

nonisolated enum ExportCoding {
    private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static func encode(_ document: ExportDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(dateStyle))
        }
        return try encoder.encode(document)
    }

    static func decode(_ data: Data) throws -> ExportDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            return try dateStyle.parse(string)
        }
        return try decoder.decode(ExportDocument.self, from: data)
    }
}
```

### `RepsTests/ExportTests.swift`

```swift
import Foundation
import SwiftData
import Testing

@testable import Reps

@MainActor
struct ExportTests {
    // Keep the container alive; a context alone doesn't retain it.
    let container: ModelContainer
    let context: ModelContext
    let t0 = Date(timeIntervalSince1970: 1_790_000_000.25)

    init() throws {
        container = try RepsStore.makeContainer(inMemory: true)
        context = container.mainContext
    }

    // One plan with two blocks, one finished session using it, one active free session.
    private func seed() throws {
        context.insert(BagClub(name: "9 iron", sortOrder: 1))
        context.insert(BagClub(name: "8 iron", sortOrder: 0, isInBag: false))

        let plan = PracticePlan(name: "Wedge day", mode: .rangeCounterWithClips, isStrictCount: true, createdAt: t0)
        context.insert(plan)
        plan.blocks = [
            PlanBlock(clubName: "9 iron", targetReps: 30, order: 1),
            PlanBlock(clubName: "8 iron", targetReps: 40, note: "150m, fade", order: 0),
        ]

        let finished = PracticeSession(plan: plan, mode: plan.mode, cameraAngle: .downTheLine, startedAt: t0)
        context.insert(finished)
        finished.blockResults = plan.sortedBlocks.enumerated().map { BlockResult(block: $1, order: $0) }
        let first = finished.sortedBlockResults[0]
        first.tags = ["fade"]
        first.repsCounted = 1
        first.repsManualAdjust = 1
        let late = ShotRecord(timestamp: t0.addingTimeInterval(20.5), detectedBy: .manual, clubName: "8 iron")
        let early = ShotRecord(
            timestamp: t0.addingTimeInterval(10), detectedBy: .camera, clubName: "8 iron", tags: ["fade"])
        early.clipFileName = "clips/abc/\(early.id.uuidString).mov"
        early.tempoRatio = 3.1
        early.isFavourite = true
        first.shots = [late, early]
        finished.status = .finished
        finished.endedAt = t0.addingTimeInterval(3600)

        let active = PracticeSession(
            plan: nil, mode: .putting, cameraAngle: .none, startedAt: t0.addingTimeInterval(7200))
        context.insert(active)
        try context.save()
    }

    private func json() throws -> [String: Any] {
        try seed()
        let document = try RepsExport.document(from: context, exportedAt: t0)
        let data = try ExportCoding.encode(document)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func topLevelShape() throws {
        let root = try json()
        #expect(Set(root.keys) == ["formatVersion", "exportedAt", "bag", "plans", "sessions"])
        #expect(root["formatVersion"] as? Int == 1)
        #expect(root["exportedAt"] as? String == "2026-09-21T14:13:20.250Z")
    }

    @Test func bagIsSortedBySortOrder() throws {
        let bag = try #require(try json()["bag"] as? [[String: Any]])
        #expect(bag.map { $0["name"] as? String } == ["8 iron", "9 iron"])
        #expect(Set(bag[0].keys) == ["id", "name", "sortOrder", "isInBag"])
        #expect(bag[0]["isInBag"] as? Bool == false)
    }

    @Test func planShape() throws {
        let plans = try #require(try json()["plans"] as? [[String: Any]])
        let plan = try #require(plans.first)
        #expect(
            Set(plan.keys) == ["id", "name", "mode", "isOrderMandatory", "isStrictCount", "createdAt", "blocks"])
        #expect(plan["mode"] as? String == "rangeCounterWithClips")
        #expect(plan["isStrictCount"] as? Bool == true)
        let blocks = try #require(plan["blocks"] as? [[String: Any]])
        #expect(blocks.map { $0["clubName"] as? String } == ["8 iron", "9 iron"])
        #expect(Set(blocks[0].keys) == ["id", "order", "clubName", "targetReps", "note"])
        #expect(Set(blocks[1].keys) == ["id", "order", "clubName", "targetReps"])
    }

    @Test func onlyFinishedSessionsAreExported() throws {
        let sessions = try #require(try json()["sessions"] as? [[String: Any]])
        #expect(sessions.count == 1)
        let session = try #require(sessions.first)
        #expect(session["status"] as? String == "finished")
        #expect(session["cameraAngle"] as? String == "downTheLine")
        #expect(session["planName"] as? String == "Wedge day")
        #expect(session["endedAt"] as? String == "2026-09-21T15:13:20.250Z")
        #expect(
            Set(session.keys) == [
                "id", "planId", "planName", "mode", "status", "startedAt", "endedAt", "cameraAngle", "blocks",
            ])
    }

    @Test func blockResultsAndShots() throws {
        let sessions = try #require(try json()["sessions"] as? [[String: Any]])
        let blocks = try #require(sessions.first?["blocks"] as? [[String: Any]])
        #expect(blocks.map { $0["order"] as? Int } == [0, 1])
        let first = blocks[0]
        #expect(
            Set(first.keys) == [
                "id", "order", "planBlockId", "clubName", "targetReps", "tags", "repsCounted", "repsManualAdjust",
                "shots",
            ])
        #expect(first["targetReps"] as? Int == 40)
        #expect(first["repsManualAdjust"] as? Int == 1)
        let shots = try #require(first["shots"] as? [[String: Any]])
        #expect(shots.map { $0["detectedBy"] as? String } == ["camera", "manual"])
        #expect(shots[0]["timestamp"] as? String == "2026-09-21T14:13:30.250Z")
        #expect(shots[0]["tempoRatio"] as? Double == 3.1)
        #expect(Set(shots[1].keys) == ["id", "timestamp", "detectedBy", "clubName", "tags", "isFavourite"])
    }

    @Test func clipIsReferencedByFileNameOnly() throws {
        let sessions = try #require(try json()["sessions"] as? [[String: Any]])
        let blocks = try #require(sessions.first?["blocks"] as? [[String: Any]])
        let shots = try #require(blocks.first?["shots"] as? [[String: Any]])
        let id = try #require(shots[0]["id"] as? String)
        #expect(shots[0]["clipFileName"] as? String == "\(id).mov")
    }

    @Test func freeSessionHasNoPlanKeys() throws {
        let session = PracticeSession(plan: nil, mode: .putting, cameraAngle: .none, startedAt: t0)
        session.status = .finished
        context.insert(session)
        session.blockResults = [BlockResult(clubName: "Putter", order: 0)]
        try context.save()
        let data = try ExportCoding.encode(try RepsExport.document(from: context, exportedAt: t0))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let exported = try #require((root["sessions"] as? [[String: Any]])?.first)
        #expect(exported["planId"] == nil)
        #expect(exported["planName"] == nil)
        #expect(exported["cameraAngle"] as? String == "none")
        let block = try #require((exported["blocks"] as? [[String: Any]])?.first)
        #expect(block["planBlockId"] == nil)
        #expect(block["targetReps"] == nil)
    }

    @Test func roundTripsAndIsDeterministic() throws {
        try seed()
        let document = try RepsExport.document(from: context, exportedAt: t0)
        let data = try ExportCoding.encode(document)
        #expect(try ExportCoding.decode(data) == document)
        #expect(try ExportCoding.encode(document) == data)
    }

    @Test(arguments: [
        ("abc.mov", "abc.mov"),
        ("clips/s1/abc.mov", "abc.mov"),
        ("/var/mobile/Documents/clips/s1/abc.mov", "abc.mov"),
        ("", ""),
    ])
    func bareFileName(path: String, expected: String) {
        #expect(RepsExport.bareFileName(path) == expected)
    }
}
```

## Appendix B — `docs/adr/0012-data-model-and-export-v1.md`

```markdown
# 0012 — Data model snapshots, VersionedSchema V1, JSON export v1

- Status: Accepted (extends 0004, 0006)
- Date: 2026-09-27

## Context
Spec §5.1 sketches six SwiftData models; §10 wants plans and sessions exportable as JSON without changes. Plans get edited and deleted while their session history must stay readable, and real sessions get logged from Phase 1 on.

## Decision
- Every model has a `UUID` `id`. Blocks and block results carry an explicit `order`; relationship arrays are never read in stored order.
- Delete rules: plan → blocks cascade; plan → sessions nullify; plan block → results nullify; session → results → shots cascade. BagClub has no relationships; everything references clubs by name.
- History is snapshotted: `PracticeSession.planName` and `mode`, `BlockResult.clubName`, `targetReps` (nil in free sessions) and `tags`, `ShotRecord.clubName`.
- Completion is pure (`Completion`): block = max(0, counted + manualAdjust) / target, uncapped; session = total done / total target over targeted blocks; nil without a target.
- Schema is `RepsSchemaV1` (1.0.0) with `RepsMigrationPlan` from day one. Before V2, the V1 classes are copied unchanged into `RepsSchemaV1` as nested types.
- Export format v1: `ExportDocument` with `formatVersion`, `exportedAt`, `bag`, `plans`, finished `sessions` (nested blocks and shots). Keys are the Swift property names, ISO 8601 UTC dates with milliseconds, sorted keys, nil fields omitted, enums as raw strings, clips as bare `<shotId>.mov`, no derived values. Encoding returns `Data` only.

## Consequences
Editing or deleting plans and clubs never changes history or old exports. Any change to an `Export*` property name or enum raw value is a format change and bumps `formatVersion`. Writing or sharing the export is a separate, security-reviewed feature.
```

## Appendix C — `docs/code-reference.md` entries

Replace the `Reps/Persistence/RepsStore.swift` entry with:

```markdown
## Reps/Persistence/RepsStore.swift
Builds the SwiftData container for the app and tests.
- `RepsStore.models`: the `@Model` types (`RepsSchemaV1.models`)
- `RepsStore.makeContainer(inMemory:) throws -> ModelContainer`: container over `RepsSchemaV1` with `RepsMigrationPlan`; `inMemory: true` for tests
```

Add after `Reps/App/RootView.swift`:

```markdown
## Reps/Model/ModelEnums.swift
Stored and exported enums; raw values are frozen (ADR 0012).
- `PracticeMode`: rangeCounter, rangeCounterWithClips, putting
- `CameraAngle`: faceOn, downTheLine, none (putting)
- `DetectionSource`: camera, manual
- `SessionStatus`: active, finished (ADR 0006)

## Reps/Model/Completion.swift
Pure completion math (spec §5.1, F21), nonisolated.
- `BlockTally(counted:manualAdjust:target:)`: `done` = max(0, counted + manualAdjust); `target` nil = free block
- `Completion.block(_:) -> Double?`: done / target, uncapped; nil without a positive target
- `Completion.isComplete(_:) -> Bool`: done ≥ target
- `Completion.session(_:) -> Double?`: total done / total target over targeted blocks; nil if none

## Reps/Model/BagClub.swift
- `BagClub(name:sortOrder:isInBag:)`: one club in the user's bag; `isInBag` false hides it from pickers. No relationships.

## Reps/Model/PracticePlan.swift
- `PracticePlan(name:mode:isOrderMandatory:isStrictCount:createdAt:)`: reusable plan; `blocks` cascade, `sessions` nullify
- `sortedBlocks`: blocks by `order`

## Reps/Model/PlanBlock.swift
- `PlanBlock(clubName:targetReps:note:order:)`: one block of a plan; `results` nullify on delete

## Reps/Model/PracticeSession.swift
- `PracticeSession(plan:mode:cameraAngle:startedAt:)`: one run (plan nil = free session); copies `planName`; `status` starts `.active`; `blockResults` cascade
- `sortedBlockResults`: by `order`; `completion`: `Completion.session` over the results

## Reps/Model/BlockResult.swift
- `BlockResult(block:order:)`: result for a plan block; copies `clubName` and `targetReps`
- `BlockResult(clubName:tags:order:)`: free-session block, no target
- `tally`: `BlockTally` for completion; `sortedShots`: by `timestamp`; `shots` cascade

## Reps/Model/ShotRecord.swift
- `ShotRecord(timestamp:detectedBy:clubName:tags:)`: one counted shot; `clipFileName` is the bare `<id>.mov` in `Documents/clips/<sessionId>/` (ADR 0006)

## Reps/Model/RepsSchema.swift
- `RepsSchemaV1`: VersionedSchema 1.0.0 with the six models
- `RepsMigrationPlan`: schemas `[RepsSchemaV1]`, no stages yet

## Reps/Export/ExportDocument.swift
JSON export format v1 (ADR 0012); property names are the JSON keys.
- `ExportDocument`: `formatVersion`, `exportedAt`, `bag`, `plans`, `sessions`; `currentFormatVersion` = 1
- `ExportClub`, `ExportPlan`, `ExportPlanBlock`, `ExportSession`, `ExportBlockResult`, `ExportShot`: raw stored fields, ids for cross references

## Reps/Export/RepsExport.swift
- `RepsExport.document(clubs:plans:sessions:exportedAt:) -> ExportDocument`: sorted snapshot; finished sessions only
- `RepsExport.document(from:exportedAt:) throws -> ExportDocument`: fetches everything from a context
- `RepsExport.bareFileName(_:) -> String`: last path component
- `ExportCoding.encode(_:) throws -> Data`: pretty, sorted keys, ISO 8601 UTC with ms; no file I/O
- `ExportCoding.decode(_:) throws -> ExportDocument`: inverse of `encode`
```

Replace the `RepsTests/RepsStoreTests.swift` entry and add after it:

```markdown
## RepsTests/RepsStoreTests.swift
- `inMemoryContainerOpens`, `schemaHasEveryModel`, `schemaIsVersionOne`

## RepsTests/CompletionTests.swift
Block and session completion: uncapped, manual adjust, clamping, missing targets, skipped blocks.

## RepsTests/ModelTests.swift
In-memory store: order indexes, snapshots, delete rules, enum/tag persistence, status predicate.

## RepsTests/ExportTests.swift
Export key sets, ordering, finished-only, nil omission, ISO dates, clip file names, round trip, determinism.
```

## Appendix D — `docs/open-questions.md` rows

```markdown
| Q21 | Does −1 delete the latest ShotRecord (and its clip) or only decrement `repsManualAdjust`? | #8 | Model supports both. Leaning: only decrement; the shot list stays what the camera/taps produced. |
| Q22 | Session completion: may surplus on one block cover a shortfall on another (45/30 + 15/30 = 100 %)? | #11 | Spec §5.1 literal says yes (total done / total target), implemented that way in #4. Alternative: cap each block at its target for the session number. |
```
