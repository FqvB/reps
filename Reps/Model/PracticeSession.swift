import Foundation
import SwiftData

@Model
final class PracticeSession {
    var id: UUID = UUID()
    var plan: PracticePlan?
    // Snapshot so the log still names the plan after it's deleted.
    var planName: String?
    var mode: PracticeMode = PracticeMode.rangeCounter
    var status: SessionStatus = SessionStatus.active
    var startedAt: Date = Date()
    var endedAt: Date?
    var cameraAngle: CameraAngle = CameraAngle.none
    // Plan rules copied at start so resume survives plan edits or deletion (Q24).
    var isStrictCount: Bool = false
    var isOrderMandatory: Bool = false
    // `order` of the block being counted; nil when no block is left to run.
    var activeBlockOrder: Int?
    @Relationship(deleteRule: .cascade, inverse: \BlockResult.session)
    var blockResults: [BlockResult] = []

    init(plan: PracticePlan?, mode: PracticeMode, cameraAngle: CameraAngle, startedAt: Date = .now) {
        self.plan = plan
        self.planName = plan?.name
        self.isStrictCount = plan?.isStrictCount ?? false
        self.isOrderMandatory = plan?.isOrderMandatory ?? false
        self.mode = mode
        self.cameraAngle = cameraAngle
        self.startedAt = startedAt
    }

    // A planned session always has a planName, even after its plan is deleted.
    var isFreeSession: Bool { planName == nil }

    var sortedBlockResults: [BlockResult] {
        blockResults.sorted { ($0.order, $0.id.uuidString) < ($1.order, $1.id.uuidString) }
    }

    var completion: Double? {
        Completion.session(blockResults.map(\.tally))
    }
}
