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
