import CoreGraphics
import CoreVideo
import Foundation
import ShotDetector
import Testing

struct VideoFrameReaderTests {
    @Test(arguments: [
        (CGSize(width: 1920, height: 1080), 854, 480),
        (CGSize(width: 1080, height: 1920), 480, 854),
        (CGSize(width: 1280, height: 720), 854, 480),
    ])
    func scaledSizeKeepsAspectWithEvenSides(size: CGSize, width: Int, height: Int) throws {
        let scaled = try #require(VideoFrameReader.scaledSize(size, shortSide: 480))
        #expect(scaled.width == width)
        #expect(scaled.height == height)
    }

    @Test func smallVideoIsNotScaled() {
        #expect(VideoFrameReader.scaledSize(CGSize(width: 640, height: 480), shortSide: 480) == nil)
    }

    @Test func orientationFollowsRotation() {
        #expect(VideoFrameReader.orientation(from: .identity) == .up)
        #expect(VideoFrameReader.orientation(from: CGAffineTransform(rotationAngle: .pi / 2)) == .right)
        #expect(VideoFrameReader.orientation(from: CGAffineTransform(rotationAngle: -.pi / 2)) == .left)
        #expect(VideoFrameReader.orientation(from: CGAffineTransform(rotationAngle: .pi)) == .down)
    }

    @Test(.enabled(if: MLData.root != nil, "hitreg-ml not found; set REPS_ML_DIR"))
    func decodesDownscaledSampledFrames() async throws {
        // 59.94 fps, 1080×1920, 332 frames (data/manifest.csv).
        let url = try #require(MLData.root).appending(path: "data/raw/2025-07-16_uldis_dtl_cloud_1.mov")
        var frames: [(time: Double, width: Int, height: Int, format: OSType)] = []
        let times = try await VideoFrameReader(url: url).read { frame in
            frames.append(
                (
                    frame.time, CVPixelBufferGetWidth(frame.pixelBuffer), CVPixelBufferGetHeight(frame.pixelBuffer),
                    CVPixelBufferGetPixelFormatType(frame.pixelBuffer)
                ))
        }
        #expect(times.count == 332)
        #expect(zip(times, times.dropFirst()).allSatisfy { $0 < $1 })
        #expect(abs(frames.count - 332 / 4) <= 2)  // 15 of 59.94 fps
        #expect(frames.allSatisfy { min($0.width, $0.height) == DetectorInput.shortSide })
        #expect(frames.allSatisfy { $0.format == DetectorInput.pixelFormat })
        let gaps = zip(frames, frames.dropFirst()).map { $1.time - $0.time }
        #expect(gaps.allSatisfy { $0 > 0.05 && $0 < 0.09 })
    }
}
