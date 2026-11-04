// ReadmeScreenshotTests.swift — the README's point-tagging shot and five-theme
// strip. Opt-in only (DEUCEMATE_CAPTURE_SCREENSHOTS=1), like the other capture
// helpers in this target. See docs/screenshots/README.md.
import XCTest

private let screenshotOutputDir = ProcessInfo.processInfo.environment["DEUCEMATE_SCREENSHOT_OUTPUT_DIR"]
    ?? NSTemporaryDirectory() + "deucemate-screenshots"

final class ReadmeScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["DEUCEMATE_CAPTURE_SCREENSHOTS"] == "1",
            "Opt-in only — set DEUCEMATE_CAPTURE_SCREENSHOTS=1; see docs/screenshots/README.md."
        )
    }

    @MainActor
    private func saveScreenshot(_ name: String) {
        let dir = URL(fileURLWithPath: screenshotOutputDir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: dir.appendingPathComponent("\(name).png"))
    }

    /// Taps a button by label within `timeout`, also looking in the Health sheet.
    @MainActor
    @discardableResult
    private func tapButton(_ label: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let button = app.buttons.matching(NSPredicate(format: "label ==[c] %@", label)).firstMatch
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if button.exists && button.isHittable { button.tap(); return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }

    /// A deliberate drag across the scoreboard; the stock swipes are too short
    /// to clear the app's scoring threshold reliably on the simulator.
    @MainActor
    private func drag(_ app: XCUIApplication, fromY: CGFloat, toY: CGFloat) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: fromY))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: toY))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// Reaches the scoreboard: clears the first-launch Health sheet and guide
    /// offer, then resumes a parked match or starts a new one.
    @MainActor
    private func launch(_ app: XCUIApplication, arguments: [String], firstLaunch: Bool = false) {
        app.terminate()
        app.launchArguments = arguments
        app.launch()
        Thread.sleep(forTimeInterval: 3)
        if firstLaunch {
            // The Health sheet is a remote view XCUITest can't query.
            for _ in 0..<3 {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.11)).tap()
                Thread.sleep(forTimeInterval: 1.5)
            }
            tapButton("Not now", in: app, timeout: 4)
        }
        if tapButton("Resume Match", in: app, timeout: 2) { Thread.sleep(forTimeInterval: 1); return }
        guard tapButton("Start Match", in: app, timeout: 3) else { return }
        XCTAssertTrue(tapButton("Warm Up Complete", in: app, timeout: 8))
        XCTAssertTrue(tapButton("Me", in: app, timeout: 8))
        Thread.sleep(forTimeInterval: 1)
    }

    @MainActor
    private func play(_ app: XCUIApplication, points: [Bool]) {
        for meWins in points {
            if meWins { drag(app, fromY: 0.72, toY: 0.28) } else { drag(app, fromY: 0.28, toY: 0.72) }
            Thread.sleep(forTimeInterval: 0.25)
            if tapButton("OK", in: app, timeout: 0.6) { Thread.sleep(forTimeInterval: 0.4) }
        }
    }

    /// Plays to 6–4, 3–1, 30–15 with tracking off, shoots that score in every
    /// theme, then turns tracking on for the real tag sheet.
    @MainActor
    func test_captureThemesAndTagSheet() throws {
        let app = XCUIApplication()
        let trackingOff = ["-statsTrackingEnabled", "NO"]
        launch(app, arguments: trackingOff, firstLaunch: true)

        let me = [true, true, false, true, true]
        let opp = [false, true, false, false, false]
        let games = [me, opp, me, me, opp, me, opp, me, opp, me, me, me, opp, me]
        play(app, points: games.flatMap { $0 } + [true, false, true])
        Thread.sleep(forTimeInterval: 1)

        for theme in ["default", "clayCourt", "grassCourt", "hardCourtDay", "hardCourtNight"] {
            launch(app, arguments: trackingOff + ["-selectedTheme", theme])
            Thread.sleep(forTimeInterval: 1.5)
            saveScreenshot("readme-theme-\(theme)")
        }

        launch(app, arguments: ["-statsTrackingEnabled", "YES", "-selectedTheme", "default"])
        drag(app, fromY: 0.72, toY: 0.28)
        Thread.sleep(forTimeInterval: 1.5)
        saveScreenshot("readme-watch-tag-point")
    }
}
