import SwiftUI

// Figma 11 scrubber panel: filmstrip with a yellow playhead, then time, event track and overlay toggle.
struct ClipScrubber: View {
    let player: ClipPlayer
    let events: [ClipEvent]

    var body: some View {
        VStack(spacing: 10) {
            filmstrip
            HStack(spacing: 12) {
                Text(ClipPlayback.timeTitle(player.currentTime))
                    .font(Theme.Typography.playerTime)
                    .foregroundStyle(.white)
                    .accessibilityLabel("\(ClipPlayback.timeTitle(player.currentTime)) seconds")
                track
                Button {
                    // TODO(#27): pose overlay toggle.
                } label: {
                    Image(systemName: "figure.stand")
                        .font(Theme.Typography.playerIcon)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(true)
                .opacity(0.5)
                .accessibilityLabel("Pose overlay")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.playerPill, in: .rect(cornerRadius: ClipDetailMetrics.panelRadius))
        .disabled(player.state != .ready)
    }

    private var fraction: Double {
        ClipPlayback.fraction(player.currentTime, duration: player.duration)
    }

    private var filmstrip: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            HStack(spacing: ClipDetailMetrics.filmstripGap) {
                ForEach(0..<ClipDetailMetrics.filmstripFrames, id: \.self) { index in
                    Theme.thumbnail
                        .overlay {
                            if let image = player.filmstrip.indices.contains(index) ? player.filmstrip[index] : nil {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            }
                        }
                        .clipShape(.rect(cornerRadius: ClipDetailMetrics.frameRadius))
                }
            }
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.favourite)
                    .frame(
                        width: ClipDetailMetrics.playheadWidth,
                        height: ClipDetailMetrics.filmstripHeight + 2 * ClipDetailMetrics.playheadOverhang
                    )
                    .offset(x: fraction * max(width - ClipDetailMetrics.playheadWidth, 0))
            }
            .contentShape(.rect)
            .gesture(scrubGesture(width: width, inset: 0, snaps: false))
        }
        .frame(height: ClipDetailMetrics.filmstripHeight)
        .accessibilityElement()
        .accessibilityLabel("Filmstrip")
        .accessibilityValue(ClipPlayback.timeTitle(player.currentTime))
        .accessibilityAdjustableAction { direction in
            player.step(by: direction == .increment ? 1 : -1)
        }
    }

    private var track: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let knobX = fraction * max(width - ClipDetailMetrics.knob, 0)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.playerTrack)
                    .frame(height: ClipDetailMetrics.trackHeight)
                Capsule()
                    .fill(Theme.favourite)
                    .frame(width: knobX + ClipDetailMetrics.knob / 2, height: ClipDetailMetrics.trackHeight)
                ForEach(events, id: \.seconds) { event in
                    Rectangle()
                        .fill(event.kind == .impact ? Theme.danger : .white)
                        .frame(width: ClipDetailMetrics.markWidth, height: ClipDetailMetrics.markHeight)
                        .offset(x: markX(event, width: width))
                }
                Circle()
                    .fill(Theme.favourite)
                    .frame(width: ClipDetailMetrics.knob, height: ClipDetailMetrics.knob)
                    .offset(x: knobX)
            }
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(scrubGesture(width: width, inset: ClipDetailMetrics.knob / 2, snaps: true))
        }
        .frame(height: ClipDetailMetrics.knob)
        .accessibilityHidden(true)
    }

    private func markX(_ event: ClipEvent, width: CGFloat) -> CGFloat {
        let usable = max(width - ClipDetailMetrics.knob, 0)
        return ClipPlayback.fraction(event.seconds, duration: player.duration) * usable + ClipDetailMetrics.knob / 2
            - ClipDetailMetrics.markWidth / 2
    }

    // Drag or tap to scrub; on the track a release near an event mark jumps exactly to it.
    private func scrubGesture(width: CGFloat, inset: CGFloat, snaps: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                player.scrub(to: seconds(at: value.location.x, width: width, inset: inset))
            }
            .onEnded { value in
                let seconds = seconds(at: value.location.x, width: width, inset: inset)
                guard snaps else { return player.endScrub(at: seconds) }
                player.endScrub(
                    at: ClipPlayback.snapped(
                        seconds, to: events, duration: player.duration,
                        trackWidth: Double(max(width - ClipDetailMetrics.knob, 0)),
                        tolerance: Double(ClipDetailMetrics.markTapTolerance)))
            }
    }

    // `inset` keeps the knob's centre inside the track.
    private func seconds(at x: CGFloat, width: CGFloat, inset: CGFloat) -> Double {
        let usable = max(width - 2 * inset, 1)
        return ClipPlayback.seconds(atFraction: Double((x - inset) / usable), duration: player.duration)
    }
}
