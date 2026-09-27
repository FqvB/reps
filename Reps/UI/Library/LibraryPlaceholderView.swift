import SwiftUI

// TODO(#24): replace with the video library.
struct LibraryPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Library",
                systemImage: "film.stack",
                description: Text("Your clips will show up here.")  // PLACEHOLDER: library empty copy
            )
            .navigationTitle("Library")
        }
    }
}
