# #14 Ball locator + presence detector

Goal: a pure-logic `BallPresenceDetector: ShotDetecting` in ShotDetector. It finds the ball itself (a round edge, the first one still for 1 s locks, older static clutter is remembered and skipped, pluggable search region), keeps a reference patch, and tracks presence with NCC. When the ball is gone for ≥ 300 ms it emits one `ShotEvent` and searches again. Unit tests run on synthetic luma images, and `BallPresenceEvalTests` scores it on the putting footage.

Spec: §5.2 (reference patch, NCC, re-arm), §5.5 (putting), §5.4 (ball watcher), §6 (box lost). ADRs: **0017 (new, written by the planner: this plan's locator and presence choices)**, 0008 (absent ≥ 300 ms = stroke, no `occluded`, re-arm after 1 s present), 0010 (frame contract, eval), 0011 (auto-locate, newest still ~1 s, search region, re-search after each shot), 0016 (detectors get upright 420f frames on `detectorQueue`; size can flip, Q44).

Out of scope:
- Wiring into `CameraPipeline.setSinks` or `SessionController`, and putting-mode config (#16).
- The lock box UI, the tap override, and the "lost ball" voice line (#15).
- The pose-based feet region (#19).
- Accuracy gates (#21).
- §5.2's `occluded` state: ADR 0008 drops it. Don't re-add it, even if the motion stretch causes false fires. Report the numbers instead.

## Measured on the footage (planner prototype)

The planner ran a numpy/OpenCV port of the algorithm below on `ml/data/putting` (one clip, 312 s, 19 putts + 3 pickups positive, 15 motion negative). It used every 2nd frame (15 fps), 854×480 grey. The prototype had no frame-gap or search-region paths, and it clipped patches at the frame edge instead of skipping candidates whose patch doesn't fit.

| Variant | Result | Verdict |
|---|---|---|
| Bright blobs (local-contrast threshold + connected components + fill/aspect) | The ball merges with the light floor strip behind it (ball ≈ 200–220 luma, floor 150–200, ball's shaded side darker than the floor) | Rejected |
| Gradient circle vote, ring ±1 px, cos ≥ 0.9 | Ball found, but the door-lock cylinder also passes (coverage 0.75–0.94), and a bright 24 px square scores 1.0 | Rejected |
| **Gradient circle vote, exact ring, cos ≥ 0.95, coverage ≥ 0.8** | Only the ball in all 8 sample frames; squares, edges and uniform areas rejected; radius within ±1 px | **Chosen locator** |
| NCC patch half-side 1.5r and 3r (3r = spec's "3× diameter"), with the old locator | Half 1.5r: present ≈ 0.77, gone ≈ 0.61, because the background dominates. Half 3r: 0/22. Both runs also kept re-locking the door cylinder | Rejected |
| NCC patch half-side 1.5r, final locator, threshold 0.7 | 7/22, 9 FP. Half 3r was not re-run with the final locator | Rejected |
| **NCC patch half-side = r, threshold 0.75, ±0.25r shift search** | **19/22 positives, 1 FP** (190.07 s, in the motion stretch). Event times within 0.1 s of labels | **Chosen presence** |
| NCC patch half-side = r, threshold 0.6 | 11/22, 6 FP | Too low |
| Chosen defaults but `trackMemory` 1.0 s | 8/22, 3 FP | Worse |
| Chosen defaults but `trackMemory` 1.5 s | 10/22, 2 FP. It catches the 18.77 s ball but misses 12 others. Cause not isolated: either more ignored spots near the ball's usual position, or locks from sparse sightings with poor reference patches (both FPs come 0.1–0.6 s after a lock) | Keep 0.5 s; don't tune this knob |
| Edge-coverage presence (re-run the circle check at the lock) | 19/22, 0 FP | Not chosen: the issue and spec ask for NCC. Recorded as the #16 fallback (Q46) |

The NCC margin is thin. While present, the 5th percentile is 0.69 and the median 0.98. In the first 0.3 s after the ball leaves, the max is 0.75 and the median 0.55. Short dips (putter passing) are filtered by the 300 ms hold.

Misses with the chosen defaults:
- 18.77 s and 135.98 s: no lock. The planner checked with the stateless locator: while the putter rests against the ball at address, the circle is found only on some frames, with gaps over the 0.5 s `trackMemory`, so no track lasts 1 s. The ignored spots were not the cause.
- 212.89 s: the second of two pickups 0.73 s apart. It's structurally unreachable because a lock needs 1 s (Q45).

Locks seen: the first at 1.07 s on the ball; every later lock on a ball (y ≈ 354–362).

Swift will differ a little: 420f Y plane instead of OpenCV grey, AVAssetReader scaling instead of INTER_AREA. So the eval asserts floors, not these exact numbers.

## Decisions

| Topic | Decision |
|---|---|
| Pixels | Work on the luma (Y) plane only, copied into a plain `LumaImage` (`[UInt8]`, no row padding). Unit tests build `LumaImage` directly and need no pixel buffers. |
| Orientation | Ignored. Round edges and patch comparison don't care about rotation, and all coordinates are buffer pixels (top-left origin). Add a one-line comment saying so. |
| Locator | Gradient-direction circle vote (classic vision, ADR 0011). No Vision, no Accelerate: plain loops over `withUnsafe…BufferPointer`, so it runs in Debug tests at a usable speed. |
| Lock rule | A track is "still" while every match stays within `max(2, 0.3·r)` px of where it was first seen. The **first** track to be still for ≥ 1 s locks. "Newest" (ADR 0011) only breaks ties between tracks that reach 1 s on the same frame, then higher coverage, then larger radius. At lock, every other track still for ≥ 0.5 s becomes an **ignored spot** (clutter: pile, door handle) for the rest of the session, so from the second lock on, older static things never win. **Deviation from ADR 0011:** at the very first lock, static clutter that was in view before the ball locks first (nothing is "older" yet). Recorded in ADR 0017 and Q46(b). |
| Re-arm | Lock implies 1 s still, which is ADR 0008's "present ≥ 1 s", so a fresh lock is armed. No separate re-arm timer. |
| Event time | `ShotEvent.time` = time of the **first** frame below threshold (ball exit). Emitted on the frame where absence reaches 0.3 s. |
| Durations | Always `time` differences with 1 ms slack (`>= x - 0.001`), never frame counts (ADR 0010). |
| Frame gap | If `time - lastTime > 1.0` s (interruption), drop the lock, the tracks and any pending absence, keep the ignored spots, and search again. No event. |
| Size change | Any change in width/height (Q44 rotation) resets everything, including the ignored spots. |
| End of stream | `finish()` stays the protocol default `[]`. An absence shorter than 0.3 s at the end is not a stroke. |
| Search region | `searchRegion: CGRect` normalized to the buffer (0…1, top-left origin), default the whole frame. Only `searching` uses it. CoreGraphics is an allowed import (ADR 0010 list). |
| Public read-only state | `ball: BallCandidate?` (nil while searching) and `similarity: Double?` (last NCC, nil while searching). #15 draws the box and #16 tunes from these. |
| Non-planar buffer | `LumaImage(pixelBuffer:)` returns nil and `process` returns `[]` without touching state. |

## Files

All new files go in the synced folders. No pbxproj or test-plan edits. `RepsTests` already links ShotDetector (`import ShotDetector`, see `FrameSamplerTests`).

### `ShotDetector/LumaImage.swift` (new)

```swift
import CoreVideo

public struct LumaImage: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public var pixels: [UInt8]   // row-major, width * height, no padding

    public init(width: Int, height: Int, pixels: [UInt8])   // precondition(pixels.count == width * height)
    public init(width: Int, height: Int, fill: UInt8)
    public init?(pixelBuffer: CVPixelBuffer)                 // plane 0 of a planar buffer; nil if not planar
    public subscript(x: Int, y: Int) -> UInt8 { get set }    // pixels[y * width + x]
    public func cropped(x: Int, y: Int, width: Int, height: Int) -> LumaImage   // caller passes an in-bounds rect
}
```

- `init?(pixelBuffer:)`: `guard CVPixelBufferIsPlanar(buffer)`. Then `CVPixelBufferLockBaseAddress(buffer, .readOnly)` with `defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }`; the flags must match (Context7). Use `CVPixelBufferGetWidthOfPlane/HeightOfPlane/BytesPerRowOfPlane/BaseAddressOfPlane(buffer, 0)`. Return nil if the base address is nil. Copy `width` bytes per row from `base + row * bytesPerRow`, because rows are padded.

### `ShotDetector/BallLocator.swift` (new)

```swift
public struct BallCandidate: Sendable, Equatable {
    public var x: Double          // centre, buffer pixels
    public var y: Double
    public var radius: Double
    public var coverage: Double   // 0...1, share of 16 sectors with radial edge on the ring
}

public struct BallLocator: Sendable {
    public struct Config: Sendable, Equatable {
        public var minRadius = 6          // px at 480p; putting ball ≈ 25
        public var maxRadius = 30
        public var edgeThreshold: Float = 60   // Sobel magnitude on the 3×3-mean image
        public var radialCosine: Float = 0.95
        public var maxPeaks = 24
        public var minCoverage = 0.8
        public init() {}
    }
    public var config: Config
    public init(config: Config = Config())
    public func candidates(in image: LumaImage) -> [BallCandidate]
}
```

`candidates(in:)` follows these steps exactly. `W`/`H` are the image size. Return `[]` if `W < 3 || H < 3` or `config.minRadius < 1`.

1. **Smooth:** `s[i]` (`[Float]`) is the 3×3 box mean, with coordinates clamped at the borders (replicate).
2. **Sobel** for interior pixels `1...W-2 × 1...H-2` only:
   - `gx = (s[y-1][x+1] + 2s[y][x+1] + s[y+1][x+1]) - (s[y-1][x-1] + 2s[y][x-1] + s[y+1][x-1])`
   - `gy = (s[y+1][x-1] + 2s[y+1][x] + s[y+1][x+1]) - (s[y-1][x-1] + 2s[y-1][x] + s[y-1][x+1])`
   - `mag = sqrt(gx² + gy²)`. If `mag >= edgeThreshold`, append an edge `(x, y, ux: gx/mag, uy: gy/mag)`.
   - Edges come out in row-major order. Also record `rowStart[y]`: the index of the first edge with that `y`, with `H + 1` entries so row `y` is `rowStart[y]..<rowStart[y+1]`.
3. **Vote:** `acc` is an `[Int32]` of size `W*H`. For each edge, for `r in minRadius...maxRadius`, for `sign in [1, -1]`:
   - `cx = Int((Float(x) + sign*Float(r)*ux).rounded())`, `cy` likewise.
   - If it's in bounds, `acc[cy*W + cx] += 1`.
   - Both signs, because the ball can be darker than the background on its shaded side.
4. **Score:** `score[i]` = sum of `acc` over the 3×3 neighbourhood (out-of-bounds counts 0).
5. **Peaks:** before the loop, compute `rowBest[y]` = (max `score` in row `y`, its first `x`). Repeat up to `maxPeaks` times:
   - The argmax is the best `rowBest` entry; on ties, the lowest `y`, and within a row the lowest `x` (row-major lowest index).
   - Stop if the max is `<= 0`.
   - Zero `score` in the square `|dx| <= minRadius, |dy| <= minRadius` around it (clamped to the image), then recompute `rowBest` for those rows only. A full-image argmax scan 24 times per frame would cost more than the voting.
   - Evaluate the peak (step 6).
6. **Coverage** of a peak `(cx, cy)`:
   - `masks = [UInt16](repeating: 0, count: maxRadius + 1)` and `counts = [Int](repeating: 0, count: maxRadius + 1)`.
   - Visit only edges in rows `max(0, cy - maxRadius - 1)...min(H - 1, cy + maxRadius + 1)`, using `rowStart`.
   - For each edge: `dx = x - cx`, `dy = y - cy` (Float), `d = sqrt(dx² + dy²)`, `ri = Int(d.rounded())`. Skip it unless `minRadius <= ri && ri <= maxRadius && abs(dx*ux + dy*uy) >= radialCosine * d`.
   - `sector = Int((atan2(dy, dx) + .pi) / (2 * .pi) * 16) % 16`. Then `masks[ri] |= 1 << sector` and `counts[ri] += 1`.
   - Pick the best `r` in `minRadius...maxRadius`: highest `masks[r].nonzeroBitCount`, ties to the higher `counts[r]`, then to the smaller `r`.
   - `coverage = Double(bits) / 16`. If `coverage >= minCoverage`, append `BallCandidate(x: Double(cx), y: Double(cy), radius: Double(r), coverage:)`.
7. Return the candidates in pick order.

Performance note: the mat gives ~45 k edges per 480p frame, so voting is ~2.3 M increments. Do steps 1–6 inside `withUnsafeBufferPointer` / `withUnsafeMutableBufferPointer` so Debug builds (the test plans run Debug, `-Onone`) stay usable. Don't add Accelerate.

### `ShotDetector/PatchMatcher.swift` (new)

```swift
public struct PatchMatcher: Sendable {
    public let x: Int, y: Int, size: Int   // reference window: top-left and side, buffer pixels
    // nil when the window doesn't fit inside the image
    public init?(reference image: LumaImage, centerX: Int, centerY: Int, halfSize: Int)
    // best NCC over offsets (k*step, l*step), k,l in -n...n, n = maxShift / step; offsets whose window leaves the image are skipped; 0 if none fit
    public func similarity(in image: LumaImage, maxShift: Int, step: Int = 2) -> Double
    public static func ncc(_ a: [UInt8], _ b: [UInt8]) -> Double
}
```

- The window is `x = centerX - halfSize`, `y = centerY - halfSize`, `size = 2*halfSize + 1`. Store the reference pixels (`size*size`) and their mean and centred sum of squares once.
- `ncc`: `Σ(a-ā)(b-b̄) / sqrt(Σ(a-ā)² · Σ(b-b̄)²)` in `Double`. Return `0` when the denominator `< 1e-6` (flat patch). Precondition: equal counts.
- `similarity` uses `n = maxShift / step`, so `maxShift` 6 with step 2 gives offsets −6, −4, …, 6, which always includes 0.

### `ShotDetector/BallPresenceDetector.swift` (new)

```swift
import CoreGraphics

public struct BallPresenceDetector: ShotDetecting, Sendable {
    public struct Config: Sendable, Equatable {
        public var locator = BallLocator.Config()
        public var lockDelay = 1.0          // s still before lock (ADR 0011) = re-arm (ADR 0008)
        public var stillTolerance = 0.3     // × radius, min 2 px, from the track's first position
        public var radiusTolerance = 0.3    // × radius
        public var trackMemory = 0.5        // s a track survives without a match
        public var clutterAge = 0.5         // s still at lock time to become an ignored spot
        public var patchScale = 1.0         // patch half-side = patchScale × radius
        public var maxShift = 0.25          // × radius, NCC search
        public var presentThreshold = 0.75  // NCC
        public var absentHold = 0.3         // s (ADR 0008)
        public var maxFrameGap = 1.0        // s; longer gap → search again
        public init() {}
    }

    public let config: Config
    public var searchRegion = CGRect(x: 0, y: 0, width: 1, height: 1)
    public private(set) var ball: BallCandidate?
    public private(set) var similarity: Double?

    public init(config: Config = Config())
    public mutating func process(_ frame: VideoFrame) -> [ShotEvent]          // LumaImage(pixelBuffer:) ?? return []
    public mutating func process(_ image: LumaImage, time: Double) -> [ShotEvent]
}
```

Private state:
- `struct Track { var anchorX, anchorY, x, y, radius, coverage, firstSeen, lastSeen: Double }`
- `tracks: [Track]`
- `ignored: [BallCandidate]`
- `matcher: PatchMatcher?`
- `absentSince: Double?`
- `lastTime: Double?`
- `frameWidth = 0`, `frameHeight = 0` (0 = no frame yet; avoids an optional tuple)

`process(_ image:time:)` in order:

1. **Size:** if `frameWidth != 0` and `(frameWidth, frameHeight) != (image.width, image.height)`, clear `tracks`, `ignored`, `matcher`, `ball`, `similarity`, `absentSince` and `lastTime`. Then store the new size.
2. **Gap:** if `lastTime` is set and `time - lastTime > maxFrameGap`, call `searchAgain()`, which clears `tracks`, `matcher`, `ball`, `similarity` and `absentSince` but keeps `ignored`. Then set `lastTime = time`.
3. **Locked** (`matcher != nil`):
   - `s = matcher.similarity(in: image, maxShift: Int((maxShift * radius).rounded()))` and `similarity = s`.
   - If `s >= presentThreshold`: `absentSince = nil` and return `[]`.
   - Otherwise set `absentSince = absentSince ?? time`. If `time - absentSince >= absentHold - 0.001`, let `exit = absentSince`, call `searchAgain()` and return `[ShotEvent(time: exit)]`. Else return `[]`.
4. **Searching:**
   - Convert `searchRegion` to a pixel rect:
     - `x0 = clamp(Int((minX * W).rounded(.down)), 0, W)` and `x1 = clamp(Int((maxX * W).rounded(.up)), 0, W)`; `y0`/`y1` likewise with `H`.
     - If `x1 - x0 < 3 || y1 - y0 < 3`, return `[]`.
   - Run `BallLocator(config: config.locator).candidates(in: image.cropped(...))` and add `x0`/`y0` to each candidate.
   - Drop candidates within `max(2, stillTolerance × spot.radius)` of any ignored spot.
   - **Match:** for each candidate in order, find the first track not yet matched on this frame where `hypot(c - anchor) <= max(2, stillTolerance × track.radius)` and `abs(c.radius - track.radius) <= radiusTolerance × track.radius`.
     - On a match: update `x`, `y`, `radius`, `coverage`, `lastSeen = time`. The anchor and `firstSeen` stay.
     - Otherwise append a new track with anchor = position and `firstSeen = lastSeen = time`.
   - Remove tracks with `time - lastSeen > trackMemory`.
   - **Ready:** tracks with `lastSeen == time`, `time - firstSeen >= lockDelay - 0.001`, and a `PatchMatcher(reference: image, centerX: Int(x.rounded()), centerY: Int(y.rounded()), halfSize: Int((patchScale * radius).rounded()))` that is non-nil.
   - Pick the ready track with the max `firstSeen`, then max `coverage`, then max `radius`.
   - **Lock:**
     - `ignored +=` every other track with `time - firstSeen >= clutterAge - 0.001`, as `BallCandidate(x:y:radius:coverage:)`.
     - Set `matcher` and `ball` (from the track's current `x`, `y`, `radius`, `coverage`), `similarity = 1`, `absentSince = nil`.
     - Clear `tracks`.
   - Return `[]`.

Comment once in the file that ADR 0008 drops `occluded` and that a lock implies present ≥ 1 s (the re-arm).

### `RepsTests/` (new suites, Unit plan)

Shared test helper, a `private` free function in each file that needs it:

```swift
func luma(_ width: Int = 200, _ height: Int = 160, background: UInt8 = 60,
          discs: [(x: Int, y: Int, r: Int, value: UInt8)] = []) -> LumaImage
```

It fills the background, then sets every pixel with `(px-x)² + (py-y)² <= r²` to `value`.

`LumaImageTests.swift`:
- `copiesLumaPlaneDroppingRowPadding`: a 30×20 420f `CVPixelBuffer` (create it like `FrameScalerTests.source`), luma = `x + 2*y`. Check that `LumaImage(pixelBuffer:)` has width 30, height 20 and matching pixels. Also `#expect(CVPixelBufferGetBytesPerRowOfPlane(buffer, 0) >= 30)`.
- `nonPlanarBufferIsNil`: a 32BGRA buffer returns nil.
- `croppedCopiesTheRect`.

`BallLocatorTests.swift` (default config):
- `findsADisc` (arguments r ∈ [6, 8, 12, 20, 28]): a disc at (100, 80), value 220 on 60. Expect exactly one candidate within 1 px of the centre, `abs(radius - r) <= 1.5`, coverage ≥ 0.9.
- `findsADiscWithALightBackgroundBehindIt`: rows `0..<80` are 150, the rest 60, and a disc r 12 of value 200 at (100, 80). Expect one candidate within 1 px.
- `rejectsSquares` (arguments side ∈ [12, 16, 24, 40]): a filled square of 220 centred at (100, 80) gives `[]`.
- `rejectsAStraightEdge` (columns ≥ 100 are 220) and `rejectsAUniformImage`: both give `[]`.
- `ignoresDiscsOutsideTheRadiusRange`: r 3 in 200×160 and r 50 in 400×300 both give `[]`.
- `findsTwoDiscs`: (50, 50, r 10) and (150, 110, r 14) give two candidates, each within 1 px of one of the discs.

`PatchMatcherTests.swift` (images 100×100, disc r 12 value 220 on 60 at (50, 50), `halfSize: 12`):
- `identicalIsOne`: `ncc(a, a) == 1` (±1e-9).
- `invertedIsMinusOne`.
- `flatIsZero`.
- `nilWhenWindowLeavesImage`: centre (5, 50) with `halfSize: 12` is nil.
- `shiftedDiscStillMatches`: the disc moved to (54, 50) with `maxShift: 4` gives ≥ 0.95. Offsets are −4, −2, 0, 2, 4.
- `removedDiscDoesNotMatch`: the reference has the disc and the current image is background only, so similarity < 0.5. Flat gives 0.

`BallPresenceDetectorTests.swift`:
- Frame `i` has `t = Double(i) / 15`, fed through `process(_:time:)`. All timings below are frame indices, because 0.5 s is not a frame time.
- Disc A is the ball: (100, 80), r 14, value 220, in 200×160.
- Helper: `run(_ detector: inout BallPresenceDetector, frames: [(LumaImage, Double)]) -> [(frame: Int, events: [ShotEvent])]`.

Cases:
1. `locksAfterOneSecondStill`: A from frame 0. `ball == nil` after frame 14 and non-nil (centre within 1 px) after frame 15. No events.
2. `emitsOnceWhenGoneForHoldTime`: A in frames 0–29, gone from frame 30 (t = 2.0). Exactly one event in total, returned on frame 35 (t − 2.0 = 0.333, the first ≥ 0.299), with `time == 30.0 / 15` (±1e-9). `ball == nil` after frame 35.
3. `shortDropoutIsNotAStroke`: A gone in frames 30–33 (0.2 s), back from 34. No events. Still locked at frame 40.
4. `relocksANewBallAndCountsAgain`: A in frames 0–29 (event at time 2.0). Disc B at (60, 100), r 12 from frame 45, locked after frame 60, gone from frame 75. Two events, at times 30/15 and 75/15.
5. `staticClutterNeverLocksLater`:
   - A and C at (40, 40), r 10 both from frame 0. After frame 15, `ball` is A: same `firstSeen`, both coverage 1.0, the larger radius wins.
   - A gone from frame 30 (event). C stays to frame 90, and `ball` stays nil through frame 74.
   - D at (150, 120), r 12 from frame 60. `ball` is D after frame 75.
6. `oldEnoughCandidateAtLockBecomesClutter`: A from frame 0 and B at (60, 100), r 12 from frame 6 (0.6 s old at frame 15). A locks after frame 15. A gone from frame 30 (event on 35). B stays to frame 75 and never locks.
7. `youngCandidateAtLockIsNotClutter`: same as 6, but B from frame 10 (0.33 s old at frame 15). After the event on frame 35, searching restarts on frame 36. B locks after frame 51 (36 + 15).
8. `movingDiscDoesNotLock`: 240×160 images, a disc r 14 starting at (30, 80) and moving +6 px in x per frame (more than `max(2, 0.3·14)` = 4.2) for 30 frames, ending at x = 204. `ball` stays nil.
9. `sizeChangeResets`: lock at 200×160 (frames 0–20). From frame 21, 160×200 frames with the disc at (80, 100): `ball == nil` after frame 21, non-nil after frame 36, no events.
10. `longGapSearchesAgainWithoutEvent`: lock (frames 0–20), then frames from `t = 20.0/15 + 1.5` on, without the disc, for 2 s. `ball == nil` and no events.
11. `searchRegionLimitsTheLocator`: a disc at (150, 80) for 30 frames. With `searchRegion = CGRect(x: 0, y: 0, width: 0.5, height: 1)` it never locks. With the default region it locks after frame 15.
12. `pixelBufferFramesWork`: 20 frames through `process(_ frame: VideoFrame)`, using 420f `CVPixelBuffer`s whose plane 0 rows are copied from `luma(...)` with A (chroma plane 128). `ball != nil` after frame 15.

### `DetectorEvalTests/BallPresenceEvalTests.swift` (new)

Same shape as `OracleEvalTests.putting`:

```swift
@Suite(.enabled(if: MLData.root.map(EvalDataset.hasPutting) == true, "no putting footage; set REPS_ML_DIR"))
struct BallPresenceEvalTests {
    @Test func putting() async throws {
        let dataset = try EvalDataset.putting(root: try #require(MLData.root))
        let report = try await EvalRunner().run("ball-presence-putting", on: dataset) { _ in BallPresenceDetector() }
        try EvalOutput.publish(report)
        let all = report.overall
        // Floors, not targets: the planner's prototype scored recall 19/22, precision 19/20 (docs/plans/14-ball-presence.md). #21 sets the real gates.
        #expect(try #require(all.recall) >= 0.7)
        #expect(try #require(all.precision) >= 0.8)
    }
}
```

No range suite. Range needs the feet region (#19), and a whole-frame search on the range would lock downrange balls.

### Docs

- `docs/code-reference.md`: one entry each for the four ShotDetector files, the four RepsTests suites and `BallPresenceEvalTests`, in the existing style (one line per public type or function). Each goes in the commit that adds the file.
- `docs/adr/0017-ball-locator-and-presence.md` and its row in `docs/adr/README.md` are already written by the planner.
- `docs/roadmap.md`: mark #14 done when the PR merges (CLAUDE.md).
- `docs/open-questions.md`: Q45 and Q46 are already added by the planner. When the PR merges, append the measured Swift recall/precision to Q46's notes.

## Steps

Branch `feat/14-ball-presence` (checked out). Before every commit:
- run `xcrun swift-format lint --strict --recursive --parallel ShotDetector RepsTests DetectorEvalTests`
- run `grep -rnE 'import (AVFoundation|AVKit|UIKit|SwiftUI|CoreMedia)' ShotDetector`, which must print nothing.

Commit bodies end with `Refs #14`. TDD: write the test file first, see it fail to compile or fail, implement, then see it pass.

```sh
DEST='platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'
```

1. **LumaImage**
   - Add `RepsTests/LumaImageTests.swift`, then `ShotDetector/LumaImage.swift`.
   - Run `xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan Unit -destination "$DEST" -only-testing:RepsTests/LumaImageTests`.
   - Add this step's entries to `docs/code-reference.md` (the file and its test suite) in the same commit (CLAUDE.md).
   - Commit `added luma image for detectors`.
2. **BallLocator**
   - Add `RepsTests/BallLocatorTests.swift`, then `ShotDetector/BallLocator.swift`, implemented exactly as specified.
   - Run with `-only-testing:RepsTests/BallLocatorTests`.
   - If `rejectsSquares` fails, check the exact-ring rule (`ri == r`, not ±1) and `radialCosine` 0.95 before changing anything else.
   - Add this step's entries to `docs/code-reference.md` (the file and its test suite) in the same commit (CLAUDE.md).
   - Commit `added ball locator`.
3. **PatchMatcher**
   - Add the test file, then the implementation.
   - Run with `-only-testing:RepsTests/PatchMatcherTests`.
   - Add this step's entries to `docs/code-reference.md` (the file and its test suite) in the same commit (CLAUDE.md).
   - Commit `added ncc patch matcher`.
4. **BallPresenceDetector**
   - Add the test file, then the implementation.
   - Run with `-only-testing:RepsTests/BallPresenceDetectorTests`, plus the three suites above.
   - If case 5's tie goes to C, print both candidates' coverage. Don't change the tie rule; the planner measured both discs at 1.0.
   - Add this step's entries to `docs/code-reference.md` (the file and its test suite) in the same commit (CLAUDE.md).
   - Commit `added ball presence detector`.
5. **Eval**
   - Add `DetectorEvalTests/BallPresenceEvalTests.swift`.
   - Run `xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan DetectorEval -destination "$DEST" -only-testing:DetectorEvalTests/BallPresenceEvalTests`. With footage in `ml/`, `MLData.root` finds it; otherwise set `TEST_RUNNER_REPS_ML_DIR`.
   - Read `build/eval/ball-presence-putting.txt`.
   - If the floors fail, you may try **only** these single-knob changes to the `Config()` defaults, one at a time:
     - `presentThreshold` 0.7 or 0.8
     - `locator.minCoverage` 0.75
   - Diagnostic if the floors still fail: rerun once with `clutterAge = .infinity` (no ignored spots) and report both results in the PR. That tells a clutter-list problem from a threshold problem. Don't ship that setting.
   - Keep the best. If none passes, stop: commit with the failing numbers in the PR body and leave the floors unchanged. Don't invent new algorithm steps.
   - Note the run time from the report. If it's over 5 minutes, say so in the PR.
   - Add this step's entries to `docs/code-reference.md` (the file and its test suite) in the same commit (CLAUDE.md).
   - Commit `added ball presence eval`.
6. **Open question**
   - Add the measured numbers to Q46 in `docs/open-questions.md`.
   - Run the full `Unit` plan once (`-testPlan Unit`, no filter) and the build.
   - Commit `recorded ball presence eval numbers`.

## Tests

- Unit (`RepsTests`): `LumaImageTests`, `BallLocatorTests`, `PatchMatcherTests`, `BallPresenceDetectorTests`, all synthetic and under 1 s each.
- DetectorEval: `BallPresenceEvalTests.putting` (footage, skips without it). The harness's pure suites are unchanged, so there's no need to rerun them.
- No UI tests: there's no UI.

## Risks and unresolved

- **Putter resting against the ball** breaks the circle, so no lock happens and that putt is missed. That's 2 of 22 in the prototype. #15's tap override or a lower `minCoverage` (#16) are the fixes, and a trained detector is the fallback (ADR 0011, Phase 6). See Q46.
- **Wrong lock at session start (deviation from ADR 0011's "newest"):** something round and static that is in view before the ball (and not tied with it) locks first, because the first track to reach 1 s wins. Nothing frees it until #15's tap. Setup copy (#15) tells the user to keep other balls out of view. See Q46.
- **Thin NCC margin** (present p5 0.69 vs absent max 0.75). Measured alternative: re-check the circle at the lock (19/22, 0 FP). #16 decides. See Q46.
- **Pickups 0.73 s apart** (212.16 and 212.89 s) can't both count, so recall 22/22 is impossible on this clip. See Q45.
- **The track/clutter rules are sensitive.** Raising `trackMemory` to 1.0 s or 1.5 s dropped recall to 8/22 or 10/22, and the cause was not isolated (ignored spots near the ball, or sparse-sighting locks).
- **Clutter memory is position-only.** A real ball placed exactly where clutter sat at a previous lock won't lock. This is unlikely, and frame size changes clear it.
- **Debug speed:** eval runs at `-Onone`, the locator runs on every searching frame (~60 % of frames), and the clip has ~45 k edges per frame. If eval time hurts, a later issue can halve the locator's rate while searching.
- **Range** isn't evaluated here: a whole-frame search would lock downrange or pile balls. #19 supplies the feet region, and min/max radius will need range values there (balls ≈ 5–8 px radius at 480p).
- **Tuning belongs to #16** (Q17). #14 ships defaults and floors only.
