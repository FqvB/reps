import Foundation
import Testing

@testable import Reps

@MainActor
struct SessionLogDisplayTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let locale = Locale(identifier: "en_US")
    // Wednesday 16 September 2026, 10:00 UTC
    private let wednesday = Date(timeIntervalSince1970: 1_789_552_800)

    private func block(
        _ order: Int, _ club: String, counted: Int, adjust: Int = 0, target: Int?, note: String? = nil,
        tags: [String] = [], clips: Int = 0
    ) -> LogBlock {
        LogBlock(
            order: order, clubName: club, note: note, tags: tags, counted: counted, manualAdjust: adjust,
            target: target, clipCount: clips)
    }

    private func entry(
        _ planName: String?, mode: PracticeMode = .rangeCounter, angle: CameraAngle = .faceOn, start: Date,
        minutes: Double? = 48, blocks: [LogBlock], id: UUID = UUID()
    ) -> LogEntry {
        LogEntry(
            id: id, planName: planName, mode: mode, cameraAngle: angle, startedAt: start,
            endedAt: minutes.map { start.addingTimeInterval($0 * 60) }, blocks: blocks)
    }

    // No block over target, so the numbers hold with or without the Q22 cap (#11).
    private var wedgeDay: LogEntry {
        entry(
            "Wedge day", mode: .rangeCounterWithClips, start: wednesday,
            blocks: [
                block(1, "GW", counted: 20, adjust: 2, target: 30, clips: 20),
                block(0, "PW", counted: 40, target: 40, clips: 40),
                block(2, "SW", counted: 0, target: 30),
            ])
    }

    @Test func sectionsGroupByMonthNewestFirst() {
        let august = wednesday.addingTimeInterval(-30 * 86_400)
        let lastYear = wednesday.addingTimeInterval(-365 * 86_400)
        let a = entry("A", start: wednesday.addingTimeInterval(-86_400), blocks: [])
        let b = entry("B", start: wednesday, blocks: [])
        let c = entry("C", start: august, blocks: [])
        let d = entry("D", start: lastYear, blocks: [])
        let sections = SessionLogDisplay.sections([c, a, d, b], calendar: calendar, locale: locale)
        #expect(sections.map(\.title) == ["September 2026", "August 2026", "September 2025"])
        #expect(sections.map { $0.rows.map(\.title) } == [["B", "A"], ["C"], ["D"]])
        #expect(SessionLogDisplay.sections([], calendar: calendar, locale: locale).isEmpty)
    }

    @Test func sameStartTimeSortsStably() {
        let low = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let high = UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001")!
        let first = entry("Low", start: wednesday, blocks: [], id: low)
        let second = entry("High", start: wednesday, blocks: [], id: high)
        let rows = SessionLogDisplay.sections([first, second], calendar: calendar, locale: locale)[0].rows
        #expect(rows.map(\.title) == ["High", "Low"])
    }

    @Test func plannedRow() {
        let row = SessionLogDisplay.row(wedgeDay, calendar: calendar, locale: locale)
        #expect(row.title == "Wedge day")
        #expect(row.subtitle == "Wed, Sep 16 · 10:00\u{202F}AM · 48 min")
        #expect(row.detail == "62 shots · 3 blocks · 60 clips")
        #expect(row.percent == "62%")
        #expect(!row.isComplete)
    }

    @Test func completeRowShows100AndNoClips() {
        let done = entry(
            "Irons", start: wednesday, minutes: 72,
            blocks: [
                block(0, "7 iron", counted: 30, target: 30), block(1, "6 iron", counted: 29, adjust: 1, target: 30),
            ])
        let row = SessionLogDisplay.row(done, calendar: calendar, locale: locale)
        #expect(row.percent == "100%")
        #expect(row.isComplete)
        #expect(row.detail == "60 shots · 2 blocks")
        #expect(row.subtitle.hasSuffix(" · 1 h 12 min"))
    }

    @Test func percentNeverShows100BeforeTarget() {
        let almost = entry("Long", start: wednesday, blocks: [block(0, "PW", counted: 199, target: 200)])
        #expect(SessionLogDisplay.row(almost, calendar: calendar, locale: locale).percent == "99%")
        #expect(SessionLogDisplay.percent(0.996, isComplete: false) == "99%")
        #expect(SessionLogDisplay.percent(1.5, isComplete: true) == "150%")
        #expect(SessionLogDisplay.percent(1.0 / 3.0, isComplete: false) == "33%")
    }

    @Test func freeRowListsClubsAndHidesUnusedBlocks() {
        let free = entry(
            nil, mode: .putting, angle: .none, start: wednesday, minutes: nil,
            blocks: [
                block(0, "Putter", counted: 12, target: nil),
                block(1, "7 iron", counted: 0, target: nil),
                block(2, "Putter", counted: 0, adjust: 3, target: nil, tags: ["lag"]),
            ])
        let row = SessionLogDisplay.row(free, calendar: calendar, locale: locale)
        #expect(row.title == "Free session")
        #expect(row.subtitle == "Wed, Sep 16 · 10:00\u{202F}AM")
        #expect(row.detail == "15 putts · Putter")
        #expect(row.percent == nil)
        #expect(!row.isComplete)
    }

    @Test func plannedDetail() {
        let detail = SessionLogDisplay.detail(wedgeDay, calendar: calendar, locale: locale)
        #expect(detail.dateLine == "Wed, Sep 16, 2026 · 10:00\u{202F}AM")
        #expect(detail.modeLine == "Range + clips · face-on")
        #expect(detail.headline == "62%")
        #expect(detail.caption == "62 of 100 shots")
        #expect(
            detail.rows == [
                LogBlockRow(id: 0, title: "PW", detail: "40 / 40", percent: "100%", isOverTarget: false),
                LogBlockRow(id: 1, title: "GW", detail: "22 / 30", percent: "73%", isOverTarget: false),
                LogBlockRow(id: 2, title: "SW", detail: "0 / 30", percent: "0%", isOverTarget: false),
            ])
        #expect(detail.stats.map(\.value) == ["48 min", "60", "2"])
        #expect(detail.stats.map(\.label) == ["duration", "clips saved", "manual fixes"])
    }

    @Test func overTargetBlockRow() {
        let row = SessionLogDisplay.blockRow(
            block(0, "GW", counted: 45, target: 30), mode: .rangeCounter, isFree: false)
        #expect(row.detail == "45 / 30")
        #expect(row.percent == "150%")
        #expect(row.isOverTarget)
    }

    @Test func puttingDetailUsesNotes() {
        let putting = entry(
            "Putting 3-6-9", mode: .putting, angle: .none, start: wednesday,
            blocks: [
                block(0, "Putter", counted: 30, target: 30, note: "3 ft"),
                block(1, "Putter", counted: 10, adjust: -1, target: 30, note: " "),
            ])
        let detail = SessionLogDisplay.detail(putting, calendar: calendar, locale: locale)
        #expect(detail.modeLine == "Putting counter")
        #expect(detail.caption == "39 of 60 putts")
        #expect(detail.rows.map(\.title) == ["3 ft", "Putter"])
        #expect(detail.stats[2].value == "1")
    }

    @Test func freeDetail() {
        let free = entry(
            nil, start: wednesday, minutes: 0.5,
            blocks: [
                block(0, "7 iron", counted: 0, adjust: 20, target: nil),
                block(1, "7 iron", counted: 0, adjust: 5, target: nil, tags: ["fade", "low"]),
                block(2, "PW", counted: 0, target: nil),
            ])
        let detail = SessionLogDisplay.detail(free, calendar: calendar, locale: locale)
        #expect(detail.headline == "25")
        #expect(detail.caption == "shots")
        #expect(detail.rows.map(\.title) == ["7 iron", "7 iron · fade, low"])
        #expect(detail.rows.map(\.detail) == ["20", "5"])
        #expect(detail.rows.allSatisfy { $0.percent == nil })
        #expect(detail.stats.map(\.value) == ["under 1 min", "0", "25"])
    }

    @Test func durationFormats() {
        let start = wednesday
        func after(_ minutes: Double) -> String? {
            SessionLogDisplay.duration(from: start, to: start.addingTimeInterval(minutes * 60))
        }
        #expect(SessionLogDisplay.duration(from: start, to: nil) == nil)
        #expect(after(0.9) == "under 1 min")
        #expect(after(-5) == "under 1 min")
        #expect(after(48.7) == "48 min")
        #expect(after(60) == "1 h")
        #expect(after(125) == "2 h 5 min")
    }
}
