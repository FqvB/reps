import Foundation
import Testing

@testable import Reps

struct AppSettingsTests {
    private func withSettings(_ body: (AppSettings) throws -> Void) rethrows {
        let suite = "RepsTests.AppSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(AppSettings(defaults: defaults))
    }

    @Test func defaultsWhenEmpty() throws {
        try withSettings { settings in
            #expect(settings.defaultCameraAngle == .faceOn)
            #expect(settings.clipQuality == .p1080fps60)
            #expect(settings.saveClipsToPhotos == false)
            #expect(settings.recordClipAudio == true)
            #expect(settings.announceCount == true)
            #expect(settings.announceTempo == false)
        }
    }

    @Test func roundTripsEveryValue() throws {
        let suite = "RepsTests.AppSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)

        settings.defaultCameraAngle = .downTheLine
        settings.clipQuality = .p720fps30
        settings.saveClipsToPhotos = true
        settings.recordClipAudio = false
        settings.announceCount = false
        settings.announceTempo = true

        #expect(settings.defaultCameraAngle == .downTheLine)
        #expect(settings.clipQuality == .p720fps30)
        #expect(settings.saveClipsToPhotos == true)
        #expect(settings.recordClipAudio == false)
        #expect(settings.announceCount == false)
        #expect(settings.announceTempo == true)

        let reread = AppSettings(defaults: defaults)
        #expect(reread.defaultCameraAngle == .downTheLine)
        #expect(reread.clipQuality == .p720fps30)
        #expect(reread.saveClipsToPhotos == true)
        #expect(reread.recordClipAudio == false)
        #expect(reread.announceCount == false)
        #expect(reread.announceTempo == true)
    }

    @Test func unknownOrNoneAngleFallsBack() throws {
        try withSettings { settings in
            settings.defaults.set("none", forKey: AppSettings.Key.defaultCameraAngle)
            #expect(settings.defaultCameraAngle == .faceOn)
            settings.defaults.set("sideways", forKey: AppSettings.Key.defaultCameraAngle)
            #expect(settings.defaultCameraAngle == .faceOn)
            settings.defaults.set("downTheLine", forKey: AppSettings.Key.defaultCameraAngle)
            #expect(settings.defaultCameraAngle == .downTheLine)
        }
    }

    @Test func unknownQualityFallsBack() throws {
        try withSettings { settings in
            settings.defaults.set("4k", forKey: AppSettings.Key.clipQuality)
            #expect(settings.clipQuality == .p1080fps60)
        }
    }

    @Test func keysMatchAppStorageNames() {
        #expect(AppSettings.Key.defaultCameraAngle == "settings.defaultCameraAngle")
        #expect(AppSettings.Key.clipQuality == "settings.clipQuality")
        #expect(AppSettings.Key.saveClipsToPhotos == "settings.saveClipsToPhotos")
        #expect(AppSettings.Key.recordClipAudio == "settings.recordClipAudio")
        #expect(AppSettings.Key.announceCount == "settings.announceCount")
        #expect(AppSettings.Key.announceTempo == "settings.announceTempo")
    }

    @Test func cameraAngleForMode() throws {
        try withSettings { settings in
            settings.defaultCameraAngle = .downTheLine
            #expect(settings.cameraAngle(for: .rangeCounter) == .downTheLine)
            #expect(settings.cameraAngle(for: .rangeCounterWithClips) == .downTheLine)
            #expect(settings.cameraAngle(for: .putting) == .none)
        }
    }
}
