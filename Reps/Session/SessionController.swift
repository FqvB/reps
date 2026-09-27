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
    @ObservationIgnored private var handlers: [(SessionEvent) -> Void] = []
    // Set by a strict auto-advance so an immediate −1 undoes into the block that just ended.
    @ObservationIgnored private var autoAdvancedFrom: BlockResult?

    init(context: ModelContext, clipFiles: any ClipFileRemoving = NoClipFiles(), now: @escaping () -> Date = { .now }) {
        self.context = context
        self.clipFiles = clipFiles
        self.now = now
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
        handlers.append(handler)
    }

    func start(plan: PracticePlan, cameraAngle: CameraAngle) throws {
        guard session == nil else { throw SessionError.sessionInProgress }
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
        guard session == nil else { throw SessionError.sessionInProgress }
        let newSession = PracticeSession(plan: nil, mode: mode, cameraAngle: cameraAngle, startedAt: now())
        context.insert(newSession)
        let block = BlockResult(clubName: clubName, tags: tags, order: 0)
        newSession.blockResults = [block]
        session = newSession
        activeTags = tags
        activate(block)
    }

    // The session to offer in the "resume?" prompt at launch: the newest active one.
    static func activeSession(in context: ModelContext) throws -> PracticeSession? {
        let active = SessionStatus.active
        var descriptor = FetchDescriptor<PracticeSession>(
            predicate: #Predicate { $0.status == active },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func resume(_ saved: PracticeSession) throws {
        guard session == nil else { throw SessionError.sessionInProgress }
        guard saved.status == .active else { throw SessionError.notActive }
        session = saved
        let block = saved.activeBlockOrder.flatMap { order in saved.blockResults.first { $0.order == order } }
        activeTags = block?.tags ?? []
        activate(block)
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
        save()
        let done = block.tally.done
        emit(.countChanged(done: done, target: block.targetReps))
        guard let target = block.targetReps, target > 0, done == target else { return shot }
        emit(.targetReached(clubName: block.clubName, target: target, isStrict: session.isStrictCount))
        if session.isStrictCount {
            let next = nextBlock(after: block)
            autoAdvancedFrom = block
            activate(next)
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
        save()
        if let clipFileName {
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
        }
        session.status = .finished
        session.endedAt = now()
        session.activeBlockOrder = nil
        save()
        reset()
    }

    func discard() {
        guard let session else { return }
        let sessionID = session.id
        context.delete(session)
        save()
        clipFiles.removeClips(sessionID: sessionID)
        reset()
    }

    private func nextBlock(after current: BlockResult) -> BlockResult? {
        let all = blocks
        let later = all.filter { $0.order > current.order }
        if isOrderMandatory { return later.first }
        let earlier = all.filter { $0.order < current.order }
        return (later + earlier).first { !Completion.isComplete($0.tally) }
    }

    private func activate(_ block: BlockResult?) {
        activeBlock = block
        session?.activeBlockOrder = block?.order
        block?.tags = activeTags
        save()
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

    private func save() {
        do {
            try context.save()
            lastSaveError = nil
        } catch {
            lastSaveError = error
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
