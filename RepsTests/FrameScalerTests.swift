import CoreVideo
import Testing

@testable import Reps

struct FrameScalerTests {
    enum Corner: Sendable {
        case topLeft, topRight, bottomRight, bottomLeft
    }

    // 420f with a white block in the top-left quarter; everything else black.
    private func source(width: Int = 1920, height: Int = 1080) throws -> CVPixelBuffer {
        var made: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, attributes, &made)
        let buffer = try #require(made)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let luma = try #require(CVPixelBufferGetBaseAddressOfPlane(buffer, 0)).assumingMemoryBound(to: UInt8.self)
        let lumaRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        for row in 0..<height {
            for column in 0..<width {
                luma[row * lumaRow + column] = row < height / 4 && column < width / 4 ? 255 : 0
            }
        }
        let chroma = try #require(CVPixelBufferGetBaseAddressOfPlane(buffer, 1)).assumingMemoryBound(to: UInt8.self)
        let chromaRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
        for index in 0..<(chromaRow * height / 2) { chroma[index] = 128 }
        return buffer
    }

    private func luma(_ buffer: CVPixelBuffer, x: Int, y: Int) -> UInt8 {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)!.assumingMemoryBound(to: UInt8.self)
        return base[y * CVPixelBufferGetBytesPerRowOfPlane(buffer, 0) + x]
    }

    @Test(arguments: [(0.0, 0), (90, 1), (180, 2), (270, 3), (360, 0), (-90, 3), (89.6, 1)])
    func quarterTurnsSnapAndWrap(degrees: Double, turns: Int) {
        #expect(FrameScaler.quarterTurns(degrees) == turns)
    }

    @Test(arguments: [(0, 854, 480), (1, 480, 854), (2, 854, 480), (3, 480, 854)])
    func outputIsDetectorSized(turns: Int, width: Int, height: Int) throws {
        let scaler = try #require(FrameScaler())
        let output = try #require(scaler.detectorBuffer(from: try source(), quarterTurns: turns))
        #expect(CVPixelBufferGetWidth(output) == width)
        #expect(CVPixelBufferGetHeight(output) == height)
        #expect(CVPixelBufferGetPixelFormatType(output) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
    }

    // The block starts top-left; each clockwise quarter turn moves it one corner on.
    @Test(arguments: [(0, Corner.topLeft), (1, .topRight), (2, .bottomRight), (3, .bottomLeft)])
    func turnsAreClockwise(turns: Int, corner: Corner) throws {
        let scaler = try #require(FrameScaler())
        let output = try #require(scaler.detectorBuffer(from: try source(), quarterTurns: turns))
        let (width, height, margin) = (CVPixelBufferGetWidth(output), CVPixelBufferGetHeight(output), 10)
        let corners: [Corner: (Int, Int)] = [
            .topLeft: (margin, margin), .topRight: (width - margin, margin),
            .bottomRight: (width - margin, height - margin), .bottomLeft: (margin, height - margin),
        ]
        for (name, point) in corners {
            let bright = luma(output, x: point.0, y: point.1) > 200
            #expect(bright == (name == corner), "corner \(name)")
        }
    }

    @Test func smallFramesAreCopiedNotScaled() throws {
        let scaler = try #require(FrameScaler())
        let small = try source(width: 640, height: 480)
        let output = try #require(scaler.detectorBuffer(from: small, quarterTurns: 0))
        #expect(output !== small)
        #expect(CVPixelBufferGetWidth(output) == 640)
        #expect(CVPixelBufferGetHeight(output) == 480)
    }
}
