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

        // AI Coach hand-off: this health-free match (see below) opens the sheet
        // with no disclosure — the same skip-when-empty gate as sharing.
        // Dismissed here so the share check can run afterwards.
        let aiCoach = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] 'ai coach'"))
            .firstMatch
        XCTAssertTrue(aiCoach.waitForExistence(timeout: 10))
        aiCoach.tap()
        XCTAssertFalse(
            app.staticTexts["Share health data?"].waitForExistence(timeout: 2),
            "A health-free match must not show the health disclosure"
        )
        XCTAssertTrue(app.buttons["Copy Prompt to Clipboard"].waitForExistence(timeout: 5))
        app.navigationBars["AI Coach"].buttons["Done"].tap()

        let export = app.buttons["Export match"]
        XCTAssertTrue(export.waitForExistence(timeout: 10))
        export.tap()
        XCTAssertTrue(app.buttons["Interactive Web Page"].waitForExistence(timeout: 5))

        // This match was just entered and never resumed/played on a Watch (the
        // sim is unpaired), so it holds no HealthKit data yet. Sharing it must
        // therefore skip the per-export health disclosure and present the share
        // sheet directly — verifying the consent gate's skip-when-empty path.
        // (A resumed-and-played match gains health data and would show the
        // disclosure; that data-driven behavior is covered by the Core tests.)
        let shareSummary = app.buttons["Share Summary"].firstMatch
        XCTAssertTrue(shareSummary.waitForExistence(timeout: 5))
        shareSummary.tap()
        XCTAssertFalse(
            app.staticTexts["Share health data?"].waitForExistence(timeout: 2),
            "A health-free match must not show the health disclosure"
        )
        XCTAssertTrue(
            app.otherElements["ActivityListView"].waitForExistence(timeout: 8),
            "The system share sheet should present directly"
        )
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
