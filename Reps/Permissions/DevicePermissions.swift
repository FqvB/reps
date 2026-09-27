import AVFoundation

extension PermissionState {
    // Unknown future cases read as denied, so the UI offers Settings instead of assuming access.
    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .authorized: self = .granted
        case .denied: self = .denied
        case .restricted: self = .restricted
        @unknown default: self = .denied
        }
    }
}

extension CaptureMedium {
    var mediaType: AVMediaType {
        switch self {
        case .camera: .video
        case .microphone: .audio
        }
    }
}

// AVCaptureDevice-backed. The INFOPLIST_KEY_NS*UsageDescription strings must exist or the request crashes.
struct DevicePermissions: CapturePermissions {
    func state(of medium: CaptureMedium) -> PermissionState {
        PermissionState(AVCaptureDevice.authorizationStatus(for: medium.mediaType))
    }

    func request(_ medium: CaptureMedium) async -> PermissionState {
        guard state(of: medium) == .notDetermined else { return state(of: medium) }
        _ = await AVCaptureDevice.requestAccess(for: medium.mediaType)
        // Re-read rather than trust the Bool: restricted also answers false.
        return state(of: medium)
    }
}
