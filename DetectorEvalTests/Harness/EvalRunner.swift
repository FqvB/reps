import Foundation
import ShotDetector

struct VideoResult: Sendable {
    var video: String
    var scenario: String
    var score: VideoScore
    var decodedFrames: Int
    var sampledFrames: Int
}

// Runs one detector over one dataset and scores every video.
struct EvalRunner {
    var window: Double = 0.5  // spec §5.4: impact within ±0.5 s
    var frameRate: Double? = DetectorInput.frameRate
    var shortSide: Int? = DetectorInput.shortSide

    enum RunError: Error {
        case nonIncreasingFrameTimes(video: String)
    }

    // Labels move onto the decoder's clock by frame number; past the end, the CSV seconds are used.
    static func labelTimes(_ labels: [EvalLabel], frameTimes: [Double]) -> [Double] {
        labels.map { label in
            frameTimes.indices.contains(label.frame) ? frameTimes[label.frame] : label.seconds
        }
    }

    // Frame timestamps must be strictly increasing for labelTimes' frame → time mapping to be valid.
    static func isStrictlyIncreasing(_ times: [Double]) -> Bool {
        zip(times, times.dropFirst()).allSatisfy { $0 < $1 }
    }

    func run(
        _ name: String,
        on dataset: EvalDataset,
        makeDetector: (EvalVideo) throws -> any ShotDetecting
    ) async throws -> EvalReport {
        let clock = ContinuousClock()
        let start = clock.now
        var results: [VideoResult] = []
        for video in dataset.videos {
            var detector = try makeDetector(video)
            var detections: [Detection] = []
            var sampled = 0
            var lastTime = 0.0
            let reader = VideoFrameReader(url: video.url, frameRate: frameRate, shortSide: shortSide)
            let frameTimes = try await reader.read { frame in
                sampled += 1
                lastTime = frame.time
                detections += detector.process(frame).map { Detection(time: $0.time, emittedAt: frame.time) }
            }
            detections += detector.finish().map { Detection(time: $0.time, emittedAt: lastTime) }
            guard Self.isStrictlyIncreasing(frameTimes) else {
                throw RunError.nonIncreasingFrameTimes(video: video.name)
            }
            let times = Self.labelTimes(video.labels, frameTimes: frameTimes)
            let labels = zip(video.labels, times).map { TimedLabel(time: $1, kind: $0.kind) }
            results.append(
                VideoResult(
                    video: video.name,
                    scenario: video.scenario,
                    score: EventMatcher.score(
                        labels: labels, detections: detections, profile: dataset.profile, window: window),
                    decodedFrames: frameTimes.count,
                    sampledFrames: sampled))
        }
        return EvalReport(
            name: name, dataset: dataset.name, profile: dataset.profile.name, window: window,
            frameRate: frameRate, shortSide: shortSide, results: results,
            seconds: (clock.now - start) / .seconds(1))
    }
}
