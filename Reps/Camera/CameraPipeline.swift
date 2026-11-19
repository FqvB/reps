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
