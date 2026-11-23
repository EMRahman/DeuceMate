import Foundation
import Testing
@testable import DeuceMate

struct LocalArchiveExportDirectoryTests {
    @Test func preparesBackupExcludedFolderAndPreservesExistingExports() throws {
        let documents = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: documents) }
        var directory = try #require(LocalArchiveExportDirectory.prepare(in: documents))
        #expect(directory.lastPathComponent == "Exports")
        #expect(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        let file = directory.appendingPathComponent("archive.json")
        let bytes = Data("manual export".utf8)
        try bytes.write(to: file)
        var values = URLResourceValues()
        values.isExcludedFromBackup = false
        try directory.setResourceValues(values)

        let preparedAgain = try #require(LocalArchiveExportDirectory.prepare(in: documents))
        #expect(try preparedAgain.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test func aFileAtTheSuggestedPathFallsBackWithoutChangingTheFile() throws {
        let documents = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: documents) }
        let file = documents.appendingPathComponent("Exports")
        let bytes = Data("existing file".utf8)
        try bytes.write(to: file)

        #expect(LocalArchiveExportDirectory.prepare(in: documents) == nil)
        #expect(try Data(contentsOf: file) == bytes)
    }
}
