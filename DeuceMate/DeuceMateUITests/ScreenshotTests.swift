// ScreenshotTests.swift — captures fresh App Store/doc screenshots from a real
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
/// defaults to the latest completed match (2026-08-05) from the real imported
/// archive used to capture the currently committed App Store upload set.
private let targetMatchID = ProcessInfo.processInfo.environment["DEUCEMATE_TARGET_MATCH_ID"]
    ?? "44ACB61B-BBF0-444C-86BC-2A0125E0DF6D"

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
    func test_captureAppStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launch()

        let matchRow = app.buttons["match-row-\(targetMatchID)"]
        XCTAssertTrue(app.navigationBars["Matches"].waitForExistence(timeout: 20))
        // The archive establishes that this is a real product with useful
        // history, rather than a one-screen score counter.
        saveScreenshot("05-match-archive")
        for _ in 0..<6 where !matchRow.exists {
            app.swipeUp()
        }
        try XCTSkipUnless(
            matchRow.waitForExistence(timeout: 10),
            "Archive not seeded with match \(targetMatchID) — run `DeuceMateArchiveTool seed` first; see docs/screenshots/README.md."
        )
        matchRow.tap()

        // Strongest first upload slot: completed score, result, points graph,
        // and the beginning of the match analysis on one screen.
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 0.5)
        saveScreenshot("01-match-overview")

        // --- Expanded Points Graph: HR + steps overlays ---
        let expandButton = app.buttons["expand-points-graph"]
        for _ in 0..<4 where !expandButton.exists {
            app.swipeUp()
        }
        XCTAssertTrue(expandButton.waitForExistence(timeout: 10))
        expandButton.tap()

        XCTAssertTrue(app.navigationBars["Points Graph"].waitForExistence(timeout: 10))
        // Add authentic health overlays when the seeded full-fidelity archive
        // contains them. A score-only archive still produces the base graph.
        let stepsToggle = app.buttons["steps-overlay-toggle"]
        if stepsToggle.waitForExistence(timeout: 3) {
            stepsToggle.tap()
        }
        let heartRateToggle = app.buttons["heart-rate-overlay-toggle"]
        if heartRateToggle.waitForExistence(timeout: 3) {
            heartRateToggle.tap()
        }
        Thread.sleep(forTimeInterval: 0.5)
        saveScreenshot("02-points-momentum")
        app.navigationBars["Points Graph"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["expand-points-graph"].waitForExistence(timeout: 10))

        // --- Stats tab, scrolled to data-driven coaching insights ---
        let coachingHeading = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH 'Coaching Insights'"))
            .firstMatch
        for _ in 0..<6 where !coachingHeading.exists {
            app.swipeUp()
        }
        XCTAssertTrue(coachingHeading.waitForExistence(timeout: 10))
        saveScreenshot("04-coaching-insights")

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
