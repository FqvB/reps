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
