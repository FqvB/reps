import SwiftUI

// Full-width green CTA (Save plan, Done).
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label(configuration: configuration)
    }

    private struct Label: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(Theme.Typography.cta)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Theme.accent, in: .rect(cornerRadius: Theme.Radius.cta))
                .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
        }
    }
}

// Footer area for `.safeAreaInset(edge: .bottom)`; `accessory` sits above the button (e.g. the undo toast).
struct FooterCTA<Accessory: View>: View {
    let title: String
    var isEnabled = true
    let action: () -> Void
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(spacing: Theme.Spacing.rowGap) {
            accessory
            Button(title, action: action)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!isEnabled)
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Theme.background)
    }
}

extension FooterCTA where Accessory == EmptyView {
    init(title: String, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.init(title: title, isEnabled: isEnabled, action: action) { EmptyView() }
    }
}
