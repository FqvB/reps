// Scores summed over videos (micro-averaged), then turned into rates.
struct EvalMetrics: Sendable {
    var videos = 0
    var positives = 0
    var detections = 0
    var truePositives = 0
    var hardNegativeFalsePositives = 0
    var otherFalsePositives = 0
    var absCountError = 0
    var latencies: [Double] = []
    var timingErrors: [Double] = []
    var labelsByKind: [LabelKind: Int] = [:]
    var firedByKind: [LabelKind: Int] = [:]

    init() {}

    init(_ scores: [VideoScore]) {
        for score in scores { add(score) }
    }

    mutating func add(_ score: VideoScore) {
        videos += 1
        positives += score.positives
        detections += score.detections
        truePositives += score.truePositives
        hardNegativeFalsePositives += score.hardNegativeFalsePositives
        otherFalsePositives += score.otherFalsePositives
        absCountError += abs(score.countError)
        latencies += score.latencies
        timingErrors += score.timingErrors
        labelsByKind.merge(score.labelsByKind, uniquingKeysWith: +)
        firedByKind.merge(score.firedByKind, uniquingKeysWith: +)
    }

    var falsePositives: Int { hardNegativeFalsePositives + otherFalsePositives }
    var falseNegatives: Int { positives - truePositives }

    // nil when undefined (no detections / no positives), never NaN.
    var precision: Double? { detections == 0 ? nil : Double(truePositives) / Double(detections) }
    var recall: Double? { positives == 0 ? nil : Double(truePositives) / Double(positives) }
    // Spec §2: at most 1 false count per 50 real shots.
    var falsePer50: Double? { positives == 0 ? nil : Double(falsePositives) * 50 / Double(positives) }
    var meanLatency: Double? { latencies.isEmpty ? nil : latencies.reduce(0, +) / Double(latencies.count) }
    var maxLatency: Double? { latencies.max() }
    var meanAbsTimingError: Double? {
        timingErrors.isEmpty ? nil : timingErrors.map(abs).reduce(0, +) / Double(timingErrors.count)
    }
}
