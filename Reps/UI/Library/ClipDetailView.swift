import SwiftUI

// Figma 11 Clip detail, 15 delete alert (F27, §5.3b): dark full-bleed player with floating pills.
struct ClipDetailView: View {
    let clip: LibraryClip
    let tagSuggestions: [String]
    let onFavourite: (Bool) throws -> Void
    let onAddTag: (String) throws -> Void
    let onRemoveTag: (String) throws -> Void
    // Called after the user confirms; the library deletes once this screen has closed.
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var player = ClipPlayer()
    @State private var isTagSheetShown = false
    @State private var isDeleteAlertShown = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerLayerView(player: player.player)
                .ignoresSafeArea()
            if player.state == .missing { missingFile }
            VStack(spacing: 0) {
                topControls
                labelPill
                Spacer(minLength: 0)
                ClipScrubber(player: player, events: ClipPlayback.events(duration: player.duration))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                bottomControls
            }
        }
        .preferredColorScheme(.dark)
        .task(id: clip.id) {
            let url = clip.sessionID.flatMap {
                ClipStorage.clipURL(fileName: clip.clipFileName, sessionID: $0)
            }
            await player.load(url, filmstripCount: ClipDetailMetrics.filmstripFrames)
        }
        .onDisappear { player.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { player.pause() }
        }
        .sheet(isPresented: $isTagSheetShown) {
            LibraryTagSheet(
                selectedCount: 1,
                onSelection: clip.tags,
                suggestions: tagSuggestions,
                onAdd: { tag in run("Couldn't add the tag.") { try onAddTag(tag) } },  // PLACEHOLDER: error copy (#29)
                onRemove: { tag in run("Couldn't remove the tag.") { try onRemoveTag(tag) } }  // PLACEHOLDER
            )
            .preferredColorScheme(.light)
        }
        .alert("Delete this clip?", isPresented: $isDeleteAlertShown) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                player.stop()
                onDelete()
            }
        } message: {
            // PLACEHOLDER: Figma 15 copy; the shot row goes too (#24 delete path), see Q35.
            Text("The shot stays counted; only the video is removed.")
        }
        .alert(
            errorMessage ?? "",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        }
    }

    private var topControls: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(PlayerCircleButtonStyle(size: ClipDetailMetrics.topControl))
            .accessibilityLabel("Close")
            Spacer()
            HStack(spacing: 10) {
                Button {
                    run("Couldn't change the favourite.") { try onFavourite(!clip.isFavourite) }  // PLACEHOLDER (#29)
                } label: {
                    Image(systemName: clip.isFavourite ? "star.fill" : "star")
                        .foregroundStyle(clip.isFavourite ? Theme.favourite : .white)
                }
                .accessibilityLabel(clip.isFavourite ? "Unfavourite" : "Favourite")
                Button {
                    // TODO(#26): share sheet.
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(true)
                .accessibilityLabel("Share")
            }
            .buttonStyle(PlayerCircleButtonStyle(size: ClipDetailMetrics.topControl))
            Spacer()
            Menu {
                Button("Tags", systemImage: "tag") { isTagSheetShown = true }
                Button("Save to Photos", systemImage: "square.and.arrow.down") {
                    // TODO(#26): save to Photos.
                }
                .disabled(true)
                Button("Delete", systemImage: "trash", role: .destructive) { isDeleteAlertShown = true }
            } label: {
                Image(systemName: "ellipsis")
                    .font(Theme.Typography.playerIcon)
                    .foregroundStyle(.white)
                    .frame(width: ClipDetailMetrics.topControl, height: ClipDetailMetrics.topControl)
                    .background(Theme.playerPill, in: .circle)
            }
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var labelPill: some View {
        Text(ClipPlayback.label(clip))
            .font(Theme.Typography.playerLabel)
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.playerPill, in: .capsule)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 10)
    }

    private var bottomControls: some View {
        HStack(spacing: 10) {
            Button(player.speed.title) { player.cycleSpeed() }
                .font(Theme.Typography.playerSpeed)
                .foregroundStyle(.white)
                .frame(width: ClipDetailMetrics.speedWidth, height: ClipDetailMetrics.bottomControl)
                .background(Theme.playerPill, in: .capsule)
                .accessibilityLabel("Speed \(player.speed.title)")
            HStack {
                Button {
                    player.step(by: -1)
                } label: {
                    Image(systemName: "backward.frame")
                }
                .accessibilityLabel("Previous frame")
                Spacer()
                Button {
                    player.togglePlay()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                Spacer()
                Button {
                    player.step(by: 1)
                } label: {
                    Image(systemName: "forward.frame")
                }
                .accessibilityLabel("Next frame")
            }
            .font(Theme.Typography.playerStep)
            .foregroundStyle(.white)
            .buttonStyle(.plain)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
            .frame(height: ClipDetailMetrics.bottomControl)
            .background(Theme.playerPill, in: .capsule)
            Button {
                // TODO(#27): overlay options (pose skeleton, event marks).
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(PlayerCircleButtonStyle(size: ClipDetailMetrics.bottomControl))
            .disabled(true)
            .accessibilityLabel("Overlay options")
        }
        .disabled(player.state != .ready)
        .padding(.horizontal, 14)
    }

    private var missingFile: some View {
        VStack(spacing: 10) {
            Image(systemName: "video.slash")
                .font(.largeTitle)
            Text("This clip's video file is missing.")  // PLACEHOLDER: missing clip copy
                .font(Theme.Typography.body)
        }
        .foregroundStyle(.white.opacity(0.8))
        .accessibilityElement(children: .combine)
    }

    private func run(_ failure: String, _ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = failure
        }
    }
}

// Round translucent control (Figma 11 "Control ✕", "☆", "⇧", "⚙").
private struct PlayerCircleButtonStyle: ButtonStyle {
    let size: CGFloat
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.playerIcon)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.playerPill, in: .circle)
            .opacity(configuration.isPressed ? 0.7 : isEnabled ? 1 : 0.5)
    }
}

#if DEBUG
    #Preview("Missing file") {
        ClipDetailView(
            clip: LibraryClip(
                id: UUID(), timestamp: .now, clubName: "Gap wedge", tags: ["fade"], isFavourite: false, tempoRatio: 3.1,
                clipFileName: "missing.mov", sessionID: UUID(), sessionTitle: "Wedge day", sessionStartedAt: .now,
                angle: .faceOn),
            tagSuggestions: ["fade", "gate drill"],
            onFavourite: { _ in }, onAddTag: { _ in }, onRemoveTag: { _ in }, onDelete: {}
        )
    }
#endif
