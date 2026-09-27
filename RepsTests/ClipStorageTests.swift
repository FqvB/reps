import Foundation
import Testing

@testable import Reps

struct ClipStorageTests {
    @Test func missingFolderIsZero() {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        #expect(ClipStorage.usage(at: root) == .zero)
    }

    @Test func sumsMovFilesInSessionFolders() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? fileManager.removeItem(at: root) }

        let s1 = root.appending(path: "s1")
        let s2 = root.appending(path: "s2")
        try fileManager.createDirectory(at: s1, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: s2, withIntermediateDirectories: true)

        try Data(count: 100).write(to: s1.appending(path: "a.mov"))
        try Data(count: 50).write(to: s1.appending(path: "b.MOV"))
        try Data(count: 25).write(to: s2.appending(path: "c.mov"))
        try Data(count: 999).write(to: s2.appending(path: "thumb.jpg"))
        try Data(count: 7).write(to: root.appending(path: ".hidden.mov"))

        #expect(ClipStorage.usage(at: root) == ClipUsage(bytes: 175, count: 3))
    }

    @Test func clipsDirectoryIsDocumentsClips() {
        let directory = ClipStorage.clipsDirectory
        #expect(directory.lastPathComponent == "clips")
        #expect(
            directory.deletingLastPathComponent().standardizedFileURL.path
                == URL.documentsDirectory.standardizedFileURL.path)
    }
}
