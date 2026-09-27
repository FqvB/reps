import SwiftUI

// Session screen values from Figma 03, 05 and 14.
extension Theme.Typography {
    static let count = Font.system(size: 132, weight: .bold, design: .rounded)
    static let countTracking: CGFloat = -5.28
    static let countDetail = Font.body
    static let manualButton = Font.system(size: 28, weight: .semibold)
    static let stripTitle = Font.subheadline.weight(.semibold)
    static let stripDetail = Font.caption2.weight(.medium)
    static let navSubtitle = Font.caption
}

extension Theme.Radius {
    static let stripChip: CGFloat = 14
    static let preview: CGFloat = 20
}
