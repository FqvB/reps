# Reps

iOS golf practice rep counter. Phone on a tripod counts shots and putts through the camera, calls the count out loud, and optionally saves a clip of every shot. Native Swift, SwiftUI, SwiftData, AVFoundation, Vision, Core ML. Personal use, iOS only, fully offline, no backend.

- Spec (source of truth): `docs/spec/mvp-design-doc.md` (original: `docs/spec/mvp-design-doc.html`)
- Roadmap: `docs/roadmap.md` · GitHub milestones = phases, issues = features
- Figma: https://www.figma.com/design/pMKE8PoWxIEotHas0rmQX1 · notes in `docs/design.md`
- Open questions: `docs/open-questions.md` · decisions: `docs/adr/`
- Code reference (file + function docs): `docs/code-reference.md`

## Platform

- iOS 26 minimum, iPhone only. Bundle ID `com.fqvb.reps`.
- Signing: free provisioning for now (builds expire after 7 days). The paid Apple Developer Program is pending.
- Formatter: swift-format.
- ML and footage live in the sibling repo `../hitreg-ml` (Python 3.14 + uv, PyTorch, coremltools). It holds the videos, label CSVs, the splits, and the trained Create ML swing classifier. Tests find it via `REPS_ML_DIR`. See ADR 0007.
- Voice is English only.

## Feature workflow

Every roadmap issue goes through the same pipeline. Use the agents in `.claude/agents/`; model and effort are pinned there.

1. **Branch**: `feat/<issue>-<slug>` from `main` (`fix/…`, `docs/…` for other kinds).
2. **Plan**: `opus-planner` (Opus, high). Use `fable-planner` (Fable, high) instead when the issue has the `plan:fable` label or touches auth, permissions, privacy, or data leaving the device. Output: `docs/plans/<issue>-<slug>.md`.
3. **Implement**: `sonnet-implementer` (Sonnet, high) follows the plan and nothing more.
4. **Review** (only when warranted, see the issue labels):
   - `review:opus` → `opus-reviewer` (Opus, high): correctness and design, for logic-heavy work (session engine, detectors, fusion, pipelines).
   - `review:fable-security` → `fable-security-reviewer` (Fable, high): permissions, file paths, Photos, sharing, anything that stores or exports user data.
   - Neither label → no review. Simple UI and docs skip it.
5. Fix review findings, then verify locally, commit, push, and open a PR that closes the issue.

Small fixes and docs changes don't need the plan step. Use judgement, and keep the plan step for anything touching logic across more than one file.

## Tools and skills

- **Always use Context7** (`resolve-library-id` → `query-docs`) before writing or planning against any framework API: SwiftUI, SwiftData, AVFoundation, Vision, Core ML, Create ML, PhotosKit, AVSpeechSynthesizer, XCTest/Swift Testing, xcodebuild. Apple APIs change every year. Don't trust memory.
- Use the matching skills instead of improvising:
  - `superpowers:brainstorming` before a new feature's design, `superpowers:writing-plans` for plans
  - `superpowers:test-driven-development` for detector and session-engine logic
  - `superpowers:systematic-debugging` for bugs, `superpowers:verification-before-completion` before claiming done
  - `figma:figma-design-to-code` / `figma:figma-swiftui` when building a screen from Figma
  - `engineering:architecture` for new ADRs
  - `code-review` / `security-review` in the review step
  - `superpowers:finishing-a-development-branch` when wrapping up a branch

## Testing: local only, only what the change deserves

- **No CI/CD.** Don't add GitHub Actions or any remote pipelines. Everything is verified locally.
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
# DetectorEval (footage from ../hitreg-ml; override with TEST_RUNNER_REPS_ML_DIR=/path, skips if not found)
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
- Source files go in the synced folders (`Reps/`, `ShotDetector/`, `RepsTests/`, `DetectorEvalTests/`); never edit `project.pbxproj` to add files. Signing: put `DEVELOPMENT_TEAM = …` in `Config/Signing.local.xcconfig` (gitignored).
- Only write tests for behaviour that matters: logic, state machines, math, detectors. Skip tests for pure layout.

## Code style

- Keep comments short, one line and only where the *why* isn't obvious. No doc-comment essays, no file headers.
- Real documentation lives in `docs/code-reference.md`: one entry per file, one line per public type/function. Update it in the same commit as the code.
- `ShotDetector` and everything under it stays free of AVFoundation so it runs against video files in tests (spec §4). Detectors take `VideoFrame`s through `ShotDetecting` (ADR 0010). Check: `grep -rnE 'import (AVFoundation|AVKit|UIKit|SwiftUI|CoreMedia)' ShotDetector` prints nothing.

## Commits and PRs

- Title: short, lowercase, imperative-ish, e.g. `implemented ball presence detector`.
- Body: one line at most, e.g. `added NCC patch matcher and state machine`. Then issue refs (`Closes #14`, `Refs #3`).
- No long AI-written descriptions, bullet lists, or summaries in commits.
- No attribution: no `Co-Authored-By`, no `Claude-Session`, no "Generated with Claude Code" in commits or PRs.
- PR: title same style, body is 1–3 lines plus `Closes #N`.
- Until the MVP ships, auto-merge your own PRs into `main` once local verification passes and any required review is fixed: `gh pr merge --squash --delete-branch`, then pull `main`.
- Update `docs/roadmap.md` status when an issue closes. Add new questions to `docs/open-questions.md` and decisions to `docs/adr/`.
