import Testing

@testable import Reps

struct CaptureFormatTests {
    private func hd(_ fps: Double, fullRange: Bool = true) -> FormatCandidate {
        FormatCandidate(width: 1920, height: 1080, maxFrameRate: fps, isFullRange: fullRange)
    }

    private let uhd60 = FormatCandidate(width: 3840, height: 2160, maxFrameRate: 60, isFullRange: true)

    @Test func picks1080p60OverOtherSizesAndRates() {
        #expect(CaptureFormat.best([uhd60, hd(30), hd(60)]) == 2)
    }

    @Test func skipsSlowMotionFormats() {
        #expect(CaptureFormat.best([hd(240), hd(120), hd(60)]) == 2)
    }

    @Test func fallsBackToTheFastest1080p() {
        #expect(CaptureFormat.best([hd(24), hd(30), uhd60]) == 1)
    }

    @Test func prefersFullRangeAtTheSameRate() {
        #expect(CaptureFormat.best([hd(60, fullRange: false), hd(60)]) == 1)
    }

    @Test func frameRateBeatsFullRange() {
        #expect(CaptureFormat.best([hd(30), hd(60, fullRange: false)]) == 1)
    }

    @Test func tiesKeepTheDeviceOrder() {
        #expect(CaptureFormat.best([hd(60), hd(60)]) == 0)
    }

    @Test func nilWithoutA1080pFormat() {
        #expect(CaptureFormat.best([uhd60]) == nil)
        #expect(CaptureFormat.best([]) == nil)
    }
}
