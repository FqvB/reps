# #25 Clip detail player

Goal: replace #24's `TODO(#25)` placeholder with the dark full-bleed clip player of Figma 11: floating translucent pills, a filmstrip scrubber with a yellow playhead, time in seconds, an event track, ¼/½/1× speed, previous-frame / play / next-frame, favourite, tags and delete (Figma 15 confirm alert). A missing clip file (every clip until #22) shows a placeholder state instead of crashing.

Spec: F27, §5.3b (clip detail paragraph), §5.8 (clip window), F28 ("deleting a clip asks first"). ADRs: 0006 (clip paths), 0009 (MainActor default, synced folders), 0013 (save, then files). Figma: 11 Clip detail `12:108`, 15 delete alert `18:105`.

**Base: `main` after #24 is merged** (branch `feat/25-clip-detail`). If `LibraryView`, `LibraryClip`, `LibraryEdits`, `LibraryTagSheet`, `ClipThumbnails`, `ClipStorage.clipURL`, `Theme.thumbnail`/`Theme.favourite` or `ClipDetailPlaceholderView` differ from #24's plan (`docs/plans/24-video-library.md`), stop and report.

**How this was checked.** All files below were written into a copy of main + #24 (the copy #24's plan was verified in), formatted with the repo's swift-format (`lint --strict` clean), built by Xcode with no new warnings, and `ClipPlaybackTests` (11) + `LibraryEditsTests` + `LibraryDisplayTests` passed on iOS 27 (A26BAE3A…); `ClipPlaybackTests` also on iOS 26.5 (6D2623EF…). Views were built, not run (no sample video exists). **Copy every file exactly.**

