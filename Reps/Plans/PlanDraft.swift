import Foundation

nonisolated struct BlockDraft: Identifiable, Equatable, Sendable {
    static let repsRange = 1...999
    static let defaultReps = 30

    var id: UUID
    var clubName: String
    var targetReps: Int
    var note: String

    init(id: UUID = UUID(), clubName: String, targetReps: Int = BlockDraft.defaultReps, note: String = "") {
        self.id = id
        self.clubName = clubName
        self.targetReps = targetReps
        self.note = note
    }

    var trimmedClubName: String { clubName.trimmingCharacters(in: .whitespacesAndNewlines) }

    // Blank notes are stored as nil.
    var storedNote: String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var isValid: Bool { !trimmedClubName.isEmpty && Self.repsRange.contains(targetReps) }

    mutating func adjustReps(by delta: Int) {
        targetReps = min(max(targetReps + delta, Self.repsRange.lowerBound), Self.repsRange.upperBound)
    }
}

nonisolated struct RemovedBlock: Identifiable, Equatable, Sendable {
    let block: BlockDraft
    let index: Int

    var id: UUID { block.id }
}

// The editor's working copy; nothing touches SwiftData until PlanLibrary.save.
nonisolated struct PlanDraft: Equatable, Sendable {
    var name: String
    var mode: PracticeMode
    var isOrderMandatory: Bool
    var isStrictCount: Bool
    var blocks: [BlockDraft]

    init(
        name: String = "",
        mode: PracticeMode = .rangeCounter,
        isOrderMandatory: Bool = false,
        isStrictCount: Bool = false,
        blocks: [BlockDraft] = []
    ) {
        self.name = name
        self.mode = mode
        self.isOrderMandatory = isOrderMandatory
        self.isStrictCount = isStrictCount
        self.blocks = blocks
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var totalReps: Int { blocks.reduce(0) { $0 + $1.targetReps } }
    var canSave: Bool { !trimmedName.isEmpty && !blocks.isEmpty && blocks.allSatisfy(\.isValid) }

    func index(of id: UUID) -> Int? { blocks.firstIndex { $0.id == id } }

    // Replaces the block with the same id, or appends it.
    mutating func upsert(_ block: BlockDraft) {
        if let index = index(of: block.id) {
            blocks[index] = block
        } else {
            blocks.append(block)
        }
    }

    mutating func removeBlock(id: UUID) -> RemovedBlock? {
        guard let index = index(of: id) else { return nil }
        return RemovedBlock(block: blocks.remove(at: index), index: index)
    }

    // Puts it back where it was, clamped if the list has shrunk since.
    mutating func restore(_ removed: RemovedBlock) {
        guard index(of: removed.block.id) == nil else { return }
        blocks.insert(removed.block, at: min(removed.index, blocks.count))
    }

    // Same semantics as SwiftUI's move(fromOffsets:toOffset:), without importing SwiftUI.
    mutating func moveBlocks(fromOffsets source: IndexSet, toOffset destination: Int) {
        let valid = source.filter { blocks.indices.contains($0) }
        guard !valid.isEmpty else { return }
        let moving = valid.map { blocks[$0] }
        let shift = valid.filter { $0 < destination }.count
        for index in valid.reversed() { blocks.remove(at: index) }
        blocks.insert(contentsOf: moving, at: min(max(destination - shift, 0), blocks.count))
    }
}
