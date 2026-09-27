import Testing

struct EvalMetricsTests {
    private func video(positives: Int, truePositives: Int, hardFP: Int = 0, otherFP: Int = 0) -> VideoScore {
        var s = VideoScore()
        s.positives = positives
        s.truePositives = truePositives
        s.hardNegativeFalsePositives = hardFP
        s.otherFalsePositives = otherFP
        s.detections = truePositives + hardFP + otherFP
        return s
    }

    @Test func sumsOverVideosBeforeDividing() {
        let m = EvalMetrics([video(positives: 1, truePositives: 1), video(positives: 9, truePositives: 3, otherFP: 1)])
        #expect(m.videos == 2)
        #expect(m.recall == 0.4)
        #expect(m.precision == 0.8)
        #expect(m.falseNegatives == 6)
    }

    @Test func undefinedRatesAreNil() {
        let empty = EvalMetrics([video(positives: 0, truePositives: 0)])
        #expect(empty.precision == nil)
        #expect(empty.recall == nil)
        #expect(empty.falsePer50 == nil)
        #expect(empty.meanLatency == nil)
        #expect(empty.maxLatency == nil)
    }

    @Test func falsePositivesPerFiftyShots() {
        let m = EvalMetrics([video(positives: 100, truePositives: 100, hardFP: 1, otherFP: 1)])
        #expect(m.falsePer50 == 1)
        #expect(m.falsePositives == 2)
    }

    @Test func countErrorIsSummedPerVideoMagnitude() {
        // +1 on one video and −1 on another must not cancel out.
        let m = EvalMetrics([video(positives: 2, truePositives: 2, otherFP: 1), video(positives: 2, truePositives: 1)])
        #expect(m.absCountError == 2)
    }

    @Test func latencyMeanAndMax() {
        var a = VideoScore()
        a.latencies = [0.2, 0.4]
        a.timingErrors = [-0.1, 0.1]
        var b = VideoScore()
        b.latencies = [0.9]
        b.timingErrors = [0.4]
        let m = EvalMetrics([a, b])
        #expect(abs(m.meanLatency! - 0.5) < 1e-9)
        #expect(m.maxLatency == 0.9)
        #expect(abs(m.meanAbsTimingError! - 0.2) < 1e-9)
    }

    @Test func kindCountsMerge() {
        var a = VideoScore()
        a.labelsByKind = [.swing: 1, .motion: 2]
        a.firedByKind = [.swing: 1]
        var b = VideoScore()
        b.labelsByKind = [.swing: 3]
        b.firedByKind = [.swing: 2]
        let m = EvalMetrics([a, b])
        #expect(m.labelsByKind == [.swing: 4, .motion: 2])
        #expect(m.firedByKind == [.swing: 3])
    }
}
