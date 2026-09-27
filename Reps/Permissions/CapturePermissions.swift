import Foundation

nonisolated enum CaptureMedium: CaseIterable, Sendable {
    case camera
    case microphone
}

// App-side view of AVAuthorizationStatus.
nonisolated enum PermissionState: Equatable, Sendable {
    case notDetermined
    case granted
    case denied
    case restricted
}

// The only way the app asks for the camera or mic. DevicePermissions is the real one; tests use a fake.
protocol CapturePermissions {
    func state(of medium: CaptureMedium) -> PermissionState
    // Prompts only while notDetermined; otherwise returns the current state.
    func request(_ medium: CaptureMedium) async -> PermissionState
}
