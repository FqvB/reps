import Foundation
import SwiftData

// Plan writes for the plans list and editor.
enum PlanLibrary {
    static func draft(from plan: PracticePlan) -> PlanDraft {
        PlanDraft(
            name: plan.name,
            mode: plan.mode,
            isOrderMandatory: plan.isOrderMandatory,
            isStrictCount: plan.isStrictCount,
            blocks: plan.sortedBlocks.map {
                BlockDraft(id: $0.id, clubName: $0.clubName, targetReps: $0.targetReps, note: $0.note ?? "")
            }
        )
    }

    // Creates the plan when `plan` is nil. Blocks keep their ids, so session results stay linked;
    // removed blocks are deleted (their results keep the snapshot). Order is renumbered 0..<n.
    @discardableResult
    static func save(_ draft: PlanDraft, to plan: PracticePlan?, in context: ModelContext, now: Date = .now) throws
        -> PracticePlan
    {
        let target: PracticePlan
        if let plan {
            target = plan
        } else {
            target = PracticePlan(name: draft.trimmedName, mode: draft.mode, createdAt: now)
            context.insert(target)
        }
        target.name = draft.trimmedName
        target.mode = draft.mode
        target.isOrderMandatory = draft.isOrderMandatory
        target.isStrictCount = draft.isStrictCount

        let keptIDs = Set(draft.blocks.map(\.id))
        let removed = target.blocks.filter { !keptIDs.contains($0.id) }
        target.blocks.removeAll { !keptIDs.contains($0.id) }
        for block in removed { context.delete(block) }

        let existing = Dictionary(uniqueKeysWithValues: target.blocks.map { ($0.id, $0) })
        for (order, item) in draft.blocks.enumerated() {
            if let block = existing[item.id] {
                block.clubName = item.trimmedClubName
                block.targetReps = item.targetReps
                block.note = item.storedNote
                block.order = order
            } else {
                let block = PlanBlock(
                    clubName: item.trimmedClubName, targetReps: item.targetReps, note: item.storedNote, order: order)
                block.id = item.id
                target.blocks.append(block)
            }
        }
        try context.save()
        return target
    }

    // Deep copy: new plan and block ids, same order, no sessions.
    @discardableResult
    static func duplicate(_ plan: PracticePlan, in context: ModelContext, now: Date = .now) throws -> PracticePlan {
        let copy = PracticePlan(
            name: "\(plan.name) copy",  // PLACEHOLDER: duplicate naming
            mode: plan.mode,
            isOrderMandatory: plan.isOrderMandatory,
            isStrictCount: plan.isStrictCount,
            createdAt: now
        )
        context.insert(copy)
        copy.blocks = plan.sortedBlocks.enumerated().map { order, block in
            PlanBlock(clubName: block.clubName, targetReps: block.targetReps, note: block.note, order: order)
        }
        try context.save()
        return copy
    }

    // Sessions keep their planName snapshot (nullify).
    static func delete(_ plan: PracticePlan, in context: ModelContext) throws {
        context.delete(plan)
        try context.save()
    }

    // Newest finished session's end; enum filtered in Swift (ADR 0013).
    static func lastDone(_ plan: PracticePlan) -> Date? {
        plan.sessions.filter { $0.status == .finished }.map { $0.endedAt ?? $0.startedAt }.max()
    }
}
