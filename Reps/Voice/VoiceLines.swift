import Foundation

// One spoken line. A count goes stale once a newer count arrives; a callout never does.
nonisolated struct Phrase: Equatable, Sendable {
    nonisolated enum Kind: Equatable, Sendable {
        case count
        case callout
    }

    let text: String
    let kind: Kind
}

// F6, §5.7: what the voice says for each session event. English only (Q12).
nonisolated enum VoiceLines {
    static let sessionSaved = "Done. Session saved."
    static let targetReached = "Target reached."  // PLACEHOLDER: minimums target callout (Q39)
    static let strictStop = "Stop. Block done."  // PLACEHOLDER: strict stop callout, F22 (Q39)
    static let planEnded = "End of plan."  // PLACEHOLDER: no-block-left callout (Q39)

    // announceCount silences only the count; block, stop and saved callouts always speak (Q40).
    static func phrases(for event: SessionEvent, announceCount: Bool) -> [Phrase] {
        switch event {
        case .countChanged(let done, _):
            // TODO(#27): add the tempo ("twelve, three point one", §5.3a) when announceTempo is on.
            return announceCount ? [Phrase(text: count(done), kind: .count)] : []
        case .targetReached(_, _, let isStrict):
            return [Phrase(text: isStrict ? strictStop : targetReached, kind: .callout)]
        case .blockChanged(let clubName, let target, let done):
            return [Phrase(text: block(clubName: clubName, target: target, done: done), kind: .callout)]
        case .planEnded:
            return [Phrase(text: planEnded, kind: .callout)]
        case .sessionSaved:
            return [Phrase(text: sessionSaved, kind: .callout)]
        }
    }

    // Digits, not words: the synthesizer reads "12" as "twelve".
    static func count(_ done: Int) -> String {
        "\(done)"
    }

    // §5.7 "Nine iron. Thirty reps."; a block with shots already on it says where it stands.
    static func block(clubName: String, target: Int?, done: Int) -> String {
        let club = spokenClub(clubName)
        guard let target, target > 0 else { return "\(club)." }
        if done > 0 {
            return "\(club). \(done) of \(target)."  // PLACEHOLDER: returning-block callout (Q39)
        }
        return "\(club). \(target) \(target == 1 ? "rep" : "reps")."
    }

    // The bag's short wedge names would otherwise be read letter by letter.
    static func spokenClub(_ name: String) -> String {
        switch BagCatalog.key(name) {
        case "pw": "Pitching wedge"
        case "gw": "Gap wedge"
        case "sw": "Sand wedge"
        case "lw": "Lob wedge"
        default: BagCatalog.trimmed(name)
        }
    }
}
