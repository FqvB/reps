# Open questions

Answer inline, then move the decision to an ADR if it's architectural. Settled questions move to the Resolved table.

## Open

| # | Question | Blocks | Notes / leaning |
|---|---|---|---|
| Q19 | The range test split has 23 swings, 16 practice, 7 motion. Enough to gate ≥95 % recall and ≤1 false per 50? | #21 | No: one miss is −4 %. Leaning: record more range footage for the test split, or gate on test + val once the classifier is frozen. Two test swings hit < 2 s into their clip; a detector warm-up (e.g. ball lock ~1 s) can miss them for trimming reasons, so check miss times before reading recall. |
| Q20 | Swing classifier (ADR 0007) was trained on 2 s windows at 30 fps (60 poses); DetectorInput is 15 fps. | #18 | #18 must retrain at 15 fps, resample poses, or get 30 fps pose frames. |
| Q23 | Can a `#Predicate` filter on `tags: [String]` (ShotRecord/BlockResult) against the SQLite store? | #24 | Tag filtering is required (owner). Spike first in #24; if the predicate fails, use a Tag model (many-to-many) or filter in memory after the other predicates. |
| Q25 | When the launch "resume?" prompt is declined, keep the session (`finish`) or delete it (`discard`)? | #9, #11 | Leaning: keep (finish), since ADR 0006 already saved every shot; offer delete only from the log. #8 provides both. |
| Q26 | F2 says blocks advance automatically at target; F21 says targets are minimums and the count goes past. Should non-strict blocks auto-advance? | – (decided in #8, confirm) | #8: no. Minimums announce the target and stay; strict auto-advances (ADR 0013). Flip it in `recordShot` if the owner prefers F2 literally. |

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
| Q14 | Putting approach | Phone on the ground, face-on. Ball gone ≥ 300 ms = stroke, no pose, no occlusion state. A pickup counts too (fix with −1). | ADR 0008 |
| Q15 | Re-tee/pickup ground truth | `motion` rows are the re-tee/pickup events. They must not count, and they're the hard negatives. | ADR 0007 |
| Q16 | Where the Create ML model lives | Copied into this repo as `ml/models/SwingClassifier_hitreg_ml1.mlmodel` (4 MB). The suffix names its hitreg-ml source version. | ADR 0007 |
| Q17 | Putting eval footage | Recorded 2026-09-27: one indoor clip, 19 putts + 15 motion + 3 pickup, in hitreg-ml `data/putting/` (`tools/label_putt.py`, kinds putt/pickup/motion). Threshold gets set in #16. | ADR 0007 |
| Q18 | Ball region for eval footage | Not needed: detectors auto-locate the ball (putting: newest ball still ~1 s anywhere; range: near the feet via pose). | ADR 0011 |
| Q21 | What −1 does | Deletes the latest ShotRecord (and its clip file) when there is one, which lowers the count; with no shot to delete it decrements `repsManualAdjust`. Never below zero. | ADR 0013 |
| Q22 | Can surplus on one block cover another | No. Session completion caps each block at its target (45/30 + 15/30 = 75 %); per-block completion still shows over-target. Change `Completion` in #11. | #11 plan |
| Q24 | Snapshot plan rules on the session | Yes: the session keeps `isStrictCount`, `isOrderMandatory` and the active block, so resume works after the plan is edited or deleted. | ADR 0013 |
| Q13 | Which Figma frames are current | The Figma file has one page for this project, and all of it is current. | docs/design.md |
