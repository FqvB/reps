import Foundation

// Copy for the Settings screen; pure, unit-tested.
nonisolated enum SettingsCopy {
    static func clubCount(_ count: Int) -> String {
        switch count {
        case 0: "No clubs"  // PLACEHOLDER: empty bag copy
        case 1: "1 club"
        default: "\(count) clubs"
        }
    }

    static func angleTitle(_ angle: CameraAngle) -> String {
        switch angle {
        case .faceOn: "Face-on"
        case .downTheLine: "Down-the-line"
        case .none: "None"
        }
    }

    static func clipQualityTitle(_ quality: ClipQuality) -> String {
        switch quality {
        case .p1080fps60: "1080p · 60 fps"
        case .p1080fps30: "1080p · 30 fps"
        case .p720fps30: "720p · 30 fps"
        }
    }

    // nil while the size is still being computed.
    static func clipUsage(_ usage: ClipUsage?, locale: Locale = .current) -> String {
        guard let usage else { return "Calculating…" }  // PLACEHOLDER: storage loading copy
        guard usage.count > 0 else { return "No clips yet" }  // PLACEHOLDER: empty storage copy
        let size = usage.bytes.formatted(.byteCount(style: .file).locale(locale))
        let clips = usage.count == 1 ? "1 clip" : "\(usage.count.formatted(.number.locale(locale))) clips"
        return "\(size) · \(clips)"
    }

    // "0.1 (12)" from CFBundleShortVersionString and CFBundleVersion.
    static func version(info: [String: Any]?) -> String {
        let short = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (short, build) {
        case (let short?, let build?): return "\(short) (\(build))"
        case (let short?, nil): return short
        case (nil, let build?): return "(\(build))"
        case (nil, nil): return "–"
        }
    }
}
