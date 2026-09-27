# Open questions

Answer inline, then move the decision to an ADR if it's architectural. Settled questions move to the Resolved table.

## Open

| # | Question | Blocks | Notes / leaning |
|---|---|---|---|
| Q19 | The range test split has 23 swings, 16 practice, 7 motion. Enough to gate ≥95 % recall and ≤1 false per 50? | #21 | No: one miss is −4 %. Leaning: record more range footage for the test split, or gate on test + val once the classifier is frozen. Two test swings hit < 2 s into their clip; a detector warm-up (e.g. ball lock ~1 s) can miss them for trimming reasons, so check miss times before reading recall. |
| Q20 | Swing classifier (ADR 0007) was trained on 2 s windows at 30 fps (60 poses); DetectorInput is 15 fps. | #18 | #18 must retrain at 15 fps, resample poses, or get 30 fps pose frames. |
| Q25 | When the launch "resume?" prompt is declined, keep the session (`finish`) or delete it (`discard`)? | #9, #11 | Leaning: keep (finish), since ADR 0006 already saved every shot; offer delete only from the log. #8 provides both. #9 ships the leaning: "End it" in the launch prompt calls resume + finish. #11 keeps #9's behaviour. #12 adds delete from the log (swipe, asks first). |
| Q26 | F2 says blocks advance automatically at target; F21 says targets are minimums and the count goes past. Should non-strict blocks auto-advance? | – (decided in #8, confirm) | #8: no. Minimums announce the target and stay; strict auto-advances (ADR 0013). Flip it in `recordShot` if the owner prefers F2 literally. |
| Q27 | Plans list order: creation date (now), most recently done, or manual drag order? | – (#7 ships creation order) | Manual order would need a `sortOrder` on PracticePlan (schema V2). Leaning: keep creation order unless it annoys in use. |
| Q28 | Free session start: which mode (and club) does "Free session" start in? #9 starts Range with the first bag club. | – (#9 ships Range) | Options: a small mode sheet before start, or the last-used mode. Leaning: last-used mode, stored in Settings (#6). |
| Q29 | Dim (§5.3c): in-app black overlay (shipped in #9) or lower system brightness (§5.6 "brightness low")? | #28 | System brightness persists after the app closes until the phone locks (UIKit docs), so it must be restored on background/kill. Leaning: keep the overlay; revisit in #28 if battery tests say otherwise. |
| Q30 | "Manual fixes" on the summary is Σ \|repsManualAdjust\| per block (net, so +1 then −1 counts 0). Count every +1/−1 tap instead? | – (#11 ships net) | Counting taps needs a new stored field (schema V2). Leaning: keep net; it's what §5.1 uses for detector accuracy. |
| Q31 | Figma 10 has a global "Save clips to Photos" toggle, but spec §5.8 says Photos saving is per clip and never automatic (40 clips would flood the roll). Which is it? | #26 | #6 stores the preference only (default off). Leaning: the toggle means "auto-save every clip", off by default, and per-clip save stays in the clip detail. |
| Q32 | Clip quality options: #6 offers 1080p60 (default), 1080p30, 720p30. Does capture (1080p60 for detection, §5.6) constrain these to export presets only? | #22 | #22 maps them to writer settings or trims the list. |
| Q33 | The session log (#12) was designed without a Figma frame. OK as built: "Log" at the top left of Plans, month sections of plan-style cards, a detail like the summary (no bars), swipe to delete? Also: should a plan card open that plan's history? | – (#12 ships this) | Choices listed in docs/plans/12-session-log.md. A Figma frame can follow once the owner has used it; per-plan history would reuse SessionLogView with a plan filter. |
| Q34 | Mic prompt timing: #5 asks at onboarding when Record audio is on and the camera was just granted (F20, Figma 09); #22 will ask in context if still undetermined. Keep the onboarding prompt, or defer entirely to the first clip with audio? | #22 | Apple's guidance is "only when the user invokes the feature". Leaning: keep; the screen explains it and the toggle gates it. If the owner prefers deferral, delete `asksMicrophoneOnFinish` from `allowAndFinish` and the row tap keeps working. |
| Q35 | Library delete removes the ShotRecord and its file, but not the session's rep counts (so the log still says 62 shots after deleting 10 clips). Should it only remove the clip (clear `clipFileName`) and keep the shot for stats/export? And is Undo alone (no alert) enough for bulk delete? | – (#24 ships row delete + undo) | Clearing only the file would keep tempo/timestamps; it's a one-function change in `LibraryEdits.delete`. |
| Q36 | The library's bulk mode (bottom bar: Club, Tags, ★, Delete), tag sheet and filter menus have no Figma frame; search also matches month/weekday names. OK as built? | – (#24 ships these) | Choices in docs/plans/24-video-library.md. A Figma frame can follow after use. |
| Q37 | F27 asks for "jump-to-event chips"; Figma 11 shows only marks on the track. #25 draws the marks and a release within 12 pt of one jumps to it. Only impact exists, assumed 3.0 s into the clip (§5.8 window). OK, or add a chip row (Address · Top · Impact · Finish) once #27 has the pose events? | #27 | #22 should store the real impact offset per clip (`ClipPlayback.events(duration:impactOffset:)` takes it); chips would be one HStack of buttons calling `player.seek`. |
| Q38 | Figma 15 says "The shot stays counted; only the video is removed", but delete from the player uses #24's path, which removes the ShotRecord row too (counts stay). Same choice as Q35, row delete, or clear `clipFileName` and keep the shot? | – (#25 ships row delete) | Changing `LibraryEdits.delete` fixes both the library and the player; the alert copy is a PLACEHOLDER until then. |
| Q39 | Callout wording beyond §5.7: minimums target "Target reached.", strict "Stop. Block done.", plan end "End of plan.", a block with shots already "9 iron. 12 of 30.". §5.7's "Done. Session saved." now plays on Done, not at plan end (only Done saves). OK? | – (#10 ships these) | All four are `PLACEHOLDER` constants in `VoiceLines`. |
| Q40 | "Announce count" off silences only the count; block, stop, plan-end and saved callouts still speak. Add a master "Voice" toggle? | – (#10 ships counts-only) | A master toggle is one more `AppSettings` key checked first in `SpeechAnnouncer.handle`. |
| Q41 | Voice with clip audio (#22): recording needs `.playAndRecord` and a session that stays active, so music stays ducked the whole session and callouts ("twelve") are recorded into every clip's sound. Accept, or mute callouts while a clip window is open? Also `AVCaptureSession.automaticallyConfiguresApplicationAudioSession` must be false or speech may move to the earpiece. | #13, #22 | `VoiceAudioSession` is the single place to change. Alternative: `AVSpeechSynthesizer.usesApplicationAudioSession = false` lets the system manage speech separately; ducking behaviour then needs a device test. |
| Q42 | Podcasts/audiobooks duck under the callouts like music. Pause spoken audio instead (`.interruptSpokenAudioAndMixWithOthers`, Apple's advice for exercise apps)? | – | Pausing every ~10 s on the range seems worse than ducking. One option in `VoiceAudioSession.configure`. |

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
| Q22 | Can surplus on one block cover another | No. Session completion caps each block at its target (45/30 + 15/30 = 75 %); per-block completion still shows over-target. Change `Completion` in #11. | `Completion.session`, spec §5.1, ADR 0012 (#11) |
| Q24 | Snapshot plan rules on the session | Yes: the session keeps `isStrictCount`, `isOrderMandatory` and the active block, so resume works after the plan is edited or deleted. | ADR 0013 |
| Q23 | Can a `#Predicate` filter on `tags: [String]`? | No. Spiked on iOS 27 and 26.5 with an SQLite store: every tag predicate (`contains`, AND, `isEmpty`, `allSatisfy`, composed `evaluate`) crashes the fetch; tags are an encoded blob. The library fetches `clipFileName != nil` by timestamp and filters tags (AND) and everything else in memory. No Tag model needed at this scale. | ADR 0013, docs/plans/24-video-library.md |
| Q13 | Which Figma frames are current | The Figma file has one page for this project, and all of it is current. | docs/design.md |
