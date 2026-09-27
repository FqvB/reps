import SwiftUI

// Session log sizes. No Figma frame: values follow 12 Session summary (docs/design.md).
extension Theme.Typography {
    static let logHeadline = Font.system(size: 64, weight: .bold, design: .rounded)
    static let logHeadlineTracking: CGFloat = -1.92
    static let logCaption = Font.system(size: 15, weight: .medium)
    static let logModeLine = Font.system(size: 15)
    static let logRowTitle = Font.system(size: 15, weight: .semibold)
    static let logRowDetail = Font.system(size: 14)
    static let logRowPercent = Font.system(size: 14, weight: .semibold)
    static let logStatValue = Font.system(size: 20, weight: .semibold)
    static let logStatLabel = Font.system(size: 12)
}

extension Theme.Radius {
    static let logStat: CGFloat = 14
}
