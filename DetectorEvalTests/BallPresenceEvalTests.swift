import ShotDetector
import Testing

@Suite(.enabled(if: MLData.root.map(EvalDataset.hasPutting) == true, "no putting footage; set REPS_ML_DIR"))
struct BallPresenceEvalTests {
    @Test func putting() async throws {
        let dataset = try EvalDataset.putting(root: try #require(MLData.root))
        let report = try await EvalRunner().run("ball-presence-putting", on: dataset) { _ in BallPresenceDetector() }
        try EvalOutput.publish(report)
        let all = report.overall
        // Floors, not targets: the planner's prototype scored recall 19/22, precision 19/20 (docs/plans/14-ball-presence.md). #21 sets the real gates.
        #expect(try #require(all.recall) >= 0.7)
        #expect(try #require(all.precision) >= 0.8)
    }
}
