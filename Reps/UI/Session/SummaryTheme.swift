import SwiftUI

// Figma 12 values; the file has no variables.
extension Theme.Typography {
    static let summaryHeadline = Font.system(size: 88, weight: .bold, design: .rounded)
    static let summaryHeadlineTracking: CGFloat = -2.64
    static let summarySubtitle = Font.subheadline
    static let summaryCaption = Font.subheadline.weight(.medium)
    static let summaryRowTitle = Font.subheadline.weight(.semibold)
    static let summaryRowPercent = Font.system(size: 14, weight: .semibold)
    static let summaryStatValue = Font.title3.weight(.semibold)
    static let summaryStatLabel = Font.caption
}

extension Theme.Radius {
    static let stat: CGFloat = 14
}
