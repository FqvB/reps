import AVFoundation
import Observation
import UIKit

// Drives one clip in the detail player (F27). UI layer only; ShotDetector never sees AVPlayer.
@Observable
final class ClipPlayer {
    enum State: Equatable {
        case loading
        case ready
        case missing
    }

    @ObservationIgnored let player = AVPlayer()
    private(set) var state = State.loading
    private(set) var duration = 0.0
    private(set) var frameDuration = ClipPlayback.frameDuration(nominalFrameRate: 0)
    private(set) var currentTime = 0.0
    private(set) var isPlaying = false
    private(set) var speed = PlaybackSpeed.full
    private(set) var filmstrip: [UIImage?] = []

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var isScrubbing = false

    // nil or a missing/undecodable file leaves the player in `.missing` (no clips exist before #22).
    func load(_ url: URL?, filmstripCount: Int) async {
        guard let url, FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            state = .missing
            return
        }
        let asset = AVURLAsset(url: url)
        guard let length = try? await asset.load(.duration), length.seconds.isFinite, length.seconds > 0,
            let track = try? await asset.loadTracks(withMediaType: .video).first
        else {
            state = .missing
            return
        }
        let rate = (try? await track.load(.nominalFrameRate)) ?? 0
        guard !Task.isCancelled else { return }
        duration = length.seconds
        frameDuration = ClipPlayback.frameDuration(nominalFrameRate: rate)
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
        player.defaultRate = Float(speed.rawValue)
        addTimeObserver()
        state = .ready
        filmstrip = await Self.frames(
            of: asset, at: ClipPlayback.filmstripTimes(count: filmstripCount, duration: duration))
    }

    func togglePlay() {
        guard state == .ready else { return }
        if isPlaying {
            pause()
            return
        }
        if ClipPlayback.isAtEnd(currentTime, frameDuration: frameDuration, duration: duration) { seek(to: 0) }
        player.defaultRate = Float(speed.rawValue)
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func cycleSpeed() {
        speed = speed.next
        player.defaultRate = Float(speed.rawValue)
        if isPlaying { player.rate = Float(speed.rawValue) }
    }

    func step(by count: Int) {
        guard state == .ready else { return }
        pause()
        seek(to: ClipPlayback.stepped(from: currentTime, by: count, frameDuration: frameDuration, duration: duration))
    }

    // Frame-accurate; a newer seek cancels an unfinished one, so dragging stays responsive on 5 s clips.
    func seek(to seconds: Double) {
        guard state == .ready else { return }
        currentTime = min(max(seconds, 0), duration)
        player.seek(
            to: CMTime(seconds: currentTime, preferredTimescale: 6_000), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func scrub(to seconds: Double) {
        if !isScrubbing {
            isScrubbing = true
            pause()
        }
        seek(to: seconds)
    }

    func endScrub(at seconds: Double) {
        seek(to: seconds)
        isScrubbing = false
    }

    func stop() {
        player.pause()
        isPlaying = false
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player.replaceCurrentItem(with: nil)
    }

    private func addTimeObserver() {
        guard timeObserver == nil else { return }
        // Also fires when playback starts or stops (e.g. at the end), which keeps `isPlaying` honest.
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
    }

    private func tick(_ seconds: Double) {
        isPlaying = player.rate != 0
        guard !isScrubbing, seconds.isFinite else { return }
        currentTime = min(max(seconds, 0), duration)
    }

    private static func frames(of asset: AVURLAsset, at times: [Double]) async -> [UIImage?] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 120, height: 120)  // PLACEHOLDER: filmstrip frame size
        var images = [UIImage?](repeating: nil, count: times.count)
        let requested = times.map { CMTime(seconds: $0, preferredTimescale: 6_000) }
        for await result in generator.images(for: requested) {
            guard let index = requested.firstIndex(of: result.requestedTime),
                let image = try? result.image
            else { continue }
            images[index] = UIImage(cgImage: image)
        }
        return images
    }
}
