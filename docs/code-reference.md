# Code reference

The documentation for files and functions. Code comments stay short, and the detail lives here. Update this file in the same commit as the code.

Format:

```
## path/to/File.swift
Purpose in one line.
- `TypeOrFunction(signature)`: what it does / returns, notable side effects
```

## Reps/App/RepsApp.swift
App entry point; opens the SwiftData store and shows the root view.
- `RepsApp`: `@main` app; builds the container with `RepsStore.makeContainer()` (fatal on failure until #29) and attaches it with `.modelContainer(_:)`

## Reps/App/RootView.swift
Placeholder root screen until the plans list (#7) replaces it.
- `RootView`: shows the app name

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

## Reps/Persistence/RepsStore.swift
Builds the SwiftData container for the app and tests.
- `RepsStore.models`: the `@Model` types (`RepsSchemaV1.models`)
- `RepsStore.makeContainer(inMemory:) throws -> ModelContainer`: container over `RepsSchemaV1` with `RepsMigrationPlan`; `inMemory: true` for tests

## ShotDetector/ShotEvent.swift
Output type of the ShotDetector framework (spec §4). The framework must never import AVFoundation, AVKit, UIKit, SwiftUI or CoreMedia (ADR 0010).
- `ShotEvent(time:)`: one detected shot; `time` is the detector's estimate of when it happened (impact or ball exit), in seconds on the frame stream's clock

## ShotDetector/ShotDetecting.swift
The detector boundary (spec §4, ADR 0010).
- `ShotDetecting`: `mutating process(_:) -> [ShotEvent]` takes frames in time order and returns shots confirmed on that frame; `mutating finish() -> [ShotEvent]` flushes at end of stream (default `[]`)

## ShotDetector/VideoFrame.swift
What detectors are fed.
- `VideoFrame(pixelBuffer:time:orientation:)`: one downscaled frame; `time` in seconds (presentation time), `orientation` for Vision
- `DetectorInput`: the frame contract for the camera pipeline and the eval harness: `frameRate` 15, `shortSide` 480, `pixelFormat` 420f

## RepsTests/RepsStoreTests.swift
- `inMemoryContainerOpens`, `schemaHasEveryModel`, `schemaIsVersionOne`

## RepsTests/CompletionTests.swift
Block and session completion: uncapped, manual adjust, clamping, missing targets, skipped blocks.

## RepsTests/ModelTests.swift
In-memory store: order indexes, snapshots, delete rules, enum/tag persistence, status predicate.

## RepsTests/ExportTests.swift
Export key sets, ordering, finished-only, nil omission, ISO dates, clip file names, round trip, determinism.

## DetectorEvalTests/MLData.swift
Locates the hitreg-ml checkout (ADR 0007).
- `MLData.root: URL?`: `REPS_ML_DIR` if set, else `<repo>/../hitreg-ml`; `nil` when `data/manifest.csv` isn't there (suites skip)

## DetectorEvalTests/MLDataTests.swift
- `MLDataTests.testSplitIsListed`: `data/splits.json` has a non-empty `test` split; skipped without footage

## DetectorEvalTests/Harness/CSV.swift
- `CSV.parse(_:) -> [[String]]`: RFC 4180 rows (quotes, `""`, CRLF)
- `CSV.records(_:) -> [[String: String]]`: rows keyed by the header; blank lines dropped, missing fields `""`

## DetectorEvalTests/Harness/EvalLabel.swift
Ground-truth kinds and how each detector type should treat them.
- `LabelKind`: swing, practice, motion (range); putt, pickup, motion (putting)
- `EvalLabel(frame:seconds:kind:)`: one CSV row
- `ScoringProfile`: kind → `LabelRole` (positive/negative); `.rangeShot` (practice negative), `.rangeSwing` (practice positive), `.putting` (pickup positive)

## DetectorEvalTests/Harness/EventMatcher.swift
- `Detection(time:emittedAt:)`: an event's estimated time and the frame time it was returned on
- `TimedLabel(time:kind:)`: a label on the decoder's clock
- `VideoScore`: per-video counts, latencies, timing errors, per-kind labels/fired
- `EventMatcher.score(labels:detections:profile:window:) -> VideoScore`: one-to-one matching within ±window; unmatched detections are hard (near a negative label) or other false positives

## DetectorEvalTests/Harness/EvalMetrics.swift
- `EvalMetrics(_ scores:)`: sums video scores; `precision`, `recall`, `falsePer50`, `meanLatency`, `maxLatency`, `meanAbsTimingError` are nil when undefined; `absCountError` sums per-video |detections − positives|

## DetectorEvalTests/Harness/EvalDataset.swift
- `EvalVideo`: name, file URL, scenario (`angle/light` or `putt/light`), labels
- `EvalDataset.rangeTest(root:profile:)`: hitreg-ml test split (skips `discard` rows); throws on missing files or bad rows
- `EvalDataset.putting(root:)`: every clip in `data/putting/manifest.csv`
- `EvalDataset.hasPutting(root:)`, `EvalDataset.labels(_:)`

## DetectorEvalTests/Harness/VideoFrameReader.swift
The only AVFoundation code on the detector path; test target only.
- `VideoFrameReader(url:frameRate:shortSide:)`: defaults from `DetectorInput`; `nil` = every frame / native size
- `read(_ body:) async throws -> [Double]`: calls `body` per sampled frame; returns the PTS of every decoded frame by index
- `orientation(from:)`: preferredTransform → `CGImagePropertyOrientation` (same as hitreg-ml `tools/extract`)
- `scaledSize(_:shortSide:)`: even output size with the short side at `shortSide`, nil if already smaller

## DetectorEvalTests/Harness/EvalRunner.swift
- `EvalRunner(window:frameRate:shortSide:)`: window defaults to 0.5 s
- `run(_ name:on:makeDetector:) async throws -> EvalReport`: decodes each video, feeds a fresh detector, moves labels onto the decoder clock by frame number, scores; throws `RunError.nonIncreasingFrameTimes` if a video's frame times aren't strictly increasing
- `labelTimes(_:frameTimes:) -> [Double]`: pure frame-number → timestamp mapping, CSV seconds past the end
- `isStrictlyIncreasing(_:) -> Bool`: guards the frame-time mapping is valid
- `VideoResult`: one video's score plus decoded/sampled frame counts

## DetectorEvalTests/Harness/EvalReport.swift
- `EvalReport.scenarios`: metrics per scenario (sorted) then `all`; `overall`
- `table`: fixed-width text report with per-kind fired/labels and miscounted videos
- `json`: pretty, sorted-keys JSON of the same

## DetectorEvalTests/Harness/EvalOutput.swift
- `EvalOutput.publish(_:)`: prints the table, attaches `.txt`/`.json` to the test, writes them to `build/eval/<name>.*`

## DetectorEvalTests/Detectors/LabelOracle.swift
- `LabelOracle(video:profile:)`: test-only `ShotDetecting` that fires on the first sampled frame at/after each positive label

## DetectorEvalTests/CSVTests.swift, EventMatcherTests.swift, EvalMetricsTests.swift, EvalRunnerTests.swift
Pure harness logic, no footage.

## DetectorEvalTests/EvalDatasetTests.swift
- Label parsing (pure); `rangeTestSplitLoads` (22 videos), `puttingLoads` (footage)

## DetectorEvalTests/VideoFrameReaderTests.swift
- Scaling and orientation math (pure); `decodesDownscaledSampledFrames` (footage: 480 short side, 420f, ~15 fps)

## DetectorEvalTests/OracleEvalTests.swift
- `rangeTestSplit`, `putting`: the oracle scores recall 1, precision 1 and publishes `oracle-range` / `oracle-putting` reports
