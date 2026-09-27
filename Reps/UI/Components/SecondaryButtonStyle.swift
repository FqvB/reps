import SwiftUI

// Full-width grey CTA (Continue session, Figma 12).
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.cta)
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.cta))
            .contentShape(.rect(cornerRadius: Theme.Radius.cta))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
