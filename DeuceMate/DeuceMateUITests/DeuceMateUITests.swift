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

    /// Regression coverage for the selected-row confirmation presenter: the row's
    /// frame is captured before the swipe closes, while the stable List overlay
    /// owns the dialog. Cancellation must keep the row tappable and repeatable;
    /// only confirming may remove it, including after the app relaunches.
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
        let rowFrame = newestMatch.frame
        captureDeletionScreen(app, named: "Archive before deletion")

        // Long-press path: the explicit popover must be adjacent to the row it
        // describes, not attached to the Trends section or screen container.
        newestMatch.press(forDuration: 1)
        let contextDelete = app.buttons["Delete Permanently"].firstMatch
        XCTAssertTrue(contextDelete.waitForExistence(timeout: 5))
        contextDelete.tap()

        let popover = app.descendants(matching: .any)["permanent-delete-popover"]
        XCTAssertTrue(
            popover.waitForExistence(timeout: 5),
            "Long-press Delete Permanently should raise the selected-row popover"
        )
        captureDeletionScreen(app, named: "Long-press confirmation")
        let popoverFrame = popover.frame
        let horizontalGap = max(
            rowFrame.minX - popoverFrame.maxX,
            popoverFrame.minX - rowFrame.maxX,
            0
        )
        let verticalGap = max(
            rowFrame.minY - popoverFrame.maxY,
            popoverFrame.minY - rowFrame.maxY,
            0
        )
        XCTAssertLessThanOrEqual(
            hypot(horizontalGap, verticalGap),
            48,
            "Permanent-delete popover should remain adjacent to its match row"
        )

        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertFalse(popover.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons[rowIdentifier].isHittable)

        // Swipe path: closing/replacing the swipe cell must not dismiss the stable
        // List-owned popover.
        newestMatch.swipeLeft()
        XCTAssertFalse(popover.exists, "A full swipe must not request permanent deletion")
        XCTAssertTrue(app.buttons[rowIdentifier].exists)
        let deleteAction = app.buttons["Delete"].firstMatch
        XCTAssertTrue(deleteAction.waitForExistence(timeout: 5))
        deleteAction.tap()

        let confirm = app.buttons["Delete Permanently"].firstMatch
        XCTAssertTrue(
            confirm.waitForExistence(timeout: 5),
            "Swiping to Delete should raise the permanent-delete confirmation"
        )
        captureDeletionScreen(app, named: "Swipe confirmation")
        XCTAssertTrue(app.buttons[rowIdentifier].exists, "The row must remain until confirmation")

        // The heart of it: the dialog must still be there a beat later. An inverted
        // expectation reports the disappearance itself rather than a bare sleep.
        let vanished = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: confirm
        )
        vanished.isInverted = true
        wait(for: [vanished], timeout: 3)

        cancel.tap()
        XCTAssertFalse(popover.waitForExistence(timeout: 2))
        let retainedMatch = app.buttons[rowIdentifier]
        XCTAssertTrue(retainedMatch.isHittable)
        retainedMatch.tap()
        let done = app.navigationBars.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "Cancel must leave the row selectable")
        done.tap()

        // A second swipe on the same row must still work after cancelling and
        // opening its detail sheet; no stale presentation may consume the gesture.
        retainedMatch.swipeLeft()
        XCTAssertTrue(deleteAction.waitForExistence(timeout: 5))
        deleteAction.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))

        // Confirming still deletes — which also leaves no test match behind for the
        // seed-gated test below.
        confirm.tap()
        let rowGone = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: app.buttons[rowIdentifier]
        )
        wait(for: [rowGone], timeout: 5)
        XCTAssertFalse(popover.exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(manualEntry.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons[rowIdentifier].exists, "Confirmed deletion must persist")
    }

    @MainActor
    func testDeleteConfirmationTracksDifferentRowsAfterScrolling() throws {
        let app = XCUIApplication()
        app.launch()

        // Create enough disposable rows to scroll even in an empty archive.
        // Never confirm deletion of a pre-existing simulator match.
        var createdRows: [String] = []
        for _ in 0..<6 {
            let manualEntry = app.buttons["Manual match entry"]
            XCTAssertTrue(manualEntry.waitForExistence(timeout: 10))
            manualEntry.tap()
            let save = app.buttons["Save Match"]
            for _ in 0..<6 where !save.isHittable {
                app.swipeUp()
            }
            XCTAssertTrue(save.isHittable)
            save.tap()
            let newest = app.buttons.matching(
                NSPredicate(format: "identifier BEGINSWITH 'match-row-'")
            ).firstMatch
            XCTAssertTrue(newest.waitForExistence(timeout: 5))
            createdRows.append(newest.identifier)
        }
        XCTAssertEqual(Set(createdRows).count, 6)

        let popover = app.descendants(matching: .any)["permanent-delete-popover"]
        // Oldest first forces scrolling. Each following row then has a different
        // source position, exposing stale or screen-centred popup anchors.
        for (index, identifier) in createdRows.enumerated() {
            let row = app.buttons[identifier]
            for _ in 0..<8 {
                if row.isHittable && row.frame.minY > 115 && row.frame.maxY < app.frame.maxY - 60 {
                    break
                }
                if row.exists && row.frame.minY < 115 {
                    app.swipeDown()
                } else {
                    app.swipeUp()
                }
            }
            XCTAssertTrue(row.isHittable)
            let rowFrame = row.frame
            if index.isMultiple(of: 2) {
                row.press(forDuration: 1)
                let menuDelete = app.buttons["Delete Permanently"].firstMatch
                XCTAssertTrue(menuDelete.waitForExistence(timeout: 5))
                menuDelete.tap()
            } else {
                row.swipeLeft()
                let swipeDelete = app.buttons["Delete"].firstMatch
                XCTAssertTrue(swipeDelete.waitForExistence(timeout: 5))
                swipeDelete.tap()
            }
            XCTAssertTrue(popover.waitForExistence(timeout: 5))
            captureDeletionScreen(app, named: "Scrolled row confirmation \(index + 1)")
            let popupFrame = popover.frame
            XCTAssertLessThanOrEqual(
                min(abs(popupFrame.minY - rowFrame.midY), abs(popupFrame.maxY - rowFrame.midY)),
                48,
                "The popup edge must point to this row's centre, even after scrolling"
            )
            XCTAssertTrue(row.exists)
            app.buttons["Delete Permanently"].firstMatch.tap()
            let removed = expectation(
                for: NSPredicate(format: "exists == false"),
                evaluatedWith: row
            )
            wait(for: [removed], timeout: 5)
            XCTAssertFalse(popover.exists)
            for remaining in createdRows.dropFirst(index + 1) {
                // List virtualizes off-screen cells. Reveal each newer survivor
                // before asserting it is still present and interactive.
                let survivor = app.buttons[remaining]
                for _ in 0..<8 where !survivor.isHittable {
                    app.swipeDown()
                }
                XCTAssertTrue(survivor.isHittable, "Deleting one row must preserve the others")
            }
        }
    }

    @MainActor
    private func captureDeletionScreen(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
