import Foundation
import Testing

@testable import Reps

struct SettingsCopyTests {
    private let locale = Locale(identifier: "en_US")

    @Test func clubCount() {
        #expect(SettingsCopy.clubCount(0) == "No clubs")
        #expect(SettingsCopy.clubCount(1) == "1 club")
        #expect(SettingsCopy.clubCount(14) == "14 clubs")
    }

    @Test func clipUsage() {
        #expect(SettingsCopy.clipUsage(nil, locale: locale) == "Calculating…")
        #expect(SettingsCopy.clipUsage(.zero, locale: locale) == "No clips yet")
        #expect(SettingsCopy.clipUsage(ClipUsage(bytes: 48_000_000, count: 1), locale: locale) == "48 MB · 1 clip")
        #expect(
            SettingsCopy.clipUsage(ClipUsage(bytes: 3_200_000_000, count: 412), locale: locale)
                == "3.2 GB · 412 clips")
        #expect(
            SettingsCopy.clipUsage(ClipUsage(bytes: 3_200_000_000, count: 1_412), locale: locale)
                == "3.2 GB · 1,412 clips")
    }

    @Test func version() {
        #expect(
            SettingsCopy.version(info: ["CFBundleShortVersionString": "0.1", "CFBundleVersion": "12"]) == "0.1 (12)")
        #expect(SettingsCopy.version(info: ["CFBundleShortVersionString": "0.1"]) == "0.1")
        #expect(SettingsCopy.version(info: ["CFBundleVersion": "12"]) == "(12)")
        #expect(SettingsCopy.version(info: nil) == "–")
    }

    @Test func angleAndQualityTitles() {
        #expect(SettingsCopy.angleTitle(.faceOn) == "Face-on")
        #expect(SettingsCopy.angleTitle(.downTheLine) == "Down-the-line")
        #expect(SettingsCopy.clipQualityTitle(.p1080fps60) == "1080p · 60 fps")
    }
}
