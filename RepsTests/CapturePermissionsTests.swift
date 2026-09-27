import AVFoundation
import Testing

@testable import Reps

@MainActor
struct CapturePermissionsTests {
    @Test(arguments: [
        (AVAuthorizationStatus.notDetermined, PermissionState.notDetermined),
        (.authorized, .granted),
        (.denied, .denied),
        (.restricted, .restricted),
    ])
    func mapsAuthorizationStatus(status: AVAuthorizationStatus, expected: PermissionState) {
        #expect(PermissionState(status) == expected)
    }

    @Test func unknownStatusFailsClosed() {
        #expect(PermissionState(AVAuthorizationStatus(rawValue: 99)!) == .denied)
    }

    @Test func mediaTypes() {
        #expect(CaptureMedium.camera.mediaType == .video)
        #expect(CaptureMedium.microphone.mediaType == .audio)
    }
}
