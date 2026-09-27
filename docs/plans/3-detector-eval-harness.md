# #3 Detector evaluation harness

Goal: a DetectorEval harness that decodes hitreg-ml footage (range **test** split and the putting clips), feeds downscaled frames into any `ShotDetecting` detector, matches its events to the label CSVs, and reports precision/recall/count error/latency per angle×light scenario. A label-replaying oracle proves it end to end until real detectors land (#14, #16, #17–#19).

Spec: §4 (design rule), §5.2/§5.4/§5.5 (what detectors emit), §5.6 (15 fps, ~480 px), §7 (precision/recall per scenario), §2 NFR (≥95 % recall, ≤1 false per 50, <1.5 s). ADRs: 0002, 0007, 0008, 0009.

Every file in Appendix A was built and run by the planner in a scratch copy of the repo with Xcode 27.0 (27A5252f) on the iPhone 17 Pro simulator: full `DetectorEval` plan passed (36 tests, ~18 s of test time, ~36 s wall clock including build), skip path passed, the filtered pure suites passed in < 0.1 s, app built for simulator and `generic/platform=iOS`, `swift-format lint --strict` clean, boundary grep clean. **Copy the file contents exactly.** Don't open the project in the Xcode GUI.

Out of scope (belongs to later issues): any real detector (#14, #16, #17, #19), accuracy thresholds as pass/fail gates (#21), the camera pipeline (#13), per-video ball regions for footage (new Q18).

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Test framework | Swift Testing, as in #1 (the issue says "XCTest target"; that's the DetectorEval test *target*, not the framework). | `.enabled(if:)` skip, parameterized args, `Attachment.record` all verified. |
| Detector protocol | `public protocol ShotDetecting { mutating func process(_ frame: VideoFrame) -> [ShotEvent]; mutating func finish() -> [ShotEvent] }` in ShotDetector, `finish()` defaults to `[]`. Synchronous, value-type friendly, no Sendable requirement. | Detectors are state machines fed in frame order; sync keeps them deterministic and trivially drivable from a file or a capture queue. A protocol named `ShotDetector` would clash with the module name. |
| Frame type | `public struct VideoFrame { pixelBuffer: CVPixelBuffer; time: Double; orientation: CGImagePropertyOrientation }`. `time` = seconds on the stream clock (presentation time). `orientation` is what Vision needs (`VNImageRequestHandler(cvPixelBuffer:orientation:)`). | CVPixelBuffer is what both AVCaptureVideoDataOutput and AVAssetReader produce and what Vision/Core ML consume. Double seconds matches `ShotEvent.time`. |
| Allowed imports in ShotDetector | Allowed: Foundation, CoreVideo, ImageIO, CoreGraphics, Accelerate, CoreImage, Vision, CoreML. **Forbidden: AVFoundation, AVKit, UIKit, SwiftUI, CoreMedia.** New grep: `grep -rnE 'import (AVFoundation\|AVKit\|UIKit\|SwiftUI\|CoreMedia)' ShotDetector` must print nothing. | CoreMedia is added so `CMSampleBuffer`/`CMTime` never leak into the detector API; timestamps stay Double. Recorded in ADR 0010 (0009 is not edited; ADRs are immutable). |
| Frame contract | `DetectorInput.frameRate = 15`, `DetectorInput.shortSide = 480`, `DetectorInput.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange` (public, in ShotDetector). The camera pipeline (#13) must deliver the same. | Spec §5.6 (every 4th of 60 fps ≈ 15 fps, ~480 px). 420f is the camera's native format and gives a luma plane for NCC (#14) for free. "~480 px wide" is read as the *short* side, so portrait range and landscape putting footage get the same detail. |
| Decoding | `AVAssetReaderTrackOutput` with `kCVPixelBufferWidthKey/HeightKey` scaling and `copyNextSampleBuffer()`, in DetectorEvalTests only. Orientation from `preferredTransform`, same mapping as hitreg-ml's `tools/extract` (keeps pose coordinates compatible, ADR 0007). The new `outputProvider(for:)` async API was considered and not used: the sync loop is proven (hitreg-ml extractor) and simpler. | Decoder-side scaling halves decode time (measured 7.1 s → 3.5 s for an 83 s 1080p clip). |
| Frame sampling | Time-based: emit a frame when `pts + 1 ms ≥ nextDue`; first frame always; `nextDue = first ? pts + 1/15 : max(nextDue + 1/15, pts + 1/30)`. `frameRate: nil` = every frame. | Works for 30, 29.97, 59.94 and 48 fps footage (every 2nd / every 4th frame). Verified gaps are all 67 ms on 59.94 fps footage. |
| Label clock | Every decoded frame's PTS is recorded; a label's time = PTS of frame `label.frame`, falling back to `label.seconds` past the end. | hitreg-ml writes `seconds = frame / avg_fps`; on VFR clips (the putting clip) that drifts ~20 ms from the real PTS. Frame index is exact. |
| Event times | `ShotEvent.time` = the detector's estimate of when the shot happened (impact for pose, ball exit for ball presence). The harness also records `emittedAt` = time of the frame on which `process` returned it (last frame's time for `finish()`). | Matching uses `time`; latency uses `emittedAt`. A detector that confirms late (putting waits ≥ 300 ms) still matches if its estimate is right, and the delay shows up as latency. |
| Label roles | `ScoringProfile` maps kind → positive/negative. `rangeShot` (default for range): swing +, practice −, motion −. `rangeSwing` (for pose-only #17/#18): swing +, practice +, motion −. `putting`: putt +, pickup +, motion −. Unknown kinds default to negative; unknown kinds in a CSV throw. | ADR 0002/spec §5.4: the ball gate means practice swings must not count. ADR 0007: the classifier treats practice as swing. ADR 0008: a pickup is *expected* to count. |
| Matching | Window ±0.5 s inclusive (spec §5.4), one-to-one. Positive labels in time order each claim the earliest unclaimed detection within the window (maximum-cardinality for equal windows; nearest-pair-first is not). Unclaimed detections are false positives: "hard" if a negative label lies within the window (attributed to the nearest), else "other". A negative label counts as *fired* if any unclaimed detection was attributed to it. | Double counts become FPs; one event can't satisfy two labels; hard-negative FPs are split out because they're what the ball gate is supposed to kill. |
| Metrics | Summed over videos, then divided (micro average). precision = TP/detections (nil if 0 detections), recall = TP/positives (nil if 0), FP/50 = FP×50/positives, `absCountError` = Σ per-video abs(detections − positives), latency mean/max of `emittedAt − label`, mean abs(time − label), per-kind fired/labels. nil prints as `-`, never NaN. | Maps 1:1 onto the §2 NFR numbers #21 will gate on. |
| Scenarios | `angle/light` from `data/manifest.csv` (e.g. `dtl/sun`); putting = `putt/<light>`. Each report is one dataset: rows per scenario, sorted, then `all`. | §7 "per scenario". Putting has no angle and is its own dataset. |
| Datasets | `EvalDataset.rangeTest(root:profile:)` = `splits.json["test"]` (22 videos), rows whose manifest `notes` contain `discard` skipped. `EvalDataset.putting(root:)` = every row of `data/putting/manifest.csv` (1 clip now). | ADR 0007 (test split only). Putting has no split yet; #16 tunes on it knowingly. |
| Report output | Printed table (shows in xcodebuild output), `Attachment.record` of `.txt` and `.json` (in the .xcresult), and files `build/eval/<name>.txt` and `.json` in the repo (gitignored `build/`), overwritten each run. | Terminal for a quick look, JSON for diffing detector versions. |
| Where harness code lives | All in `DetectorEvalTests/` (`Harness/`, `Detectors/`), not in ShotDetector. Pure suites (CSV, matcher, metrics, reader math, label parsing) run in the DetectorEval plan without footage via `-only-testing`. | Eval code must not ship in the app. The DetectorEval target has no app host, so its pure tests are as fast as Unit. |
| Baseline | `LabelOracle`: test-only `ShotDetecting` that emits `ShotEvent(time: frame.time)` on the first sampled frame at/after each positive label. Must score recall 1, precision 1, max latency ≤ 2/15 s on both datasets. No never-fires detector: its behaviour is covered by `EventMatcherTests.noDetections`. | Proves decode → timestamps → label clock → matching → report on real footage. |
| Runtime | Measured on the scratch copy: range oracle 16.4 s (22 videos, 255 s of video), putting oracle 14.3 s (312 s), in parallel → ~18 s test time. Decode ≈ 20–25× realtime at 480 px. | Real detectors add their per-frame cost on top (~3.8 k frames range, ~4.7 k putting at 15 fps). |

## Final layout

```
ShotDetector/
  ShotEvent.swift                 (unchanged)
  ShotDetecting.swift             new: detector protocol
  VideoFrame.swift                new: VideoFrame, DetectorInput
DetectorEvalTests/
  MLData.swift, MLDataTests.swift (unchanged)
  Harness/CSV.swift               new
  Harness/EvalLabel.swift         new: LabelKind, EvalLabel, LabelRole, ScoringProfile
  Harness/EventMatcher.swift      new: Detection, TimedLabel, VideoScore, EventMatcher
  Harness/EvalMetrics.swift       new
  Harness/EvalDataset.swift       new: EvalVideo, EvalDataset
  Harness/VideoFrameReader.swift  new (the only AVFoundation user)
  Harness/EvalRunner.swift        new: VideoResult, EvalRunner
  Harness/EvalReport.swift        new: EvalReport (+ private ReportJSON)
  Harness/EvalOutput.swift        new
  Detectors/LabelOracle.swift     new
  CSVTests.swift, EventMatcherTests.swift, EvalMetricsTests.swift,
  EvalDatasetTests.swift, VideoFrameReaderTests.swift, OracleEvalTests.swift   new
docs/adr/0010-detector-frame-contract-and-eval.md   new
```

No pbxproj or test plan changes: synced folders pick up the subfolders (verified).

## Steps

Branch `feat/3-detector-eval-harness` (already checked out). Run everything from the repo root. `DEST='platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'`. After creating files in each step, run `xcrun swift-format lint --strict --recursive --parallel ShotDetector DetectorEvalTests` (must print nothing). Every commit body is `Refs #3`.

Steps 2–6 are TDD (CLAUDE.md): create the **test file first**, run the filtered command and see it fail (compile error: the type doesn't exist yet), then create the implementation file(s), run again and see it pass, then commit both.

Shorthand used below:

```sh
EVAL='xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan DetectorEval -destination "$DEST"'
```
(Write the full command out; the shorthand is just for reading.)

### Step 1 — detector frame contract

1. Create `ShotDetector/VideoFrame.swift` and `ShotDetector/ShotDetecting.swift` (Appendix A).
2. Verify:
   ```sh
   xcodebuild build -project Reps.xcodeproj -scheme Reps -destination "$DEST" -quiet
   grep -rnE 'import (AVFoundation|AVKit|UIKit|SwiftUI|CoreMedia)' ShotDetector   # prints nothing
   ```
3. Commit: `added detector frame contract`.

### Step 2 — CSV reader (TDD)

1. `DetectorEvalTests/CSVTests.swift`, then `DetectorEvalTests/Harness/CSV.swift`.
2. `$EVAL -only-testing:DetectorEvalTests/CSVTests` → 5 tests pass.
3. Commit: `added csv reader for eval labels`.

### Step 3 — labels and matcher (TDD)

1. `DetectorEvalTests/EventMatcherTests.swift`, then `Harness/EvalLabel.swift` and `Harness/EventMatcher.swift`.
2. `$EVAL -only-testing:DetectorEvalTests/EventMatcherTests` → 14 tests pass.
3. Commit: `added eval event matcher`.

### Step 4 — metrics (TDD)

1. `DetectorEvalTests/EvalMetricsTests.swift`, then `Harness/EvalMetrics.swift`.
2. `$EVAL -only-testing:DetectorEvalTests/EvalMetricsTests` → 6 tests pass.
3. Commit: `added eval metrics`.

### Step 5 — datasets (TDD)

1. `DetectorEvalTests/EvalDatasetTests.swift`, then `Harness/EvalDataset.swift`.
2. `$EVAL -only-testing:DetectorEvalTests/EvalDatasetTests` → 4 tests pass (the two footage tests run because hitreg-ml is a sibling checkout; `rangeTestSplitLoads` expects exactly 22 videos).
3. Commit: `added hitreg-ml dataset loader`.

### Step 6 — video frame reader (TDD)

1. `DetectorEvalTests/VideoFrameReaderTests.swift`, then `Harness/VideoFrameReader.swift`.
2. `$EVAL -only-testing:DetectorEvalTests/VideoFrameReaderTests` → 4 tests pass (one parameterized with 3 cases). The log contains repeated `unrecognised property key` lines from the simulator's decoder; that's noise, ignore it.
3. Commit: `added video frame reader for eval`.

### Step 7 — runner, report, oracle

1. Create `Harness/EvalRunner.swift`, `Harness/EvalReport.swift`, `Harness/EvalOutput.swift`, `Detectors/LabelOracle.swift`, `OracleEvalTests.swift`.
2. Run the whole plan: `$EVAL` → `** TEST SUCCEEDED **`, 36 tests in 7 suites. The output contains two tables (`DetectorEval oracle-range on range-test (rangeShot) …` and `DetectorEval oracle-putting on putting (putting) …`) with `recall 1.00`, `prec 1.00`, `FP 0` on every row, and `fired/labels: swing 23/23  practice 0/16  motion 0/7` / `motion 0/15  putt 19/19  pickup 3/3` (numbers as of 2026-09-27; they change only if hitreg-ml data changes).
3. `ls build/eval` shows `oracle-range.txt`, `oracle-range.json`, `oracle-putting.txt`, `oracle-putting.json`. `git status` must not list them (ignored by `build/`).
   - If the first run stalls on a macOS privacy prompt (writing under `~/Documents`), allow it, as in #1.
4. Skip path: `TEST_RUNNER_REPS_ML_DIR=/nonexistent $EVAL` → `** TEST SUCCEEDED **`; `OracleEvalTests` and `MLDataTests` suites skipped, `rangeTestSplitLoads`, `puttingLoads`, `decodesDownscaledSampledFrames` skipped; pure tests pass.
5. Commit: `added detector eval runner and oracle baseline`.

### Step 8 — docs

1. **docs/code-reference.md**: update the `ShotDetector/ShotEvent.swift` entry and append the entries in **Appendix B**.
2. **CLAUDE.md** (Testing section): in the code block, after the `# DetectorEval …` command, add:
   ```sh
   # DetectorEval harness logic only (no footage, < 1 s)
   xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan DetectorEval -destination "$DEST" -only-testing:DetectorEvalTests/CSVTests -only-testing:DetectorEvalTests/EventMatcherTests -only-testing:DetectorEvalTests/EvalMetricsTests
   # one detector's eval suite, e.g. the oracle
   xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan DetectorEval -destination "$DEST" -only-testing:DetectorEvalTests/OracleEvalTests
   ```
   and after the `- Env vars reach simulator tests …` bullet add:
   ```markdown
   - Eval reports land in `build/eval/<name>.txt` and `.json` (latest run, gitignored) and are attached to the test in the .xcresult. A new detector gets its own `<Name>EvalTests` suite that calls `EvalRunner().run(…)` and `EvalOutput.publish(_:)`.
   ```
   In "Code style", replace the line that starts ``- `ShotDetector` and everything under it stays free of AVFoundation`` with:
   ```markdown
   - `ShotDetector` and everything under it stays free of AVFoundation so it runs against video files in tests (spec §4). Detectors take `VideoFrame`s through `ShotDetecting` (ADR 0010). Check: `grep -rnE 'import (AVFoundation|AVKit|UIKit|SwiftUI|CoreMedia)' ShotDetector` prints nothing.
   ```
3. **docs/adr/0010-detector-frame-contract-and-eval.md**: create with **Appendix C**; add to `docs/adr/README.md` after 0009:
   `| [0010](0010-detector-frame-contract-and-eval.md) | Detectors take VideoFrames via ShotDetecting; eval matching and metrics | Accepted |`
4. **docs/open-questions.md**: add to the Open table the two rows in **Appendix D**.
5. **docs/roadmap.md**: #3 status `☐` → `☑` (do this in the final commit before the PR, when the issue is about to close).
6. Commit: `documented detector eval harness`.

Then push and open the PR (CLAUDE.md): title `added detector eval harness`, body `frame contract, footage decoder, matcher and metrics, oracle baseline` plus `Closes #3`. Review label is `review:opus`: run `opus-reviewer` before the PR.

## Tests

All in the `DetectorEval` plan (target `DetectorEvalTests`); nothing in `Unit` (no app code changed).

- Pure, no footage (always run):
  - `CSVTests` (5): quoted comma field, `""` escape, CRLF + no trailing newline, empty trailing field + blank lines, short row.
  - `EventMatcherTests` (14): hit inside window with latency/timing error, inclusive window edges, outside window = FN + other FP, double count = 1 FP, one detection can't serve two labels, maximum matching beats nearest-first, unsorted input, practice is hard negative for `rangeShot`, practice positive for `rangeSwing`, motion negative in all profiles, pickup counts in putting, positive wins over a nearby negative, two detections on one negative = 2 FPs / 1 fired, no detections.
  - `EvalMetricsTests` (6): micro average, nil rates, FP/50, per-video count error magnitude, latency/timing means and max, per-kind merge.
  - `EvalDatasetTests.parsesLabelRows`, `.unknownKindThrows`.
  - `VideoFrameReaderTests.scaledSizeKeepsAspectWithEvenSides` (3 args), `.smallVideoIsNotScaled`, `.orientationFollowsRotation`.
- Footage (skip without hitreg-ml):
  - `EvalDatasetTests.rangeTestSplitLoads` (22 videos, each has a swing, angle is dtl/faceon), `.puttingLoads`.
  - `VideoFrameReaderTests.decodesDownscaledSampledFrames`: 332 decoded frames, increasing PTS, ~83 sampled, short side 480, 420f, every gap 50–90 ms.
  - `OracleEvalTests.rangeTestSplit`, `.putting`: recall 1, precision 1, no hard FPs, max latency ≤ 2/15 s; publishes reports.
  - `MLDataTests` unchanged.

## Risks / unresolved

- **Ball region for footage (Q18).** The ball presence detector (§5.2) needs the user's tap. The harness passes each `EvalVideo` to the `makeDetector` factory, so #14/#16 can load a per-video region from wherever Q18 decides; nothing here blocks that, but #14 can't be scored until it's answered. (Superseded: detectors auto-locate the ball, see ADR 0011.)
- **Small range test set (Q19).** 23 swings, 16 practice, 7 motion in 22 videos. One miss = −4 % recall; "≤1 false per 50" can't be judged on 23 positives. #21 has to decide what set it gates on.
- **Frame contract binds #13.** `DetectorInput` (15 fps, short side 480, 420f) is now what the camera pipeline must deliver. If #13 finds a reason to change it, change the constants in one place and re-run DetectorEval.
- **Orientation.** Range clips here are stored upright (orientation `.up`); rotated clips get `.right/.left/.down` exactly like hitreg-ml's extractor. The pixel buffer is *not* rotated, the detector gets the orientation. Ball-patch code (#14) must use the same convention as the live camera buffers (#13).
- **`VideoFrame` is not `Sendable`** (CVPixelBuffer). Fine for the synchronous harness; #13 may need `@unchecked Sendable` or to keep detection on one queue. Left for #13.
- **Pickup scoring.** `putting` treats pickup as positive (ADR 0008 says it counts). The report shows `pickup n/3` separately so #16 can see it; if the owner later wants pickups to count against the detector, switch that role to negative.
- **Simulator decode noise.** `unrecognised property key` and one `FigExportCommmon … err=-12785` line per video in the log; harmless (seen with and without scaling).
- **Runtime grows with real detectors.** Vision pose on the simulator is CPU-bound; expect minutes, not seconds, for #17–#19 over ~3.8 k frames. `EvalRunner` runs videos sequentially; parallelising (TaskGroup, one detector per task) is a later option if needed.
- **TCC**: the first write to `build/eval` under `~/Documents` may trigger a one-off privacy prompt.

---

## Appendix A — files

### `ShotDetector/VideoFrame.swift`

```swift
import CoreVideo
import ImageIO

// One downscaled frame handed to a detector. Built by the camera pipeline or, in tests, by a video file reader.
public struct VideoFrame {
    public var pixelBuffer: CVPixelBuffer
    public var time: Double
    public var orientation: CGImagePropertyOrientation

    public init(pixelBuffer: CVPixelBuffer, time: Double, orientation: CGImagePropertyOrientation = .up) {
        self.pixelBuffer = pixelBuffer
        self.time = time
        self.orientation = orientation
    }
}

// What the camera pipeline and the eval harness feed detectors (spec §5.6).
public enum DetectorInput {
    public static let frameRate: Double = 15
    public static let shortSide = 480
    public static let pixelFormat: OSType = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
}
```

### `ShotDetector/ShotDetecting.swift`

```swift
// A detector consumes frames in time order and returns the shots it confirms (spec §4).
public protocol ShotDetecting {
    mutating func process(_ frame: VideoFrame) -> [ShotEvent]
    mutating func finish() -> [ShotEvent]
}

extension ShotDetecting {
    public mutating func finish() -> [ShotEvent] { [] }
}
```

### `DetectorEvalTests/CSVTests.swift`

```swift
import Testing

struct CSVTests {
    @Test func quotedFieldKeepsCommas() {
        let text = "video,light,notes\nclip_1,indoor,\"black mat, white ball (30 cm)\"\n"
        #expect(
            CSV.records(text) == [["video": "clip_1", "light": "indoor", "notes": "black mat, white ball (30 cm)"]])
    }

    @Test func doubledQuoteIsEscape() {
        #expect(CSV.parse("a,\"say \"\"hi\"\"\"\n") == [["a", "say \"hi\""]])
    }

    @Test func crlfAndMissingTrailingNewline() {
        #expect(CSV.parse("a,b\r\n1,2") == [["a", "b"], ["1", "2"]])
    }

    @Test func emptyTrailingFieldAndBlankLines() {
        let text = "frame,seconds,notes\n1,0.5,\n\n"
        #expect(CSV.records(text) == [["frame": "1", "seconds": "0.5", "notes": ""]])
    }

    @Test func shortRowFillsMissingKeysWithEmpty() {
        #expect(CSV.records("a,b,c\n1,2\n") == [["a": "1", "b": "2", "c": ""]])
    }
}
```

### `DetectorEvalTests/Harness/CSV.swift`

```swift
// Minimal RFC 4180 reader: commas, double-quoted fields, "" escapes, \n or \r\n rows.
enum CSV {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = text.makeIterator()
        var pending: Character? = nil
        while let c = pending ?? chars.next() {
            pending = nil
            if inQuotes {
                if c == "\"" {
                    if let next = chars.next() {
                        if next == "\"" {
                            field.append("\"")
                        } else {
                            inQuotes = false
                            pending = next
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                inQuotes = true
            } else if c == "," {
                row.append(field)
                field = ""
            } else if c == "\n" || c == "\r\n" || c == "\r" {
                row.append(field)
                rows.append(row)
                row = []
                field = ""
            } else {
                field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }

    // Rows as dictionaries keyed by the header row. Blank lines are dropped.
    static func records(_ text: String) -> [[String: String]] {
        let rows = parse(text).filter { $0 != [""] }
        guard let header = rows.first else { return [] }
        return rows.dropFirst().map { row in
            var record: [String: String] = [:]
            for (index, key) in header.enumerated() {
                record[key] = index < row.count ? row[index] : ""
            }
            return record
        }
    }
}
```

### `DetectorEvalTests/EventMatcherTests.swift`

```swift
import Testing

struct EventMatcherTests {
    private func score(
        _ labels: [(Double, LabelKind)], _ detections: [Double], profile: ScoringProfile = .rangeShot
    ) -> VideoScore {
        EventMatcher.score(
            labels: labels.map { TimedLabel(time: $0.0, kind: $0.1) },
            detections: detections.map { Detection(time: $0, emittedAt: $0 + 0.3) },
            profile: profile, window: 0.5)
    }

    @Test func detectionInsideWindowIsTruePositive() {
        let s = score([(10, .swing)], [10.2])
        #expect(s.truePositives == 1)
        #expect(s.falsePositives == 0)
        #expect(s.falseNegatives == 0)
        #expect(s.latencies.count == 1)
        #expect(abs(s.latencies[0] - 0.5) < 1e-9)  // emittedAt 10.5 − label 10
        #expect(abs(s.timingErrors[0] - 0.2) < 1e-9)
    }

    @Test func windowEdgeIsInclusive() {
        #expect(score([(10, .swing)], [9.5]).truePositives == 1)
        #expect(score([(10, .swing)], [10.5]).truePositives == 1)
    }

    @Test func detectionOutsideWindowIsMissPlusFalsePositive() {
        let s = score([(10, .swing)], [10.6])
        #expect(s.truePositives == 0)
        #expect(s.falseNegatives == 1)
        #expect(s.otherFalsePositives == 1)
        #expect(s.hardNegativeFalsePositives == 0)
    }

    @Test func doubleCountIsOneFalsePositive() {
        let s = score([(10, .swing)], [10.0, 10.1])
        #expect(s.truePositives == 1)
        #expect(s.falsePositives == 1)
        #expect(s.countError == 1)
    }

    @Test func oneDetectionServesOneLabel() {
        let s = score([(10, .swing), (10.4, .swing)], [10.2])
        #expect(s.truePositives == 1)
        #expect(s.falseNegatives == 1)
        #expect(s.countError == -1)
    }

    // Nearest-pair-first would pair 10.45 with 10.8 and lose a match.
    @Test func matchingMaximisesTruePositives() {
        let s = score([(10, .swing), (10.8, .swing)], [10.45, 11.2])
        #expect(s.truePositives == 2)
        #expect(s.falsePositives == 0)
    }

    @Test func unsortedInputGivesSameResult() {
        let s = score([(20, .swing), (10, .swing)], [20.1, 10.1])
        #expect(s.truePositives == 2)
    }

    @Test func practiceSwingIsHardNegativeForRangeShot() {
        let s = score([(5, .practice)], [5.1])
        #expect(s.positives == 0)
        #expect(s.hardNegativeFalsePositives == 1)
        #expect(s.firedByKind[.practice] == 1)
    }

    @Test func practiceSwingIsPositiveForRangeSwing() {
        let s = score([(5, .practice)], [5.1], profile: .rangeSwing)
        #expect(s.truePositives == 1)
        #expect(s.falsePositives == 0)
    }

    @Test func motionIsHardNegativeEverywhere() {
        for profile in [ScoringProfile.rangeShot, .rangeSwing, .putting] {
            #expect(score([(8, .motion)], [8.0], profile: profile).hardNegativeFalsePositives == 1)
        }
    }

    @Test func pickupCountsInPutting() {
        let s = score([(3, .pickup), (9, .putt)], [3.2, 9.1], profile: .putting)
        #expect(s.truePositives == 2)
        #expect(s.firedByKind[.pickup] == 1)
    }

    @Test func positiveWinsOverNearbyNegative() {
        let s = score([(10, .swing), (10.2, .motion)], [10.1])
        #expect(s.truePositives == 1)
        #expect(s.falsePositives == 0)
        #expect(s.firedByKind[.motion] == nil)
    }

    @Test func twoDetectionsOnOneNegativeAreTwoFalsePositives() {
        let s = score([(8, .motion)], [8.0, 8.2])
        #expect(s.hardNegativeFalsePositives == 2)
        #expect(s.firedByKind[.motion] == 1)
    }

    @Test func noDetections() {
        let s = score([(1, .swing), (2, .practice), (5, .swing)], [])
        #expect(s.detections == 0)
        #expect(s.falseNegatives == 2)
        #expect(s.labelsByKind == [.swing: 2, .practice: 1])
        #expect(s.firedByKind.isEmpty)
    }
}
```

### `DetectorEvalTests/Harness/EvalLabel.swift`

```swift
// Ground-truth marks from hitreg-ml label CSVs (ADR 0007, 0008).
enum LabelKind: String, CaseIterable, Codable, Sendable {
    case swing, practice, motion, putt, pickup
}

struct EvalLabel: Hashable, Sendable {
    var frame: Int
    var seconds: Double
    var kind: LabelKind
}

enum LabelRole: Sendable {
    case positive  // the detector should fire once
    case negative  // the detector must not fire (hard negative)
}

// Which label kinds a detector is expected to count.
struct ScoringProfile: Sendable {
    var name: String
    var roles: [LabelKind: LabelRole]

    func role(of kind: LabelKind) -> LabelRole { roles[kind] ?? .negative }

    // Ball-gated range counter (spec §5.4): practice swings leave the ball, so they must not count.
    static let rangeShot = ScoringProfile(
        name: "rangeShot", roles: [.swing: .positive, .practice: .negative, .motion: .negative])
    // Pose-only swing detection (#17, #18): practice swings are swings (ADR 0007).
    static let rangeSwing = ScoringProfile(
        name: "rangeSwing", roles: [.swing: .positive, .practice: .positive, .motion: .negative])
    // Putting (ADR 0008): a pickup moves the ball, so the detector is expected to count it.
    static let putting = ScoringProfile(
        name: "putting", roles: [.putt: .positive, .pickup: .positive, .motion: .negative])
}
```

### `DetectorEvalTests/Harness/EventMatcher.swift`

```swift
// A detector output as the harness sees it: the event's own time and the frame time it was emitted at.
struct Detection: Hashable, Sendable {
    var time: Double
    var emittedAt: Double
}

// A label with its time on the decoded stream's clock.
struct TimedLabel: Hashable, Sendable {
    var time: Double
    var kind: LabelKind
}

struct VideoScore: Sendable {
    var positives = 0
    var detections = 0
    var truePositives = 0
    var hardNegativeFalsePositives = 0
    var otherFalsePositives = 0
    var latencies: [Double] = []
    var timingErrors: [Double] = []
    var labelsByKind: [LabelKind: Int] = [:]
    var firedByKind: [LabelKind: Int] = [:]

    var falsePositives: Int { hardNegativeFalsePositives + otherFalsePositives }
    var falseNegatives: Int { positives - truePositives }
    var countError: Int { detections - positives }
}

enum EventMatcher {
    // One-to-one matching of detections to positive labels within ±window seconds.
    // Labels are taken in time order, each claiming the earliest free detection in its window;
    // with equal windows this gives the largest possible number of matches.
    static func score(
        labels: [TimedLabel], detections: [Detection], profile: ScoringProfile, window: Double
    ) -> VideoScore {
        var score = VideoScore()
        let sortedDetections = detections.sorted { $0.time < $1.time }
        let sortedLabels = labels.sorted { $0.time < $1.time }
        var claimed = Array(repeating: false, count: sortedDetections.count)
        score.detections = sortedDetections.count

        for label in sortedLabels {
            score.labelsByKind[label.kind, default: 0] += 1
            guard profile.role(of: label.kind) == .positive else { continue }
            score.positives += 1
            let hit = sortedDetections.indices.first { index in
                !claimed[index] && abs(sortedDetections[index].time - label.time) <= window
            }
            if let hit {
                claimed[hit] = true
                score.truePositives += 1
                score.firedByKind[label.kind, default: 0] += 1
                score.latencies.append(sortedDetections[hit].emittedAt - label.time)
                score.timingErrors.append(sortedDetections[hit].time - label.time)
            }
        }

        let negatives = sortedLabels.filter { profile.role(of: $0.kind) == .negative }
        var negativeFired = Array(repeating: false, count: negatives.count)
        for (index, detection) in sortedDetections.enumerated() where !claimed[index] {
            let nearest = negatives.indices
                .filter { abs(negatives[$0].time - detection.time) <= window }
                .min { abs(negatives[$0].time - detection.time) < abs(negatives[$1].time - detection.time) }
            if let nearest {
                score.hardNegativeFalsePositives += 1
                negativeFired[nearest] = true
            } else {
                score.otherFalsePositives += 1
            }
        }
        for (index, label) in negatives.enumerated() where negativeFired[index] {
            score.firedByKind[label.kind, default: 0] += 1
        }
        return score
    }
}
```

### `DetectorEvalTests/EvalMetricsTests.swift`

```swift
import Testing

struct EvalMetricsTests {
    private func video(positives: Int, truePositives: Int, hardFP: Int = 0, otherFP: Int = 0) -> VideoScore {
        var s = VideoScore()
        s.positives = positives
        s.truePositives = truePositives
        s.hardNegativeFalsePositives = hardFP
        s.otherFalsePositives = otherFP
        s.detections = truePositives + hardFP + otherFP
        return s
    }

    @Test func sumsOverVideosBeforeDividing() {
        let m = EvalMetrics([video(positives: 1, truePositives: 1), video(positives: 9, truePositives: 3, otherFP: 1)])
        #expect(m.videos == 2)
        #expect(m.recall == 0.4)
        #expect(m.precision == 0.8)
        #expect(m.falseNegatives == 6)
    }

    @Test func undefinedRatesAreNil() {
        let empty = EvalMetrics([video(positives: 0, truePositives: 0)])
        #expect(empty.precision == nil)
        #expect(empty.recall == nil)
        #expect(empty.falsePer50 == nil)
        #expect(empty.meanLatency == nil)
        #expect(empty.maxLatency == nil)
    }

    @Test func falsePositivesPerFiftyShots() {
        let m = EvalMetrics([video(positives: 100, truePositives: 100, hardFP: 1, otherFP: 1)])
        #expect(m.falsePer50 == 1)
        #expect(m.falsePositives == 2)
    }

    @Test func countErrorIsSummedPerVideoMagnitude() {
        // +1 on one video and −1 on another must not cancel out.
        let m = EvalMetrics([video(positives: 2, truePositives: 2, otherFP: 1), video(positives: 2, truePositives: 1)])
        #expect(m.absCountError == 2)
    }

    @Test func latencyMeanAndMax() {
        var a = VideoScore()
        a.latencies = [0.2, 0.4]
        a.timingErrors = [-0.1, 0.1]
        var b = VideoScore()
        b.latencies = [0.9]
        b.timingErrors = [0.4]
        let m = EvalMetrics([a, b])
        #expect(abs(m.meanLatency! - 0.5) < 1e-9)
        #expect(m.maxLatency == 0.9)
        #expect(abs(m.meanAbsTimingError! - 0.2) < 1e-9)
    }

    @Test func kindCountsMerge() {
        var a = VideoScore()
        a.labelsByKind = [.swing: 1, .motion: 2]
        a.firedByKind = [.swing: 1]
        var b = VideoScore()
        b.labelsByKind = [.swing: 3]
        b.firedByKind = [.swing: 2]
        let m = EvalMetrics([a, b])
        #expect(m.labelsByKind == [.swing: 4, .motion: 2])
        #expect(m.firedByKind == [.swing: 3])
    }
}
```

### `DetectorEvalTests/Harness/EvalMetrics.swift`

```swift
// Scores summed over videos (micro-averaged), then turned into rates.
struct EvalMetrics: Sendable {
    var videos = 0
    var positives = 0
    var detections = 0
    var truePositives = 0
    var hardNegativeFalsePositives = 0
    var otherFalsePositives = 0
    var absCountError = 0
    var latencies: [Double] = []
    var timingErrors: [Double] = []
    var labelsByKind: [LabelKind: Int] = [:]
    var firedByKind: [LabelKind: Int] = [:]

    init() {}

    init(_ scores: [VideoScore]) {
        for score in scores { add(score) }
    }

    mutating func add(_ score: VideoScore) {
        videos += 1
        positives += score.positives
        detections += score.detections
        truePositives += score.truePositives
        hardNegativeFalsePositives += score.hardNegativeFalsePositives
        otherFalsePositives += score.otherFalsePositives
        absCountError += abs(score.countError)
        latencies += score.latencies
        timingErrors += score.timingErrors
        labelsByKind.merge(score.labelsByKind, uniquingKeysWith: +)
        firedByKind.merge(score.firedByKind, uniquingKeysWith: +)
    }

    var falsePositives: Int { hardNegativeFalsePositives + otherFalsePositives }
    var falseNegatives: Int { positives - truePositives }

    // nil when undefined (no detections / no positives), never NaN.
    var precision: Double? { detections == 0 ? nil : Double(truePositives) / Double(detections) }
    var recall: Double? { positives == 0 ? nil : Double(truePositives) / Double(positives) }
    // Spec §2: at most 1 false count per 50 real shots.
    var falsePer50: Double? { positives == 0 ? nil : Double(falsePositives) * 50 / Double(positives) }
    var meanLatency: Double? { latencies.isEmpty ? nil : latencies.reduce(0, +) / Double(latencies.count) }
    var maxLatency: Double? { latencies.max() }
    var meanAbsTimingError: Double? {
        timingErrors.isEmpty ? nil : timingErrors.map(abs).reduce(0, +) / Double(timingErrors.count)
    }
}
```

### `DetectorEvalTests/EvalDatasetTests.swift`

```swift
import Foundation
import Testing

struct EvalDatasetTests {
    private func labels(_ csv: String) throws -> [EvalLabel] {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).csv")
        try Data(csv.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try EvalDataset.labels(url)
    }

    @Test func parsesLabelRows() throws {
        #expect(
            try labels("frame,seconds,kind\n130,4.333,practice\n1416,47.200,swing\n") == [
                EvalLabel(frame: 130, seconds: 4.333, kind: .practice),
                EvalLabel(frame: 1416, seconds: 47.2, kind: .swing),
            ])
    }

    @Test func unknownKindThrows() {
        #expect(throws: EvalDataset.LoadError.self) { try labels("frame,seconds,kind\n1,0.1,chip\n") }
    }

    @Test(.enabled(if: MLData.root != nil, "hitreg-ml not found; set REPS_ML_DIR"))
    func rangeTestSplitLoads() throws {
        let dataset = try EvalDataset.rangeTest(root: try #require(MLData.root))
        #expect(dataset.videos.count == 22)  // ADR 0007: 22 test videos
        for video in dataset.videos {
            #expect(video.labels.contains { $0.kind == .swing }, "\(video.name)")
            #expect(["dtl", "faceon"].contains(video.scenario.split(separator: "/").first), "\(video.name)")
        }
    }

    @Test(.enabled(if: MLData.root.map(EvalDataset.hasPutting) == true, "no data/putting in hitreg-ml"))
    func puttingLoads() throws {
        let dataset = try EvalDataset.putting(root: try #require(MLData.root))
        #expect(!dataset.videos.isEmpty)
        for video in dataset.videos {
            #expect(video.scenario.hasPrefix("putt/"))
            #expect(video.labels.contains { $0.kind == .putt }, "\(video.name)")
        }
    }
}
```

### `DetectorEvalTests/Harness/EvalDataset.swift`

```swift
import Foundation

struct EvalVideo: Sendable {
    var name: String
    var url: URL
    var scenario: String  // "dtl/sun", "faceon/cloud", "putt/indoor"
    var labels: [EvalLabel]
}

struct EvalDataset: Sendable {
    var name: String
    var profile: ScoringProfile
    var videos: [EvalVideo]

    enum LoadError: Error, CustomStringConvertible {
        case missingFile(String)
        case badRow(file: String, row: [String: String])
        case unknownVideo(String)

        var description: String {
            switch self {
            case .missingFile(let path): "missing file: \(path)"
            case .badRow(let file, let row): "bad row in \(file): \(row)"
            case .unknownVideo(let name): "video in splits.json but not in manifest.csv: \(name)"
            }
        }
    }

    // Range footage, test split only (ADR 0007). Rows whose notes say "discard" are left out.
    static func rangeTest(root: URL, profile: ScoringProfile = .rangeShot) throws -> EvalDataset {
        let data = root.appending(path: "data")
        let splits = try JSONDecoder().decode(
            [String: [String]].self, from: Data(contentsOf: data.appending(path: "splits.json")))
        let manifest = try manifestRows(data.appending(path: "manifest.csv"))
        var videos: [EvalVideo] = []
        for name in splits["test"] ?? [] {
            guard let row = manifest[name] else { throw LoadError.unknownVideo(name) }
            if row["notes"]?.contains("discard") == true { continue }
            videos.append(
                EvalVideo(
                    name: name,
                    url: try existing(data.appending(path: "raw/\(name).mov")),
                    scenario: "\(row["angle"] ?? "?")/\(row["light"] ?? "?")",
                    labels: try labels(data.appending(path: "labels/\(name).csv"))))
        }
        return EvalDataset(name: "range-test", profile: profile, videos: videos)
    }

    // Putting footage (ADR 0008): every clip in data/putting/manifest.csv; no splits yet.
    static func putting(root: URL) throws -> EvalDataset {
        let data = root.appending(path: "data/putting")
        let manifest = try manifestRows(data.appending(path: "manifest.csv"))
        let videos = try manifest.keys.sorted().map { name in
            EvalVideo(
                name: name,
                url: try existing(data.appending(path: "raw/\(name).mov")),
                scenario: "putt/\(manifest[name]?["light"] ?? "?")",
                labels: try labels(data.appending(path: "labels/\(name).csv")))
        }
        return EvalDataset(name: "putting", profile: .putting, videos: videos)
    }

    static func hasPutting(root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appending(path: "data/putting/manifest.csv").path)
    }

    static func labels(_ url: URL) throws -> [EvalLabel] {
        try records(url).map { row in
            guard let frame = row["frame"].flatMap({ Int($0) }),
                let seconds = row["seconds"].flatMap({ Double($0) }),
                let kind = row["kind"].flatMap({ LabelKind(rawValue: $0) })
            else { throw LoadError.badRow(file: url.lastPathComponent, row: row) }
            return EvalLabel(frame: frame, seconds: seconds, kind: kind)
        }
    }

    private static func manifestRows(_ url: URL) throws -> [String: [String: String]] {
        var byVideo: [String: [String: String]] = [:]
        for row in try records(url) {
            guard let video = row["video"], !video.isEmpty else {
                throw LoadError.badRow(file: url.lastPathComponent, row: row)
            }
            byVideo[video] = row
        }
        return byVideo
    }

    private static func records(_ url: URL) throws -> [[String: String]] {
        CSV.records(try String(contentsOf: try existing(url), encoding: .utf8))
    }

    private static func existing(_ url: URL) throws -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { throw LoadError.missingFile(url.path) }
        return url
    }
}
```

### `DetectorEvalTests/VideoFrameReaderTests.swift`

```swift
import CoreGraphics
import CoreVideo
import Foundation
import ShotDetector
import Testing

struct VideoFrameReaderTests {
    @Test(arguments: [
        (CGSize(width: 1920, height: 1080), 854, 480),
        (CGSize(width: 1080, height: 1920), 480, 854),
        (CGSize(width: 1280, height: 720), 854, 480),
    ])
    func scaledSizeKeepsAspectWithEvenSides(size: CGSize, width: Int, height: Int) throws {
        let scaled = try #require(VideoFrameReader.scaledSize(size, shortSide: 480))
        #expect(scaled.width == width)
        #expect(scaled.height == height)
    }

    @Test func smallVideoIsNotScaled() {
        #expect(VideoFrameReader.scaledSize(CGSize(width: 640, height: 480), shortSide: 480) == nil)
    }

    @Test func orientationFollowsRotation() {
        #expect(VideoFrameReader.orientation(from: .identity) == .up)
        #expect(VideoFrameReader.orientation(from: CGAffineTransform(rotationAngle: .pi / 2)) == .right)
        #expect(VideoFrameReader.orientation(from: CGAffineTransform(rotationAngle: -.pi / 2)) == .left)
        #expect(VideoFrameReader.orientation(from: CGAffineTransform(rotationAngle: .pi)) == .down)
    }

    @Test(.enabled(if: MLData.root != nil, "hitreg-ml not found; set REPS_ML_DIR"))
    func decodesDownscaledSampledFrames() async throws {
        // 59.94 fps, 1080×1920, 332 frames (data/manifest.csv).
        let url = try #require(MLData.root).appending(path: "data/raw/2025-07-16_uldis_dtl_cloud_1.mov")
        var frames: [(time: Double, width: Int, height: Int, format: OSType)] = []
        let times = try await VideoFrameReader(url: url).read { frame in
            frames.append(
                (
                    frame.time, CVPixelBufferGetWidth(frame.pixelBuffer), CVPixelBufferGetHeight(frame.pixelBuffer),
                    CVPixelBufferGetPixelFormatType(frame.pixelBuffer)
                ))
        }
        #expect(times.count == 332)
        #expect(zip(times, times.dropFirst()).allSatisfy { $0 < $1 })
        #expect(abs(frames.count - 332 / 4) <= 2)  // 15 of 59.94 fps
        #expect(frames.allSatisfy { min($0.width, $0.height) == DetectorInput.shortSide })
        #expect(frames.allSatisfy { $0.format == DetectorInput.pixelFormat })
        let gaps = zip(frames, frames.dropFirst()).map { $1.time - $0.time }
        #expect(gaps.allSatisfy { $0 > 0.05 && $0 < 0.09 })
    }
}
```

### `DetectorEvalTests/Harness/VideoFrameReader.swift`

```swift
import AVFoundation
import ShotDetector

// Decodes a video file into VideoFrames the way the camera pipeline will deliver them:
// sampled to frameRate, scaled so the short side is shortSide, 420f pixels (DetectorInput).
struct VideoFrameReader {
    var url: URL
    var frameRate: Double? = DetectorInput.frameRate  // nil = every frame
    var shortSide: Int? = DetectorInput.shortSide  // nil = native size

    enum ReadError: Error {
        case noVideoTrack(URL)
        case cannotRead(URL, (any Error)?)
    }

    // Calls body for every sampled frame, in order. Returns the presentation time of every
    // decoded frame (sampled or not), indexed by frame number, so labels can be put on the same clock.
    func read(_ body: (VideoFrame) throws -> Void) async throws -> [Double] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ReadError.noVideoTrack(url)
        }
        let (naturalSize, transform) = try await track.load(.naturalSize, .preferredTransform)
        let orientation = Self.orientation(from: transform)

        var settings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: DetectorInput.pixelFormat]
        if let shortSide, let size = Self.scaledSize(naturalSize, shortSide: shortSide) {
            settings[kCVPixelBufferWidthKey as String] = size.width
            settings[kCVPixelBufferHeightKey as String] = size.height
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw ReadError.cannotRead(url, reader.error) }

        var times: [Double] = []
        var nextDue = -Double.infinity
        let step = frameRate.map { 1 / $0 } ?? 0
        while let sample = output.copyNextSampleBuffer() {
            let time = sample.presentationTimeStamp.seconds
            times.append(time)
            // 1 ms slack so 29.97 fps footage still lands on every 2nd frame.
            guard time + 0.001 >= nextDue, let pixelBuffer = sample.imageBuffer else { continue }
            nextDue = nextDue.isFinite ? max(nextDue + step, time + step / 2) : time + step
            try body(VideoFrame(pixelBuffer: pixelBuffer, time: time, orientation: orientation))
        }
        if reader.status == .failed { throw ReadError.cannotRead(url, reader.error) }
        return times
    }

    // Same mapping as hitreg-ml's keypoint extractor, so pose coordinates match the training data.
    static func orientation(from transform: CGAffineTransform) -> CGImagePropertyOrientation {
        switch Int((atan2(transform.b, transform.a) * 180 / .pi).rounded()) {
        case 90: .right
        case -90: .left
        case 180, -180: .down
        default: .up
        }
    }

    // Even dimensions with the short side at shortSide; nil if the video is already that small.
    static func scaledSize(_ size: CGSize, shortSide: Int) -> (width: Int, height: Int)? {
        let scale = Double(shortSide) / Double(min(size.width, size.height))
        guard scale < 1 else { return nil }
        func even(_ value: Double) -> Int { Int((value * scale / 2).rounded()) * 2 }
        return (even(size.width), even(size.height))
    }
}
```

### `DetectorEvalTests/Harness/EvalRunner.swift`

```swift
import Foundation
import ShotDetector

struct VideoResult: Sendable {
    var video: String
    var scenario: String
    var score: VideoScore
    var decodedFrames: Int
    var sampledFrames: Int
}

// Runs one detector over one dataset and scores every video.
struct EvalRunner {
    var window: Double = 0.5  // spec §5.4: impact within ±0.5 s
    var frameRate: Double? = DetectorInput.frameRate
    var shortSide: Int? = DetectorInput.shortSide

    func run(
        _ name: String,
        on dataset: EvalDataset,
        makeDetector: (EvalVideo) throws -> any ShotDetecting
    ) async throws -> EvalReport {
        let clock = ContinuousClock()
        let start = clock.now
        var results: [VideoResult] = []
        for video in dataset.videos {
            var detector = try makeDetector(video)
            var detections: [Detection] = []
            var sampled = 0
            var lastTime = 0.0
            let reader = VideoFrameReader(url: video.url, frameRate: frameRate, shortSide: shortSide)
            let frameTimes = try await reader.read { frame in
                sampled += 1
                lastTime = frame.time
                detections += detector.process(frame).map { Detection(time: $0.time, emittedAt: frame.time) }
            }
            detections += detector.finish().map { Detection(time: $0.time, emittedAt: lastTime) }
            // Labels move onto the decoder's clock by frame number; past the end, the CSV seconds are used.
            let labels = video.labels.map { label in
                TimedLabel(
                    time: frameTimes.indices.contains(label.frame) ? frameTimes[label.frame] : label.seconds,
                    kind: label.kind)
            }
            results.append(
                VideoResult(
                    video: video.name,
                    scenario: video.scenario,
                    score: EventMatcher.score(
                        labels: labels, detections: detections, profile: dataset.profile, window: window),
                    decodedFrames: frameTimes.count,
                    sampledFrames: sampled))
        }
        return EvalReport(
            name: name, dataset: dataset.name, profile: dataset.profile.name, window: window,
            frameRate: frameRate, shortSide: shortSide, results: results,
            seconds: (clock.now - start) / .seconds(1))
    }
}
```

### `DetectorEvalTests/Harness/EvalReport.swift`

```swift
import Foundation

struct EvalReport: Sendable {
    var name: String
    var dataset: String
    var profile: String
    var window: Double
    var frameRate: Double?
    var shortSide: Int?
    var results: [VideoResult]
    var seconds: Double

    // One row per scenario (sorted), then "all".
    var scenarios: [(scenario: String, metrics: EvalMetrics)] {
        Set(results.map(\.scenario)).sorted().map { scenario in
            (scenario, EvalMetrics(results.filter { $0.scenario == scenario }.map(\.score)))
        } + [("all", overall)]
    }

    var overall: EvalMetrics { EvalMetrics(results.map(\.score)) }

    var table: String {
        var lines = [
            "DetectorEval \(name) on \(dataset) (\(profile))  window ±\(format(window)) s  "
                + "\(frameRate.map { "\(format($0)) fps" } ?? "every frame")  "
                + "short side \(shortSide.map(String.init) ?? "native")  took \(format(seconds)) s",
            Self.row([
                "scenario", "videos", "pos", "det", "TP", "FP", "hardFP", "FN", "prec", "recall", "FP/50", "|cnt|",
                "lat", "latMax",
            ]),
        ]
        for (scenario, m) in scenarios {
            lines.append(
                Self.row([
                    scenario, "\(m.videos)", "\(m.positives)", "\(m.detections)", "\(m.truePositives)",
                    "\(m.falsePositives)", "\(m.hardNegativeFalsePositives)", "\(m.falseNegatives)",
                    format(m.precision), format(m.recall), format(m.falsePer50), "\(m.absCountError)",
                    format(m.meanLatency), format(m.maxLatency),
                ]))
        }
        let all = overall
        lines.append(
            "fired/labels: "
                + LabelKind.allCases.compactMap { kind in
                    all.labelsByKind[kind].map { "\(kind.rawValue) \(all.firedByKind[kind] ?? 0)/\($0)" }
                }.joined(separator: "  "))
        for result in results where result.score.countError != 0 {
            lines.append("miscount \(result.video): expected \(result.score.positives), got \(result.score.detections)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    var json: Data {
        get throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(ReportJSON(self))
        }
    }

    private static func row(_ cells: [String]) -> String {
        cells.enumerated().map { index, cell in
            index == 0
                ? cell.padding(toLength: 14, withPad: " ", startingAt: 0)
                : String(repeating: " ", count: max(1, 8 - cell.count)) + cell
        }.joined()
    }

    private func format(_ value: Double?) -> String {
        value.map { String(format: "%.2f", $0) } ?? "-"
    }
}

// Encoded shape of a report (build/eval/<name>.json).
private struct ReportJSON: Encodable {
    struct Scenario: Encodable {
        var scenario: String
        var videos, positives, detections, truePositives, falsePositives, hardNegativeFalsePositives: Int
        var falseNegatives, absCountError: Int
        var precision, recall, falsePer50, meanLatency, maxLatency, meanAbsTimingError: Double?
        var labelsByKind, firedByKind: [String: Int]
    }
    struct Video: Encodable {
        var video, scenario: String
        var positives, detections, truePositives, falsePositives, decodedFrames, sampledFrames: Int
    }
    var name, dataset, profile: String
    var window: Double
    var frameRate: Double?
    var shortSide: Int?
    var seconds: Double
    var scenarios: [Scenario]
    var videos: [Video]

    init(_ report: EvalReport) {
        name = report.name
        dataset = report.dataset
        profile = report.profile
        window = report.window
        frameRate = report.frameRate
        shortSide = report.shortSide
        seconds = report.seconds
        scenarios = report.scenarios.map { scenario, m in
            Scenario(
                scenario: scenario, videos: m.videos, positives: m.positives, detections: m.detections,
                truePositives: m.truePositives, falsePositives: m.falsePositives,
                hardNegativeFalsePositives: m.hardNegativeFalsePositives, falseNegatives: m.falseNegatives,
                absCountError: m.absCountError, precision: m.precision, recall: m.recall,
                falsePer50: m.falsePer50, meanLatency: m.meanLatency, maxLatency: m.maxLatency,
                meanAbsTimingError: m.meanAbsTimingError,
                labelsByKind: Dictionary(uniqueKeysWithValues: m.labelsByKind.map { ($0.rawValue, $1) }),
                firedByKind: Dictionary(uniqueKeysWithValues: m.firedByKind.map { ($0.rawValue, $1) }))
        }
        videos = report.results.map {
            Video(
                video: $0.video, scenario: $0.scenario, positives: $0.score.positives,
                detections: $0.score.detections, truePositives: $0.score.truePositives,
                falsePositives: $0.score.falsePositives, decodedFrames: $0.decodedFrames,
                sampledFrames: $0.sampledFrames)
        }
    }
}
```

### `DetectorEvalTests/Harness/EvalOutput.swift`

```swift
import Foundation
import Testing

// Prints a report, attaches it to the test result and writes it to <repo>/build/eval/ (gitignored).
enum EvalOutput {
    // <repo>/DetectorEvalTests/Harness/EvalOutput.swift -> <repo>/build/eval
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "build/eval", directoryHint: .isDirectory)

    static func publish(_ report: EvalReport) throws {
        let table = report.table
        let json = try report.json
        print(table)
        Attachment.record(table, named: "\(report.name).txt")
        Attachment.record(json, named: "\(report.name).json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(table.utf8).write(to: directory.appending(path: "\(report.name).txt"))
        try json.write(to: directory.appending(path: "\(report.name).json"))
    }
}
```

### `DetectorEvalTests/Detectors/LabelOracle.swift`

```swift
import ShotDetector

// Test-only detector: fires on the first sampled frame at or after each positive label.
// Proves decode → detect → match → report end to end without a real detector.
struct LabelOracle: ShotDetecting {
    private var pending: [Double]

    init(video: EvalVideo, profile: ScoringProfile) {
        pending = video.labels.filter { profile.role(of: $0.kind) == .positive }.map(\.seconds).sorted()
    }

    mutating func process(_ frame: VideoFrame) -> [ShotEvent] {
        var events: [ShotEvent] = []
        while let next = pending.first, frame.time + 0.001 >= next {
            pending.removeFirst()
            events.append(ShotEvent(time: frame.time))
        }
        return events
    }
}
```

### `DetectorEvalTests/OracleEvalTests.swift`

```swift
import Foundation
import ShotDetector
import Testing

// End-to-end check of the harness: a detector that replays the labels must score perfectly.
@Suite(.enabled(if: MLData.root != nil, "hitreg-ml not found; set REPS_ML_DIR"))
struct OracleEvalTests {
    @Test func rangeTestSplit() async throws {
        let dataset = try EvalDataset.rangeTest(root: try #require(MLData.root))
        try await expectPerfectScore(on: dataset, name: "oracle-range")
    }

    @Test(.enabled(if: MLData.root.map(EvalDataset.hasPutting) == true, "no data/putting in hitreg-ml"))
    func putting() async throws {
        let dataset = try EvalDataset.putting(root: try #require(MLData.root))
        try await expectPerfectScore(on: dataset, name: "oracle-putting")
    }

    private func expectPerfectScore(on dataset: EvalDataset, name: String) async throws {
        #expect(!dataset.videos.isEmpty)
        let report = try await EvalRunner().run(name, on: dataset) { video in
            LabelOracle(video: video, profile: dataset.profile)
        }
        try EvalOutput.publish(report)
        let all = report.overall
        #expect(all.recall == 1)
        #expect(all.precision == 1)
        #expect(all.hardNegativeFalsePositives == 0)
        // The oracle fires on the next sampled frame, so it lags by at most ~one sampling step.
        #expect(try #require(all.maxLatency) <= 2 / DetectorInput.frameRate)
    }
}
```

## Appendix B — docs/code-reference.md

Replace the `ShotDetector/ShotEvent.swift` entry with:

```markdown
## ShotDetector/ShotEvent.swift
Output type of the ShotDetector framework (spec §4). The framework must never import AVFoundation, AVKit, UIKit, SwiftUI or CoreMedia (ADR 0010).
- `ShotEvent(time:)`: one detected shot; `time` is the detector's estimate of when it happened (impact or ball exit), in seconds on the frame stream's clock
```

Insert after it:

```markdown
## ShotDetector/ShotDetecting.swift
The detector boundary (spec §4, ADR 0010).
- `ShotDetecting`: `mutating process(_:) -> [ShotEvent]` takes frames in time order and returns shots confirmed on that frame; `mutating finish() -> [ShotEvent]` flushes at end of stream (default `[]`)

## ShotDetector/VideoFrame.swift
What detectors are fed.
- `VideoFrame(pixelBuffer:time:orientation:)`: one downscaled frame; `time` in seconds (presentation time), `orientation` for Vision
- `DetectorInput`: the frame contract for the camera pipeline and the eval harness: `frameRate` 15, `shortSide` 480, `pixelFormat` 420f
```

Append after the `DetectorEvalTests/MLDataTests.swift` entry:

```markdown
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
```

## Appendix C — docs/adr/0010-detector-frame-contract-and-eval.md

```markdown
# 0010 — Detectors take VideoFrames via ShotDetecting; eval matching and metrics

- Status: Accepted (extends 0009)
- Date: 2026-09-27

## Context
Spec §4 needs ShotDetector to run against saved video in tests; §7 needs precision/recall per scenario. The ball presence, putting and range detectors (#14, #16, #17–#19) must all be scored the same way against hitreg-ml footage (ADR 0007).

## Decision
- ShotDetector's input is `VideoFrame` (CVPixelBuffer, time in seconds, `CGImagePropertyOrientation`) through `protocol ShotDetecting { process(_:) -> [ShotEvent]; finish() -> [ShotEvent] }`, synchronous, called in frame order.
- `DetectorInput`: 15 fps, short side 480 px, 420f pixel buffers. The camera pipeline and the eval decoder both deliver this.
- ShotDetector never imports AVFoundation, AVKit, UIKit, SwiftUI or CoreMedia. Check: `grep -rnE 'import (AVFoundation|AVKit|UIKit|SwiftUI|CoreMedia)' ShotDetector` prints nothing.
- `ShotEvent.time` is the estimated shot time (impact or ball exit); the harness also records when the event was emitted, for latency.
- DetectorEval decodes footage with AVAssetReader in the test target, puts labels on the decoder clock by frame number, and matches events one-to-one to positive labels within ±0.5 s. Unmatched events are false positives, split into hard (near a negative label) and other.
- Label roles per detector type: range shot counter: swing positive, practice and motion negative; pose-only swing detector: swing and practice positive, motion negative; putting: putt and pickup positive, motion negative.
- Metrics are summed over videos per `angle/light` scenario (putting: `putt/light`): precision, recall, false positives per 50, per-video absolute count error, latency (emit − label), per-kind fired counts. Reports go to `build/eval/` and the test attachments.

## Consequences
Every detector gets the same scoreboard with no AVFoundation in its code. The camera pipeline (#13) is bound to the `DetectorInput` contract. Accuracy thresholds are applied separately (#21).
```

## Appendix D — docs/open-questions.md rows

```markdown
| Q18 | Where does DetectorEval get the ball region (the user's tap, §5.2) for each footage clip? | #14, #16, #19 | Leaning: a small per-video file in hitreg-ml (e.g. `data/putting/roi/<video>.json`, normalised rect at the first frame) written by a labelling tool; the `makeDetector(video)` factory reads it. Alternative: auto-locate the ball in the first second. |
| Q19 | The range test split has 23 swings, 16 practice, 7 motion. Enough to gate ≥95 % recall and ≤1 false per 50? | #21 | No: one miss is −4 %. Leaning: record more range footage for the test split, or gate on test + val once the classifier is frozen. |
```
