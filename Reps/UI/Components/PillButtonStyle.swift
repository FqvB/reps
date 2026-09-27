import SwiftUI

// Small capsule "Start" button on cards.
struct PillButtonStyle: ButtonStyle {
    enum Kind {
        case onAccent
        case neutral
    }

    var kind: Kind = .neutral

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.pill)
            .foregroundStyle(kind == .onAccent ? Theme.accent : Theme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(kind == .onAccent ? Color.white : Theme.fill, in: .capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
