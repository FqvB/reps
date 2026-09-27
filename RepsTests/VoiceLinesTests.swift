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
