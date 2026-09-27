import Foundation

// Deletes clip files in Documents/clips/<sessionId>/ (ADR 0006). #22 supplies the real one.
protocol ClipFileRemoving {
    func removeClip(fileName: String, sessionID: UUID)
    func removeClips(sessionID: UUID)
}

// Until #22 no clip files exist, so there is nothing to delete.
struct NoClipFiles: ClipFileRemoving {
    func removeClip(fileName: String, sessionID: UUID) {}
    func removeClips(sessionID: UUID) {}
}
