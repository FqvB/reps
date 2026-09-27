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

    // Q22: each block counts at most its target, so surplus on one block never covers another (45/30 + 15/30 = 75 %).
    // Untargeted blocks are ignored.
    static func session(_ tallies: [BlockTally]) -> Double? {
        var done = 0
        var target = 0
        for tally in tallies {
            guard let blockTarget = tally.target, blockTarget > 0 else { continue }
            done += min(tally.done, blockTarget)
            target += blockTarget
        }
        guard target > 0 else { return nil }
        return Double(done) / Double(target)
    }
}
