nonisolated struct BlockTally: Equatable, Sendable {
    var counted: Int
    var manualAdjust: Int
    // nil = no target (free session block).
    var target: Int?

    var done: Int { max(0, counted + manualAdjust) }
}

nonisolated enum Completion {
    // Uncapped: 45 of 30 is 1.5. nil without a positive target.
    static func block(_ tally: BlockTally) -> Double? {
        guard let target = tally.target, target > 0 else { return nil }
        return Double(tally.done) / Double(target)
    }

    static func isComplete(_ tally: BlockTally) -> Bool {
        guard let target = tally.target, target > 0 else { return false }
        return tally.done >= target
    }

    // Total done over total target across targeted blocks; untargeted blocks are ignored.
    static func session(_ tallies: [BlockTally]) -> Double? {
        let targeted = tallies.filter { ($0.target ?? 0) > 0 }
        let target = targeted.reduce(0) { $0 + ($1.target ?? 0) }
        guard target > 0 else { return nil }
        let done = targeted.reduce(0) { $0 + $1.done }
        return Double(done) / Double(target)
    }
}
