import XCTest

final class WalkthroughUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor private func tap(_ identifier: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        if !button.isHittable {
            for _ in 0..<4 where !button.isHittable { app.swipeUp() }
        }
        XCTAssertTrue(button.isHittable, "Unreachable \(identifier)")
        button.tap()
    }
    @MainActor private func tapCanvas(in app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
    }
    @MainActor private func waitForStep(_ step: Int, in app: XCUIApplication, timeout: TimeInterval = 16) {
        XCTAssertTrue(app.staticTexts["\(step)/9"].waitForExistence(timeout: timeout))
    }
    @MainActor private func screenshot(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    @MainActor private func assertReplica(in app: XCUIApplication, step: Int) {
        let score = app.descendants(matching: .any).matching(identifier: "guideScoreboard").firstMatch
        XCTAssertTrue(score.exists)
        XCTAssertGreaterThanOrEqual(score.frame.minX, 0)
        XCTAssertLessThanOrEqual(score.frame.maxX, app.frame.maxX)
        XCTAssertGreaterThanOrEqual(score.frame.height, 70, "Score rows must use live size")
        XCTAssertTrue(app.staticTexts["DEMO"].exists)
        XCTAssertTrue(app.staticTexts["\(step)/9"].exists)
        let heartRate = app.descendants(matching: .any).matching(identifier: "guideHeartRate").firstMatch
        let metrics = app.descendants(matching: .any).matching(identifier: "guideMetrics").firstMatch
        XCTAssertTrue(heartRate.exists)
        XCTAssertTrue(metrics.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "guideMomentum").firstMatch.exists)
        XCTAssertLessThanOrEqual(heartRate.frame.maxX, app.frame.maxX)
        XCTAssertGreaterThanOrEqual(heartRate.frame.height, 35, "Heart rate badge must use live size")
        XCTAssertLessThanOrEqual(metrics.frame.maxY, app.frame.maxY + 1,
                                 "Calories and elapsed time must fit on screen")
        XCTAssertTrue(app.buttons["guideClose"].isHittable)
    }

    @MainActor func testNineFullscreenDemosAndCompletion() {
        let app = XCUIApplication()
        app.launchArguments = ["--walkthrough-ui-test"]
        app.launch()
        waitForStep(1, in: app)
        assertReplica(in: app, step: 1)
        for step in 1...9 {
            waitForStep(step, in: app)
            let play = app.buttons["guidePlayExample"]
            XCTAssertTrue(play.waitForExistence(timeout: 5), "Example \(step) must wait for a tap")
            XCTAssertTrue(play.label.contains("Play example"))
            if step == 4 {
                XCTAssertTrue(play.label.contains("record your loss for an unforced error during a rally"))
            } else if step == 5 {
                XCTAssertTrue(play.label.contains("double tap to record a second serve"))
            } else if step == 9 {
                XCTAssertTrue(play.label.contains("Notice the sticky reminder until the next point"))
            }
            screenshot("Guide \(step): commentary", in: app)
            play.tap()
            if step >= 8 {
                let reason = step == 8 ? "Even games – balls change ends" : "Set complete – players change ends"
                XCTAssertTrue(app.staticTexts[reason].waitForExistence(timeout: 15))
                screenshot("Guide \(step): changeover reason", in: app)
            }
            if step == 9 {
                XCTAssertTrue(app.staticTexts["Players change ends"].waitForExistence(timeout: 15))
                screenshot("Guide \(step): reminder", in: app)
            }
            if step == 7 {
                let error = app.descendants(matching: .any).matching(identifier: "countStat-Unforced Errors").firstMatch
                XCTAssertTrue(error.waitForExistence(timeout: 8))
                XCTAssertEqual(error.label, "Unforced Errors. Me: 1. Opp: 0.")
                let fault = app.descendants(matching: .any).matching(identifier: "countStat-Double Faults").firstMatch
                XCTAssertTrue(fault.waitForExistence(timeout: 8))
                XCTAssertEqual(fault.label, "Double Faults. Me: 1. Opp: 0.")
            }
            screenshot("Guide \(step): fullscreen", in: app)
        }
        XCTAssertTrue(app.buttons["Animated guide"].waitForExistence(timeout: 16))
    }

    @MainActor func testTapStartsOnlyCurrentExampleAndGuideReopensAtFirstFixture() {
        let app = XCUIApplication()
        app.launchArguments = ["--walkthrough-ui-test", "--walkthrough-reduce-motion"]
        app.launch()
        let play = app.buttons["guidePlayExample"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["2/9"].waitForExistence(timeout: 2),
                       "Commentary stays until tapped")
        tapCanvas(in: app) // The first tap starts the example.
        XCTAssertTrue(app.buttons["guideClose"].exists)
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: play)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
        tapCanvas(in: app) // During playback: no extra score or navigation.
        XCTAssertTrue(app.buttons["guideClose"].exists)
        waitForStep(2, in: app)
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["3/9"].waitForExistence(timeout: 2),
                       "The next example also waits for a tap")
        let score = app.descendants(matching: .any).matching(identifier: "guideScoreboard").firstMatch
        XCTAssertTrue(score.label.contains("Games"), "The score remains a read-only replica")
        tap("guideClose", in: app)
        XCTAssertTrue(app.buttons["Animated guide"].waitForExistence(timeout: 5))
        tap("Animated guide", in: app)
        XCTAssertTrue(app.staticTexts["1/9"].waitForExistence(timeout: 5))
        XCTAssertTrue(score.label.contains("Points 0–0"))
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        screenshot("Guide: reopened fresh fixture, Reduce Motion", in: app)
    }

    @MainActor func testBackgroundReturnKeepsCurrentExample() {
        let app = XCUIApplication()
        app.launchArguments = ["--walkthrough-ui-test"]
        app.launch()
        let score = app.descendants(matching: .any).matching(identifier: "guideScoreboard").firstMatch
        XCTAssertTrue(score.waitForExistence(timeout: 5))
        tap("guidePlayExample", in: app)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["1/9"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["guidePlayExample"].waitForExistence(timeout: 5),
                      "An interrupted demonstration restarts at its commentary")
        XCTAssertTrue(score.label.contains("Points 0–0"))
    }
}
