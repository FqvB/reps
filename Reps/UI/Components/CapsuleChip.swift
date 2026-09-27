import SwiftUI

// Capsule chip for the session club and tags (Figma 03); filled when selected, read-only without an action.
struct CapsuleChip: View {
    let title: String
    let isSelected: Bool
    var action: (() -> Void)?

    var body: some View {
        if let action {
            Button(action: action) { label }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            label
        }
    }

    private var label: some View {
        Text(title)
            .font(isSelected ? Theme.Typography.chipSelected : Theme.Typography.chip)
            .foregroundStyle(isSelected ? Color.white : Theme.secondaryText)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                if isSelected {
                    Capsule().fill(Theme.accent)
                } else {
                    Capsule().strokeBorder(Theme.hairline, lineWidth: 1.5)
                }
            }
            .contentShape(.capsule)
    }
}
