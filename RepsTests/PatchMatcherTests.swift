import ShotDetector
import Testing

private func scene(discX: Int? = 50) -> LumaImage {
    var image = LumaImage(width: 100, height: 100, fill: 60)
    guard let discX else { return image }
    for y in 38...62 {
        for x in (discX - 12)...(discX + 12) where (x - discX) * (x - discX) + (y - 50) * (y - 50) <= 144 {
            image[x, y] = 220
        }
    }
    return image
}

struct PatchMatcherTests {
    private let patch: [UInt8] = (0..<50).map { UInt8($0 * 5) }

    @Test func identicalIsOne() {
        #expect(abs(PatchMatcher.ncc(patch, patch) - 1) < 1e-9)
    }

    @Test func invertedIsMinusOne() {
        #expect(abs(PatchMatcher.ncc(patch, patch.map { 255 - $0 }) + 1) < 1e-9)
    }

    @Test func flatIsZero() {
        #expect(PatchMatcher.ncc(patch, [UInt8](repeating: 9, count: 50)) == 0)
    }

    @Test func nilWhenWindowLeavesImage() {
        #expect(PatchMatcher(reference: scene(), centerX: 5, centerY: 50, halfSize: 12) == nil)
    }

    @Test func shiftedDiscStillMatches() throws {
        let matcher = try #require(PatchMatcher(reference: scene(), centerX: 50, centerY: 50, halfSize: 12))
        #expect(matcher.similarity(in: scene(discX: 54), maxShift: 4) >= 0.95)
    }

    @Test func removedDiscDoesNotMatch() throws {
        let matcher = try #require(PatchMatcher(reference: scene(), centerX: 50, centerY: 50, halfSize: 12))
        #expect(matcher.similarity(in: scene(discX: nil), maxShift: 4) < 0.5)
    }
}
