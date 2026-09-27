import Foundation
import Testing

@testable import Reps

@MainActor
struct ClipPlaybackTests {
    private let frame = 1.0 / 60

    private func clip(club: String = "Gap wedge", tempo: Double? = 3.1, angle: CameraAngle = .faceOn) -> LibraryClip {
        LibraryClip(
            id: UUID(), timestamp: .now, clubName: club, tags: [], isFavourite: false, tempoRatio: tempo,
            clipFileName: "a.mov", sessionID: UUID(), sessionTitle: nil, sessionStartedAt: nil, angle: angle)
    }

    @Test func speedCyclesFullHalfQuarter() {
        #expect(PlaybackSpeed.full.next == .half)
        #expect(PlaybackSpeed.half.next == .quarter)
        #expect(PlaybackSpeed.quarter.next == .full)
        #expect(PlaybackSpeed.allCases.map(\.title) == ["1×", "½×", "¼×"])
        #expect(PlaybackSpeed.allCases.map(\.rawValue) == [1, 0.5, 0.25])
    }

    @Test func frameDurationFallsBackTo60() {
        #expect(ClipPlayback.frameDuration(nominalFrameRate: 30) == 1.0 / 30)
        #expect(ClipPlayback.frameDuration(nominalFrameRate: 60) == frame)
        #expect(ClipPlayback.frameDuration(nominalFrameRate: 0) == frame)
        #expect(ClipPlayback.frameDuration(nominalFrameRate: -1) == frame)
        #expect(ClipPlayback.frameDuration(nominalFrameRate: .nan) == frame)
    }

    @Test func stepLandsOnFrameMiddles() {
        #expect(ClipPlayback.stepped(from: 0, by: 1, frameDuration: frame, duration: 5) == 1.5 * frame)
        // 2.1 s is exactly frame 126 at 60 fps, despite floating point.
        #expect(ClipPlayback.stepped(from: 2.1, by: 1, frameDuration: frame, duration: 5) == 127.5 * frame)
        #expect(ClipPlayback.stepped(from: 2.1, by: -1, frameDuration: frame, duration: 5) == 125.5 * frame)
        // Stepping from a frame middle moves exactly one frame each time.
        let once = ClipPlayback.stepped(from: 0, by: 1, frameDuration: frame, duration: 5)
        #expect(ClipPlayback.stepped(from: once, by: 1, frameDuration: frame, duration: 5) == 2.5 * frame)
        #expect(ClipPlayback.stepped(from: once, by: -1, frameDuration: frame, duration: 5) == 0.5 * frame)
    }

    @Test func stepClampsToTheClip() {
        #expect(ClipPlayback.stepped(from: 0, by: -1, frameDuration: frame, duration: 5) == 0.5 * frame)
        // 5 s at 60 fps is frames 0...299; no phantom frame 300.
        #expect(ClipPlayback.stepped(from: 4.995, by: 1, frameDuration: frame, duration: 5) == 299.5 * frame)
        #expect(ClipPlayback.stepped(from: 9, by: 0, frameDuration: frame, duration: 5) == 299.5 * frame)
        // A partial last frame is still reachable but never past the end.
        #expect(ClipPlayback.stepped(from: 5, by: 1, frameDuration: frame, duration: 5.005) <= 5.005)
        #expect(ClipPlayback.stepped(from: 1, by: 1, frameDuration: frame, duration: 0) == 0)
        #expect(ClipPlayback.stepped(from: 1, by: 1, frameDuration: 0, duration: 5) == 0)
    }

    @Test func endDetection() {
        #expect(ClipPlayback.isAtEnd(5, frameDuration: frame, duration: 5))
        #expect(ClipPlayback.isAtEnd(299.5 * frame, frameDuration: frame, duration: 5))
        #expect(!ClipPlayback.isAtEnd(4.9, frameDuration: frame, duration: 5))
    }

    @Test func fractionAndSecondsClamp() {
        #expect(ClipPlayback.fraction(2.5, duration: 5) == 0.5)
        #expect(ClipPlayback.fraction(-1, duration: 5) == 0)
        #expect(ClipPlayback.fraction(9, duration: 5) == 1)
        #expect(ClipPlayback.fraction(1, duration: 0) == 0)
        #expect(ClipPlayback.seconds(atFraction: 0.5, duration: 5) == 2.5)
        #expect(ClipPlayback.seconds(atFraction: -0.2, duration: 5) == 0)
        #expect(ClipPlayback.seconds(atFraction: 1.3, duration: 5) == 5)
    }

    @Test func timeTitleHasThreeDecimals() {
        #expect(ClipPlayback.timeTitle(2.098) == "2.098")
        #expect(ClipPlayback.timeTitle(0) == "0.000")
        #expect(ClipPlayback.timeTitle(12.3456) == "12.346")
        #expect(ClipPlayback.timeTitle(-0.01) == "0.000")
    }

    @Test func filmstripTimesAreSliceMiddles() {
        #expect(ClipPlayback.filmstripTimes(count: 4, duration: 2) == [0.25, 0.75, 1.25, 1.75])
        #expect(ClipPlayback.filmstripTimes(count: 10, duration: 5).count == 10)
        #expect(ClipPlayback.filmstripTimes(count: 0, duration: 5).isEmpty)
        #expect(ClipPlayback.filmstripTimes(count: 10, duration: 0).isEmpty)
    }

    @Test func impactMarkOnlyInsideTheClip() {
        #expect(ClipPlayback.events(duration: 5) == [ClipEvent(kind: .impact, seconds: 3)])
        #expect(ClipPlayback.events(duration: 3).isEmpty)
        #expect(ClipPlayback.events(duration: 0).isEmpty)
        #expect(ClipPlayback.events(duration: 5, impactOffset: nil).isEmpty)
        #expect(ClipPlayback.events(duration: 5, impactOffset: 1.2) == [ClipEvent(kind: .impact, seconds: 1.2)])
    }

    @Test func releaseNearAMarkJumpsToIt() {
        let events = [ClipEvent(kind: .impact, seconds: 3)]
        // 200 pt track over 5 s: 0.1 s is 4 pt, 0.5 s is 20 pt.
        #expect(ClipPlayback.snapped(3.1, to: events, duration: 5, trackWidth: 200, tolerance: 12) == 3)
        #expect(ClipPlayback.snapped(2.85, to: events, duration: 5, trackWidth: 200, tolerance: 12) == 3)
        #expect(ClipPlayback.snapped(3.5, to: events, duration: 5, trackWidth: 200, tolerance: 12) == 3.5)
        #expect(ClipPlayback.snapped(3.1, to: [], duration: 5, trackWidth: 200, tolerance: 12) == 3.1)
        #expect(ClipPlayback.snapped(3.1, to: events, duration: 0, trackWidth: 200, tolerance: 12) == 3.1)
    }

    @Test func labelPill() {
        #expect(ClipPlayback.label(clip()) == "Gap wedge · face-on · tempo 3.1 : 1")
        #expect(ClipPlayback.label(clip(tempo: nil)) == "Gap wedge · face-on")
        #expect(ClipPlayback.label(clip(club: "Putter", tempo: nil, angle: .none)) == "Putter")
        #expect(
            ClipPlayback.label(clip(tempo: 2.96, angle: .downTheLine)) == "Gap wedge · down-the-line · tempo 3.0 : 1")
    }
}
