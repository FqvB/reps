import SwiftUI

// Selectable grid chip (club picker); later screens reuse it for tags.
struct Chip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(isSelected ? Theme.Typography.chipSelected : Theme.Typography.chip)
                .foregroundStyle(isSelected ? Color.white : Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(isSelected ? Theme.accent : Theme.card, in: .rect(cornerRadius: Theme.Radius.chip))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
