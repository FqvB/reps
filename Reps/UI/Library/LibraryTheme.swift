import SwiftUI

// Library values from Figma 04 (docs/design.md).
extension Theme.Typography {
    static let filterChip = Font.system(size: 13, weight: .medium)
    static let filterChipSelected = Font.system(size: 13, weight: .semibold)
    static let resultCount = Font.system(size: 13, weight: .medium)
    static let tileTitle = Font.system(size: 13, weight: .semibold)
    static let tileDetail = Font.system(size: 12)
    static let tileTempo = Font.system(size: 12, weight: .semibold)
    static let tileStar = Font.system(size: 13)
    static let tilePlay = Font.system(size: 11)
}

extension Theme.Spacing {
    static let gridGap: CGFloat = 10
}

extension Theme.Radius {
    static let tile: CGFloat = 16
}

enum LibraryMetrics {
    static let thumbnailHeight: CGFloat = 120
    static let playSize: CGFloat = 28
}
