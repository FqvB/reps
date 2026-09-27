import Foundation
import ShotDetector
import Testing

// End-to-end check of the harness: a detector that replays the labels must score perfectly.
@Suite(.enabled(if: MLData.root != nil, "hitreg-ml not found; set REPS_ML_DIR"))
struct OracleEvalTests {
    @Test func rangeTestSplit() async throws {
        let dataset = try EvalDataset.rangeTest(root: try #require(MLData.root))
        try await expectPerfectScore(on: dataset, name: "oracle-range")
    }

    @Test(.enabled(if: MLData.root.map(EvalDataset.hasPutting) == true, "no data/putting in hitreg-ml"))
    func putting() async throws {
        let dataset = try EvalDataset.putting(root: try #require(MLData.root))
        try await expectPerfectScore(on: dataset, name: "oracle-putting")
    }

    private func expectPerfectScore(on dataset: EvalDataset, name: String) async throws {
        #expect(!dataset.videos.isEmpty)
        let report = try await EvalRunner().run(name, on: dataset) { video in
            LabelOracle(video: video, profile: dataset.profile)
        }
        try EvalOutput.publish(report)
        let all = report.overall
        #expect(all.recall == 1)
        #expect(all.precision == 1)
        #expect(all.hardNegativeFalsePositives == 0)
        // The oracle fires on the next sampled frame, so it lags by at most ~one sampling step.
        #expect(try #require(all.maxLatency) <= 2 / DetectorInput.frameRate)
    }
}
