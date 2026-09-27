import SwiftData
import SwiftUI

// Figma 12. Shown in place of the session screen on End; the session stays active until Done (F23, F28).
struct SessionSummaryView: View {
    let summary: SessionSummary
    let onContinue: () -> Void
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                overall
                if !summary.rows.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(summary.rows) { SummaryRowView(row: $0) }
                    }
                }
                HStack(alignment: .top, spacing: 10) {
                    ForEach(summary.stats) { SummaryStatView(stat: $0) }
                }
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.top, 24)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) { footer }
        .background(Theme.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(SummaryDisplay.title)
                .font(Theme.Typography.largeTitle)
                .foregroundStyle(Theme.ink)
            Text(summary.subtitle)
                .font(Theme.Typography.summarySubtitle)
                .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    private var overall: some View {
        VStack(spacing: 2) {
            Text(summary.headline)
                .font(Theme.Typography.summaryHeadline)
                .tracking(Theme.Typography.summaryHeadlineTracking)
                .foregroundStyle(Theme.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(summary.caption)
                .font(Theme.Typography.summaryCaption)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.card))
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Text(SummaryDisplay.footnote)
                .font(Theme.Typography.summaryStatLabel)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Button("Continue session", action: onContinue)
                .buttonStyle(SecondaryButtonStyle())
            Button("Done", action: onDone)
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(.horizontal, Theme.Spacing.gutter)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Theme.background)
    }
}

private struct SummaryRowView: View {
    let row: SummaryRow

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title)
                    .font(Theme.Typography.summaryRowTitle)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    Text(row.detail)
                        .foregroundStyle(Theme.secondaryText)
                    if let percent = row.percent {
                        Text(percent)
                            .font(Theme.Typography.summaryRowPercent)
                            .foregroundStyle(row.isOverTarget ? Theme.accent : Theme.ink)
                    }
                }
                .font(Theme.Typography.detail)
                .monospacedDigit()
            }
            if let bar = row.bar {
                SummaryBarView(bar: bar)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// 6 pt track: accent up to the target, darker surplus past it (Figma 12).
private struct SummaryBarView: View {
    let bar: SummaryBar

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.card)
                Capsule().fill(Theme.accent).frame(width: width * bar.fill)
                if let from = bar.surplusFrom {
                    Capsule().fill(Theme.accentDeep)
                        .frame(width: width * (1 - from))
                        .offset(x: width * from)
                }
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

private struct SummaryStatView: View {
    let stat: SummaryStat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stat.value)
                .font(Theme.Typography.summaryStatValue)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(stat.label)
                .font(Theme.Typography.summaryStatLabel)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 12)
        .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.stat))
        .accessibilityElement(children: .combine)
    }
}

extension SummaryBlock {
    init(_ result: BlockResult) {
        self.init(
            order: result.order, clubName: result.clubName, note: result.block?.note, tags: result.tags,
            counted: result.repsCounted, manualAdjust: result.repsManualAdjust, target: result.targetReps,
            clipCount: result.shots.count { $0.clipFileName != nil }, tempos: result.shots.compactMap(\.tempoRatio))
    }
}

#Preview {
    SessionSummaryView(
        summary: SummaryDisplay.summary(
            planName: "Wedge day", mode: .rangeCounterWithClips,
            blocks: [
                SummaryBlock(
                    order: 0, clubName: "Pitching wedge", note: nil, tags: [], counted: 40, manualAdjust: 0,
                    target: 40, clipCount: 40, tempos: [3.0]),
                SummaryBlock(
                    order: 1, clubName: "Gap wedge", note: nil, tags: [], counted: 42, manualAdjust: 3, target: 30,
                    clipCount: 45, tempos: []),
                SummaryBlock(
                    order: 2, clubName: "9 iron", note: nil, tags: [], counted: 12, manualAdjust: 0, target: 30,
                    clipCount: 12, tempos: []),
            ],
            elapsed: 48 * 60),
        onContinue: {}, onDone: {})
}
