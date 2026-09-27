import SwiftUI

// TODO(#11): replace with the session summary (Figma 12, F23). Only Done finishes the session (F28).
struct SummaryPlaceholderView: View {
    let onKeepGoing: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.sectionGap) {
            ContentUnavailableView(
                "Session summary",
                systemImage: "checkmark.circle",
                description: Text("The full summary is coming.")  // PLACEHOLDER: summary screen (#11)
            )
            .frame(maxHeight: .infinity)
            Button("Done", action: onDone)
                .buttonStyle(PrimaryButtonStyle())
            Button("Keep going", action: onKeepGoing)
                .font(Theme.Typography.cta)
                .foregroundStyle(Theme.accent)
                .padding(.vertical, 12)
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.bottom, 8)
        .background(Theme.background)
        .interactiveDismissDisabled()
    }
}
