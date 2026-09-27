import Foundation
import SwiftData

@Model
final class BlockResult {
    var id: UUID = UUID()
    var session: PracticeSession?
    var block: PlanBlock?
    var order: Int = 0
    var clubName: String = ""
    // Snapshot of the plan block's target; nil in a free session.
    var targetReps: Int?
    // Active tag set for this block, restored on resume.
    var tags: [String] = []
    var repsCounted: Int = 0
    // Net of +1/−1 taps, kept apart from detections (spec §5.1).
    var repsManualAdjust: Int = 0
    @Relationship(deleteRule: .cascade, inverse: \ShotRecord.blockResult)
    var shots: [ShotRecord] = []

    init(block: PlanBlock, order: Int) {
        self.block = block
        self.order = order
        self.clubName = block.clubName
        self.targetReps = block.targetReps
    }

    init(clubName: String, tags: [String] = [], order: Int) {
        self.clubName = clubName
        self.tags = tags
        self.order = order
    }

    var tally: BlockTally {
        BlockTally(counted: repsCounted, manualAdjust: repsManualAdjust, target: targetReps)
    }

    var sortedShots: [ShotRecord] {
        shots.sorted { ($0.timestamp, $0.id.uuidString) < ($1.timestamp, $1.id.uuidString) }
    }
}
