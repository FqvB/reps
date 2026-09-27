import Foundation

struct EvalReport: Sendable {
    var name: String
    var dataset: String
    var profile: String
    var window: Double
    var frameRate: Double?
    var shortSide: Int?
    var results: [VideoResult]
    var seconds: Double

    // One row per scenario (sorted), then "all".
    var scenarios: [(scenario: String, metrics: EvalMetrics)] {
        Set(results.map(\.scenario)).sorted().map { scenario in
            (scenario, EvalMetrics(results.filter { $0.scenario == scenario }.map(\.score)))
        } + [("all", overall)]
    }

    var overall: EvalMetrics { EvalMetrics(results.map(\.score)) }

    var table: String {
        var lines = [
            "DetectorEval \(name) on \(dataset) (\(profile))  window ±\(format(window)) s  "
                + "\(frameRate.map { "\(format($0)) fps" } ?? "every frame")  "
                + "short side \(shortSide.map(String.init) ?? "native")  took \(format(seconds)) s",
            Self.row([
                "scenario", "videos", "pos", "det", "TP", "FP", "hardFP", "FN", "prec", "recall", "FP/50", "|cnt|",
                "lat", "latMax",
            ]),
        ]
        for (scenario, m) in scenarios {
            lines.append(
                Self.row([
                    scenario, "\(m.videos)", "\(m.positives)", "\(m.detections)", "\(m.truePositives)",
                    "\(m.falsePositives)", "\(m.hardNegativeFalsePositives)", "\(m.falseNegatives)",
                    format(m.precision), format(m.recall), format(m.falsePer50), "\(m.absCountError)",
                    format(m.meanLatency), format(m.maxLatency),
                ]))
        }
        let all = overall
        lines.append(
            "fired/labels: "
                + LabelKind.allCases.compactMap { kind in
                    all.labelsByKind[kind].map { "\(kind.rawValue) \(all.firedByKind[kind] ?? 0)/\($0)" }
                }.joined(separator: "  "))
        for result in results where result.score.countError != 0 {
            lines.append("miscount \(result.video): expected \(result.score.positives), got \(result.score.detections)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    var json: Data {
        get throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(ReportJSON(self))
        }
    }

    private static func row(_ cells: [String]) -> String {
        cells.enumerated().map { index, cell in
            index == 0
                ? cell.padding(toLength: 14, withPad: " ", startingAt: 0)
                : String(repeating: " ", count: max(1, 8 - cell.count)) + cell
        }.joined()
    }

    private func format(_ value: Double?) -> String {
        value.map { String(format: "%.2f", $0) } ?? "-"
    }
}

// Encoded shape of a report (build/eval/<name>.json).
private struct ReportJSON: Encodable {
    struct Scenario: Encodable {
        var scenario: String
        var videos, positives, detections, truePositives, falsePositives, hardNegativeFalsePositives: Int
        var falseNegatives, absCountError: Int
        var precision, recall, falsePer50, meanLatency, maxLatency, meanAbsTimingError: Double?
        var labelsByKind, firedByKind: [String: Int]
    }
    struct Video: Encodable {
        var video, scenario: String
        var positives, detections, truePositives, falsePositives, decodedFrames, sampledFrames: Int
    }
    var name, dataset, profile: String
    var window: Double
    var frameRate: Double?
    var shortSide: Int?
    var seconds: Double
    var scenarios: [Scenario]
    var videos: [Video]

    init(_ report: EvalReport) {
        name = report.name
        dataset = report.dataset
        profile = report.profile
        window = report.window
        frameRate = report.frameRate
        shortSide = report.shortSide
        seconds = report.seconds
        scenarios = report.scenarios.map { scenario, m in
            Scenario(
                scenario: scenario, videos: m.videos, positives: m.positives, detections: m.detections,
                truePositives: m.truePositives, falsePositives: m.falsePositives,
                hardNegativeFalsePositives: m.hardNegativeFalsePositives, falseNegatives: m.falseNegatives,
                absCountError: m.absCountError, precision: m.precision, recall: m.recall,
                falsePer50: m.falsePer50, meanLatency: m.meanLatency, maxLatency: m.maxLatency,
                meanAbsTimingError: m.meanAbsTimingError,
                labelsByKind: Dictionary(uniqueKeysWithValues: m.labelsByKind.map { ($0.rawValue, $1) }),
                firedByKind: Dictionary(uniqueKeysWithValues: m.firedByKind.map { ($0.rawValue, $1) }))
        }
        videos = report.results.map {
            Video(
                video: $0.video, scenario: $0.scenario, positives: $0.score.positives,
                detections: $0.score.detections, truePositives: $0.score.truePositives,
                falsePositives: $0.score.falsePositives, decodedFrames: $0.decodedFrames,
                sampledFrames: $0.sampledFrames)
        }
    }
}
