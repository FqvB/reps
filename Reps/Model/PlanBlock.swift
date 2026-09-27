import Foundation
import SwiftData

@Model
final class PlanBlock {
    var id: UUID = UUID()
    var clubName: String = ""
    var targetReps: Int = 0
    var note: String?
    var order: Int = 0
    var plan: PracticePlan?
    // Results keep their snapshot when the block is deleted.
    @Relationship(deleteRule: .nullify, inverse: \BlockResult.block)
    var results: [BlockResult] = []

    init(clubName: String, targetReps: Int, note: String? = nil, order: Int) {
        self.clubName = clubName
        self.targetReps = targetReps
        self.note = note
        self.order = order
    }
}
