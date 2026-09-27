import SwiftData
import SwiftUI

enum PlanEditorTarget: Identifiable {
    case new
    case edit(PracticePlan)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let plan): plan.id.uuidString
        }
    }

    var plan: PracticePlan? {
        if case .edit(let plan) = self { plan } else { nil }
    }
}

// Figma 01 Plans.
struct PlansView: View {
    let onStartPlan: (PracticePlan) -> Void
    let onStartFreeSession: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \PracticePlan.createdAt) private var plans: [PracticePlan]
    @State private var editing: PlanEditorTarget?
    @State private var planToDelete: PracticePlan?
    @State private var errorMessage: String?
    @State private var showsSettings = false
    @State private var showsLog = false

    var body: some View {
        NavigationStack {
            List {
                FreeSessionCard(onStart: onStartFreeSession)
                    .plansRow()
                ForEach(plans) { plan in
                    PlanCard(
                        plan: plan,
                        onOpen: { editing = .edit(plan) },
                        onStart: { onStartPlan(plan) }
                    )
                    .plansRow()
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        // No destructive role: the row must stay until the alert is confirmed.
                        Button("Delete") { planToDelete = plan }
                            .tint(Theme.danger)
                        Button("Duplicate") { duplicate(plan) }
                            .tint(Theme.accent)
                    }
                }
                DashedAddButton(title: "New plan") { editing = .new }
                    .plansRow()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Plans")
            .navigationSubtitle(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Log") { showsLog = true }  // PLACEHOLDER: session log entry label
                        .tint(Theme.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings") { showsSettings = true }
                        .tint(Theme.accent)
                }
            }
            .navigationDestination(isPresented: $showsSettings) { SettingsView() }
            .navigationDestination(isPresented: $showsLog) { SessionLogView() }
            .fullScreenCover(item: $editing) { target in
                PlanEditorView(plan: target.plan)
            }
            .alert(
                "Delete \(planToDelete?.name ?? "plan")?",
                isPresented: Binding(get: { planToDelete != nil }, set: { if !$0 { planToDelete = nil } }),
                presenting: planToDelete
            ) { plan in
                Button("Delete", role: .destructive) { delete(plan) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Its sessions stay in the log.")  // PLACEHOLDER: delete-plan alert copy
            }
            .alert(
                errorMessage ?? "",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private func duplicate(_ plan: PracticePlan) {
        do {
            try PlanLibrary.duplicate(plan, in: context)
        } catch {
            errorMessage = "Couldn't duplicate the plan."  // PLACEHOLDER: error copy (#29)
        }
    }

    private func delete(_ plan: PracticePlan) {
        do {
            try PlanLibrary.delete(plan, in: context)
        } catch {
            errorMessage = "Couldn't delete the plan."  // PLACEHOLDER: error copy (#29)
        }
    }
}

extension View {
    // Card rows draw their own background so they slide with the swipe.
    fileprivate func plansRow() -> some View {
        listRowInsets(
            EdgeInsets(
                top: Theme.Spacing.cardGap / 2, leading: Theme.Spacing.gutter,
                bottom: Theme.Spacing.cardGap / 2, trailing: Theme.Spacing.gutter)
        )
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

#Preview {
    PlansView(onStartPlan: { _ in }, onStartFreeSession: {})
        .modelContainer(PreviewData.container())
}
