# Golf Rep Counter — MVP Design Doc

Working title: **Reps** (rename whenever). Status: draft v9, 2026-09-17 (v9: ball-gated fusion; v8: dark full-bleed clip player; v7: microphone removed from detection; v6: frame-by-frame review, accident-proofing states; v2: free sessions, library + tags, tempo, Create ML path; v3: order toggle, coach system noted; v4: white theme, custom bag, onboarding, clickable prototype; v5: minimums + strict count, session summary, swipe to delete, settings, clip detail).

Figma: [https://www.figma.com/design/pMKE8PoWxIEotHas0rmQX1](https://www.figma.com/design/pMKE8PoWxIEotHas0rmQX1)

Audience: Emils, building this for personal use first. iOS only.

## 1. Problem

Structured practice means hitting a fixed number of shots per club (e.g. 40 × 8-iron, 30 × 9-iron) and a fixed number of putts per drill. Counting by hand is unreliable and breaks focus. A phone on a tripod already sits there for swing video, so it should also do the counting and tell you the count out loud.

## 2. Requirements

### Functional

| ID | Requirement | MVP |
|---|---|---|
| F1 | Create practice plans: an ordered list of blocks, each with club, target reps, optional note (e.g. target distance) | Yes |
| F2 | Run a plan as a session; advance block automatically when target reps reached | Yes |
| F3 | **Mode 1 — Range Counter**: detect each shot from the camera, no recording | Yes |
| F4 | **Mode 2 — Range Counter + Clips**: same as Mode 1, plus save a trimmed video clip of every counted shot | Yes |
| F5 | **Mode 3 — Putting Counter**: stationary phone on the mat, count every putt struck | Yes |
| F6 | Voice announces the count after every rep ("twelve"), and the block change ("nine iron, thirty reps") | Yes |
| F7 | Manual +1 / −1 buttons as a fallback when detection misses | Yes |
| F8 | Session log: date, plan, per-block reps, duration, clips | Yes |
| F9 | Choose camera angle preset (face-on / down-the-line) — affects only the setup guide overlay and clip label | Yes |
| F10 | Audio impact detection | **No.** The microphone is only used to record sound on clips — see §3.2 |
| F11 | Voice control ("next drill") | No — later |
| F12 | Made-putt detection (ball enters hole) | No — later |
| F13 | Android, cloud sync, sharing, launch-monitor data | No |
| F14 | **Free session**: start counting/recording without a plan; a "current club" chip at the top of the screen tags every following shot until changed. If you forget to change it, clips are simply tagged with the wrong club and can be fixed in bulk later | Yes |
| F15 | **Video library**: every clip, filterable by club, angle, date, session, and custom tags. Bulk-select to retag, favourite, or delete | Yes |
| F16 | **Custom tags** set while recording (e.g. "fade", "gate drill") apply to every shot until removed, same as the club chip | Yes |
| F17 | **Swing tempo** (backswing : downswing ratio) computed from pose per shot, shown on the clip and optionally spoken with the count | Yes |
| F18 | **Order toggle per plan**: "Order is mandatory" off (default) lets you jump to any block from the session's block strip and come back later; on locks the sequence. A block is complete when its count reaches target regardless of the order it was done in | Yes |
| F19 | **Your bag**: a user-defined club list set during onboarding (defaults to a common 14) and editable in Settings; the plan editor's club picker shows only these clubs, plus custom-named clubs | Yes |
| F20 | **Onboarding**: three screens — welcome, your bag, camera/microphone permissions with default angle | Yes |
| F21 | **Targets are minimums**: a block's target is the minimum, not a cap. Keep hitting and the count goes past target; completion is reported as a percentage and can exceed 100% | Yes |
| F22 | **Strict count toggle per plan**: on, a block ends exactly at target and the voice tells you to stop (test drills); off (default), targets are minimums (warm-ups, volume work) | Yes |
| F23 | **Session summary** on End: overall completion %, per-block done/target with %, clips saved, average tempo, manual fixes; "Keep going" returns to the session, "Done" saves | Yes |
| F24 | **Swipe to delete** a block in the plan editor, with undo via the standard iOS toast | Yes |
| F25 | **Settings**: my bag, default angle, clip quality, save-to-Photos, record audio on clips, voice toggles, storage, version | Yes |
| F27 | **Frame-by-frame review** on the clip detail: filmstrip, single-frame step, ¼/½/1× speed, and jump-to-event chips (address, top, impact, finish) placed by the pose model | Yes |
| F28 | **Accident-proofing**: ending a session never saves until Done, and the summary has Continue session; Next block before target asks first; Cancel with unsaved plan edits asks first; deleting a clip asks first; deleting a block gets an undo toast | Yes |
| F26 | **Voice guidance** beyond the count ("keep going", "last five", "stop", "next block") | Later — design last, after the counter is trusted |

### Non-functional

- Detection accuracy on the range: ≥ 95% of real shots counted, ≤ 1 false count per 50 shots. Below that the manual buttons get used more than the camera and the app is pointless.
- Latency from impact to voice callout: < 1.5 s.
- Must survive a 90-minute range session outdoors. Onform runs continuous pose + auto-clipping on the same iPhone 15 Pro all session without visible throttling, so this is achievable; the budget in §5.6 is the discipline that keeps it that way.
- One-handed, glove-on usability: every action during a session is a large tap target; the live screen shows one big number and one chip.
- Works fully offline. All data on device.
- Zero cost to run (no backend).

### Constraints

- Solo developer, evenings/weekends around uni and golf.
- Existing skills: Python, TypeScript, React Native/Expo. New to Swift; learning it is part of the project.
- Hardware: iPhone 15 Pro, MacBook Pro (M5 Pro), one tripod. Right-handed golfer (matters only for setup overlays).

## 3. Key decisions

### 3.1 Native Swift, not React Native

This app is 80% camera pipeline and on-device vision. React Native would need a native frame-processor plugin in Swift anyway, so you'd be writing Swift plus a bridge layer plus fighting Expo's camera abstractions. Go straight to **Swift + SwiftUI + AVFoundation + Vision**. Learning cost is real (2–3 weeks to get comfortable) but it removes an entire layer of problems.

Trade-off: you lose your RN productivity for the UI screens. The UI here is small — plan editor, session screen, log — so that's a cheap loss.

### 3.2 Detection by fusion, not by color

Color detection was the original idea; drop it. Onform's auto-detect (the benchmark you named) works from the golfer's body — it's a trained ML model that recognises the swing motion, which is why it ignores re-tees and why it's iOS-only (it leans on Apple's Vision/Neural Engine). We do the same, with one extra signal they don't need because they only record, they don't count:

| Signal | What it answers | Source |
|---|---|---|
| **Swing event** | "Did a full swing just happen?" | Vision body pose (`VNDetectHumanBodyPoseRequest`) → a trained classifier on keypoint windows. Create ML Action Classifier first, own PyTorch model second (see the ML roadmap). The wrist heuristic in §5.3 is only the day-one baseline |
| **Ball absence** | "Did the ball leave?" | Small region around the ball the user taps once at setup; compare against a reference patch |

**Shot = swing event AND ball gone within ±0.5 s of the swing's low point.**

**The camera is king.** There is no audio signal in the decision. Impact sound was considered and rejected: wind swamps it, a golfer two metres away in the next bay produces identical strikes, and a clean strike on a mat is quieter than a fat one. Any rule that lets the microphone confirm or veto a shot adds a failure mode the camera doesn't have. The microphone is used for exactly one thing: recording audio on the clips.

This kills the two failure cases in one rule:

- Practice swing → swing event, ball still there → not counted.
- Re-tee / rake ball over / pick up ball → ball gone, no swing → not counted.

Putting mode doesn't need pose at all: the phone is stationary on a mat, so ball absence alone is the count.

### 3.3 Continuous record + cut, not ring buffer

For clips: record the camera continuously to rolling temp files (e.g. 60 s segments). When a shot is counted, export the range [impact − 3 s, impact + 2 s] to a permanent clip with `AVAssetExportSession`, then delete old segments. A frame ring buffer in memory is the "smarter" design but 1080p60 × 5 s is ~1 GB of raw frames; not worth it for an MVP.

## 4. High-level design

```
┌─────────────────────────────────────────────────────────────┐
│ SwiftUI                                                      │
│  PlanEditor   SessionScreen (live count, +1/−1)   SessionLog │
└──────────────┬──────────────────────────────────────────────┘
│ observes
┌──────────────▼──────────────────────────────────────────────┐
│ SessionController                                            │
│  - current plan / block / rep count                          │
│  - takes ShotEvents, advances blocks, triggers voice + clip  │
└──────┬───────────────┬──────────────────┬───────────────────┘
│               │                  │
┌──────▼──────┐ ┌──────▼────────┐ ┌───────▼─────────┐
│ VoiceOutput │ │ ClipWriter    │ │ SessionStore    │
│ AVSpeech-   │ │ rolling temp  │ │ SwiftData:      │
│ Synthesizer │ │ files + export│ │ plans, sessions │
└─────────────┘ └──────▲────────┘ └─────────────────┘
│ raw camera stream
┌──────────────────────┴──────────────────────────────────────┐
│ CameraPipeline (AVCaptureSession, 1080p60)                   │
│   every frame  ──► ClipWriter                                │
│   every Nth frame, downscaled ──► ShotDetector               │
└──────────────────────┬──────────────────────────────────────┘
│
┌──────────────────────▼──────────────────────────────────────┐
│ ShotDetector (pure logic, testable against video files)      │
│   SwingDetector (pose) ─┐                                    │
│   BallPresenceDetector ─┼─► Fusion state machine ─► ShotEvent│
│                          (no audio input)                    │
└─────────────────────────────────────────────────────────────┘

```

Design rule: **ShotDetector takes frames in and emits events out, with no dependency on AVFoundation.** That makes it runnable against saved videos in unit tests, which is how the algorithm actually gets tuned.

## 5. Deep dive

### 5.1 Data model (SwiftData)

```
// A reusable template, e.g. "Wedge day"
@Model class PracticePlan {
var name: String
var mode: PracticeMode           // .rangeCounter, .rangeCounterWithClips, .putting
var isOrderMandatory: Bool       // false = blocks can be done in any order
var isStrictCount: Bool          // false = targets are minimums; true = stop exactly at target
var blocks: [PlanBlock]          // ordered
var createdAt: Date
}

// The user's bag, set in onboarding, edited in Settings. Feeds the plan editor's club picker.
@Model class BagClub {
var name: String                 // "7 iron", "4 hybrid", or a custom name
var sortOrder: Int
var isInBag: Bool                // false = hidden from pickers but kept so old plans still resolve
}

@Model class PlanBlock {
var clubName: String             // "8 iron", "Putter"
var targetReps: Int
var note: String?                // "150m, fade"
var order: Int
}

// One run of a plan on a given day, or a free session with no plan
@Model class PracticeSession {
var plan: PracticePlan?           // nil = free session
var startedAt: Date
var endedAt: Date?
var cameraAngle: CameraAngle     // .faceOn, .downTheLine, .none (putting)
var blockResults: [BlockResult]
}

// In a planned session this mirrors a PlanBlock; in a free session a new one
// starts every time the club chip or tag set changes.
@Model class BlockResult {
var block: PlanBlock?
var clubName: String
var repsCounted: Int
var repsManualAdjust: Int        // net of +1/−1 taps, kept separate for accuracy tracking
var shots: [ShotRecord]
}

@Model class ShotRecord {
var timestamp: Date
var detectedBy: DetectionSource  // .camera, .manual
var clubName: String             // copied from the block so retagging one shot is cheap
var tags: [String]               // "fade", "gate drill" — inherited from the active tag set
var isFavourite: Bool
var tempoRatio: Double?          // backswing duration / downswing duration, e.g. 3.0
var clipFileName: String?        // relative path in app Documents
}

```

Club and tags are stored on every shot rather than only on the block, so bulk retagging in the library is a simple update over the selected shots, and library filters are one predicate.

Completion for a block is `(repsCounted + repsManualAdjust) / targetReps`, uncapped, so 45 of 30 reports 150%. Session completion is total done over total target, also uncapped.

Keeping `repsManualAdjust` separate is deliberate: it tells you the detector's real-world accuracy for free, straight from the log.

### 5.2 Ball presence detector

1. **Setup**: user taps the ball on screen. App takes a square region ~3× the ball's apparent diameter, stores it as the reference patch, and shows a small green box.
2. **Per frame** (downscaled, ~15 fps): compute similarity between the current patch and the reference (normalised cross-correlation is enough; start there, no ML).
3. **States**:

  - `present` — similarity above threshold
  - `occluded` — similarity below threshold *and* significant motion inside the region in the last ~200 ms (hand, club head, shadow moving). No decision made.
  - `absent` — similarity below threshold with no motion for K consecutive frames (K = 3 at 15 fps ≈ 200 ms).

4. **Re-arm**: after `absent`, wait for `present` to hold for ≥ 1 s before it can emit again. Stops a rolling ball or a re-tee from double-counting.

The occlusion state matters most for putting, where the putter head sits over the ball before every stroke.

Known weak spots: strong shadows sweeping across the region (clouds, your own body), and range mats with a texture that resembles the ball. Mitigation is the reference-patch approach plus re-tapping the ball if the box goes red; don't over-engineer before the test footage says you need to.

### 5.3 Swing detector (range modes only)

Run `VNDetectHumanBodyPoseRequest` on the same downscaled frames. Track the wrist midpoint (average of both wrists) over the last 2 s.

A swing event fires when this sequence happens within ≤ 2 s:

1. wrist midpoint rises above shoulder height (top of backswing),
2. then drops below hip height fast (downswing),
3. then rises again (follow-through).

Emit the timestamp of step 2's lowest point as the **impact estimate**.

This heuristic will be ~90% right and take one evening. It is the baseline the trained classifier has to beat; the ML roadmap covers replacing it with Create ML and then your own model.

### 5.3a Tempo

Free once pose is running. From the wrist-midpoint track around a counted shot:

- **takeaway** = first frame the wrists move away from address by more than a small threshold
- **top** = frame of maximum wrist height before impact
- **impact** = the classifier's impact estimate, refined to the frame of lowest wrist point

`tempoRatio = (top − takeaway) / (impact − top)`. Tour reference is about 3:1. Display to one decimal on the clip; speak it only if the setting is on ("twelve, three point one"). Putting mode: skip.

### 5.3b Video library and tags

- One screen: a grid of clip thumbnails, newest first, with a filter bar (club, angle, date range, session, tag, favourites). Filters are `AND`.
- Every clip shows club, angle, tempo, and tags on its thumbnail.
- Bulk mode: long-press → multi-select → retag club, add/remove tag, favourite, delete. This is the fix for "forgot to change the chip for 40 shots."
- Tags are free text with autocomplete from your history; no tag management screen in the MVP.
- Clip detail is the one dark screen in the app, modelled on Onform's player: the video fills the screen edge to edge, and every control floats over it in translucent pills. Top: close, favourite, share, more (tags, delete, save to Photos live under "more"). Bottom: a filmstrip scrubber with a yellow playhead, the time in seconds, and event marks on the track (address, top, impact in red, finish), then a row with speed, previous-frame / play / next-frame, and overlay options. Frame stepping is the point of the screen; nothing else competes with it. Event positions come from the same pose track that computes tempo.

### 5.3c Quality of life that isn't on a screen

- Plans list: swipe a plan for Duplicate / Delete; delete asks first.
- Onboarding bag screen has "Use the default bag" so a first session is two taps away.
- Session screen keeps the display awake and dims after 30 s; any tap restores it.
- Undo toast lasts 5 s for block deletion and bulk library actions.
- Thumbnails are generated once at export time (impact frame) and cached; the grid never decodes video.

### 5.4 Fusion: gate on the ball

The ball watcher runs every frame; it's cheap. The pose model runs only when asked. The pose buffer (last ~1.5 s of normalised keypoints) is kept continuously but not classified.

```
idle ──(ball present ≥1s)──► armed
armed ──(ball absent, confirmed over K frames)──► classify the pose buffer ending at the exit time
model says swing, impact within ±0.5 s of ball exit ──► SHOT COUNTED ──► idle
model says no swing (re-tee, pickup, rake, gust) ──► idle, nothing counted

```

Consequences:

- Practice swings never reach the model — the ball stays, so nothing is asked. They cost no false positives and need no special handling.
- The model's only job is recall on real swings plus rejecting the few motions that coincide with a ball leaving: bending to re-tee, picking the ball up, raking a fresh one over. That's a small, recordable negative set.
- The model runs a few dozen times a session instead of 15 times a second. Battery and heat drop with it.
- The ball watcher is now load-bearing, not a helper. It gets its own test matrix: shadow sweeping the box, mat texture, yellow tee markers, ball rolled a few centimetres by the club at address.
- If the model is unsure (probability near threshold), count the shot anyway and flag it in the log; a missed shot annoys more than a rare extra one, and the +1/−1 buttons exist.

### 5.5 Putting mode

Same `BallPresenceDetector`, no pose, tighter thresholds:

- putt = `present → occluded → absent`, absent held ≥ 300 ms
- re-arm when a ball is present ≥ 1 s
- announce count; block advances at target reps

Made/missed detection is explicitly out of scope; a second region at the hole is the obvious later extension.

### 5.6 Camera + thermal budget

- Capture at 1080p60 (clips look good, slow-mo works). Detection processes every 4th frame, downscaled to ~480 px wide. That's 15 fps of vision work, which a recent iPhone handles on the Neural Engine comfortably.
- Watch `ProcessInfo.thermalState`. At `.serious`: drop to every 6th frame and stop showing the live preview (keep a black screen with the count). At `.critical`: stop clips, keep counting.
- `isIdleTimerDisabled = true`, brightness low. Screen only needs to show a big number.
- Mode 1 should be noticeably cooler than Mode 2 because it never writes video. That's the point of having Mode 1.

### 5.7 Voice

`AVSpeechSynthesizer`, pre-warmed at session start. Utterances queued, never overlapping. Count after each rep; on block change: "Nine iron. Thirty reps." At plan end: "Done. Session saved."

### 5.8 Clips

- Rolling 60 s temp segments via `AVAssetWriter`.
- On shot: export [impact − 3 s, impact + 2 s] → `Documents/clips/<sessionId>/<index>-<club>-<angle>.mov`.
- Delete temp segments older than 2 min.
- Optional "Save to Photos" per clip from the log screen (one call to `PHPhotoLibrary`). Not automatic — 40 clips a session would flood the camera roll.

## 6. Error handling

| Failure | Behaviour |
|---|---|
| Ball box drifts / lighting shifts | Box turns red; tap ball again. Count continues via manual buttons. |
| Pose not found (you walked out of frame) | Detector idles; overlay says "step into frame". No false counts. |
| Thermal critical | Clips stop, counting continues, one voice warning. |
| Export fails | Shot still counted; `clipFileName` nil; retry once, then log. |
| App killed mid-session | Session persisted after every shot; reopens with a "resume?" prompt. |
| Phone call / Siri / notification interrupts the camera | Capture pauses, count is kept, voice says "paused"; resumes when the app is foregrounded. |
| Battery under 15% during a session | One voice warning; clips stop at 10%, counting continues. |
| Voice callouts while music plays | Callouts duck other audio (`AVAudioSession` `.duckOthers`) rather than stopping it. |
| Camera or mic permission denied at onboarding | Explain what stops working and deep-link to Settings; manual counting still works. |
| Ball box turns red for > 10 s | Voice: "Lost the ball — tap it again." |

## 7. Validation plan (do this before writing detection code)

**Milestone 0 is footage, not code.** Record on your actual range and mat:

- Range, down-the-line: 40 shots, including 10 practice swings, 5 re-tees, 3 chunks that move the ball a metre, one basket dropped next to the ball.
- Range, face-on: same script.
- Putting mat: 50 putts, including 10 where the putter waggles over the ball, 5 where you pick it up.
- Two lighting conditions (overcast and low sun with long shadows).

Write the ground-truth counts down while recording. Every version of `ShotDetector` runs against these files in an XCTest target and reports precision/recall per scenario. Tune thresholds against that, not by standing on the range with Xcode open.

## 8. Milestones

| # | Deliverable | Why this order |
|---|---|---|
| M0 | Test footage + ground truth | Everything else is guessing without it |
| M1 | Plans, free session, club chip + tags, manual counter, voice, session log | Usable on the range immediately with a tap per shot |
| M2 | Putting Counter (ball presence only) | Simplest vision path; proves the camera pipeline |
| M3 | Range Counter: Vision pose + Create ML classifier + fusion | The hard part, built on a working pipeline; Create ML gets it working in days |
| M4 | Clips + video library with filters and bulk retag | Adds the recording layer once counting is trusted |
| M5 | Tempo, thermal handling, polish | Cheap once pose exists |
| M6 | Replace Create ML with your own trained model | Only if it beats Create ML on the event metric |

M1 alone is already better than what you have. Ship it to your own phone in week two and start logging sessions while the vision work continues.

## 9. Trade-offs made explicit

| Decision | Chosen | Alternative | Cost of the choice |
|---|---|---|---|
| Platform | Native Swift | React Native + native plugin | Learning Swift; slower UI at first |
| Swing detection | Pose heuristic | Create ML classifier | Lower ceiling; upgrade path is clear |
| Ball detection | Tapped reference patch | Trained ball detector (YOLO-style) | Needs a re-tap when lighting shifts; zero training data needed |
| Clips | Record + cut | Frame ring buffer | Extra disk churn; far simpler |
| Storage | SwiftData, local only | Cloud sync | No backup beyond iCloud device backup |
| Putting makes | Out of scope | Hole region | You count strokes, not makes, for now |

## 10. What to revisit if it grows beyond you

- **Detection**: swap the pose heuristic for a Create ML action classifier trained on your accumulated clips; swap the reference patch for a real ball detector so setup needs no tap.
- **Putting makes**: second region at the hole; "made" = ball absent at start region *and* transient presence at hole region.
- **Sync/export**: CloudKit is the cheapest path since the data model is already SwiftData.
- **Plans as a product**: this is the part other golfers would pay for — plan templates, progression, history charts. The counter is plumbing.
- **Coaches** (explicitly post-MVP): a coach account linked to a player sees their plans, daily completion percentage per plan, and clips the player chooses to send. This is the first feature that needs a backend and accounts; everything above it stays local-only, so design the data model so plans and sessions can be exported as JSON without changes.
- **Android**: would need a full rewrite of the vision layer (MediaPipe pose, CameraX). Don't plan for it.
