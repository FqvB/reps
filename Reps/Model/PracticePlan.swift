import Foundation
import SwiftData

@Model
final class PracticePlan {
    var id: UUID = UUID()
    var name: String = ""
    var mode: PracticeMode = PracticeMode.rangeCounter
    var isOrderMandatory: Bool = false
    var isStrictCount: Bool = false
    var createdAt: Date = Date()
    // Unordered in the store; read through sortedBlocks.
    @Relationship(deleteRule: .cascade, inverse: \PlanBlock.plan)
    var blocks: [PlanBlock] = []
    // Sessions outlive their plan.
    @Relationship(deleteRule: .nullify, inverse: \PracticeSession.plan)
    var sessions: [PracticeSession] = []

    init(
        name: String,
        mode: PracticeMode,
        isOrderMandatory: Bool = false,
        isStrictCount: Bool = false,
        createdAt: Date = .now
    ) {
        self.name = name
        self.mode = mode
        self.isOrderMandatory = isOrderMandatory
        self.isStrictCount = isStrictCount
        self.createdAt = createdAt
    }

    var sortedBlocks: [PlanBlock] {
        blocks.sorted { $0.order < $1.order }
    }
}
