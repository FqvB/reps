import Foundation

struct EvalVideo: Sendable {
    var name: String
    var url: URL
    var scenario: String  // "dtl/sun", "faceon/cloud", "putt/indoor"
    var labels: [EvalLabel]
}

struct EvalDataset: Sendable {
    var name: String
    var profile: ScoringProfile
    var videos: [EvalVideo]

    enum LoadError: Error, CustomStringConvertible {
        case missingFile(String)
        case badRow(file: String, row: [String: String])
        case unknownVideo(String)

        var description: String {
            switch self {
            case .missingFile(let path): "missing file: \(path)"
            case .badRow(let file, let row): "bad row in \(file): \(row)"
            case .unknownVideo(let name): "video in splits.json but not in manifest.csv: \(name)"
            }
        }
    }

    // Range footage, test split only (ADR 0007). Rows whose notes say "discard" are left out.
    static func rangeTest(root: URL, profile: ScoringProfile = .rangeShot) throws -> EvalDataset {
        let data = root.appending(path: "data")
        let splits = try JSONDecoder().decode(
            [String: [String]].self, from: Data(contentsOf: data.appending(path: "splits.json")))
        let manifest = try manifestRows(data.appending(path: "manifest.csv"))
        var videos: [EvalVideo] = []
        for name in splits["test"] ?? [] {
            guard let row = manifest[name] else { throw LoadError.unknownVideo(name) }
            if row["notes"]?.contains("discard") == true { continue }
            videos.append(
                EvalVideo(
                    name: name,
                    url: try existing(data.appending(path: "raw/\(name).mov")),
                    scenario: "\(row["angle"] ?? "?")/\(row["light"] ?? "?")",
                    labels: try labels(data.appending(path: "labels/\(name).csv"))))
        }
        return EvalDataset(name: "range-test", profile: profile, videos: videos)
    }

    // Putting footage (ADR 0008): every clip in data/putting/manifest.csv; no splits yet.
    static func putting(root: URL) throws -> EvalDataset {
        let data = root.appending(path: "data/putting")
        let manifest = try manifestRows(data.appending(path: "manifest.csv"))
        let videos = try manifest.keys.sorted().map { name in
            EvalVideo(
                name: name,
                url: try existing(data.appending(path: "raw/\(name).mov")),
                scenario: "putt/\(manifest[name]?["light"] ?? "?")",
                labels: try labels(data.appending(path: "labels/\(name).csv")))
        }
        return EvalDataset(name: "putting", profile: .putting, videos: videos)
    }

    static func hasPutting(root: URL) -> Bool {
        FileManager.default.fileExists(atPath: root.appending(path: "data/putting/manifest.csv").path)
    }

    static func labels(_ url: URL) throws -> [EvalLabel] {
        try records(url).map { row in
            guard let frame = row["frame"].flatMap({ Int($0) }),
                let seconds = row["seconds"].flatMap({ Double($0) }),
                let kind = row["kind"].flatMap({ LabelKind(rawValue: $0) })
            else { throw LoadError.badRow(file: url.lastPathComponent, row: row) }
            return EvalLabel(frame: frame, seconds: seconds, kind: kind)
        }
    }

    private static func manifestRows(_ url: URL) throws -> [String: [String: String]] {
        var byVideo: [String: [String: String]] = [:]
        for row in try records(url) {
            guard let video = row["video"], !video.isEmpty else {
                throw LoadError.badRow(file: url.lastPathComponent, row: row)
            }
            byVideo[video] = row
        }
        return byVideo
    }

    private static func records(_ url: URL) throws -> [[String: String]] {
        CSV.records(try String(contentsOf: try existing(url), encoding: .utf8))
    }

    private static func existing(_ url: URL) throws -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { throw LoadError.missingFile(url.path) }
        return url
    }
}
