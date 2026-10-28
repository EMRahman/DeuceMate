import XCTest

/// Opt-in end-to-end comparison evidence using the browser's exact match fixtures.
/// Generate with scripts/iphone-demo-native-fixtures.cjs and import using
/// NativeDemoParitySeedTests, then enable DEUCEMATE_NATIVE_PARITY in the test
/// runner environment. Never touches a real device.
final class NativeDemoParityTests: XCTestCase {
    private let completedID = "03D450C6-CBB3-1736-86C0-989EC0C26A06"
    private let inProgressID = "0DED8C0A-11AB-7805-C987-6AE17FC8C6B8"
    private let scoreOnlyID = "F52783C6-C19B-5622-2534-A7661A7599FE"

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if targetEnvironment(simulator)
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DEUCEMATE_NATIVE_PARITY"] == "1",
                          "Opt-in native/demo parity audit; requires seeded disposable simulator.")
        #else
        throw XCTSkip("The native demo parity audit is simulator-only.")
        #endif
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) throws {
        let directory = URL(fileURLWithPath: "/tmp/deucemate-native-parity-shots")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try app.screenshot().pngRepresentation.write(to: directory.appendingPathComponent(name + ".png"))
        try app.debugDescription.write(to: directory.appendingPathComponent(name + ".txt"), atomically: true, encoding: .utf8)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor private func reveal(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<12 where !element.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Matches"].waitForExistence(timeout: 15))
        return app
    }

    @MainActor func testManualEntryNativeAppearance() throws {
        let app = launch()
        app.buttons["Manual match entry"].tap()
        XCTAssertTrue(app.navigationBars["Manual Entry"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.steppers.firstMatch.exists)
        try capture(app, "18-native-manual-entry")
        app.swipeUp(velocity: .slow)
        try capture(app, "19-native-manual-game")
        app.navigationBars["Manual Entry"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Matches"].exists)
    }

    @MainActor func testShareMenuMatchesNativeExportChoices() throws {
        let app = launch()
        let row = app.buttons["match-row-" + completedID]
        reveal(app, row)
        row.tap()
        let export = app.buttons["Export match"]
        XCTAssertTrue(export.waitForExistence(timeout: 10))
        export.tap()
        XCTAssertTrue(app.buttons["Interactive Web Page"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "Share Summary").count, 2)
        XCTAssertEqual(app.buttons.matching(identifier: "Share Summary + Raw Points").count, 2)
        try capture(app, "15-native-share-menu")
        app.buttons["Interactive Web Page"].tap()
        XCTAssertTrue(app.buttons["My Perspective"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Opponent's Perspective"].exists)
        try capture(app, "16-native-share-perspective")
        app.buttons["Opponent's Perspective"].tap()
        XCTAssertTrue(app.alerts["Share health data?"].waitForExistence(timeout: 5))
        try capture(app, "17-native-share-disclosure")
        app.alerts.buttons["Cancel"].tap()
        XCTAssertFalse(app.otherElements["ActivityListView"].exists)
    }

    @MainActor func testTrackedDetailGraphAndPoints() throws {
        let app = launch()
        try capture(app, "01-native-archive")
        let row = app.buttons["match-row-" + completedID]
        reveal(app, row)
        row.tap()
        XCTAssertTrue(app.navigationBars["Match Stats"].waitForExistence(timeout: 8))
        try capture(app, "02-native-detail")
        let expand = app.buttons["expand-points-graph"]
        reveal(app, expand)
        expand.tap()
        XCTAssertTrue(app.navigationBars["Points Graph"].waitForExistence(timeout: 8))
        let pointsWon = app.buttons["points-won-chip"]
        reveal(app, pointsWon)
        pointsWon.tap()
        let steps = app.buttons["steps-overlay-toggle"]
        for _ in 0..<8 where !steps.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.86))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.61)))
        }
        XCTAssertTrue(steps.isHittable)
        steps.tap()
        let heartRate = app.buttons["heart-rate-overlay-toggle"]
        XCTAssertTrue(heartRate.isHittable)
        heartRate.tap()
        try capture(app, "03-native-expanded-graph")
        app.navigationBars["Points Graph"].buttons["Done"].tap()
        let points = app.segmentedControls.buttons["Points"]
        reveal(app, points)
        points.tap()
        try capture(app, "04-native-points")
        app.segmentedControls.buttons["Stats"].tap()
        let duration = app.staticTexts["Duration"]
        reveal(app, duration)
        try capture(app, "05-native-duration")
        let outcomes = app.staticTexts["Outcome Breakdown"]
        reveal(app, outcomes)
        try capture(app, "06-native-comparisons")
    }

    @MainActor func testTrendsFiltersAndSettingsOverride() throws {
        let app = launch()
        let trends = app.otherElements.matching(NSPredicate(format: "label BEGINSWITH 'Trends,'")).firstMatch
        XCTAssertTrue(trends.waitForExistence(timeout: 10))
        trends.tap()
        XCTAssertTrue(app.navigationBars["Trends"].waitForExistence(timeout: 8))
        // Trends persists its filters across launches. Begin with the full
        // seeded sample before verifying the deliberately sparse Doubles scope.
        let typePicker = app.segmentedControls.containing(.button, identifier: "Doubles").firstMatch
        typePicker.buttons["All"].tap()
        XCTAssertTrue(app.staticTexts["Errors"].waitForExistence(timeout: 5))
        try capture(app, "07-native-trends")
        app.segmentedControls.buttons["Count"].tap()
        app.segmentedControls.buttons["Doubles"].tap()
        XCTAssertTrue(app.staticTexts["Not Enough Matches"].waitForExistence(timeout: 5))
        try capture(app, "08-native-trends-filtered")
        app.navigationBars.buttons["Matches"].tap()
        let toolbarButtons = app.navigationBars["Matches"].buttons
        toolbarButtons.element(boundBy: toolbarButtons.count - 1).tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 8))
        try capture(app, "09-native-settings")
        let overrideToggle = app.switches.matching(NSPredicate(format: "label BEGINSWITH 'Override Max HR'")).firstMatch
        reveal(app, overrideToggle)
        if overrideToggle.value as? String != "1" {
            overrideToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        try capture(app, "10-native-override")
        XCTAssertEqual(overrideToggle.value as? String, "1")
        let birthYear = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Birth Year'")).firstMatch
        XCTAssertTrue(birthYear.exists)
        XCTAssertFalse(birthYear.isEnabled)
        overrideToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.navigationBars["Settings"].buttons["Done"].tap()
        let cloud = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'iCloud'")).firstMatch
        reveal(app, cloud)
        cloud.tap()
        try capture(app, "11-native-icloud-help")
        XCTAssertTrue(app.buttons["Open Settings"].waitForExistence(timeout: 5))
    }

    @MainActor func testScoreOnlyAndEndAtCurrentScore() throws {
        let app = launch()
        let scoreOnly = app.buttons["match-row-" + scoreOnlyID]
        reveal(app, scoreOnly)
        scoreOnly.tap()
        XCTAssertTrue(app.navigationBars["Perpetual Points"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.segmentedControls.buttons["Stats"].exists)
        XCTAssertFalse(app.segmentedControls.buttons["Points"].exists)
        try capture(app, "12-native-score-only")
        app.navigationBars.buttons["Done"].tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.navigationBars["Matches"].waitForExistence(timeout: 15))
        let inProgress = app.buttons["match-row-" + inProgressID]
        reveal(app, inProgress)
        inProgress.tap()
        let end = app.buttons["End at Current Score"]
        XCTAssertTrue(end.waitForExistence(timeout: 8))
        end.tap()
        try capture(app, "13-native-end-confirmation")
        let confirmation = app.sheets["End at current score?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        // Current iOS presents confirmation dialogs as popovers, omitting the
        // explicit cancel row and exposing a dismiss region instead.
        if app.buttons["Cancel"].exists {
            app.buttons["Cancel"].tap()
        } else {
            let dismissRegion = app.otherElements["PopoverDismissRegion"]
            XCTAssertTrue(dismissRegion.exists)
            dismissRegion.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.2)).tap()
        }
        XCTAssertFalse(confirmation.exists)
        XCTAssertTrue(end.isHittable)
        end.tap()
        app.sheets.buttons["End at Current Score"].tap()
        let manualEntry = app.buttons["Manual match entry"]
        let returnedToArchive = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: manualEntry)
        wait(for: [returnedToArchive], timeout: 8)
        XCTAssertFalse(app.buttons["End at Current Score"].exists)
        try capture(app, "14-native-ended-archive")
    }
}
