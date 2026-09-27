import Foundation
import Testing

@Suite(.enabled(if: MLData.root != nil, "hitreg-ml not found; set REPS_ML_DIR"))
struct MLDataTests {
    @Test func testSplitIsListed() throws {
        let root = try #require(MLData.root)
        let data = try Data(contentsOf: root.appending(path: "data/splits.json"))
        let splits = try JSONDecoder().decode([String: [String]].self, from: data)
        let test = try #require(splits["test"])
        #expect(!test.isEmpty)
    }
}
