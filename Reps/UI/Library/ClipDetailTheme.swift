import SwiftUI

// Clip detail values from Figma 11 (the one dark screen, docs/design.md).
extension Theme {
    static let playerPill = Color.black.opacity(0.38)
    static let playerTrack = Color.white.opacity(0.35)
}

extension Theme.Typography {
    static let playerLabel = Font.system(size: 13, weight: .semibold)
    static let playerTime = Font.system(size: 20, weight: .semibold).monospacedDigit()
    static let playerSpeed = Font.system(size: 17, weight: .semibold)
    static let playerIcon = Font.system(size: 20)
    static let playerStep = Font.system(size: 22)
}

enum ClipDetailMetrics {
    static let topControl: CGFloat = 48
    static let bottomControl: CGFloat = 56
    static let speedWidth: CGFloat = 72
    static let panelRadius: CGFloat = 22
    static let filmstripFrames = 10
    static let filmstripHeight: CGFloat = 56
    static let filmstripGap: CGFloat = 3
    static let frameRadius: CGFloat = 3
    static let playheadWidth: CGFloat = 4
    static let playheadOverhang: CGFloat = 5
    static let trackHeight: CGFloat = 6
    static let markWidth: CGFloat = 2
    static let markHeight: CGFloat = 18
    static let knob: CGFloat = 20
    static let markTapTolerance: CGFloat = 12
}
