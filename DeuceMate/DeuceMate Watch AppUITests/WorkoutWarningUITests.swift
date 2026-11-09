import XCTest

final class WorkoutWarningUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--workout-ui-test"]
        app.launch()
        XCTAssertTrue(app.buttons["failWorkoutRecording"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor func testRecordingWarningOnLiveScreenCanBeDismissedAndReturnsForNextFailure() {
        let app = launch()
        app.buttons["failWorkoutRecording"].tap()
        let warning = app.staticTexts["workoutWarning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        XCTAssertTrue(warning.label.contains("Fitness recording"))
        app.buttons["dismissWorkoutWarning"].tap()
        XCTAssertTrue(warning.waitForNonExistence(timeout: 5))
        app.buttons["failWorkoutRecording"].tap()
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
    }

    @MainActor func testDelayedSaveFailureRemainsVisibleAfterReturningHome() {
        let app = launch()
        app.buttons["parkWorkout"].tap()
        XCTAssertTrue(app.buttons["Start Match"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["workoutWarning"].exists)
        app.buttons["failWorkoutSave"].tap()
        let warning = app.staticTexts["workoutWarning"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        XCTAssertTrue(warning.label.contains("couldn’t be saved to Health"))
        XCTAssertTrue(warning.label.contains("match score is kept"))
        app.buttons["dismissWorkoutWarning"].tap()
        XCTAssertTrue(warning.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start Match"].exists)
    }
}
