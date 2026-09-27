# 0009 — Hand-written synced-folder Xcode project, ShotDetector as a framework

- Status: Accepted
- Date: 2026-09-27

## Context
The project is created and changed by agents without the Xcode GUI. Spec §4 requires ShotDetector to have no AVFoundation dependency so it runs against video files in tests.

## Decision
- `Reps.xcodeproj` is hand-written (objectVersion 77) with file-system synchronized folders: `Reps/`, `ShotDetector/`, `RepsTests/`, `DetectorEvalTests/`. No xcodegen or tuist.
- `ShotDetector` is its own framework target, embedded in the app. It never imports AVFoundation, AVKit, UIKit or SwiftUI. It is nonisolated by default; the app target defaults to MainActor isolation.
- Tests use Swift Testing. `Unit` runs `RepsTests` (hosted in the app); `DetectorEval` runs `DetectorEvalTests` (no host, links only ShotDetector).
- Signing stays out of git: `Config/Signing.xcconfig` includes the gitignored `Signing.local.xcconfig`.

## Consequences
Adding files needs no project edits. Adding a target (UI tests with #11) needs a hand edit of `project.pbxproj`. The detector boundary is enforced by the module, and checked with `grep -rnE 'import (AVFoundation|AVKit|UIKit|SwiftUI)' ShotDetector`.
