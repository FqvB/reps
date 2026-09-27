import SwiftUI

// Horizontal block chips under the nav (Figma 03, 05); tapping a selectable chip jumps to that block (F18).
struct BlockStrip: View {
    let chips: [StripChip]
    let onSelect: (Int) -> Void

    private var activeID: Int? { chips.first { $0.state == .active }?.id }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.rowGap) {
                    ForEach(chips) { chip in
                        Button {
                            onSelect(chip.id)
                        } label: {
                            StripChipLabel(chip: chip)
                        }
                        .buttonStyle(.plain)
                        // Not .disabled: that would grey out the active chip.
                        .allowsHitTesting(chip.isSelectable)
                        .accessibilityAddTraits(chip.state == .active ? .isSelected : [])
                        .id(chip.id)
                    }
                }
                .padding(.horizontal, Theme.Spacing.gutter)
            }
            .onChange(of: activeID, initial: true) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }
}

private struct StripChipLabel: View {
    let chip: StripChip

    var body: some View {
        VStack(spacing: 1) {
            Text(chip.title)
                .font(Theme.Typography.stripTitle)
                .foregroundStyle(titleColor)
            Text(chip.detail)
                .font(Theme.Typography.stripDetail)
                .foregroundStyle(detailColor)
                .monospacedDigit()
        }
        .lineLimit(1)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(background, in: .rect(cornerRadius: Theme.Radius.stripChip))
        .accessibilityElement(children: .combine)
    }

    private var background: Color {
        switch chip.state {
        case .active: Theme.accent
        case .complete: Theme.fill
        case .pending: Theme.card
        }
    }

    private var titleColor: Color {
        switch chip.state {
        case .active: .white
        case .complete: Theme.secondaryText
        case .pending: Theme.ink
        }
    }

    private var detailColor: Color {
        chip.state == .active ? Theme.onAccentSecondary : Theme.secondaryText
    }
}
