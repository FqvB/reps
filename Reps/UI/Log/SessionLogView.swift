import SwiftData
import SwiftUI

// Session log (F8). No Figma frame: cards follow 01 Plans, the detail follows 12 Summary (Q33).
struct SessionLogView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PracticeSession.startedAt, order: .reverse) private var sessions: [PracticeSession]
    @State private var selected: PracticeSession?
    @State private var sessionToDelete: PracticeSession?
    @State private var errorMessage: String?

    var body: some View {
        // ADR 0006: finished sessions only; the enum is filtered in memory (ADR 0013).
        let finished = sessions.filter { $0.status == .finished }
        let byID = Dictionary(finished.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let sections = SessionLogDisplay.sections(finished.map(LogEntry.init))
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        LogCard(row: row) { selected = byID[row.id] }
                            .logRow()
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                // No destructive role: the row must stay until the alert is confirmed.
                                Button("Delete") { sessionToDelete = byID[row.id] }
                                    .tint(Theme.danger)
                            }
                    }
                } header: {
                    Text(section.title)
                        .font(Theme.Typography.footnoteMedium)
                        .foregroundStyle(Theme.secondaryText)
                        .textCase(nil)
                }
                .listSectionSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .overlay {
            if sections.isEmpty {
                ContentUnavailableView(
                    "No sessions yet",  // PLACEHOLDER: empty log copy
                    systemImage: "clock",
                    description: Text("Finished sessions show up here.")
                )
            }
        }
        .navigationTitle("Session log")
        .navigationDestination(item: $selected) { session in
            SessionLogDetailView(session: session)
        }
        .alert(
            "Delete this session?",
            isPresented: Binding(get: { sessionToDelete != nil }, set: { if !$0 { sessionToDelete = nil } }),
            presenting: sessionToDelete
        ) { session in
            Button("Delete", role: .destructive) { delete(session) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its shots and clips are deleted too.")  // PLACEHOLDER: delete-session alert copy
        }
        .alert(
            errorMessage ?? "",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        }
    }

    private func delete(_ session: PracticeSession) {
        do {
            // TODO(#22): pass the real ClipFileRemoving once clips exist.
            try SessionLog.delete(session, in: context, clipFiles: NoClipFiles())
        } catch {
            errorMessage = "Couldn't delete the session."  // PLACEHOLDER: error copy (#29)
        }
    }
}

private struct LogCard: View {
    let row: LogRow
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.title)
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(Theme.ink)
                    Text(row.subtitle)
                        .font(Theme.Typography.detail)
                        .foregroundStyle(Theme.secondaryText)
                    Text(row.detail)
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                if let percent = row.percent {
                    Text(percent)
                        .font(Theme.Typography.value)
                        .monospacedDigit()
                        .foregroundStyle(row.isComplete ? Theme.accent : Theme.ink)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.hairline)
            }
            .padding(.leading, 20)
            .padding(.trailing, 16)
            .padding(.vertical, 18)
            .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.card))
            .contentShape(.rect(cornerRadius: Theme.Radius.card))
        }
        .buttonStyle(.plain)
    }
}

extension LogEntry {
    init(_ session: PracticeSession) {
        self.init(
            id: session.id,
            planName: session.planName,
            mode: session.mode,
            cameraAngle: session.cameraAngle,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            blocks: session.blockResults.map(LogBlock.init)
        )
    }
}

extension LogBlock {
    init(_ result: BlockResult) {
        self.init(
            order: result.order,
            clubName: result.clubName,
            note: result.block?.note,
            tags: result.tags,
            counted: result.repsCounted,
            manualAdjust: result.repsManualAdjust,
            target: result.targetReps,
            clipCount: result.shots.filter { $0.clipFileName != nil }.count
        )
    }
}

extension View {
    // Same card-row insets as the plans list.
    fileprivate func logRow() -> some View {
        listRowInsets(
            EdgeInsets(
                top: Theme.Spacing.cardGap / 2, leading: Theme.Spacing.gutter,
                bottom: Theme.Spacing.cardGap / 2, trailing: Theme.Spacing.gutter)
        )
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

#if DEBUG
    extension PreviewData {
        // The plans container plus one finished session per plan, a few days apart.
        static func logContainer() -> ModelContainer {
            let made = container()
            let context = made.mainContext
            let plans = (try? context.fetch(FetchDescriptor<PracticePlan>())) ?? []
            for (index, plan) in plans.enumerated() {
                let start = Date.now.addingTimeInterval(-Double(index + 1) * 3 * 86_400)
                let angle: CameraAngle = plan.mode == .putting ? .none : .faceOn
                let session = PracticeSession(plan: plan, mode: plan.mode, cameraAngle: angle, startedAt: start)
                context.insert(session)
                for block in plan.sortedBlocks {
                    let result = BlockResult(block: block, order: block.order)
                    result.repsManualAdjust = max(0, block.targetReps - 5 * block.order)
                    session.blockResults.append(result)
                }
                session.status = .finished
                session.endedAt = start.addingTimeInterval(48 * 60)
            }
            return made
        }
    }

    #Preview {
        NavigationStack { SessionLogView() }
            .modelContainer(PreviewData.logContainer())
    }
#endif
