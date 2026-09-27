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

## Reps/Persistence/RepsStore.swift
Builds the SwiftData container for the app and tests.
- `RepsStore.models`: the `@Model` types in the schema (empty until #4)
- `RepsStore.makeContainer(inMemory:) throws -> ModelContainer`: container over `models`; `inMemory: true` for tests

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
- `RepsStoreTests.inMemoryContainerOpens`: the schema opens in an in-memory container

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
- `run(_ name:on:makeDetector:) async throws -> EvalReport`: decodes each video, feeds a fresh detector, moves labels onto the decoder clock by frame number, scores
- `VideoResult`: one video's score plus decoded/sampled frame counts

## DetectorEvalTests/Harness/EvalReport.swift
- `EvalReport.scenarios`: metrics per scenario (sorted) then `all`; `overall`
- `table`: fixed-width text report with per-kind fired/labels and miscounted videos
- `json`: pretty, sorted-keys JSON of the same

## DetectorEvalTests/Harness/EvalOutput.swift
- `EvalOutput.publish(_:)`: prints the table, attaches `.txt`/`.json` to the test, writes them to `build/eval/<name>.*`

## DetectorEvalTests/Detectors/LabelOracle.swift
- `LabelOracle(video:profile:)`: test-only `ShotDetecting` that fires on the first sampled frame at/after each positive label

## DetectorEvalTests/CSVTests.swift, EventMatcherTests.swift, EvalMetricsTests.swift
Pure harness logic, no footage.

## DetectorEvalTests/EvalDatasetTests.swift
- Label parsing (pure); `rangeTestSplitLoads` (22 videos), `puttingLoads` (footage)

## DetectorEvalTests/VideoFrameReaderTests.swift
- Scaling and orientation math (pure); `decodesDownscaledSampledFrames` (footage: 480 short side, 420f, ~15 fps)

## DetectorEvalTests/OracleEvalTests.swift
- `rangeTestSplit`, `putting`: the oracle scores recall 1, precision 1 and publishes `oracle-range` / `oracle-putting` reports
