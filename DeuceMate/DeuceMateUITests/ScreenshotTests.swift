// ScreenshotTests.swift — captures fresh marketing/doc screenshots from a real
// imported match. Opt-in only (DEUCEMATE_CAPTURE_SCREENSHOTS=1): this target is
// part of the default "DeuceMate" scheme, so an ungated run would fail on any
// simulator whose archive isn't seeded with `targetMatchID`. Run explicitly via
// `DEUCEMATE_CAPTURE_SCREENSHOTS=1 xcodebuild test -only-testing:DeuceMateUITests/ScreenshotTests`.
// See docs/screenshots/README.md for the full capture workflow (seeding the
// archive, running this suite, rendering the AI-prompt shots).
import XCTest

/// Absolute host path screenshots are written to — the test process runs
/// unsandboxed on the simulator host, so a plain file write reaches the Mac's
/// disk directly (same technique fastlane's `snapshot` uses). Override with
/// DEUCEMATE_SCREENSHOT_OUTPUT_DIR; defaults to a temp folder.
private let screenshotOutputDir = ProcessInfo.processInfo.environment["DEUCEMATE_SCREENSHOT_OUTPUT_DIR"]
    ?? NSTemporaryDirectory() + "deucemate-screenshots"

/// UUID of the match to capture — seeded into the archive beforehand via
/// `DeuceMateArchiveTool seed`. Override with DEUCEMATE_TARGET_MATCH_ID;
/// defaults to record #1 (2026-07-15) from the real imported archive used to
/// capture the currently-committed shots, chosen for its dramatic 3-set
/// comeback score.
private let targetMatchID = ProcessInfo.processInfo.environment["DEUCEMATE_TARGET_MATCH_ID"]
    ?? "5ABCB95C-1E5E-4554-B2B6-503C7C85F0C0"

final class ScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["DEUCEMATE_CAPTURE_SCREENSHOTS"] == "1",
            "Opt-in only — set DEUCEMATE_CAPTURE_SCREENSHOTS=1 (and seed the archive) to run this marketing-screenshot helper; see docs/screenshots/README.md."
        )
    }

    @MainActor
    private func saveScreenshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let dir = URL(fileURLWithPath: screenshotOutputDir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(name).png")
        try? shot.pngRepresentation.write(to: url)
    }

    @MainActor
    func test_captureStaleScreenshots() throws {
        let app = XCUIApplication()
        app.launch()

        let matchRow = app.buttons["match-row-\(targetMatchID)"]
        for _ in 0..<6 where !matchRow.exists {
            app.swipeUp()
        }
        try XCTSkipUnless(
            matchRow.waitForExistence(timeout: 10),
            "Archive not seeded with match \(targetMatchID) — run `DeuceMateArchiveTool seed` first; see docs/screenshots/README.md."
        )
        matchRow.tap()

        // --- Expanded Points Graph: 02 (HR+Steps overlays), 07 (Points Won), 08 (Points Lost) ---
        let expandButton = app.buttons["expand-points-graph"]
        for _ in 0..<4 where !expandButton.exists {
            app.swipeUp()
        }
        XCTAssertTrue(expandButton.waitForExistence(timeout: 10))
        expandButton.tap()

        let stepsToggle = app.buttons["steps-overlay-toggle"]
        let hrToggle = app.buttons["heart-rate-overlay-toggle"]
        XCTAssertTrue(stepsToggle.waitForExistence(timeout: 10))
        stepsToggle.tap()
        XCTAssertTrue(hrToggle.waitForExistence(timeout: 5))
        hrToggle.tap()
        // Let the chart animation settle before capturing.
        Thread.sleep(forTimeInterval: 0.5)
        saveScreenshot("02-points-momentum-graph")

        let pointsWonChip = app.buttons["points-won-chip"]
        XCTAssertTrue(pointsWonChip.waitForExistence(timeout: 5))
        pointsWonChip.tap()
        Thread.sleep(forTimeInterval: 0.3)
        saveScreenshot("07-points-outcomes-won")

        let pointsLostChip = app.buttons["points-lost-chip"]
        XCTAssertTrue(pointsLostChip.waitForExistence(timeout: 5))
        pointsLostChip.tap()
        Thread.sleep(forTimeInterval: 0.3)
        saveScreenshot("08-points-outcomes-lost")

        app.buttons["Done"].firstMatch.tap()

        // --- Stats tab, scrolled to Pulse Coach: 05 ---
        let pulseCoachHeading = app.staticTexts["Pulse Coach"]
        for _ in 0..<8 where !pulseCoachHeading.exists {
            app.swipeUp()
        }
        XCTAssertTrue(pulseCoachHeading.waitForExistence(timeout: 10))
        saveScreenshot("05-pulse-coach-hr-zones")

        // --- Stats tab, scrolled to Outcome Breakdown / Serve: 03 ---
        let outcomeBreakdown = app.staticTexts["Outcome Breakdown"]
        for _ in 0..<8 where !outcomeBreakdown.exists {
            app.swipeUp()
        }
        XCTAssertTrue(outcomeBreakdown.waitForExistence(timeout: 10))
        // "Outcome Breakdown" merely existing can mean it's only just peeking
        // into frame at the bottom edge — scroll a little further so it leads
        // the shot (Winners/Unforced Errors/Aggression Index), without
        // overshooting into the Serve/Return/Break Points sections below it.
        app.swipeUp(velocity: .slow)
        saveScreenshot("03-match-stats")
    }
}
