// MatchDetailsUITests.swift — Match Info (opponent / partner / competition),
// private notes, Settings → Players and "Compare with previous match", driven
// the way a user would (MATCH_TAGS_PLAN.md §5, §7.1, §12.1).
//
// Matches are created only through the app's normal Manual Entry flow (and
// finished with End at Current Score), so no production launch hook or
// container seeding is needed. Every test deletes the matches it created.
// Player names carry a per-run token so a leftover from an interrupted run can
// never be mistaken for this run's player.
//
// Screenshots are attached to the result bundle; set
// TEST_RUNNER_DEUCEMATE_UI_SHOTS_DIR to also write them as PNG files.
import XCTest

final class MatchDetailsUITests: XCTestCase {
    private let app = XCUIApplication()
    private var createdRows: [String] = []
    /// Two letters, e.g. "QK" — keeps names readable ("Alex QK").
    private let token: String = {
        let letters = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
        return String((0..<2).map { _ in letters[Int.random(in: 0..<letters.count)] })
    }()

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        // Leave no test match behind, even after a failure.
        guard !createdRows.isEmpty else { return }
        // XCTest runs tearDown on the main thread.
        MainActor.assumeIsolated {
            // A relaunch lands on the archive root whatever the test left open.
            app.terminate()
            app.launch()
            _ = app.buttons["Manual match entry"].waitForExistence(timeout: 15)
            for identifier in createdRows.reversed() {
                deleteMatch(identifier)
            }
        }
        createdRows.removeAll()
    }

    // MARK: - Flows

    /// Tag a completed singles match with a new opponent + League; tag a second
    /// match by picking the same player from the roster (no duplicate is made);
    /// the rematch comparison and head-to-head then use that identity.
    @MainActor
    func testTagCompletedMatchesAndReuseRosterPlayer() throws {
        launch()
        let alex = "Alex \(token)"

        let first = createMatch(gamesMe: 3, complete: true)
        openMatch(first)
        editMatchInfo(competition: "League", opponents: [.new(alex)])
        XCTAssertTrue(matchInfoRow(contains: "vs \(alex) · League"))
        capture("01-detail-match-info")
        closeDetail()
        XCTAssertTrue(archiveRow(first, contains: "vs \(alex) · League"), "The archive row shows the subtitle")
        capture("02-archive-row-subtitle")

        let second = createMatch(gamesMe: 1, complete: true)
        openMatch(second)
        app.buttons["match-info-row"].tap()
        XCTAssertTrue(app.navigationBars["Match Info"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["Friendly"].tap()
        app.buttons["Add opponent"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText(alex.lowercased())
        let existing = app.buttons["roster-player-\(alex)"]
        XCTAssertTrue(existing.waitForExistence(timeout: 5), "Typing an existing name offers that player first")
        XCTAssertTrue(app.buttons["add-new-player"].label.contains("Add another"))
        capture("03-picker-existing-first")
        existing.tap()
        app.buttons["save-match-info"].tap()
        XCTAssertTrue(matchInfoRow(contains: "vs \(alex) · Friendly"))
        XCTAssertTrue(matchInfoRow(contains: "Head-to-head"), "A known opponent shows the head-to-head line")

        // Rematch comparison against the first match.
        tapCompare()
        XCTAssertTrue(app.staticTexts["Previous match against \(alex)"].waitForExistence(timeout: 5))
        capture("04-compare-rematch")
        // Head-to-head sits at the bottom of a lazily loaded List.
        let headToHead = app.staticTexts["head-to-head-summary"]
        for _ in 0..<8 where !headToHead.exists { app.swipeUp() }
        XCTAssertTrue(headToHead.exists)
        XCTAssertTrue(headToHead.label.contains("1 match"), headToHead.label)
        capture("05-compare-head-to-head")
        goBack(from: "Compare")
        closeDetail()

        // One roster entry, two matches — no duplicate Alex.
        openPlayers()
        let rows = app.buttons.matching(NSPredicate(format: "identifier == %@", "player-row-\(alex)"))
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows.firstMatch.label.contains("2 matches"))
        capture("06-settings-players")
        closeSettings()
    }

    /// Naming an in-progress match never completes it or changes its score.
    @MainActor
    func testTaggingAnInProgressMatchKeepsItInProgress() throws {
        launch()
        let jo = "Jo \(token)"
        let live = createMatch(gamesMe: 3, gamesOpp: 1, complete: false)
        openMatch(live)
        let scoreBefore = headerScoreLabel()
        XCTAssertTrue(app.staticTexts["In Progress"].exists)

        editMatchInfo(competition: "Tournament", opponents: [.new(jo)])

        XCTAssertTrue(matchInfoRow(contains: "vs \(jo) · Tournament"))
        XCTAssertTrue(app.staticTexts["In Progress"].exists, "Still in progress after editing details")
        XCTAssertTrue(app.buttons["End at Current Score"].exists)
        XCTAssertEqual(headerScoreLabel(), scoreBefore, "The score is unchanged")

        tapCompare()
        let noRematch = app.staticTexts["No previous match against this opponent"]
        XCTAssertTrue(noRematch.waitForExistence(timeout: 5))
        capture("07-compare-in-progress-no-rematch")
        goBack(from: "Compare")
        closeDetail()
        XCTAssertTrue(archiveRow(live, contains: "vs \(jo) · Tournament"))
    }

    /// Doubles: partner plus two opponents; then clearing the details.
    @MainActor
    func testDoublesPartnerAndTwoOpponentsThenClear() throws {
        launch()
        let sam = "Sam \(token)", alex = "Alex \(token)", jo = "Jo \(token)"
        let match = createMatch(gamesMe: 2, complete: true, doubles: true)
        openMatch(match)
        XCTAssertTrue(matchInfoRow(contains: "Add players & type"))

        app.buttons["match-info-row"].tap()
        XCTAssertTrue(app.navigationBars["Match Info"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["Practice"].tap()
        pick(.new(sam), slotButton: "Add partner")
        pick(.new(alex), slotButton: "Add opponent 1")
        pick(.new(jo), slotButton: "Add opponent 2")
        capture("08-editor-doubles")
        app.buttons["save-match-info"].tap()
        XCTAssertTrue(matchInfoRow(contains: "With \(sam) vs \(alex) & \(jo) · Practice"))
        capture("09-detail-doubles")

        // Clear: an explicit, confirmed, empty revision.
        app.buttons["match-info-row"].tap()
        let clear = app.buttons["clear-match-details"]
        for _ in 0..<4 where !clear.isHittable { app.swipeUp() }
        clear.tap()
        app.buttons["Clear Details"].firstMatch.tap()
        XCTAssertTrue(matchInfoRow(contains: "Add players & type"))
        closeDetail()
        XCTAssertFalse(archiveRow(match, contains: sam))
    }

    /// Settings → Players: merge a duplicate, rename everywhere, forget everywhere.
    @MainActor
    func testRenameMergeAndForgetPlayer() throws {
        launch()
        let alex = "Alex \(token)", duplicate = "Alexx \(token)", renamed = "Alexander \(token)"
        let a = createMatch(gamesMe: 1, complete: true)
        openMatch(a)
        editMatchInfo(competition: nil, opponents: [.new(alex)])
        closeDetail()
        let b = createMatch(gamesMe: 2, complete: true)
        openMatch(b)
        editMatchInfo(competition: nil, opponents: [.new(duplicate)])
        closeDetail()

        // Merge the duplicate into Alex.
        openPlayers()
        app.buttons["player-row-\(duplicate)"].tap()
        app.buttons["merge-player"].tap()
        app.buttons["merge-target-\(alex)"].tap()
        let mergeConfirm = app.buttons["Merge"]
        XCTAssertTrue(mergeConfirm.waitForExistence(timeout: 5))
        capture("10-merge-confirmation")
        mergeConfirm.tap()
        XCTAssertTrue(app.buttons["player-row-\(alex)"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["player-row-\(duplicate)"].exists)
        XCTAssertTrue(app.buttons["player-row-\(alex)"].label.contains("2 matches"))

        // Rename: every match updates.
        app.buttons["player-row-\(alex)"].tap()
        let field = app.textFields["rename-player-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.clearAndType(renamed)
        app.buttons["rename-player"].tap()
        XCTAssertTrue(app.navigationBars[renamed].waitForExistence(timeout: 5))
        capture("11-player-manage")
        goBack(from: renamed)
        closeSettings()
        XCTAssertTrue(archiveRow(a, contains: "vs \(renamed)"))
        XCTAssertTrue(archiveRow(b, contains: "vs \(renamed)"))

        // Forget: gone from every match and from the roster.
        openPlayers()
        app.buttons["player-row-\(renamed)"].tap()
        app.buttons["forget-player"].tap()
        let forget = dialogButton("Forget Player", notIdentifier: "forget-player")
        XCTAssertTrue(forget.waitForExistence(timeout: 5))
        capture("12-forget-confirmation")
        forget.tap()
        XCTAssertTrue(app.navigationBars["Players"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["player-row-\(renamed)"].exists)
        closeSettings()
        XCTAssertFalse(archiveRow(a, contains: renamed))
        XCTAssertFalse(archiveRow(b, contains: renamed))
        openMatch(a)
        XCTAssertTrue(matchInfoRow(contains: "Add opponent & type"))
        closeDetail()
    }

    /// Private notes: add, relaunch, edit, delete.
    @MainActor
    func testPrivateNotesPersistAcrossRelaunch() throws {
        launch()
        let match = createMatch(gamesMe: 2, complete: true)
        openMatch(match)
        let notesRow = app.buttons["match-notes-row"]
        XCTAssertTrue(notesRow.label.contains("Add private note"))
        notesRow.tap()
        let editor = app.textViews["match-notes-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText("Attack the backhand \(token).\nServe wide on deuce.")
        XCTAssertTrue(app.staticTexts["Stored on this iPhone. Not backed up automatically."].exists)
        capture("13-notes-editor")
        app.buttons["save-match-note"].tap()
        XCTAssertTrue(notesRow.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForLabel(notesRow, contains: "Attack the backhand \(token)"))
        capture("14-detail-with-note")
        closeDetail()

        app.terminate()
        launch()
        openMatch(match)
        XCTAssertTrue(waitForLabel(app.buttons["match-notes-row"], contains: "Attack the backhand \(token)"),
                      "The note survives a relaunch")

        // Edit, then delete.
        app.buttons["match-notes-row"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(" Edited.")
        app.buttons["save-match-note"].tap()
        XCTAssertTrue(waitForLabel(app.buttons["match-notes-row"], contains: "Edited."))
        app.buttons["match-notes-row"].tap()
        app.buttons["delete-match-note"].tap()
        dialogButton("Delete Note", notIdentifier: "delete-match-note").tap()
        XCTAssertTrue(waitForLabel(app.buttons["match-notes-row"], contains: "Add private note"))
        closeDetail()
    }

    /// No rematch → Choose another match (completed, then including in-progress,
    /// labelled partial); an untagged match falls back to the same type.
    @MainActor
    func testCompareFallbacksAndChooseAnotherMatch() throws {
        launch()
        let pat = "Pat \(token)"
        let older = createMatch(gamesMe: 4, complete: true)
        let partial = createMatch(gamesMe: 1, complete: false)
        let current = createMatch(gamesMe: 2, complete: true)

        openMatch(current)
        tapCompare()
        let sameType = app.staticTexts["Most recent earlier singles match"]
        XCTAssertTrue(sameType.waitForExistence(timeout: 5), "Untagged ⇒ most recent earlier same-type match")
        XCTAssertTrue(anyElement(containing: "Compared with").exists)
        goBack(from: "Compare")

        editMatchInfo(competition: "League", opponents: [.new(pat)])
        tapCompare()
        XCTAssertTrue(app.staticTexts["No previous match against this opponent"].waitForExistence(timeout: 5))

        app.buttons["choose-another-match"].tap()
        XCTAssertTrue(app.navigationBars["Choose a Match"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["baseline-candidate-\(uuid(partial))"].exists, "In-progress hidden by default")
        flipSwitch("include-in-progress-toggle")
        let partialRow = app.buttons["baseline-candidate-\(uuid(partial))"]
        XCTAssertTrue(partialRow.waitForExistence(timeout: 5))
        XCTAssertTrue(partialRow.label.contains("In Progress — partial stats"))
        capture("15-choose-another-match")
        app.buttons["baseline-candidate-\(uuid(older))"].tap()
        XCTAssertTrue(app.staticTexts["Comparing with a match you chose"].waitForExistence(timeout: 5))
        capture("16-compare-chosen")

        app.buttons["choose-another-match"].tap()
        flipSwitch("include-in-progress-toggle")
        app.buttons["baseline-candidate-\(uuid(partial))"].tap()
        let partialLabel = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'In Progress — partial stats'")).firstMatch
        XCTAssertTrue(partialLabel.waitForExistence(timeout: 5), "A partial baseline is labelled")
        XCTAssertTrue(anyElement(containing: "In progress").exists, "No result is inferred for a partial match")
        capture("17-compare-partial-baseline")
        goBack(from: "Compare")
        closeDetail()
    }

    /// At an accessibility text size the editor still works: the competition
    /// type becomes a menu instead of five cramped segments.
    @MainActor
    func testLargeDynamicTypeEditorIsUsable() throws {
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        launch()
        let rio = "Rio \(token)"
        let match = createMatch(complete: true)
        openMatch(match)
        let row = app.buttons["match-info-row"]
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        row.tap()
        XCTAssertTrue(app.navigationBars["Match Info"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.segmentedControls.firstMatch.exists, "Segments give way to a menu at large sizes")
        let menu = app.buttons["competition-type-picker"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.tap()
        app.buttons["League"].firstMatch.tap()
        pick(.new(rio), slotButton: "Add opponent")
        capture("18-editor-large-type")
        app.buttons["save-match-info"].tap()
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(waitForLabel(row, contains: "vs \(rio) · League"))
        capture("19-detail-large-type")
        closeDetail()
    }

    // MARK: - Helpers: archive

    private enum PlayerChoice { case new(String), existing(String) }

    @MainActor
    private func launch() {
        app.launch()
        XCTAssertTrue(app.buttons["Manual match entry"].waitForExistence(timeout: 15))
    }

    /// Creates a match through Manual Entry, optionally finishing it with End at
    /// Current Score, and returns its row identifier.
    @MainActor
    @discardableResult
    private func createMatch(gamesMe: Int = 0, gamesOpp: Int = 0, complete: Bool, doubles: Bool = false) -> String {
        app.buttons["Manual match entry"].tap()
        XCTAssertTrue(app.navigationBars["Manual Entry"].waitForExistence(timeout: 5))
        if doubles {
            app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Type")).firstMatch.tap()
            app.buttons["Doubles"].firstMatch.tap()
        }
        increment("Games — Me", times: gamesMe)
        increment("Games — Opp", times: gamesOpp)
        let save = app.buttons["Save Match"]
        for _ in 0..<6 where !save.isHittable { app.swipeUp() }
        save.tap()
        let newest = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'match-row-'")).firstMatch
        XCTAssertTrue(newest.waitForExistence(timeout: 5))
        let identifier = newest.identifier
        createdRows.append(identifier)
        if complete {
            openMatch(identifier)
            let end = app.buttons["End at Current Score"]
            XCTAssertTrue(end.waitForExistence(timeout: 5))
            end.tap()
            let confirm = app.buttons["End at Current Score"].firstMatch
            // The dialog's own button (the header button is behind the dialog).
            let dialogButton = app.sheets.buttons["End at Current Score"].exists
                ? app.sheets.buttons["End at Current Score"]
                : app.buttons.matching(identifier: "End at Current Score").element(boundBy: 1)
            (dialogButton.exists ? dialogButton : confirm).tap()
            XCTAssertTrue(app.buttons["Manual match entry"].waitForExistence(timeout: 5))
        }
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
        XCTAssertTrue(app.buttons["match-info-row"].waitForExistence(timeout: 8))
    }

    @MainActor
    private func closeDetail() {
        let done = app.navigationBars.buttons["Done"].firstMatch
        if done.waitForExistence(timeout: 3) { done.tap() }
        XCTAssertTrue(app.buttons["Manual match entry"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func archiveRow(_ identifier: String, contains text: String) -> Bool {
        let row = revealRow(identifier)
        return waitForLabel(row, contains: text, timeout: 3)
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
        _ = waitForNonExistence(app.buttons[identifier], timeout: 5)
    }

    /// Taps the back button of the navigation bar titled `title`.
    @MainActor
    private func goBack(from title: String) {
        let back = app.navigationBars[title].buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "Back button on \(title)")
        back.tap()
    }

    // MARK: - Helpers: detail

    @MainActor
    private func matchInfoRow(contains text: String) -> Bool {
        let row = app.buttons["match-info-row"]
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        return waitForLabel(row, contains: text)
    }

    @MainActor
    private func headerScoreLabel() -> String {
        let texts = app.staticTexts.allElementsBoundByIndex.map(\.label)
        return texts.first { $0.contains("–") || $0.contains("-") } ?? ""
    }

    @MainActor
    private func tapCompare() {
        let compare = app.buttons["compare-previous-match"]
        for _ in 0..<6 where !compare.isHittable { app.swipeUp() }
        compare.tap()
        XCTAssertTrue(app.navigationBars["Compare"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func editMatchInfo(competition: String?, opponents: [PlayerChoice]) {
        let row = app.buttons["match-info-row"]
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        row.tap()
        XCTAssertTrue(app.navigationBars["Match Info"].waitForExistence(timeout: 5))
        if let competition { app.segmentedControls.buttons[competition].tap() }
        for (index, choice) in opponents.enumerated() {
            pick(choice, slotButton: opponents.count > 1 ? "Add opponent \(index + 1)" : "Add opponent")
        }
        app.buttons["save-match-info"].tap()
        XCTAssertTrue(app.buttons["match-info-row"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func pick(_ choice: PlayerChoice, slotButton: String) {
        let slot = app.buttons[slotButton]
        for _ in 0..<4 where !slot.isHittable { app.swipeUp() }
        slot.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        switch choice {
        case .new(let name):
            search.tap()
            search.typeText(name)
            let add = app.buttons["add-new-player"]
            XCTAssertTrue(add.waitForExistence(timeout: 5))
            add.tap()
        case .existing(let name):
            search.tap()
            search.typeText(name)
            app.buttons["roster-player-\(name)"].tap()
        }
        XCTAssertTrue(app.navigationBars["Match Info"].waitForExistence(timeout: 5))
    }

    // MARK: - Helpers: settings

    @MainActor
    private func openPlayers() {
        let gear = app.navigationBars["Matches"].buttons["Settings"]
        gear.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        // The row sits below the fold and List cells load lazily.
        let players = app.descendants(matching: .any)["players-settings"]
        for _ in 0..<8 where !(players.exists && players.isHittable) { app.swipeUp() }
        XCTAssertTrue(players.isHittable)
        players.tap()
        XCTAssertTrue(app.navigationBars["Players"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func closeSettings() {
        if app.navigationBars["Players"].exists { goBack(from: "Players") }
        let done = app.navigationBars["Settings"].buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(app.buttons["Manual match entry"].waitForExistence(timeout: 5))
    }

    // MARK: - Helpers: misc

    private func uuid(_ rowIdentifier: String) -> String {
        String(rowIdentifier.dropFirst("match-row-".count))
    }

    /// Any element whose (possibly combined) accessibility label contains `text`.
    @MainActor
    private func anyElement(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// A confirmation dialog's button, not the same-titled button that opened it.
    @MainActor
    private func dialogButton(_ label: String, notIdentifier: String) -> XCUIElement {
        let button = app.buttons.matching(
            NSPredicate(format: "label == %@ AND identifier != %@", label, notIdentifier)
        ).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Dialog button \(label)")
        return button
    }

    /// Taps the switch knob itself: a tap on a List toggle row's centre lands
    /// on its label and does not flip it.
    @MainActor
    private func flipSwitch(_ identifier: String) {
        let toggle = app.switches[identifier]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let before = toggle.value as? String
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let flipped = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", before ?? ""), object: toggle)
        XCTAssertEqual(XCTWaiter().wait(for: [flipped], timeout: 3), .completed, "\(identifier) flipped")
    }

    @MainActor
    private func waitForLabel(_ element: XCUIElement, contains text: String, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitForNonExistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
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

private extension XCUIElement {
    func clearAndType(_ text: String) {
        if let current = value as? String, !current.isEmpty {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        typeText(text)
    }
}
