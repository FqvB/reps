import AVFoundation
import ShotDetector

// Decodes a video file into VideoFrames the way the camera pipeline will deliver them:
// sampled to frameRate, scaled so the short side is shortSide, 420f pixels (DetectorInput).
struct VideoFrameReader {
    var url: URL
    var frameRate: Double? = DetectorInput.frameRate  // nil = every frame
    var shortSide: Int? = DetectorInput.shortSide  // nil = native size

    enum ReadError: Error {
        case noVideoTrack(URL)
        case cannotRead(URL, (any Error)?)
    }

    // Calls body for every sampled frame, in order. Returns the presentation time of every
    // decoded frame (sampled or not), indexed by frame number, so labels can be put on the same clock.
    func read(_ body: (VideoFrame) throws -> Void) async throws -> [Double] {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ReadError.noVideoTrack(url)
        }
        let (naturalSize, transform) = try await track.load(.naturalSize, .preferredTransform)
        let orientation = Self.orientation(from: transform)

        var settings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: DetectorInput.pixelFormat]
        if let shortSide,
            let size = DetectorInput.scaledSize(
                width: Int(naturalSize.width), height: Int(naturalSize.height), shortSide: shortSide)
        {
            settings[kCVPixelBufferWidthKey as String] = size.width
            settings[kCVPixelBufferHeightKey as String] = size.height
        }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw ReadError.cannotRead(url, reader.error) }

        var times: [Double] = []
        var sampler = frameRate.map { FrameSampler(frameRate: $0) }
        while let sample = output.copyNextSampleBuffer() {
            let time = sample.presentationTimeStamp.seconds
            // Only samples with an image buffer count as decoded frames, so an empty sample
            // can't shift the frame-number → timestamp mapping labels are put on.
            guard let pixelBuffer = sample.imageBuffer else { continue }
            times.append(time)
            guard sampler?.take(time) ?? true else { continue }
            try body(VideoFrame(pixelBuffer: pixelBuffer, time: time, orientation: orientation))
        }
        if reader.status == .failed { throw ReadError.cannotRead(url, reader.error) }
        return times
    }

    // Same mapping as hitreg-ml's keypoint extractor, so pose coordinates match the training data.
    static func orientation(from transform: CGAffineTransform) -> CGImagePropertyOrientation {
        switch Int((atan2(transform.b, transform.a) * 180 / .pi).rounded()) {
        case 90: .right
        case -90: .left
        case 180, -180: .down
        default: .up
        }
    }
}
