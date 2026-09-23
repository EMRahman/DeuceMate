// SetupGuidePhoneScreenshotTests.swift — the iPhone half of the website's
// step-by-step setup guide (docs/website/setup.html): the archive list with
// the first watch match in it, then that match's detail. Opt-in only
// (DEUCEMATE_CAPTURE_SCREENSHOTS=1). Run it after the watch's
// SetupGuideScreenshotTests has played a match on the paired watch
// simulator (with -parallel-testing-enabled NO, so both tests use the real
// pair rather than clones). See docs/screenshots/README.md "Setup guide shots".
import XCTest

private let screenshotOutputDir = ProcessInfo.processInfo.environment["DEUCEMATE_SCREENSHOT_OUTPUT_DIR"]
    ?? NSTemporaryDirectory() + "deucemate-setup-screenshots"

final class SetupGuidePhoneScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["DEUCEMATE_CAPTURE_SCREENSHOTS"] == "1",
            "Opt-in only — set DEUCEMATE_CAPTURE_SCREENSHOTS=1; see docs/screenshots/README.md."
        )
    }

    @MainActor
    private func shot(_ name: String, settle: TimeInterval = 1.5) {
        Thread.sleep(forTimeInterval: settle)
        let dir = URL(fileURLWithPath: screenshotOutputDir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: dir.appendingPathComponent("\(name).png"))
        try? XCUIApplication().debugDescription
            .write(to: dir.appendingPathComponent("\(name).txt"), atomically: true, encoding: .utf8)
    }

    @MainActor
    func test_firstMatchOnIPhone() throws {
        let app = XCUIApplication()
        app.launch()
        shot("p03-matches-list", settle: 6)

        let firstMatch = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH 'match-row-'"))
            .firstMatch
        XCTAssertTrue(firstMatch.waitForExistence(timeout: 10))
        firstMatch.tap()
        shot("p04-match-detail", settle: 3)

        // A Health prompt may appear the first time heart rate is looked up.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let healthAllow = springboard.buttons["Allow"]
        if healthAllow.waitForExistence(timeout: 2) { shot("p05-health-prompt") }

        app.swipeUp()
        shot("p06-match-detail-scrolled")
        app.swipeUp()
        shot("p07-match-detail-scrolled-2")
    }
}
