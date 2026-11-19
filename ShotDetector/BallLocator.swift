import Foundation

public struct BallCandidate: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var radius: Double
    public var coverage: Double

    public init(x: Double, y: Double, radius: Double, coverage: Double) {
        self.x = x
        self.y = y
        self.radius = radius
        self.coverage = coverage
    }
}

// Gradient-direction circle vote (ADR 0017). Pure and stateless; coordinates are buffer pixels.
public struct BallLocator: Sendable {
    public struct Config: Sendable, Equatable {
        public var minRadius = 6
        public var maxRadius = 30
        public var edgeThreshold: Float = 60
        public var radialCosine: Float = 0.95
        public var maxPeaks = 24
        public var minCoverage = 0.75
        public init() {}
    }

    public var config: Config

    public init(config: Config = Config()) {
        self.config = config
    }

    public func candidates(in image: LumaImage) -> [BallCandidate] {
        let width = image.width
        let height = image.height
        let minR = config.minRadius
        let maxR = config.maxRadius
        guard width >= 3, height >= 3, minR >= 1 else { return [] }

        let smooth = Self.boxMean(image)
        var edgeX = [Int32]()
        var edgeY = [Int32]()
        var edgeUX = [Float]()
        var edgeUY = [Float]()
        var rowStart = [Int](repeating: 0, count: height + 1)
        smooth.withUnsafeBufferPointer { s in
            for y in 0..<height {
                rowStart[y] = edgeX.count
                guard y >= 1, y <= height - 2 else { continue }
                for x in 1...(width - 2) {
                    let a = y * width + x
                    let up = a - width
                    let down = a + width
                    let gx = (s[up + 1] + 2 * s[a + 1] + s[down + 1]) - (s[up - 1] + 2 * s[a - 1] + s[down - 1])
                    let gy = (s[down - 1] + 2 * s[down] + s[down + 1]) - (s[up - 1] + 2 * s[up] + s[up + 1])
                    let mag = (gx * gx + gy * gy).squareRoot()
                    guard mag >= config.edgeThreshold else { continue }
                    edgeX.append(Int32(x))
                    edgeY.append(Int32(y))
                    edgeUX.append(gx / mag)
                    edgeUY.append(gy / mag)
                }
            }
            rowStart[height] = edgeX.count
        }

        // Both signs, because the ball can be darker than the background on its shaded side.
        var acc = [Int32](repeating: 0, count: width * height)
        acc.withUnsafeMutableBufferPointer { acc in
            for e in 0..<edgeX.count {
                let fx = Float(edgeX[e])
                let fy = Float(edgeY[e])
                let ux = edgeUX[e]
                let uy = edgeUY[e]
                for r in minR...maxR {
                    let fr = Float(r)
                    for sign: Float in [1, -1] {
                        let cx = Int((fx + sign * fr * ux).rounded())
                        let cy = Int((fy + sign * fr * uy).rounded())
                        if cx >= 0, cx < width, cy >= 0, cy < height { acc[cy * width + cx] += 1 }
                    }
                }
            }
        }

        var score = [Int32](repeating: 0, count: width * height)
        acc.withUnsafeBufferPointer { acc in
            for y in 0..<height {
                for x in 0..<width {
                    var sum: Int32 = 0
                    for ny in max(0, y - 1)...min(height - 1, y + 1) {
                        for nx in max(0, x - 1)...min(width - 1, x + 1) { sum += acc[ny * width + nx] }
                    }
                    score[y * width + x] = sum
                }
            }
        }

        func bestOfRow(_ y: Int) -> (value: Int32, x: Int) {
            var best: (value: Int32, x: Int) = (Int32.min, 0)
            for x in 0..<width where score[y * width + x] > best.value { best = (score[y * width + x], x) }
            return best
        }
        var rowBest = (0..<height).map(bestOfRow)

        var found = [BallCandidate]()
        for _ in 0..<config.maxPeaks {
            var peakY = 0
            for y in 1..<height where rowBest[y].value > rowBest[peakY].value { peakY = y }
            guard rowBest[peakY].value > 0 else { break }
            let peakX = rowBest[peakY].x
            let y0 = max(0, peakY - minR)
            let y1 = min(height - 1, peakY + minR)
            for y in y0...y1 {
                for x in max(0, peakX - minR)...min(width - 1, peakX + minR) { score[y * width + x] = 0 }
                rowBest[y] = bestOfRow(y)
            }
            let ball = coverage(
                cx: peakX, cy: peakY, width: width, height: height,
                edgeX: edgeX, edgeY: edgeY, edgeUX: edgeUX, edgeUY: edgeUY, rowStart: rowStart)
            if let ball { found.append(ball) }
        }
        return found
    }

    private func coverage(
        cx: Int, cy: Int, width: Int, height: Int,
        edgeX: [Int32], edgeY: [Int32], edgeUX: [Float], edgeUY: [Float], rowStart: [Int]
    ) -> BallCandidate? {
        let minR = config.minRadius
        let maxR = config.maxRadius
        var masks = [UInt16](repeating: 0, count: maxR + 1)
        var counts = [Int](repeating: 0, count: maxR + 1)
        for row in max(0, cy - maxR - 1)...min(height - 1, cy + maxR + 1) {
            for e in rowStart[row]..<rowStart[row + 1] {
                let dx = Float(Int(edgeX[e]) - cx)
                let dy = Float(row - cy)
                let d = (dx * dx + dy * dy).squareRoot()
                let ri = Int(d.rounded())
                guard ri >= minR, ri <= maxR, abs(dx * edgeUX[e] + dy * edgeUY[e]) >= config.radialCosine * d else {
                    continue
                }
                let sector = Int((atan2(dy, dx) + .pi) / (2 * .pi) * 16) % 16
                masks[ri] |= 1 << UInt16(sector)
                counts[ri] += 1
            }
        }
        var best = minR
        for r in minR...maxR {
            let bits = masks[r].nonzeroBitCount
            let bestBits = masks[best].nonzeroBitCount
            if bits > bestBits || (bits == bestBits && counts[r] > counts[best]) { best = r }
        }
        let coverage = Double(masks[best].nonzeroBitCount) / 16
        guard coverage >= config.minCoverage else { return nil }
        return BallCandidate(x: Double(cx), y: Double(cy), radius: Double(best), coverage: coverage)
    }

    // 3×3 mean with replicated borders, as two 1-D passes.
    private static func boxMean(_ image: LumaImage) -> [Float] {
        let width = image.width
        let height = image.height
        var horizontal = [Float](repeating: 0, count: width * height)
        var out = [Float](repeating: 0, count: width * height)
        image.pixels.withUnsafeBufferPointer { p in
            for y in 0..<height {
                for x in 0..<width {
                    let l = max(0, x - 1)
                    let r = min(width - 1, x + 1)
                    horizontal[y * width + x] =
                        Float(p[y * width + l]) + Float(p[y * width + x]) + Float(p[y * width + r])
                }
            }
        }
        for y in 0..<height {
            let u = max(0, y - 1)
            let d = min(height - 1, y + 1)
            for x in 0..<width {
                out[y * width + x] =
                    (horizontal[u * width + x] + horizontal[y * width + x] + horizontal[d * width + x]) / 9
            }
        }
        return out
    }
}
