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

    /// Regression: the permanent-delete confirmation used to be attached to the
    /// archive row itself, so tapping the swipe action closed the swipe, tore down
    /// the cell the dialog was anchored in, and dismissed it a moment after it
    /// appeared — the match could never be deleted by swiping. It survived only on
    /// the long-press path, which doesn't reconfigure the cell.
    ///
    /// No Watch is needed to reproduce it: the simulator is unpaired, so every
    /// archive row resolves to `.phoneOnly` and its swipe offers exactly "Delete"
    /// (with full-swipe off, so the swipe reveals the button rather than firing it).
    @MainActor
    func testSwipeDeleteConfirmationStaysUntilAnswered() throws {
        let app = XCUIApplication()
        app.launch()

        // Seed a throwaway match to act on, the same way the export test does.
        let manualEntry = app.buttons["Manual match entry"]
        XCTAssertTrue(manualEntry.waitForExistence(timeout: 10))
        manualEntry.tap()

        let save = app.buttons["Save Match"]
        for _ in 0..<6 where !save.exists {
            app.swipeUp()
        }
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        // Manual entry stamps the match with `Date()`, so it sorts newest-first.
        let newestMatch = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'match-row-'")
        ).firstMatch
        XCTAssertTrue(newestMatch.waitForExistence(timeout: 5))
        // Pin the identifier: after the delete, `firstMatch` would happily resolve
        // to whatever row took its place and the assertion would pass vacuously.
        let rowIdentifier = newestMatch.identifier

        newestMatch.swipeLeft()
        let deleteAction = app.buttons["Delete"].firstMatch
        XCTAssertTrue(deleteAction.waitForExistence(timeout: 5))
        deleteAction.tap()

        let confirm = app.buttons["Delete Permanently"].firstMatch
        XCTAssertTrue(
            confirm.waitForExistence(timeout: 5),
            "Swiping to Delete should raise the permanent-delete confirmation"
        )

        // The heart of it: the dialog must still be there a beat later. An inverted
        // expectation reports the disappearance itself rather than a bare sleep.
        let vanished = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: confirm
        )
        vanished.isInverted = true
        wait(for: [vanished], timeout: 3)

        // Confirming still deletes — which also leaves no test match behind for the
        // seed-gated test below.
        confirm.tap()
        let rowGone = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: app.buttons[rowIdentifier]
        )
        wait(for: [rowGone], timeout: 5)
    }

    /// Positive counterpart to the skip-when-empty gate above: a match that DOES
    /// carry HealthKit data must surface the "Share health data?" disclosure before
    /// anything leaves the device. Health only exists on a real watch-recorded
    /// match, so this test requires the archive to be seeded with a health-bearing
    /// match (the default seed match carries HR + steps) via `DeuceMateArchiveTool
    /// seed` — see docs/screenshots/README.md and docs/architecture/health-data-flow.md
    /// §6. It SKIPS cleanly when the archive is not seeded rather than failing.
    @MainActor
    func testHealthBearingMatchShowsConsentDisclosureBeforeSharing() throws {
        let targetMatchID = ProcessInfo.processInfo.environment["DEUCEMATE_TARGET_MATCH_ID"]
            ?? "5ABCB95C-1E5E-4554-B2B6-503C7C85F0C0"

        let app = XCUIApplication()
        app.launch()

        let matchRow = app.buttons["match-row-\(targetMatchID)"]
        for _ in 0..<6 where !matchRow.exists {
            app.swipeUp()
        }
        try XCTSkipUnless(
            matchRow.waitForExistence(timeout: 10),
            "Archive not seeded with health-bearing match \(targetMatchID) — run `DeuceMateArchiveTool seed` first; see docs/screenshots/README.md."
        )
        matchRow.tap()

        let disclosure = app.staticTexts["Share health data?"]

        // 1) AI Coach hand-off: gated at sheet entry with the disclosure, so the
        // sheet must NOT open until the user confirms.
        let aiCoach = app.buttons
            .matching(NSPredicate(format: "label CONTAINS[c] 'ai coach'"))
            .firstMatch
        XCTAssertTrue(aiCoach.waitForExistence(timeout: 10))
        aiCoach.tap()
        XCTAssertTrue(
            disclosure.waitForExistence(timeout: 5),
            "A health-bearing match must show the health disclosure before the AI Coach hand-off"
        )
        app.buttons["Cancel"].tap()
        XCTAssertFalse(
            app.buttons["Copy Prompt to Clipboard"].waitForExistence(timeout: 2),
            "Cancelling the disclosure must not open the AI Coach sheet"
        )

        // 2) Sharing: the disclosure must precede the system share sheet.
        let export = app.buttons["Export match"]
        XCTAssertTrue(export.waitForExistence(timeout: 10))
        export.tap()
        let shareSummary = app.buttons["Share Summary"].firstMatch
        XCTAssertTrue(shareSummary.waitForExistence(timeout: 5))
        shareSummary.tap()
        XCTAssertTrue(
            disclosure.waitForExistence(timeout: 5),
            "A health-bearing match must show the health disclosure before sharing"
        )
        app.buttons["Cancel"].tap()
        XCTAssertFalse(
            app.otherElements["ActivityListView"].waitForExistence(timeout: 2),
            "Cancelling the disclosure must not present the share sheet"
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
