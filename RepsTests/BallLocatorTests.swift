import ShotDetector
import Testing

private func luma(
    _ width: Int = 200, _ height: Int = 160, background: UInt8 = 60,
    discs: [(x: Int, y: Int, r: Int, value: UInt8)] = []
) -> LumaImage {
    var image = LumaImage(width: width, height: height, fill: background)
    for disc in discs {
        for py in max(0, disc.y - disc.r)...min(height - 1, disc.y + disc.r) {
            for px in max(0, disc.x - disc.r)...min(width - 1, disc.x + disc.r)
            where (px - disc.x) * (px - disc.x) + (py - disc.y) * (py - disc.y) <= disc.r * disc.r {
                image[px, py] = disc.value
            }
        }
    }
    return image
}

struct BallLocatorTests {
    private let locator = BallLocator()

    @Test(arguments: [6, 8, 12, 20, 28])
    func findsADisc(r: Int) throws {
        let found = locator.candidates(in: luma(discs: [(100, 80, r, 220)]))
        let ball = try #require(found.first)
        #expect(found.count == 1)
        #expect(abs(ball.x - 100) <= 1 && abs(ball.y - 80) <= 1)
        #expect(abs(ball.radius - Double(r)) <= 1.5)
        #expect(ball.coverage >= 0.9)
    }

    @Test func findsADiscWithALightBackgroundBehindIt() throws {
        var image = luma(discs: [])
        for y in 0..<80 { for x in 0..<200 { image[x, y] = 150 } }
        for py in 68...92 {
            for px in 88...112 where (px - 100) * (px - 100) + (py - 80) * (py - 80) <= 144 { image[px, py] = 200 }
        }
        let found = locator.candidates(in: image)
        let ball = try #require(found.first)
        #expect(found.count == 1)
        #expect(abs(ball.x - 100) <= 1 && abs(ball.y - 80) <= 1)
    }

    @Test(arguments: [12, 16, 24, 40])
    func rejectsSquares(side: Int) {
        var image = luma()
        for y in (80 - side / 2)..<(80 + side / 2) {
            for x in (100 - side / 2)..<(100 + side / 2) { image[x, y] = 220 }
        }
        #expect(locator.candidates(in: image).isEmpty)
    }

    @Test func rejectsAStraightEdge() {
        var image = luma()
        for y in 0..<160 { for x in 100..<200 { image[x, y] = 220 } }
        #expect(locator.candidates(in: image).isEmpty)
    }

    @Test func rejectsAUniformImage() {
        #expect(locator.candidates(in: luma()).isEmpty)
    }

    @Test func ignoresDiscsOutsideTheRadiusRange() {
        #expect(locator.candidates(in: luma(discs: [(100, 80, 3, 220)])).isEmpty)
        #expect(locator.candidates(in: luma(400, 300, discs: [(200, 150, 50, 220)])).isEmpty)
    }

    @Test func findsTwoDiscs() {
        let found = locator.candidates(in: luma(discs: [(50, 50, 10, 220), (150, 110, 14, 220)]))
        #expect(found.count == 2)
        for ball in found {
            let near = [(50.0, 50.0), (150.0, 110.0)].contains { abs(ball.x - $0.0) <= 1 && abs(ball.y - $0.1) <= 1 }
            #expect(near)
        }
    }
}
