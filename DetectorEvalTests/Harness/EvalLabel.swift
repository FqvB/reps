// Ground-truth marks from hitreg-ml label CSVs (ADR 0007, 0008).
enum LabelKind: String, CaseIterable, Codable, Sendable {
    case swing, practice, motion, putt, pickup
}

struct EvalLabel: Hashable, Sendable {
    var frame: Int
    var seconds: Double
    var kind: LabelKind
}

enum LabelRole: Sendable {
    case positive  // the detector should fire once
    case negative  // the detector must not fire (hard negative)
}

// Which label kinds a detector is expected to count.
struct ScoringProfile: Sendable {
    var name: String
    var roles: [LabelKind: LabelRole]

    func role(of kind: LabelKind) -> LabelRole { roles[kind] ?? .negative }

    // Ball-gated range counter (spec §5.4): practice swings leave the ball, so they must not count.
    static let rangeShot = ScoringProfile(
        name: "rangeShot", roles: [.swing: .positive, .practice: .negative, .motion: .negative])
    // Pose-only swing detection (#17, #18): practice swings are swings (ADR 0007).
    static let rangeSwing = ScoringProfile(
        name: "rangeSwing", roles: [.swing: .positive, .practice: .positive, .motion: .negative])
    // Putting (ADR 0008): a pickup moves the ball, so the detector is expected to count it.
    static let putting = ScoringProfile(
        name: "putting", roles: [.putt: .positive, .pickup: .positive, .motion: .negative])
}
