import SwiftUI

// TODO(#25): replace with the clip detail player (Figma 11).
struct ClipDetailPlaceholderView: View {
    let clip: LibraryClip

    var body: some View {
        ContentUnavailableView(
            LibraryDisplay.tileTitle(clip),
            systemImage: "play.rectangle",
            description: Text("The clip player comes in a later build.")  // PLACEHOLDER: clip detail copy
        )
        .navigationTitle(LibraryDisplay.tileDate(clip.timestamp))
        .navigationBarTitleDisplayMode(.inline)
    }
}
