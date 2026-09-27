import Foundation
import Testing

@testable import Reps

struct PlanSummaryTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let locale = Locale(identifier: "en_US")
    // Wednesday 16 September 2026, 10:00 UTC
    private let now = Date(timeIntervalSince1970: 1_789_552_800)

    private func lastDone(daysAgo days: Double) -> String {
        PlanSummary.lastDone(now.addingTimeInterval(-days * 86_400), now: now, calendar: calendar, locale: locale)
    }

    @Test func repsUseSingularPluralAndPutts() {
        #expect(PlanSummary.reps(1, mode: .rangeCounter) == "1 shot")
        #expect(PlanSummary.reps(170, mode: .rangeCounterWithClips) == "170 shots")
        #expect(PlanSummary.reps(90, mode: .putting) == "90 putts")
        #expect(PlanSummary.blocks(1) == "1 block")
    }

    @Test func subtitleAndTotals() {
        #expect(
            PlanSummary.subtitle(blockCount: 5, totalReps: 170, mode: .rangeCounter, isOrderMandatory: false)
                == "5 blocks · 170 shots · any order")
        #expect(
            PlanSummary.subtitle(blockCount: 3, totalReps: 90, mode: .putting, isOrderMandatory: true)
                == "3 blocks · 90 putts · in order")
        #expect(PlanSummary.totals(blockCount: 0, totalReps: 0, mode: .rangeCounter) == "0 blocks · 0 shots")
    }

    @Test func blockDetailAddsNote() {
        #expect(PlanSummary.blockDetail(targetReps: 40, note: "110 m", mode: .rangeCounter) == "40 shots · 110 m")
        #expect(PlanSummary.blockDetail(targetReps: 40, note: nil, mode: .rangeCounter) == "40 shots")
        #expect(PlanSummary.blockDetail(targetReps: 10, note: "", mode: .putting) == "10 putts")
    }

    @Test func lastDoneFormats() {
        #expect(PlanSummary.lastDone(nil, now: now, calendar: calendar, locale: locale) == "Not done yet")
        #expect(lastDone(daysAgo: 0.3) == "Last done today")
        #expect(lastDone(daysAgo: -1) == "Last done today")
        #expect(lastDone(daysAgo: 2) == "Last done Mon")
        #expect(lastDone(daysAgo: 6) == "Last done Thu")
        #expect(lastDone(daysAgo: 7) == "Last done Sep 9")
        #expect(lastDone(daysAgo: 372) == "Last done Sep 9, 2025")
    }
}
