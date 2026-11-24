// ArchiveDiagnosticsUITests.swift — Settings › Backup & Transfer › Archive
// Diagnostics opens on a healthy archive, its file list expands, and Share
// Report hands a file to the share sheet (ARCHIVE_DERISK_PLAN.md §5).
//
// Screenshots are attached to the result bundle; set
// TEST_RUNNER_DEUCEMATE_UI_SHOTS_DIR to also write them as PNG files.
import XCTest

final class ArchiveDiagnosticsUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testArchiveDiagnosticsOpensFromSettingsAndSharesTheReport() throws {
        app.launch()
        XCTAssertTrue(app.buttons["Manual match entry"].waitForExistence(timeout: 15))
        app.navigationBars["Matches"].buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let row = app.buttons["Archive Diagnostics"]
        for _ in 0..<10 where !(row.exists && row.isHittable) { app.swipeUp() }
        XCTAssertFalse(app.staticTexts["Needs attention"].exists, "A healthy archive needs no attention")
        row.tap()

        XCTAssertTrue(app.navigationBars["Archive Diagnostics"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No problems found"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Share Report and Damaged Files"].exists)
        XCTAssertFalse(app.buttons["Damaged copies (0)"].exists)
        capture("archive-diagnostics-healthy")

        let files = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Files on this iPhone'")).firstMatch
        XCTAssertTrue(files.waitForExistence(timeout: 5))
        files.tap()
        XCTAssertTrue(app.staticTexts["matchHistory.json"].waitForExistence(timeout: 5))
        capture("archive-diagnostics-files-expanded")

        let share = app.buttons["Share Report"]
        for _ in 0..<4 where !share.isHittable { app.swipeUp() }
        share.tap()
        XCTAssertTrue(
            app.otherElements["ActivityListView"].waitForExistence(timeout: 10)
                || app.buttons["Copy"].waitForExistence(timeout: 10)
        )
        capture("archive-diagnostics-share-sheet")
        let close = app.buttons["Close"]
        if close.exists { close.tap() } else { app.swipeDown() }
        XCTAssertTrue(app.navigationBars["Archive Diagnostics"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func capture(_ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["DEUCEMATE_UI_SHOTS_DIR"], !directory.isEmpty {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: url.appendingPathComponent(name + ".png"))
        }
    }
}
