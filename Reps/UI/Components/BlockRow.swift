import SwiftUI

// One plan block: handle, club, detail, target, chevron.
struct BlockRow: View {
    let clubName: String
    let detail: String
    let targetReps: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")  // PLACEHOLDER: drag handle glyph (Figma "≡")
                .font(.system(size: 17))
                .foregroundStyle(Theme.hairline)
            VStack(alignment: .leading, spacing: 2) {
                Text(clubName)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            Text("\(targetReps)")
                .font(Theme.Typography.value)
                .foregroundStyle(Theme.accent)
            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.hairline)
        }
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .padding(.vertical, 14)
        .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.row))
        .contentShape(.rect(cornerRadius: Theme.Radius.row))
    }
}
