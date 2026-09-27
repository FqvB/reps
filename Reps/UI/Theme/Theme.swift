import SwiftUI

// Literal values from the Figma frames (no Figma variables exist); see docs/design.md.
enum Theme {
    static let background = Color(hex: 0xFFFFFF)
    static let ink = Color(hex: 0x17181A)
    static let secondaryText = Color(hex: 0x6F7175)
    static let accent = Color(hex: 0x2F6B4F)
    static let onAccentSecondary = Color(hex: 0xCFE3D8)
    static let card = Color(hex: 0xF2F2F0)
    static let fill = Color(hex: 0xE9E8E3)
    static let hairline = Color(hex: 0xD9D8D3)
    static let sheet = Color(hex: 0xF6F5F2)
    static let danger = Color(hex: 0xD0463D)
    static let dangerText = Color(hex: 0xB3413A)
    static let toastAction = Color(hex: 0x9FD3B7)
    static let accentDeep = Color(hex: 0x1E4A36)
    static let illustration = Color(hex: 0x8A9A84)
    static let ballBox = Color(hex: 0xE6D35A)

    enum Typography {
        static let largeTitle = Font.largeTitle.bold()
        static let value = Font.title2.weight(.semibold)
        static let sheetTitle = Font.title3.bold()
        static let cardTitleLarge = Font.title3.weight(.semibold)
        static let cardTitle = Font.system(size: 18, weight: .semibold)
        static let cta = Font.headline
        static let rowTitle = Font.callout.weight(.semibold)
        static let body = Font.callout
        static let pill = Font.subheadline.weight(.semibold)
        static let detail = Font.system(size: 14)
        static let chip = Font.system(size: 14, weight: .medium)
        static let chipSelected = Font.system(size: 14, weight: .semibold)
        static let footnote = Font.footnote
        static let footnoteMedium = Font.footnote.weight(.medium)
        static let label = Font.caption.weight(.medium)
        static let stepperValue = Font.system(size: 64, weight: .bold, design: .rounded)
        static let stepperValueTracking: CGFloat = -1.92
        static let stepperButton = Font.title2.weight(.semibold)
    }

    enum Spacing {
        static let gutter: CGFloat = 20
        static let cardGap: CGFloat = 12
        static let sectionGap: CGFloat = 14
        static let rowGap: CGFloat = 8
        static let sheetGap: CGFloat = 18
        static let cardPadding: CGFloat = 16
    }

    enum Radius {
        static let card: CGFloat = 20
        static let row: CGFloat = 16
        static let cta: CGFloat = 18
        static let toast: CGFloat = 14
        static let chip: CGFloat = 12
        static let sheet: CGFloat = 32
    }
}

extension Color {
    fileprivate init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