Out of scope: share and Save to Photos (#26, buttons present but disabled), tempo and the address/top/finish marks (#27), pose overlay and overlay options (#27, disabled), writing clips / real `ClipFileRemoving` (#22).

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Presentation | `fullScreenCover(item:)` from `LibraryView` (replaces #24's `NavigationStack(path:)` push; `path` goes away). | Figma 11 has a ✕ close, no back bar; the one dark screen shouldn't sit in a light nav stack. |
| Player | `AVPlayer` in an `@Observable` `ClipPlayer` (UI layer), drawn by `PlayerLayerView` (`UIViewRepresentable` over `AVPlayerLayer`, `.resizeAspect` on black). Not SwiftUI `VideoPlayer`. | `VideoPlayer` brings system controls we'd fight; every control here is custom (§5.3b). Aspect fit so the whole swing and club head stay visible; the pills float over the bars. |
| Time tracking | `addPeriodicTimeObserver` every 1/30 s on `.main` (`MainActor.assumeIsolated`); it also fires on start/stop, which sets `isPlaying` from `player.rate`. No KVO, no end notification (default `actionAtItemEnd = .pause`). Play on the last frame restarts from 0. | Fewest moving parts, no off-main callbacks (Context7: observer fires "when time jumps or playback starts/stops"). |
| Frame step | Pause, then a zero-tolerance seek (`seek(to:toleranceBefore: .zero, toleranceAfter: .zero)`) to `ClipPlayback.stepped`, which snaps to the frame grid (`1 / nominalFrameRate`, 60 fps fallback) and returns the **middle** of the target frame, clamped to the clip. Not `AVPlayerItem.step(byCount:)`. | Deterministic, testable, and the time label updates at once; middle-of-frame lands on the right frame whatever the exported PTS offset. |
| Speeds | `PlaybackSpeed` 1× → ½× → ¼× → 1× (F27), one pill cycles. `player.defaultRate` so `play()` keeps the speed; `rate` when already playing. | Figma 11 shows one "1×" pill. |
| Filmstrip | 10 frames (Figma) from `AVAssetImageGenerator.images(for:)` at slice middles, max 120 px, generated once per open in `ClipPlayer` (UI layer; never in ShotDetector). Grey-green `Theme.thumbnail` tiles until loaded or when missing. Drag/tap on the strip scrubs. | §5.3b; no cache needed for one screen. |
| Scrubbing | `DragGesture(minimumDistance: 0)` on strip and track: pause, exact seeks while dragging (a newer seek cancels the old one), final exact seek on release. | 5 s clips; exact seeks keep frames honest. |
| Events | Marks on the track per Figma 11 (impact red `Theme.danger`, others white). Only **impact** exists now, assumed **3.0 s in** (§5.8 cuts [impact − 3 s, impact + 2 s]) and only when inside the clip: `// PLACEHOLDER` + `TODO(#22)` to store the real offset. Address/top/finish: `TODO(#27)`. F27's "jump-to-event chips" = releasing within 12 pt of a mark jumps exactly to it (`ClipPlayback.snapped`). No separate chip row. | Model has no event times (`ShotRecord` only has `tempoRatio`). Figma 11 shows marks, not chips (new Q). |
| Label pill | `LibraryDisplay.tileTitle` + " · tempo 3.1 : 1" when tempo exists ("Gap wedge · face-on · tempo 3.1 : 1"). | Figma 11. |
| Favourite | ☆/★ pill toggles `LibraryEdits.setFavourite` on the one shot; saved at once, no toast (a second tap is the undo). | Reuses #24; §5.3c toast is for bulk. |
| Tags | "More" menu → Tags opens #24's `LibraryTagSheet` for one clip (`selectedCount: 1`), forced light. `LibraryEdits.addTag/removeTag`. | §5.3b "tags … live under more". |
| Delete | "More" → Delete → native `.alert` (Figma 15 copy, dark because the screen is dark). Confirm stops the player and closes it; `LibraryView` then runs **#24's `LibraryEdits.delete`** (rows, save, then files) + `ClipThumbnails.remove` in the cover's `onDismiss`. **No undo** (F28: asks first). | One delete path in the app; the model is never touched while the player still shows it; killed mid-dismiss = nothing deleted (safe direction). |
| Undo window | Opening a clip calls `finishUndo()` first (commits a pending bulk delete, drops the toast). | Otherwise a later bulk Undo would restore a snapshot over a favourite/tag change made in the player. |
| Errors | Player edits throw back into `ClipDetailView`, which shows its own alert (a presenter alert can't show over the cover). Delete errors show on the library after dismissal. Copy `// PLACEHOLDER (#29)`. | |
| Missing file | `ClipPlayer.state == .missing` when `clipURL` is nil (unsafe name / no session), the file doesn't exist, or it has no duration/video track: centred `video.slash` + copy, playback/scrubber disabled, top controls (close, ★, more → tags/delete) still work so an orphan can be removed. | No clips exist before #22; previews have none. |
| Icons | SF Symbols (`xmark`, `star`/`star.fill`, `square.and.arrow.up`, `ellipsis`, `backward.frame`, `play.fill`/`pause.fill`, `forward.frame`, `slider.horizontal.3`, `figure.stand`) instead of Figma's text glyphs/vectors. | Pause state isn't in Figma; symbols give VoiceOver-friendly, consistent weights. |
| Theme | Colours reuse `Theme.favourite` (#E6D35A playhead/progress/knob), `Theme.danger` (#D0463D impact), `Theme.thumbnail` (frames). New: `Theme.playerPill` (black 0.38), `Theme.playerTrack` (white 0.35), fonts and `ClipDetailMetrics` in `ClipDetailTheme.swift`. | Figma 11 values; no new hex. |
| Safe areas | Video and black background ignore safe areas; controls respect them (+8 top, as Figma). Status bar goes light via `.preferredColorScheme(.dark)`. | |

## Security note (review label?)

No new file-path or deletion code: the player opens `ClipStorage.clipURL` (validated in #24) read-only, and delete-from-detail is one id through `LibraryEdits.delete`, the path #24 already flagged for review. **No separate fable-security review needed for #25.** If #24's recommended security look hasn't happened yet, add `LibraryView.commitDetailDelete` to its scope (points: delete runs only after confirm + dismissal, saves before removing files, thumbnails dropped).

## Final layout

```
Reps/Library/ClipPlayback.swift            new: PlaybackSpeed, ClipEventKind, ClipEvent, ClipPlayback
Reps/UI/Library/ClipDetailTheme.swift      new: Theme.playerPill/playerTrack, player fonts, ClipDetailMetrics
Reps/UI/Library/PlayerLayerView.swift      new: PlayerLayerView (AVPlayerLayer host)
Reps/UI/Library/ClipPlayer.swift           new: @Observable ClipPlayer
Reps/UI/Library/ClipScrubber.swift         new: ClipScrubber (filmstrip, time, event track)
Reps/UI/Library/ClipDetailView.swift       new: ClipDetailView, PlayerCircleButtonStyle (private), #Preview
Reps/UI/Library/LibraryView.swift          changed: fullScreenCover → ClipDetailView; detail edits/delete
Reps/UI/Library/ClipDetailPlaceholderView.swift   deleted
RepsTests/ClipPlaybackTests.swift          new (11 tests)
docs/code-reference.md, docs/design.md, docs/open-questions.md, docs/roadmap.md
```

Never edit `project.pbxproj` (synced folders, ADR 0009).

## Steps

Branch `feat/25-clip-detail` from `main` (with #24 merged). From the repo root:

```sh
DEST27='platform=iOS Simulator,id=A26BAE3A-CDDE-45A8-892D-2359740C877A'   # iOS 27
DEST265='platform=iOS Simulator,id=6D2623EF-0394-46F9-BFEC-022E3D2B7FE8'  # iOS 26.5
T="xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan Unit"
```

Before each commit: `xcrun swift-format format --in-place --recursive --parallel Reps RepsTests`, then `xcrun swift-format lint --strict --recursive --parallel Reps RepsTests` must print nothing.

### Step 1: playback math (TDD)

1. Add `RepsTests/ClipPlaybackTests.swift` (Appendix B). `$T -destination "$DEST27" -only-testing:RepsTests/ClipPlaybackTests` fails to compile.
2. Add `Reps/Library/ClipPlayback.swift` (Appendix A). Rerun: 11 tests pass. Same on `$DEST265`.
3. `docs/code-reference.md`: the `Reps/Library/ClipPlayback.swift` entry (after the `Reps/Library/LibraryEdits.swift` entry) and the `RepsTests/ClipPlaybackTests.swift` entry (next to `LibraryEditsTests`), text under "Docs".
4. Commit `added clip playback math` / body `frame step, speeds, scrub and event marks` + `Refs #25`.

### Step 2: player screen

1. Add `ClipDetailTheme.swift`, `PlayerLayerView.swift`, `ClipPlayer.swift`, `ClipScrubber.swift`, `ClipDetailView.swift` under `Reps/UI/Library/` (Appendix A).
2. Apply the `LibraryView.swift` changes (Appendix A, exact edits). Delete `Reps/UI/Library/ClipDetailPlaceholderView.swift`.
3. Build, then the whole `Unit` plan on both: `$T -destination "$DEST27"` and `$T -destination "$DEST265"`. Everything passes (#24's count + 11). No new warnings in the new files.
4. Smoke check (optional, not a test): `ClipDetailView.swift` `#Preview` shows the dark screen with the missing-file placeholder, label pill "Gap wedge · face-on · tempo 3.1 : 1", disabled bottom controls, working ✕/★/more. In `LibraryView`'s preview, tapping a tile opens the player; Delete asks, then the tile is gone; ★ in the player shows on the tile after closing.
5. code-reference: the five UI entries, the `LibraryView` line update, delete the `ClipDetailPlaceholderView` entry.
6. Commit `added clip detail player` / `dark full-bleed player with filmstrip, frame step and speeds` + `Refs #25`.

### Step 3: docs

1. `docs/open-questions.md`: the two new questions (text under "Docs"), numbered with the next free numbers (Q34–Q36 are expected to be taken by #5/#24; check the table).
2. `docs/design.md`: the note under the table (text below).
3. `docs/roadmap.md`: #25 ☑ in the Phase 4 table.
4. Commit `documented clip detail choices` / `event marks and delete copy questions` + `Closes #25`. PR title `added clip detail player`, body: `Dark full-bleed player: filmstrip, frame step, ¼/½/1×, impact mark, favourite/tags/delete.` + `Closes #25`.

## Tests

Suite `Unit`, `RepsTests/ClipPlaybackTests` (11, `@MainActor`, pure): speed cycle, titles and rates; frame duration + 60 fps fallback (0, negative, NaN); step lands on frame middles and moves exactly one frame from a middle (incl. 2.1 s = frame 126 floating-point case); clamps at both ends, no phantom frame at an exact multiple, partial last frame never past the end, zero duration/frame → 0; end detection; fraction/seconds clamp; time title 3 decimals, negative → 0.000; filmstrip slice middles, empty for 0 count/duration; impact mark only when inside the clip, custom/nil offset; snap within 12 pt only, no events/zero duration unchanged; label pill with/without tempo, putting (no angle), down-the-line + rounding.

No new tests for delete/favourite/tags: the player calls #24's `LibraryEdits.setFavourite/addTag/removeTag/delete` unchanged (covered by `LibraryEditsTests`); the rest is view wiring (CLAUDE.md: views build-only). `ClipPlayer` wraps AVPlayer and needs a real clip, so it's exercised once #22 writes clips.

## Docs

**code-reference.md**

```
## Reps/Library/ClipPlayback.swift
Clip player math and copy (F27, §5.3b); pure, tested.
- `PlaybackSpeed` (1×, ½×, ¼×): `next` cycles, `title`
- `ClipEventKind` (address, top, impact, finish), `ClipEvent(kind:seconds:)`
- `ClipPlayback.frameDuration(nominalFrameRate:)`: 1/rate, 60 fps fallback
- `ClipPlayback.stepped(from:by:frameDuration:duration:)`: middle of the frame `count` away, clamped to the clip
- `ClipPlayback.isAtEnd`, `fraction`, `seconds(atFraction:duration:)`, `timeTitle` ("2.098"), `filmstripTimes(count:duration:)`
- `ClipPlayback.events(duration:impactOffset:)`: impact at `assumedImpactOffset` (3 s, §5.8) when inside the clip; the rest #27
- `ClipPlayback.snapped(_:to:duration:trackWidth:tolerance:)`: jump to a mark released within `tolerance` points
- `ClipPlayback.label(_:)`: "Gap wedge · face-on · tempo 3.1 : 1"

## Reps/UI/Library/ClipDetailTheme.swift
Figma 11 values: `Theme.playerPill`, `Theme.playerTrack`, `Theme.Typography.playerLabel/playerTime/playerSpeed/playerIcon/playerStep`, `ClipDetailMetrics`.

## Reps/UI/Library/PlayerLayerView.swift
- `PlayerLayerView(player:)`: `AVPlayerLayer` host, aspect fit on black, no system controls

## Reps/UI/Library/ClipPlayer.swift
- `ClipPlayer` (@Observable): `load(_:filmstripCount:)` (`.missing` for nil/missing/undecodable files), `togglePlay`, `pause`, `cycleSpeed`, `step(by:)`, `seek(to:)` (zero tolerance), `scrub(to:)`/`endScrub(at:)`, `stop`; publishes `state`, `duration`, `frameDuration`, `currentTime`, `isPlaying`, `speed`, `filmstrip` (10 frames via `AVAssetImageGenerator.images(for:)`)

## Reps/UI/Library/ClipScrubber.swift
- `ClipScrubber(player:events:)`: filmstrip with yellow playhead (drag to scrub), time, track with event marks and knob (release near a mark jumps to it), pose toggle (#27, disabled)

## Reps/UI/Library/ClipDetailView.swift
Figma 11, 15. Presented full screen by `LibraryView`.
- `ClipDetailView(clip:tagSuggestions:onFavourite:onAddTag:onRemoveTag:onDelete:)`: ✕, ★, share (#26), more (Tags sheet, Save to Photos (#26), Delete with confirm alert), label pill, scrubber, speed / frame step / play, overlay options (#27); missing-file placeholder

## RepsTests/ClipPlaybackTests.swift
- Speed cycle, frame duration, frame step and clamping, end, fraction/seconds, time title, filmstrip times, impact mark, snapping, label pill
```

In the `## Reps/UI/Library/LibraryView.swift` entry, replace the tap/placeholder wording with: `tap opens ClipDetailView full screen (ends the undo window first); player favourite/tag edits save at once; player delete runs LibraryEdits.delete after the cover closes`. Delete the `## Reps/UI/Library/ClipDetailPlaceholderView.swift` entry.

**open-questions.md** (Open table; `QA`/`QB` = next free numbers):

`| QA | F27 asks for "jump-to-event chips"; Figma 11 shows only marks on the track. #25 draws the marks and a release within 12 pt of one jumps to it. Only impact exists, assumed 3.0 s into the clip (§5.8 window). OK, or add a chip row (Address · Top · Impact · Finish) once #27 has the pose events? | #27 | #22 should store the real impact offset per clip (`ClipPlayback.events(duration:impactOffset:)` takes it); chips would be one HStack of buttons calling \`player.seek\`. |`

`| QB | Figma 15 says "The shot stays counted; only the video is removed", but delete from the player uses #24's path, which removes the ShotRecord row too (counts stay). Same choice as Q35: row delete, or clear \`clipFileName\` and keep the shot? | – (#25 ships row delete) | Changing \`LibraryEdits.delete\` fixes both the library and the player; the alert copy is a PLACEHOLDER until then. |`

(Replace `Q35` in QB with #24's actual number for its delete question if it differs.)

**design.md**, below the table:
`- Clip detail (#25): full-screen cover from the library, dark via \`preferredColorScheme\`; video aspect-fit on black. Figma 11 glyphs are SF Symbols in code (pause isn't designed). Event marks on the track, no chip row (QA). Figma 15 is the native alert. Tokens in \`Reps/UI/Library/ClipDetailTheme.swift\`; colours reuse \`Theme.favourite\`, \`Theme.danger\`, \`Theme.thumbnail\`.`

## Placeholders (`// PLACEHOLDER:` in code)

1. `ClipPlayback.assumedImpactOffset`: impact assumed 3 s in (+ `TODO(#22)`); `events`: `TODO(#27)` for address/top/finish
2. `ClipPlayer.frames`: filmstrip frame size (120 px)
3. `ClipDetailView`: delete alert message (Figma 15 copy vs row delete, QB); missing clip copy; error copy (#29) ×3 (favourite, add tag, remove tag via `run`)
4. `ClipDetailView`: `TODO(#26)` share and Save to Photos (disabled); `TODO(#27)` overlay options (disabled)
5. `ClipScrubber`: `TODO(#27)` pose overlay toggle (disabled)
6. `LibraryView.commitDetailDelete`: error copy (#29)

## Risks and hand-offs

- **Untested against a real clip.** Nothing writes clips before #22, so AVPlayer behaviour (exact seeks, 30/60 fps grid, filmstrip decode, rates < 1 with audio) is build-checked only. #22 should open a written clip in the player once as its smoke test, and pass the real impact offset (see QA).
- **Frame grid assumes constant frame rate** (`nominalFrameRate`). Exported 1080p60 clips are CFR; a VFR clip would step by the nominal frame, still landing on real frames thanks to middle-of-frame seeks, but may skip one occasionally.
- **Cover content refresh**: `byID[item.id] ?? item` relies on SwiftUI re-running the cover's content when `LibraryView`'s `@Query` changes (so ★/tags update in the player). If the star doesn't flip on device, keep a local `@State isFavourite` in `ClipDetailView` seeded from `clip` and toggled on success.
- **`onDisappear` of the library** fires when the cover presents; harmless (`finishUndo()` already ran in `tap`).
- **Audio**: default audio session (silent switch mutes clips). If #10's voice layer changes the category app-wide, clip audio follows it.
- **VoiceOver**: filmstrip is an adjustable element (swipe up/down steps frames); the track is hidden to VoiceOver.
- The tag sheet is forced light inside the dark cover so `Theme.ink` suggestions stay readable.

## Appendix A: source (copy exactly)

### `Reps/Library/ClipPlayback.swift`

```swift
import Foundation

// F27 speeds; the pill cycles 1× → ½× → ¼× → 1×.
enum PlaybackSpeed: Double, CaseIterable {
    case full = 1
    case half = 0.5
    case quarter = 0.25

    var next: PlaybackSpeed {
        switch self {
        case .full: .half
        case .half: .quarter
        case .quarter: .full
        }
    }

    var title: String {
        switch self {
        case .full: "1×"
        case .half: "½×"
        case .quarter: "¼×"
        }
    }
}

enum ClipEventKind: CaseIterable {
    case address
    case top
    case impact
    case finish
}

struct ClipEvent: Equatable {
    let kind: ClipEventKind
    let seconds: Double
}

// Timeline math and copy for the clip detail player (F27, §5.3b). Times are seconds from the clip start.
enum ClipPlayback {
    // §5.6 captures at 60 fps; used when a track reports no frame rate.
    static let fallbackFrameRate = 60.0
    // PLACEHOLDER: §5.8 cuts [impact − 3 s, impact + 2 s], so impact is assumed 3 s in. TODO(#22): store the real offset.
    static let assumedImpactOffset = 3.0

    static func frameDuration(nominalFrameRate: Float) -> Double {
        let rate = Double(nominalFrameRate)
        return 1 / (rate.isFinite && rate > 0 ? rate : fallbackFrameRate)
    }

    // Moves `count` frames from the frame showing at `seconds`, clamped to the clip.
    // Returns the middle of the target frame so a zero-tolerance seek lands on it whatever the frame's exact timestamp.
    static func stepped(from seconds: Double, by count: Int, frameDuration: Double, duration: Double) -> Double {
        guard frameDuration > 0, duration > 0 else { return 0 }
        let lastFrame = max(0, Int((duration / frameDuration - 1e-6).rounded(.up)) - 1)
        let current = min(max(Int((seconds / frameDuration + 1e-6).rounded(.down)), 0), lastFrame)
        let target = min(max(current + count, 0), lastFrame)
        return min((Double(target) + 0.5) * frameDuration, duration)
    }

    // Play from the start when the playhead is on the last frame.
    static func isAtEnd(_ seconds: Double, frameDuration: Double, duration: Double) -> Bool {
        seconds >= duration - frameDuration
    }

    static func fraction(_ seconds: Double, duration: Double) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(seconds / duration, 0), 1)
    }

    static func seconds(atFraction fraction: Double, duration: Double) -> Double {
        min(max(fraction, 0), 1) * max(duration, 0)
    }

    // "2.098"; POSIX formatting so the decimal point doesn't follow the locale.
    static func timeTitle(_ seconds: Double) -> String {
        String(format: "%.3f", max(seconds, 0))
    }

    // The middle of `count` equal slices, one filmstrip frame each.
    static func filmstripTimes(count: Int, duration: Double) -> [Double] {
        guard count > 0, duration > 0 else { return [] }
        let slice = duration / Double(count)
        return (0..<count).map { (Double($0) + 0.5) * slice }
    }

    // Marks on the track. TODO(#27): address, top and finish from the pose track that computes tempo.
    static func events(duration: Double, impactOffset: Double? = assumedImpactOffset) -> [ClipEvent] {
        guard let impactOffset, impactOffset > 0, impactOffset < duration else { return [] }
        return [ClipEvent(kind: .impact, seconds: impactOffset)]
    }

    // A tap within `tolerance` points of a mark jumps exactly to that event (F27 jump-to-event).
    static func snapped(
        _ seconds: Double, to events: [ClipEvent], duration: Double, trackWidth: Double, tolerance: Double
    ) -> Double {
        guard duration > 0, trackWidth > 0 else { return seconds }
        let nearest = events.min { abs($0.seconds - seconds) < abs($1.seconds - seconds) }
        guard let nearest, abs(nearest.seconds - seconds) / duration * trackWidth <= tolerance else { return seconds }
        return nearest.seconds
    }

    // "Gap wedge · face-on · tempo 3.1 : 1" (Figma 11 label pill).
    static func label(_ clip: LibraryClip) -> String {
        let title = LibraryDisplay.tileTitle(clip)
        guard let tempo = LibraryDisplay.tempo(clip.tempoRatio) else { return title }
        return "\(title) · tempo \(tempo) : 1"
    }
}
```

### `Reps/UI/Library/ClipDetailTheme.swift`

```swift
import SwiftUI

// Clip detail values from Figma 11 (the one dark screen, docs/design.md).
extension Theme {
    static let playerPill = Color.black.opacity(0.38)
    static let playerTrack = Color.white.opacity(0.35)
}

extension Theme.Typography {
    static let playerLabel = Font.system(size: 13, weight: .semibold)
    static let playerTime = Font.system(size: 20, weight: .semibold).monospacedDigit()
    static let playerSpeed = Font.system(size: 17, weight: .semibold)
    static let playerIcon = Font.system(size: 20)
    static let playerStep = Font.system(size: 22)
}

enum ClipDetailMetrics {
    static let topControl: CGFloat = 48
    static let bottomControl: CGFloat = 56
    static let speedWidth: CGFloat = 72
    static let panelRadius: CGFloat = 22
    static let filmstripFrames = 10
    static let filmstripHeight: CGFloat = 56
    static let filmstripGap: CGFloat = 3
    static let frameRadius: CGFloat = 3
    static let playheadWidth: CGFloat = 4
    static let playheadOverhang: CGFloat = 5
    static let trackHeight: CGFloat = 6
    static let markWidth: CGFloat = 2
    static let markHeight: CGFloat = 18
    static let knob: CGFloat = 20
    static let markTapTolerance: CGFloat = 12
}
```

### `Reps/UI/Library/PlayerLayerView.swift`

```swift
import AVFoundation
import SwiftUI

// AVPlayerLayer without system controls; the clip detail draws its own (Figma 11).
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.player = player
        // Aspect fit: frame review needs the whole swing, club head included.
        view.playerLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: PlayerUIView, context: Context) {
        view.playerLayer.player = player
    }

    final class PlayerUIView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
```

### `Reps/UI/Library/ClipPlayer.swift`

```swift
import AVFoundation
import Observation
import UIKit

// Drives one clip in the detail player (F27). UI layer only; ShotDetector never sees AVPlayer.
@Observable
final class ClipPlayer {
    enum State: Equatable {
        case loading
        case ready
        case missing
    }

    @ObservationIgnored let player = AVPlayer()
    private(set) var state = State.loading
    private(set) var duration = 0.0
    private(set) var frameDuration = ClipPlayback.frameDuration(nominalFrameRate: 0)
    private(set) var currentTime = 0.0
    private(set) var isPlaying = false
    private(set) var speed = PlaybackSpeed.full
    private(set) var filmstrip: [UIImage?] = []

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var isScrubbing = false

    // nil or a missing/undecodable file leaves the player in `.missing` (no clips exist before #22).
    func load(_ url: URL?, filmstripCount: Int) async {
        guard let url, FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            state = .missing
            return
        }
        let asset = AVURLAsset(url: url)
        guard let length = try? await asset.load(.duration), length.seconds.isFinite, length.seconds > 0,
            let track = try? await asset.loadTracks(withMediaType: .video).first
        else {
            state = .missing
            return
        }
        let rate = (try? await track.load(.nominalFrameRate)) ?? 0
        guard !Task.isCancelled else { return }
        duration = length.seconds
        frameDuration = ClipPlayback.frameDuration(nominalFrameRate: rate)
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
        player.defaultRate = Float(speed.rawValue)
        addTimeObserver()
        state = .ready
        filmstrip = await Self.frames(
            of: asset, at: ClipPlayback.filmstripTimes(count: filmstripCount, duration: duration))
    }

    func togglePlay() {
        guard state == .ready else { return }
        if isPlaying {
            pause()
            return
        }
        if ClipPlayback.isAtEnd(currentTime, frameDuration: frameDuration, duration: duration) { seek(to: 0) }
        player.defaultRate = Float(speed.rawValue)
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func cycleSpeed() {
        speed = speed.next
        player.defaultRate = Float(speed.rawValue)
        if isPlaying { player.rate = Float(speed.rawValue) }
    }

    func step(by count: Int) {
        guard state == .ready else { return }
        pause()
        seek(to: ClipPlayback.stepped(from: currentTime, by: count, frameDuration: frameDuration, duration: duration))
    }

    // Frame-accurate; a newer seek cancels an unfinished one, so dragging stays responsive on 5 s clips.
    func seek(to seconds: Double) {
        guard state == .ready else { return }
        currentTime = min(max(seconds, 0), duration)
        player.seek(
            to: CMTime(seconds: currentTime, preferredTimescale: 6_000), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func scrub(to seconds: Double) {
        if !isScrubbing {
            isScrubbing = true
            pause()
        }
        seek(to: seconds)
    }

    func endScrub(at seconds: Double) {
        seek(to: seconds)
        isScrubbing = false
    }

    func stop() {
        player.pause()
        isPlaying = false
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player.replaceCurrentItem(with: nil)
    }

    private func addTimeObserver() {
        guard timeObserver == nil else { return }
        // Also fires when playback starts or stops (e.g. at the end), which keeps `isPlaying` honest.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
    }

    private func tick(_ seconds: Double) {
        isPlaying = player.rate != 0
        guard !isScrubbing, seconds.isFinite else { return }
        currentTime = min(max(seconds, 0), duration)
    }

    private static func frames(of asset: AVURLAsset, at times: [Double]) async -> [UIImage?] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 120, height: 120)  // PLACEHOLDER: filmstrip frame size
        var images = [UIImage?](repeating: nil, count: times.count)
        let requested = times.map { CMTime(seconds: $0, preferredTimescale: 6_000) }
        for await result in generator.images(for: requested) {
            guard let index = requested.firstIndex(of: result.requestedTime),
                let image = try? result.image
            else { continue }
            images[index] = UIImage(cgImage: image)
        }
        return images
    }
}
```

### `Reps/UI/Library/ClipScrubber.swift`

```swift
import SwiftUI

// Figma 11 scrubber panel: filmstrip with a yellow playhead, then time, event track and overlay toggle.
struct ClipScrubber: View {
    let player: ClipPlayer
    let events: [ClipEvent]

    var body: some View {
        VStack(spacing: 10) {
            filmstrip
            HStack(spacing: 12) {
                Text(ClipPlayback.timeTitle(player.currentTime))
                    .font(Theme.Typography.playerTime)
                    .foregroundStyle(.white)
                    .accessibilityLabel("\(ClipPlayback.timeTitle(player.currentTime)) seconds")
                track
                Button {
                    // TODO(#27): pose overlay toggle.
                } label: {
                    Image(systemName: "figure.stand")
                        .font(Theme.Typography.playerIcon)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(true)
                .opacity(0.5)
                .accessibilityLabel("Pose overlay")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.playerPill, in: .rect(cornerRadius: ClipDetailMetrics.panelRadius))
        .disabled(player.state != .ready)
    }

    private var fraction: Double {
        ClipPlayback.fraction(player.currentTime, duration: player.duration)
    }

    private var filmstrip: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            HStack(spacing: ClipDetailMetrics.filmstripGap) {
                ForEach(0..<ClipDetailMetrics.filmstripFrames, id: \.self) { index in
                    Theme.thumbnail
                        .overlay {
                            if let image = player.filmstrip.indices.contains(index) ? player.filmstrip[index] : nil {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            }
                        }
                        .clipShape(.rect(cornerRadius: ClipDetailMetrics.frameRadius))
                }
            }
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.favourite)
                    .frame(
                        width: ClipDetailMetrics.playheadWidth,
                        height: ClipDetailMetrics.filmstripHeight + 2 * ClipDetailMetrics.playheadOverhang
                    )
                    .offset(x: fraction * max(width - ClipDetailMetrics.playheadWidth, 0))
            }
            .contentShape(.rect)
            .gesture(scrubGesture(width: width, inset: 0, snaps: false))
        }
        .frame(height: ClipDetailMetrics.filmstripHeight)
        .accessibilityElement()
        .accessibilityLabel("Filmstrip")
        .accessibilityValue(ClipPlayback.timeTitle(player.currentTime))
        .accessibilityAdjustableAction { direction in
            player.step(by: direction == .increment ? 1 : -1)
        }
    }

    private var track: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let knobX = fraction * max(width - ClipDetailMetrics.knob, 0)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.playerTrack)
                    .frame(height: ClipDetailMetrics.trackHeight)
                Capsule()
                    .fill(Theme.favourite)
                    .frame(width: knobX + ClipDetailMetrics.knob / 2, height: ClipDetailMetrics.trackHeight)
                ForEach(events, id: \.seconds) { event in
                    Rectangle()
                        .fill(event.kind == .impact ? Theme.danger : .white)
                        .frame(width: ClipDetailMetrics.markWidth, height: ClipDetailMetrics.markHeight)
                        .offset(x: markX(event, width: width))
                }
                Circle()
                    .fill(Theme.favourite)
                    .frame(width: ClipDetailMetrics.knob, height: ClipDetailMetrics.knob)
                    .offset(x: knobX)
            }
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(scrubGesture(width: width, inset: ClipDetailMetrics.knob / 2, snaps: true))
        }
        .frame(height: ClipDetailMetrics.knob)
        .accessibilityHidden(true)
    }

    private func markX(_ event: ClipEvent, width: CGFloat) -> CGFloat {
        let usable = max(width - ClipDetailMetrics.knob, 0)
        return ClipPlayback.fraction(event.seconds, duration: player.duration) * usable + ClipDetailMetrics.knob / 2
            - ClipDetailMetrics.markWidth / 2
    }

    // Drag or tap to scrub; on the track a release near an event mark jumps exactly to it.
    private func scrubGesture(width: CGFloat, inset: CGFloat, snaps: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                player.scrub(to: seconds(at: value.location.x, width: width, inset: inset))
            }
            .onEnded { value in
                let seconds = seconds(at: value.location.x, width: width, inset: inset)
                guard snaps else { return player.endScrub(at: seconds) }
                player.endScrub(
                    at: ClipPlayback.snapped(
                        seconds, to: events, duration: player.duration,
                        trackWidth: Double(max(width - ClipDetailMetrics.knob, 0)),
                        tolerance: Double(ClipDetailMetrics.markTapTolerance)))
            }
    }

    // `inset` keeps the knob's centre inside the track.
    private func seconds(at x: CGFloat, width: CGFloat, inset: CGFloat) -> Double {
        let usable = max(width - 2 * inset, 1)
        return ClipPlayback.seconds(atFraction: Double((x - inset) / usable), duration: player.duration)
    }
}
```

### `Reps/UI/Library/ClipDetailView.swift`

```swift
import SwiftUI

// Figma 11 Clip detail, 15 delete alert (F27, §5.3b): dark full-bleed player with floating pills.
struct ClipDetailView: View {
    let clip: LibraryClip
    let tagSuggestions: [String]
    let onFavourite: (Bool) throws -> Void
    let onAddTag: (String) throws -> Void
    let onRemoveTag: (String) throws -> Void
    // Called after the user confirms; the library deletes once this screen has closed.
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var player = ClipPlayer()
    @State private var isTagSheetShown = false
    @State private var isDeleteAlertShown = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerLayerView(player: player.player)
                .ignoresSafeArea()
            if player.state == .missing { missingFile }
            VStack(spacing: 0) {
                topControls
                labelPill
                Spacer(minLength: 0)
                ClipScrubber(player: player, events: ClipPlayback.events(duration: player.duration))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                bottomControls
            }
        }
        .preferredColorScheme(.dark)
        .task(id: clip.id) {
            let url = clip.sessionID.flatMap {
                ClipStorage.clipURL(fileName: clip.clipFileName, sessionID: $0)
            }
            await player.load(url, filmstripCount: ClipDetailMetrics.filmstripFrames)
        }
        .onDisappear { player.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { player.pause() }
        }
        .sheet(isPresented: $isTagSheetShown) {
            LibraryTagSheet(
                selectedCount: 1,
                onSelection: clip.tags,
                suggestions: tagSuggestions,
                onAdd: { tag in run("Couldn't add the tag.") { try onAddTag(tag) } },  // PLACEHOLDER: error copy (#29)
                onRemove: { tag in run("Couldn't remove the tag.") { try onRemoveTag(tag) } }  // PLACEHOLDER
            )
            .preferredColorScheme(.light)
        }
        .alert("Delete this clip?", isPresented: $isDeleteAlertShown) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                player.stop()
                onDelete()
            }
        } message: {
            // PLACEHOLDER: Figma 15 copy; the shot row goes too (#24 delete path), see Q35.
            Text("The shot stays counted; only the video is removed.")
        }
        .alert(
            errorMessage ?? "",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        }
    }

    private var topControls: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(PlayerCircleButtonStyle(size: ClipDetailMetrics.topControl))
            .accessibilityLabel("Close")
            Spacer()
            HStack(spacing: 10) {
                Button {
                    run("Couldn't change the favourite.") { try onFavourite(!clip.isFavourite) }  // PLACEHOLDER (#29)
                } label: {
                    Image(systemName: clip.isFavourite ? "star.fill" : "star")
                        .foregroundStyle(clip.isFavourite ? Theme.favourite : .white)
                }
                .accessibilityLabel(clip.isFavourite ? "Unfavourite" : "Favourite")
                Button {
                    // TODO(#26): share sheet.
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(true)
                .accessibilityLabel("Share")
            }
            .buttonStyle(PlayerCircleButtonStyle(size: ClipDetailMetrics.topControl))
            Spacer()
            Menu {
                Button("Tags", systemImage: "tag") { isTagSheetShown = true }
                Button("Save to Photos", systemImage: "square.and.arrow.down") {
                    // TODO(#26): save to Photos.
                }
                .disabled(true)
                Button("Delete", systemImage: "trash", role: .destructive) { isDeleteAlertShown = true }
            } label: {
                Image(systemName: "ellipsis")
                    .font(Theme.Typography.playerIcon)
                    .foregroundStyle(.white)
                    .frame(width: ClipDetailMetrics.topControl, height: ClipDetailMetrics.topControl)
                    .background(Theme.playerPill, in: .circle)
            }
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var labelPill: some View {
        Text(ClipPlayback.label(clip))
            .font(Theme.Typography.playerLabel)
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.playerPill, in: .capsule)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 10)
    }

    private var bottomControls: some View {
        HStack(spacing: 10) {
            Button(player.speed.title) { player.cycleSpeed() }
                .font(Theme.Typography.playerSpeed)
                .foregroundStyle(.white)
                .frame(width: ClipDetailMetrics.speedWidth, height: ClipDetailMetrics.bottomControl)
                .background(Theme.playerPill, in: .capsule)
                .accessibilityLabel("Speed \(player.speed.title)")
            HStack {
                Button {
                    player.step(by: -1)
                } label: {
                    Image(systemName: "backward.frame")
                }
                .accessibilityLabel("Previous frame")
                Spacer()
                Button {
                    player.togglePlay()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                Spacer()
                Button {
                    player.step(by: 1)
                } label: {
                    Image(systemName: "forward.frame")
                }
                .accessibilityLabel("Next frame")
            }
            .font(Theme.Typography.playerStep)
            .foregroundStyle(.white)
            .buttonStyle(.plain)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
            .frame(height: ClipDetailMetrics.bottomControl)
            .background(Theme.playerPill, in: .capsule)
            Button {
                // TODO(#27): overlay options (pose skeleton, event marks).
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(PlayerCircleButtonStyle(size: ClipDetailMetrics.bottomControl))
            .disabled(true)
            .accessibilityLabel("Overlay options")
        }
        .disabled(player.state != .ready)
        .padding(.horizontal, 14)
    }

    private var missingFile: some View {
        VStack(spacing: 10) {
            Image(systemName: "video.slash")
                .font(.largeTitle)
            Text("This clip's video file is missing.")  // PLACEHOLDER: missing clip copy
                .font(Theme.Typography.body)
        }
        .foregroundStyle(.white.opacity(0.8))
        .accessibilityElement(children: .combine)
    }

    private func run(_ failure: String, _ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = failure
        }
    }
}

// Round translucent control (Figma 11 "Control ✕", "☆", "⇧", "⚙").
private struct PlayerCircleButtonStyle: ButtonStyle {
    let size: CGFloat
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.playerIcon)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.playerPill, in: .circle)
            .opacity(configuration.isPressed ? 0.7 : isEnabled ? 1 : 0.5)
    }
}

#if DEBUG
    #Preview("Missing file") {
        ClipDetailView(
            clip: LibraryClip(
                id: UUID(), timestamp: .now, clubName: "Gap wedge", tags: ["fade"], isFavourite: false, tempoRatio: 3.1,
                clipFileName: "missing.mov", sessionID: UUID(), sessionTitle: "Wedge day", sessionStartedAt: .now,
                angle: .faceOn),
            tagSuggestions: ["fade", "gate drill"],
            onFavourite: { _ in }, onAddTag: { _ in }, onRemoveTag: { _ in }, onDelete: {}
        )
    }
#endif
```

### `Reps/UI/Library/LibraryView.swift` (edits to #24's file; nothing else changes)

1. Replace `    @State private var path: [UUID] = []` with:

```swift
    @State private var detail: LibraryClip?
    @State private var detailDeleteID: UUID?
```

2. `NavigationStack(path: $path) {` → `NavigationStack {`

3. Replace the whole `.navigationDestination(for: UUID.self) { id in … ClipDetailPlaceholderView … }` modifier with:

```swift
            .fullScreenCover(item: $detail, onDismiss: commitDetailDelete) { item in
                ClipDetailView(
                    clip: byID[item.id] ?? item,
                    tagSuggestions: LibraryDisplay.tagOptions(all),
                    onFavourite: { value in
                        try editDetail(item.id) { try LibraryEdits.setFavourite(value, on: $0, in: context) }
                    },
                    onAddTag: { tag in try editDetail(item.id) { try LibraryEdits.addTag(tag, to: $0, in: context) } },
                    onRemoveTag: { tag in
                        try editDetail(item.id) { try LibraryEdits.removeTag(tag, from: $0, in: context) }
                    },
                    onDelete: {
                        detailDeleteID = item.id
                        detail = nil
                    }
                )
            }
```

4. In `tap(_:)`, replace `path.append(clip.id)` with:

```swift
            // Opening a clip ends any undo window, so a later Undo can't overwrite edits made in the player.
            finishUndo()
            detail = clip
```

5. Insert directly above `private func undo(_ undo: LibraryUndo) {`:

```swift
    // Player edits (Figma 11): one shot, saved at once, no toast; the player shows its own error.
    private func editDetail(_ id: UUID, _ edit: ([ShotRecord]) throws -> [ShotSnapshot]) throws {
        let targets = shots.filter { $0.id == id }
        guard !targets.isEmpty else { return }
        _ = try edit(targets)
    }

    // Figma 15: confirmed in the player, so no Undo. Runs once the player has closed (same path as bulk delete).
    private func commitDetailDelete() {
        guard let id = detailDeleteID else { return }
        detailDeleteID = nil
        do {
            let deleted = try LibraryEdits.delete(ids: [id], in: context, clipFiles: clipFiles)
            Task { await ClipThumbnails.shared.remove(deleted) }
        } catch {
            errorMessage = "Couldn't delete the clip."  // PLACEHOLDER: error copy (#29)
        }
    }

```

## Appendix B: tests

### `RepsTests/ClipPlaybackTests.swift`

```swift
import Foundation
import Testing

@testable import Reps

@MainActor
struct ClipPlaybackTests {
    private let frame = 1.0 / 60

    private func clip(club: String = "Gap wedge", tempo: Double? = 3.1, angle: CameraAngle = .faceOn) -> LibraryClip {
        LibraryClip(
            id: UUID(), timestamp: .now, clubName: club, tags: [], isFavourite: false, tempoRatio: tempo,
            clipFileName: "a.mov", sessionID: UUID(), sessionTitle: nil, sessionStartedAt: nil, angle: angle)
    }

    @Test func speedCyclesFullHalfQuarter() {
        #expect(PlaybackSpeed.full.next == .half)
        #expect(PlaybackSpeed.half.next == .quarter)
        #expect(PlaybackSpeed.quarter.next == .full)
        #expect(PlaybackSpeed.allCases.map(\.title) == ["1×", "½×", "¼×"])
        #expect(PlaybackSpeed.allCases.map(\.rawValue) == [1, 0.5, 0.25])
    }

    @Test func frameDurationFallsBackTo60() {
        #expect(ClipPlayback.frameDuration(nominalFrameRate: 30) == 1.0 / 30)
        #expect(ClipPlayback.frameDuration(nominalFrameRate: 60) == frame)
        #expect(ClipPlayback.frameDuration(nominalFrameRate: 0) == frame)
        #expect(ClipPlayback.frameDuration(nominalFrameRate: -1) == frame)
        #expect(ClipPlayback.frameDuration(nominalFrameRate: .nan) == frame)
    }

    @Test func stepLandsOnFrameMiddles() {
        #expect(ClipPlayback.stepped(from: 0, by: 1, frameDuration: frame, duration: 5) == 1.5 * frame)
        // 2.1 s is exactly frame 126 at 60 fps, despite floating point.
        #expect(ClipPlayback.stepped(from: 2.1, by: 1, frameDuration: frame, duration: 5) == 127.5 * frame)
        #expect(ClipPlayback.stepped(from: 2.1, by: -1, frameDuration: frame, duration: 5) == 125.5 * frame)
        // Stepping from a frame middle moves exactly one frame each time.
        let once = ClipPlayback.stepped(from: 0, by: 1, frameDuration: frame, duration: 5)
        #expect(ClipPlayback.stepped(from: once, by: 1, frameDuration: frame, duration: 5) == 2.5 * frame)
        #expect(ClipPlayback.stepped(from: once, by: -1, frameDuration: frame, duration: 5) == 0.5 * frame)
    }

    @Test func stepClampsToTheClip() {
        #expect(ClipPlayback.stepped(from: 0, by: -1, frameDuration: frame, duration: 5) == 0.5 * frame)
        // 5 s at 60 fps is frames 0...299; no phantom frame 300.
        #expect(ClipPlayback.stepped(from: 4.995, by: 1, frameDuration: frame, duration: 5) == 299.5 * frame)
        #expect(ClipPlayback.stepped(from: 9, by: 0, frameDuration: frame, duration: 5) == 299.5 * frame)
        // A partial last frame is still reachable but never past the end.
        #expect(ClipPlayback.stepped(from: 5, by: 1, frameDuration: frame, duration: 5.005) <= 5.005)
        #expect(ClipPlayback.stepped(from: 1, by: 1, frameDuration: frame, duration: 0) == 0)
        #expect(ClipPlayback.stepped(from: 1, by: 1, frameDuration: 0, duration: 5) == 0)
    }

    @Test func endDetection() {
        #expect(ClipPlayback.isAtEnd(5, frameDuration: frame, duration: 5))
        #expect(ClipPlayback.isAtEnd(299.5 * frame, frameDuration: frame, duration: 5))
        #expect(!ClipPlayback.isAtEnd(4.9, frameDuration: frame, duration: 5))
    }

    @Test func fractionAndSecondsClamp() {
        #expect(ClipPlayback.fraction(2.5, duration: 5) == 0.5)
        #expect(ClipPlayback.fraction(-1, duration: 5) == 0)
        #expect(ClipPlayback.fraction(9, duration: 5) == 1)
        #expect(ClipPlayback.fraction(1, duration: 0) == 0)
        #expect(ClipPlayback.seconds(atFraction: 0.5, duration: 5) == 2.5)
        #expect(ClipPlayback.seconds(atFraction: -0.2, duration: 5) == 0)
        #expect(ClipPlayback.seconds(atFraction: 1.3, duration: 5) == 5)
    }

    @Test func timeTitleHasThreeDecimals() {
        #expect(ClipPlayback.timeTitle(2.098) == "2.098")
        #expect(ClipPlayback.timeTitle(0) == "0.000")
        #expect(ClipPlayback.timeTitle(12.3456) == "12.346")
        #expect(ClipPlayback.timeTitle(-0.01) == "0.000")
    }

    @Test func filmstripTimesAreSliceMiddles() {
        #expect(ClipPlayback.filmstripTimes(count: 4, duration: 2) == [0.25, 0.75, 1.25, 1.75])
        #expect(ClipPlayback.filmstripTimes(count: 10, duration: 5).count == 10)
        #expect(ClipPlayback.filmstripTimes(count: 0, duration: 5).isEmpty)
        #expect(ClipPlayback.filmstripTimes(count: 10, duration: 0).isEmpty)
    }

    @Test func impactMarkOnlyInsideTheClip() {
        #expect(ClipPlayback.events(duration: 5) == [ClipEvent(kind: .impact, seconds: 3)])
        #expect(ClipPlayback.events(duration: 3).isEmpty)
        #expect(ClipPlayback.events(duration: 0).isEmpty)
        #expect(ClipPlayback.events(duration: 5, impactOffset: nil).isEmpty)
        #expect(ClipPlayback.events(duration: 5, impactOffset: 1.2) == [ClipEvent(kind: .impact, seconds: 1.2)])
    }

    @Test func releaseNearAMarkJumpsToIt() {
        let events = [ClipEvent(kind: .impact, seconds: 3)]
        // 200 pt track over 5 s: 0.1 s is 4 pt, 0.5 s is 20 pt.
        #expect(ClipPlayback.snapped(3.1, to: events, duration: 5, trackWidth: 200, tolerance: 12) == 3)
        #expect(ClipPlayback.snapped(2.85, to: events, duration: 5, trackWidth: 200, tolerance: 12) == 3)
        #expect(ClipPlayback.snapped(3.5, to: events, duration: 5, trackWidth: 200, tolerance: 12) == 3.5)
        #expect(ClipPlayback.snapped(3.1, to: [], duration: 5, trackWidth: 200, tolerance: 12) == 3.1)
        #expect(ClipPlayback.snapped(3.1, to: events, duration: 0, trackWidth: 200, tolerance: 12) == 3.1)
    }

    @Test func labelPill() {
        #expect(ClipPlayback.label(clip()) == "Gap wedge · face-on · tempo 3.1 : 1")
        #expect(ClipPlayback.label(clip(tempo: nil)) == "Gap wedge · face-on")
        #expect(ClipPlayback.label(clip(club: "Putter", tempo: nil, angle: .none)) == "Putter")
        #expect(
            ClipPlayback.label(clip(tempo: 2.96, angle: .downTheLine)) == "Gap wedge · down-the-line · tempo 3.0 : 1")
    }
}
```
