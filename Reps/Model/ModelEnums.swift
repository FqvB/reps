// Raw values are persisted and exported; never rename them.
nonisolated enum PracticeMode: String, Codable, CaseIterable, Sendable {
    case rangeCounter
    case rangeCounterWithClips
    case putting
}

nonisolated enum CameraAngle: String, Codable, CaseIterable, Sendable {
    case faceOn
    case downTheLine
    case none
}

nonisolated enum DetectionSource: String, Codable, CaseIterable, Sendable {
    case camera
    case manual
}

nonisolated enum SessionStatus: String, Codable, CaseIterable, Sendable {
    case active
    case finished
}
