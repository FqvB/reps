import SwiftData
import SwiftUI

// Figma 02 Plan editor + 13 discard alert. Edits a PlanDraft; only Save writes to the store.
struct PlanEditorView: View {
    private let plan: PracticePlan?
    private let original: PlanDraft

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var draft: PlanDraft
    @State private var editingBlock: BlockDraft?
    @State private var lastRemoved: RemovedBlock?
    @State private var confirmDiscard = false
    @State private var saveFailed = false

    init(plan: PracticePlan?) {
        self.plan = plan
        let draft = plan.map(PlanLibrary.draft(from:)) ?? PlanDraft()
        original = draft
        _draft = State(initialValue: draft)
    }

    private var hasChanges: Bool { draft != original }
    private var displayName: String { draft.trimmedName.isEmpty ? "This plan" : draft.trimmedName }

    var body: some View {
        NavigationStack {
            List {
                Group {
                    FieldCard(label: "Plan name") {
                        TextField("e.g. Wedge day", text: $draft.name)  // PLACEHOLDER: name prompt
                            .font(Theme.Typography.value)
                            .foregroundStyle(Theme.ink)
                            .submitLabel(.done)
                    }
                    Picker("Mode", selection: $draft.mode) {
                        ForEach(PracticeMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    ToggleRow(
                        title: "Order is mandatory",
                        subtitle: draft.isOrderMandatory
                            ? "On — blocks run in the order below"  // PLACEHOLDER: order on copy
                            : "Off — jump to any block during the session",
                        isOn: $draft.isOrderMandatory
                    )
                    ToggleRow(
                        title: "Strict count",
                        subtitle: draft.isStrictCount
                            ? "On — each block stops exactly at its target"  // PLACEHOLDER: strict on copy
                            : "Off — targets are minimums, keep hitting past them",
                        isOn: $draft.isStrictCount
                    )
                    HStack {
                        Text("Blocks")
                        Spacer()
                        Text(
                            PlanSummary.totals(
                                blockCount: draft.blocks.count, totalReps: draft.totalReps, mode: draft.mode))
                    }
                    .font(Theme.Typography.footnoteMedium)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 4)
                    .padding(.top, 6)
                }
                .editorRow(gap: Theme.Spacing.sectionGap)

                ForEach(draft.blocks) { block in
                    Button {
                        editingBlock = block
                    } label: {
                        BlockRow(
                            clubName: block.trimmedClubName,
                            detail: PlanSummary.blockDetail(
                                targetReps: block.targetReps, note: block.storedNote, mode: draft.mode),
                            targetReps: block.targetReps
                        )
                    }
                    .buttonStyle(.plain)
                    .editorRow(gap: Theme.Spacing.rowGap)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Delete", role: .destructive) { remove(block.id) }
                            .tint(Theme.danger)
                    }
                }
                .onMove { draft.moveBlocks(fromOffsets: $0, toOffset: $1) }

                DashedAddButton(
                    title: "Add block",
                    font: Theme.Typography.pill,
                    verticalPadding: 16,
                    cornerRadius: Theme.Radius.row
                ) {
                    editingBlock = BlockDraft(clubName: "")
                }
                .editorRow(gap: Theme.Spacing.sectionGap)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle(plan == nil ? "New plan" : "Edit plan")  // PLACEHOLDER: "New plan" title
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges { confirmDiscard = true } else { dismiss() }
                    }
                    .tint(Theme.secondaryText)
                }
            }
            .safeAreaInset(edge: .bottom) {
                FooterCTA(title: "Save plan", isEnabled: draft.canSave, action: save) {
                    if let removed = lastRemoved {
                        UndoToast(message: "\(removed.block.trimmedClubName) removed") {
                            withAnimation {
                                draft.restore(removed)
                                lastRemoved = nil
                            }
                        }
                    }
                }
            }
            .undoToastTimer($lastRemoved)
            .sheet(item: $editingBlock) { block in
                let index = draft.index(of: block.id)
                BlockEditorSheet(
                    block: block,
                    mode: draft.mode,
                    title: index.map { "Block \($0 + 1)" } ?? "New block",  // PLACEHOLDER: "New block" title
                    isNew: index == nil,
                    onDone: { draft.upsert($0) },
                    onRemove: { remove($0.id) }
                )
            }
            .alert("Discard changes?", isPresented: $confirmDiscard) {
                Button("Keep editing", role: .cancel) {}
                Button("Discard", role: .destructive) { dismiss() }
            } message: {
                Text("\(displayName) has unsaved changes.")
            }
            .alert("Couldn't save the plan.", isPresented: $saveFailed) {  // PLACEHOLDER: save error copy (#29)
                Button("OK", role: .cancel) {}
            }
        }
    }

    private func remove(_ id: UUID) {
        withAnimation {
            if let removed = draft.removeBlock(id: id) { lastRemoved = removed }
        }
    }

    private func save() {
        do {
            try PlanLibrary.save(draft, to: plan, in: context)
            dismiss()
        } catch {
            saveFailed = true
        }
    }
}

extension View {
    fileprivate func editorRow(gap: CGFloat) -> some View {
        listRowInsets(
            EdgeInsets(top: gap / 2, leading: Theme.Spacing.gutter, bottom: gap / 2, trailing: Theme.Spacing.gutter)
        )
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

#Preview {
    let container = PreviewData.container()
    let plan = try? container.mainContext.fetch(FetchDescriptor<PracticePlan>()).first
    PlanEditorView(plan: plan)
        .modelContainer(container)
}
