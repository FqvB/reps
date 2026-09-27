import SwiftUI

// One grid cell (Figma 04 "Clip"): thumbnail with ★ and play mark, then club · angle, date · tempo, tags.
struct ClipTile: View {
    let clip: LibraryClip
    let isSelecting: Bool
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnail
            meta
        }
        .background(Theme.card)
        .clipShape(.rect(cornerRadius: Theme.Radius.tile))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: Theme.Radius.tile).strokeBorder(Theme.accent, lineWidth: 3)
            }
        }
        .contentShape(.rect(cornerRadius: Theme.Radius.tile))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var thumbnail: some View {
        ClipThumbnail(clip: clip)
            .frame(maxWidth: .infinity)
            .frame(height: LibraryMetrics.thumbnailHeight)
            .clipped()
            .overlay(alignment: .topTrailing) {
                if clip.isFavourite {
                    Text("★")
                        .font(Theme.Typography.tileStar)
                        .foregroundStyle(Theme.favourite)
                        .padding(8)
                        .accessibilityLabel("Favourite")
                }
            }
            .overlay(alignment: .topLeading) {
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Theme.accent : .white)
                        .background(Circle().fill(isSelected ? .white : .black.opacity(0.25)))
                        .padding(8)
                }
            }
    }

    private var meta: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LibraryDisplay.tileTitle(clip))
                .font(Theme.Typography.tileTitle)
                .foregroundStyle(Theme.ink)
            HStack(spacing: 4) {
                Text(LibraryDisplay.tileDate(clip.timestamp) + (clip.tempoRatio == nil ? "" : " ·"))
                    .font(Theme.Typography.tileDetail)
                    .foregroundStyle(Theme.secondaryText)
                if let tempo = LibraryDisplay.tempo(clip.tempoRatio) {
                    Text(tempo)
                        .font(Theme.Typography.tileTempo)
                        .foregroundStyle(Theme.accent)
                }
            }
            if let tags = LibraryDisplay.tagLine(clip.tags) {
                Text(tags)
                    .font(Theme.Typography.tileDetail)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}

// Thumbnail, or the plain Figma fill while loading; a missing clip file gets a slashed icon.
private struct ClipThumbnail: View {
    let clip: LibraryClip
    @State private var image: UIImage?
    @State private var isMissing = false

    var body: some View {
        ZStack {
            Theme.thumbnail
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
            if isMissing {
                Image(systemName: "video.slash")  // PLACEHOLDER: missing clip file tile
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.8))
                    .accessibilityLabel("Clip file missing")
            } else {
                Circle()
                    .fill(.black.opacity(0.45))
                    .frame(width: LibraryMetrics.playSize, height: LibraryMetrics.playSize)
                    .overlay {
                        Text("▶")
                            .font(Theme.Typography.tilePlay)
                            .foregroundStyle(.white)
                    }
                    .accessibilityHidden(true)
            }
        }
        .task(id: clip.id) {
            guard let sessionID = clip.sessionID,
                let url = ClipStorage.clipURL(fileName: clip.clipFileName, sessionID: sessionID)
            else {
                isMissing = true
                return
            }
            image = await ClipThumbnails.shared.image(shotID: clip.id, clipURL: url)
            isMissing = image == nil
        }
    }
}
