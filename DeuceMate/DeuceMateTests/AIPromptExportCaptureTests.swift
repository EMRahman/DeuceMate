// AIPromptExportCaptureTests.swift — not a regression test: captures the real
// generated AI-coach prompt text for a real imported match, for the
// docs/screenshots/README.md web-rendered prompt shots (10/11/12). Calling
// MatchExporter.aiPromptExport directly (same code the app's AI Coach sheet
// uses) sidesteps driving the UI/pasteboard, which is unreliable here — see
// docs/screenshots/README.md for why.
//
// Opt-in only (DEUCEMATE_CAPTURE_SCREENSHOTS=1 + DEUCEMATE_ARCHIVE_PATH): this
// target is part of the default "DeuceMate" scheme, so an ungated run would
// fail on any machine without a personal archive file at a hardcoded path.
import Foundation
import DeuceMateCore
import Testing
@testable import DeuceMate

struct AIPromptExportCaptureTests {
    @Test(.enabled(
        if: ProcessInfo.processInfo.environment["DEUCEMATE_CAPTURE_SCREENSHOTS"] == "1",
        "Opt-in only — set DEUCEMATE_CAPTURE_SCREENSHOTS=1 and DEUCEMATE_ARCHIVE_PATH to run this marketing-screenshot helper; see docs/screenshots/README.md."
    ))
    func captureRealAIPrompt() throws {
        let archivePath = try #require(
            ProcessInfo.processInfo.environment["DEUCEMATE_ARCHIVE_PATH"],
            "Set DEUCEMATE_ARCHIVE_PATH to a manual archive JSON file (Settings > Backup & Transfer > Export Match Archive)."
        )
        let targetMatchIDString = ProcessInfo.processInfo.environment["DEUCEMATE_TARGET_MATCH_ID"]
            ?? "5ABCB95C-1E5E-4554-B2B6-503C7C85F0C0"
        let targetMatchID = try #require(UUID(uuidString: targetMatchIDString))

        let data = try Data(contentsOf: URL(fileURLWithPath: archivePath))
        let archive = try ManualMatchArchiveBackup.decode(data)
        let record = try #require(archive.records.first { $0.id == targetMatchID })

        let prompt = MatchExporter.aiPromptExport(for: record, maxHR: 190, focal: .me, playerNTRP: "3.0–3.5")
        #expect(!prompt.isEmpty)

        let outputDir = ProcessInfo.processInfo.environment["DEUCEMATE_SCREENSHOT_OUTPUT_DIR"]
            ?? NSTemporaryDirectory() + "deucemate-screenshots"
        let dir = URL(fileURLWithPath: outputDir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let promptURL = dir.appendingPathComponent("ai-prompt.txt")
        try prompt.write(to: promptURL, atomically: true, encoding: .utf8)
        print("Wrote \(promptURL.path)")
    }
}
