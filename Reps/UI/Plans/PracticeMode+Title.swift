extension PracticeMode {
    // Segment labels from Figma 02.
    var title: String {
        switch self {
        case .rangeCounter: "Range"
        case .rangeCounterWithClips: "Range + clips"
        case .putting: "Putting"
        }
    }
}
