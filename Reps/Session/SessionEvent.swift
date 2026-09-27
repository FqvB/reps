// What the session engine tells the voice layer (#10); plain values, no models.
nonisolated enum SessionEvent: Equatable, Sendable {
    // After every counted shot and every effective −1; `done` is that block's count.
    case countChanged(done: Int, target: Int?)
    // The count just reached the target. In a strict session the block ends here.
    case targetReached(clubName: String, target: Int, isStrict: Bool)
    // A block became the one being counted.
    case blockChanged(clubName: String, target: Int?, done: Int)
    // No block is left to run; shots are ignored until one is selected or the session ends.
    case planEnded
    // Done saved the session (§5.7 "Done. Session saved."); not sent when finish() discards or the save fails.
    case sessionSaved
}
