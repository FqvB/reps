import Foundation
import Testing

@testable import Reps

@MainActor
struct SummaryDisplayTests {
    private func block(
        _ order: Int, _ club: String, done: Int, target: Int?, manual: Int = 0, note: String? = nil,
        tags: [String] = [], clips: Int = 0, tempos: [Double] = []
    ) -> SummaryBlock {
        SummaryBlock(
            order: order, clubName: club, note: note, tags: tags, counted: done - manual, manualAdjust: manual,
            target: target, clipCount: clips, tempos: tempos)
    }

    // Figma 12's blocks: 190 of 170 shots. Q22 caps the headline at 100 %, not Figma's 112 %.
    private var wedgeDay: [SummaryBlock] {
        [
            block(0, "Pitching wedge", done: 40, target: 40, clips: 40, tempos: [3.0, 3.2]),
            block(1, "Gap wedge", done: 45, target: 30, manual: 2, clips: 45, tempos: [2.8]),
            block(2, "Sand wedge", done: 40, target: 40, manual: -1, clips: 40),
            block(3, "Lob wedge", done: 30, target: 30, clips: 30),
            block(4, "9 iron", done: 35, target: 30, clips: 35),
        ]
    }

    @Test func plannedSessionMatchesFigma() {
        let summary = SummaryDisplay.summary(
            planName: "Wedge day", mode: .rangeCounterWithClips, blocks: wedgeDay.reversed(), elapsed: 48 * 60 + 30)
        #expect(summary.subtitle == "Wedge day · Range + clips · 48 min")
        #expect(summary.headline == "100%")
        #expect(summary.caption == "190 of 170 shots · every block complete")
        #expect(summary.rows.map(\.title) == ["Pitching wedge", "Gap wedge", "Sand wedge", "Lob wedge", "9 iron"])
        #expect(summary.rows[1].detail == "45 / 30")
        #expect(summary.rows[1].percent == "150%")
        #expect(summary.rows[1].isOverTarget)
        #expect(summary.rows[1].bar == SummaryBar(fill: 1, surplusFrom: 30.0 / 45.0))
        #expect(summary.rows[4].percent == "117%")
        #expect(summary.rows[0].percent == "100%")
        #expect(!summary.rows[0].isOverTarget)
        #expect(summary.rows[0].bar == SummaryBar(fill: 1, surplusFrom: nil))
        #expect(
            summary.stats == [
                SummaryStat(value: "190", label: "clips saved"),
                SummaryStat(value: "3.0 : 1", label: "avg tempo"),
                SummaryStat(value: "3", label: "manual fixes"),
            ])
    }

    @Test func shortBlocksLowerTheHeadline() {
        let blocks = [
            block(0, "PW", done: 45, target: 30),
            block(1, "GW", done: 15, target: 30),
            block(2, "SW", done: 0, target: 40),
        ]
        let summary = SummaryDisplay.summary(planName: "Wedge day", mode: .rangeCounter, blocks: blocks, elapsed: 0)
        #expect(summary.headline == "45%")
        #expect(summary.caption == "60 of 100 shots · 2 blocks short")
        #expect(summary.rows[1].bar == SummaryBar(fill: 0.5, surplusFrom: nil))
        #expect(summary.rows[2].percent == "0%")
        #expect(summary.rows[2].bar == SummaryBar(fill: 0, surplusFrom: nil))
        #expect(summary.subtitle == "Wedge day · Range · under 1 min")
    }

    @Test func percentNeverShowsHundredBeforeTarget() {
        #expect(SummaryDisplay.percent(299.0 / 300.0, isComplete: false) == "99%")
        #expect(SummaryDisplay.percent(1.0, isComplete: true) == "100%")
        #expect(SummaryDisplay.percent(35.0 / 30.0, isComplete: true) == "117%")
        #expect(SummaryDisplay.percent(1.0 / 3.0, isComplete: false) == "33%")
        let caption = SummaryDisplay.overall([block(0, "PW", done: 29, target: 30)], mode: .rangeCounter).caption
        #expect(caption == "29 of 30 shots · 1 block short")
    }

    @Test func puttingUsesNotesAndPutts() {
        let blocks = [
            block(0, "Putter", done: 30, target: 30, note: "3 ft"),
            block(1, "Putter", done: 12, target: 30, note: " "),
        ]
        let summary = SummaryDisplay.summary(planName: "Lag", mode: .putting, blocks: blocks, elapsed: 600)
        #expect(summary.rows.map(\.title) == ["3 ft", "Putter"])
        #expect(summary.caption == "42 of 60 putts · 1 block short")
        #expect(summary.subtitle == "Lag · Putting · 10 min")
    }

    @Test func freeSessionShowsCountsWithoutTargets() {
        let blocks = [
            block(0, "7 iron", done: 12, target: nil),
            block(1, "7 iron", done: 8, target: nil, manual: 8, tags: ["fade", "low"]),
            block(2, "PW", done: 0, target: nil),
        ]
        let summary = SummaryDisplay.summary(planName: nil, mode: .rangeCounter, blocks: blocks, elapsed: 3900)
        #expect(summary.subtitle == "Free session · Range · 1 h 5 min")
        #expect(summary.headline == "20")
        #expect(summary.caption == "shots")
        #expect(summary.rows.map(\.title) == ["7 iron", "7 iron · fade, low"])
        #expect(summary.rows[0].detail == "12")
        #expect(summary.rows[0].percent == nil)
        #expect(summary.rows[0].bar == nil)
        #expect(summary.stats[1].value == "–")
        #expect(summary.stats[2].value == "8")
    }

    @Test func emptyFreeSession() {
        let summary = SummaryDisplay.summary(
            planName: nil, mode: .putting, blocks: [block(0, "Putter", done: 0, target: nil)], elapsed: 0)
        #expect(summary.headline == "0")
        #expect(summary.caption == "putts")
        #expect(summary.rows.isEmpty)
    }

    @Test func duration() {
        #expect(SummaryDisplay.duration(-5) == "under 1 min")
        #expect(SummaryDisplay.duration(59) == "under 1 min")
        #expect(SummaryDisplay.duration(60) == "1 min")
        #expect(SummaryDisplay.duration(59 * 60 + 59) == "59 min")
        #expect(SummaryDisplay.duration(2 * 3600) == "2 h")
        #expect(SummaryDisplay.duration(3600 + 12 * 60) == "1 h 12 min")
    }

    @Test func tempo() {
        #expect(SummaryDisplay.tempo([]) == "–")
        #expect(SummaryDisplay.tempo([3.0]) == "3.0 : 1")
        #expect(SummaryDisplay.tempo([2.9, 3.3]) == "3.1 : 1")
    }
}
