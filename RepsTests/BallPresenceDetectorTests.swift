import CoreGraphics
import CoreVideo
import ShotDetector
import Testing

private typealias Disc = (x: Int, y: Int, r: Int, value: UInt8)

private func luma(
    _ width: Int = 200, _ height: Int = 160, background: UInt8 = 60, discs: [Disc] = []
) -> LumaImage {
    var image = LumaImage(width: width, height: height, fill: background)
    for disc in discs {
        for py in max(0, disc.y - disc.r)...min(height - 1, disc.y + disc.r) {
            for px in max(0, disc.x - disc.r)...min(width - 1, disc.x + disc.r)
            where (px - disc.x) * (px - disc.x) + (py - disc.y) * (py - disc.y) <= disc.r * disc.r {
                image[px, py] = disc.value
            }
        }
    }
    return image
}

private let discA: Disc = (100, 80, 14, 220)

// Feeds consecutive frames at 15 fps and returns the frames that returned events.
private func run(
    _ detector: inout BallPresenceDetector, _ frames: Range<Int>, width: Int = 200, height: Int = 160,
    discs: (Int) -> [Disc]
) -> [(frame: Int, events: [ShotEvent])] {
    var out: [(frame: Int, events: [ShotEvent])] = []
    for i in frames {
        let events = detector.process(luma(width, height, discs: discs(i)), time: Double(i) / 15)
        if !events.isEmpty { out.append((i, events)) }
    }
    return out
}

private func near(_ ball: BallCandidate?, _ disc: Disc) -> Bool {
    guard let ball else { return false }
    return abs(ball.x - Double(disc.x)) <= 1 && abs(ball.y - Double(disc.y)) <= 1
}

struct BallPresenceDetectorTests {
    @Test func locksAfterOneSecondStill() {
        var detector = BallPresenceDetector()
        #expect(run(&detector, 0..<15) { _ in [discA] }.isEmpty)
        #expect(detector.ball == nil)
        #expect(run(&detector, 15..<16) { _ in [discA] }.isEmpty)
        #expect(near(detector.ball, discA))
    }

    @Test func emitsOnceWhenGoneForHoldTime() {
        var detector = BallPresenceDetector()
        let events = run(&detector, 0..<50) { $0 < 30 ? [discA] : [] }
        #expect(events.count == 1)
        #expect(events.first?.frame == 35)
        #expect(abs((events.first?.events.first?.time ?? 0) - 30.0 / 15) < 1e-9)
        #expect(detector.ball == nil)
    }

    @Test func shortDropoutIsNotAStroke() {
        var detector = BallPresenceDetector()
        let events = run(&detector, 0..<41) { (30...33).contains($0) ? [] : [discA] }
        #expect(events.isEmpty)
        #expect(near(detector.ball, discA))
    }

    @Test func relocksANewBallAndCountsAgain() {
        let discB: Disc = (60, 100, 12, 220)
        var detector = BallPresenceDetector()
        var events = run(&detector, 0..<60) { i in i < 30 ? [discA] : i >= 45 ? [discB] : [] }
        #expect(detector.ball == nil)
        events += run(&detector, 60..<61) { _ in [discB] }
        #expect(near(detector.ball, discB))
        events += run(&detector, 61..<90) { $0 < 75 ? [discB] : [] }
        #expect(events.flatMap(\.events).map(\.time) == [30.0 / 15, 75.0 / 15])
    }

    @Test func staticClutterNeverLocksLater() {
        let clutter: Disc = (40, 40, 10, 220)
        let discD: Disc = (150, 120, 12, 220)
        var detector = BallPresenceDetector()
        _ = run(&detector, 0..<16) { _ in [discA, clutter] }
        #expect(near(detector.ball, discA))
        let events = run(&detector, 16..<60) { $0 < 30 ? [discA, clutter] : [clutter] }
        #expect(events.count == 1)
        #expect(detector.ball == nil)
        _ = run(&detector, 60..<76) { _ in [clutter, discD] }
        #expect(near(detector.ball, discD))
    }

