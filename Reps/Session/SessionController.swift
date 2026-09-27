import Foundation
import Observation
import SwiftData

enum SessionError: Error, Equatable {
    case sessionInProgress
    case emptyPlan
    case notActive
}

@MainActor
@Observable
final class SessionController {
    private(set) var session: PracticeSession?
    private(set) var activeBlock: BlockResult?
    private(set) var activeTags: [String] = []
    private(set) var lastSaveError: (any Error)?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let clipFiles: any ClipFileRemoving
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let saveHook: () throws -> Void
    @ObservationIgnored private var handlers: [(SessionEvent) -> Void] = []
    // Set by a strict auto-advance so an immediate −1 undoes into the block that just ended.
    @ObservationIgnored private var autoAdvancedFrom: BlockResult?

    // saveHook defaults to context.save(); tests inject a failing one to check save-gated cleanup.
    init(
        context: ModelContext, clipFiles: any ClipFileRemoving = NoClipFiles(), now: @escaping () -> Date = { .now },
        saveHook: (() throws -> Void)? = nil
    ) {
        self.context = context
        self.clipFiles = clipFiles
        self.now = now
        self.saveHook = saveHook ?? { try context.save() }
    }

    var blocks: [BlockResult] { session?.sortedBlockResults ?? [] }
    var isFreeSession: Bool { session?.isFreeSession ?? false }
    var isStrictCount: Bool { session?.isStrictCount ?? false }
    var isOrderMandatory: Bool { session?.isOrderMandatory ?? false }
    var canSelectBlocks: Bool { session != nil && !isFreeSession && !isOrderMandatory }

    var isPlanComplete: Bool {
        let targeted = blocks.filter { ($0.targetReps ?? 0) > 0 }
        return !targeted.isEmpty && targeted.allSatisfy { Completion.isComplete($0.tally) }
    }

    func addEventHandler(_ handler: @escaping (SessionEvent) -> Void) {
        // Handlers run synchronously inside emit(); they must not call back into the controller.
        handlers.append(handler)
    }

    func start(plan: PracticePlan, cameraAngle: CameraAngle) throws {
        guard session == nil, try Self.activeSession(in: context) == nil else { throw SessionError.sessionInProgress }
        // A plan fetched via another context must be re-owned before it can be attached to this session.
        let plan = plan.modelContext === context ? plan : (context.model(for: plan.persistentModelID) as! PracticePlan)
        let planBlocks = plan.sortedBlocks
        guard !planBlocks.isEmpty else { throw SessionError.emptyPlan }
        let newSession = PracticeSession(plan: plan, mode: plan.mode, cameraAngle: cameraAngle, startedAt: now())
        context.insert(newSession)
        // One result per plan block up front, so skipped blocks count against completion.
        newSession.blockResults = planBlocks.enumerated().map { BlockResult(block: $1, order: $0) }
        session = newSession
        activeTags = []
        activate(newSession.sortedBlockResults.first)
    }

    func startFree(mode: PracticeMode, cameraAngle: CameraAngle, clubName: String, tags: [String] = []) throws {
        guard session == nil, try Self.activeSession(in: context) == nil else { throw SessionError.sessionInProgress }
        let newSession = PracticeSession(plan: nil, mode: mode, cameraAngle: cameraAngle, startedAt: now())
        context.insert(newSession)
        let block = BlockResult(clubName: clubName, tags: tags, order: 0)
        newSession.blockResults = [block]
        session = newSession
        activeTags = tags
        activate(block)
    }

    // The session to offer in the "resume?" prompt at launch: the newest active one.
    // Filtered in Swift, not #Predicate: comparing to a captured enum constant isn't supported on this SDK.
    static func activeSession(in context: ModelContext) throws -> PracticeSession? {
        let descriptor = FetchDescriptor<PracticeSession>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        return try context.fetch(descriptor).first { $0.status == .active }
    }

    func resume(_ saved: PracticeSession) throws {
        guard session == nil else { throw SessionError.sessionInProgress }
        guard saved.status == .active else { throw SessionError.notActive }
        // A session fetched via a different context must be re-owned so this controller's saves reach the store.
        let resumed =
            saved.modelContext === context ? saved : (context.model(for: saved.persistentModelID) as! PracticeSession)
        session = resumed
        let sorted = resumed.sortedBlockResults
        var block = resumed.activeBlockOrder.flatMap { order in sorted.first { $0.order == order } }
        // A stale activeBlockOrder with no matching block falls back to the first incomplete one.
        if block == nil, resumed.activeBlockOrder != nil {
            block = sorted.first { !Completion.isComplete($0.tally) }
        }
        // A strict session killed right after completing its active block finishes the advance now.
        if resumed.isStrictCount, let current = block, Completion.isComplete(current.tally) {
            block = nextBlock(after: current)
        }
        activeTags = block?.tags ?? sorted.last?.tags ?? []
        setActive(block)
        save()
        emitActivation(block)
    }

    @discardableResult
    func recordShot(source: DetectionSource) -> ShotRecord? {
        guard let session, let block = activeBlock else { return nil }
        if session.isStrictCount && Completion.isComplete(block.tally) { return nil }
        autoAdvancedFrom = nil
        let shot = ShotRecord(timestamp: now(), detectedBy: source, clubName: block.clubName, tags: activeTags)
        context.insert(shot)
        block.shots.append(shot)
        switch source {
        case .camera: block.repsCounted += 1
        case .manual: block.repsManualAdjust += 1
        }
        let done = block.tally.done
        let target = block.targetReps
        let justCompleted = target.map { $0 > 0 && done == $0 } ?? false
        let didAdvance = justCompleted && session.isStrictCount
        var advancedTo: BlockResult?
        if didAdvance {
            advancedTo = nextBlock(after: block)
            autoAdvancedFrom = block
            setActive(advancedTo)
        }
        // One save for the shot and, when it completes a strict block, the advance together.
        save()
        emit(.countChanged(done: done, target: block.targetReps))
        if justCompleted, let target {
            emit(.targetReached(clubName: block.clubName, target: target, isStrict: session.isStrictCount))
            if didAdvance {
                emitActivation(advancedTo)
            }
        }
        return shot
    }

