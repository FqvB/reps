import SwiftData
import SwiftUI

// Figma 06 Block editor (sheet). Edits a copy; Done hands it back.
struct BlockEditorSheet: View {
    let mode: PracticeMode
    let title: String
    let isNew: Bool
    let onDone: (BlockDraft) -> Void
    let onRemove: (BlockDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\BagClub.sortOrder), SortDescriptor(\BagClub.name)]) private var clubs: [BagClub]
    @State private var working: BlockDraft
    @State private var askCustomClub = false
    @State private var customClubName = ""

    init(
        block: BlockDraft, mode: PracticeMode, title: String, isNew: Bool,
        onDone: @escaping (BlockDraft) -> Void, onRemove: @escaping (BlockDraft) -> Void
    ) {
        self.mode = mode
        self.title = title
        self.isNew = isNew
        self.onDone = onDone
        self.onRemove = onRemove
        _working = State(initialValue: block)
    }

    private var bagNames: [String] { clubs.filter(\.isInBag).map(\.name) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.sheetGap) {
                HStack {
                    Text(title)
                        .font(Theme.Typography.sheetTitle)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    if !isNew {
                        Button("Remove") {
                            onRemove(working)
                            dismiss()
                        }
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.dangerText)
                        .buttonStyle(.plain)
                    }
                }
                sectionLabel("Club")
                if bagNames.isEmpty {
                    Text("Your bag is empty. Add clubs in Settings, or use Other…")  // PLACEHOLDER: empty-bag hint
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
                ClubPicker(
                    names: ClubChoices.names(bag: bagNames, current: working.clubName),
                    selection: $working.clubName,
                    onCustom: {
                        customClubName = ""
                        askCustomClub = true
                    }
                )
                sectionLabel(mode == .putting ? "Putts" : "Shots")
                RepsStepper(block: $working)
                FieldCard(label: "Note (optional)") {
                    TextField("e.g. 95 m, half swing", text: $working.note)  // PLACEHOLDER: note prompt
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.ink)
                }
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.top, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            FooterCTA(title: "Done", isEnabled: working.isValid) {
                onDone(working)
                dismiss()
            }
            .background(Theme.sheet)
        }
        .alert("Club name", isPresented: $askCustomClub) {  // PLACEHOLDER: custom club alert copy
            TextField("Club name", text: $customClubName)
            Button("Cancel", role: .cancel) {}
            Button("Use") {
                let name = customClubName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { working.clubName = name }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.sheet)
        .presentationCornerRadius(Theme.Radius.sheet)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.footnoteMedium)
            .foregroundStyle(Theme.secondaryText)
    }
}

struct ClubPicker: View {
    let names: [String]
    @Binding var selection: String
    let onCustom: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.rowGap), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: Theme.Spacing.rowGap) {
            ForEach(names, id: \.self) { name in
                Chip(title: name, isSelected: name == selection) { selection = name }
            }
            Chip(title: "Other…", isSelected: false, action: onCustom)  // PLACEHOLDER: custom club chip label
        }
    }
}

struct RepsStepper: View {
    @Binding var block: BlockDraft

    var body: some View {
        VStack(spacing: Theme.Spacing.sheetGap) {
            HStack(spacing: 12) {
                bigStep(-10)
                Text("\(block.targetReps)")
                    .font(Theme.Typography.stepperValue)
                    .tracking(Theme.Typography.stepperValueTracking)
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                bigStep(10)
            }
            HStack(spacing: Theme.Spacing.rowGap) {
                ForEach([-5, -1, 1, 5], id: \.self) { fineStep($0) }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .contain)
    }

    private func label(_ delta: Int) -> String { delta < 0 ? "−\(-delta)" : "+\(delta)" }

    private func canStep(_ delta: Int) -> Bool {
        var copy = block
        copy.adjustReps(by: delta)
        return copy.targetReps != block.targetReps
    }

    private func step(_ delta: Int) {
        withAnimation { block.adjustReps(by: delta) }
    }

    private func bigStep(_ delta: Int) -> some View {
        Button(label(delta)) { step(delta) }
            .font(Theme.Typography.stepperButton)
            .foregroundStyle(Theme.ink)
            .frame(width: 96, height: 64)
            .background(Theme.fill, in: .rect(cornerRadius: Theme.Radius.cta))
            .buttonStyle(.plain)
            .disabled(!canStep(delta))
    }

    private func fineStep(_ delta: Int) -> some View {
        Button(label(delta)) { step(delta) }
            .font(Theme.Typography.chip)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .overlay { Capsule().strokeBorder(Theme.hairline, lineWidth: 1.5) }
            .contentShape(.capsule)
            .buttonStyle(.plain)
            .disabled(!canStep(delta))
    }
}
