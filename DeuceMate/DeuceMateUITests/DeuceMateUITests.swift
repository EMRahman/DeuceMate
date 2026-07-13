//
//  DeuceMateUITests.swift
//  DeuceMateUITests
//

import XCTest

final class DeuceMateUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testManualMatchCanBeReviewedAndExportedWithoutWatchInteraction() throws {
        let app = XCUIApplication()
        app.launch()

        let manualEntry = app.buttons["Manual match entry"]
        XCTAssertTrue(manualEntry.waitForExistence(timeout: 10))
        manualEntry.tap()

        let save = app.buttons["Save Match"]
        for _ in 0..<6 where !save.exists {
            app.swipeUp()
        }
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isHittable)
        XCTAssertTrue(save.isEnabled)
        save.tap()

        let newestMatch = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'match-row-'")
        ).firstMatch
        XCTAssertTrue(newestMatch.waitForExistence(timeout: 5))
        newestMatch.tap()

        XCTAssertTrue(
            app.staticTexts["In Progress — view only on iPhone"]
                .waitForExistence(timeout: 5)
        )

        let emptyGraph = app.staticTexts["No Points to Graph"]
        for _ in 0..<4 where !emptyGraph.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(emptyGraph.isHittable)

        let emptyStats = app.staticTexts["No point-by-point statistics were recorded for this match."]
        for _ in 0..<4 where !emptyStats.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(emptyStats.isHittable)

        let export = app.buttons["Export match"]
        XCTAssertTrue(export.waitForExistence(timeout: 10))
        export.tap()
        XCTAssertTrue(app.buttons["Interactive Web Page"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
