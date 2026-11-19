import CoreVideo
import ShotDetector
import VideoToolbox

// Makes the detector copy of a camera frame: short side DetectorInput.shortSide, 420f, turned upright (ADR 0016).
// Not thread-safe; CameraPipeline uses it only on its frame queue.
nonisolated final class FrameScaler {
    private let transfer: VTPixelTransferSession
    private let rotation: VTPixelRotationSession
    private var appliedTurns = 0
    private var pools: [Size: CVPixelBufferPool] = [:]

    private struct Size: Hashable {
        var width: Int
        var height: Int
    }

    init?() {
        var transfer: VTPixelTransferSession?
        var rotation: VTPixelRotationSession?
        guard VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &transfer) == noErr,
            VTPixelRotationSessionCreate(nil, &rotation) == noErr,
            let transfer, let rotation
        else { return nil }
        self.transfer = transfer
        self.rotation = rotation
    }

    deinit {
        VTPixelTransferSessionInvalidate(transfer)
        VTPixelRotationSessionInvalidate(rotation)
    }

    // Clockwise quarter turns (0...3) for a rotation angle in degrees, snapped to the nearest 90°.
    static func quarterTurns(_ degrees: Double) -> Int {
        ((Int((degrees / 90).rounded()) % 4) + 4) % 4
    }

    // Always a new buffer, never the camera's own, so a detector holding a frame can't starve capture.
    func detectorBuffer(from source: CVPixelBuffer, quarterTurns: Int) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        let scaled = DetectorInput.scaledSize(width: width, height: height) ?? (width, height)
        guard let small = makeBuffer(Size(width: scaled.width, height: scaled.height)),
            VTPixelTransferSessionTransferImage(transfer, from: source, to: small) == noErr
        else { return nil }
        let turns = Self.quarterTurns(Double(quarterTurns * 90))
        guard turns != 0 else { return small }
        if turns != appliedTurns {
            let value = [kVTRotation_0, kVTRotation_CW90, kVTRotation_180, kVTRotation_CCW90][turns]
            guard VTSessionSetProperty(rotation, key: kVTPixelRotationPropertyKey_Rotation, value: value) == noErr
            else { return nil }
            appliedTurns = turns
        }
        let size =
            turns % 2 == 1
            ? Size(width: scaled.height, height: scaled.width) : Size(width: scaled.width, height: scaled.height)
        guard let upright = makeBuffer(size), VTPixelRotationSessionRotateImage(rotation, small, upright) == noErr
        else { return nil }
        return upright
    }

    private func makeBuffer(_ size: Size) -> CVPixelBuffer? {
        if pools[size] == nil {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: DetectorInput.pixelFormat,
                kCVPixelBufferWidthKey as String: size.width,
                kCVPixelBufferHeightKey as String: size.height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            ]
            var pool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
            pools[size] = pool
        }
        guard let pool = pools[size] else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        return buffer
    }
}
