// ShotDetector stays free of AVFoundation (spec §4): frames in, events out.
public struct ShotEvent: Sendable, Hashable {
    public var time: Double

    public init(time: Double) {
        self.time = time
    }
}
