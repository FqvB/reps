import Foundation

@testable import Reps

// Each read is one second later, so shots never tie on timestamp.
@MainActor
final class TestClock {
    private(set) var date = Date(timeIntervalSince1970: 1_790_000_000)

    func next() -> Date {
        date = date.addingTimeInterval(1)
        return date
    }
}

@MainActor
final class ClipSpy: ClipFileRemoving {
    private(set) var removedClips: [String] = []
    private(set) var removedSessions: [UUID] = []

    func removeClip(fileName: String, sessionID: UUID) {
        removedClips.append("\(sessionID.uuidString)/\(fileName)")
    }

    func removeClips(sessionID: UUID) {
        removedSessions.append(sessionID)
    }
}

@MainActor
final class EventLog {
    var events: [SessionEvent] = []
}
