import Foundation

// Locates the ML data (ADR 0007): REPS_ML_DIR, else <repo>/ml.
enum MLData {
    static let root: URL? = {
        let candidate: URL
        if let path = ProcessInfo.processInfo.environment["REPS_ML_DIR"], !path.isEmpty {
            candidate = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            candidate = repoMLFolder
        }
        let manifest = candidate.appending(path: "data/manifest.csv")
        return FileManager.default.fileExists(atPath: manifest.path) ? candidate : nil
    }()

    // <repo>/DetectorEvalTests/MLData.swift -> <repo>/ml
    private static var repoMLFolder: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "ml", directoryHint: .isDirectory)
    }
}
