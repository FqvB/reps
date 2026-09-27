import Foundation

nonisolated struct OnboardingFeature: Identifiable, Sendable {
    let title: String
    let detail: String
    let symbol: String
    var id: String { title }
}

// Copy for onboarding (Figma 07–09); pure, unit-tested.
nonisolated enum OnboardingCopy {
    static let welcomeTitle = "Count every shot.\nKeep every swing."
    static let welcomeIntro =
        "Put your phone on a tripod. Reps counts your range balls and putts, calls the number out loud, and saves a clip of every swing."
    // PLACEHOLDER: feature icons (the Figma circles are empty)
    static let features = [
        OnboardingFeature(
            title: "Practice plans", detail: "40 pitching wedges, then 30 nine irons — in order or any order.",
            symbol: "list.bullet.rectangle"),
        OnboardingFeature(
            title: "Counts by camera", detail: "Sees the ball leave, not your practice swings.", symbol: "camera"),
        OnboardingFeature(
            title: "Clips and tempo", detail: "Every swing trimmed and tagged, with your tempo ratio.", symbol: "film"),
    ]
    static let getStarted = "Get started"
    static let bagTitle = "Your bag"
    static let bagIntro =
        "Tap to add or remove clubs. This is the list you pick from when building a plan. Change it any time in Settings."
    static let cameraTitle = "Set up the camera"
    static let cameraIntro =
        "Reps needs the camera to count and record. The microphone only adds sound to your clips. Nothing leaves your phone."
    static let illustrationCaption = "Whole body and ball in frame · tripod at hip height"
    static let angleLabel = "Default angle"
    static let cameraRow = (title: "Camera", subtitle: "Counting and clips")
    static let microphoneRow = (title: "Microphone", subtitle: "Only for sound on your clips, optional")

    static func continueTitle(clubCount: Int) -> String {
        switch clubCount {
        case 0: "Continue without clubs"  // PLACEHOLDER: empty-bag continue copy
        case 1: "Continue with 1 club"
        default: "Continue with \(clubCount) clubs"
        }
    }

    // "Finish" once nothing is left to ask. PLACEHOLDER: not in Figma
    static func finishTitle(willPrompt: Bool) -> String {
        willPrompt ? "Allow and finish" : "Finish"
    }

    // Status pill. PLACEHOLDER: only "Not yet" is in Figma
    static func status(_ state: PermissionState) -> String {
        switch state {
        case .notDetermined: "Not yet"
        case .granted: "Allowed"
        case .denied: "Denied"
        case .restricted: "Restricted"
        }
    }

    // Under the rows when the camera can't be used; nil otherwise. PLACEHOLDER: denied/restricted copy
    static func cameraNote(_ state: PermissionState) -> String? {
        switch state {
        case .denied: "Reps can't count by camera until you allow it in Settings. The +1 button always works."
        case .restricted: "Camera access is restricted on this phone. You can still count with the +1 button."
        case .notDetermined, .granted: nil
        }
    }
}
