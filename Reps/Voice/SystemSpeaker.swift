import AVFoundation

// AVSpeechSynthesizer behind Speaker (§5.7, §6). Build-only; checked by ear on a device.
final class SystemSpeaker: NSObject, Speaker, AVSpeechSynthesizerDelegate {
    // Music comes back up this long after the last line, so a burst of callouts doesn't pump it.
    private static let releaseDelay: Duration = .milliseconds(600)
    // A line that never reports back (e.g. a phone call took the audio) is dropped after this.
    private static let lineTimeout: Duration = .seconds(6)

    private let synthesizer = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice?
    private var current: (utterance: AVSpeechUtterance, finished: () -> Void)?
    private var isPrepared = false
    private var isAudioActive = false
    private var releaseTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    override init() {
        voice = Self.englishVoice()
        super.init()
        synthesizer.delegate = self
    }

    func prepare() {
        guard !isPrepared else { return }
        isPrepared = true
        VoiceAudioSession.configure()
        // Rendering a line to a buffer loads the voice without playing or ducking anything.
        synthesizer.write(makeUtterance("Ready")) { _ in }
    }

    func speak(_ text: String, finished: @escaping () -> Void) {
        prepare()
        releaseTask?.cancel()
        if !isAudioActive {
            isAudioActive = VoiceAudioSession.activate()
        }
        let utterance = makeUtterance(text)
        current = (utterance, finished)
        synthesizer.speak(utterance)
        let id = ObjectIdentifier(utterance)
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.lineTimeout)
            guard !Task.isCancelled else { return }
            self?.synthesizer.stopSpeaking(at: .immediate)
            self?.ended(id)
        }
    }

    func stop() {
        current = nil
        timeoutTask?.cancel()
        synthesizer.stopSpeaking(at: .immediate)
        scheduleRelease()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.ended(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.ended(id) }
    }

    // Ignores the warm-up line and anything stop() already dropped.
    private func ended(_ id: ObjectIdentifier) {
        guard let line = current, ObjectIdentifier(line.utterance) == id else { return }
        current = nil
        timeoutTask?.cancel()
        scheduleRelease()
        line.finished()
    }

    private func scheduleRelease() {
        releaseTask?.cancel()
        releaseTask = Task { [weak self] in
            try? await Task.sleep(for: Self.releaseDelay)
            guard !Task.isCancelled else { return }
            self?.releaseAudio()
        }
    }

    private func releaseAudio() {
        guard isAudioActive, current == nil, !synthesizer.isSpeaking else { return }
        isAudioActive = !VoiceAudioSession.deactivate()
    }

    private func makeUtterance(_ text: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        return utterance
    }

    // English only (Q12): the device's English variant or US; a downloaded enhanced/premium voice wins.
    private static func englishVoice() -> AVSpeechSynthesisVoice? {
        let deviceCode = AVSpeechSynthesisVoice.currentLanguageCode()
        let code = deviceCode.hasPrefix("en") ? deviceCode : "en-US"
        let better = AVSpeechSynthesisVoice.speechVoices()
            .filter { voice in
                voice.language == code && voice.quality != .default
                    && !voice.voiceTraits.contains(.isNoveltyVoice) && !voice.voiceTraits.contains(.isPersonalVoice)
            }
            .max { $0.quality.rawValue < $1.quality.rawValue }
        return better ?? AVSpeechSynthesisVoice(language: code)
    }
}

// The only code that shapes the app's audio session; #22 revisits it when clips record sound (Q41).
enum VoiceAudioSession {
    // .playback speaks with the silent switch on; .duckOthers lowers music instead of stopping it (§6).
    static func configure() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
    }

    // Ducking starts here (AVAudioSession docs: it lasts while the session is active).
    static func activate() -> Bool {
        (try? AVAudioSession.sharedInstance().setActive(true)) != nil
    }

    // Ends the duck and lets paused apps resume.
    static func deactivate() -> Bool {
        (try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)) != nil
    }
}
