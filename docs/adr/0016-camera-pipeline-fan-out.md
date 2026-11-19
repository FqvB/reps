# 0016 — Camera pipeline: one data output, sensor-native frames, upright detector copies

- Status: Accepted (supersedes one line of ADR 0010's consequences, see below)
- Date: 2026-11-19

## Context
Spec §5.6 wants 1080p60 capture, every frame to the clip writer (#22, ADR 0003), and every 4th frame downscaled to the detectors. ADR 0010 fixed the detector contract (15 fps, short side 480, 420f, upright `.up` frames) and said #13 would set the capture connection's `videoRotationAngle` so frames arrive upright.

AVFoundation's docs (Context7, `AVCaptureConnection.videoRotationAngle`): for `AVCaptureVideoDataOutput` the connection "deliver[s] physically rotated buffers, which costs work on every frame", and changing it "reconfigures the capture render pipeline, so set it before calling startRunning()". For `AVAssetWriter` they say "don't rotate the video with AVCaptureConnection. Instead, set the rotation with an AVAssetWriterInput instance's transform property ... which uses less energy". The SDK header adds that video data output clients "should set videoRotationAngle to 0 to avoid the physical buffer rotation".

## Decision
- One `AVCaptureSession`, back wide camera, one `AVCaptureVideoDataOutput` (420f, `alwaysDiscardsLateVideoFrames`). Its connection stays at `videoRotationAngle = 0`, so buffers are sensor-native. **This replaces ADR 0010's line "#13 sets the capture connection's `videoRotationAngle`".** The detector-facing contract is unchanged: detectors still get upright `.up` frames.
- Format: the 1080p device format whose max rate is the lowest that reaches 60 fps (skips slow-mo formats), 420f preferred; otherwise the fastest 1080p format. The frame duration is locked at 1/60 s (or that format's fastest).
- Queues: `sessionQueue` for configuration and the blocking `startRunning`/`stopRunning`, `frameQueue` for the sample delegate (Apple's AVCam layout), and `detectorQueue` for detectors.
- Fan-out on `frameQueue`: every frame goes to a sample sink with the clockwise rotation (0/90/180/270) from `AVCaptureDevice.RotationCoordinator.videoRotationAngleForHorizonLevelCapture`. #22 applies it as `AVAssetWriterInput.transform`.
- Detector path: a timestamp-based `FrameSampler` (in ShotDetector, now also used by the eval decoder so live and eval sample alike) picks 1 frame per 1/15 s. VideoToolbox scales it to short side 480 (`VTPixelTransferSession`) and turns it upright (`VTPixelRotationSession`). Rotating at 480p costs a fraction of rotating at 1080p. Detectors run on their own serial queue. While they are still busy, new frames are skipped rather than queued, so `frameQueue` (and #22's 60 fps) never waits on Vision.
- Rotation follows the phone live, so detector frame size can flip between 854×480 and 480×854 mid-session (Q44).
- Interruptions: no explicit stop on background. The system interrupts and resumes the session. A media-services reset gets one restart, and returning to the foreground restarts a session that isn't running. "Paused." is spoken once per interruption (§6, Q43).
- The capture session never configures the app audio session (`automaticallyConfiguresApplicationAudioSession = false`); `VoiceAudioSession` owns it (ADR 0015, Q41).
- Not used: `AVCaptureMovieFileOutput` (no fan-out), multi-cam, deferred start (iOS 26; only helps camera-first launch).

## Consequences
The detectors' eval-tested orientation path (`.up`) is the only one they see live. The clip writer must set a transform instead of expecting upright buffers. Rotation direction is unit-tested on VideoToolbox. That `videoRotationAngleForHorizonLevelCapture` is clockwise for the back camera is a device check. Thermal changes (#28) adjust `FrameSampler.interval`.
