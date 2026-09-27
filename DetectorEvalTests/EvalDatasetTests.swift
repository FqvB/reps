import Foundation
import Testing

struct EvalDatasetTests {
    private func labels(_ csv: String) throws -> [EvalLabel] {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).csv")
        try Data(csv.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try EvalDataset.labels(url)
    }

    @Test func parsesLabelRows() throws {
        #expect(
            try labels("frame,seconds,kind\n130,4.333,practice\n1416,47.200,swing\n") == [
                EvalLabel(frame: 130, seconds: 4.333, kind: .practice),
                EvalLabel(frame: 1416, seconds: 47.2, kind: .swing),
            ])
    }

    @Test func unknownKindThrows() {
        #expect(throws: EvalDataset.LoadError.self) { try labels("frame,seconds,kind\n1,0.1,chip\n") }
    }

    @Test(.enabled(if: MLData.root != nil, "hitreg-ml not found; set REPS_ML_DIR"))
    func rangeTestSplitLoads() throws {
        let dataset = try EvalDataset.rangeTest(root: try #require(MLData.root))
        #expect(dataset.videos.count == 22)  // ADR 0007: 22 test videos
        for video in dataset.videos {
            #expect(video.labels.contains { $0.kind == .swing }, "\(video.name)")
            #expect(["dtl", "faceon"].contains(video.scenario.split(separator: "/").first), "\(video.name)")
        }
    }

    @Test(.enabled(if: MLData.root.map(EvalDataset.hasPutting) == true, "no data/putting in hitreg-ml"))
    func puttingLoads() throws {
        let dataset = try EvalDataset.putting(root: try #require(MLData.root))
        #expect(!dataset.videos.isEmpty)
        for video in dataset.videos {
            #expect(video.scenario.hasPrefix("putt/"))
            #expect(video.labels.contains { $0.kind == .putt }, "\(video.name)")
        }
    }
}
