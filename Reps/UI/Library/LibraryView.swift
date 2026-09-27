import SwiftData
import SwiftUI

// Figma 04 Library (F15, F16, §5.3b).
struct LibraryView: View {
    // TODO(#22): pass the real ClipFileRemoving once clips exist.
    var clipFiles: any ClipFileRemoving = NoClipFiles()

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    // Q23: only this predicate runs in SQLite; tags, angle and the rest are filtered in memory.
    @Query(filter: #Predicate<ShotRecord> { $0.clipFileName != nil }, sort: \ShotRecord.timestamp, order: .reverse)
    private var shots: [ShotRecord]
    @Query(sort: [SortDescriptor(\BagClub.sortOrder), SortDescriptor(\BagClub.name)]) private var bag: [BagClub]
    @State private var filter = LibraryFilter()
    @State private var detail: LibraryClip?
    @State private var detailDeleteID: UUID?
    @State private var isSelecting = false
    @State private var selection: Set<UUID> = []
    @State private var pendingDelete: Set<UUID> = []
    @State private var lastUndo: LibraryUndo?
    @State private var isTagSheetShown = false
    @State private var errorMessage: String?

    var body: some View {
        let all = shots.compactMap(LibraryClip.init)
        let clips = LibraryDisplay.visible(all, filter: filter, hidden: pendingDelete)
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        NavigationStack {
            ScrollView {
                LibraryFilterBar(
                    filter: $filter,
                    clubs: LibraryDisplay.clubOptions(all, bag: bag.map(\.name)),
                    tags: LibraryDisplay.tagOptions(all),
                    months: LibraryDisplay.monthOptions(all),
                    sessions: LibraryDisplay.sessionOptions(all)
                )
                Text(LibraryDisplay.countTitle(clips.count))
                    .font(Theme.Typography.resultCount)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 4)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.gridGap), count: 2),
                    spacing: Theme.Spacing.gridGap
                ) {
                    ForEach(clips) { clip in
                        ClipTile(clip: clip, isSelecting: isSelecting, isSelected: selection.contains(clip.id))
                            .onTapGesture { tap(clip) }
                            .onLongPressGesture { startSelecting(with: clip.id) }
                    }
                }
                .padding(.horizontal, Theme.Spacing.gutter)
                .padding(.top, 4)
                .padding(.bottom, 12)
            }
            .background(Theme.background)
            .overlay { emptyState(hasClips: !all.isEmpty, hasResults: !clips.isEmpty) }
            .navigationTitle(isSelecting ? LibraryDisplay.countTitle(selection.count) : "Library")
            .navigationBarTitleDisplayMode(isSelecting ? .inline : .large)
            .searchable(
                text: $filter.searchText, placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search clubs, tags, dates"
            )
            .toolbar { toolbar(visible: clips) }
            .toolbar(isSelecting ? .hidden : .automatic, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    if let lastUndo {
                        UndoToast(message: lastUndo.message) { undo(lastUndo) }
                            .padding(.horizontal, Theme.Spacing.gutter)
                    }
                    if isSelecting {
                        let selected = selection.compactMap { byID[$0] }
                        LibraryBulkBar(
                            clubs: ClubChoices.names(bag: bag.filter(\.isInBag).map(\.name), current: ""),
                            isEnabled: !selection.isEmpty,
                            favouriteTarget: LibraryDisplay.favouriteTarget(selected),
                            onClub: { club in apply("Moved") { try LibraryEdits.setClub(club, on: $0, in: context) } },
                            onTags: { isTagSheetShown = true },
                            onFavourite: {
                                let value = LibraryDisplay.favouriteTarget(selected)
                                apply(value ? "Favourited" : "Unfavourited") {
                                    try LibraryEdits.setFavourite(value, on: $0, in: context)
                                }
                            },
                            onDelete: deleteSelection
                        )
                    }
                }
            }
            .undoToastTimer($lastUndo)
            .fullScreenCover(item: $detail, onDismiss: commitDetailDelete) { item in
                ClipDetailView(
                    clip: byID[item.id] ?? item,
                    tagSuggestions: LibraryDisplay.tagOptions(all),
                    onFavourite: { value in
                        try editDetail(item.id) { try LibraryEdits.setFavourite(value, on: $0, in: context) }
                    },
                    onAddTag: { tag in try editDetail(item.id) { try LibraryEdits.addTag(tag, to: $0, in: context) } },
                    onRemoveTag: { tag in
                        try editDetail(item.id) { try LibraryEdits.removeTag(tag, from: $0, in: context) }
                    },
                    onDelete: {
                        detailDeleteID = item.id
                        detail = nil
                    }
                )
            }
            .sheet(isPresented: $isTagSheetShown) {
                let selected = selection.compactMap { byID[$0] }
                LibraryTagSheet(
                    selectedCount: selected.count,
                    onSelection: LibraryDisplay.tagOptions(selected),
                    suggestions: LibraryDisplay.tagOptions(all),
                    onAdd: { tag in apply("Tagged") { try LibraryEdits.addTag(tag, to: $0, in: context) } },
                    onRemove: { tag in apply("Untagged") { try LibraryEdits.removeTag(tag, from: $0, in: context) } }
                )
            }
            .alert(
                errorMessage ?? "",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            }
        }
        .tint(Theme.accent)
        // The toast expired (or was replaced): the hidden clips are deleted for real now.
        .onChange(of: lastUndo?.id) { _, new in
            if new == nil { commitPendingDelete() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { finishUndo() }
        }
        .onDisappear { finishUndo() }
    }

    @ToolbarContentBuilder
    private func toolbar(visible: [LibraryClip]) -> some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .topBarLeading) {
                let allSelected = !visible.isEmpty && Set(visible.map(\.id)).isSubset(of: selection)
                Button(allSelected ? "Deselect All" : "Select All") {
                    selection = allSelected ? [] : Set(visible.map(\.id))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { stopSelecting() }
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Select") { isSelecting = true }
                    .disabled(visible.isEmpty)
            }
        }
    }

    @ViewBuilder
    private func emptyState(hasClips: Bool, hasResults: Bool) -> some View {
        if !hasClips {
            ContentUnavailableView(
                "No clips yet",  // PLACEHOLDER: library empty copy
                systemImage: "film.stack",
                description: Text("Clips from Range + clips sessions show up here.")
            )
        } else if !hasResults {
            if filter.hasChipFilters {
                ContentUnavailableView {
                    Label("No matching clips", systemImage: "line.3.horizontal.decrease.circle")  // PLACEHOLDER
                } description: {
                    Text("Every filter has to match.")  // PLACEHOLDER: no-results copy
                } actions: {
                    Button("Clear filters") { filter = LibraryFilter(searchText: filter.searchText) }
                }
            } else {
                ContentUnavailableView.search(text: filter.searchText)
            }
        }
    }

    private func tap(_ clip: LibraryClip) {
        guard isSelecting else {
            // Opening a clip ends any undo window, so a later Undo can't overwrite edits made in the player.
            finishUndo()
            detail = clip
            return
        }
        if selection.contains(clip.id) { selection.remove(clip.id) } else { selection.insert(clip.id) }
    }

    // §5.3b: long-press starts bulk mode with that clip selected.
    private func startSelecting(with id: UUID) {
        isSelecting = true
        selection.insert(id)
    }

    private func stopSelecting() {
        isSelecting = false
        selection = []
    }

    private func selectedShots() -> [ShotRecord] {
        shots.filter { selection.contains($0.id) && !pendingDelete.contains($0.id) }
    }

    // Runs one bulk edit on the selection and offers Undo; selection mode stays on for the next edit.
    private func apply(_ verb: String, _ edit: ([ShotRecord]) throws -> [ShotSnapshot]) {
        finishUndo()
        let targets = selectedShots()
        guard !targets.isEmpty else { return }
        do {
            let snapshots = try edit(targets)
            guard !snapshots.isEmpty else { return }
            withAnimation {
                lastUndo = LibraryUndo(
                    message: LibraryDisplay.undoMessage(verb, count: snapshots.count), kind: .restore(snapshots))
            }
        } catch {
            errorMessage = "Couldn't change the clips."  // PLACEHOLDER: error copy (#29)
        }
    }

    // Hidden now, deleted when the toast goes away without Undo (§5.3c). No alert: Undo is the safety net.
    private func deleteSelection() {
        finishUndo()
        let ids = Set(selectedShots().map(\.id))
        guard !ids.isEmpty else { return }
        pendingDelete = ids
        stopSelecting()
        withAnimation {
            lastUndo = LibraryUndo(message: LibraryDisplay.undoMessage("Deleted", count: ids.count), kind: .delete(ids))
        }
    }

    // Player edits (Figma 11): one shot, saved at once, no toast; the player shows its own error.
    private func editDetail(_ id: UUID, _ edit: ([ShotRecord]) throws -> [ShotSnapshot]) throws {
        let targets = shots.filter { $0.id == id }
        guard !targets.isEmpty else { return }
        _ = try edit(targets)
    }

    // Figma 15: confirmed in the player, so no Undo. Runs once the player has closed (same path as bulk delete).
    private func commitDetailDelete() {
        guard let id = detailDeleteID else { return }
        detailDeleteID = nil
        do {
            let deleted = try LibraryEdits.delete(ids: [id], in: context, clipFiles: clipFiles)
            Task { await ClipThumbnails.shared.remove(deleted) }
        } catch {
            errorMessage = "Couldn't delete the clip."  // PLACEHOLDER: error copy (#29)
        }
    }

    private func undo(_ undo: LibraryUndo) {
        switch undo.kind {
        case .delete:
            pendingDelete = []
        case .restore(let snapshots):
            do {
                try LibraryEdits.restore(snapshots, in: context)
            } catch {
                errorMessage = "Couldn't undo."  // PLACEHOLDER: error copy (#29)
            }
        }
        withAnimation { lastUndo = nil }
    }

    // Ends the undo window now: commits a pending delete and drops the toast.
    private func finishUndo() {
        commitPendingDelete()
        lastUndo = nil
    }

    private func commitPendingDelete() {
        guard !pendingDelete.isEmpty else { return }
        let ids = pendingDelete
        pendingDelete = []
        do {
            let deleted = try LibraryEdits.delete(ids: ids, in: context, clipFiles: clipFiles)
            Task { await ClipThumbnails.shared.remove(deleted) }
        } catch {
            errorMessage = "Couldn't delete the clips."  // PLACEHOLDER: error copy (#29)
        }
    }
}

#if DEBUG
    extension PreviewData {
        // Library sample: clips without files, so tiles show the missing-file placeholder.
        static func libraryContainer() -> ModelContainer {
            let made = container()
            let context = made.mainContext
            let session = PracticeSession(plan: nil, mode: .rangeCounterWithClips, cameraAngle: .faceOn)
            session.planName = "Wedge day"
            session.status = .finished
            context.insert(session)
            let block = BlockResult(clubName: "GW", tags: ["fade"], order: 0)
            context.insert(block)
            block.session = session
            for index in 0..<8 {
                let shot = ShotRecord(
                    timestamp: .now.addingTimeInterval(Double(-index) * 3_600 * 20), detectedBy: .camera,
                    clubName: index < 5 ? "GW" : "PW", tags: index.isMultiple(of: 3) ? ["fade"] : [])
                shot.tempoRatio = 2.9 + Double(index % 4) / 10
                shot.isFavourite = index == 0 || index == 3
                shot.clipFileName = "\(shot.id.uuidString).mov"
                context.insert(shot)
                shot.blockResult = block
            }
            return made
        }
    }

    #Preview {
        LibraryView()
            .modelContainer(PreviewData.libraryContainer())
    }
#endif
