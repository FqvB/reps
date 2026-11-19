import CoreGraphics

// Finds the ball, locks onto it, and fires one shot when it's gone for absentHold (ADR 0017).
// ADR 0008 drops `occluded`; a lock implies the ball was present for lockDelay, which is the re-arm.
// Orientation is ignored: round edges and patch matching don't care, all coordinates are buffer pixels.
public struct BallPresenceDetector: ShotDetecting, Sendable {
    public struct Config: Sendable, Equatable {
        public var locator = BallLocator.Config()
        public var lockDelay = 1.0
        public var stillTolerance = 0.3
        public var radiusTolerance = 0.3
        public var trackMemory = 0.5
        public var clutterAge = 0.5
        public var patchScale = 1.0
        public var maxShift = 0.25
        public var presentThreshold = 0.75
        public var absentHold = 0.3
        public var maxFrameGap = 1.0
        public init() {}
    }

    private struct Track {
        var anchorX, anchorY, x, y, radius, coverage, firstSeen, lastSeen: Double
    }

    public let config: Config
    public var searchRegion = CGRect(x: 0, y: 0, width: 1, height: 1)
    public private(set) var ball: BallCandidate?
    public private(set) var similarity: Double?

    private var tracks: [Track] = []
    private var ignored: [BallCandidate] = []
    private var matcher: PatchMatcher?
    private var absentSince: Double?
    private var lastTime: Double?
    private var frameWidth = 0
    private var frameHeight = 0

    public init(config: Config = Config()) {
        self.config = config
    }

    public mutating func process(_ frame: VideoFrame) -> [ShotEvent] {
        guard let image = LumaImage(pixelBuffer: frame.pixelBuffer) else { return [] }
        return process(image, time: frame.time)
    }

    public mutating func process(_ image: LumaImage, time: Double) -> [ShotEvent] {
        if frameWidth != 0, (frameWidth, frameHeight) != (image.width, image.height) {
            ignored = []
            searchAgain()
            lastTime = nil
        }
        (frameWidth, frameHeight) = (image.width, image.height)
        if let lastTime, time - lastTime > config.maxFrameGap { searchAgain() }
        lastTime = time

        if let matcher, let ball {
            let shift = Int((config.maxShift * ball.radius).rounded())
            let score = matcher.similarity(in: image, maxShift: shift)
            similarity = score
            if score >= config.presentThreshold {
                absentSince = nil
                return []
            }
            let exit = absentSince ?? time
            absentSince = exit
            guard time - exit >= config.absentHold - 0.001 else { return [] }
            searchAgain()
            return [ShotEvent(time: exit)]
        }
        search(image, time: time)
        return []
    }

    private mutating func searchAgain() {
        tracks = []
        matcher = nil
        ball = nil
        similarity = nil
        absentSince = nil
    }

    private mutating func search(_ image: LumaImage, time: Double) {
        let (width, height) = (image.width, image.height)
        func clamp(_ value: Int, _ limit: Int) -> Int { min(max(value, 0), limit) }
        let region = searchRegion.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !region.isNull, !region.isEmpty else { return }
        let x0 = clamp(Int((region.minX * Double(width)).rounded(.down)), width)
        let x1 = clamp(Int((region.maxX * Double(width)).rounded(.up)), width)
        let y0 = clamp(Int((region.minY * Double(height)).rounded(.down)), height)
        let y1 = clamp(Int((region.maxY * Double(height)).rounded(.up)), height)
        guard x1 - x0 >= 3, y1 - y0 >= 3 else { return }

        var found = BallLocator(config: config.locator)
            .candidates(in: image.cropped(x: x0, y: y0, width: x1 - x0, height: y1 - y0))
        for index in found.indices {
            found[index].x += Double(x0)
            found[index].y += Double(y0)
        }
        found.removeAll { candidate in
            ignored.contains { spot in
                hypot(candidate.x - spot.x, candidate.y - spot.y) <= max(2, config.stillTolerance * spot.radius)
            }
        }

        var matched = Set<Int>()
        for candidate in found {
            let index = tracks.indices.first { index in
                let track = tracks[index]
                return !matched.contains(index)
                    && hypot(candidate.x - track.anchorX, candidate.y - track.anchorY)
                        <= max(2, config.stillTolerance * track.radius)
                    && abs(candidate.radius - track.radius) <= config.radiusTolerance * track.radius
            }
            if let index {
                matched.insert(index)
                tracks[index].x = candidate.x
                tracks[index].y = candidate.y
                tracks[index].radius = candidate.radius
                tracks[index].coverage = candidate.coverage
                tracks[index].lastSeen = time
            } else {
                tracks.append(
                    Track(
                        anchorX: candidate.x, anchorY: candidate.y, x: candidate.x, y: candidate.y,
                        radius: candidate.radius, coverage: candidate.coverage, firstSeen: time, lastSeen: time))
            }
        }
        tracks.removeAll { time - $0.lastSeen > config.trackMemory }

        var best: (index: Int, matcher: PatchMatcher)?
        for index in tracks.indices {
            let track = tracks[index]
            guard track.lastSeen == time, time - track.firstSeen >= config.lockDelay - 0.001,
                let patch = PatchMatcher(
                    reference: image, centerX: Int(track.x.rounded()), centerY: Int(track.y.rounded()),
                    halfSize: Int((config.patchScale * track.radius).rounded()))
            else { continue }
            if let current = best {
                let other = tracks[current.index]
                let wins =
                    (track.firstSeen, track.coverage, track.radius)
                    > (other.firstSeen, other.coverage, other.radius)
                guard wins else { continue }
            }
            best = (index, patch)
        }
        guard let best else { return }

        let locked = tracks[best.index]
        for (index, track) in tracks.enumerated()
        where index != best.index && time - track.firstSeen >= config.clutterAge - 0.001
            && hypot(track.x - locked.x, track.y - locked.y) > locked.radius
        {
            ignored.append(
                BallCandidate(x: track.x, y: track.y, radius: track.radius, coverage: track.coverage))
        }
        matcher = best.matcher
        ball = BallCandidate(x: locked.x, y: locked.y, radius: locked.radius, coverage: locked.coverage)
        similarity = 1
        absentSince = nil
        tracks = []
    }
}
