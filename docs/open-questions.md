# Open questions

Answer inline, then move the decision to an ADR if it's architectural. Settled questions move to the Resolved table.

## Open

| # | Question | Blocks | Notes / leaning |
|---|---|---|---|
| Q14 | Putting footage and ground truth don't exist yet (hitreg-ml is range only) | #14, #16 | Record the §7 putting script: 50 putts, 10 waggles over the ball, 5 pickups. Label with `tools/label.py` (kinds `putt`, `motion`). |
| Q15 | The ground truth has no explicit "ball gone, no swing" rows (re-tee, pickup, basket) | #14, #19 | `motion` covers some of it. Decide whether to add a `retee`/`pickup` kind, or keep `motion` and note it in the manifest. |
| Q16 | Ship the Create ML `.mlmodel` in the app repo or copy it at build time from hitreg-ml? | #18 | 4 MB. Leaning: copy the chosen version into the app repo with its source version in the file name. |

## Resolved

| # | Question | Answer | Recorded in |
|---|---|---|---|
| Q1 | Minimum iOS | iOS 26 | CLAUDE.md |
| Q2 | App name / bundle ID | Reps, `com.fqvb.reps` | CLAUDE.md |
| Q3 | Signing | Paid program applied (pending). Use free provisioning until approved (7-day builds). | CLAUDE.md |
| Q4 | Footage location | `~/Documents/Programming/GitHub/hitreg-ml/data/` (raw videos, labels, keypoints). Stays out of this repo. DetectorEval reads it via the `REPS_ML_DIR` env var. | ADR 0007 |
| Q5 | Ground-truth format | hitreg-ml's existing format: `data/labels/<video>.csv` (`frame,seconds,kind`, kind ∈ swing/practice/motion), `data/manifest.csv` (angle, light, fps), `data/splits.json` (train/val/test). | ADR 0007 |
| Q6 | Persist per shot vs save on Done | Persist continuously with `status: active \| finished`. Done sets `finished`. An `active` session found at launch triggers "resume?". | ADR 0006 |
| Q7 | Uncertain-shot flag | No flag or confidence stored. Shots near the threshold still count (spec §5.4), and the +1/−1 buttons correct them. | ADR 0006 |
| Q8 | Clip file names | UUID file names. Club and angle live only in SwiftData. | ADR 0006 |
| Q9 | 2D vs 3D pose | 2D `VNDetectHumanBodyPoseRequest`, 13 joints, same as hitreg-ml's extractor. | ADR 0007 |
| Q10 | Formatter | swift-format | CLAUDE.md |
| Q11 | Classifier training data | Already done in hitreg-ml: Create ML action classifier `hitreg_ml 1.mlmodel` (swing vs other, 2 s windows @ 30 fps). Practice swings count as swing, and `motion` rows are hard negatives. | ADR 0007 |
| Q12 | Voice language | English | – |
| Q13 | Which Figma frames are current | The Figma file has one page for this project, and all of it is current. | docs/design.md |
