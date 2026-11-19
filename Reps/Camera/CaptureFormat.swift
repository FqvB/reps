import Foundation

// One device format as the picker sees it.
nonisolated struct FormatCandidate: Equatable, Sendable {
    var width: Int
    var height: Int
    var maxFrameRate: Double
    var isFullRange: Bool
}

// §5.6: capture 1080p at 60 fps, or the closest the camera offers.
nonisolated enum CaptureFormat {
    static let width = 1920
    static let height = 1080
    static let frameRate = 60.0

    // 1080p only. With formats reaching 60 fps, the slowest of them (skips slow-mo formats); otherwise the
    // fastest. Then 420f, then the device's order. Nil without any 1080p format.
    static func best(_ candidates: [FormatCandidate]) -> Int? {
        let hd = candidates.indices.filter { candidates[$0].width == width && candidates[$0].height == height }
        let fast = hd.filter { candidates[$0].maxFrameRate >= frameRate }
        let ranked = (fast.isEmpty ? hd : fast).sorted { a, b in
            let (first, second) = (candidates[a], candidates[b])
            if first.maxFrameRate != second.maxFrameRate {
                return fast.isEmpty
                    ? first.maxFrameRate > second.maxFrameRate : first.maxFrameRate < second.maxFrameRate
            }
            if first.isFullRange != second.isFullRange { return first.isFullRange }
            return a < b
        }
        return ranked.first
    }
}
