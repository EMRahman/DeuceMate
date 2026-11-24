// ArchiveExportReminderUITests.swift — end-to-end iPhone UI coverage for the
// periodic manual archive export reminder card and Settings › Backup & Transfer
// controls (docs/features/ARCHIVE_EXPORT_REMINDER_PLAN.md §7).
//
// Creates 5 completed matches through Manual Entry + End at Current Score (and
// adds a private note to each so every match counts regardless of simulator
// iCloud sign-in state), then verifies the card appears, Export Archive opens
// the shared options sheet with private notes off, Don't Remind Me Again turns
// the Settings toggle off, re-enabling restores the card immediately, and Later
// hides the card without turning off the toggle. Cleans up every created match
// and restores the reminder toggle in tearDown.
import XCTest

final class ArchiveExportReminderUITests: XCTestCase {
    private let app = XCUIApplication()
    private var createdRows: [String] = []
    private let note = "export reminder ui test note"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        MainActor.assumeIsolated {
            app.terminate()
            app.launch()
            if app.buttons["Manual match entry"].waitForExistence(timeout: 15) {
                for identifier in createdRows.reversed() {
                    deleteMatch(identifier)
                }
                ensureReminderToggleOn()
            }
        }
        createdRows.removeAll()
    }

    @MainActor
    func testReminderCardAppearsAfterFiveCountableMatchesAndControlsWork() throws {
        app.launch()
        XCTAssertTrue(app.buttons["Manual match entry"].waitForExistence(timeout: 15))
        ensureReminderToggleOn()

        // Seed 5 completed matches with private notes so they are always
        // countable whether iCloud Drive is signed in or unavailable.
        for _ in 0..<5 {
            createCompletedMatchWithNote()
        }

        // Scroll to the top of Matches so the first section is visible.
        let card = app.descendants(matching: .any)["export-reminder-card"]
        for _ in 0..<6 where !card.exists { app.swipeDown() }
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Reminder card should appear once 5 countable matches exist")

        // Export Archive opens the shared ArchiveExportOptionsSheet with private notes OFF.
        let exportButton = app.buttons["export-reminder-export"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        exportButton.tap()
        XCTAssertTrue(app.navigationBars["Export Match Archive"].waitForExistence(timeout: 5))
        let includeNotes = app.switches["archive-include-notes"]
        XCTAssertTrue(includeNotes.waitForExistence(timeout: 5))
        XCTAssertEqual(includeNotes.value as? String, "0", "Private notes must default OFF when opened from the reminder card")

        // Cancelling the sheet leaves the card showing.
        app.navigationBars["Export Match Archive"].buttons["Cancel"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Cancelling export must leave the card visible")

        // Don't Remind Me Again hides the card and turns the Settings toggle OFF.
        let neverButton = app.buttons["export-reminder-never"]
        XCTAssertTrue(neverButton.waitForExistence(timeout: 5))
        neverButton.tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5), "Don't Remind Me Again must hide the card")

        openSettings()
        let toggle = findSettingsElement(app.switches["archive-export-reminder-toggle"])
        XCTAssertTrue(toggle.exists)
        XCTAssertEqual(toggle.value as? String, "0", "Don't Remind Me Again must switch Remind Me to Export OFF")
        XCTAssertTrue(findSettingsElement(app.staticTexts["archive-last-exported"]).exists)

        // Turning the toggle back ON shows the card again straight away.
        flipSwitch(toggle)
        XCTAssertEqual(toggle.value as? String, "1")
        app.navigationBars["Settings"].buttons["Done"].tap()
        for _ in 0..<4 where !card.exists { app.swipeDown() }
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Re-enabling the toggle with 5+ unexported matches must show the card")

        // Later hides the card without turning off the Settings toggle.
        let laterButton = app.buttons["export-reminder-later"]
        XCTAssertTrue(laterButton.waitForExistence(timeout: 5))
        laterButton.tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 5), "Later must hide the card")

        openSettings()
        let toggleAfterLater = findSettingsElement(app.switches["archive-export-reminder-toggle"])
        XCTAssertEqual(toggleAfterLater.value as? String, "1", "Later must keep reminders enabled in Settings")
        app.navigationBars["Settings"].buttons["Done"].tap()
    }

    // MARK: - Helpers

    @MainActor
    private func createCompletedMatchWithNote() {
        app.buttons["Manual match entry"].tap()
        XCTAssertTrue(app.navigationBars["Manual Entry"].waitForExistence(timeout: 5))
        let save = app.buttons["Save Match"]
        for _ in 0..<6 where !save.isHittable { app.swipeUp() }
        save.tap()

        let newest = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'match-row-'")).firstMatch
        XCTAssertTrue(newest.waitForExistence(timeout: 5))
        let identifier = newest.identifier
        createdRows.append(identifier)

        // Open the match once: add a private note, then complete it.
        openMatch(identifier)
        let notesRow = app.buttons["match-notes-row"]
        for _ in 0..<6 where !notesRow.isHittable { app.swipeUp() }
        XCTAssertTrue(notesRow.waitForExistence(timeout: 5))
        notesRow.tap()

        let editor = app.textViews["match-notes-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(note)
        app.buttons["save-match-note"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))

        let end = app.buttons["End at Current Score"]
        for _ in 0..<6 where !(end.exists && end.isHittable) { app.swipeDown() }
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        end.tap()
        let dialog = app.sheets.buttons["End at Current Score"].exists
            ? app.sheets.buttons["End at Current Score"]
            : app.buttons.matching(identifier: "End at Current Score").element(boundBy: 1)
        (dialog.exists ? dialog : app.buttons["End at Current Score"].firstMatch).tap()
        XCTAssertTrue(app.buttons["Manual match entry"].waitForExistence(timeout: 8))
    }

    @MainActor
    private func revealRow(_ identifier: String) -> XCUIElement {
        let row = app.buttons[identifier]
        for _ in 0..<10 where !row.isHittable {
            if row.exists && row.frame.minY < 120 { app.swipeDown() } else { app.swipeUp() }
        }
        return row
    }

    @MainActor
    private func openMatch(_ identifier: String) {
        let row = revealRow(identifier)
        XCTAssertTrue(row.isHittable, "Row \(identifier)")
        row.tap()
        let disclosure = app.buttons["match-info-disclosure"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 8))
        if disclosure.value as? String == "Collapsed" { disclosure.tap() }
        XCTAssertTrue(app.buttons["match-info-row"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func deleteMatch(_ identifier: String) {
        let row = revealRow(identifier)
        guard row.exists else { return }
        row.press(forDuration: 1)
        let menuDelete = app.buttons["Delete Permanently"].firstMatch
        guard menuDelete.waitForExistence(timeout: 5) else { return }
        menuDelete.tap()
        let confirm = app.buttons["Delete Permanently"].firstMatch
        if confirm.waitForExistence(timeout: 5) {
            confirm.tap()
        }
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons[identifier])
        _ = XCTWaiter().wait(for: [gone], timeout: 5)
    }

    @MainActor
    private func openSettings() {
        let gear = app.navigationBars["Matches"].buttons["Settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
        gear.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func findSettingsElement(_ element: XCUIElement) -> XCUIElement {
        for _ in 0..<10 where !(element.exists && element.isHittable) { app.swipeUp() }
        return element
    }

    @MainActor
    private func ensureReminderToggleOn() {
        guard app.navigationBars["Matches"].buttons["Settings"].exists else { return }
        openSettings()
        let toggle = findSettingsElement(app.switches["archive-export-reminder-toggle"])
        if toggle.exists, toggle.value as? String == "0" {
            flipSwitch(toggle)
        }
        if app.navigationBars["Settings"].buttons["Done"].exists {
            app.navigationBars["Settings"].buttons["Done"].tap()
        }
    }

    @MainActor
    private func flipSwitch(_ toggle: XCUIElement) {
        let control = toggle.switches.firstMatch.exists ? toggle.switches.firstMatch : toggle
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }
}
