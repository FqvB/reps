import Foundation

// F6, §5.7: turns session events into speech, one line at a time, never overlapping.
final class SpeechAnnouncer {
    private let speaker: any Speaker
    private let settings: AppSettings
    private(set) var pending: [Phrase] = []
    private(set) var isSpeaking = false
    // Bumped on every line and every stop, so a late `finished` from a cancelled line is ignored.
    private var generation = 0

    init(speaker: any Speaker, settings: AppSettings = AppSettings()) {
        self.speaker = speaker
        self.settings = settings
    }

    func prepare() {
        speaker.prepare()
    }

    // Registered with SessionController.addEventHandler; never calls back into the controller (ADR 0013).
    func handle(_ event: SessionEvent) {
        if event == .sessionSaved {
            // Done: anything still queued is moot, so the closing line cuts in.
            pending = []
            if isSpeaking { stopCurrent() }
        }
        // Read on every event so the Settings toggle applies mid-session.
        for phrase in VoiceLines.phrases(for: event, announceCount: settings.announceCount) {
            enqueue(phrase)
        }
    }

    private func enqueue(_ phrase: Phrase) {
        // Only the newest count is worth saying; fast +1 taps must not back up the queue.
        if phrase.kind == .count {
            pending.removeAll { $0.kind == .count }
        }
        pending.append(phrase)
        speakNextIfIdle()
    }

    private func speakNextIfIdle() {
        guard !isSpeaking, !pending.isEmpty else { return }
        let phrase = pending.removeFirst()
        isSpeaking = true
        generation += 1
        let line = generation
        speaker.speak(phrase.text) { [weak self] in
            guard let self, self.generation == line else { return }
            self.isSpeaking = false
            self.speakNextIfIdle()
        }
    }

    private func stopCurrent() {
        generation += 1
        isSpeaking = false
        speaker.stop()
    }
}
