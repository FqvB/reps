import Foundation
import Testing

@testable import Reps

@MainActor
struct LibraryDisplayTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let locale = Locale(identifier: "en_US")
    // Wed 16 Sep 2026, 10:00 UTC
    private let now = Date(timeIntervalSince1970: 1_789_552_800)
    private let wedgeDay = UUID()
    private let ironsDay = UUID()

    private func clip(
        _ club: String = "GW", tags: [String] = [], favourite: Bool = false, hoursAgo: Double = 0,
        angle: CameraAngle = .faceOn, session: UUID? = nil, title: String? = "Wedge day", tempo: Double? = nil,
        id: UUID = UUID()
    ) -> LibraryClip {
        LibraryClip(
            id: id, timestamp: now.addingTimeInterval(-hoursAgo * 3_600), clubName: club, tags: tags,
            isFavourite: favourite, tempoRatio: tempo, clipFileName: "\(id.uuidString).mov",
            sessionID: session ?? wedgeDay, sessionTitle: title,
            sessionStartedAt: now.addingTimeInterval(-hoursAgo * 3_600),
            angle: angle)
    }

    private func visible(_ clips: [LibraryClip], _ filter: LibraryFilter, hidden: Set<UUID> = []) -> [LibraryClip] {
        LibraryDisplay.visible(clips, filter: filter, hidden: hidden, calendar: calendar, locale: locale)
    }

    @Test func emptyFilterKeepsEverythingNewestFirst() {
        let old = clip(hoursAgo: 5)
        let new = clip(hoursAgo: 1)
        let mid = clip(hoursAgo: 3)
        #expect(visible([old, new, mid], LibraryFilter()).map(\.id) == [new.id, mid.id, old.id])
    }

    @Test func sameTimestampSortsById() {
        let a = clip(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let b = clip(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        #expect(visible([b, a], LibraryFilter()).map(\.id) == [a.id, b.id])
    }

    @Test func tagsAreAnded() {
        let both = clip(tags: ["fade", "low"])
        let fadeOnly = clip(tags: ["fade"])
        let fader = clip(tags: ["fader", "low"])
        var filter = LibraryFilter()
        filter.tags = ["fade"]
        #expect(Set(visible([both, fadeOnly, fader], filter).map(\.id)) == [both.id, fadeOnly.id])
        filter.tags = ["fade", "low"]
        #expect(visible([both, fadeOnly, fader], filter).map(\.id) == [both.id])
    }

    @Test func everyChipFilterIsAnded() {
        let match = clip("GW", tags: ["fade"], favourite: true, angle: .faceOn, session: wedgeDay)
        let wrongClub = clip("PW", tags: ["fade"], favourite: true)
        let wrongAngle = clip(tags: ["fade"], favourite: true, angle: .downTheLine)
        let notFavourite = clip(tags: ["fade"])
        let otherSession = clip(tags: ["fade"], favourite: true, session: ironsDay)
        let lastMonth = clip(tags: ["fade"], favourite: true, hoursAgo: 24 * 20)
        var filter = LibraryFilter()
        filter.club = "GW"
        filter.angle = .faceOn
        filter.month = LibraryMonth(year: 2026, month: 9)
        filter.sessionID = wedgeDay
        filter.tags = ["fade"]
        filter.favouritesOnly = true
        #expect(filter.hasChipFilters)
        let all = [match, wrongClub, wrongAngle, notFavourite, otherSession, lastMonth]
        #expect(visible(all, filter).map(\.id) == [match.id])
    }

    @Test func searchWordsMustAllMatchSomeField() {
        let gw = clip("Gap wedge", tags: ["fade"], title: "Wedge day")
        let pw = clip("Pitching wedge", tags: ["draw"], title: "Irons")
        var filter = LibraryFilter()
        filter.searchText = "wedge"
        #expect(visible([gw, pw], filter).count == 2)
        filter.searchText = "WEDGE fade"
        #expect(visible([gw, pw], filter).map(\.id) == [gw.id])
        filter.searchText = "irons draw"
        #expect(visible([gw, pw], filter).map(\.id) == [pw.id])
        filter.searchText = "sept wednesday face-on"
        #expect(visible([gw, pw], filter).count == 2)
        filter.searchText = "october"
        #expect(visible([gw, pw], filter).isEmpty)
        #expect(!filter.hasChipFilters)
    }

    @Test func hiddenClipsAreLeftOut() {
        let a = clip()
        let b = clip(hoursAgo: 1)
        #expect(visible([a, b], LibraryFilter(), hidden: [a.id]).map(\.id) == [b.id])
    }

    @Test func clubOptionsFollowTheBagThenAlphabetical() {
        let clips = [clip("PW"), clip("Old wedge"), clip("7 iron"), clip("PW"), clip("A club")]
        #expect(
            LibraryDisplay.clubOptions(clips, bag: ["Driver", "7 iron", "PW"]) == [
                "7 iron", "PW", "A club", "Old wedge",
            ])
    }

    @Test func tagOptionsByUseThenName() {
        let clips = [clip(tags: ["low", "fade"]), clip(tags: ["fade"]), clip(tags: ["draw"]), clip(tags: ["low"])]
        #expect(LibraryDisplay.tagOptions(clips) == ["fade", "low", "draw"])
    }

    @Test func monthAndSessionOptionsNewestFirst() {
        let clips = [
            clip(hoursAgo: 24 * 20, session: ironsDay, title: "Irons"), clip(hoursAgo: 1), clip(hoursAgo: 2),
        ]
        #expect(
            LibraryDisplay.monthOptions(clips, calendar: calendar) == [
                LibraryMonth(year: 2026, month: 9), LibraryMonth(year: 2026, month: 8),
            ])
        let sessions = LibraryDisplay.sessionOptions(clips)
        #expect(sessions.map(\.id) == [wedgeDay, ironsDay])
        #expect(sessions.map(\.title) == ["Wedge day", "Irons"])
        #expect(LibraryDisplay.sessionTitle(sessions[1], calendar: calendar, locale: locale) == "Irons · Aug 27")
    }

    @Test func freeSessionOptionIsNamed() {
        #expect(LibraryDisplay.sessionOptions([clip(title: nil)]).map(\.title) == ["Free session"])
    }

    @Test func monthTitleShowsYearOnlyWhenNotThisYear() {
        #expect(
            LibraryDisplay.monthTitle(LibraryMonth(year: 2026, month: 9), now: now, calendar: calendar, locale: locale)
                == "September")
        #expect(
            LibraryDisplay.monthTitle(LibraryMonth(year: 2025, month: 12), now: now, calendar: calendar, locale: locale)
                == "December 2025")
    }

    @Test func tileCopy() {
        #expect(LibraryDisplay.tileTitle(clip("Gap wedge")) == "Gap wedge · face-on")
        #expect(LibraryDisplay.tileTitle(clip("Putter", angle: .none)) == "Putter")
        #expect(LibraryDisplay.tempo(3.06) == "3.1")
        #expect(LibraryDisplay.tempo(nil) == nil)
        #expect(LibraryDisplay.tagLine(["fade", "low"]) == "fade, low")
        #expect(LibraryDisplay.tagLine([]) == nil)
        #expect(LibraryDisplay.countTitle(1) == "1 clip")
        #expect(LibraryDisplay.countTitle(62) == "62 clips")
        #expect(LibraryDisplay.tagChipTitle([]) == "Tag")
        #expect(LibraryDisplay.tagChipTitle(["low", "fade"]) == "fade +1")
        #expect(LibraryDisplay.undoMessage("Deleted", count: 3) == "Deleted 3 clips")
    }

    @Test func tileDates() {
        func date(_ hoursAgo: Double) -> String {
            LibraryDisplay.tileDate(
                now.addingTimeInterval(-hoursAgo * 3_600), now: now, calendar: calendar, locale: locale)
        }
        #expect(date(2) == "Today 8:00\u{202F}AM")
        #expect(date(40) == "Mon 6:00\u{202F}PM")
        #expect(date(24 * 7) == "Sep 9")
        #expect(date(24 * 300) == "Nov 20, 2025")
    }

    @Test func favouriteTargetFlipsOnlyWhenAllAreFavourites() {
        #expect(LibraryDisplay.favouriteTarget([clip(favourite: true), clip()]))
        #expect(!LibraryDisplay.favouriteTarget([clip(favourite: true), clip(favourite: true)]))
    }
}
