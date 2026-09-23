// SetupGuideScreenshotTests.swift — walks a brand-new user's first session
// (Health prompt → first match → Past Matches) and saves one screenshot per
// step for the website's step-by-step setup guide (docs/website/setup.html).
// Opt-in only (DEUCEMATE_CAPTURE_SCREENSHOTS=1), like LiveMatchScreenshotTests:
// it needs a freshly installed app with reset privacy state
// (`xcrun simctl privacy <udid> reset all`) so the real Health prompt appears.
// See docs/screenshots/README.md "Setup guide shots".
import XCTest

private let screenshotOutputDir = ProcessInfo.processInfo.environment["DEUCEMATE_SCREENSHOT_OUTPUT_DIR"]
    ?? NSTemporaryDirectory() + "deucemate-setup-screenshots"

final class SetupGuideScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["DEUCEMATE_CAPTURE_SCREENSHOTS"] == "1",
            "Opt-in only — set DEUCEMATE_CAPTURE_SCREENSHOTS=1; see docs/screenshots/README.md."
        )
    }

    @MainActor
    private func shot(_ name: String, settle: TimeInterval = 1.2) {
        Thread.sleep(forTimeInterval: settle)
        let dir = URL(fileURLWithPath: screenshotOutputDir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation
            .write(to: dir.appendingPathComponent("\(name).png"))
        // Element tree alongside each shot, to locate tap targets for the guide.
        try? XCUIApplication().debugDescription
            .write(to: dir.appendingPathComponent("\(name).txt"), atomically: true, encoding: .utf8)
    }

    /// Taps the first button labelled exactly `text`, in the app or in a
    /// system (Health) sheet presented over it.
    @MainActor
    @discardableResult
    private func tapButton(_ text: String, in app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "label ==[c] %@", text)
        let candidates = [
            app.buttons.matching(predicate).firstMatch,
            XCUIApplication(bundleIdentifier: "com.apple.HealthKit.HealthKitWatchUI").buttons.matching(predicate).firstMatch,
            XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons.matching(predicate).firstMatch,
        ]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for element in candidates where element.exists && element.isHittable {
                element.tap()
                return true
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return false
    }

    @MainActor
    private func tap(_ app: XCUIApplication, x: CGFloat, y: CGFloat) {
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
    }

    /// A deliberate drag across the scoreboard (XCUIApplication.swipeDown is
    /// too short to register as the watch's point-to-opponent gesture).
    @MainActor
    private func drag(_ app: XCUIApplication, fromY: CGFloat, toY: CGFloat, fromX: CGFloat = 0.5, toX: CGFloat = 0.5) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: fromX, dy: fromY))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: toX, dy: toY))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @MainActor private func myPoint(_ app: XCUIApplication) { drag(app, fromY: 0.75, toY: 0.3) }
    @MainActor private func theirPoint(_ app: XCUIApplication) { drag(app, fromY: 0.3, toY: 0.75) }
    @MainActor private func undo(_ app: XCUIApplication) { drag(app, fromY: 0.5, toY: 0.5, fromX: 0.85, toX: 0.15) }

    @MainActor
    func test_firstSession() throws {
        let app = XCUIApplication()
        app.launch()

        // 1. Health prompt: Review → switch → Next. The Health sheet is a
        // remote view that XCUITest can't query, so it is driven by position.
        shot("w01-health-prompt", settle: 4)
        tap(app, x: 0.5, y: 0.92)   // Review
        shot("w02-write-access", settle: 2)
        tap(app, x: 0.84, y: 0.46)  // "All Requested Data Below" switch
        XCUIDevice.shared.rotateDigitalCrown(delta: 3.0)
        shot("w03-write-access-next", settle: 2)
        // Later Health pages don't respond to synthesized taps in the
        // simulator; back out and close so the rest of the session can run.
        for _ in 0..<3 { tap(app, x: 0.12, y: 0.11); Thread.sleep(forTimeInterval: 1.5) }

        // 2. First-use guide offer — "Not now" so the real match can start.
        shot("w04-after-health", settle: 3)
        tapButton("Not now", in: app, timeout: 4)
        shot("w05-home")

        // 3. Start Match → who serves first.
        XCTAssertTrue(tapButton("Start Match", in: app, timeout: 10))
        shot("w06a-warming-up")
        XCTAssertTrue(tapButton("Warm Up Complete", in: app, timeout: 5))
        shot("w06b-who-serves")
        XCTAssertTrue(tapButton("Me", in: app, timeout: 5))
        shot("w07-scoreboard-0-0", settle: 2)

        // 4. Score: up = my point, down = theirs, left = undo.
        myPoint(app)
        shot("w08-15-0")
        theirPoint(app)
        shot("w09-15-15")
        myPoint(app)
        shot("w10-30-15")
        theirPoint(app)
        shot("w11-30-30-mistake")
        undo(app)
        shot("w12-undo-back-to-30-15")
        myPoint(app)
        shot("w13-40-15")
        myPoint(app)
        shot("w14-game-1-0", settle: 2)
        // A changeover prompt follows the first game.
        if tapButton("OK", in: app, timeout: 3) { shot("w15-after-changeover-ok") }
        // Play a few more games so the history has something to show.
        for meWins in [false, false, true, false, false, true, true, false, true, true, false, true, true, true] {
            if meWins { myPoint(app) } else { theirPoint(app) }
            Thread.sleep(forTimeInterval: 0.3)
            if tapButton("OK", in: app, timeout: 0.8) { Thread.sleep(forTimeInterval: 0.5) }
        }
        shot("w16-later-in-match", settle: 2)

        // 5. The ✕ in the corner goes back to the home screen to finish.
        tapButton("Close", in: app)
        shot("w18-back-home")
        if tapButton("End Match", in: app, timeout: 5) {
            shot("w19-end-confirm")
            tap(app, x: 0.5, y: 0.58)   // alert's End Match
        }
        shot("w20-home-after-end", settle: 2)

        // 6. Past Matches.
        if tapButton("Past Matches", in: app, timeout: 5) {
            shot("w21-past-matches")
            app.cells.firstMatch.tap()
            shot("w22-past-match-detail", settle: 2)
        }
    }
}
