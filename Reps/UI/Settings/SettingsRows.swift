import SwiftUI

// Figma 10: a small label over one grey card of rows.
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.settingsLabelGap) {
            Text(title)
                .font(Theme.Typography.footnoteMedium)
                .foregroundStyle(Theme.secondaryText)
            VStack(spacing: 0) { content }
                .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.row))
        }
    }
}

struct SettingsRowText: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.ink)
            if let subtitle {
                Text(subtitle)
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

// Title (and subtitle) left; grey value and chevron right.
struct SettingsRow: View {
    let title: String
    var subtitle: String?
    var value: String?
    var showsChevron = false

    var body: some View {
        HStack(spacing: 12) {
            SettingsRowText(title: title, subtitle: subtitle)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if let value {
                    Text(value)
                        .font(Theme.Typography.settingsValue)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
                if showsChevron {
                    Image(systemName: "chevron.right")  // PLACEHOLDER: Figma draws "›" as text
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.hairline)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.vertical, Theme.Spacing.settingsRowVertical)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}

struct SettingsToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            SettingsRowText(title: title, subtitle: subtitle)
        }
        .tint(Theme.accent)
        .padding(.horizontal, Theme.Spacing.cardPadding)
        .padding(.vertical, Theme.Spacing.settingsRowVertical)
    }
}

// Hairline inset to the row text.
struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 0.5)
            .padding(.leading, Theme.Spacing.cardPadding)
    }
}
