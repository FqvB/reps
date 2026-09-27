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
