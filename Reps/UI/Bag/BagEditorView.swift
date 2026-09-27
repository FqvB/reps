import SwiftData
import SwiftUI

// Figma 08 bag grid (F19). Every tap saves. Hosted by BagSettingsView and onboarding (#5).
struct BagEditorView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\BagClub.sortOrder), SortDescriptor(\BagClub.name)]) private var clubs: [BagClub]
    @State private var askNewClub = false
    @State private var newClubName = ""
    @State private var renaming: BagClub?
    @State private var renameText = ""
    @State private var errorMessage: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.rowGap), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sheetGap) {
            ForEach(BagCatalog.groups) { group in
                section(group.title) {
                    ForEach(group.clubs, id: \.self) { name in
                        let selected = isInBag(name)
                        Chip(title: chipTitle(name, selected), isSelected: selected) { setInBag(name, !selected) }
                    }
                }
            }
            let custom = clubs.filter { !BagCatalog.isStandard($0.name) }
            if !custom.isEmpty {
                section("Custom") {  // PLACEHOLDER: custom group title (not in Figma)
                    ForEach(custom) { club in
                        Chip(title: chipTitle(club.name, club.isInBag), isSelected: club.isInBag) {
                            setInBag(club.name, !club.isInBag)
                        }
                        .contextMenu {
                            Button("Rename") {
                                renameText = club.name
                                renaming = club
                            }
                            Button("Delete", role: .destructive) { delete(club) }
                        }
                    }
                }
            }
            DashedAddButton(
                title: "Add a custom club", font: Theme.Typography.pill, verticalPadding: 14, cornerRadius: 14
            ) {
                newClubName = ""
                askNewClub = true
            }
        }
        .alert("Add a club", isPresented: $askNewClub) {  // PLACEHOLDER: add club alert copy
            TextField("Club name", text: $newClubName)
            Button("Cancel", role: .cancel) {}
            Button("Add") { add() }
        }
        .alert(
            "Rename club",  // PLACEHOLDER: rename alert copy
            isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
            presenting: renaming
        ) { club in
            TextField("Club name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { rename(club) }
        }
        .alert(
            errorMessage ?? "",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.rowGap) {
            Text(title)
                .font(Theme.Typography.footnoteMedium)
                .foregroundStyle(Theme.secondaryText)
            LazyVGrid(columns: columns, spacing: Theme.Spacing.rowGap) { content() }
        }
    }

    private func chipTitle(_ name: String, _ selected: Bool) -> String {
        selected ? "✓ \(name)" : name
    }

    private func isInBag(_ name: String) -> Bool {
        BagLibrary.club(named: name, in: clubs)?.isInBag ?? false
    }

    private func setInBag(_ name: String, _ isInBag: Bool) {
        perform { try BagLibrary.setInBag(name, isInBag, in: context) }
    }

    private func add() {
        perform { try BagLibrary.addCustom(newClubName, in: context) }
    }

    private func rename(_ club: BagClub) {
        perform { try BagLibrary.rename(club, to: renameText, in: context) }
    }

    private func delete(_ club: BagClub) {
        perform { try BagLibrary.delete(club, in: context) }
    }

    private func perform(_ write: () throws -> Void) {
        do {
            try write()
        } catch BagLibrary.BagError.emptyName {
            return
        } catch BagLibrary.BagError.duplicateName {
            errorMessage = "That club is already in your bag."  // PLACEHOLDER: duplicate club copy
        } catch {
            errorMessage = "Couldn't save your bag."  // PLACEHOLDER: error copy (#29)
        }
    }
}
