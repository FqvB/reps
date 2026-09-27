import Foundation

nonisolated enum OnboardingPage: Int, CaseIterable, Sendable {
    case welcome
    case bag
    case camera
}

// What a tap on a permission row does.
nonisolated enum PermissionRowAction: Equatable, Sendable {
    case request
    case openSettings
    case none
}

// Onboarding state (F20). Prompts go through CapturePermissions, so tests never reach TCC.
@Observable
final class OnboardingModel {
    private(set) var page: OnboardingPage = .welcome
    private(set) var camera: PermissionState = .notDetermined
    private(set) var microphone: PermissionState = .notDetermined
    private(set) var isRequesting = false
    private(set) var isFinished = false

    private let permissions: any CapturePermissions
    private let settings: AppSettings

    init(permissions: any CapturePermissions, settings: AppSettings = AppSettings()) {
        self.permissions = permissions
        self.settings = settings
        refresh()
    }

    var isLastPage: Bool { page == .camera }

    // The mic is asked only when clips will carry audio and the camera is usable.
    // TODO(#22): re-check in context before the first recording with audio on; ask then if still undetermined.
    var asksMicrophoneOnFinish: Bool {
        microphone == .notDetermined && camera == .granted && settings.recordClipAudio
    }

    // Whether "Allow and finish" will show at least one system prompt.
    var willPrompt: Bool {
        camera == .notDetermined || asksMicrophoneOnFinish
    }

    func state(of medium: CaptureMedium) -> PermissionState {
        switch medium {
        case .camera: camera
        case .microphone: microphone
        }
    }

    func advance() {
        guard let next = OnboardingPage(rawValue: page.rawValue + 1) else { return }
        page = next
    }

    // Re-read after the Settings app may have changed things.
    func refresh() {
        camera = permissions.state(of: .camera)
        microphone = permissions.state(of: .microphone)
    }

    func rowAction(for medium: CaptureMedium) -> PermissionRowAction {
        switch state(of: medium) {
        case .notDetermined: .request
        case .denied: .openSettings
        case .granted, .restricted: .none
        }
    }

    func request(_ medium: CaptureMedium) async {
        guard state(of: medium) == .notDetermined, !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }
        let result = await permissions.request(medium)
        switch medium {
        case .camera: camera = result
        case .microphone: microphone = result
        }
    }

    // Camera first, then the mic. A denial never blocks: manual counting works without either (spec §6).
    func allowAndFinish() async {
        guard !isRequesting else { return }
        await request(.camera)
        if asksMicrophoneOnFinish { await request(.microphone) }
        finish()
    }

    func finish() {
        settings.hasCompletedOnboarding = true
        isFinished = true
    }
}
