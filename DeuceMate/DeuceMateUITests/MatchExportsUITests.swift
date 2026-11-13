// MatchExportsUITests.swift — PR 4: match details in AI Coach, shared reports
// and the manual archive, driven the way a user would (MATCH_TAGS_PLAN.md
// 7.3, 8.1, 12.1 "Export privacy").
//
// Matches are created only through Manual Entry + End at Current Score (as in
// MatchDetailsUITests) and every test deletes what it created. Player names
// carry a per-run token so a leftover can never be mistaken for this run's.
//
// Screenshots are attached to the result bundle; set
// TEST_RUNNER_DEUCEMATE_UI_SHOTS_DIR to also write them as PNG files.
import XCTest

final class MatchExportsUITests: XCTestCase {
    private let app = XCUIApplication()
    private var createdRows: [String] = []
    private let token: String = {
        let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
        return String((0..<2).map { _ in letters[Int.random(in: 0..<letters.count)] })
    }()
    private let note = "knee sore; attack second serve"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        guard !createdRows.isEmpty else { return }
        MainActor.assumeIsolated {
            app.terminate()
            app.launch()
            _ = app.buttons["Manual match entry"].waitForExistence(timeout: 15)
            for identifier in createdRows.reversed() { deleteMatch(identifier) }
        }
        createdRows.removeAll()
    }

    // MARK: - AI Coach

    /// Names (default ON, like the share menu) and the private note (a
    /// default-OFF opt-in) are separate toggles on the AI Coach sheet; the
    /// visible prompt changes exactly with them.
    @MainActor
    func testAICoachNamesAndNoteAreOptIns() throws {
        launch()
        let alex = "Alex \(token)"
        _ = try seedTaggedPair(opponent: alex, note: note)

        let aiButton = app.buttons["AI Coach"]
        XCTAssertTrue(aiButton.waitForExistence(timeout: 10))
        aiButton.tap()
        XCTAssertTrue(app.navigationBars["AI Coach"].waitForExistence(timeout: 5))

        // Defaults: names on, note off.
        let names = app.switches["ai-include-names"]
        let notes = app.switches["ai-include-notes"]
        XCTAssertTrue(names.waitForExistence(timeout: 5))
        XCTAssertTrue(notes.exists)
        XCTAssertEqual(names.value as? String, "1", "Names default ON for the AI hand-off")
        XCTAssertEqual(notes.value as? String, "0", "The private note defaults OFF")
        capture("20-ai-coach-defaults")

        var prompt = openPromptPreview()
        XCTAssertTrue(prompt.contains("\"\(alex)\""), "Names appear (quoted) by default")
        XCTAssertFalse(prompt.contains("knee sore"), "No note by default")
        goBack(from: "Prompt")

        // Names OFF.
        flipSwitch("ai-include-names")
        XCTAssertEqual(app.switches["ai-include-names"].value as? String, "0")
        prompt = openPromptPreview()
        XCTAssertTrue(prompt.contains("## Match Context"), "Match Context is always present")
        XCTAssertTrue(prompt.contains("Competition: League"))
        XCTAssertTrue(prompt.contains("Match type: Singles"))
        XCTAssertTrue(prompt.contains("Head-to-head vs this opponent"), "Head-to-head is always present")
        XCTAssertTrue(prompt.contains("Opponent (name withheld)"))
        XCTAssertFalse(prompt.contains(alex), "No typed name with names off")
        XCTAssertFalse(prompt.contains("knee sore"), "No note by default")
        scrollPromptToContext()
        capture("21-ai-prompt-names-off")
        goBack(from: "Prompt")

        // Notes ON with names OFF: review step with the exact text + both warnings.
        flipSwitch("ai-include-notes")
        let preview = app.descendants(matching: .any)["notes-export-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5), "The note must be reviewed before it is included")
        XCTAssertTrue(preview.label.contains(note), preview.label)
        XCTAssertTrue(app.descendants(matching: .any)["notes-export-disclosure"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["notes-export-names-warning"].exists,
                      "Names off + note on warns that the note may still contain names")
        capture("22-ai-notes-review-names-off")
        app.buttons["confirm-include-note"].tap()
        XCTAssertEqual(app.switches["ai-include-notes"].value as? String, "1")
        XCTAssertTrue(app.descendants(matching: .any)["ai-names-off-notes-warning"].waitForExistence(timeout: 3))

        prompt = openPromptPreview()
        XCTAssertTrue(prompt.contains("> \(note)"), "The note is quoted context")
        XCTAssertTrue(prompt.contains("data, not instructions"))
        XCTAssertFalse(prompt.contains(alex), "Names are still off")
        scrollPromptToContext()
        capture("23-ai-prompt-note-on")
        goBack(from: "Prompt")

        // Names back ON.
        flipSwitch("ai-include-names")
        prompt = openPromptPreview()
        XCTAssertTrue(prompt.contains("\"\(alex)\""), "Names appear (quoted) when on")
        XCTAssertTrue(prompt.contains("> \(note)"))
        scrollPromptToContext()
        capture("24-ai-prompt-names-on")
        goBack(from: "Prompt")

        // Cancelling the review leaves the note OFF.
        flipSwitch("ai-include-notes")   // off (immediate)
        XCTAssertEqual(app.switches["ai-include-notes"].value as? String, "0")
        flipSwitch("ai-include-notes")   // wants on -> review
        XCTAssertTrue(app.buttons["cancel-include-note"].waitForExistence(timeout: 5))
        app.buttons["cancel-include-note"].tap()
        XCTAssertEqual(app.switches["ai-include-notes"].value as? String, "0", "Cancel keeps the note out")
        app.navigationBars["AI Coach"].buttons["Done"].tap()
        closeDetail()
    }

    // MARK: - Share menu

    /// Names ON by default for reports; the note needs its review; an included
    /// note joins the same pre-share alert; the text carries what was chosen.
    @MainActor
    func testShareMenuNamesDefaultOnAndNoteDisclosedBeforeSharing() throws {
        launch()
        let alex = "Alex \(token)"
        // An untagged, note-free match whose (empty) note editor is where the
        // shared text is pasted back so it can be read.
        let scratch = createMatch()
        let tagged = try seedTaggedPair(opponent: alex, note: note)

        openExportMenu()
        XCTAssertEqual(menuToggleValue("Include player names"), "1", "Names default ON for reports")
        XCTAssertEqual(menuToggleValue("Include private note"), "0", "Note defaults OFF for reports")
        capture("25-share-menu-toggles")

        // Without the note: no extra alert, share sheet opens straight away.
        app.buttons["Share Summary"].firstMatch.tap()
        XCTAssertTrue(waitForShareSheet(), "A health-free, note-free share opens directly")
        let copied = copyAndRead(tagged: tagged, scratch: scratch)
        XCTAssertTrue(copied.contains("Competition:"), copied)
        XCTAssertTrue(copied.contains(alex), "Text summary shows the name by default")
        XCTAssertFalse(copied.contains("knee sore"), "No note unless opted in")

        // Note ON via its review sheet, then share: one combined disclosure.
        openExportMenu()
        app.buttons["Include private note"].tap()
        XCTAssertTrue(app.buttons["confirm-include-note"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["notes-export-names-warning"].exists,
                       "Names are on, so no names-off warning")
        capture("26-share-notes-review")
        app.buttons["confirm-include-note"].tap()

        openExportMenu()
        XCTAssertEqual(menuToggleValue("Include private note"), "1")
        app.buttons["Share Summary"].firstMatch.tap()
        let alert = app.alerts["Share private note?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "An included note is disclosed before sharing")
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS 'personal or health information'")).count > 0)
        capture("27-share-note-disclosure")
        alert.buttons["Share"].tap()
        XCTAssertTrue(waitForShareSheet())
        let withNote = copyAndRead(tagged: tagged, scratch: scratch)
        XCTAssertTrue(withNote.contains("> \(note)"), withNote)
        XCTAssertTrue(withNote.contains(alex))

        // Reopening the detail resets both choices to their defaults (names ON,
        // note OFF): opt-ins are never remembered between visits.
        openExportMenu()
        XCTAssertEqual(menuToggleValue("Include private note"), "0", "The note opt-in does not persist")
        app.buttons["Include private note"].tap()
        XCTAssertTrue(app.buttons["confirm-include-note"].waitForExistence(timeout: 5))
        app.buttons["confirm-include-note"].tap()

        // Names OFF + note ON: the alert adds the "may still contain names" warning.
        openExportMenu()
        app.buttons["Include player names"].tap()
        openExportMenu()
        XCTAssertEqual(menuToggleValue("Include player names"), "0")
        app.buttons["Share Summary"].firstMatch.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS 'may still contain names'")).count > 0)
        capture("28-share-names-off-note-warning")
        alert.buttons["Share"].tap()
        XCTAssertTrue(waitForShareSheet())
        let namesOff = copyAndRead(tagged: tagged, scratch: scratch)
        XCTAssertFalse(namesOff.contains(alex), "Names OFF: the typed name is absent from the text")
        XCTAssertTrue(namesOff.contains("Competition:"))
        XCTAssertTrue(namesOff.contains("knee sore"), "The opted-in note is still there")
        closeDetail()
    }

    /// Leaves the staged interactive HTML files built with names OFF and the
    /// note OFF so the host can verify them on disk (see the PR evidence).
    @MainActor
    func testShareMenuNamesOffRebuildsStagedFiles() throws {
        launch()
        let alex = "Alex \(token)"
        _ = try seedTaggedPair(opponent: alex, note: note)
        openExportMenu()
        app.buttons["Include player names"].tap()
        openExportMenu()
        XCTAssertEqual(menuToggleValue("Include player names"), "0")
        // The interactive submenu is available again once the rebuild finishes.
        app.buttons["Interactive Web Page"].firstMatch.tap()
        XCTAssertTrue(app.buttons["My Perspective"].waitForExistence(timeout: 20), "Files rebuilt after the toggle")
        capture("29-share-interactive-names-off")
        app.buttons["My Perspective"].tap()
        XCTAssertTrue(waitForShareSheet())
        dismissShareSheet()
        closeDetail()
    }

    /// Names ON + note ON staged files (the host checks them on disk).
    @MainActor
    func testShareMenuNamesAndNoteOnRebuildsStagedFiles() throws {
        launch()
        let alex = "Alex \(token)"
        _ = try seedTaggedPair(opponent: alex, note: note)
        openExportMenu()
        app.buttons["Include private note"].tap()
        XCTAssertTrue(app.buttons["confirm-include-note"].waitForExistence(timeout: 5))
        app.buttons["confirm-include-note"].tap()
        openExportMenu()
        XCTAssertEqual(menuToggleValue("Include private note"), "1")
        app.buttons["Interactive Web Page"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Opponent's Perspective"].waitForExistence(timeout: 20))
        app.buttons["Opponent's Perspective"].tap()
        let alert = app.alerts["Share private note?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Cancel"].tap()
        closeDetail()
    }

    // MARK: - Manual archive

    @MainActor
    func testArchiveExportOffersNotesAsOptInWithPreview() throws {
        launch()
        _ = try seedTaggedPair(opponent: "Alex \(token)", note: note)
        closeDetail()
        let gear = app.navigationBars["Matches"].buttons["Settings"]
        gear.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let export = app.buttons["Export Match Archive"]
        for _ in 0..<8 where !(export.exists && export.isHittable) { app.swipeUp() }
        export.tap()
        XCTAssertTrue(app.navigationBars["Export Match Archive"].waitForExistence(timeout: 5))
        let toggle = app.switches["archive-include-notes"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0", "Archive notes default OFF")
        capture("30-archive-export-options")
        flipSwitch("archive-include-notes")
        XCTAssertTrue(app.descendants(matching: .any)["archive-notes-disclosure"].waitForExistence(timeout: 3))
        XCTAssertTrue(anyElement(containing: note).exists, "The exact note text is previewed")
        capture("31-archive-export-notes-preview")
        app.navigationBars["Export Match Archive"].buttons["Cancel"].tap()
        let done = app.navigationBars["Settings"].buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
    }

    @MainActor
    func testArchiveExportStillOffersNotesOptInWhenEveryNoteWasCleared() throws {
        launch()
        _ = try seedTaggedPair(opponent: "Alex \(token)", note: note)
        // Clear the note: the editor saves an explicit empty revision.
        let row = app.buttons["match-notes-row"]
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        row.tap()
        let editor = app.textViews["match-notes-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let delete = app.buttons["delete-match-note"]
        for _ in 0..<4 where !delete.isHittable { app.swipeUp() }
        delete.tap()
        let confirm = app.sheets.buttons["Delete Note"].firstMatch.exists
            ? app.sheets.buttons["Delete Note"].firstMatch
            : app.buttons.matching(identifier: "Delete Note").element(boundBy: 1)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5), "Editor closes after deleting the note")
        closeDetail()
        app.navigationBars["Matches"].buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let export = app.buttons["Export Match Archive"]
        for _ in 0..<8 where !(export.exists && export.isHittable) { app.swipeUp() }
        export.tap()
        XCTAssertTrue(app.navigationBars["Export Match Archive"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["archive-include-notes"].waitForExistence(timeout: 5),
                      "A cleared note still needs the opt-in so the clear can transfer")
        flipSwitch("archive-include-notes")
        XCTAssertTrue(app.descendants(matching: .any)["archive-notes-cleared"].waitForExistence(timeout: 3))
        XCTAssertFalse(anyElement(containing: note).exists, "Cleared text is never previewed")
        app.navigationBars["Export Match Archive"].buttons["Cancel"].tap()
        let done = app.navigationBars["Settings"].buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
    }

    // MARK: - Helpers: scenario

    /// Two completed singles matches against the same opponent (so a
    /// head-to-head exists), the second carrying a private note. Leaves the
    /// SECOND match's detail open.
    @MainActor
    private func seedTaggedPair(opponent: String, note: String) throws -> String {
        let first = createMatch(gamesMe: 3)
        openMatch(first)
        editMatchInfo(competition: "League", opponent: opponent)
        closeDetail()
        let second = createMatch(gamesMe: 2)
        openMatch(second)
        editMatchInfo(competition: "League", existingOpponent: opponent)
        let row = app.buttons["match-notes-row"]
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        row.tap()
        let editor = app.textViews["match-notes-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(note)
        app.buttons["save-match-note"].tap()
        XCTAssertTrue(waitForLabel(row, contains: "Private note saved"))
        return second
    }

    /// Brings the Match Context section into view for the screenshots.
    @MainActor
    private func scrollPromptToContext() {
        for _ in 0..<2 { app.swipeUp() }
    }

    @MainActor
    private func openPromptPreview() -> String {
        app.buttons["ai-preview-prompt"].tap()
        let text = app.staticTexts["ai-prompt-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        return text.label
    }

    // MARK: - Helpers: share

    @MainActor
    private func openExportMenu() {
        let menu = app.buttons["Export match"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15))
        menu.tap()
        XCTAssertTrue(app.buttons["Share Summary"].firstMatch.waitForExistence(timeout: 5))
    }

    /// The checkmark state of a toggle inside a menu ("1"/"0").
    @MainActor
    private func menuToggleValue(_ title: String) -> String? {
        let item = app.buttons[title]
        XCTAssertTrue(item.waitForExistence(timeout: 5), title)
        return item.isSelected ? "1" : "0"
    }

    @MainActor
    private func waitForShareSheet() -> Bool {
        app.otherElements["ActivityListView"].waitForExistence(timeout: 10)
            || app.buttons["Copy"].waitForExistence(timeout: 10)
    }

    @MainActor
    private func dismissShareSheet() {
        let close = app.buttons["Close"]
        if close.exists { close.tap() } else { app.swipeDown() }
    }

    /// Taps Copy in the share sheet, then pastes into the SCRATCH match's empty
    /// note editor to read exactly what was shared (never saved), and returns
    /// to the tagged match.
    @MainActor
    private func copyAndRead(tagged: String, scratch: String) -> String {
        capture("share-sheet-\(Int(Date().timeIntervalSince1970) % 100000)")
        let copy = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Copy'")).firstMatch
        for _ in 0..<3 where !copy.exists { app.swipeUp() }
        XCTAssertTrue(copy.waitForExistence(timeout: 5), "Copy action in the share sheet")
        copy.tap()
        closeDetail()
        openMatch(scratch)
        let row = app.buttons["match-notes-row"]
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        row.tap()
        let editor = app.textViews["match-notes-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.press(forDuration: 1.2)
        let paste = app.menuItems["Paste"]
        if paste.waitForExistence(timeout: 3) { paste.tap() }
        let allow = app.buttons["Allow Paste"]
        if allow.waitForExistence(timeout: 2) { allow.tap() }
        let value = (editor.value as? String) ?? ""
        // Only Save writes the note, so discard what was pasted to read it.
        app.buttons["cancel-match-note"].tap()
        let discard = app.buttons["Discard Changes"]
        if discard.waitForExistence(timeout: 3) { discard.tap() }
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        closeDetail()
        openMatch(tagged)
        return value
    }

    // MARK: - Helpers: archive

    @MainActor
    private func launch() {
        app.launch()
        XCTAssertTrue(app.buttons["Manual match entry"].waitForExistence(timeout: 15))
    }

    @MainActor
    @discardableResult
    private func createMatch(gamesMe: Int = 0, gamesOpp: Int = 0) -> String {
        app.buttons["Manual match entry"].tap()
        XCTAssertTrue(app.navigationBars["Manual Entry"].waitForExistence(timeout: 5))
        increment("Games — Me", times: gamesMe)
        increment("Games — Opp", times: gamesOpp)
        let save = app.buttons["Save Match"]
        for _ in 0..<6 where !save.isHittable { app.swipeUp() }
        save.tap()
        let newest = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'match-row-'")).firstMatch
        XCTAssertTrue(newest.waitForExistence(timeout: 5))
        let identifier = newest.identifier
        createdRows.append(identifier)
        openMatch(identifier)
        let end = app.buttons["End at Current Score"]
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        end.tap()
        let dialog = app.sheets.buttons["End at Current Score"].exists
            ? app.sheets.buttons["End at Current Score"]
            : app.buttons.matching(identifier: "End at Current Score").element(boundBy: 1)
        (dialog.exists ? dialog : app.buttons["End at Current Score"].firstMatch).tap()
        XCTAssertTrue(app.buttons["Manual match entry"].waitForExistence(timeout: 5))
        return identifier
    }

    @MainActor
    private func increment(_ label: String, times: Int) {
        guard times > 0 else { return }
        let stepper = app.steppers.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
        for _ in 0..<6 where !stepper.isHittable { app.swipeUp() }
        XCTAssertTrue(stepper.exists, "Stepper \(label)")
        for _ in 0..<times { stepper.buttons["Increment"].tap() }
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
    private func closeDetail() {
        let done = app.navigationBars.buttons["Done"].firstMatch
        if done.waitForExistence(timeout: 3) { done.tap() }
        XCTAssertTrue(app.buttons["Manual match entry"].waitForExistence(timeout: 5))
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
        if confirm.waitForExistence(timeout: 5) { confirm.tap() }
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons[identifier])
        _ = XCTWaiter().wait(for: [gone], timeout: 5)
    }

    @MainActor
    private func goBack(from title: String) {
        let back = app.navigationBars[title].buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "Back button on \(title)")
        back.tap()
    }

    // MARK: - Helpers: match info

    @MainActor
    private func editMatchInfo(competition: String, opponent: String) {
        openEditor(competition: competition)
        pickNew(opponent)
        app.buttons["save-match-info"].tap()
        XCTAssertTrue(app.buttons["match-info-row"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func editMatchInfo(competition: String, existingOpponent: String) {
        openEditor(competition: competition)
        let slot = app.buttons["Add opponent"]
        for _ in 0..<4 where !slot.isHittable { app.swipeUp() }
        slot.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText(existingOpponent)
        let existing = app.buttons["roster-player-\(existingOpponent)"]
        XCTAssertTrue(existing.waitForExistence(timeout: 5))
        existing.tap()
        XCTAssertTrue(app.navigationBars["Match Info"].waitForExistence(timeout: 5))
        app.buttons["save-match-info"].tap()
        XCTAssertTrue(app.buttons["match-info-row"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func openEditor(competition: String) {
        let row = app.buttons["match-info-row"]
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        row.tap()
        XCTAssertTrue(app.navigationBars["Match Info"].waitForExistence(timeout: 5))
        app.buttons["competition-\(competition.lowercased())"].tap()
    }

    @MainActor
    private func pickNew(_ name: String) {
        let slot = app.buttons["Add opponent"]
        for _ in 0..<4 where !slot.isHittable { app.swipeUp() }
        slot.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText(name)
        let add = app.buttons["add-new-player"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(app.navigationBars["Match Info"].waitForExistence(timeout: 5))
    }

    // MARK: - Helpers: misc

    @MainActor
    private func anyElement(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor
    private func flipSwitch(_ identifier: String) {
        let toggle = app.switches[identifier]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let before = toggle.value as? String
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        // The notes toggles present a review sheet instead of flipping at once.
        if app.buttons["confirm-include-note"].waitForExistence(timeout: 1.5) { return }
        let flipped = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", before ?? ""), object: toggle)
        XCTAssertEqual(XCTWaiter().wait(for: [flipped], timeout: 3), .completed, "\(identifier) flipped")
    }

    @MainActor
    private func waitForLabel(_ element: XCUIElement, contains text: String, timeout: TimeInterval = 5) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func capture(_ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let directory = ProcessInfo.processInfo.environment["DEUCEMATE_UI_SHOTS_DIR"], !directory.isEmpty {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: url.appendingPathComponent(name + ".png"))
        }
    }
}
