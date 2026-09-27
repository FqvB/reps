import Testing

struct EvalRunnerTests {
    @Test func labelTimeInRangeUsesFrameTime() {
        let labels = [EvalLabel(frame: 1, seconds: 99, kind: .swing)]
        let times = EvalRunner.labelTimes(labels, frameTimes: [0.0, 0.5, 1.0])
        #expect(times == [0.5])
    }

    @Test func labelTimePastEndFallsBackToCSVSeconds() {
        let labels = [EvalLabel(frame: 5, seconds: 3.2, kind: .swing)]
        let times = EvalRunner.labelTimes(labels, frameTimes: [0.0, 0.5, 1.0])
        #expect(times == [3.2])
    }

    @Test func labelTimesMapsEachLabelIndependently() {
        let labels = [
            EvalLabel(frame: 0, seconds: 10, kind: .swing),
            EvalLabel(frame: 9, seconds: 10, kind: .motion),
        ]
        let times = EvalRunner.labelTimes(labels, frameTimes: [0.0, 0.5, 1.0])
        #expect(times == [0.0, 10])
    }

    @Test func strictlyIncreasingFrameTimesPass() {
        #expect(EvalRunner.isStrictlyIncreasing([0.0, 0.5, 1.0]))
        #expect(EvalRunner.isStrictlyIncreasing([]))
        #expect(EvalRunner.isStrictlyIncreasing([0.0]))
    }

    @Test func nonIncreasingFrameTimesAreDetected() {
        #expect(!EvalRunner.isStrictlyIncreasing([0.0, 0.5, 0.5]))
        #expect(!EvalRunner.isStrictlyIncreasing([0.0, 0.5, 0.4]))
    }
}
