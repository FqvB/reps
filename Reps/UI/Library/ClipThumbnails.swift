import AVFoundation
import UIKit

// Tile images: memory, then Caches/thumbnails/<shotId>.jpg, then one frame decoded from the clip (§5.3c).
actor ClipThumbnails {
    static let shared = ClipThumbnails()
    static let maximumSize = CGSize(width: 480, height: 480)  // PLACEHOLDER: thumbnail size

    private let memory = NSCache<NSUUID, UIImage>()
    private let directory: URL

    init(directory: URL = URL.cachesDirectory.appending(path: "thumbnails", directoryHint: .isDirectory)) {
        self.directory = directory
    }

    // nil when the clip file is missing or can't be decoded; the tile keeps its placeholder.
    func image(shotID: UUID, clipURL: URL) async -> UIImage? {
        if let cached = memory.object(forKey: shotID as NSUUID) { return cached }
        let file = cacheFile(shotID)
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            memory.setObject(image, forKey: shotID as NSUUID)
            return image
        }
        guard FileManager.default.fileExists(atPath: clipURL.path(percentEncoded: false)) else { return nil }
        let asset = AVURLAsset(url: clipURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = Self.maximumSize
        let duration = (try? await asset.load(.duration)) ?? .zero
        // PLACEHOLDER: the middle of the clip stands in for the impact frame until #22 stores one.
        let time = CMTimeMultiplyByRatio(duration, multiplier: 1, divisor: 2)
        guard let cgImage = try? await generator.image(at: time).image else { return nil }
        let image = UIImage(cgImage: cgImage)
        memory.setObject(image, forKey: shotID as NSUUID)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? image.jpegData(compressionQuality: 0.8)?.write(to: file, options: .atomic)
        return image
    }

    // Deleted clips must not leave frames behind in Caches.
    func remove(_ shotIDs: [UUID]) {
        for id in shotIDs {
            memory.removeObject(forKey: id as NSUUID)
            try? FileManager.default.removeItem(at: cacheFile(id))
        }
    }

    private func cacheFile(_ shotID: UUID) -> URL {
        directory.appending(path: "\(shotID.uuidString).jpg", directoryHint: .notDirectory)
    }
}
