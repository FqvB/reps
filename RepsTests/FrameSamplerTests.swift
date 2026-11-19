import ShotDetector
import Testing

struct FrameSamplerTests {
    // Frame times at a steady rate on a host-clock-like origin.
    private func times(fps: Double, count: Int, start: Double = 1000) -> [Double] {
        (0..<count).map { start + Double($0) / fps }
    }

    private func taken(_ times: [Double]) -> [Int] {
        var sampler = FrameSampler()
        return times.indices.filter { sampler.take(times[$0]) }
    }

    @Test func sixtyFpsTakesEveryFourthFrame() {
        #expect(taken(times(fps: 60, count: 60)) == Array(stride(from: 0, to: 60, by: 4)))
    }

    @Test(arguments: [30.0, 30000.0 / 1001])
    func thirtyFpsTakesEverySecondFrame(fps: Double) {
        #expect(taken(times(fps: fps, count: 30)) == Array(stride(from: 0, to: 30, by: 2)))
    }

    @Test func aDroppedDueFrameIsReplacedByTheNextOne() {
        var frames = times(fps: 60, count: 60)
        frames.removeSubrange(4...5)
        let numbers = taken(frames).map { Int(((frames[$0] - 1000) * 60).rounded()) }
        #expect(numbers == [0, 6, 8] + Array(stride(from: 12, to: 60, by: 4)))
    }

    @Test func longerIntervalTakesEffectAtOnce() {
        var sampler = FrameSampler()
        let frames = times(fps: 60, count: 120)
        var picked: [Int] = []
        for index in frames.indices {
            if index == 30 { sampler.interval = 0.1 }
            if sampler.take(frames[index]) { picked.append(index) }
        }
        #expect(picked == Array(stride(from: 0, through: 32, by: 4)) + Array(stride(from: 38, to: 120, by: 6)))
    }

    @Test func aPauseRestartsWithoutABurst() {
        let frames = times(fps: 60, count: 30) + times(fps: 60, count: 30, start: 1010)
        let picked = taken(frames).map { frames[$0] }
        #expect(picked.contains(1010))
        for (earlier, later) in zip(picked, picked.dropFirst()) {
            #expect(later - earlier >= 1.0 / 30 - 0.001)
        }
    }
}
