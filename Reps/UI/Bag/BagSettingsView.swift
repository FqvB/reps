import SwiftData
import SwiftUI

// Settings → My bag: the bag grid plus a Reorder sheet for picker order.
struct BagSettingsView: View {
    @State private var reordering = false

    var body: some View {
        ScrollView {
            BagEditorView()
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.top, 8)
                .padding(.bottom, 20)
        }
        .background(Theme.background)
        .navigationTitle("My bag")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reorder") { reordering = true }  // PLACEHOLDER: reorder entry (not in Figma)
                    .tint(Theme.accent)
            }
        }
        .sheet(isPresented: $reordering) { BagOrderSheet() }
    }
}

// Drag the in-bag clubs into picker order.
struct BagOrderSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: [SortDescriptor(\BagClub.sortOrder), SortDescriptor(\BagClub.name)]) private var clubs: [BagClub]
    @State private var failed = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(clubs.filter(\.isInBag)) { club in
                    Text(club.name)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.ink)
                }
                .onMove { source, destination in
                    do {
                        try BagLibrary.move(fromOffsets: source, toOffset: destination, in: context)
                    } catch {
                        failed = true
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Bag order")  // PLACEHOLDER: reorder sheet title
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .tint(Theme.accent)
                }
            }
            .alert("Couldn't save the order.", isPresented: $failed) {  // PLACEHOLDER: error copy (#29)
                Button("OK", role: .cancel) {}
            }
        }
    }
}

#Preview {
    NavigationStack { BagSettingsView() }
        .modelContainer(PreviewData.container())
}
