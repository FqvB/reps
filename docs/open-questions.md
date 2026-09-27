# Open questions

Answer inline, then move the decision to an ADR if it's architectural. Remove a question once it's settled.

| # | Question | Blocks | Notes / leaning |
|---|---|---|---|
| Q1 | Minimum iOS version: 18 or 26? | #1 | Personal use on an iPhone 15 Pro, so 26 is fine. It unlocks the newest SwiftData/Vision APIs, and there's no reason to support older versions. |
| Q2 | Final app name and bundle ID | #1 | Working title "Reps". |
| Q3 | Apple Developer Program ($99) or free provisioning? | #1, install in Phase 1 | Free provisioning builds expire after 7 days, which means reinstalling every week. |
| Q4 | Where does test footage live? It's too big for git. | #2, #3 | Leaning: a local folder outside the repo (e.g. `~/RepsFootage`), passed to DetectorEval via env var, with the ground-truth JSON kept in the repo. Alternative is Git LFS, but the free quota is small. |
| Q5 | Ground-truth format | #2, #3 | Leaning: one JSON per video with a scenario tag and a list of `{t, kind: shot\|practice\|retee\|pickup}`. |
| Q6 | "Persisted after every shot" (§6) vs "ending never saves until Done" (F28) | #4, #8 | Leaning: persist continuously with a `status: active\|finished` flag. Done flips it, and an active session on launch triggers "resume?". |
| Q7 | Uncertain shots are "flagged in the log" (§5.4), but `ShotRecord` has no flag field | #4, #19 | Add `isUncertain: Bool` (or a confidence value) now to avoid a migration later. |
| Q8 | Clip file names use `<club>-<angle>`, and club names are user text | #22 | Leaning: UUID file names, with club/angle kept only in SwiftData. This avoids path issues and keeps renames free. |
| Q9 | 2D pose (`VNDetectHumanBodyPoseRequest`) or 3D pose for tempo/events? | #17, #27 | Start with 2D per spec, and revisit if face-on vs DTL tempo disagree. |
| Q10 | Formatter/linter: `swift-format` (ships with Xcode) or SwiftLint? | #1 | Leaning: swift-format, no extra dependency. |
| Q11 | Create ML training data: how many labelled swings, and labelling tool? | #18 | Probably clips from Phase 1–2 sessions plus footage. Decide the minimum set before #18. |
| Q12 | Voice language and number format (English only?) | #10 | Assume English. |
| Q13 | Which Figma pages/frames are final (v9) vs older iterations? | UI issues | See `docs/design.md`. Needs the Figma MCP authenticated. |
