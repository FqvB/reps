import Foundation
import Testing

@testable import Reps

@MainActor
struct SessionDisplayTests {
    @Test func titleAndSubtitle() {
        #expect(SessionDisplay.title(planName: "Wedge day") == "Wedge day")
        #expect(SessionDisplay.title(planName: nil) == "Free session")
        #expect(SessionDisplay.subtitle(mode: .rangeCounterWithClips, angle: .faceOn) == "Range + clips · face-on")
        #expect(SessionDisplay.subtitle(mode: .rangeCounter, angle: .downTheLine) == "Range · down-the-line")
        #expect(SessionDisplay.subtitle(mode: .rangeCounter, angle: .none) == "Range")
        #expect(SessionDisplay.subtitle(mode: .putting, angle: .faceOn) == "Putting counter")
    }

    @Test func countDetail() {
        #expect(SessionDisplay.countDetail(done: 12, target: 30, note: "95 m", mode: .rangeCounterWithClips) == "of 30")
        #expect(SessionDisplay.countDetail(done: 17, target: 30, note: "6 ft", mode: .putting) == "of 30 · 6 ft")
        #expect(SessionDisplay.countDetail(done: 17, target: 30, note: "  ", mode: .putting) == "of 30")
        #expect(SessionDisplay.countDetail(done: 17, target: 30, note: nil, mode: .putting) == "of 30")
        #expect(SessionDisplay.countDetail(done: 1, target: nil, note: nil, mode: .rangeCounter) == "shot")
        #expect(SessionDisplay.countDetail(done: 0, target: nil, note: nil, mode: .rangeCounter) == "shots")
        #expect(SessionDisplay.countDetail(done: 3, target: nil, note: nil, mode: .putting) == "putts")
    }

    private let wedgeDay = [
        BlockSnapshot(order: 0, clubName: "PW", note: "110 m", done: 40, target: 40),
        BlockSnapshot(order: 1, clubName: "GW", note: nil, done: 12, target: 30),
        BlockSnapshot(order: 2, clubName: "SW", note: nil, done: 0, target: 40),
        BlockSnapshot(order: 3, clubName: "9i", note: nil, done: 45, target: 30),
    ]

    @Test func stripChipsFreeOrder() {
        let chips = SessionDisplay.stripChips(
            wedgeDay, mode: .rangeCounterWithClips, activeOrder: 1, canSelect: true, isStrict: false)
        #expect(chips.map(\.id) == [0, 1, 2, 3])
        #expect(chips.map(\.title) == ["PW", "GW", "SW", "9i"])
        #expect(chips.map(\.detail) == ["40/40", "12/30", "0/40", "45/30"])
        #expect(chips.map(\.state) == [.complete, .active, .pending, .complete])
        #expect(chips.map(\.isSelectable) == [true, false, true, true])
    }

    @Test func stripChipsStrictAndLocked() {
        let strict = SessionDisplay.stripChips(
            wedgeDay, mode: .rangeCounter, activeOrder: 1, canSelect: true, isStrict: true)
        #expect(strict.map(\.isSelectable) == [false, false, true, false])
        let locked = SessionDisplay.stripChips(
            wedgeDay, mode: .rangeCounter, activeOrder: 1, canSelect: false, isStrict: false)
        #expect(locked.allSatisfy { !$0.isSelectable })
        let ended = SessionDisplay.stripChips(
            wedgeDay, mode: .rangeCounter, activeOrder: nil, canSelect: true, isStrict: false)
        #expect(!ended.contains { $0.state == .active })
        #expect(ended.map(\.isSelectable) == [true, true, true, true])
    }

    @Test func stripChipsPuttingUseNotes() {
        let blocks = [
            BlockSnapshot(order: 0, clubName: "Putter", note: "3 ft", done: 30, target: 30),
            BlockSnapshot(order: 1, clubName: "Putter", note: " ", done: 17, target: 30),
        ]
        let chips = SessionDisplay.stripChips(blocks, mode: .putting, activeOrder: 1, canSelect: true, isStrict: false)
        #expect(chips.map(\.title) == ["3 ft", "Putter"])
        #expect(SessionDisplay.blockTitle(clubName: "GW", note: "95 m", mode: .rangeCounter) == "GW")
    }

    @Test func nextBlockPrompt() {
        let prompt = SessionDisplay.nextBlockPrompt(clubName: "Gap wedge", done: 12, target: 30, canComeBack: true)
        #expect(prompt?.title == "Move on at 12 of 30?")
        #expect(
            prompt?.message
                == "Gap wedge will stay at 40% for this session. You can come back to it from the block strip.")
        let locked = SessionDisplay.nextBlockPrompt(clubName: "GW", done: 29, target: 30, canComeBack: false)
        #expect(locked?.message == "GW will stay at 96% for this session.")
        #expect(SessionDisplay.nextBlockPrompt(clubName: "GW", done: 30, target: 30, canComeBack: true) == nil)
        #expect(SessionDisplay.nextBlockPrompt(clubName: "GW", done: 45, target: 30, canComeBack: true) == nil)
        #expect(SessionDisplay.nextBlockPrompt(clubName: "GW", done: 3, target: nil, canComeBack: true) == nil)
        #expect(SessionDisplay.nextBlockPrompt(clubName: "GW", done: 0, target: 0, canComeBack: true) == nil)
    }

    @Test func elapsed() {
        #expect(SessionDisplay.elapsed(0) == "0:00")
        #expect(SessionDisplay.elapsed(59.9) == "0:59")
        #expect(SessionDisplay.elapsed(760) == "12:40")
        #expect(SessionDisplay.elapsed(3723) == "1:02:03")
        #expect(SessionDisplay.elapsed(36000) == "10:00:00")
        #expect(SessionDisplay.elapsed(-5) == "0:00")
    }

    @Test func tagChoices() {
        let choices = SessionDisplay.tagChoices(
            active: ["fade", " fade "], recent: ["gate drill", "fade", " ", "draw", "gate drill"])
        #expect(choices == ["fade", "gate drill", "draw"])
        let capped = SessionDisplay.tagChoices(active: ["low"], recent: ["a", "b", "c", "d"], limit: 2)
        #expect(capped == ["low", "a", "b"])
    }

    @Test func togglingAndAddingTags() {
        #expect(SessionDisplay.toggling("fade", in: ["fade", "draw"]) == ["draw"])
        #expect(SessionDisplay.toggling("low", in: ["fade"]) == ["fade", "low"])
        #expect(SessionDisplay.adding("  low ", to: ["fade"]) == ["fade", "low"])
        #expect(SessionDisplay.adding("fade", to: ["fade"]) == nil)
        #expect(SessionDisplay.adding("   ", to: []) == nil)
    }

    @Test func resumeMessage() {
        #expect(
            SessionDisplay.resumeMessage(title: "Wedge day", done: 42, mode: .rangeCounter)
                == "Wedge day · 42 shots so far.")
        #expect(
            SessionDisplay.resumeMessage(title: "Free session", done: 1, mode: .putting)
                == "Free session · 1 putt so far.")
    }
}
