import Foundation

// Locates the hitreg-ml checkout (ADR 0007): REPS_ML_DIR, else the sibling repo.
enum MLData {
    static let root: URL? = {
        let candidate: URL
        if let path = ProcessInfo.processInfo.environment["REPS_ML_DIR"], !path.isEmpty {
            candidate = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            candidate = siblingCheckout
        }
        let manifest = candidate.appending(path: "data/manifest.csv")
        return FileManager.default.fileExists(atPath: manifest.path) ? candidate : nil
    }()

    // <repo>/DetectorEvalTests/MLData.swift -> <repo>/../hitreg-ml
    private static var siblingCheckout: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "hitreg-ml", directoryHint: .isDirectory)
    }
}
