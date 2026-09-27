import SwiftUI

// "+  New plan" / "+  Add block".
struct DashedAddButton: View {
    let title: String
    var font: Font = Theme.Typography.rowTitle
    var verticalPadding: CGFloat = 18
    var cornerRadius: CGFloat = Theme.Radius.cta
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("+  \(title)")
                .font(font)
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, verticalPadding)
                .contentShape(.rect(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }
        }
        .buttonStyle(.plain)
    }
}
