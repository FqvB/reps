import Foundation

// Stored in UserDefaults by raw value; never rename.
nonisolated enum ClipQuality: String, CaseIterable, Sendable {
    case p1080fps60 = "1080p60"
    case p1080fps30 = "1080p30"
    case p720fps30 = "720p30"  // PLACEHOLDER: clip quality options (Q32)
}

// Typed Settings preferences (F25). SettingsView binds the same keys with @AppStorage.
nonisolated struct AppSettings {
    nonisolated enum Key {
        static let defaultCameraAngle = "settings.defaultCameraAngle"
        static let clipQuality = "settings.clipQuality"
        static let saveClipsToPhotos = "settings.saveClipsToPhotos"
        static let recordClipAudio = "settings.recordClipAudio"
        static let announceCount = "settings.announceCount"
        static let announceTempo = "settings.announceTempo"
        static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
    }

    nonisolated enum Default {
        static let cameraAngle: CameraAngle = .faceOn
        static let clipQuality: ClipQuality = .p1080fps60
        static let saveClipsToPhotos = false
        static let recordClipAudio = true
        static let announceCount = true
        static let announceTempo = false
        static let hasCompletedOnboarding = false
    }

    // .none means putting, so it isn't a choice.
    static let angleChoices: [CameraAngle] = [.faceOn, .downTheLine]

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var defaultCameraAngle: CameraAngle {
        get {
            let stored = defaults.string(forKey: Key.defaultCameraAngle).flatMap(CameraAngle.init(rawValue:))
            guard let stored, Self.angleChoices.contains(stored) else { return Default.cameraAngle }
            return stored
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.defaultCameraAngle) }
    }

    var clipQuality: ClipQuality {
        get { defaults.string(forKey: Key.clipQuality).flatMap(ClipQuality.init(rawValue:)) ?? Default.clipQuality }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.clipQuality) }
    }

    var saveClipsToPhotos: Bool {
        get { bool(Key.saveClipsToPhotos, Default.saveClipsToPhotos) }
        nonmutating set { defaults.set(newValue, forKey: Key.saveClipsToPhotos) }
    }

    var recordClipAudio: Bool {
        get { bool(Key.recordClipAudio, Default.recordClipAudio) }
        nonmutating set { defaults.set(newValue, forKey: Key.recordClipAudio) }
    }

    var announceCount: Bool {
        get { bool(Key.announceCount, Default.announceCount) }
        nonmutating set { defaults.set(newValue, forKey: Key.announceCount) }
    }

    var announceTempo: Bool {
        get { bool(Key.announceTempo, Default.announceTempo) }
        nonmutating set { defaults.set(newValue, forKey: Key.announceTempo) }
    }

    // Set once by onboarding (#5); the app shows the onboarding screens while it's false.
    var hasCompletedOnboarding: Bool {
        get { bool(Key.hasCompletedOnboarding, Default.hasCompletedOnboarding) }
        nonmutating set { defaults.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }

    // Putting has no camera angle; range sessions start at the default.
    func cameraAngle(for mode: PracticeMode) -> CameraAngle {
        mode == .putting ? .none : defaultCameraAngle
    }

    private func bool(_ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }
}
