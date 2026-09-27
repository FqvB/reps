import Foundation
import Testing

@testable import Reps

struct PlanDraftTests {
    private let a = BlockDraft(clubName: "PW", targetReps: 40)
    private let b = BlockDraft(clubName: "GW", targetReps: 30)
    private let c = BlockDraft(clubName: "SW", targetReps: 20)

    private func draft() -> PlanDraft {
        PlanDraft(name: "Wedge day", blocks: [a, b, c])
    }

    private func clubs(_ draft: PlanDraft) -> [String] { draft.blocks.map(\.clubName) }

    @Test func emptyDraftCannotSave() {
        #expect(!PlanDraft().canSave)
        #expect(!PlanDraft(name: "   ", blocks: [a]).canSave)
        #expect(!PlanDraft(name: "Wedge day").canSave)
        #expect(!PlanDraft(name: "Wedge day", blocks: [BlockDraft(clubName: "  ")]).canSave)
        #expect(!PlanDraft(name: "Wedge day", blocks: [BlockDraft(clubName: "PW", targetReps: 0)]).canSave)
    }

    @Test func namedDraftWithValidBlocksCanSave() {
        #expect(draft().canSave)
        #expect(draft().totalReps == 90)
    }

    @Test func adjustRepsClampsToRange() {
        var block = BlockDraft(clubName: "PW", targetReps: 3)
        block.adjustReps(by: -10)
        #expect(block.targetReps == 1)
        block.adjustReps(by: 5)
        #expect(block.targetReps == 6)
        block.targetReps = 995
        block.adjustReps(by: 10)
        #expect(block.targetReps == 999)
    }

    @Test func storedNoteTrimsAndDropsBlank() {
        #expect(BlockDraft(clubName: "PW", note: "  110 m ").storedNote == "110 m")
        #expect(BlockDraft(clubName: "PW", note: " \n ").storedNote == nil)
    }

    @Test func upsertReplacesByIDOrAppends() {
        var draft = draft()
        var edited = b
        edited.targetReps = 50
        draft.upsert(edited)
        #expect(draft.blocks[1].targetReps == 50)
        #expect(draft.blocks.count == 3)
        let added = BlockDraft(clubName: "LW")
        draft.upsert(added)
        #expect(draft.blocks.last == added)
    }

    @Test func moveBlocksMatchesListSemantics() {
        var down = draft()
        down.moveBlocks(fromOffsets: [0], toOffset: 3)
        #expect(clubs(down) == ["GW", "SW", "PW"])
        var up = draft()
        up.moveBlocks(fromOffsets: [2], toOffset: 0)
        #expect(clubs(up) == ["SW", "PW", "GW"])
        var several = draft()
        several.moveBlocks(fromOffsets: [0, 2], toOffset: 2)
        #expect(clubs(several) == ["GW", "PW", "SW"])
        var inPlace = draft()
        inPlace.moveBlocks(fromOffsets: [1], toOffset: 1)
        #expect(inPlace == draft())
    }

    @Test func moveBlocksIgnoresOffsetsOutOfRange() {
        var draft = draft()
        draft.moveBlocks(fromOffsets: [7], toOffset: 0)
        #expect(draft == self.draft())
    }

    @Test func removeThenRestorePutsBlockBack() throws {
        var draft = draft()
        let taken = draft.removeBlock(id: b.id)
        let removed = try #require(taken)
        #expect(removed.index == 1)
        #expect(clubs(draft) == ["PW", "SW"])
        draft.restore(removed)
        #expect(draft == self.draft())
        let missing = draft.removeBlock(id: UUID())
        #expect(missing == nil)
    }

    @Test func restoreClampsWhenListShrank() throws {
        var draft = draft()
        let taken = draft.removeBlock(id: c.id)
        let removed = try #require(taken)
        _ = draft.removeBlock(id: b.id)
        draft.restore(removed)
        #expect(clubs(draft) == ["PW", "SW"])
    }

    @Test func restoreIgnoresABlockAlreadyPresent() throws {
        var draft = draft()
        let taken = draft.removeBlock(id: a.id)
        let removed = try #require(taken)
        draft.restore(removed)
        draft.restore(removed)
        #expect(draft.blocks.count == 3)
    }

    @Test func changesAreDetected() throws {
        let original = draft()
        var edited = original
        #expect(edited == original)

        edited.name = "Wedges"
        #expect(edited != original)
        edited = original
        edited.isStrictCount = true
        #expect(edited != original)
        edited = original
        edited.mode = .putting
        #expect(edited != original)
        edited = original
        edited.blocks[0].adjustReps(by: 1)
        #expect(edited != original)
        edited = original
        edited.blocks[2].note = "80 m"
        #expect(edited != original)

        edited = original
        edited.moveBlocks(fromOffsets: [0], toOffset: 2)
        #expect(edited != original)
        edited.moveBlocks(fromOffsets: [1], toOffset: 0)
        #expect(edited == original)

        edited = original
        let taken = edited.removeBlock(id: a.id)
        let removed = try #require(taken)
        #expect(edited != original)
        edited.restore(removed)
        #expect(edited == original)
    }
}
