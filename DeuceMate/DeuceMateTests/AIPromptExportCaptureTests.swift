// AIPromptExportCaptureTests.swift — not a regression test: captures the real
// generated AI-coach prompt text for a real imported match, for the
// docs/screenshots/README.md web-rendered prompt shots (10/11/12). Calling
// MatchExporter.aiPromptExport directly (same code the app's AI Coach sheet
// uses) sidesteps driving the UI/pasteboard, which is unreliable here — see
// docs/screenshots/README.md for why.
import Foundation
import DeuceMateCore
import Testing
@testable import DeuceMate

struct AIPromptExportCaptureTests {
    @Test func captureRealAIPrompt() throws {
        let archivePath = "/Users/ehsanrahman/Library/Mobile Documents/com~apple~CloudDocs/Downloads/deucemate_archive_2026-07-17.json"
        let targetMatchID = UUID(uuidString: "5ABCB95C-1E5E-4554-B2B6-503C7C85F0C0")!

        let data = try Data(contentsOf: URL(fileURLWithPath: archivePath))
        let archive = try ManualMatchArchiveBackup.decode(data)
        let record = try #require(archive.records.first { $0.id == targetMatchID })

        let prompt = MatchExporter.aiPromptExport(for: record, maxHR: 190, focal: .me, playerNTRP: "3.0–3.5")
        #expect(!prompt.isEmpty)

        let outputDir = "/private/tmp/claude-501/-Users-ehsanrahman-Library-Mobile-Documents-com-apple-CloudDocs-Git2-DeuceMate/ef616c1f-7d65-43b2-8a63-04f9d90681c1/scratchpad/ios-shots"
        let dir = URL(fileURLWithPath: outputDir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try prompt.write(to: dir.appendingPathComponent("ai-prompt.txt"), atomically: true, encoding: .utf8)
    }
}
