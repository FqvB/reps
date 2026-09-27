import SwiftUI

// Bulk actions under the grid while selecting (§5.3b). No Figma frame: PLACEHOLDER: bulk bar design.
struct LibraryBulkBar: View {
    let clubs: [String]
    let isEnabled: Bool
    let favouriteTarget: Bool
    let onClub: (String) -> Void
    let onTags: () -> Void
    let onFavourite: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Menu {
                ForEach(clubs, id: \.self) { club in
                    Button(club) { onClub(club) }
                }
            } label: {
                Label("Club", systemImage: "figure.golf")
            }
            Spacer()
            Button(action: onTags) {
                Label("Tags", systemImage: "tag")
            }
            Spacer()
            Button(action: onFavourite) {
                Label(
                    favouriteTarget ? "Favourite" : "Unfavourite", systemImage: favouriteTarget ? "star" : "star.slash")
            }
            Spacer()
            Button(action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .tint(Theme.danger)
        }
        .labelStyle(.iconOnly)
        .font(.title3)
        .tint(Theme.accent)
        .disabled(!isEnabled)
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(Theme.background)
        .overlay(alignment: .top) { Divider() }
    }
}