    // Q21: removes the latest shot and its clip when there is one; −1 is always a manual correction.
    func minusOne() {
        guard let session, let block = autoAdvancedFrom ?? activeBlock else { return }
        autoAdvancedFrom = nil
        guard block.tally.done > 0 else { return }
        let latest = block.sortedShots.last
        let clipFileName = latest?.clipFileName
        if let latest {
            block.shots.removeAll { $0 === latest }
            context.delete(latest)
        }
        block.repsManualAdjust -= 1
        if save(), let clipFileName {
            clipFiles.removeClip(fileName: clipFileName, sessionID: session.id)
        }
        emit(.countChanged(done: block.tally.done, target: block.targetReps))
        if block !== activeBlock {
            activate(block)
        }
    }

    // Next block; before target this is a skip (the UI confirms first, F28).
    func advance() {
        guard let session, !session.isFreeSession, let block = activeBlock else { return }
        autoAdvancedFrom = nil
        activate(nextBlock(after: block))
    }

    // Block strip jump; refused in free sessions, when order is mandatory, or onto a finished strict block.
    @discardableResult
    func select(_ block: BlockResult) -> Bool {
        guard let session, !session.isFreeSession, !session.isOrderMandatory,
            block.session === session, block !== activeBlock
        else { return false }
        if session.isStrictCount && Completion.isComplete(block.tally) { return false }
        autoAdvancedFrom = nil
        activate(block)
        return true
    }

    // Free session club chip: a new block starts unless the current one is still unused.
    func setClub(_ clubName: String) {
        guard let session, session.isFreeSession, let block = activeBlock, clubName != block.clubName else { return }
        autoAdvancedFrom = nil
        if isUnused(block) {
            block.clubName = clubName
            activate(block)
        } else {
            startFreeBlock(clubName: clubName)
        }
    }

    // Tags apply to every following shot until changed (F16) and carry across blocks.
    func setTags(_ tags: [String]) {
        guard let session, Set(tags) != Set(activeTags) else { return }
        autoAdvancedFrom = nil
        activeTags = tags
        guard let block = activeBlock else { return }
        if session.isFreeSession && !isUnused(block) {
            startFreeBlock(clubName: block.clubName)
        } else {
            block.tags = tags
            save()
        }
    }

    // Done on the summary (#11); planned sessions keep skipped blocks, free sessions drop unused ones.
    func finish() {
        guard let session else { return }
        if session.isFreeSession {
            for block in session.blockResults where isUnused(block) {
                session.blockResults.removeAll { $0 === block }
                context.delete(block)
            }
            // Nothing left to show: a free session with every block dropped is not worth keeping.
            if session.blockResults.isEmpty {
                discard()
                return
            }
        }
        session.status = .finished
        session.endedAt = now()
        session.activeBlockOrder = nil
        let saved = save()
        reset()
        // Only a session that really reached the store is announced as saved (§5.7).
        if saved { emit(.sessionSaved) }
    }

    func discard() {
        guard let session else { return }
        let sessionID = session.id
        context.delete(session)
        if save() {
            clipFiles.removeClips(sessionID: sessionID)
        }
        reset()
    }

    private func nextBlock(after current: BlockResult) -> BlockResult? {
        let all = blocks
        let later = all.filter { $0.order > current.order }
        if isOrderMandatory { return later.first }
        let earlier = all.filter { $0.order < current.order }
        // A block with no positive target can never complete on its own; skip it so free order keeps moving.
        return (later + earlier).first { block in
            guard let target = block.targetReps, target > 0 else { return false }
            return !Completion.isComplete(block.tally)
        }
    }

    private func activate(_ block: BlockResult?) {
        setActive(block)
        save()
        emitActivation(block)
    }

    private func setActive(_ block: BlockResult?) {
        activeBlock = block
        session?.activeBlockOrder = block?.order
        block?.tags = activeTags
    }

    private func emitActivation(_ block: BlockResult?) {
        if let block {
            emit(.blockChanged(clubName: block.clubName, target: block.targetReps, done: block.tally.done))
        } else {
            emit(.planEnded)
        }
    }

    private func startFreeBlock(clubName: String) {
        guard let session else { return }
        let order = (session.blockResults.map(\.order).max() ?? -1) + 1
        let block = BlockResult(clubName: clubName, tags: activeTags, order: order)
        session.blockResults.append(block)
        activate(block)
    }

    private func isUnused(_ block: BlockResult) -> Bool {
        block.shots.isEmpty && block.repsCounted == 0 && block.repsManualAdjust == 0
    }

    @discardableResult
    private func save() -> Bool {
        do {
            try saveHook()
            lastSaveError = nil
            return true
        } catch {
            lastSaveError = error
            return false
        }
    }

    private func emit(_ event: SessionEvent) {
        for handler in handlers { handler(event) }
    }

    private func reset() {
        session = nil
        activeBlock = nil
        activeTags = []
        autoAdvancedFrom = nil
    }
}
