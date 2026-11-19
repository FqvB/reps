import CoreVideo
import ShotDetector
import Testing

struct LumaImageTests {
    private func buffer(format: OSType, width: Int, height: Int) throws -> CVPixelBuffer {
        var made: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()] as CFDictionary
        CVPixelBufferCreate(nil, width, height, format, attributes, &made)
        return try #require(made)
    }

    @Test func copiesLumaPlaneDroppingRowPadding() throws {
        let source = try buffer(format: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, width: 30, height: 20)
        CVPixelBufferLockBaseAddress(source, [])
        let base = try #require(CVPixelBufferGetBaseAddressOfPlane(source, 0)).assumingMemoryBound(to: UInt8.self)
        let row = CVPixelBufferGetBytesPerRowOfPlane(source, 0)
        for y in 0..<20 { for x in 0..<30 { base[y * row + x] = UInt8(x + 2 * y) } }
        CVPixelBufferUnlockBaseAddress(source, [])
        #expect(CVPixelBufferGetBytesPerRowOfPlane(source, 0) >= 30)

        let image = try #require(LumaImage(pixelBuffer: source))
        #expect(image.width == 30)
        #expect(image.height == 20)
        #expect(image.pixels == (0..<20).flatMap { y in (0..<30).map { UInt8($0 + 2 * y) } })
    }

    @Test func nonPlanarBufferIsNil() throws {
        let source = try buffer(format: kCVPixelFormatType_32BGRA, width: 32, height: 16)
        #expect(LumaImage(pixelBuffer: source) == nil)
    }

    @Test func croppedCopiesTheRect() {
        let image = LumaImage(width: 6, height: 5, pixels: (0..<30).map { UInt8($0) })
        let crop = image.cropped(x: 2, y: 1, width: 3, height: 2)
        #expect(crop.width == 3)
        #expect(crop.height == 2)
        #expect(crop.pixels == [8, 9, 10, 14, 15, 16])
    }
}
