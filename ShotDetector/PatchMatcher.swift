import Foundation

// Normalised cross-correlation of a reference window against the same place in later frames (spec §5.2).
public struct PatchMatcher: Sendable {
    public let x: Int
    public let y: Int
    public let size: Int
    private let reference: [UInt8]

    public init?(reference image: LumaImage, centerX: Int, centerY: Int, halfSize: Int) {
        let x = centerX - halfSize
        let y = centerY - halfSize
        let size = 2 * halfSize + 1
        guard halfSize >= 0, x >= 0, y >= 0, x + size <= image.width, y + size <= image.height else { return nil }
        self.x = x
        self.y = y
        self.size = size
        reference = image.cropped(x: x, y: y, width: size, height: size).pixels
    }

    public func similarity(in image: LumaImage, maxShift: Int, step: Int = 2) -> Double {
        let n = maxShift / step
        var best: Double?
        for l in -n...n {
            for k in -n...n {
                let wx = x + k * step
                let wy = y + l * step
                guard wx >= 0, wy >= 0, wx + size <= image.width, wy + size <= image.height else { continue }
                let value = Self.ncc(reference, image.cropped(x: wx, y: wy, width: size, height: size).pixels)
                best = max(best ?? value, value)
            }
        }
        return best ?? 0
    }

    public static func ncc(_ a: [UInt8], _ b: [UInt8]) -> Double {
        precondition(a.count == b.count)
        let n = Double(a.count)
        let meanA = a.reduce(0.0) { $0 + Double($1) } / n
        let meanB = b.reduce(0.0) { $0 + Double($1) } / n
        var cross = 0.0
        var varA = 0.0
        var varB = 0.0
        for i in 0..<a.count {
            let da = Double(a[i]) - meanA
            let db = Double(b[i]) - meanB
            cross += da * db
            varA += da * da
            varB += db * db
        }
        let denominator = (varA * varB).squareRoot()
        return denominator < 1e-6 ? 0 : cross / denominator
    }
}
