import SwiftData
import SwiftUI

// F14: the free session's club chip. Picking a club closes the sheet; the controller starts a new block.
struct FreeClubSheet: View {
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\BagClub.sortOrder), SortDescriptor(\BagClub.name)]) private var clubs: [BagClub]
    @State private var selection: String
    @State private var askCustomClub = false
    @State private var customClubName = ""

    init(current: String, onPick: @escaping (String) -> Void) {
        self.onPick = onPick
        _selection = State(initialValue: current)
    }

    private var bagNames: [String] { clubs.filter(\.isInBag).map(\.name) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.sheetGap) {
                Text("Club")  // PLACEHOLDER: free-session club sheet title
                    .font(Theme.Typography.sheetTitle)
                    .foregroundStyle(Theme.ink)
                ClubPicker(
                    names: ClubChoices.names(bag: bagNames, current: selection),
                    selection: $selection,
                    onCustom: {
                        customClubName = ""
                        askCustomClub = true
                    }
                )
            }
            .padding(.horizontal, Theme.Spacing.gutter)
            .padding(.top, 20)
        }
        .onChange(of: selection) { _, club in
            onPick(club)
            dismiss()
        }
        .alert("Club name", isPresented: $askCustomClub) {  // PLACEHOLDER: custom club alert copy (same as #7)
            TextField("Club name", text: $customClubName)
            Button("Cancel", role: .cancel) {}
            Button("Use") {
                let name = customClubName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { selection = name }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.sheet)
        .presentationCornerRadius(Theme.Radius.sheet)
    }
}
