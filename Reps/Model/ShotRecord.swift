import Foundation
import SwiftData

@Model
final class ShotRecord {
    var id: UUID = UUID()
    var blockResult: BlockResult?
    var timestamp: Date = Date()
    var detectedBy: DetectionSource = DetectionSource.manual
    // Copied from the block so retagging one shot is cheap (spec §5.1).
    var clubName: String = ""
    var tags: [String] = []
    var isFavourite: Bool = false
    var tempoRatio: Double?
    // Bare file name "<id>.mov" under Documents/clips/<sessionId>/ (ADR 0006).
    var clipFileName: String?

    init(timestamp: Date = .now, detectedBy: DetectionSource, clubName: String, tags: [String] = []) {
        self.timestamp = timestamp
        self.detectedBy = detectedBy
        self.clubName = clubName
        self.tags = tags
    }
}
