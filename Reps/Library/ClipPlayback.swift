import Foundation

// F27 speeds; the pill cycles 1× → ½× → ¼× → 1×.
enum PlaybackSpeed: Double, CaseIterable {
    case full = 1
    case half = 0.5
    case quarter = 0.25

    var next: PlaybackSpeed {
        switch self {
        case .full: .half
        case .half: .quarter
        case .quarter: .full
        }
    }

    var title: String {
        switch self {
        case .full: "1×"
        case .half: "½×"
        case .quarter: "¼×"
        }
    }
}

enum ClipEventKind: CaseIterable {
    case address
    case top
    case impact
    case finish
}

struct ClipEvent: Equatable {
    let kind: ClipEventKind
    let seconds: Double
}

// Timeline math and copy for the clip detail player (F27, §5.3b). Times are seconds from the clip start.
enum ClipPlayback {
    // §5.6 captures at 60 fps; used when a track reports no frame rate.
    static let fallbackFrameRate = 60.0
    // PLACEHOLDER: §5.8 cuts [impact − 3 s, impact + 2 s], so impact is assumed 3 s in. TODO(#22): store the real offset.
    static let assumedImpactOffset = 3.0

    static func frameDuration(nominalFrameRate: Float) -> Double {
        let rate = Double(nominalFrameRate)
        return 1 / (rate.isFinite && rate > 0 ? rate : fallbackFrameRate)
    }

    // Moves `count` frames from the frame showing at `seconds`, clamped to the clip.
    // Returns the middle of the target frame so a zero-tolerance seek lands on it whatever the frame's exact timestamp.
    static func stepped(from seconds: Double, by count: Int, frameDuration: Double, duration: Double) -> Double {
        guard frameDuration > 0, duration > 0 else { return 0 }
        let lastFrame = max(0, Int((duration / frameDuration - 1e-6).rounded(.up)) - 1)
        let current = min(max(Int((seconds / frameDuration + 1e-6).rounded(.down)), 0), lastFrame)
        let target = min(max(current + count, 0), lastFrame)
        return min((Double(target) + 0.5) * frameDuration, duration)
    }

    // Play from the start when the playhead is on the last frame.
    static func isAtEnd(_ seconds: Double, frameDuration: Double, duration: Double) -> Bool {
        seconds >= duration - frameDuration
    }

    static func fraction(_ seconds: Double, duration: Double) -> Double {
        guard duration > 0 else { return 0 }
        return min(max(seconds / duration, 0), 1)
    }

    static func seconds(atFraction fraction: Double, duration: Double) -> Double {
        min(max(fraction, 0), 1) * max(duration, 0)
    }

    // "2.098"; POSIX formatting so the decimal point doesn't follow the locale.
    static func timeTitle(_ seconds: Double) -> String {
        String(format: "%.3f", max(seconds, 0))
    }

    // The middle of `count` equal slices, one filmstrip frame each.
    static func filmstripTimes(count: Int, duration: Double) -> [Double] {
        guard count > 0, duration > 0 else { return [] }
        let slice = duration / Double(count)
        return (0..<count).map { (Double($0) + 0.5) * slice }
    }

    // Marks on the track. TODO(#27): address, top and finish from the pose track that computes tempo.
    static func events(duration: Double, impactOffset: Double? = assumedImpactOffset) -> [ClipEvent] {
        guard let impactOffset, impactOffset > 0, impactOffset < duration else { return [] }
        return [ClipEvent(kind: .impact, seconds: impactOffset)]
    }

    // A tap within `tolerance` points of a mark jumps exactly to that event (F27 jump-to-event).
    static func snapped(
        _ seconds: Double, to events: [ClipEvent], duration: Double, trackWidth: Double, tolerance: Double
    ) -> Double {
        guard duration > 0, trackWidth > 0 else { return seconds }
        let nearest = events.min { abs($0.seconds - seconds) < abs($1.seconds - seconds) }
        guard let nearest, abs(nearest.seconds - seconds) / duration * trackWidth <= tolerance else { return seconds }
        return nearest.seconds
    }

    // "Gap wedge · face-on · tempo 3.1 : 1" (Figma 11 label pill).
    static func label(_ clip: LibraryClip) -> String {
        let title = LibraryDisplay.tileTitle(clip)
        guard let tempo = LibraryDisplay.tempo(clip.tempoRatio) else { return title }
        return "\(title) · tempo \(tempo) : 1"
    }
}
