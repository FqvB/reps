import ShotDetector

// Test-only detector: fires on the first sampled frame at or after each positive label.
// Proves decode → detect → match → report end to end without a real detector.
struct LabelOracle: ShotDetecting {
    private var pending: [Double]

    init(video: EvalVideo, profile: ScoringProfile) {
        pending = video.labels.filter { profile.role(of: $0.kind) == .positive }.map(\.seconds).sorted()
    }

    mutating func process(_ frame: VideoFrame) -> [ShotEvent] {
        var events: [ShotEvent] = []
        while let next = pending.first, frame.time + 0.001 >= next {
            pending.removeFirst()
            events.append(ShotEvent(time: frame.time))
        }
        return events
    }
}
