import Foundation
import Testing

@testable import Reps

// Scripted permissions: `answers` is what a prompt would return; `requests` records every prompt.
@MainActor
final class FakePermissions: CapturePermissions {
    var states: [CaptureMedium: PermissionState]
    var answers: [CaptureMedium: PermissionState] = [:]
    private(set) var requests: [CaptureMedium] = []

    init(camera: PermissionState = .notDetermined, microphone: PermissionState = .notDetermined) {
        states = [.camera: camera, .microphone: microphone]
    }

    func state(of medium: CaptureMedium) -> PermissionState {
        states[medium] ?? .notDetermined
    }

    func request(_ medium: CaptureMedium) async -> PermissionState {
        requests.append(medium)
        if let answer = answers[medium] { states[medium] = answer }
        return state(of: medium)
    }
}

@MainActor
final class OnboardingModelTests {
    private let suite = "RepsTests.Onboarding.\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let settings: AppSettings

    init() {
        defaults = UserDefaults(suiteName: suite)!
        settings = AppSettings(defaults: defaults)
    }

    isolated deinit {
        defaults.removePersistentDomain(forName: suite)
    }

    private func model(_ permissions: FakePermissions) -> OnboardingModel {
        OnboardingModel(permissions: permissions, settings: settings)
    }

    @Test func pagesGoForwardAndStopAtCamera() {
        let model = model(FakePermissions())
        #expect(model.page == .welcome)
        #expect(!model.isLastPage)
        model.advance()
        #expect(model.page == .bag)
        model.advance()
        #expect(model.page == .camera)
        #expect(model.isLastPage)
        model.advance()
        #expect(model.page == .camera)
    }

    @Test func readsInitialStates() {
        let model = model(FakePermissions(camera: .denied, microphone: .granted))
        #expect(model.camera == .denied)
        #expect(model.microphone == .granted)
        #expect(model.state(of: .camera) == .denied)
        #expect(model.state(of: .microphone) == .granted)
        #expect(!model.isFinished)
        #expect(settings.hasCompletedOnboarding == false)
    }

    @Test func allowAndFinishAsksCameraThenMicrophone() async {
        let fake = FakePermissions()
        fake.answers = [.camera: .granted, .microphone: .granted]
        let model = model(fake)
        #expect(model.willPrompt)
        await model.allowAndFinish()
        #expect(fake.requests == [.camera, .microphone])
        #expect(model.camera == .granted)
        #expect(model.microphone == .granted)
        #expect(model.isFinished)
        #expect(settings.hasCompletedOnboarding)
        #expect(!model.isRequesting)
    }

    @Test func allowAndFinishSkipsMicWhenClipAudioOff() async {
        settings.recordClipAudio = false
        let fake = FakePermissions()
        fake.answers = [.camera: .granted]
        let model = model(fake)
        await model.allowAndFinish()
        #expect(fake.requests == [.camera])
        #expect(model.microphone == .notDetermined)
        #expect(model.isFinished)
    }

    @Test func deniedCameraSkipsMicAndStillFinishes() async {
        let fake = FakePermissions()
        fake.answers = [.camera: .denied]
        let model = model(fake)
        await model.allowAndFinish()
        #expect(fake.requests == [.camera])
        #expect(model.camera == .denied)
        #expect(model.microphone == .notDetermined)
        #expect(model.isFinished)
        #expect(settings.hasCompletedOnboarding)
    }

    @Test func decidedPermissionsAreNotAskedAgain() async {
        let fake = FakePermissions(camera: .granted, microphone: .denied)
        let model = model(fake)
        #expect(!model.willPrompt)
        await model.allowAndFinish()
        #expect(fake.requests.isEmpty)
        #expect(model.isFinished)
    }

    @Test func restrictedMicrophoneIsNeverAsked() async {
        let fake = FakePermissions(camera: .granted, microphone: .restricted)
        let model = model(fake)
        #expect(!model.asksMicrophoneOnFinish)
        await model.request(.microphone)
        await model.allowAndFinish()
        #expect(fake.requests.isEmpty)
    }

    @Test func rowActionsFollowTheState() {
        let undetermined = model(FakePermissions(camera: .notDetermined, microphone: .denied))
        #expect(undetermined.rowAction(for: .camera) == .request)
        #expect(undetermined.rowAction(for: .microphone) == .openSettings)
        let decided = model(FakePermissions(camera: .granted, microphone: .restricted))
        #expect(decided.rowAction(for: .camera) == .none)
        #expect(decided.rowAction(for: .microphone) == .none)
    }

    @Test func requestOnlyPromptsWhileUndetermined() async {
        let fake = FakePermissions(camera: .denied)
        fake.answers = [.microphone: .granted]
        let model = model(fake)
        await model.request(.camera)
        #expect(fake.requests.isEmpty)
        await model.request(.microphone)
        #expect(fake.requests == [.microphone])
        #expect(model.microphone == .granted)
        #expect(!model.isFinished)
    }

    @Test func refreshPicksUpChangesMadeInSettings() {
        let fake = FakePermissions(camera: .denied)
        let model = model(fake)
        fake.states[.camera] = .granted
        #expect(model.camera == .denied)
        model.refresh()
        #expect(model.camera == .granted)
    }

    @Test func willPromptOnlyWhileSomethingIsAskable() {
        #expect(model(FakePermissions(camera: .notDetermined, microphone: .granted)).willPrompt)
        // Mic still undetermined but the camera isn't granted yet: the mic alone doesn't count.
        #expect(!model(FakePermissions(camera: .denied, microphone: .notDetermined)).willPrompt)
        #expect(model(FakePermissions(camera: .granted, microphone: .notDetermined)).willPrompt)
        settings.recordClipAudio = false
        #expect(!model(FakePermissions(camera: .granted, microphone: .notDetermined)).willPrompt)
    }
}