    @Test func oldEnoughCandidateAtLockBecomesClutter() {
        let discB: Disc = (60, 100, 12, 220)
        var detector = BallPresenceDetector()
        _ = run(&detector, 0..<16) { i in i >= 6 ? [discA, discB] : [discA] }
        #expect(near(detector.ball, discA))
        let events = run(&detector, 16..<76) { i in i < 30 ? [discA, discB] : [discB] }
        #expect(events.count == 1)
        #expect(detector.ball == nil)
    }

    @Test func youngCandidateAtLockIsNotClutter() {
        let discB: Disc = (60, 100, 12, 220)
        var detector = BallPresenceDetector()
        _ = run(&detector, 0..<16) { i in i >= 10 ? [discA, discB] : [discA] }
        let events = run(&detector, 16..<51) { i in i < 30 ? [discA, discB] : [discB] }
        #expect(events.map(\.frame) == [35])
        #expect(detector.ball == nil)
        _ = run(&detector, 51..<52) { _ in [discB] }
        #expect(near(detector.ball, discB))
    }

    @Test func movingDiscDoesNotLock() {
        var detector = BallPresenceDetector()
        let events = run(&detector, 0..<30, width: 240) { [(30 + 6 * $0, 80, 14, 220)] }
        #expect(events.isEmpty)
        #expect(detector.ball == nil)
    }

    @Test func sizeChangeResets() {
        var detector = BallPresenceDetector()
        var events = run(&detector, 0..<21) { _ in [discA] }
        #expect(detector.ball != nil)
        events += run(&detector, 21..<22, width: 160, height: 200) { _ in [(80, 100, 14, 220)] }
        #expect(detector.ball == nil)
        events += run(&detector, 22..<37, width: 160, height: 200) { _ in [(80, 100, 14, 220)] }
        #expect(detector.ball != nil)
        #expect(events.isEmpty)
    }

    @Test func longGapSearchesAgainWithoutEvent() {
        var detector = BallPresenceDetector()
        var events = run(&detector, 0..<21) { _ in [discA] }
        #expect(detector.ball != nil)
        let resume = 20.0 / 15 + 1.5
        for i in 0..<30 {
            events += detector.process(luma(), time: resume + Double(i) / 15).isEmpty ? [] : [(i, [])]
        }
        #expect(events.isEmpty)
        #expect(detector.ball == nil)
    }

    @Test func searchRegionLimitsTheLocator() {
        let disc: Disc = (150, 80, 14, 220)
        var limited = BallPresenceDetector()
        limited.searchRegion = CGRect(x: 0, y: 0, width: 0.5, height: 1)
        _ = run(&limited, 0..<30) { _ in [disc] }
        #expect(limited.ball == nil)
        var whole = BallPresenceDetector()
        _ = run(&whole, 0..<16) { _ in [disc] }
        #expect(near(whole.ball, disc))
    }

    @Test func pixelBufferFramesWork() throws {
        var detector = BallPresenceDetector()
        for i in 0..<20 {
            let image = luma(discs: [discA])
            var made: CVPixelBuffer?
            CVPixelBufferCreate(
                nil, image.width, image.height, DetectorInput.pixelFormat,
                [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary, &made)
            let buffer = try #require(made)
            CVPixelBufferLockBaseAddress(buffer, [])
            let base = try #require(CVPixelBufferGetBaseAddressOfPlane(buffer, 0)).assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
            for y in 0..<image.height { for x in 0..<image.width { base[y * stride + x] = image[x, y] } }
            let chroma = try #require(CVPixelBufferGetBaseAddressOfPlane(buffer, 1)).assumingMemoryBound(to: UInt8.self)
            for index in 0..<(CVPixelBufferGetBytesPerRowOfPlane(buffer, 1) * image.height / 2) { chroma[index] = 128 }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            _ = detector.process(VideoFrame(pixelBuffer: buffer, time: Double(i) / 15))
        }
        #expect(near(detector.ball, discA))
    }
}
