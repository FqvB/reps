# Architecture decision records

One file per decision: `NNNN-short-title.md`, based on `0000-template.md`. Don't edit accepted ADRs. Supersede them with a new one.

| ADR | Decision | Status |
|---|---|---|
| [0001](0001-native-swift.md) | Native Swift + SwiftUI, not React Native | Accepted |
| [0002](0002-ball-gated-fusion.md) | Shot = ball-gated pose classification, no audio | Accepted |
| [0003](0003-record-and-cut-clips.md) | Clips via rolling segments + export, not a ring buffer | Accepted |
| [0004](0004-swiftdata-local-only.md) | SwiftData, local only, JSON-exportable | Accepted |
| [0005](0005-dev-workflow.md) | Plan/implement/review model routing, local-only verification | Accepted |
| [0006](0006-session-and-clip-storage.md) | Active/finished sessions, no uncertainty flag, UUID clip names | Accepted |
| [0007](0007-hitreg-ml-footage-and-model.md) | hitreg-ml is the footage, ground-truth and model source | Accepted |
| [0008](0008-putting-absence-is-a-stroke.md) | Putting: ball gone ≥300 ms = stroke, no occlusion state | Accepted |
| [0009](0009-project-structure.md) | Hand-written synced-folder Xcode project, ShotDetector as a framework | Accepted |
| [0010](0010-detector-frame-contract-and-eval.md) | Detectors take VideoFrames via ShotDetecting; eval matching and metrics | Accepted |
| [0011](0011-ball-auto-locate.md) | Detector auto-locates the ball (newest settled), no tap | Accepted |
| [0012](0012-data-model-and-export-v1.md) | Data model snapshots, VersionedSchema V1, JSON export format v1 | Accepted |
| [0013](0013-session-engine-rules.md) | Session engine rules, −1, snapshots; V1 amended before first install | Accepted |
