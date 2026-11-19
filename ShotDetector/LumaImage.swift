import CoreVideo

// Luma plane copied without row padding, so detectors and tests work on plain arrays.
public struct LumaImage: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height)
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public init(width: Int, height: Int, fill: UInt8) {
        self.init(width: width, height: height, pixels: [UInt8](repeating: fill, count: width * height))
    }

    public init?(pixelBuffer buffer: CVPixelBuffer) {
        guard CVPixelBufferIsPlanar(buffer) else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        var pixels = [UInt8]()
        pixels.reserveCapacity(width * height)
        for row in 0..<height {
            pixels.append(
                contentsOf: UnsafeBufferPointer(
                    start: (base + row * stride).assumingMemoryBound(to: UInt8.self), count: width))
        }
        self.init(width: width, height: height, pixels: pixels)
    }

    public subscript(x: Int, y: Int) -> UInt8 {
        get { pixels[y * width + x] }
        set { pixels[y * width + x] = newValue }
    }

    public func cropped(x: Int, y: Int, width: Int, height: Int) -> LumaImage {
        var out = [UInt8]()
        out.reserveCapacity(width * height)
        for row in y..<(y + height) {
            out.append(contentsOf: pixels[(row * self.width + x)..<(row * self.width + x + width)])
        }
        return LumaImage(width: width, height: height, pixels: out)
    }
}
