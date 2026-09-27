// A detector output as the harness sees it: the event's own time and the frame time it was emitted at.
struct Detection: Hashable, Sendable {
    var time: Double
    var emittedAt: Double
}

// A label with its time on the decoded stream's clock.
struct TimedLabel: Hashable, Sendable {
    var time: Double
    var kind: LabelKind
}

struct VideoScore: Sendable {
    var positives = 0
    var detections = 0
    var truePositives = 0
    var hardNegativeFalsePositives = 0
    var otherFalsePositives = 0
    var latencies: [Double] = []
    var timingErrors: [Double] = []
    var labelsByKind: [LabelKind: Int] = [:]
    var firedByKind: [LabelKind: Int] = [:]

    var falsePositives: Int { hardNegativeFalsePositives + otherFalsePositives }
    var falseNegatives: Int { positives - truePositives }
    var countError: Int { detections - positives }
}

enum EventMatcher {
    // One-to-one matching of detections to positive labels within ±window seconds.
    // Labels are taken in time order, each claiming the earliest free detection in its window;
    // with equal windows this gives the largest possible number of matches.
    static func score(
        labels: [TimedLabel], detections: [Detection], profile: ScoringProfile, window: Double
    ) -> VideoScore {
        var score = VideoScore()
        let sortedDetections = detections.sorted { $0.time < $1.time }
        let sortedLabels = labels.sorted { $0.time < $1.time }
        var claimed = Array(repeating: false, count: sortedDetections.count)
        score.detections = sortedDetections.count

        for label in sortedLabels {
            score.labelsByKind[label.kind, default: 0] += 1
            guard profile.role(of: label.kind) == .positive else { continue }
            score.positives += 1
            // Earliest free detection, not nearest: keeps the matching maximal (see the comment
            // above), so a reported latency can come out negative.
            let hit = sortedDetections.indices.first { index in
                !claimed[index] && abs(sortedDetections[index].time - label.time) <= window
            }
            if let hit {
                claimed[hit] = true
                score.truePositives += 1
                score.firedByKind[label.kind, default: 0] += 1
                score.latencies.append(sortedDetections[hit].emittedAt - label.time)
                score.timingErrors.append(sortedDetections[hit].time - label.time)
            }
        }

        let negatives = sortedLabels.filter { profile.role(of: $0.kind) == .negative }
        var negativeFired = Array(repeating: false, count: negatives.count)
        for (index, detection) in sortedDetections.enumerated() where !claimed[index] {
            let nearest = negatives.indices
                .filter { abs(negatives[$0].time - detection.time) <= window }
                .min { abs(negatives[$0].time - detection.time) < abs(negatives[$1].time - detection.time) }
            if let nearest {
                score.hardNegativeFalsePositives += 1
                negativeFired[nearest] = true
            } else {
                score.otherFalsePositives += 1
            }
        }
        for (index, label) in negatives.enumerated() where negativeFired[index] {
            score.firedByKind[label.kind, default: 0] += 1
        }
        return score
    }
}
