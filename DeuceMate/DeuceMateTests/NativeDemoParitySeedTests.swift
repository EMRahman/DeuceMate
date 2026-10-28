import Foundation
import XCTest
import DeuceMateCore
@testable import DeuceMate

/// Fixture preparation for the explicitly enabled native/browser UI audit.
/// Uses the app's normal importer in its own simulator sandbox; never writes
/// into a simulator container from the host or adds a production launch hook.
final class NativeDemoParitySeedTests: XCTestCase {
    @MainActor func testWriteNativeExportReferences() throws {
        #if targetEnvironment(simulator)
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DEUCEMATE_NATIVE_PARITY"] == "1",
                          "Opt-in native export references require fictional fixtures.")
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["DEUCEMATE_NATIVE_FIXTURE_PATH"])
        let archive = try ManualMatchArchiveBackup.decode(Data(contentsOf: URL(fileURLWithPath: path)))
        let directory = URL(fileURLWithPath: "/tmp/deucemate-native-export-references")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for record in archive.records {
            let me = MatchExporter.aiPromptExport(for: record, focal: .me)
            let opponent = MatchExporter.aiPromptExport(for: record, focal: .opponent)
            for focal in [Player.me, .opponent] {
                let prompt = focal == .me ? me : opponent
                let pointRows = prompt.split(separator: "\n").filter { line in
                    let cells = line.split(separator: "|")
                    return cells.count == 12 && Int(cells[0].trimmingCharacters(in: .whitespaces)) != nil
                }
                XCTAssertEqual(pointRows.count, record.stats.count)
                let name = record.id.uuidString + "." + focal.rawValue
                try prompt.write(to: directory.appendingPathComponent(name + ".ai.txt"), atomically: true, encoding: .utf8)
                let html = MatchHTMLExporter.html(for: record, perspective: focal,
                                                aiPromptMe: me, aiPromptOpponent: opponent)
                try html.write(to: directory.appendingPathComponent(name + ".html"), atomically: true, encoding: .utf8)
            }
        }
        #else
        throw XCTSkip("Native export reference generation is simulator-only.")
        #endif
    }

    @MainActor func testImportBrowserFixturesIntoDisposableSimulator() throws {
        #if targetEnvironment(simulator)
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DEUCEMATE_NATIVE_PARITY"] == "1",
                          "Opt-in fixture import; never replace an ordinary test archive.")
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["DEUCEMATE_NATIVE_FIXTURE_PATH"])
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let archive = try ManualMatchArchiveBackup.decode(data)
        XCTAssertEqual(archive.records.count, 9)
        let preview = try PhoneStatsStore.shared.importManualArchive(data: data, mode: .replace)
        XCTAssertEqual(preview.recordCount, 9)
        XCTAssertEqual(Set(PhoneStatsStore.shared.loadHistory().map(\.id)), Set(archive.records.map(\.id)))
        #else
        throw XCTSkip("Native demo fixture import is simulator-only.")
        #endif
    }
}
