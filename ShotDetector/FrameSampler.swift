// Picks frames by timestamp at a fixed rate, so dropped or uneven frames don't change the rate (spec §5.6, ADR 0016).
// Shared by the camera pipeline and the eval decoder so both sample alike.
public struct FrameSampler {
    // Seconds between taken frames; #28 raises it under thermal load.
    public var interval: Double
    private var nextDue = -Double.infinity

    public init(frameRate: Double = DetectorInput.frameRate) {
        interval = 1 / frameRate
    }

    public mutating func take(_ time: Double) -> Bool {
        // 1 ms slack so 29.97 fps footage still lands on every 2nd frame.
        guard time + 0.001 >= nextDue else { return false }
        nextDue = nextDue.isFinite ? max(nextDue + interval, time + interval / 2) : time + interval
        return true
    }
}
