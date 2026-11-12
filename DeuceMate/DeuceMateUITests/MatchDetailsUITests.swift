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
        app.buttons["competition-friendly"].tap()
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

    /// The archive's Opponents section is backed by tagged player identity:
    /// two completed singles rematches appear under one opponent, and a rename
    /// updates both the opponent browser and the match subtitles.
    @MainActor
    func testOpponentsBrowserAndRenamePlayer() throws {
        launch()
        let opponent = "Opponent \(token)"
        let renamed = "Rival \(token)"

        let win = createMatch(gamesMe: 3, gamesOpp: 0, complete: true)
        openMatch(win)
        editMatchInfo(competition: nil, opponents: [.new(opponent)])
        closeDetail()
        XCTAssertTrue(archiveRow(win, contains: opponent))

        let loss = createMatch(gamesMe: 0, gamesOpp: 3, complete: true)
        openMatch(loss)
        editMatchInfo(competition: nil, opponents: [.existing(opponent)])
        closeDetail()
        XCTAssertTrue(archiveRow(loss, contains: opponent))

        let sectionLink = app.buttons["opponents-section-link"]
        for _ in 0..<10 where !(sectionLink.exists && sectionLink.isHittable) { app.swipeDown() }
        XCTAssertTrue(sectionLink.waitForExistence(timeout: 5))
        sectionLink.tap()
        XCTAssertTrue(app.navigationBars["Opponents"].waitForExistence(timeout: 5))

        let row = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "opponent-row-", opponent
        )).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The same player identity groups both matches")
        row.tap()
        let detail = app.descendants(matching: .any)["opponent-detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars.buttons["opponent-manage-player"].isHittable,
                      "Player management stays in the navigation bar above the match history")
        XCTAssertTrue(app.staticTexts["Past Matches"].exists)
        XCTAssertFalse(app.staticTexts["Pending Matches"].exists, "Pending Matches hides when none are in progress")
        XCTAssertFalse(app.staticTexts["No pending matches"].exists)
        let record = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "1 win", "1 loss")
        ).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 5), "Singles record shows one win and one loss")
        XCTAssertTrue(record.isHittable, "Head to head is visible above the match history")
        XCTAssertLessThan(record.frame.minY, app.staticTexts["Past Matches"].frame.minY)
        XCTAssertFalse(app.staticTexts["Head to Head · Doubles"].exists, "Doubles H2H hides when no doubles matchups exist")
        XCTAssertFalse(app.staticTexts["No complete doubles team matchups recorded for this opponent."].exists)

        let manage = app.buttons["opponent-manage-player"]
        for _ in 0..<8 where !manage.isHittable { app.swipeUp() }
        XCTAssertTrue(manage.waitForExistence(timeout: 5))
        manage.tap()
        XCTAssertTrue(app.textFields["rename-player-field"].waitForExistence(timeout: 5))

        let handednessPicker = app.buttons["player-handedness-picker"]
        for _ in 0..<5 where !handednessPicker.isHittable { app.swipeUp() }
        handednessPicker.tap()
        app.buttons["Left-handed"].tap()

        let backhandPicker = app.buttons["player-backhand-picker"]
        for _ in 0..<5 where !backhandPicker.isHittable { app.swipeUp() }
        backhandPicker.tap()
        app.buttons["One-handed"].tap()

        let playStylePicker = app.buttons["player-play-style-picker"]
        for _ in 0..<5 where !playStylePicker.isHittable { app.swipeUp() }
        playStylePicker.tap()
        app.buttons["Serve & Volley"].tap()

        let playerBack = app.navigationBars.buttons.firstMatch
        playerBack.tap()
        let handednessRow = app.staticTexts["Handedness, Left-handed"]
        for _ in 0..<8 where !handednessRow.isHittable { app.swipeDown() }
        XCTAssertTrue(handednessRow.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Backhand, One-handed"].exists)
        XCTAssertTrue(app.staticTexts["Play Style, Serve & Volley"].exists)
        for _ in 0..<8 where !manage.isHittable { app.swipeUp() }
        manage.tap()
        XCTAssertTrue(app.buttons["player-handedness-picker"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["player-handedness-picker"].label.contains("Left-handed"))
        XCTAssertTrue(app.buttons["player-backhand-picker"].label.contains("One-handed"))
        XCTAssertTrue(app.buttons["player-play-style-picker"].label.contains("Serve & Volley"))
        app.navigationBars.buttons.firstMatch.tap()

        manage.tap()
        let nameField = app.textFields["rename-player-field"]
        nameField.tap()
        nameField.clearAndType(renamed)
        nameField.typeText("\n")
        XCTAssertTrue(app.navigationBars[renamed].waitForExistence(timeout: 5))

        // Return through the navigation stack and confirm the list and archive
        // subtitles resolve the renamed name from the same player identity.
        let manageBack = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(manageBack.waitForExistence(timeout: 5))
        manageBack.tap()
        let detailBack = app.navigationBars[renamed].buttons.firstMatch
        XCTAssertTrue(detailBack.waitForExistence(timeout: 5))
        detailBack.tap()
        let renamedRow = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "opponent-row-", renamed
        )).firstMatch
        XCTAssertTrue(renamedRow.waitForExistence(timeout: 5))
        XCTAssertTrue(renamedRow.label.contains("2 matches"), renamedRow.label)
        XCTAssertEqual(app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "opponent-row-", renamed
        )).count, 1, "Rename preserves one opponent entry")
        let opponentsBack = app.navigationBars["Opponents"].buttons.firstMatch
        opponentsBack.tap()
        XCTAssertTrue(archiveRow(win, contains: renamed))
        XCTAssertTrue(archiveRow(loss, contains: renamed))
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

    /// Opponent history separates pending and completed records and opens each
    /// in the same editable match detail used by the archive.
    @MainActor
    func testOpponentHistoryOpensPendingAndCompletedMatchDetails() throws {
        launch()
        let opponent = "History Opponent \(token)"

        let pending = createMatch(gamesMe: 2, gamesOpp: 1, complete: false)
        openMatch(pending)
        editMatchInfo(competition: nil, opponents: [.new(opponent)])
        closeDetail()

        let completed = createMatch(gamesMe: 3, gamesOpp: 0, complete: true)
        openMatch(completed)
        editMatchInfo(competition: nil, opponents: [.existing(opponent)])
        closeDetail()

        let sectionLink = app.buttons["opponents-section-link"]
        for _ in 0..<10 where !(sectionLink.exists && sectionLink.isHittable) { app.swipeDown() }
        XCTAssertTrue(sectionLink.waitForExistence(timeout: 5))
        sectionLink.tap()
        let opponentRow = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "opponent-row-", opponent
        )).firstMatch
        XCTAssertTrue(opponentRow.waitForExistence(timeout: 5))
        opponentRow.tap()

        let pendingRow = app.buttons["opponent-match-\(uuid(pending))"]
        XCTAssertTrue(pendingRow.waitForExistence(timeout: 5))
        pendingRow.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["End at Current Score"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["In Progress"].exists)
        app.navigationBars.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Pending Matches"].waitForExistence(timeout: 5))

        let completedRow = app.buttons["opponent-match-\(uuid(completed))"]
        XCTAssertTrue(completedRow.waitForExistence(timeout: 5))
        completedRow.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["match-info-row"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["End at Current Score"].exists)
        app.navigationBars.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Past Matches"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Head to Head · Doubles"].exists)
    }

    /// Selecting an opponent in Match Info allows managing players directly
    /// (merging duplicates, renaming, setting playing style) without leaving the flow.
    @MainActor
    func testManagePlayerWhileSelectingOpponentInMatchInfo() throws {
        launch()
        let alex = "Alex \(token)", duplicate = "Alexx \(token)", renamed = "Alexander \(token)"

        let first = createMatch(gamesMe: 2, complete: true)
        openMatch(first)
        editMatchInfo(competition: nil, opponents: [.new(alex)])
        closeDetail()

        let second = createMatch(gamesMe: 1, complete: true)
        openMatch(second)
        editMatchInfo(competition: nil, opponents: [.new(duplicate)])
        closeDetail()

        let third = createMatch(gamesMe: 3, complete: true)
        openMatch(third)
        app.buttons["match-info-row"].tap()
        XCTAssertTrue(app.navigationBars["Match Info"].waitForExistence(timeout: 5))
        let addOpponent = app.buttons["Add opponent"]
        for _ in 0..<4 where !addOpponent.isHittable { app.swipeUp() }
        addOpponent.tap()
        XCTAssertTrue(app.navigationBars["Opponent"].waitForExistence(timeout: 5))

        // Merge duplicate into Alex directly from the opponent picker.
        let manageDuplicate = app.buttons["manage-player-\(duplicate)"]
        XCTAssertTrue(manageDuplicate.waitForExistence(timeout: 5))
        manageDuplicate.tap()
        XCTAssertTrue(app.navigationBars[duplicate].waitForExistence(timeout: 5))
        app.buttons["merge-player"].tap()
        app.buttons["merge-target-\(alex)"].tap()
        let mergeConfirm = app.buttons["Merge"]
        XCTAssertTrue(mergeConfirm.waitForExistence(timeout: 5))
        mergeConfirm.tap()

        XCTAssertTrue(app.navigationBars["Opponent"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["roster-player-\(duplicate)"].exists)
        XCTAssertTrue(app.buttons["roster-player-\(alex)"].label.contains("2 matches"))

        // Rename Alex and set playing style directly from the opponent picker, then select them.
        app.buttons["manage-player-\(alex)"].tap()
        let nameField = app.textFields["rename-player-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.clearAndType(renamed)
        nameField.typeText("\n")
        XCTAssertTrue(app.navigationBars[renamed].waitForExistence(timeout: 5))

        let handednessPicker = app.buttons["player-handedness-picker"]
        for _ in 0..<5 where !handednessPicker.isHittable { app.swipeUp() }
        handednessPicker.tap()
        app.buttons["Left-handed"].tap()

        goBack(from: renamed)
        XCTAssertTrue(app.navigationBars["Opponent"].waitForExistence(timeout: 5))
        app.buttons["roster-player-\(renamed)"].tap()

        XCTAssertTrue(app.navigationBars["Match Info"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["manage-slot-opponent-0"].exists)
        app.buttons["save-match-info"].tap()
        XCTAssertTrue(matchInfoRow(contains: "vs \(renamed)"))
        closeDetail()
        XCTAssertTrue(archiveRow(first, contains: "vs \(renamed)"))
        XCTAssertTrue(archiveRow(second, contains: "vs \(renamed)"))
        XCTAssertTrue(archiveRow(third, contains: "vs \(renamed)"))
    }

    /// A saved player's profile persists as soon as a value is picked: leaving
    /// with the back button, with no other action, must not lose it.
    @MainActor
    func testSavedPlayerProfileAutosaves() throws {
        launch()
        let alex = "Alex \(token)"
        let match = createMatch(gamesMe: 2, complete: true)
        openMatch(match)
        editMatchInfo(competition: nil, opponents: [.new(alex)])

        openManagedOpponent()
        selectHandedness("Left-handed")
        goBack(from: alex)
        XCTAssertTrue(app.navigationBars["Match Info"].waitForExistence(timeout: 5))

        app.terminate()
        launch()
        openMatch(match)
        openManagedOpponent()
        XCTAssertTrue(app.buttons["player-handedness-picker"].label.contains("Left-handed"),
                      "The profile survives a relaunch without any explicit save")
    }

    /// A typed name is saved by Back, with no need to press return first.
    @MainActor
    func testTypedPlayerNameSavesWhenGoingBack() throws {
        launch()
        let alex = "Alex \(token)", renamed = "Rival \(token)"
        let match = createMatch(gamesMe: 2, complete: true)
        openMatch(match)
        editMatchInfo(competition: nil, opponents: [.new(alex)])

        openManagedOpponent()
        let field = app.textFields["rename-player-field"]
        field.tap()
        field.clearAndType(renamed)
        let back = app.buttons["player-manage-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(app.navigationBars["Match Info"].waitForExistence(timeout: 5))

        app.terminate()
        launch()
        openMatch(match)
        XCTAssertTrue(matchInfoRow(contains: "vs \(renamed)"), "The name survives a relaunch")
    }

    /// A player not yet in the archive keeps the picked profile on the Match
    /// Info draft, and Match Info's Save writes it.
    @MainActor
    func testNewPlayerProfileIsSavedWithMatchInfo() throws {
        launch()
        let alex = "Alex \(token)"
        let match = createMatch(gamesMe: 2, complete: true)
        openMatch(match)
        app.buttons["match-info-row"].tap()
        XCTAssertTrue(app.navigationBars["Match Info"].waitForExistence(timeout: 5))
        pick(.new(alex), slotButton: "Add opponent")

        app.buttons["manage-slot-opponent-0"].tap()
        selectHandedness("Left-handed")
        goBack(from: alex)
        XCTAssertTrue(app.navigationBars["Match Info"].waitForExistence(timeout: 5))
        app.buttons["save-match-info"].tap()
        XCTAssertTrue(matchInfoRow(contains: "vs \(alex)"))

        app.terminate()
        launch()
        openMatch(match)
        openManagedOpponent()
        XCTAssertTrue(app.buttons["player-handedness-picker"].label.contains("Left-handed"),
                      "The new player's profile is saved with the match")
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
        app.buttons["competition-practice"].tap()
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
        field.typeText("\n")
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
        XCTAssertTrue(app.buttons["private-note-storage"].exists)
        capture("13-notes-editor")
        app.buttons["done-match-note"].tap()
        XCTAssertTrue(notesRow.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForLabel(notesRow, contains: "Private note saved"))
        XCTAssertFalse(notesRow.label.contains("Attack the backhand"), "The detail row never previews private note text")
        XCTAssertFalse(anyElement(containing: "Attack the backhand \(token)").exists,
                       "Saved note prose is absent from accessibility outside the editor")
        capture("14-detail-with-note")
        closeDetail()

        app.terminate()
        launch()
        openMatch(match)
        let savedRow = app.buttons["match-notes-row"]
        XCTAssertTrue(waitForLabel(savedRow, contains: "Private note saved"), "The note survives a relaunch")
        XCTAssertFalse(savedRow.label.contains("Attack the backhand"))
        XCTAssertFalse(anyElement(containing: "Attack the backhand \(token)").exists)
        savedRow.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue((editor.value as? String)?.contains("Attack the backhand \(token)") == true,
                      "The full note is available after explicitly opening its editor")
        let counter = app.staticTexts["match-note-character-count"]
        let storage = app.buttons["private-note-storage"]
        let delete = app.buttons["delete-match-note"]
        XCTAssertTrue(counter.isHittable)
        XCTAssertGreaterThan(editor.frame.height, app.frame.height * 0.4,
                             "The note input uses the available screen height")
        XCTAssertGreaterThanOrEqual(counter.frame.minY, editor.frame.maxY)
        XCTAssertLessThan(counter.frame.maxY, storage.frame.minY)
        XCTAssertTrue(delete.isHittable)
        XCTAssertLessThan(app.frame.maxY - delete.frame.maxY, 100,
                          "Delete stays near the bottom without a large unused gap")
        XCTAssertFalse(anyElement(containing: "Private notes aren't synced").exists)
        storage.tap()
        XCTAssertTrue(anyElement(containing: "Stored on this iPhone").waitForExistence(timeout: 5))
        XCTAssertTrue(anyElement(containing: "Private notes aren't synced").waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        app.buttons["done-match-note"].tap()

        // Edit, then delete.
        app.buttons["match-notes-row"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(" Edited.")
        app.buttons["done-match-note"].tap()
        XCTAssertTrue(waitForLabel(app.buttons["match-notes-row"], contains: "Private note saved"))
        XCTAssertFalse(app.buttons["match-notes-row"].label.contains("Edited."))
        app.buttons["match-notes-row"].tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue((editor.value as? String)?.contains("Edited.") == true,
                      "The edited text was persisted without exposing it in the summary")
        app.buttons["delete-match-note"].tap()
        dialogButton("Delete Note", notIdentifier: "delete-match-note").tap()
        XCTAssertTrue(waitForLabel(app.buttons["match-notes-row"], contains: "Add private note"))
        closeDetail()
    }

    /// Cancelling a dirty Match Info draft asks before discarding. Only Discard
    /// Changes is visible (iOS 26+ hides a cancel-role button in popover dialogs);
    /// tapping outside the dialog keeps editing.
    @MainActor
    func testMatchInfoDirtyCancelCanKeepEditingOrDiscard() throws {
        launch()
        let match = createMatch(complete: true)
        openMatch(match)
        app.buttons["match-info-row"].tap()
        XCTAssertTrue(app.navigationBars["Match Info"].waitForExistence(timeout: 5))
        app.buttons["competition-league"].tap()
        app.navigationBars["Match Info"].buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Discard Changes"].waitForExistence(timeout: 5))
        // Tap outside the dialog to dismiss it and keep editing.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
        XCTAssertTrue(waitForNonExistence(app.buttons["Discard Changes"], timeout: 5))
        XCTAssertTrue(app.navigationBars["Match Info"].exists)
        XCTAssertTrue(app.buttons["competition-league"].isSelected || app.buttons["competition-league"].value as? String == "1",
                      "Tapping outside the dialog preserves the draft")
        app.navigationBars["Match Info"].buttons["Cancel"].tap()
        app.buttons["Discard Changes"].tap()
        XCTAssertTrue(app.buttons["match-info-row"].waitForExistence(timeout: 5))
        XCTAssertFalse(matchInfoRow(contains: "League"), "Discard leaves saved match info unchanged")
        closeDetail()
    }

    /// Tapping a selected competition clears it, and Save persists that clear.
    @MainActor
    func testCompetitionCanBeUntickedAndSaved() throws {
        launch()
        let match = createMatch(complete: true)
        openMatch(match)
        editMatchInfo(competition: "League", opponents: [])
        XCTAssertFalse(app.buttons["convert-match-type"].exists)
        app.buttons["match-info-row"].tap()
        XCTAssertTrue(app.navigationBars["Match Info"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Clear selection"].exists)
        let league = app.buttons["competition-league"]
        XCTAssertTrue(league.isSelected || league.value as? String == "1")
        league.tap()
        XCTAssertFalse(league.isSelected || league.value as? String == "1")
        app.buttons["save-match-info"].tap()
        XCTAssertTrue(app.buttons["match-info-row"].waitForExistence(timeout: 5))
        XCTAssertFalse(matchInfoRow(contains: "League"))
        app.buttons["match-info-row"].tap()
        XCTAssertTrue(app.navigationBars["Match Info"].waitForExistence(timeout: 5))
        XCTAssertFalse(league.isSelected || league.value as? String == "1",
                       "The unticked competition stays cleared after reopening")
        app.navigationBars["Match Info"].buttons["Cancel"].tap()
        closeDetail()
    }

    /// Returning an editor draft to its saved value is clean and dismisses without a prompt.
    @MainActor
    func testRevertedMatchInfoDraftCancelsWithoutPrompt() throws {
        launch()
        let match = createMatch(complete: true)
        openMatch(match)
        editMatchInfo(competition: "League", opponents: [])
        app.buttons["match-info-row"].tap()
        XCTAssertTrue(app.navigationBars["Match Info"].waitForExistence(timeout: 5))
        app.buttons["competition-friendly"].tap()
        app.buttons["competition-league"].tap()
        app.navigationBars["Match Info"].buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["match-info-row"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Keep Editing"].exists)
        app.buttons["match-info-row"].tap()
        XCTAssertTrue(app.navigationBars["Match Info"].waitForExistence(timeout: 5))
        dragNavigationBarDown("Match Info")
        XCTAssertTrue(waitForNonExistence(app.navigationBars["Match Info"], timeout: 5))
        XCTAssertFalse(app.buttons["Keep Editing"].exists, "A clean sheet can be swiped away")
        closeDetail()
    }

    /// Match Info saves only through its explicit Save button, so swiping a dirty
    /// sheet away (a downward drag from the navigation bar) never saves the edit.
    /// Whether the sheet closes or stays open is not part of the contract.
    @MainActor
    func testDirtyMatchInfoSwipeDoesNotSaveTheEdit() throws {
        launch()
        let match = createMatch(complete: true)
        openMatch(match)
        app.buttons["match-info-row"].tap()
        XCTAssertTrue(app.navigationBars["Match Info"].waitForExistence(timeout: 5))
        app.buttons["competition-league"].tap()
        dragNavigationBarDown("Match Info")
        Thread.sleep(forTimeInterval: 1)
        if app.navigationBars["Match Info"].exists {
            app.navigationBars["Match Info"].buttons["Cancel"].tap()
            if app.buttons["Discard Changes"].waitForExistence(timeout: 3) {
                app.buttons["Discard Changes"].tap()
            }
        }
        XCTAssertTrue(app.buttons["match-info-row"].waitForExistence(timeout: 5))
        XCTAssertFalse(matchInfoRow(contains: "League"), "A swipe never saves the draft")
        closeDetail()
    }

    /// The note saves itself: there is no Save or Cancel, and each way of
    /// leaving keeps what was typed.
    @MainActor
    func testPrivateNoteAutosavesHoweverItIsLeft() throws {
        launch()
        let match = createMatch(complete: true)
        openMatch(match)
        let row = app.buttons["match-notes-row"]
        row.tap()
        let editor = app.textViews["match-notes-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let bar = app.navigationBars["Private Note"]
        XCTAssertFalse(bar.buttons["Cancel"].exists, "There is nothing to cancel")
        XCTAssertFalse(bar.buttons["Save"].exists, "There is nothing to save by hand")

        // The save during a pause must not disturb typing: the caret stays put
        // when the store publishes and Delete Note appears below the editor.
        let first = "First \(token)"
        editor.typeText(first)
        XCTAssertTrue(app.buttons["delete-match-note"].waitForExistence(timeout: 5),
                      "A pause in typing saved the note")
        XCTAssertTrue(app.buttons["delete-match-note"].isHittable,
                      "Delete remains visible above the keyboard")
        XCTAssertTrue(app.staticTexts["match-note-character-count"].isHittable,
                      "The character count stays visible while typing")
        Thread.sleep(forTimeInterval: 1)
        editor.typeText(" more")
        XCTAssertEqual(editor.value as? String, "\(first) more")

        // Swipe-down works once the pause has saved the latest text.
        Thread.sleep(forTimeInterval: 1)
        dragNavigationBarDown("Private Note")
        XCTAssertTrue(waitForNonExistence(bar, timeout: 5), "Swipe-down closes without a prompt")
        XCTAssertFalse(app.buttons["Keep Editing"].exists)
        XCTAssertTrue(waitForLabel(row, contains: "Private note saved"))

        // Done straight after typing.
        row.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "\(first) more", "Swipe-down saved the latest text")
        editor.tap()
        editor.typeText("second")
        app.buttons["done-match-note"].tap()
        XCTAssertTrue(waitForNonExistence(bar, timeout: 5))

        // Pausing is enough, even if the app is then killed from the editor.
        row.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue((editor.value as? String)?.contains("second") == true, "Done saved the latest text")
        editor.tap()
        editor.typeText("third")
        Thread.sleep(forTimeInterval: 2)
        app.terminate()
        launch()
        openMatch(match)
        row.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue((editor.value as? String)?.contains("third") == true, "A pause in typing saved the note")

        // Going to the background saves at once, with no pause.
        editor.tap()
        editor.typeText("fourth")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 0.5)
        app.terminate()
        launch()
        openMatch(match)
        row.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue((editor.value as? String)?.contains("fourth") == true, "Backgrounding saved the note")

        // Emptying the text clears the note. Tapping low in the editor puts the
        // caret after the text, so the deletes remove all of it.
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.9)).tap()
        editor.clearAndType("")
        app.buttons["done-match-note"].tap()
        XCTAssertTrue(waitForLabel(row, contains: "Add private note"))
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
    /// choices become full-width rows with readable labels.
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
        XCTAssertFalse(app.segmentedControls.firstMatch.exists, "Full-width choices at accessibility sizes")
        let tournament = app.buttons["competition-tournament"]
        XCTAssertTrue(tournament.waitForExistence(timeout: 5))
        XCTAssertEqual(tournament.label, "Tournament")
        let league = app.buttons["competition-league"]
        XCTAssertEqual(tournament.frame.minX, league.frame.minX, accuracy: 1)
        XCTAssertGreaterThan(tournament.frame.minY, league.frame.minY)
        league.tap()
        pick(.new(rio), slotButton: "Add opponent")
        capture("18-editor-large-type")
        app.buttons["save-match-info"].tap()
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(waitForLabel(row, contains: "vs \(rio) · League"))
        capture("19-detail-large-type")
        closeDetail()
    }

    /// Compact details remember both expansion states across launches. Recent
    /// selection stays in the editor, reuses identity, and excludes doubles slots.
    @MainActor
    func testCompactDetailsAndRecentPlayers() throws {
        launch()
        let alex = "Alex \(token)"
        let first = createMatch(complete: true)
        openMatch(first)
        editMatchInfo(competition: "Tournament", opponents: [.new(alex)])
        let disclosure = app.buttons["match-info-disclosure"]
        XCTAssertTrue(disclosure.label.contains("Tournament"))
        disclosure.tap()
        XCTAssertEqual(disclosure.value as? String, "Collapsed")
        XCTAssertFalse(app.buttons["match-info-row"].exists)
        XCTAssertFalse(app.buttons["match-notes-row"].exists)
        capture("20-compact-match-info")
        closeDetail()
        app.terminate()
        launch()
        revealRow(first).tap()
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        XCTAssertEqual(disclosure.value as? String, "Collapsed")
        disclosure.tap()
        closeDetail()
        app.terminate()
        launch()
        revealRow(first).tap()
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        XCTAssertEqual(disclosure.value as? String, "Expanded")
        closeDetail()

        // Add three more identities so every empty slot can show four recents.
        let rosterMatch = createMatch(complete: true, doubles: true)
        openMatch(rosterMatch)
        app.buttons["match-info-row"].tap()
        XCTAssertTrue(app.navigationBars["Match Info"].waitForExistence(timeout: 5))
        pick(.new("Sam \(token)"), slotButton: "Add partner")
        pick(.new("Jo \(token)"), slotButton: "Add opponent 1")
        pick(.new("Pat \(token)"), slotButton: "Add opponent 2")
        app.buttons["save-match-info"].tap()
        XCTAssertTrue(app.buttons["match-info-row"].waitForExistence(timeout: 5))
        closeDetail()

        let second = createMatch(complete: true, doubles: true)
        openMatch(second)
        app.buttons["match-info-row"].tap()
        let recentPartner = app.buttons["recent-partner-\(alex)"]
        XCTAssertTrue(recentPartner.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "recent-partner-")).count, 4)
        recentPartner.tap()
        XCTAssertTrue(app.navigationBars["Match Info"].exists, "Quick selection stays on the first screen")
        XCTAssertLessThan(app.buttons["manage-slot-partner"].frame.maxX, app.staticTexts[alex].frame.minX)
        XCTAssertFalse(app.buttons["\(alex), change"].exists)
        XCTAssertFalse(app.buttons["recent-opponent-0-\(alex)"].exists)
        XCTAssertFalse(app.buttons["recent-opponent-1-\(alex)"].exists)
        app.buttons["Remove \(alex)"].tap()
        let recentOpponent = app.buttons["recent-opponent-0-\(alex)"]
        for _ in 0..<4 where !recentOpponent.isHittable { app.swipeUp() }
        recentOpponent.tap()
        XCTAssertFalse(app.buttons["recent-opponent-1-\(alex)"].exists)
        XCTAssertFalse(app.buttons["recent-partner-\(alex)"].exists)
        capture("21-recent-player-selected")
        app.buttons["save-match-info"].tap()
        XCTAssertTrue(matchInfoRow(contains: "vs \(alex)"))
        closeDetail()
        openPlayers()
        XCTAssertTrue(app.buttons["player-row-\(alex)"].label.contains("2 matches"), "Recent selection reuses identity")
        closeSettings()
    }

    /// Prepare Game Plan opens from an opponent's profile ready to hand off:
    /// Last 5, names on, and the upcoming match pre-filled from the previous
    /// match. The size estimate follows the selection and the contents, each
    /// of which is edited on its own pushed screen, and the preview shows the
    /// exact pack.
    @MainActor
    func testPrepareGamePlanFromOpponentProfile() throws {
        launch()
        let opponent = "Planner \(token)"
        let league = createMatch(gamesMe: 3, gamesOpp: 1, complete: true)
        openMatch(league)
        editMatchInfo(competition: "League", opponents: [.new(opponent)])
        closeDetail()
        let friendly = createMatch(gamesMe: 1, gamesOpp: 3, complete: true)
        openMatch(friendly)
        editMatchInfo(competition: "Friendly", opponents: [.existing(opponent)])
        closeDetail()

        let sectionLink = app.buttons["opponents-section-link"]
        for _ in 0..<10 where !(sectionLink.exists && sectionLink.isHittable) { app.swipeDown() }
        XCTAssertTrue(sectionLink.waitForExistence(timeout: 5))
        sectionLink.tap()
        let row = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "opponent-row-", opponent
        )).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let prepare = app.buttons["opponent-prepare-game-plan"]
        XCTAssertTrue(prepare.waitForExistence(timeout: 5), "The entry point sits on the opponent's profile")
        capture("30-opponent-prepare-entry")
        prepare.tap()
        let mainBar = app.navigationBars["Prepare Game Plan"]
        XCTAssertTrue(mainBar.waitForExistence(timeout: 5))

        // Ready on arrival: the estimate and the hand-off sit on the first screen.
        let estimate = app.descendants(matching: .any)["game-plan-estimate"]
        XCTAssertTrue(estimate.waitForExistence(timeout: 15), "The size estimate appears once the pack is built")
        XCTAssertTrue(waitForLabel(estimate, contains: "2 matches selected"))
        XCTAssertTrue(estimate.label.contains("Estimated input: ~"), "VoiceOver hears the count and the estimate together")
        XCTAssertTrue((estimate.value as? String ?? "").hasPrefix("Names included"), "Names start on")
        XCTAssertTrue(app.buttons["game-plan-share"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["game-plan-upcoming"].label.contains("Friendly"),
                      "The upcoming match is pre-filled from the previous match")
        capture("31-game-plan-estimate")

        // A smaller selection rebuilds the estimate.
        app.buttons["game-plan-evidence"].tap()
        XCTAssertTrue(app.navigationBars["Matches"].waitForExistence(timeout: 5))
        app.buttons["game-plan-choose-matches"].tap()
        XCTAssertTrue(app.navigationBars["Choose Matches"].waitForExistence(timeout: 5))
        app.buttons["game-plan-match-\(uuid(league))"].tap()
        capture("32-game-plan-choose-matches")
        app.navigationBars["Choose Matches"].buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Custom selection"].waitForExistence(timeout: 5))
        app.navigationBars["Matches"].buttons.firstMatch.tap()
        XCTAssertTrue(mainBar.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForLabel(estimate, contains: "1 match selected", timeout: 15))

        // Names off rebuilds the pack without them.
        app.buttons["game-plan-contents"].tap()
        XCTAssertTrue(app.navigationBars["Pack Contents"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["game-plan-include-names"].value as? String, "1", "Names start on")
        flipSwitch("game-plan-include-names")
        app.navigationBars["Pack Contents"].buttons.firstMatch.tap()
        XCTAssertTrue(mainBar.waitForExistence(timeout: 5))
        let rebuilt = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value BEGINSWITH %@", "Names not included"), object: estimate)
        XCTAssertEqual(XCTWaiter().wait(for: [rebuilt], timeout: 15), .completed, "The pack rebuilds without names")
        let preview = app.buttons["game-plan-preview"]
        for _ in 0..<6 where !(preview.exists && preview.isHittable) { app.swipeUp() }
        XCTAssertTrue(preview.waitForExistence(timeout: 15))
        capture("33-game-plan-hand-off")
        preview.tap()
        XCTAssertTrue(app.navigationBars["Preview"].waitForExistence(timeout: 5))
        capture("34-game-plan-preview")
        app.buttons["game-plan-view-text"].tap()
        let text = app.textViews["game-plan-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        let contents = text.value as? String ?? ""
        XCTAssertFalse(contents.contains("\"\(opponent)\""), "Names were switched off")
        XCTAssertTrue(contents.contains("## 7. Coaching Request"))
        XCTAssertTrue(contents.contains("competition Friendly;"), "The upcoming competition comes from the previous match")
        capture("35-game-plan-text")
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

    @MainActor
    private func dragNavigationBarDown(_ title: String) {
        let bar = app.navigationBars[title]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.82))
        start.press(forDuration: 0.1, thenDragTo: end)
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
        let score = app.staticTexts["match-header-score"]
        XCTAssertTrue(score.waitForExistence(timeout: 5), "The header score is on screen")
        return score.label
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
        if let competition { app.buttons["competition-\(competition.lowercased())"].tap() }
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

    /// From a match's detail: Match Info → the first opponent's manage screen.
    @MainActor
    private func openManagedOpponent() {
        let row = app.buttons["match-info-row"]
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        row.tap()
        XCTAssertTrue(app.navigationBars["Match Info"].waitForExistence(timeout: 5))
        let manage = app.buttons["manage-slot-opponent-0"]
        for _ in 0..<4 where !manage.isHittable { app.swipeUp() }
        manage.tap()
        XCTAssertTrue(app.buttons["player-handedness-picker"].waitForExistence(timeout: 5))
    }

    /// Picks a handedness and checks the picker now shows it.
    @MainActor
    private func selectHandedness(_ value: String) {
        let picker = app.buttons["player-handedness-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        for _ in 0..<5 where !picker.isHittable { app.swipeUp() }
        picker.tap()
        app.buttons[value].tap()
        XCTAssertTrue(waitForLabel(picker, contains: value), "The picker shows \(value) once picked")
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
