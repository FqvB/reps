import SwiftData
import SwiftUI

// One finished session: overall completion, per-block results, stats (F8). Styled after Figma 12.
struct SessionLogDetailView: View {
    let session: PracticeSession

    var body: some View {
        let detail = SessionLogDisplay.detail(LogEntry(session))
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 2) {
                    Text(detail.headline)
                        .font(Theme.Typography.logHeadline)
                        .tracking(Theme.Typography.logHeadlineTracking)
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(detail.caption)
                        .font(Theme.Typography.logCaption)
                        .foregroundStyle(Theme.ink)
                    Text(detail.modeLine)
                        .font(Theme.Typography.logModeLine)
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.card))
                // TODO(#11 follow-up): reuse the summary's block row with its progress bar.
                VStack(spacing: 14) {
                    ForEach(detail.rows) { row in
                        LogBlockLine(row: row)
                    }
                }
                HStack(spacing: 10) {
                    ForEach(detail.stats) { stat in
                        LogStatTile(stat: stat)
                    }
                }
                // TODO(#24): open this session's clips in the library. TODO(#26): Save to Photos per clip (§5.8).
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle(SessionDisplay.title(planName: session.planName))
        .navigationSubtitle(detail.dateLine)
    }
}

private struct LogBlockLine: View {
    let row: LogBlockRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(row.title)
                .font(Theme.Typography.logRowTitle)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(row.detail)
                .font(Theme.Typography.logRowDetail)
                .foregroundStyle(Theme.secondaryText)
            if let percent = row.percent {
                Text(percent)
                    .font(Theme.Typography.logRowPercent)
                    .foregroundStyle(row.isOverTarget ? Theme.accent : Theme.ink)
            }
        }
        .monospacedDigit()
    }
}

private struct LogStatTile: View {
    let stat: LogStat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stat.value)
                .font(Theme.Typography.logStatValue)
                .foregroundStyle(Theme.ink)
            Text(stat.label)
                .font(Theme.Typography.logStatLabel)
                .foregroundStyle(Theme.secondaryText)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 12)
        .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.logStat))
    }
}

#if DEBUG
    #Preview {
        let container = PreviewData.logContainer()
        let session = try! container.mainContext.fetch(FetchDescriptor<PracticeSession>()).first!
        return NavigationStack { SessionLogDetailView(session: session) }
            .modelContainer(container)
    }
#endif
