import SwiftData
import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Plans", systemImage: "list.bullet.rectangle") {  // PLACEHOLDER: Plans tab icon
                PlansView(
                    onStartPlan: { _ in
                        // TODO(#9): start a session for this plan
                    },
                    onStartFreeSession: {
                        // TODO(#9): start a free session
                    }
                )
            }
            Tab("Library", systemImage: "film.stack") {  // PLACEHOLDER: Library tab icon
                LibraryPlaceholderView()
            }
        }
        .tint(Theme.accent)
    }
}

#Preview {
    RootView()
        .modelContainer(PreviewData.container())
}
