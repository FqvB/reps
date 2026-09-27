import CoreVideo
import ImageIO

// One downscaled frame handed to a detector. Built by the camera pipeline or, in tests, by a video file reader.
public struct VideoFrame {
    public var pixelBuffer: CVPixelBuffer
    public var time: Double
    public var orientation: CGImagePropertyOrientation

    public init(pixelBuffer: CVPixelBuffer, time: Double, orientation: CGImagePropertyOrientation = .up) {
        self.pixelBuffer = pixelBuffer
        self.time = time
        self.orientation = orientation
    }
}

// What the camera pipeline and the eval harness feed detectors (spec §5.6).
public enum DetectorInput {
    public static let frameRate: Double = 15
    public static let shortSide = 480
    public static let pixelFormat: OSType = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
}
