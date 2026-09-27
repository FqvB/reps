import Testing

@testable import Reps

struct CompletionTests {
    @Test(arguments: [
        (BlockTally(counted: 30, manualAdjust: 0, target: 30), 1.0),
        (BlockTally(counted: 45, manualAdjust: 0, target: 30), 1.5),
        (BlockTally(counted: 0, manualAdjust: 0, target: 30), 0.0),
        (BlockTally(counted: 28, manualAdjust: 2, target: 30), 1.0),
        (BlockTally(counted: 0, manualAdjust: 15, target: 30), 0.5),
        (BlockTally(counted: 31, manualAdjust: -1, target: 40), 0.75),
    ])
    func blockCompletion(tally: BlockTally, expected: Double) {
        #expect(Completion.block(tally) == expected)
    }

    @Test func negativeNetClampsToZero() {
        let tally = BlockTally(counted: 0, manualAdjust: -2, target: 10)
        #expect(tally.done == 0)
        #expect(Completion.block(tally) == 0)
    }

    @Test(arguments: [nil, 0, -5] as [Int?])
    func noPositiveTargetHasNoCompletion(target: Int?) {
        let tally = BlockTally(counted: 12, manualAdjust: 0, target: target)
        #expect(Completion.block(tally) == nil)
        #expect(Completion.isComplete(tally) == false)
    }

    @Test func completeAtOrOverTarget() {
        #expect(Completion.isComplete(BlockTally(counted: 29, manualAdjust: 0, target: 30)) == false)
        #expect(Completion.isComplete(BlockTally(counted: 29, manualAdjust: 1, target: 30)))
        #expect(Completion.isComplete(BlockTally(counted: 40, manualAdjust: 0, target: 30)))
    }

    // Q22: 45/30 + 15/30 is 75 %, not 100 %; surplus on one block doesn't cover another.
    @Test func sessionCapsEachBlockAtItsTarget() {
        let tallies = [
            BlockTally(counted: 45, manualAdjust: 0, target: 30),
            BlockTally(counted: 10, manualAdjust: 5, target: 30),
        ]
        #expect(Completion.session(tallies) == 0.75)
        #expect(Completion.block(tallies[0]) == 1.5)
    }

    @Test func surplusDoesNotCoverASkippedBlock() {
        let tallies = [
            BlockTally(counted: 60, manualAdjust: 0, target: 30),
            BlockTally(counted: 0, manualAdjust: 0, target: 30),
        ]
        #expect(Completion.session(tallies) == 0.5)
    }

    @Test func skippedBlockCountsAgainstSession() {
        let tallies = [
            BlockTally(counted: 30, manualAdjust: 0, target: 30),
            BlockTally(counted: 0, manualAdjust: 0, target: 10),
        ]
        #expect(Completion.session(tallies) == 0.75)
    }

    @Test func sessionNeverExceedsOne() {
        let tallies = [
            BlockTally(counted: 60, manualAdjust: 0, target: 40),
            BlockTally(counted: 35, manualAdjust: 0, target: 30),
        ]
        #expect(Completion.session(tallies) == 1.0)
    }

    @Test func untargetedBlocksAreIgnored() {
        let tallies = [
            BlockTally(counted: 20, manualAdjust: 0, target: 20),
            BlockTally(counted: 50, manualAdjust: 0, target: nil),
        ]
        #expect(Completion.session(tallies) == 1.0)
    }

    @Test func sessionWithoutTargetsHasNoCompletion() {
        #expect(Completion.session([]) == nil)
        #expect(Completion.session([BlockTally(counted: 50, manualAdjust: 0, target: nil)]) == nil)
    }
}
