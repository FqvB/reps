import Foundation

nonisolated struct ClipUsage: Equatable, Sendable {
    var bytes: Int64
    var count: Int

    static let zero = ClipUsage(bytes: 0, count: 0)
}

// Clips live in Documents/clips/<sessionId>/<shotId>.mov (ADR 0006); #22 writes them.
nonisolated enum ClipStorage {
    static var clipsDirectory: URL {
        URL.documentsDirectory.appending(path: "clips", directoryHint: .isDirectory)
    }

    // The file for a stored clip name; nil unless it's a bare "<name>.mov", since the name comes from the store.
    static func clipURL(fileName: String, sessionID: UUID, root: URL = clipsDirectory) -> URL? {
        let invalid = CharacterSet(charactersIn: "/\\:").union(.controlCharacters)
        guard !fileName.hasPrefix("."), fileName.rangeOfCharacter(from: invalid) == nil,
            fileName.lowercased().hasSuffix(".mov")
        else { return nil }
        return root.appending(path: sessionID.uuidString, directoryHint: .isDirectory)
            .appending(path: fileName, directoryHint: .notDirectory)
    }

    // Blocking file I/O: call it off the main actor. A missing folder is zero.
    static func usage(at root: URL, fileManager: FileManager = .default) -> ClipUsage {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard
            let files = fileManager.enumerator(
                at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        else { return .zero }
        var usage = ClipUsage.zero
        for case let url as URL in files where url.pathExtension.lowercased() == "mov" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else {
                continue
            }
            usage.bytes += Int64(values.fileSize ?? 0)
            usage.count += 1
        }
        return usage
    }
}
