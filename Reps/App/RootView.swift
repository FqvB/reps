import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\BagClub.sortOrder), SortDescriptor(\BagClub.name)]) private var clubs: [BagClub]
    @State private var sessions: SessionController?
    @State private var pendingResume: PracticeSession?
    @State private var startFailed = false

    var body: some View {
        let isInSession = sessions?.session != nil
        TabView {
            Tab("Plans", systemImage: "list.bullet.rectangle") {  // PLACEHOLDER: Plans tab icon
                PlansView(onStartPlan: start(plan:), onStartFreeSession: startFree)
            }
            Tab("Library", systemImage: "film.stack") {  // PLACEHOLDER: Library tab icon
                LibraryPlaceholderView()
            }
        }
        .tint(Theme.accent)
        // Driven by the controller: finish() or discard() clears the session and closes the cover.
        .fullScreenCover(isPresented: Binding(get: { isInSession }, set: { _ in })) {
            if let sessions { SessionView(controller: sessions) }
        }
        .task { offerResume() }
        .alert(
            "Resume session?",  // PLACEHOLDER: resume prompt copy
            isPresented: Binding(get: { pendingResume != nil }, set: { if !$0 { pendingResume = nil } }),
            presenting: pendingResume
        ) { saved in
            Button("Resume") { resume(saved) }
            Button("End it") { endWithoutResuming(saved) }  // PLACEHOLDER: decline button copy
        } message: { saved in
            Text(
                SessionDisplay.resumeMessage(
                    title: SessionDisplay.title(planName: saved.planName),
                    done: saved.blockResults.reduce(0) { $0 + $1.tally.done },
                    mode: saved.mode))
        }
        .alert("Couldn't start the session.", isPresented: $startFailed) {  // PLACEHOLDER: start error copy (#29)
            Button("OK", role: .cancel) {}
        }
    }

    // One controller for the app's lifetime; it holds at most one session at a time.
    private func controller() -> SessionController {
        if let sessions { return sessions }
        let made = SessionController(context: modelContext)
        // TODO(#10): subscribe the speaker here, e.g. made.addEventHandler { speaker.handle($0) }.
        // TODO(#22): pass the real ClipFileRemoving once clips exist.
        sessions = made
        return made
    }

    private func start(plan: PracticePlan) {
        do {
            try controller().start(plan: plan, cameraAngle: AppSettings().cameraAngle(for: plan.mode))
        } catch {
            startFailed = true
        }
    }

    private func startFree() {
        let club = clubs.first(where: \.isInBag)?.name ?? "7 iron"  // PLACEHOLDER: free-session club with an empty bag
        do {
            // PLACEHOLDER: free sessions start in Range mode until there's a mode choice (Q28).
            try controller().startFree(
                mode: .rangeCounter, cameraAngle: AppSettings().cameraAngle(for: .rangeCounter), clubName: club)
        } catch {
            startFailed = true
        }
    }

    // §6: an active session found at launch (the app was killed) gets a "resume?" prompt.
    private func offerResume() {
        guard sessions?.session == nil else { return }
        pendingResume = try? SessionController.activeSession(in: modelContext)
    }

    private func resume(_ saved: PracticeSession) {
        do {
            try controller().resume(saved)
        } catch {
            startFailed = true
        }
    }

    // Q25 (planner default, unconfirmed): declining keeps the session as finished; delete it from the log later.
    private func endWithoutResuming(_ saved: PracticeSession) {
        let controller = controller()
        do {
            try controller.resume(saved)
            controller.finish()
        } catch {
            startFailed = true
        }
    }
}

#Preview {
    RootView()
        .modelContainer(PreviewData.container())
}
