import SwiftUI

// Grey card with a small label over an input ("Plan name", "Note (optional)").
struct FieldCard<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(Theme.Typography.label)
                .foregroundStyle(Theme.secondaryText)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.vertical, 12)
        .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.row))
    }
}
