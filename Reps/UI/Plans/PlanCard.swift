import SwiftUI

struct PlanCard: View {
    let plan: PracticePlan
    let onOpen: () -> Void
    let onStart: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.name)
                        .font(Theme.Typography.cardTitle)
                        .foregroundStyle(Theme.ink)
                    Text(
                        PlanSummary.subtitle(
                            blockCount: plan.blocks.count,
                            totalReps: plan.blocks.reduce(0) { $0 + $1.targetReps },
                            mode: plan.mode,
                            isOrderMandatory: plan.isOrderMandatory
                        )
                    )
                    .font(Theme.Typography.detail)
                    .foregroundStyle(Theme.secondaryText)
                    Text(PlanSummary.lastDone(PlanLibrary.lastDone(plan), now: .now))
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Button("Start", action: onStart)
                .buttonStyle(PillButtonStyle(kind: .neutral))
                .disabled(plan.blocks.isEmpty)
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .padding(.vertical, 18)
        .background(Theme.card, in: .rect(cornerRadius: Theme.Radius.card))
    }
}

struct FreeSessionCard: View {
    let onStart: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Free session")
                    .font(Theme.Typography.cardTitleLarge)
                    .foregroundStyle(.white)
                Text("Count and record without a plan")
                    .font(Theme.Typography.detail)
                    .foregroundStyle(Theme.onAccentSecondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Start", action: onStart)
                .buttonStyle(PillButtonStyle(kind: .onAccent))
        }
        .padding(.leading, 20)
        .padding(.trailing, 18)
        .padding(.vertical, 18)
        .background(Theme.accent, in: .rect(cornerRadius: Theme.Radius.card))
    }
}
