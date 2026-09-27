import SwiftData
import SwiftUI

@main
struct RepsApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try RepsStore.makeContainer()
        } catch {
            // No recovery path yet; error handling lands with #29.
            fatalError("Failed to open the SwiftData store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
