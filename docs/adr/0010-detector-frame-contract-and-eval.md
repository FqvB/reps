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
- #13 sets the capture connection's `videoRotationAngle` so frames arrive upright (orientation `.up`); detectors still honour `VideoFrame.orientation`. (Eval footage is all stored upright, so rotation handling is untested.)
- `VideoFrame.time` is monotonic seconds with an arbitrary origin (live capture uses host-clock time, eval starts at 0). Detectors measure durations with `time` differences, never frame counts, since spec §5.6 may drop the rate under thermal load.
