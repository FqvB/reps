# #13 Camera pipeline

Goal: while the session screen is up, run the back camera at 1080p60. Fan every frame out to a clip sink (#22), and every 1/15 s hand an upright 480p 420f `VideoFrame` to a detector sink (#14, #16, #19). Handle interruptions, runtime errors and app background per §6. Counting by hand keeps working whatever the camera does.

Spec: §5.6 ("Capture at 1080p60 … Detection processes every 4th frame, downscaled to ~480 px wide"), §6 ("Phone call / Siri / notification interrupts the camera: Capture pauses, count is kept, voice says "paused"; resumes when the app is foregrounded"; "Camera … permission denied: Explain what stops working and deep-link to Settings; manual counting still works"), §4 (ShotDetector has no AVFoundation), §5.8 (clips need every frame). ADRs: 0010 (detector frame contract), 0014 (ask in context, never block), 0015 (`VoiceAudioSession` owns audio), 0013 (handlers never call back into the controller), 0003 (clips via AVAssetWriter), and **new 0016** (`docs/adr/0016-camera-pipeline-fan-out.md`, already written by the planner).

Scope note: the issue names only the pipeline, but `SessionView` carries `// PLACEHOLDER: camera preview (#13)` and design.md says "Camera area is a placeholder until #13". The camera also needs an owner that starts and stops it. So this plan also ships the preview, the session-screen wiring, the in-context permission check (ADR 0014) and the status copy. All of that is step 4 (plus `CameraSession` in step 3). Steps 1–3 stand alone if the owner wants the UI split out.

Out of scope: ball locator/presence (#14), lock box UI (#15), putting detector (#16), pose/fusion (#17–#19), clip writer (#22), thermal/battery reactions (#28; the seam is `FrameSampler.interval`), mic/audio input (#22), any `SessionController` change. Nothing calls `CameraPipeline.setSinks` yet; it is the fan-out seam the issue asks for.

Branch `feat/13-camera-pipeline` (already checked out). Never edit `project.pbxproj`. New `Reps/Camera/` and the new files in `RepsTests/`, `ShotDetector/` and `Reps/UI/Session/` are picked up by the synced folders (ADR 0009). The app and `RepsTests` already link `ShotDetector`.

**Already verified by the planner** in a scratch copy of the repo with every change below applied:
- A clean build and `swift-format lint --strict` pass. None of the new or changed files produce warnings; the only build warnings are pre-existing ones in `AppSettingsTests` and `SessionControllerTests`.
- The listed Unit suites pass on the iPhone 17 Pro simulator (55 tests, including `SpeechAnnouncerTests`).
- With `TEST_RUNNER_REPS_ML_DIR` pointing at `ml/`, `VideoFrameReaderTests` (footage decode) and `OracleEvalTests` pass. The `oracle-range` and `oracle-putting` reports are identical to an untouched checkout except for the run time, so the moved sampler changes nothing in eval. Copy the code **verbatim**. If something doesn't compile, fix the smallest thing and say so in the PR. Don't redesign.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Output | One `AVCaptureVideoDataOutput`, 420f (`DetectorInput.pixelFormat`), `alwaysDiscardsLateVideoFrames = true`. Three serial queues: `sessionQueue` (configure, `startRunning`/`stopRunning`, notifications, `onStatus`), `frameQueue` (sample delegate, sinks, sampler, rotation), `detectorQueue` (detector sink). | One output can feed both consumers. Context7: `startRunning()` "is a blocking call … start the session on a serial dispatch queue". Apple's samples keep a separate data-output queue, so frames never wait on start/stop. Late frames are dropped while the delegate queue is blocked, which keeps memory bounded. Each mutable property has exactly one owning queue. |
| Format | `CaptureFormat.best`: 1080p only. Among formats reaching ≥ 60 fps, the one with the lowest max (skips 120/240 slow-mo formats); otherwise the fastest 1080p one. Ties: 420f first, then device order. Duration locked at `CMTime(1, 60)` when the range contains 60, else `range.minFrameDuration`. | Context7: high frame rates need `activeFormat` + `activeVideoMin/MaxFrameDuration` inside `lockForConfiguration`; presets can't do 60 fps. The value must lie inside the range or it throws, hence the guard. |
| Rotation | Connection `videoRotationAngle = 0` (sensor-native buffers). The capture angle comes from `AVCaptureDevice.RotationCoordinator(device:previewLayer: nil).videoRotationAngleForHorizonLevelCapture` (KVO, main queue) and is stored as quarter turns on `frameQueue`. The clip sink gets `rotationDegrees`. The detector copy is turned upright by `VTPixelRotationSession` at 480p. | Context7 + SDK header: physical rotation on a data output "costs work on every frame" and reconfigures the pipeline; asset writers should use `transform`. ADR 0016 supersedes ADR 0010's line about the connection angle. Detectors still get `.up`. |
| Downscale | `FrameScaler`: `VTPixelTransferSession` to `DetectorInput.scaledSize` (854×480 from 1080p), then rotate. Buffers come from `CVPixelBufferPool`s keyed by size. Always a copy, never the camera's buffer. | Hardware scaler, no extra deps. A detector holding a camera buffer would starve the capture pool. |
| Sampling | Timestamp-based `FrameSampler` moved into ShotDetector, used by both the pipeline and `VideoFrameReader` (eval). | Same 1/15 s rule live and in eval (ADR 0010). It survives dropped frames, and `interval` is the #28 thermal seam. The code moves verbatim, so eval output doesn't change. |
| Detector queue | Detector sink runs on its own serial `detectorQueue`. A `Mutex<Bool>` "busy" flag skips new frames while the last one is still being processed (never queues). | Vision pose can take tens of ms; on `frameQueue` that would drop 60 fps clip frames. ADR 0010 already says detectors use time, not frame counts. |
| UI state | `@MainActor @Observable CameraSession` (permission gate, status, "Paused." once per interruption), over a `nonisolated protocol CameraRunning` implemented by `CameraPipeline` and a test fake. | Same pattern as `OnboardingModel` + `FakePermissions`; the logic is testable without a camera. |
| Permission | `CameraSession.start()`: granted → start; notDetermined → `request(.camera)` then decide; denied → `.denied` (note + Open Settings); restricted → `.restricted` (note, no action). Re-run on every return to `.active`, so a grant in Settings takes effect. | ADR 0014. |
| Interruptions | Observe `wasInterruptedNotification` → `.interrupted`, `interruptionEndedNotification` → `.running`, `runtimeErrorNotification` → one `startRunning()` retry on `.mediaServicesWereReset`, else `.unavailable`. No explicit stop on background; the system interrupts and resumes. `SessionView` calls `camera.start()` on `scenePhase == .active` to revive a stopped session. | Context7 `InterruptionReason` docs (background, other client, system pressure, …). AVCam pattern for resets. |
| "Paused." | Spoken once per interruption, whatever the reason (§6), via a new `SessionEvent.capturePaused` the announcer already knows how to queue. Sent by `CameraSession`, never by `SessionController` (ADR 0013). | With no mic input, a call usually backgrounds the app, so a reason filter would make the line nearly never play. Whether it's audible while backgrounding is Q43 (device check). |
| Audio | `captureSession.automaticallyConfiguresApplicationAudioSession = false`. | `VoiceAudioSession` owns the app audio session (ADR 0015, Q41). |
| Lifetime | `RootView.controller()` creates one `CameraSession(pipeline: CameraPipeline(), …)` next to the announcer (app lifetime). `SessionView` starts it in `.task` and stops it in `.onDisappear`. Configuration runs once, on first start. | The announcer lives there; "Paused." needs it. Configuring once avoids re-adding inputs. |
| Preview | `CameraPreview` (`UIViewRepresentable`, `AVCaptureVideoPreviewLayer`, `.resizeAspectFill`), shown only while `status == .running`, inside the existing 190/150 pt rounded rect. Its own `RotationCoordinator(device:previewLayer:)` sets the preview connection angle. Otherwise `SessionDisplay.cameraNote` text is shown, with "Open Settings" when denied. | The preview layer is a separate output; no data-output work. Shown only when running, so its connection already exists when the coordinator's `.initial` fires. #28 can hide it at `.serious`. |
| Not used | `AVCaptureMovieFileOutput`, multi-cam, `automaticallyRunsDeferredStart` (iOS 26), `NotificationCenter` typed messages (none exist for capture in the iOS 27.2 SDK overlay). | Not needed for this feature. |

## Files

### New `ShotDetector/FrameSampler.swift`

```swift
// Picks frames by timestamp at a fixed rate, so dropped or uneven frames don't change the rate (spec §5.6, ADR 0016).
// Shared by the camera pipeline and the eval decoder so both sample alike.
public struct FrameSampler {
    // Seconds between taken frames; #28 raises it under thermal load.
    public var interval: Double
    private var nextDue = -Double.infinity

    public init(frameRate: Double = DetectorInput.frameRate) {
        interval = 1 / frameRate
    }

    public mutating func take(_ time: Double) -> Bool {
        // 1 ms slack so 29.97 fps footage still lands on every 2nd frame.
        guard time + 0.001 >= nextDue else { return false }
        nextDue = nextDue.isFinite ? max(nextDue + interval, time + interval / 2) : time + interval
        return true
    }
}
```

### Change `ShotDetector/VideoFrame.swift` (move `scaledSize` here, Int-based)

```diff
--- a/ShotDetector/VideoFrame.swift
+++ b/ShotDetector/VideoFrame.swift
@@ -19,4 +19,12 @@
     public static let frameRate: Double = 15
     public static let shortSide = 480
     public static let pixelFormat: OSType = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
+
+    // Even dimensions with the short side at shortSide; nil if the image is already that small.
+    public static func scaledSize(width: Int, height: Int, shortSide: Int = shortSide) -> (width: Int, height: Int)? {
+        let scale = Double(shortSide) / Double(min(width, height))
+        guard scale < 1 else { return nil }
+        func even(_ value: Int) -> Int { Int((Double(value) * scale / 2).rounded()) * 2 }
+        return (even(width), even(height))
+    }
 }
```

### Change `DetectorEvalTests/Harness/VideoFrameReader.swift` (use the shared sampler and size; delete its own `scaledSize`)

```diff
--- a/DetectorEvalTests/Harness/VideoFrameReader.swift
+++ b/DetectorEvalTests/Harness/VideoFrameReader.swift
@@ -24,7 +24,10 @@
         let orientation = Self.orientation(from: transform)
 
         var settings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: DetectorInput.pixelFormat]
-        if let shortSide, let size = Self.scaledSize(naturalSize, shortSide: shortSide) {
+        if let shortSide,
+            let size = DetectorInput.scaledSize(
+                width: Int(naturalSize.width), height: Int(naturalSize.height), shortSide: shortSide)
+        {
             settings[kCVPixelBufferWidthKey as String] = size.width
             settings[kCVPixelBufferHeightKey as String] = size.height
         }
@@ -35,17 +38,14 @@
         guard reader.startReading() else { throw ReadError.cannotRead(url, reader.error) }
 
         var times: [Double] = []
-        var nextDue = -Double.infinity
-        let step = frameRate.map { 1 / $0 } ?? 0
+        var sampler = frameRate.map { FrameSampler(frameRate: $0) }
         while let sample = output.copyNextSampleBuffer() {
             let time = sample.presentationTimeStamp.seconds
             // Only samples with an image buffer count as decoded frames, so an empty sample
             // can't shift the frame-number → timestamp mapping labels are put on.
             guard let pixelBuffer = sample.imageBuffer else { continue }
             times.append(time)
-            // 1 ms slack so 29.97 fps footage still lands on every 2nd frame.
-            guard time + 0.001 >= nextDue else { continue }
-            nextDue = nextDue.isFinite ? max(nextDue + step, time + step / 2) : time + step
+            guard sampler?.take(time) ?? true else { continue }
             try body(VideoFrame(pixelBuffer: pixelBuffer, time: time, orientation: orientation))
         }
         if reader.status == .failed { throw ReadError.cannotRead(url, reader.error) }
@@ -61,12 +61,4 @@
         default: .up
         }
     }
-
-    // Even dimensions with the short side at shortSide; nil if the video is already that small.
-    static func scaledSize(_ size: CGSize, shortSide: Int) -> (width: Int, height: Int)? {
-        let scale = Double(shortSide) / Double(min(size.width, size.height))
-        guard scale < 1 else { return nil }
-        func even(_ value: Double) -> Int { Int((value * scale / 2).rounded()) * 2 }
-        return (even(size.width), even(size.height))
-    }
 }
```

### Change `DetectorEvalTests/VideoFrameReaderTests.swift`

```diff
--- a/DetectorEvalTests/VideoFrameReaderTests.swift
+++ b/DetectorEvalTests/VideoFrameReaderTests.swift
@@ -11,13 +11,14 @@
         (CGSize(width: 1280, height: 720), 854, 480),
     ])
     func scaledSizeKeepsAspectWithEvenSides(size: CGSize, width: Int, height: Int) throws {
-        let scaled = try #require(VideoFrameReader.scaledSize(size, shortSide: 480))
+        let scaled = try #require(
+            DetectorInput.scaledSize(width: Int(size.width), height: Int(size.height), shortSide: 480))
         #expect(scaled.width == width)
         #expect(scaled.height == height)
     }
 
     @Test func smallVideoIsNotScaled() {
-        #expect(VideoFrameReader.scaledSize(CGSize(width: 640, height: 480), shortSide: 480) == nil)
+        #expect(DetectorInput.scaledSize(width: 640, height: 480, shortSide: 480) == nil)
     }
 
     @Test func orientationFollowsRotation() {
```

### New `Reps/Camera/CaptureFormat.swift`

```swift
import Foundation

// One device format as the picker sees it.
nonisolated struct FormatCandidate: Equatable, Sendable {
    var width: Int
    var height: Int
    var maxFrameRate: Double
    var isFullRange: Bool
}

// §5.6: capture 1080p at 60 fps, or the closest the camera offers.
nonisolated enum CaptureFormat {
    static let width = 1920
    static let height = 1080
    static let frameRate = 60.0

    // 1080p only. With formats reaching 60 fps, the slowest of them (skips slow-mo formats); otherwise the
    // fastest. Then 420f, then the device's order. Nil without any 1080p format.
    static func best(_ candidates: [FormatCandidate]) -> Int? {
        let hd = candidates.indices.filter { candidates[$0].width == width && candidates[$0].height == height }
        let fast = hd.filter { candidates[$0].maxFrameRate >= frameRate }
        let ranked = (fast.isEmpty ? hd : fast).sorted { a, b in
            let (first, second) = (candidates[a], candidates[b])
            if first.maxFrameRate != second.maxFrameRate {
                return fast.isEmpty
                    ? first.maxFrameRate > second.maxFrameRate : first.maxFrameRate < second.maxFrameRate
            }
            if first.isFullRange != second.isFullRange { return first.isFullRange }
            return a < b
        }
        return ranked.first
    }
}
```

### New `Reps/Camera/FrameScaler.swift`

```swift
import CoreVideo
import ShotDetector
import VideoToolbox

// Makes the detector copy of a camera frame: short side DetectorInput.shortSide, 420f, turned upright (ADR 0016).
// Not thread-safe; CameraPipeline uses it only on its frame queue.
nonisolated final class FrameScaler {
    private let transfer: VTPixelTransferSession
    private let rotation: VTPixelRotationSession
    private var appliedTurns = 0
    private var pools: [Size: CVPixelBufferPool] = [:]

    private struct Size: Hashable {
        var width: Int
        var height: Int
    }

    init?() {
        var transfer: VTPixelTransferSession?
        var rotation: VTPixelRotationSession?
        guard VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &transfer) == noErr,
            VTPixelRotationSessionCreate(nil, &rotation) == noErr,
            let transfer, let rotation
        else { return nil }
        self.transfer = transfer
        self.rotation = rotation
    }

    deinit {
        VTPixelTransferSessionInvalidate(transfer)
        VTPixelRotationSessionInvalidate(rotation)
    }

    // Clockwise quarter turns (0...3) for a rotation angle in degrees, snapped to the nearest 90°.
    static func quarterTurns(_ degrees: Double) -> Int {
        ((Int((degrees / 90).rounded()) % 4) + 4) % 4
    }

    // Always a new buffer, never the camera's own, so a detector holding a frame can't starve capture.
    func detectorBuffer(from source: CVPixelBuffer, quarterTurns: Int) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        let scaled = DetectorInput.scaledSize(width: width, height: height) ?? (width, height)
        guard let small = makeBuffer(Size(width: scaled.width, height: scaled.height)),
            VTPixelTransferSessionTransferImage(transfer, from: source, to: small) == noErr
        else { return nil }
        let turns = Self.quarterTurns(Double(quarterTurns * 90))
        guard turns != 0 else { return small }
        if turns != appliedTurns {
            let value = [kVTRotation_0, kVTRotation_CW90, kVTRotation_180, kVTRotation_CCW90][turns]
            guard VTSessionSetProperty(rotation, key: kVTPixelRotationPropertyKey_Rotation, value: value) == noErr
            else { return nil }
            appliedTurns = turns
        }
        let size =
            turns % 2 == 1
            ? Size(width: scaled.height, height: scaled.width) : Size(width: scaled.width, height: scaled.height)
        guard let upright = makeBuffer(size), VTPixelRotationSessionRotateImage(rotation, small, upright) == noErr
        else { return nil }
        return upright
    }

    private func makeBuffer(_ size: Size) -> CVPixelBuffer? {
        if pools[size] == nil {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: DetectorInput.pixelFormat,
                kCVPixelBufferWidthKey as String: size.width,
                kCVPixelBufferHeightKey as String: size.height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            ]
            var pool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
            pools[size] = pool
        }
        guard let pool = pools[size] else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        return buffer
    }
}
```

### New `Reps/Camera/CameraSession.swift`

```swift
import AVFoundation
import Observation

// What the session screen shows for the camera (§6).
nonisolated enum CameraStatus: Equatable, Sendable {
    case off
    case running
    // The system took the camera (app in the background, call, Siri, another camera app, heat); it comes back by itself.
    case interrupted
    // No camera (simulator), setup failed, or a runtime error a restart didn't fix.
    case unavailable
    case denied
    case restricted
}

// The capture seam: CameraPipeline in the app, a fake in tests.
nonisolated protocol CameraRunning: AnyObject, Sendable {
    var captureSession: AVCaptureSession { get }
    var device: AVCaptureDevice? { get }
    // Starts capture unless it's running; statuses arrive on any thread until stop().
    func start(onStatus: @escaping @Sendable (CameraStatus) -> Void)
    func stop()
}

// Camera state for the session screen: asks for the camera in context (ADR 0014), starts and stops capture,
// and says "Paused." once per interruption (§6). Counting never depends on it.
@Observable
final class CameraSession {
    private(set) var status: CameraStatus = .off

    @ObservationIgnored let pipeline: any CameraRunning
    @ObservationIgnored private let permissions: any CapturePermissions
    @ObservationIgnored private let onPaused: () -> Void
    @ObservationIgnored private var wantsCapture = false

    init(pipeline: any CameraRunning, permissions: any CapturePermissions, onPaused: @escaping () -> Void = {}) {
        self.pipeline = pipeline
        self.permissions = permissions
        self.onPaused = onPaused
    }

    // Session screen appeared or the app came back to the foreground; safe to call repeatedly.
    func start() async {
        wantsCapture = true
        var permission = permissions.state(of: .camera)
        if permission == .notDetermined {
            permission = await permissions.request(.camera)
        }
        // stop() ran while the prompt was up.
        guard wantsCapture else { return }
        switch permission {
        case .granted:
            guard status != .running else { return }
            pipeline.start { [weak self] status in
                Task { @MainActor in self?.receive(status) }
            }
        case .restricted:
            status = .restricted
        case .denied, .notDetermined:
            status = .denied
        }
    }

    func stop() {
        wantsCapture = false
        pipeline.stop()
        status = .off
    }

    // Statuses from the pipeline; ignored after stop() so a late one can't revive the screen.
    func receive(_ new: CameraStatus) {
        guard wantsCapture else { return }
        if new == .interrupted, status != .interrupted {
            onPaused()
        }
        status = new
    }
}
```

### New `Reps/Camera/CameraPipeline.swift`

```swift
import AVFoundation
import ShotDetector
import Synchronization

// §5.6, ADR 0016: one 1080p60 back-camera session. Every frame goes to the sample sink (clip writer, #22);
// every 1/15 s a downscaled upright copy goes to the detector sink on its own queue (#14, #16, #19).
// Session state lives on `sessionQueue`, frame state on `frameQueue` (Apple's AVCam layout), hence @unchecked Sendable.
nonisolated final class CameraPipeline: NSObject, CameraRunning, @unchecked Sendable {
    // Sensor-native full-rate frame plus the clockwise rotation (0/90/180/270) that makes it upright; on `frameQueue`.
    typealias SampleSink = @Sendable (CMSampleBuffer, _ rotationDegrees: Int) -> Void
    // Downscaled upright frame, called in time order on the detector queue.
    typealias DetectorSink = @Sendable (VideoFrame) -> Void

    let captureSession = AVCaptureSession()
    let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)

    // startRunning/stopRunning block, so they get their own queue; frames never wait on them.
    private let sessionQueue = DispatchQueue(label: "com.fqvb.reps.camera.session", qos: .userInitiated)
    private let frameQueue = DispatchQueue(label: "com.fqvb.reps.camera.frames", qos: .userInitiated)
    private let detectorQueue = DispatchQueue(label: "com.fqvb.reps.camera.detect", qos: .userInitiated)
    // True while the detectors are still on the previous frame; new ones are skipped, never queued.
    private let detectorBusy = Mutex(false)
    private let scaler = FrameScaler()

    // sessionQueue only.
    private var onStatus: (@Sendable (CameraStatus) -> Void)?
    private var isConfigured = false
    private var observers: [any NSObjectProtocol] = []
    private var coordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?

    // frameQueue only.
    private var sampleSink: SampleSink?
    private var detectorSink: DetectorSink?
    private var sampler = FrameSampler()
    private var quarterTurns = 0

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func start(onStatus: @escaping @Sendable (CameraStatus) -> Void) {
        sessionQueue.async { [self] in
            self.onStatus = onStatus
            guard isConfigured || configure() else { return report(.unavailable) }
            if !captureSession.isRunning { captureSession.startRunning() }
            // An interrupted session reports through the interruption notifications instead.
            guard !captureSession.isInterrupted else { return }
            report(captureSession.isRunning ? .running : .unavailable)
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            onStatus = nil
            if captureSession.isRunning { captureSession.stopRunning() }
        }
    }

    // Consumers attach here; nil detaches. Takes effect on the next frame.
    func setSinks(sample: SampleSink?, detector: DetectorSink?) {
        frameQueue.async { [self] in
            sampleSink = sample
            detectorSink = detector
            sampler = FrameSampler()
        }
    }

    // Once, on `sessionQueue`. False without a camera (simulator) or when the session refuses the input or output.
    private func configure() -> Bool {
        guard let device, let input = try? AVCaptureDeviceInput(device: device) else { return false }
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: DetectorInput.pixelFormat]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: frameQueue)

        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        // VoiceAudioSession owns the app audio session (ADR 0015, Q41).
        captureSession.automaticallyConfiguresApplicationAudioSession = false
        guard captureSession.canAddInput(input), captureSession.canAddOutput(output) else { return false }
        captureSession.addInput(input)
        captureSession.addOutput(output)
        // Sensor-native buffers: rotating every 1080p60 frame on the connection costs energy (ADR 0016).
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(0) {
            connection.videoRotationAngle = 0
        }
        applyBestFormat(device)
        observeSession()
        observeRotation(device)
        isConfigured = true
        return true
    }

    private func applyBestFormat(_ device: AVCaptureDevice) {
        let formats = device.formats
        guard let index = CaptureFormat.best(formats.map(FormatCandidate.init)),
            let range = formats[index].videoSupportedFrameRateRanges.max(by: { $0.maxFrameRate < $1.maxFrameRate }),
            (try? device.lockForConfiguration()) != nil
        else { return }
        defer { device.unlockForConfiguration() }
        device.activeFormat = formats[index]
        // Exactly 60 fps when the range allows it; otherwise the range's own fastest rate, which is always valid.
        let sixty = range.minFrameRate <= CaptureFormat.frameRate && range.maxFrameRate >= CaptureFormat.frameRate
        let duration = sixty ? CMTime(value: 1, timescale: 60) : range.minFrameDuration
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
    }

    private func observeSession() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: AVCaptureSession.wasInterruptedNotification, object: captureSession, queue: nil
            ) { [weak self] _ in
                guard let self else { return }
                self.sessionQueue.async { self.report(.interrupted) }
            },
            center.addObserver(
                forName: AVCaptureSession.interruptionEndedNotification, object: captureSession, queue: nil
            ) { [weak self] _ in
                guard let self else { return }
                self.sessionQueue.async { self.report(.running) }
            },
            center.addObserver(
                forName: AVCaptureSession.runtimeErrorNotification, object: captureSession, queue: nil
            ) { [weak self] note in
                let code = (note.userInfo?[AVCaptureSessionErrorKey] as? AVError)?.code
                guard let self else { return }
                self.sessionQueue.async { self.recover(from: code) }
            },
        ]
    }

    // §6: a media-services reset gets one restart while capture is wanted; anything else leaves manual counting.
    private func recover(from code: AVError.Code?) {
        guard onStatus != nil else { return }
        if code == .mediaServicesWereReset {
            captureSession.startRunning()
            if captureSession.isRunning { return report(.running) }
        }
        report(.unavailable)
    }

    private func observeRotation(_ device: AVCaptureDevice) {
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        self.coordinator = coordinator
        // KVO arrives on the main queue (AVFoundation docs); .initial delivers the current angle.
        rotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]
        ) { [weak self] coordinator, _ in
            let turns = FrameScaler.quarterTurns(coordinator.videoRotationAngleForHorizonLevelCapture)
            guard let self else { return }
            self.frameQueue.async { self.quarterTurns = turns }
        }
    }

    private func report(_ status: CameraStatus) {
        onStatus?(status)
    }
}

extension CameraPipeline: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection
    ) {
        sampleSink?(sampleBuffer, quarterTurns * 90)
        guard let detectorSink, let pixelBuffer = sampleBuffer.imageBuffer else { return }
        let time = sampleBuffer.presentationTimeStamp.seconds
        guard sampler.take(time) else { return }
        let claimed = detectorBusy.withLock { busy in
            if busy { return false }
            busy = true
            return true
        }
        guard claimed else { return }
        guard let upright = scaler?.detectorBuffer(from: pixelBuffer, quarterTurns: quarterTurns) else {
            detectorBusy.withLock { $0 = false }
            return
        }
        // Handed off: this queue never touches the copy again.
        nonisolated(unsafe) let frame = VideoFrame(pixelBuffer: upright, time: time)
        detectorQueue.async { [self] in
            detectorSink(frame)
            detectorBusy.withLock { $0 = false }
        }
    }
}

extension FormatCandidate {
    nonisolated init(_ format: AVCaptureDevice.Format) {
        let dimensions = format.formatDescription.dimensions
        self.init(
            width: Int(dimensions.width), height: Int(dimensions.height),
            maxFrameRate: format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0,
            isFullRange: format.formatDescription.mediaSubType.rawValue
                == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
    }
}
```

### New `Reps/UI/Session/CameraPreview.swift`

```swift
import AVFoundation
import SwiftUI
import UIKit

// The live camera image (§5.6), kept level with the horizon by a rotation coordinator.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let device: AVCaptureDevice?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        if let device { view.followRotation(of: device) }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        private var coordinator: AVCaptureDevice.RotationCoordinator?
        private var observation: NSKeyValueObservation?

        func followRotation(of device: AVCaptureDevice) {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
            self.coordinator = coordinator
            // KVO arrives on the main queue (AVFoundation docs); .initial applies the current angle.
            observation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) {
                [weak self] coordinator, _ in
                let angle = coordinator.videoRotationAngleForHorizonLevelPreview
                MainActor.assumeIsolated {
                    guard let connection = self?.previewLayer.connection,
                        connection.isVideoRotationAngleSupported(angle)
                    else { return }
                    connection.videoRotationAngle = angle
                }
            }
        }
    }
}
```

### Change `Reps/Session/SessionEvent.swift`

```diff
--- a/Reps/Session/SessionEvent.swift
+++ b/Reps/Session/SessionEvent.swift
@@ -10,4 +10,6 @@
     case planEnded
     // Done saved the session (§5.7 "Done. Session saved."); not sent when finish() discards or the save fails.
     case sessionSaved
+    // Sent by CameraSession, not the controller: the system interrupted capture (§6).
+    case capturePaused
 }
```

### Change `Reps/Voice/VoiceLines.swift` ("Paused." is spec wording, not a placeholder)

```diff
--- a/Reps/Voice/VoiceLines.swift
+++ b/Reps/Voice/VoiceLines.swift
@@ -17,6 +17,7 @@
     static let targetReached = "Target reached."  // PLACEHOLDER: minimums target callout (Q39)
     static let strictStop = "Stop. Block done."  // PLACEHOLDER: strict stop callout, F22 (Q39)
     static let planEnded = "End of plan."  // PLACEHOLDER: no-block-left callout (Q39)
+    static let capturePaused = "Paused."
 
     // announceCount silences only the count; block, stop and saved callouts always speak (Q40).
     static func phrases(for event: SessionEvent, announceCount: Bool) -> [Phrase] {
@@ -32,6 +33,8 @@
             return [Phrase(text: planEnded, kind: .callout)]
         case .sessionSaved:
             return [Phrase(text: sessionSaved, kind: .callout)]
+        case .capturePaused:
+            return [Phrase(text: capturePaused, kind: .callout)]
         }
     }
 
```

### Change `Reps/Session/SessionDisplay.swift`

```diff
--- a/Reps/Session/SessionDisplay.swift
+++ b/Reps/Session/SessionDisplay.swift
@@ -147,6 +147,18 @@
         "\(title) · \(PlanSummary.reps(done, mode: mode)) so far."  // PLACEHOLDER: resume prompt copy
     }
 
+    // §6: why the camera area shows no picture; nil while it's live or not started. Counting by hand always works.
+    static func cameraNote(_ status: CameraStatus) -> String? {
+        // PLACEHOLDER: camera note copy
+        switch status {
+        case .off, .running: nil
+        case .interrupted: "Camera paused. Your count is kept."
+        case .unavailable: "Camera unavailable. Count with +1."
+        case .denied: "Camera is off. Count with +1, or allow it in Settings."
+        case .restricted: "Camera is restricted on this iPhone. Count with +1."
+        }
+    }
+
     private static func trimmed(_ text: String?) -> String? {
         guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
         return text
```

### Change `Reps/App/RootView.swift`

```diff
--- a/Reps/App/RootView.swift
+++ b/Reps/App/RootView.swift
@@ -5,6 +5,7 @@
     @Environment(\.modelContext) private var modelContext
     @Query(sort: [SortDescriptor(\BagClub.sortOrder), SortDescriptor(\BagClub.name)]) private var clubs: [BagClub]
     @State private var sessions: SessionController?
+    @State private var camera: CameraSession?
     @State private var pendingResume: PracticeSession?
     @State private var startFailed = false
     @AppStorage(AppSettings.Key.hasCompletedOnboarding) private var hasCompletedOnboarding =
@@ -32,7 +33,7 @@
         .tint(Theme.accent)
         // Driven by the controller: finish() or discard() clears the session and closes the cover.
         .fullScreenCover(isPresented: Binding(get: { isInSession }, set: { _ in })) {
-            if let sessions { SessionView(controller: sessions) }
+            if let sessions, let camera { SessionView(controller: sessions, camera: camera) }
         }
         .task { offerResume() }
         .alert(
@@ -62,6 +63,10 @@
         let announcer = SpeechAnnouncer(speaker: SystemSpeaker())
         announcer.prepare()
         made.addEventHandler { announcer.handle($0) }
+        // One capture session for the app's lifetime; SessionView starts and stops it (#13).
+        camera = CameraSession(
+            pipeline: CameraPipeline(), permissions: DevicePermissions(), onPaused: { announcer.handle(.capturePaused) }
+        )
         // TODO(#22): pass the real ClipFileRemoving once clips exist.
         sessions = made
         return made
```

### Change `Reps/UI/Session/SessionView.swift`

```diff
--- a/Reps/UI/Session/SessionView.swift
+++ b/Reps/UI/Session/SessionView.swift
@@ -1,10 +1,15 @@
 import SwiftData
 import SwiftUI
+import UIKit
 
-// Figma 03 (range), 05 (putting), 14 (next block early). Manual counting only; the camera arrives with #13.
+// Figma 03 (range), 05 (putting), 14 (next block early). Manual counting works whatever the camera does.
 struct SessionView: View {
     let controller: SessionController
+    let camera: CameraSession
 
+    @Environment(\.scenePhase) private var scenePhase
+    @Environment(\.openURL) private var openURL
+
     @Query(sort: \PracticeSession.startedAt, order: .reverse) private var sessions: [PracticeSession]
     @State private var nextPrompt: NextBlockPrompt?
     @State private var showSummary = false
@@ -27,6 +32,12 @@
             }
         }
         .sessionScreenGuard()
+        .task { await camera.start() }
+        .onDisappear { camera.stop() }
+        // §6: capture resumes when the app is back in front; also re-reads a permission changed in Settings.
+        .onChange(of: scenePhase) { _, phase in
+            if phase == .active { Task { await camera.start() } }
+        }
         .alert(
             nextPrompt?.title ?? "",
             isPresented: Binding(get: { nextPrompt != nil }, set: { if !$0 { nextPrompt = nil } }),
@@ -77,14 +88,7 @@
                     .padding(.top, controller.isFreeSession ? 10 : 6)
                     .padding(.bottom, 10)
             }
-            // PLACEHOLDER: camera preview (#13)
-            RoundedRectangle(cornerRadius: Theme.Radius.preview)
-                .fill(Theme.fill)
-                .overlay {
-                    Label("Camera", systemImage: "camera")
-                        .font(Theme.Typography.footnote)
-                        .foregroundStyle(Theme.secondaryText)
-                }
+            cameraArea
                 .frame(height: session.mode == .putting ? 150 : 190)
                 .padding(.horizontal, Theme.Spacing.gutter)
             count(session)
@@ -100,6 +104,33 @@
         .background(Theme.background)
     }
 
+    // The live preview while capture runs; otherwise why it stopped (§6).
+    private var cameraArea: some View {
+        RoundedRectangle(cornerRadius: Theme.Radius.preview)
+            .fill(Theme.fill)
+            .overlay {
+                if camera.status == .running {
+                    CameraPreview(session: camera.pipeline.captureSession, device: camera.pipeline.device)
+                }
+            }
+            .clipShape(.rect(cornerRadius: Theme.Radius.preview))
+            .overlay {
+                if let note = SessionDisplay.cameraNote(camera.status) {
+                    VStack(spacing: 8) {
+                        Text(note)
+                            .font(Theme.Typography.footnote)
+                            .foregroundStyle(Theme.secondaryText)
+                            .multilineTextAlignment(.center)
+                        if camera.status == .denied, let url = URL(string: UIApplication.openSettingsURLString) {
+                            Button("Open Settings") { openURL(url) }
+                                .font(Theme.Typography.footnote)
+                        }
+                    }
+                    .padding(Theme.Spacing.gutter)
+                }
+            }
+    }
+
     private func header(_ session: PracticeSession) -> some View {
         ZStack {
             VStack(spacing: 1) {
@@ -273,7 +304,9 @@
         let controller = SessionController(context: container.mainContext)
         let plan = try! container.mainContext.fetch(FetchDescriptor<PracticePlan>()).first { $0.name == "Wedge day" }!
         try! controller.start(plan: plan, cameraAngle: .faceOn)
-        return SessionView(controller: controller)
-            .modelContainer(container)
+        return SessionView(
+            controller: controller, camera: CameraSession(pipeline: CameraPipeline(), permissions: DevicePermissions())
+        )
+        .modelContainer(container)
     }
 #endif
```

### Tests: new `RepsTests/FrameSamplerTests.swift`

```swift
import ShotDetector
import Testing

struct FrameSamplerTests {
    // Frame times at a steady rate on a host-clock-like origin.
    private func times(fps: Double, count: Int, start: Double = 1000) -> [Double] {
        (0..<count).map { start + Double($0) / fps }
    }

    private func taken(_ times: [Double]) -> [Int] {
        var sampler = FrameSampler()
        return times.indices.filter { sampler.take(times[$0]) }
    }

    @Test func sixtyFpsTakesEveryFourthFrame() {
        #expect(taken(times(fps: 60, count: 60)) == Array(stride(from: 0, to: 60, by: 4)))
    }

    @Test(arguments: [30.0, 30000.0 / 1001])
    func thirtyFpsTakesEverySecondFrame(fps: Double) {
        #expect(taken(times(fps: fps, count: 30)) == Array(stride(from: 0, to: 30, by: 2)))
    }

    @Test func aDroppedDueFrameIsReplacedByTheNextOne() {
        var frames = times(fps: 60, count: 60)
        frames.removeSubrange(4...5)
        let numbers = taken(frames).map { Int(((frames[$0] - 1000) * 60).rounded()) }
        #expect(numbers == [0, 6, 8] + Array(stride(from: 12, to: 60, by: 4)))
    }

    @Test func longerIntervalTakesEffectAtOnce() {
        var sampler = FrameSampler()
        let frames = times(fps: 60, count: 120)
        var picked: [Int] = []
        for index in frames.indices {
            if index == 30 { sampler.interval = 0.1 }
            if sampler.take(frames[index]) { picked.append(index) }
        }
        #expect(picked == Array(stride(from: 0, through: 32, by: 4)) + Array(stride(from: 38, to: 120, by: 6)))
    }

    @Test func aPauseRestartsWithoutABurst() {
        let frames = times(fps: 60, count: 30) + times(fps: 60, count: 30, start: 1010)
        let picked = taken(frames).map { frames[$0] }
        #expect(picked.contains(1010))
        for (earlier, later) in zip(picked, picked.dropFirst()) {
            #expect(later - earlier >= 1.0 / 30 - 0.001)
        }
    }
}
```

### Tests: new `RepsTests/CaptureFormatTests.swift`

```swift
import Testing

@testable import Reps

struct CaptureFormatTests {
    private func hd(_ fps: Double, fullRange: Bool = true) -> FormatCandidate {
        FormatCandidate(width: 1920, height: 1080, maxFrameRate: fps, isFullRange: fullRange)
    }

    private let uhd60 = FormatCandidate(width: 3840, height: 2160, maxFrameRate: 60, isFullRange: true)

    @Test func picks1080p60OverOtherSizesAndRates() {
        #expect(CaptureFormat.best([uhd60, hd(30), hd(60)]) == 2)
    }

    @Test func skipsSlowMotionFormats() {
        #expect(CaptureFormat.best([hd(240), hd(120), hd(60)]) == 2)
    }

    @Test func fallsBackToTheFastest1080p() {
        #expect(CaptureFormat.best([hd(24), hd(30), uhd60]) == 1)
    }

    @Test func prefersFullRangeAtTheSameRate() {
        #expect(CaptureFormat.best([hd(60, fullRange: false), hd(60)]) == 1)
    }

    @Test func frameRateBeatsFullRange() {
        #expect(CaptureFormat.best([hd(30), hd(60, fullRange: false)]) == 1)
    }

    @Test func tiesKeepTheDeviceOrder() {
        #expect(CaptureFormat.best([hd(60), hd(60)]) == 0)
    }

    @Test func nilWithoutA1080pFormat() {
        #expect(CaptureFormat.best([uhd60]) == nil)
        #expect(CaptureFormat.best([]) == nil)
    }
}
```

### Tests: new `RepsTests/FrameScalerTests.swift`

```swift
import CoreVideo
import Testing

@testable import Reps

struct FrameScalerTests {
    enum Corner: Sendable {
        case topLeft, topRight, bottomRight, bottomLeft
    }

    // 420f with a white block in the top-left quarter; everything else black.
    private func source(width: Int = 1920, height: Int = 1080) throws -> CVPixelBuffer {
        var made: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, attributes, &made)
        let buffer = try #require(made)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let luma = try #require(CVPixelBufferGetBaseAddressOfPlane(buffer, 0)).assumingMemoryBound(to: UInt8.self)
        let lumaRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        for row in 0..<height {
            for column in 0..<width {
                luma[row * lumaRow + column] = row < height / 4 && column < width / 4 ? 255 : 0
            }
        }
        let chroma = try #require(CVPixelBufferGetBaseAddressOfPlane(buffer, 1)).assumingMemoryBound(to: UInt8.self)
        let chromaRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
        for index in 0..<(chromaRow * height / 2) { chroma[index] = 128 }
        return buffer
    }

    private func luma(_ buffer: CVPixelBuffer, x: Int, y: Int) -> UInt8 {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!.assumingMemoryBound(to: UInt8.self)
        return base[y * CVPixelBufferGetBytesPerRowOfPlane(buffer, 0) + x]
    }

    @Test(arguments: [(0.0, 0), (90, 1), (180, 2), (270, 3), (360, 0), (-90, 3), (89.6, 1)])
    func quarterTurnsSnapAndWrap(degrees: Double, turns: Int) {
        #expect(FrameScaler.quarterTurns(degrees) == turns)
    }

    @Test(arguments: [(0, 854, 480), (1, 480, 854), (2, 854, 480), (3, 480, 854)])
    func outputIsDetectorSized(turns: Int, width: Int, height: Int) throws {
        let scaler = try #require(FrameScaler())
        let output = try #require(scaler.detectorBuffer(from: try source(), quarterTurns: turns))
        #expect(CVPixelBufferGetWidth(output) == width)
        #expect(CVPixelBufferGetHeight(output) == height)
        #expect(CVPixelBufferGetPixelFormatType(output) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
    }

    // The block starts top-left; each clockwise quarter turn moves it one corner on.
    @Test(arguments: [(0, Corner.topLeft), (1, .topRight), (2, .bottomRight), (3, .bottomLeft)])
    func turnsAreClockwise(turns: Int, corner: Corner) throws {
        let scaler = try #require(FrameScaler())
        let output = try #require(scaler.detectorBuffer(from: try source(), quarterTurns: turns))
        let (width, height, margin) = (CVPixelBufferGetWidth(output), CVPixelBufferGetHeight(output), 10)
        let corners: [Corner: (Int, Int)] = [
            .topLeft: (margin, margin), .topRight: (width - margin, margin),
            .bottomRight: (width - margin, height - margin), .bottomLeft: (margin, height - margin),
        ]
        for (name, point) in corners {
            let bright = luma(output, x: point.0, y: point.1) > 200
            #expect(bright == (name == corner), "corner \(name)")
        }
    }

    @Test func smallFramesAreCopiedNotScaled() throws {
        let scaler = try #require(FrameScaler())
        let small = try source(width: 640, height: 480)
        let output = try #require(scaler.detectorBuffer(from: small, quarterTurns: 0))
        #expect(output !== small)
        #expect(CVPixelBufferGetWidth(output) == 640)
        #expect(CVPixelBufferGetHeight(output) == 480)
    }
}
```

### Tests: new `RepsTests/CameraSessionTests.swift` (reuses `FakePermissions` from `OnboardingModelTests.swift`)

```swift
import AVFoundation
import Testing

@testable import Reps

final class FakeCamera: CameraRunning, @unchecked Sendable {
    let captureSession = AVCaptureSession()
    let device: AVCaptureDevice? = nil
    private(set) var starts = 0
    private(set) var stops = 0

    func start(onStatus: @escaping @Sendable (CameraStatus) -> Void) { starts += 1 }
    func stop() { stops += 1 }
}

@MainActor
final class CameraSessionTests {
    private let camera = FakeCamera()
    private var paused = 0

    private func session(_ permissions: FakePermissions) -> CameraSession {
        CameraSession(pipeline: camera, permissions: permissions, onPaused: { [unowned self] in paused += 1 })
    }

    @Test func grantedStartsTheCameraWithoutAsking() async {
        let permissions = FakePermissions(camera: .granted)
        await session(permissions).start()
        #expect(camera.starts == 1)
        #expect(permissions.requests.isEmpty)
    }

    @Test func undeterminedAsksThenStarts() async {
        let permissions = FakePermissions(camera: .notDetermined)
        permissions.answers[.camera] = .granted
        await session(permissions).start()
        #expect(permissions.requests == [.camera])
        #expect(camera.starts == 1)
    }

    @Test func deniedAnswerShowsDenied() async {
        let permissions = FakePermissions(camera: .notDetermined)
        permissions.answers[.camera] = .denied
        let cameraSession = session(permissions)
        await cameraSession.start()
        #expect(cameraSession.status == .denied)
        #expect(camera.starts == 0)
    }

    @Test(arguments: [(PermissionState.denied, CameraStatus.denied), (.restricted, .restricted)])
    func decidedNeverAsks(state: PermissionState, status: CameraStatus) async {
        let permissions = FakePermissions(camera: state)
        let cameraSession = session(permissions)
        await cameraSession.start()
        #expect(cameraSession.status == status)
        #expect(permissions.requests.isEmpty)
        #expect(camera.starts == 0)
    }

    @Test func grantingInSettingsStartsOnReturn() async {
        let permissions = FakePermissions(camera: .denied)
        let cameraSession = session(permissions)
        await cameraSession.start()
        permissions.states[.camera] = .granted
        await cameraSession.start()
        #expect(camera.starts == 1)
    }

    @Test func runningIsNotRestartedButUnavailableIs() async {
        let cameraSession = session(FakePermissions(camera: .granted))
        await cameraSession.start()
        cameraSession.receive(.running)
        await cameraSession.start()
        #expect(camera.starts == 1)
        cameraSession.receive(.unavailable)
        await cameraSession.start()
        #expect(camera.starts == 2)
    }

    @Test func interruptionSaysPausedOncePerInterruption() async {
        let cameraSession = session(FakePermissions(camera: .granted))
        await cameraSession.start()
        cameraSession.receive(.running)
        cameraSession.receive(.interrupted)
        cameraSession.receive(.interrupted)
        #expect(paused == 1)
        #expect(cameraSession.status == .interrupted)
        cameraSession.receive(.running)
        cameraSession.receive(.interrupted)
        #expect(paused == 2)
    }

    @Test func stopIgnoresLateStatuses() async {
        let cameraSession = session(FakePermissions(camera: .granted))
        await cameraSession.start()
        cameraSession.stop()
        cameraSession.receive(.running)
        cameraSession.receive(.interrupted)
        #expect(camera.stops == 1)
        #expect(cameraSession.status == .off)
        #expect(paused == 0)
    }
}
```

### Tests: change `RepsTests/SessionDisplayTests.swift` and `RepsTests/VoiceLinesTests.swift`

```diff
--- a/RepsTests/SessionDisplayTests.swift
+++ b/RepsTests/SessionDisplayTests.swift
@@ -111,4 +111,13 @@
             SessionDisplay.resumeMessage(title: "Free session", done: 1, mode: .putting)
                 == "Free session · 1 putt so far.")
     }
+
+    @Test func cameraNoteOnlyWhenThereIsNoPicture() {
+        #expect(SessionDisplay.cameraNote(.off) == nil)
+        #expect(SessionDisplay.cameraNote(.running) == nil)
+        let stopped: [CameraStatus] = [.interrupted, .unavailable, .denied, .restricted]
+        for status in stopped {
+            #expect(SessionDisplay.cameraNote(status) != nil)
+        }
+    }
 }
--- a/RepsTests/VoiceLinesTests.swift
+++ b/RepsTests/VoiceLinesTests.swift
@@ -52,12 +52,13 @@
     @Test func planEndedAndSessionSaved() {
         #expect(texts(.planEnded) == ["End of plan."])
         #expect(texts(.sessionSaved) == ["Done. Session saved."])
+        #expect(texts(.capturePaused) == ["Paused."])
     }
 
     @Test func calloutsSpeakWithAnnounceCountOff() {
         let events: [SessionEvent] = [
             .targetReached(clubName: "9 iron", target: 30, isStrict: true),
-            .blockChanged(clubName: "9 iron", target: 30, done: 0), .planEnded, .sessionSaved,
+            .blockChanged(clubName: "9 iron", target: 30, done: 0), .planEnded, .sessionSaved, .capturePaused,
         ]
         for event in events {
             let phrases = VoiceLines.phrases(for: event, announceCount: false)
```

## Steps (one commit each; update `docs/code-reference.md` in the same commit as its files)

0. **`plan and adr for camera pipeline`** (docs only, before step 1): commit what the planner already wrote, as is. That is `docs/plans/13-camera-pipeline.md`, `docs/adr/0016-camera-pipeline-fan-out.md`, the `docs/adr/README.md` rows 0014–0016, and the `docs/open-questions.md` changes (Q41 note, Q43, Q44).
1. **`shared frame sampler for camera and eval`**: `ShotDetector/FrameSampler.swift`, the `VideoFrame.swift` change, the `VideoFrameReader.swift` and `VideoFrameReaderTests.swift` changes, `RepsTests/FrameSamplerTests.swift`. Run the ShotDetector import check, the Unit suite `FrameSamplerTests`, and the DetectorEval harness command (below).
2. **`capture format picker and frame scaler`**: `Reps/Camera/CaptureFormat.swift`, `Reps/Camera/FrameScaler.swift`, `CaptureFormatTests`, `FrameScalerTests`.
3. **`camera pipeline and camera session`**: `CameraSession.swift`, `CameraPipeline.swift`, the `SessionEvent`/`VoiceLines` changes, `CameraSessionTests`, and the `VoiceLinesTests` change.
4. **`camera preview on the session screen`**: `CameraPreview.swift`, the `SessionDisplay`, `SessionView` and `RootView` changes, the `SessionDisplayTests` change, plus the docs below (design.md, placeholders.md, code-reference). At PR time set `docs/roadmap.md` #13 to ☑.


Each step must build on its own. Step 3's `CameraPipeline` uses `FrameScaler` and `CaptureFormat` from step 2. `SessionDisplay.cameraNote` (step 4) uses `CameraStatus` from step 3.

## Tests

Unit (Swift Testing, `Unit` plan):

| Suite | Cases |
|---|---|
| `FrameSamplerTests` | 60 fps → frames 0,4,…,56; 30 and 29.97 fps → every 2nd; a dropped due frame (4–5 missing) → 0, 6, 8, 12, …, 56; interval 0.1 set at frame 30 → 0…32 by 4, then 38…116 by 6; a 10 s pause → takes 1010 at once, never two picks < 1/30 s apart |
| `CaptureFormatTests` | 1080p60 beats 4K60 and 1080p30; skips 240/120; falls back to fastest 1080p (30); 420f wins at equal rate; rate beats 420f; ties keep device order; nil with no 1080p / empty |
| `FrameScalerTests` | `quarterTurns` snaps/wraps (0, 90, 180, 270, 360, −90, 89.6); output sizes 854×480 / 480×854 and 420f for 0–3 turns; **turns are clockwise** (a white top-left block lands top-left, top-right, bottom-right, bottom-left for 0–3); a 640×480 source is copied (new buffer, same size) |
| `CameraSessionTests` | granted starts without asking; undetermined asks then starts; denied answer → `.denied`, no start; denied/restricted never ask; granting in Settings starts on the next `start()`; `.running` isn't restarted but `.unavailable` is; "Paused." once per interruption (twice for two separate interruptions); after `stop()` late statuses are ignored |
| `SessionDisplayTests` | `cameraNoteOnlyWhenThereIsNoPicture` |
| `VoiceLinesTests` | `.capturePaused` → "Paused.", also with announceCount off |

Not unit-tested (glue; no camera in the simulator): `CameraPipeline` and `CameraPreview`. They are covered by the build and the device checklist.

Commands (repo root):

```sh
DEST='platform=iOS Simulator,name=iPhone 17 Pro,OS=latest'
xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan Unit -destination "$DEST" \
  -only-testing:RepsTests/FrameSamplerTests -only-testing:RepsTests/CaptureFormatTests \
  -only-testing:RepsTests/FrameScalerTests -only-testing:RepsTests/CameraSessionTests \
  -only-testing:RepsTests/SessionDisplayTests -only-testing:RepsTests/VoiceLinesTests \
  -only-testing:RepsTests/SpeechAnnouncerTests
# eval harness still compiles and samples the same (footage test skips without ml/data)
xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan DetectorEval -destination "$DEST" \
  -only-testing:DetectorEvalTests/VideoFrameReaderTests -only-testing:DetectorEvalTests/EvalRunnerTests \
  -only-testing:DetectorEvalTests/CSVTests -only-testing:DetectorEvalTests/EventMatcherTests \
  -only-testing:DetectorEvalTests/EvalMetricsTests
# if ml/data exists locally, also: -only-testing:DetectorEvalTests/OracleEvalTests (numbers must match main)
xcodebuild build -project Reps.xcodeproj -scheme Reps -destination "$DEST" -quiet
xcrun swift-format lint --strict --recursive --parallel Reps ShotDetector RepsTests DetectorEvalTests
grep -rnE 'import (AVFoundation|AVKit|UIKit|SwiftUI|CoreMedia)' ShotDetector   # must print nothing
```

In the simulator, the session screen shows "Camera unavailable. Count with +1." (no camera device). That is the expected result there.

## Device checklist (owner, on an iPhone; the simulator can't check these)

1. Start a session with the camera not yet asked: the prompt appears on the session screen, and the preview shows after Allow. Deny it instead: the denied note and Open Settings appear. Allow it in Settings and come back: the preview appears.
2. Portrait on a tripod, then landscape: the preview stays level. (`videoRotationAngleForHorizonLevelCapture` being clockwise for the back camera can only be confirmed when #14 shows a detector frame. Note the result in #14.)
3. Swipe home mid-session, then come back: the count is unchanged and the preview returns. Is "Paused." heard, cut off, or played late on return? Record the answer in Q43.
4. Siri, and an incoming call (banner and full screen): what happens and what is heard. Record it in Q43.
5. Music playing: it ducks under "Paused." like the other callouts, and capture doesn't change the audio route (Q41).
6. Phone flat on the ground, face-on putting setup: the preview angle is stable (Q44).
7. End a session (Done) and start a second one: the preview comes back. The pipeline is reused for the app's lifetime, so a stuck stop/start would break every later session.
8. Ten minutes of capture: the phone doesn't get noticeably warm with the detector sink unset (baseline for #28).

## Docs (in step 4 unless noted)

- `docs/code-reference.md` (in the step that adds each file). Add these entries, keeping the existing order style, and update the existing ones:
  - `## ShotDetector/FrameSampler.swift`: Timestamp sampling shared by the camera pipeline and the eval decoder (ADR 0016). `- FrameSampler(frameRate:)`: `interval` (s, settable; #28 thermal seam); `take(_ time:) -> Bool` takes the first frame and then one per interval, with 1 ms slack. It resyncs after drops or pauses.
  - `ShotDetector/VideoFrame.swift`: add `- DetectorInput.scaledSize(width:height:shortSide:)`: even size with the short side at `shortSide`; nil if already that small.
  - `DetectorEvalTests/Harness/VideoFrameReader.swift`: replace the `scaledSize` line with "samples with `FrameSampler`, sizes with `DetectorInput.scaledSize`".
  - `## Reps/Camera/CaptureFormat.swift`: §5.6 format choice, pure. `- FormatCandidate`: width, height, maxFrameRate, isFullRange. `- CaptureFormat.best(_:) -> Int?`: 1080p only; the slowest format reaching 60 fps, else the fastest; then 420f, then device order.
  - `## Reps/Camera/FrameScaler.swift`: Detector copy of a camera frame (ADR 0016); confined to the pipeline queue. `- FrameScaler()`: failable (VideoToolbox sessions). `- quarterTurns(_ degrees:) -> Int`: 0…3 clockwise, snapped. `- detectorBuffer(from:quarterTurns:) -> CVPixelBuffer?`: scale to `DetectorInput.scaledSize`, then rotate clockwise; always a pooled copy.
  - `## Reps/Camera/CameraSession.swift`: `- CameraStatus`: off, running, interrupted, unavailable, denied, restricted. `- CameraRunning`: `captureSession`, `device`, `start(onStatus:)`, `stop()`. `- CameraSession(pipeline:permissions:onPaused:)`: `status`; `start() async` (permission gate per ADR 0014; starts the pipeline unless running; safe to repeat); `stop()`; `receive(_:)` (ignored after stop; calls `onPaused` once per interruption).
  - `## Reps/Camera/CameraPipeline.swift`: §5.6/§6 capture (ADR 0016); build-only, checked on a device. Queues: `sessionQueue` (session state), `frameQueue` (frames), `detectorQueue`. `- CameraPipeline`: `captureSession`, `device` (back wide); `start(onStatus:)` configures once (input, 420f data output, angle 0, `CaptureFormat.best` at 60 fps, audio session untouched, notifications, rotation coordinator), then runs; `stop()`; `setSinks(sample:detector:)` (sample: every frame + `rotationDegrees`, on `frameQueue`; detector: upright 480p `VideoFrame` every 1/15 s on `detectorQueue`, skipped while busy); interruption → `.interrupted`, ended → `.running`, runtime error → one restart on media-services reset, else `.unavailable`. `- FormatCandidate.init(_ format: AVCaptureDevice.Format)`.
  - `## Reps/UI/Session/CameraPreview.swift`: `- CameraPreview(session:device:)`: preview layer (aspect fill), angle from its own `RotationCoordinator` (KVO on main).
  - Update `SessionEvent` (`capturePaused`, sent by `CameraSession`), `VoiceLines` (`capturePaused` → "Paused."), `SessionDisplay` (`cameraNote(_:)`), `SessionView` (`camera:`; starts on `.task` and `.active`, stops on disappear; `cameraArea` preview/note/Open Settings), `RootView` (creates the `CameraSession` with the announcer's `capturePaused`).
  - Tests: `RepsTests/FrameSamplerTests.swift`, `CaptureFormatTests.swift`, `FrameScalerTests.swift`, `CameraSessionTests.swift` (`FakeCamera`), one line each.
- `docs/placeholders.md`: regenerate the table with `grep -rn 'PLACEHOLDER:' Reps`. The new row is `Reps/Session/SessionDisplay.swift` "camera note copy". The old `SessionView` "camera preview (#13)" placeholder is gone, and line numbers shift.
- `docs/design.md`: change "Camera area is a placeholder until #13." to "Camera area shows the live preview while capture runs (#13), else a note (paused / unavailable / denied with Open Settings)."
- Already written by the planner (commit them in step 0): ADR 0016, ADR README rows 0014–0016, Q41 note, Q43, Q44.

## Seams for later issues

- **#14 / #16 / #19 detectors**: get the pipeline via `camera.pipeline as? CameraPipeline` (or hold it in `RootView` next to the `CameraSession`), then call `setSinks(sample: nil, detector: { frame in … })`. The detector value (a `mutating` `ShotDetecting` struct) must live only on the detector queue, e.g. inside a small `final class` captured by the closure. Each emitted `ShotEvent` hops to the main actor and calls `controller.recordShot(source: .camera)`. Detectors must cope with a frame-size change on rotation (Q44).
- **#22 clip writer**: `setSinks(sample: { buffer, degrees in … }, detector: …)`. Always pass both sinks together; `setSinks` replaces both. The writer runs on `frameQueue` and must stay cheap. Apply `degrees` as `AVAssetWriterInput.transform` (radians), and start a new segment when it changes. Adding a mic input is #22's job, together with Q41.
- **#28 thermal**: add a `setDetectorFrameRate(_:)` that sets `sampler.interval` on `frameQueue`; hide `CameraPreview` at `.serious`.

## Risks and unknowns

- Device-only behaviour: interruption reasons for calls/Siri, whether "Paused." is heard (Q43), and the flat-phone angle (Q44). All are in the device checklist.
- Stop then start on the reused pipeline is only checked on a device (checklist 7). `stopRunning()` runs on `sessionQueue` while frames may still arrive on `frameQueue`; the queues are separate, so they can't deadlock.
- Locking the frame duration at 1/60 s stops auto low-light frame-rate drops, so indoor putting may look darker or noisier. Revisit with #16 footage if detection suffers.
- A 1080p60 format can be binned on some iPhones (lower quality); not handled. The picker only looks at size, rate and range.
- The `nonisolated(unsafe) let frame` hand-off and `@unchecked Sendable` on `CameraPipeline` are deliberate. Session state lives only on `sessionQueue` and frame state only on `frameQueue`. `detectorBusy` is a `Mutex`. `scaler` is an immutable reference, used only on `frameQueue`.
- `CameraPipeline` is never deallocated in practice (app lifetime). `deinit` removes the notification observers anyway.
