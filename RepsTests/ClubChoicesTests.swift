import Testing

@testable import Reps

struct ClubChoicesTests {
    @Test func keepsBagOrderAndDropsDuplicatesAndBlanks() {
        #expect(ClubChoices.names(bag: ["Driver", "7 iron", "Driver", " "], current: "") == ["Driver", "7 iron"])
    }

    @Test func appendsCurrentClubMissingFromBag() {
        #expect(ClubChoices.names(bag: ["Driver"], current: "Chipper") == ["Driver", "Chipper"])
        #expect(ClubChoices.names(bag: ["Driver"], current: "Driver") == ["Driver"])
        #expect(ClubChoices.names(bag: [], current: "") == [])
    }
}
