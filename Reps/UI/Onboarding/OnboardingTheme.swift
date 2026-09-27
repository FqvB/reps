import SwiftUI

// Onboarding values from Figma 07–09.
extension Theme.Typography {
    static let appMark = Font.system(size: 34, weight: .bold)
    static let onboardingIntro = Font.body
    static let illustrationCaption = Font.caption.weight(.medium)
}

extension Theme.Spacing {
    static let welcomeTop: CGFloat = 80
    static let welcomeGutter: CGFloat = 28
    static let welcomeGap: CGFloat = 28
    static let onboardingGap: CGFloat = 18
}

extension Theme.Radius {
    static let appMark: CGFloat = 22
    static let illustration: CGFloat = 20
    static let segment: CGFloat = 14
    static let segmentInner: CGFloat = 11
}
