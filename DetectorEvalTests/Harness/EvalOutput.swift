import Foundation
import Testing

// Prints a report, attaches it to the test result and writes it to <repo>/build/eval/ (gitignored).
enum EvalOutput {
    // <repo>/DetectorEvalTests/Harness/EvalOutput.swift -> <repo>/build/eval
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "build/eval", directoryHint: .isDirectory)

    static func publish(_ report: EvalReport) throws {
        let table = report.table
        let json = try report.json
        print(table)
        Attachment.record(table, named: "\(report.name).txt")
        Attachment.record(json, named: "\(report.name).json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(table.utf8).write(to: directory.appending(path: "\(report.name).txt"))
        try json.write(to: directory.appending(path: "\(report.name).json"))
    }
}
