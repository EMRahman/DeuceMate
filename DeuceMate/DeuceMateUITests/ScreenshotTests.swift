// ScreenshotTests.swift — captures fresh marketing/doc screenshots from a real
// imported match. Not part of the regular regression suite; run explicitly via
// `xcodebuild test -only-testing:DeuceMateUITests/ScreenshotTests`. See
// docs/screenshots/README.md for the full capture workflow (seeding the
// archive, running this suite, rendering the AI-prompt shots).
import XCTest

/// Absolute host path screenshots are written to — the test process runs
/// unsandboxed on the simulator host, so a plain file write reaches the Mac's
/// disk directly (same technique fastlane's `snapshot` uses).
private let screenshotOutputDir = "/private/tmp/claude-501/-Users-ehsanrahman-Library-Mobile-Documents-com-apple-CloudDocs-Git2-DeuceMate/ef616c1f-7d65-43b2-8a63-04f9d90681c1/scratchpad/ios-shots"

/// UUID of the match seeded via `DeuceMateArchiveTool seed` — record #1 (2026-07-15)
/// from the real imported archive, chosen for its dramatic 3-set comeback score.
private let targetMatchID = "5ABCB95C-1E5E-4554-B2B6-503C7C85F0C0"

final class ScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
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
        XCTAssertTrue(matchRow.waitForExistence(timeout: 10))
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
