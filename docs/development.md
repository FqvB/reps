# Development

How the project is built, tested and committed.

## Platform

- iOS 26 minimum, iPhone only. Bundle ID `com.fqvb.reps`.
- Signing: free provisioning for now (builds expire after 7 days). The paid Apple Developer Program is pending. Put `DEVELOPMENT_TEAM = …` in `Config/Signing.local.xcconfig` (gitignored).
- Formatter: swift-format.
- ML tools (labelling, keypoint extraction, data checks, clip cutting) live in [`ml/`](../ml) (Python 3.14 + uv, PyTorch, coremltools). Footage, labels and keypoints are local only and never committed. Tests find them in `ml/data/`, or wherever `REPS_ML_DIR` points. See ADR 0007.
- Voice is English only.

## Feature workflow

1. **Branch**: `feat/<issue>-<slug>` from `main` (`fix/…`, `docs/…` for other kinds).
2. **Plan**: write `docs/plans/<issue>-<slug>.md` before touching code. Small fixes and docs changes skip this.
3. **Implement** what the plan says and nothing more.
4. **Review** only when the issue's label asks for it: `review:logic` for logic-heavy work (session engine, detectors, fusion, pipelines), `review:security` for permissions, file paths, Photos, sharing, or anything that stores or exports user data.
5. Fix review findings, verify locally, commit, push, and open a PR that closes the issue.

## Testing: local only, only what the change deserves

- **No CI/CD.** Everything is verified locally.
- Pick the smallest suite that covers the change:

| Change | Run |
|---|---|
| Docs, comments, copy, assets, colours, simple layout | nothing (build only if Swift files changed) |
| UI screen without logic | build only |
| Models, session engine, voice, clip writer logic | `Unit` test plan, filtered to the touched suites |
| Detector code or thresholds | `Unit` for the detector + `DetectorEval` (footage) |
| Session flow, accident-proofing | the relevant `UI` tests only |

- Filter with `-only-testing:<Target>/<Suite>` instead of running everything. Commands (run from the repo root):

```sh
DEST='platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'
# build
xcodebuild build -project Reps.xcodeproj -scheme Reps -destination "$DEST" -quiet
# Unit, filtered to a suite
xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan Unit -destination "$DEST" -only-testing:RepsTests/RepsStoreTests
# DetectorEval (footage from ml/data; override with TEST_RUNNER_REPS_ML_DIR=/path, skips if not found)
xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan DetectorEval -destination "$DEST"
# DetectorEval harness logic only (no footage, < 1 s)
xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan DetectorEval -destination "$DEST" -only-testing:DetectorEvalTests/CSVTests -only-testing:DetectorEvalTests/EventMatcherTests -only-testing:DetectorEvalTests/EvalMetricsTests
# one detector's eval suite, e.g. the oracle
xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan DetectorEval -destination "$DEST" -only-testing:DetectorEvalTests/OracleEvalTests
# format + lint
xcrun swift-format format --in-place --recursive --parallel Reps ShotDetector RepsTests DetectorEvalTests
xcrun swift-format lint --strict --recursive --parallel Reps ShotDetector RepsTests DetectorEvalTests
```

- Env vars reach simulator tests only with the `TEST_RUNNER_` prefix (it's stripped), e.g. `TEST_RUNNER_REPS_ML_DIR`.
- Eval reports land in `build/eval/<name>.txt` and `.json` (latest run, gitignored) and are attached to the test in the .xcresult. A new detector gets its own `<Name>EvalTests` suite that calls `EvalRunner().run(…)` and `EvalOutput.publish(_:)`.
- Source files go in the synced folders (`Reps/`, `ShotDetector/`, `RepsTests/`, `DetectorEvalTests/`); never edit `project.pbxproj` to add files.
- Only write tests for behaviour that matters: logic, state machines, math, detectors. Skip tests for pure layout.

## Code style

- Keep comments short, one line and only where the *why* isn't obvious.
- Real documentation lives in `docs/code-reference.md`: one entry per file, one line per public type/function. Update it in the same commit as the code.
- `ShotDetector` and everything under it stays free of AVFoundation so it runs against video files in tests (spec §4). Detectors take `VideoFrame`s through `ShotDetecting` (ADR 0010). Check: `grep -rnE 'import (AVFoundation|AVKit|UIKit|SwiftUI|CoreMedia)' ShotDetector` prints nothing.

## Commits and PRs

- Title: short, lowercase, imperative-ish, e.g. `implemented ball presence detector`.
- Body: one line at most, then issue refs (`Closes #14`, `Refs #3`).
- PR: title same style, body is 1–3 lines plus `Closes #N`.
- Until the MVP ships, PRs are squash-merged into `main` once local verification passes and any required review is fixed.
- Update `docs/roadmap.md` status when an issue closes. Add new questions to `docs/open-questions.md` and decisions to `docs/adr/`.
