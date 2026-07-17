// LiveMatchScreenshotTests.swift — drives a real live match on the watch via
// gesture automation (the app's whole live-scoring model is swipe-based), for
// the docs/screenshots/README.md watch scoreboard (04) and hero composite (01)
// shots. Not part of the regular regression suite; run explicitly via
// `xcodebuild test -only-testing:"DeuceMate Watch AppUITests"/LiveMatchScreenshotTests`
// against a watch simulator paired with a booted phone simulator (`xcrun simctl
// pair`), so the phone mirrors the match live over WatchConnectivity.
import XCTest

private let screenshotOutputDir = "/private/tmp/claude-501/-Users-ehsanrahman-Library-Mobile-Documents-com-apple-CloudDocs-Git2-DeuceMate/ef616c1f-7d65-43b2-8a63-04f9d90681c1/scratchpad/watch-shots"

final class LiveMatchScreenshotTests: XCTestCase {

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
    func test_playLiveMatch() throws {
        let app = XCUIApplication()
        app.launch()

        // First launch prompts for HealthKit access; decline (the "X" close
        // button) so it doesn't block the rest of the flow — Simulator has no
        // real sensor data to grant access to anyway.
        let dismissHealthAccess = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'close'")).firstMatch
        if dismissHealthAccess.waitForExistence(timeout: 5) {
            dismissHealthAccess.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.15)).tap()
        }
        Thread.sleep(forTimeInterval: 1)

        // A prior interrupted run can leave a match in progress (HomeView
        // then shows "Resume Match"/"End Match" instead of "Start Match") —
        // clear it first so this run starts from a clean slate.
        let endMatch = app.buttons["End Match"]
        if endMatch.waitForExistence(timeout: 3) {
            endMatch.tap()
            let confirmEnd = app.buttons["End Match"].firstMatch
            XCTAssertTrue(confirmEnd.waitForExistence(timeout: 5))
            confirmEnd.tap()
            Thread.sleep(forTimeInterval: 1)
        }

        let startMatch = app.buttons["Start Match"]
        XCTAssertTrue(startMatch.waitForExistence(timeout: 20))
        startMatch.tap()

        let standardFormat = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] 'Best of 3 Sets (Club'"))
            .firstMatch
        XCTAssertTrue(standardFormat.waitForExistence(timeout: 10))
        standardFormat.tap()

        let warmUp = app.buttons["Warm Up Complete"]
        XCTAssertTrue(warmUp.waitForExistence(timeout: 10))
        warmUp.tap()

        let singles = app.buttons["Singles"]
        XCTAssertTrue(singles.waitForExistence(timeout: 10))
        singles.tap()

        let meServes = app.buttons["Me"]
        XCTAssertTrue(meServes.waitForExistence(timeout: 10))
        meServes.tap()

        // Live scoreboard should be up now. Play out a realistic mid-match
        // stretch via real swipe gestures (swipe up = point to me, swipe down
        // = point to opponent) — a natural-looking score, not an exact replay.
        let sequence: [Bool] = [ // true = me, false = opponent
            true, true, false, true,             // 0-40, me holds
            false, false, true, false,           // opp holds
            true, true, true, false,             // me holds
            false, true, false, false,           // opp holds
            true, false, true, true,             // me holds
            false, false, false, true, false     // opp ahead in next game
        ]
        for meWins in sequence {
            if meWins {
                app.swipeUp()
            } else {
                app.swipeDown()
            }
            Thread.sleep(forTimeInterval: 0.15)
        }

        Thread.sleep(forTimeInterval: 1.5)

        // Odd-game changeovers show a dismissible "players change ends"
        // prompt over the scoreboard — clear it before capturing.
        let changeoverOK = app.buttons["OK"]
        if changeoverOK.waitForExistence(timeout: 2) {
            changeoverOK.tap()
            Thread.sleep(forTimeInterval: 1)
        }

        saveScreenshot("04-watch-scoreboard")
    }
}
