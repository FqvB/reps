# #10 Voice output

Goal: the phone says the count after every rep and calls out block changes, target/stop, plan end and "Done. Session saved.". Lines never overlap, a stale count never backs up the queue, and music ducks while the phone speaks instead of stopping.

Spec: F6 ("Voice announces the count after every rep ("twelve"), and the block change ("nine iron, thirty reps")"), F22 (strict: "the voice tells you to stop"), §5.7 ("`AVSpeechSynthesizer`, pre-warmed at session start. Utterances queued, never overlapping. Count after each rep; on block change: "Nine iron. Thirty reps." At plan end: "Done. Session saved.""), §6 ("Callouts duck other audio (`AVAudioSession` `.duckOthers`) rather than stopping it."), non-functional latency "< 1.5 s". English only (Q12). ADR 0013 (handlers run synchronously and must not call back into the controller), ADR 0009 (synced folders, app target is MainActor by default).

Out of scope: tempo in the count (#27, leave `TODO(#27)`), "paused" / thermal / battery / lost-ball lines (§6, owned by #13/#28), F26 guidance, any capture or mic work (#13/#22).

Branch `feat/10-voice-output` from `main`. Never edit `project.pbxproj`; the new `Reps/Voice/` folder is picked up (ADR 0009).

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Layers | `VoiceLines` (pure: event → `[Phrase]`), `SpeechAnnouncer` (queue policy + settings gate, talks to a `Speaker`), `Speaker` protocol, `SystemSpeaker` (AVFoundation). | Mapping and queue policy are unit-tested with a fake speaker; only the thin wrapper is build-only. |
| Our own queue | The announcer holds the pending lines and hands the synthesizer **one line at a time**, the next one only after `finished`. | `AVSpeechSynthesizer` can only clear its whole queue (`stopSpeaking(at:)`), not drop one queued utterance, so "newest count wins" needs our own queue. Also guarantees "never overlapping". |
| Replace vs queue | A new **count** removes any unspoken count from the queue, then appends. **Callouts** (block, target/stop, plan end, saved) are never dropped. The line already being spoken always finishes. | Fast +1 taps must not produce "1, 2, 3, 4" seconds late; a block change must never be lost. A count is short (< 0.5 s), so letting it finish keeps latency well under 1.5 s. |
| "Done. Session saved." | New `SessionEvent.sessionSaved`, emitted by `finish()` only when its save succeeds (not on the discard path, not on a failed save). The announcer clears the queue, cuts off the current line (`stop()`), and speaks it. | §5.7 says it at plan end, but only Done saves (ADR 0013, F28) and #11's plan says "hook it to Done, not End". Saying "saved" before Done would be false. |
| Plan end | `.planEnded` → "End of plan." (PLACEHOLDER, Q39). | `planEnded` also fires on Next block from the last mandatory block with work left, so "complete" would be wrong. |
| Target reached | Minimums → "Target reached."; strict → "Stop. Block done." (both PLACEHOLDER, Q39). Order after a strict completion: count → stop → next block, as the controller emits them. | ADR 0013: minimums announce and stay; F22: strict tells you to stop. |
| Block callout | "9 iron. 30 reps." (§5.7); target 1 → "rep"; no/zero target (free sessions) → "7 iron."; a block that already has shots (resume, strip jump back, −1 reopening) → "9 iron. 12 of 30." (PLACEHOLDER, Q39). | Spec wording; the rest says where you stand. Free-session tag changes start a new block and re-say the club; accepted (rare, harmless). |
| Numbers | Digits in the text ("12"); the synthesizer reads them as words. | Deterministic tests, no NumberFormatter. |
| Club names | "PW/GW/SW/LW" (case-insensitive, trimmed, via `BagCatalog.key`) → "Pitching/Gap/Sand/Lob wedge"; everything else is spoken as stored (trimmed). | TTS would spell the abbreviations letter by letter. |
| Settings | `announceCount` gates **count lines only**; read from `AppSettings` on every event, so the Settings toggle applies mid-session. Callouts always speak (Q40). `announceTempo` stays `TODO(#27)`. | The toggle's name is "Announce count". |
| Audio session | Category `.playback`, mode `.voicePrompt`, options `[.duckOthers]`. Category set once in `prepare()` (no activation). Activate right before a line if inactive; deactivate with `.notifyOthersOnDeactivation` 0.6 s after the last line ends if nothing new started. | Context7 (AVFAudio): `.duckOthers` "implicitly sets the mixWithOthers option… Ducking begins when you activate your app's audio session and ends when you deactivate the session." `.voicePrompt` is "a mode that indicates that your app plays audio using text-to-speech", used by navigation apps. `.playback` keeps speaking with the silent switch on (wanted on the range). Apple recommends deferring activation until playback. The 0.6 s delay stops music pumping between back-to-back lines. |
| Spoken-audio apps | Not using `.interruptSpokenAudioAndMixWithOthers` (it pauses podcasts "as long as your session is active"). Podcasts duck like music. Q42. | §6 says duck, not stop. |
| Pre-warm | `SystemSpeaker.prepare()` configures the category and renders "Ready" with `synthesizer.write(_:toBufferCallback:)`, discarding the buffers: loads the voice without sound or ducking. `RootView` calls `announcer.prepare()` when it creates the controller, i.e. right before the first `start`/`resume`. `speak` also calls `prepare()` (idempotent). | No preload API exists; `write` renders offline. The first count comes seconds after the first block callout, which is warm by then. |
| Voice | Device English variant if the current language code starts with "en", else "en-US". Prefer an installed enhanced/premium voice for that code (not novelty, not Personal Voice); else `AVSpeechSynthesisVoice(language:)`. Default rate, no delays. | Context7: `currentLanguageCode()`, `speechVoices()`, `quality` (.default/.enhanced/.premium, downloaded), `voiceTraits` `.isNoveltyVoice`/`.isPersonalVoice`. |
| Delegate/threads | `SystemSpeaker` is MainActor (target default). Delegate methods are `nonisolated`, capture `ObjectIdentifier(utterance)` and hop to MainActor. A line ends on `didFinish` **or** `didCancel`; only the line we're tracking counts (the warm-up line and stopped lines are ignored). | Context7: `didCancel` is only called when stopped while actually speaking, and never for unspoken or in-delay utterances, so `stop()` resets state itself and never waits for a callback. |
| Hang guard | A line that hasn't reported back in 6 s is stopped and treated as finished. | Phone calls / route changes could otherwise leave the queue stuck forever. Proper interruption handling ("paused", §6) is #13's. |
| Where it's wired | `RootView.controller()`: `let announcer = SpeechAnnouncer(speaker: SystemSpeaker())`, `announcer.prepare()`, `made.addEventHandler { announcer.handle($0) }`. The closure keeps the announcer alive as long as the controller (app lifetime). | Replaces the `TODO(#10)` there. The announcer never calls the controller (ADR 0013). |

Typecheck of all four new files plus the `SessionEvent` change was done in the scratchpad with `swiftc -typecheck -swift-version 6 -default-isolation MainActor` (+ approachable concurrency features) against the iOS 26 simulator SDK: clean.

## Files

### New `Reps/Voice/VoiceLines.swift`

```swift
import Foundation

// One spoken line. A count goes stale once a newer count arrives; a callout never does.
nonisolated struct Phrase: Equatable, Sendable {
    nonisolated enum Kind: Equatable, Sendable {
        case count
        case callout
    }

    let text: String
    let kind: Kind
}

// F6, §5.7: what the voice says for each session event. English only (Q12).
nonisolated enum VoiceLines {
    static let sessionSaved = "Done. Session saved."
    static let targetReached = "Target reached."  // PLACEHOLDER: minimums target callout (Q39)
    static let strictStop = "Stop. Block done."  // PLACEHOLDER: strict stop callout, F22 (Q39)
    static let planEnded = "End of plan."  // PLACEHOLDER: no-block-left callout (Q39)

    // announceCount silences only the count; block, stop and saved callouts always speak (Q40).
    static func phrases(for event: SessionEvent, announceCount: Bool) -> [Phrase] {
        switch event {
        case .countChanged(let done, _):
            // TODO(#27): add the tempo ("twelve, three point one", §5.3a) when announceTempo is on.
            return announceCount ? [Phrase(text: count(done), kind: .count)] : []
        case .targetReached(_, _, let isStrict):
            return [Phrase(text: isStrict ? strictStop : targetReached, kind: .callout)]
        case .blockChanged(let clubName, let target, let done):
            return [Phrase(text: block(clubName: clubName, target: target, done: done), kind: .callout)]
        case .planEnded:
            return [Phrase(text: planEnded, kind: .callout)]
        case .sessionSaved:
            return [Phrase(text: sessionSaved, kind: .callout)]
        }
    }

    // Digits, not words: the synthesizer reads "12" as "twelve".
    static func count(_ done: Int) -> String {
        "\(done)"
    }

    // §5.7 "Nine iron. Thirty reps."; a block with shots already on it says where it stands.
    static func block(clubName: String, target: Int?, done: Int) -> String {
        let club = spokenClub(clubName)
        guard let target, target > 0 else { return "\(club)." }
        if done > 0 {
            return "\(club). \(done) of \(target)."  // PLACEHOLDER: returning-block callout (Q39)
        }
        return "\(club). \(target) \(target == 1 ? "rep" : "reps")."
    }

    // The bag's short wedge names would otherwise be read letter by letter.
    static func spokenClub(_ name: String) -> String {
        switch BagCatalog.key(name) {
        case "pw": "Pitching wedge"
        case "gw": "Gap wedge"
        case "sw": "Sand wedge"
        case "lw": "Lob wedge"
        default: BagCatalog.trimmed(name)
        }
    }
}
```

### New `Reps/Voice/Speaker.swift`

```swift
// The voice output seam: SystemSpeaker in the app, a fake in tests.
protocol Speaker: AnyObject {
    // Loads the voice and sets up audio so the first callout isn't late (§5.7 pre-warm).
    func prepare()
    // Speaks one line; calls `finished` once when it ends, unless stop() cancelled it first.
    func speak(_ text: String, finished: @escaping () -> Void)
    // Cuts off the current line; its `finished` is never called.
    func stop()
}
```

### New `Reps/Voice/SpeechAnnouncer.swift`

```swift
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
```

### New `Reps/Voice/SystemSpeaker.swift` (build-only)

```swift
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
```

Voice failures are silent on purpose (`try?`): counting must never depend on audio.

### Change `Reps/Session/SessionEvent.swift`

Add after `case planEnded`:

```swift
    // Done saved the session (§5.7 "Done. Session saved."); not sent when finish() discards or the save fails.
    case sessionSaved
```

(No exhaustive `switch` over `SessionEvent` exists outside `VoiceLines`; checked with grep.)

### Change `Reps/Session/SessionController.swift` — `finish()`

Replace the tail

```swift
        session.status = .finished
        session.endedAt = now()
        session.activeBlockOrder = nil
        save()
        reset()
    }
```

with

```swift
        session.status = .finished
        session.endedAt = now()
        session.activeBlockOrder = nil
        let saved = save()
        reset()
        // Only a session that really reached the store is announced as saved (§5.7).
        if saved { emit(.sessionSaved) }
    }
```

The discard path (`discard(); return`) emits nothing. `discard()` is unchanged.

### Change `Reps/App/RootView.swift` — `controller()`

Replace

```swift
        let made = SessionController(context: modelContext)
        // TODO(#10): subscribe the speaker here, e.g. made.addEventHandler { speaker.handle($0) }.
```

with

```swift
        let made = SessionController(context: modelContext)
        // The handler keeps the announcer alive with the controller; preparing now warms the voice (§5.7).
        let announcer = SpeechAnnouncer(speaker: SystemSpeaker())
        announcer.prepare()
        made.addEventHandler { announcer.handle($0) }
```

Keep the `TODO(#22)` line below it.

### Change `Reps/UI/Settings/SettingsView.swift`

Delete the line `// TODO(#10): the speaker reads announceCount.` (line ~68). Keep `// TODO(#27): …`.

### New tests

`RepsTests/VoiceLinesTests.swift`:

```swift
import Testing

@testable import Reps

struct VoiceLinesTests {
    private func texts(_ event: SessionEvent, announceCount: Bool = true) -> [String] {
        VoiceLines.phrases(for: event, announceCount: announceCount).map(\.text)
    }

    @Test func countSaysTheNumber() {
        #expect(
            VoiceLines.phrases(for: .countChanged(done: 12, target: 30), announceCount: true)
                == [Phrase(text: "12", kind: .count)])
    }

    @Test func countIsSilentWhenAnnounceCountIsOff() {
        #expect(texts(.countChanged(done: 12, target: 30), announceCount: false).isEmpty)
    }

    @Test func blockChangeFollowsTheSpec() {
        #expect(texts(.blockChanged(clubName: "9 iron", target: 30, done: 0)) == ["9 iron. 30 reps."])
    }

    @Test func singleRepTarget() {
        #expect(texts(.blockChanged(clubName: "9 iron", target: 1, done: 0)) == ["9 iron. 1 rep."])
    }

    @Test func returningBlockSaysWhereItStands() {
        #expect(texts(.blockChanged(clubName: "9 iron", target: 30, done: 12)) == ["9 iron. 12 of 30."])
    }

    @Test(arguments: [nil, 0] as [Int?])
    func untargetedBlockSaysTheClub(target: Int?) {
        #expect(texts(.blockChanged(clubName: "7 iron", target: target, done: 4)) == ["7 iron."])
    }

    @Test func wedgeAbbreviationsAreSpelledOut() {
        #expect(VoiceLines.spokenClub("PW") == "Pitching wedge")
        #expect(VoiceLines.spokenClub("gw") == "Gap wedge")
        #expect(VoiceLines.spokenClub(" SW ") == "Sand wedge")
        #expect(VoiceLines.spokenClub("LW") == "Lob wedge")
        #expect(VoiceLines.spokenClub(" 7 iron ") == "7 iron")
        #expect(VoiceLines.spokenClub("Mini driver") == "Mini driver")
        #expect(texts(.blockChanged(clubName: "PW", target: 20, done: 0)) == ["Pitching wedge. 20 reps."])
    }

    @Test func targetReachedDependsOnStrict() {
        #expect(texts(.targetReached(clubName: "9 iron", target: 30, isStrict: false)) == ["Target reached."])
        #expect(texts(.targetReached(clubName: "9 iron", target: 30, isStrict: true)) == ["Stop. Block done."])
    }

    @Test func planEndedAndSessionSaved() {
        #expect(texts(.planEnded) == ["End of plan."])
        #expect(texts(.sessionSaved) == ["Done. Session saved."])
    }

    @Test func calloutsSpeakWithAnnounceCountOff() {
        let events: [SessionEvent] = [
            .targetReached(clubName: "9 iron", target: 30, isStrict: true),
            .blockChanged(clubName: "9 iron", target: 30, done: 0), .planEnded, .sessionSaved,
        ]
        for event in events {
            let phrases = VoiceLines.phrases(for: event, announceCount: false)
            #expect(phrases.count == 1)
            #expect(phrases.allSatisfy { $0.kind == .callout })
        }
    }
}
```

`RepsTests/SpeechAnnouncerTests.swift`:

```swift
import Foundation
import Testing

@testable import Reps

@MainActor
final class FakeSpeaker: Speaker {
    private(set) var spoken: [String] = []
    private(set) var stops = 0
    private(set) var prepares = 0
    // Every line's `finished`, in order, so a test can fire a stale one.
    private(set) var finishers: [() -> Void] = []

    func prepare() { prepares += 1 }

    func speak(_ text: String, finished: @escaping () -> Void) {
        spoken.append(text)
        finishers.append(finished)
    }

    func stop() { stops += 1 }

    func finishLatest() { finishers.last?() }
}

@MainActor
struct SpeechAnnouncerTests {
    private let nineIron = SessionEvent.blockChanged(clubName: "9 iron", target: 30, done: 0)

    private func withAnnouncer(_ body: (SpeechAnnouncer, FakeSpeaker, AppSettings) throws -> Void) rethrows {
        let suite = "RepsTests.SpeechAnnouncer.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let speaker = FakeSpeaker()
        try body(SpeechAnnouncer(speaker: speaker, settings: settings), speaker, settings)
    }

    @Test func prepareWarmsTheSpeaker() {
        withAnnouncer { announcer, speaker, _ in
            announcer.prepare()
            #expect(speaker.prepares == 1)
        }
    }

    @Test func idleAnnouncerSpeaksAtOnce() {
        withAnnouncer { announcer, speaker, _ in
            announcer.handle(.countChanged(done: 1, target: 30))
            #expect(speaker.spoken == ["1"])
            #expect(announcer.isSpeaking)
        }
    }

    @Test func speaksOneLineAtATime() {
        withAnnouncer { announcer, speaker, _ in
            announcer.handle(nineIron)
            announcer.handle(.countChanged(done: 1, target: 30))
            #expect(speaker.spoken == ["9 iron. 30 reps."])
            #expect(announcer.pending.map(\.text) == ["1"])
            speaker.finishLatest()
            #expect(speaker.spoken == ["9 iron. 30 reps.", "1"])
            speaker.finishLatest()
            #expect(!announcer.isSpeaking)
            #expect(announcer.pending.isEmpty)
        }
    }

    @Test func newerCountReplacesAnUnspokenOne() {
        withAnnouncer { announcer, speaker, _ in
            announcer.handle(nineIron)
            for done in 1...3 { announcer.handle(.countChanged(done: done, target: 30)) }
            #expect(announcer.pending.map(\.text) == ["3"])
            speaker.finishLatest()
            #expect(speaker.spoken == ["9 iron. 30 reps.", "3"])
        }
    }

    @Test func newerCountQueuesBehindPendingCallouts() {
        withAnnouncer { announcer, _, _ in
            announcer.handle(.countChanged(done: 1, target: 2))
            announcer.handle(.countChanged(done: 2, target: 2))
            announcer.handle(.targetReached(clubName: "9 iron", target: 2, isStrict: false))
            announcer.handle(.countChanged(done: 3, target: 2))
            #expect(announcer.pending.map(\.text) == ["Target reached.", "3"])
        }
    }

    @Test func calloutsAreNeverDropped() {
        withAnnouncer { announcer, speaker, _ in
            // A strict block completing: count, stop, next block, all in order.
            announcer.handle(.countChanged(done: 1, target: 2))
            announcer.handle(.countChanged(done: 2, target: 2))
            announcer.handle(.targetReached(clubName: "9 iron", target: 2, isStrict: true))
            announcer.handle(.blockChanged(clubName: "PW", target: 20, done: 0))
            for _ in 0..<3 { speaker.finishLatest() }
            #expect(speaker.spoken == ["1", "2", "Stop. Block done.", "Pitching wedge. 20 reps."])
        }
    }

    @Test func announceCountIsReadOnEveryEvent() {
        withAnnouncer { announcer, speaker, settings in
            announcer.handle(.countChanged(done: 1, target: 30))
            speaker.finishLatest()
            settings.announceCount = false
            announcer.handle(.countChanged(done: 2, target: 30))
            #expect(speaker.spoken == ["1"])
            announcer.handle(nineIron)
            #expect(speaker.spoken == ["1", "9 iron. 30 reps."])
        }
    }

    @Test func sessionSavedCutsInAndClearsTheQueue() {
        withAnnouncer { announcer, speaker, _ in
            announcer.handle(.countChanged(done: 1, target: 30))
            announcer.handle(.countChanged(done: 2, target: 30))
            announcer.handle(.planEnded)
            announcer.handle(.sessionSaved)
            #expect(speaker.stops == 1)
            #expect(speaker.spoken == ["1", "Done. Session saved."])
            #expect(announcer.pending.isEmpty)
        }
    }

    @Test func sessionSavedWhenIdleDoesNotStop() {
        withAnnouncer { announcer, speaker, _ in
            announcer.handle(.sessionSaved)
            #expect(speaker.stops == 0)
            #expect(speaker.spoken == ["Done. Session saved."])
        }
    }

    @Test func lateFinishFromAStoppedLineIsIgnored() {
        withAnnouncer { announcer, speaker, _ in
            announcer.handle(.countChanged(done: 1, target: 30))
            announcer.handle(.sessionSaved)
            speaker.finishers[0]()  // the cancelled "1" reports late
            announcer.handle(.countChanged(done: 2, target: 30))
            #expect(speaker.spoken == ["1", "Done. Session saved."])
            #expect(announcer.pending.map(\.text) == ["2"])
        }
    }
}
```

Add to `RepsTests/SessionControllerTests.swift` (after `finishMarksSessionFinished`):

```swift
    @Test func finishAnnouncesTheSaveLast() throws {
        try start()
        hit(1)
        controller.finish()
        #expect(log.events == [.countChanged(done: 1, target: 3), .sessionSaved])
    }

    @Test func failedFinishIsNotAnnounced() throws {
        var shouldFail = false
        let log = EventLog()
        let controller = SessionController(
            context: context, clipFiles: clips, now: { clock.next() },
            saveHook: {
                if shouldFail { throw TestSaveError() }
                try context.save()
            })
        controller.addEventHandler { log.events.append($0) }
        try controller.start(plan: makePlan(), cameraAngle: .faceOn)
        controller.recordShot(source: .camera)

        shouldFail = true
        controller.finish()
        #expect(!log.events.contains(.sessionSaved))
        #expect(controller.lastSaveError != nil)
    }
```

Add to `RepsTests/FreeSessionTests.swift`:

```swift
    @Test func discardedFreeSessionIsNotAnnounced() throws {
        controller.finish()
        #expect(!log.events.contains(.sessionSaved))
    }

    @Test func finishedFreeSessionIsAnnounced() throws {
        hit(1)
        controller.finish()
        #expect(log.events.last == .sessionSaved)
    }
```

## Steps (one commit each, body `Refs #10`)

Set once:

```
DEST27='platform=iOS Simulator,id=A26BAE3A-CDDE-45A8-892D-2359740C877A'   # iPhone 17 Pro, iOS 27
DEST265='platform=iOS Simulator,id=6D2623EF-0394-46F9-BFEC-022E3D2B7FE8'  # iPhone 17 Pro, iOS 26.5
T="xcodebuild test -project Reps.xcodeproj -scheme Reps -testPlan Unit"
```

1. **`announced session saved on done`** (TDD). Add the four controller tests above. Run `$T -destination "$DEST27" -only-testing:RepsTests/SessionControllerTests -only-testing:RepsTests/FreeSessionTests` → fails to compile (no `.sessionSaved`). Add the `SessionEvent` case and the `finish()` change. Re-run → passes, existing tests unchanged. Update code-reference entries for `SessionEvent.swift` and `SessionController.swift`.
2. **`added voice lines`** (TDD). Add `VoiceLinesTests.swift`, run `-only-testing:RepsTests/VoiceLinesTests` → fails to compile. Add `Reps/Voice/VoiceLines.swift`. Re-run → passes.
3. **`added speech announcer`** (TDD). Add `SpeechAnnouncerTests.swift`, run `-only-testing:RepsTests/SpeechAnnouncerTests` → fails. Add `Speaker.swift` and `SpeechAnnouncer.swift`. Re-run → passes.
4. **`added system speaker`**. Add `SystemSpeaker.swift`. Build: `xcodebuild build -project Reps.xcodeproj -scheme Reps -destination "$DEST27" -quiet` → succeeds, no new warnings (in particular no concurrency warnings on the delegate methods).
5. **`wired voice into sessions`**. `RootView` and `SettingsView` changes. Build as in step 4. `grep -rn "TODO(#10)" Reps` → nothing.
6. **`documented voice output`**. Docs below. The last commit / PR uses `Closes #10`; update `docs/roadmap.md` #10 to ☑ when it closes.

## Tests

- Unit (Swift Testing): `VoiceLinesTests`, `SpeechAnnouncerTests` (new), `SessionControllerTests`, `FreeSessionTests` (added cases). `SessionResumeTests` is untouched but emits events; it runs in the final full pass.
- `SystemSpeaker` / `VoiceAudioSession`: build only (AVFoundation, needs ears). No UI tests.

## Verification

1. Steps 1–3 filtered runs pass on `$DEST27`.
2. Build on `$DEST27`, no new warnings.
3. Full Unit plan on both sims: `$T -destination "$DEST27"` and `$T -destination "$DEST265"` → both `** TEST SUCCEEDED **`.
4. `grep -c "PLACEHOLDER:" Reps/Voice/VoiceLines.swift` → `4`. `grep -rn "TODO(#10)" Reps` → nothing. `grep -rn "TODO(#27)" Reps/Voice` → 1 line.
5. Smoke on the iOS 27 simulator (it speaks through the Mac): start a plan → hear "9 iron. 30 reps." (or the first block); tap +1 five times fast → hear at most two counts, ending on "5"; End → silence; Done → "Done. Session saved." Settings → turn Announce count off → start again → +1 is silent, block callout still speaks.
6. On device when available (owner): music playing in another app ducks during each line and comes back ~0.6 s after; works with the silent switch on; first count after a shot comes well under 1.5 s. Not a blocker for merging (free provisioning).

## Docs

- `docs/code-reference.md`: add sections `Reps/Voice/VoiceLines.swift` (`Phrase` count/callout; `VoiceLines.phrases(for:announceCount:)`, `count(_:)`, `block(clubName:target:done:)`, `spokenClub(_:)`, the four line constants), `Reps/Voice/Speaker.swift` (`Speaker`: `prepare()`, `speak(_:finished:)`, `stop()` contract), `Reps/Voice/SpeechAnnouncer.swift` (`SpeechAnnouncer(speaker:settings:)`, `prepare()`, `handle(_:)`; one line at a time, newest count replaces unspoken counts, callouts never dropped, `sessionSaved` clears and cuts in; `pending`, `isSpeaking` for tests), `Reps/Voice/SystemSpeaker.swift` (`SystemSpeaker`: English voice choice, write-based warm-up, 0.6 s release, 6 s line timeout; `VoiceAudioSession.configure/activate/deactivate`: `.playback` + `.voicePrompt` + `.duckOthers`), `RepsTests/VoiceLinesTests.swift`, `RepsTests/SpeechAnnouncerTests.swift` (with `FakeSpeaker`). Update `SessionEvent` (add `sessionSaved`), `SessionController.finish()` ("emits `sessionSaved` only when its save succeeds; not on the discard path"), `RootView` (replace "voice hook is `TODO(#10)`" with "creates a `SpeechAnnouncer(speaker: SystemSpeaker())`, prepares it, and registers `handle` on the controller").
- `docs/adr/0015-voice-output.md` (use the next free number if 0015 is taken by then):

  ```
  # 0015 — Voice output: own queue, newest count wins, duck while speaking

  - Status: Accepted
  - Date: <commit date>

  ## Context
  F6/§5.7 want the count after every rep and a block callout, pre-warmed, queued and never overlapping; §6 wants music ducked, not stopped. AVSpeechSynthesizer can only clear its whole queue. Only Done saves a session (ADR 0013), but §5.7 says "Done. Session saved." at plan end.

  ## Decision
  - SessionEvent → text lives in `VoiceLines` (pure). `SpeechAnnouncer` keeps its own queue and hands `Speaker` one line at a time. A new count replaces any unspoken count; callouts are never dropped; the line being spoken finishes.
  - "Done. Session saved." is spoken on a new `SessionEvent.sessionSaved`, sent by `finish()` only after a successful save. It clears the queue and cuts in. Plan end says "End of plan." instead.
  - `announceCount` silences counts only (Q40).
  - Audio session: `.playback`, mode `.voicePrompt`, `[.duckOthers]`; active only while speaking, deactivated with `.notifyOthersOnDeactivation` 0.6 s after the last line. `VoiceAudioSession` is the only code that touches the app audio session.
  - Warm-up renders a line with `write(_:toBufferCallback:)` when the controller is created.

  ## Consequences
  Mapping and queue policy are unit-tested with a fake; the AVFoundation wrapper is checked by ear. #22 (clip audio) must revisit the audio session: recording needs `.playAndRecord`, an always-active session, and `AVCaptureSession.automaticallyConfiguresApplicationAudioSession = false` so capture doesn't reroute speech (Q41).
  ```
- `docs/open-questions.md`, Open table. **Check the file first**: #24/#25 may have taken numbers up to ~Q38. Use the next four free numbers (expected Q39–Q42); if they differ, also change the `(Q39)`/`(Q40)`/`(Q41)` references in `VoiceLines.swift` and `SystemSpeaker.swift` comments and the ADR.

  ```
  | Q39 | Callout wording beyond §5.7: minimums target "Target reached.", strict "Stop. Block done.", plan end "End of plan.", a block with shots already "9 iron. 12 of 30.". §5.7's "Done. Session saved." now plays on Done, not at plan end (only Done saves). OK? | – (#10 ships these) | All four are `PLACEHOLDER` constants in `VoiceLines`. |
  | Q40 | "Announce count" off silences only the count; block, stop, plan-end and saved callouts still speak. Add a master "Voice" toggle? | – (#10 ships counts-only) | A master toggle is one more `AppSettings` key checked first in `SpeechAnnouncer.handle`. |
  | Q41 | Voice with clip audio (#22): recording needs `.playAndRecord` and a session that stays active, so music stays ducked the whole session and callouts ("twelve") are recorded into every clip's sound. Accept, or mute callouts while a clip window is open? Also `AVCaptureSession.automaticallyConfiguresApplicationAudioSession` must be false or speech may move to the earpiece. | #13, #22 | `VoiceAudioSession` is the single place to change. Alternative: `AVSpeechSynthesizer.usesApplicationAudioSession = false` lets the system manage speech separately; ducking behaviour then needs a device test. |
  | Q42 | Podcasts/audiobooks duck under the callouts like music. Pause spoken audio instead (`.interruptSpokenAudioAndMixWithOthers`, Apple's advice for exercise apps)? | – | Pausing every ~10 s on the range seems worse than ducking. One option in `VoiceAudioSession.configure`. |
  ```
- `docs/roadmap.md`: #10 ☑ when the PR merges.
- No spec edit (spec is the source of truth; the Done/plan-end change is recorded in the ADR and Q39).

## Placeholders added

In `Reps/Voice/VoiceLines.swift` (4): `targetReached` "Target reached.", `strictStop` "Stop. Block done.", `planEnded` "End of plan.", returning-block "`club`. `done` of `target`.". All point to Q39.

## Risks

- **Pre-warm via `write`** is not a documented preload; if the first line still lags or `write` delays the first `speak`, fall back to nothing (the first block callout warms the voice) — delete the `write` line. The identity check in `ended(_:)` already ignores any delegate callback for the warm-up utterance.
- **Deactivation** is synchronous and can fail with "I/O running" if the synthesizer hasn't torn down; failure is harmless (`isAudioActive` stays true, next release retries after the next line). If music stays ducked on device, raise `releaseDelay`.
- **Interruptions** (calls, Siri): not handled beyond the 6 s timeout. #13 owns "paused" (§6).
- **Capture coexistence** (#13/#22): see Q41. Until #22, the session is `.playback`; #13 video-only capture doesn't touch the audio session, but #22 adding a mic input will, unless `automaticallyConfiguresApplicationAudioSession` is turned off.
- **Resume prompt "End it"** runs resume + finish: the block callout starts and is immediately cut by "Done. Session saved.". Acceptable.
- **Free-session tag change** re-says the club (a new block starts). Acceptable; rare.
- **Simulator** speaks through the Mac, so ducking and the silent switch can only be checked on a device.
