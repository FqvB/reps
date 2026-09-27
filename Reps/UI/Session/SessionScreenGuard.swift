import SwiftUI
import UIKit

// §5.3c: keeps the display awake while the session screen is up and dims it after 30 s without a touch.
// The first tap on a dimmed screen only wakes it, so a gloved tap can't hit +1 by accident.
private struct SessionScreenGuard: ViewModifier {
    // PLACEHOLDER: dim strength (black overlay; the spec gives no level)
    static let dimOpacity = 0.8

    @State private var isDimmed = false
    @State private var touches = 0

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(TapGesture().onEnded { touches += 1 })
            .overlay {
                if isDimmed {
                    Color.black
                        .opacity(Self.dimOpacity)
                        .ignoresSafeArea()
                        .contentShape(.rect)
                        .onTapGesture { wake() }
                        .accessibilityLabel("Screen dimmed")
                        .accessibilityHint("Tap to wake")
                        .accessibilityAddTraits(.isButton)
                        .transition(.opacity)
                }
            }
            .task(id: touches) {
                try? await Task.sleep(for: SessionDisplay.dimDelay)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.6)) { isDimmed = true }
            }
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func wake() {
        withAnimation(.easeInOut(duration: 0.2)) { isDimmed = false }
        touches += 1
    }
}

extension View {
    func sessionScreenGuard() -> some View {
        modifier(SessionScreenGuard())
    }
}
