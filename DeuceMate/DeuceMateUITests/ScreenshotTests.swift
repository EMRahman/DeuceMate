// ScreenshotTests.swift — captures fresh App Store/doc screenshots from a real
// imported match. Opt-in only (DEUCEMATE_CAPTURE_SCREENSHOTS=1): this target is
// part of the default "DeuceMate" scheme, so an ungated run would fail on any
// simulator whose archive isn't seeded with `targetMatchID`. Run explicitly via
// `DEUCEMATE_CAPTURE_SCREENSHOTS=1 xcodebuild test -only-testing:DeuceMateUITests/ScreenshotTests`.
// See docs/screenshots/README.md for the full capture workflow (seeding the
// archive, running this suite, rendering the AI-prompt shots).
import XCTest

/// Absolute host path screenshots are written to — the test process runs
/// unsandboxed on the simulator host, so a plain file write reaches the Mac's
/// disk directly (same technique fastlane's `snapshot` uses). Override with
/// DEUCEMATE_SCREENSHOT_OUTPUT_DIR; defaults to a temp folder.
private let screenshotOutputDir = ProcessInfo.processInfo.environment["DEUCEMATE_SCREENSHOT_OUTPUT_DIR"]
    ?? NSTemporaryDirectory() + "deucemate-screenshots"

/// UUID of the match to capture — seeded into the archive beforehand via
/// `DeuceMateArchiveTool seed`. Override with DEUCEMATE_TARGET_MATCH_ID;
/// defaults to the latest completed match (2026-08-05) from the real imported
/// archive used to capture the currently committed App Store upload set.
private let targetMatchID = ProcessInfo.processInfo.environment["DEUCEMATE_TARGET_MATCH_ID"]
    ?? "44ACB61B-BBF0-444C-86BC-2A0125E0DF6D"

final class ScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["DEUCEMATE_CAPTURE_SCREENSHOTS"] == "1",
            "Opt-in only — set DEUCEMATE_CAPTURE_SCREENSHOTS=1 (and seed the archive) to run this marketing-screenshot helper; see docs/screenshots/README.md."
        )
    }

    @MainActor
    private func saveScreenshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let dir = URL(fileURLWithPath: screenshotOutputDir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(name).png")
        try? shot.pngRepresentation.write(to: url)
    }

    @MainActor
    func test_captureAppStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launch()

        let matchRow = app.buttons["match-row-\(targetMatchID)"]
        XCTAssertTrue(app.navigationBars["Matches"].waitForExistence(timeout: 20))
        // The archive establishes that this is a real product with useful
        // history, rather than a one-screen score counter.
        saveScreenshot("05-match-archive")
        for _ in 0..<6 where !matchRow.exists {
            app.swipeUp()
        }
        try XCTSkipUnless(
            matchRow.waitForExistence(timeout: 10),
            "Archive not seeded with match \(targetMatchID) — run `DeuceMateArchiveTool seed` first; see docs/screenshots/README.md."
        )
        matchRow.tap()

        // Strongest first upload slot: completed score, result, points graph,
        // and the beginning of the match analysis on one screen.
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 0.5)
        saveScreenshot("01-match-overview")

        // --- Expanded Points Graph: HR + steps overlays ---
        let expandButton = app.buttons["expand-points-graph"]
        for _ in 0..<4 where !expandButton.exists {
            app.swipeUp()
        }
        XCTAssertTrue(expandButton.waitForExistence(timeout: 10))
        expandButton.tap()

        XCTAssertTrue(app.navigationBars["Points Graph"].waitForExistence(timeout: 10))
        // Add authentic health overlays when the seeded full-fidelity archive
        // contains them. A score-only archive still produces the base graph.
        let stepsToggle = app.buttons["steps-overlay-toggle"]
        if stepsToggle.waitForExistence(timeout: 3) {
            stepsToggle.tap()
        }
        let heartRateToggle = app.buttons["heart-rate-overlay-toggle"]
        if heartRateToggle.waitForExistence(timeout: 3) {
            heartRateToggle.tap()
        }
        Thread.sleep(forTimeInterval: 0.5)
        saveScreenshot("02-points-momentum")
        app.navigationBars["Points Graph"].buttons["Done"].tap()
        XCTAssertTrue(app.buttons["expand-points-graph"].waitForExistence(timeout: 10))

        // --- Stats tab, scrolled to data-driven coaching insights ---
        let coachingHeading = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH 'Coaching Insights'"))
            .firstMatch
        for _ in 0..<6 where !coachingHeading.exists {
            app.swipeUp()
        }
        XCTAssertTrue(coachingHeading.waitForExistence(timeout: 10))
        saveScreenshot("04-coaching-insights")

        // --- Stats tab, scrolled to Outcome Breakdown / Serve: 03 ---
        let outcomeBreakdown = app.staticTexts["Outcome Breakdown"]
        for _ in 0..<8 where !outcomeBreakdown.exists {
            app.swipeUp()
        }
        XCTAssertTrue(outcomeBreakdown.waitForExistence(timeout: 10))
        // "Outcome Breakdown" merely existing can mean it's only just peeking
        // into frame at the bottom edge — scroll a little further so it leads
        // the shot (Winners/Unforced Errors/Aggression Index), without
        // overshooting into the Serve/Return/Break Points sections below it.
        app.swipeUp(velocity: .slow)
        saveScreenshot("03-match-stats")

    }

    /// The screens that changed or arrived with Match Info. These show player
    /// names, so seed an archive whose names are fictional, never a real
    /// player's. Set DEUCEMATE_TARGET_MATCH_ID to a tagged rematch so Compare
    /// has a same-opponent baseline, and DEUCEMATE_OPPONENT_NAME to that opponent.
    @MainActor
    func test_captureMatchInfoScreens() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Matches"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 1)
        saveScreenshot("05-match-archive")

        // --- Opponents directory, then one opponent's head-to-head ---
        let opponentsLink = app.buttons["opponents-section-link"]
        XCTAssertTrue(opponentsLink.waitForExistence(timeout: 10))
        opponentsLink.tap()
        let opponentName = ProcessInfo.processInfo.environment["DEUCEMATE_OPPONENT_NAME"] ?? "Alice Morgan"
        let opponentRow = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH 'opponent-row-' AND label CONTAINS %@", opponentName))
            .firstMatch
        XCTAssertTrue(opponentRow.waitForExistence(timeout: 10))
        opponentRow.tap()
        Thread.sleep(forTimeInterval: 1)
        saveScreenshot("09-opponent-head-to-head")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        Thread.sleep(forTimeInterval: 0.5)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // --- Match detail with Match Info open ---
        let matchRow = app.buttons["match-row-\(targetMatchID)"]
        for _ in 0..<6 where !matchRow.exists {
            app.swipeUp()
        }
        XCTAssertTrue(matchRow.waitForExistence(timeout: 10))
        matchRow.tap()
        let disclosure = app.buttons["match-info-disclosure"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 10))
        let compare = app.buttons["compare-previous-match"]
        if !compare.waitForExistence(timeout: 1) {
            disclosure.tap()
        }
        XCTAssertTrue(compare.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.5)
        saveScreenshot("01-match-overview")

        // --- Compare with Previous Match ---
        compare.tap()
        Thread.sleep(forTimeInterval: 1)
        saveScreenshot("08-compare-previous-match")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(disclosure.waitForExistence(timeout: 10))
    }

    /// Coaching Insights, from a match that earns several ranked observations.
    /// Point DEUCEMATE_TARGET_MATCH_ID at that match for this run.
    @MainActor
    func test_captureCoachingInsights() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Matches"].waitForExistence(timeout: 20))
        let matchRow = app.buttons["match-row-\(targetMatchID)"]
        for _ in 0..<12 where !matchRow.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(matchRow.waitForExistence(timeout: 10))
        matchRow.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
        let coachingHeading = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH 'Coaching Insights'"))
            .firstMatch
        for _ in 0..<6 where !coachingHeading.exists {
            app.swipeUp()
        }
        XCTAssertTrue(coachingHeading.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 0.5)
        saveScreenshot("04-coaching-insights")
    }

    // MARK: - README gallery (docs/screenshots/README.md)

    /// Scrolls with slow drags from the left gutter (clear of the charts) until
    /// `element` sits just below the navigation bar, so a shot leads with it.
    @MainActor
    private func bring(_ element: XCUIElement, in app: XCUIApplication, toY target: CGFloat = 132) {
        for _ in 0..<14 {
            guard element.exists else {
                drag(in: app, by: 420)
                continue
            }
            let delta = element.frame.minY - target
            if abs(delta) < 24 { return }
            drag(in: app, by: max(-420, min(420, delta)))
        }
    }

    @MainActor
    private func drag(in app: XCUIApplication, by delta: CGFloat) {
        let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0))
        let start = origin.withOffset(CGVector(dx: 0, dy: delta > 0 ? 700 : 200))
        let end = start.withOffset(CGVector(dx: 0, dy: -delta))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    @MainActor
    private func openTargetMatch(_ id: String, in app: XCUIApplication) {
        let matchRow = app.buttons["match-row-\(id)"]
        for _ in 0..<40 where !matchRow.isHittable {
            app.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(matchRow.waitForExistence(timeout: 10))
        matchRow.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 0.5)
    }

    /// One match's report: momentum graph, Pulse Coach zones, insights, stats.
    /// Run in dark appearance with DEUCEMATE_TARGET_MATCH_ID set to a tracked
    /// match that has recorded heart rate.
    @MainActor
    func test_captureReadmeMatchShots() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Matches"].waitForExistence(timeout: 20))
        openTargetMatch(targetMatchID, in: app)

        let expand = app.buttons["expand-points-graph"]
        for _ in 0..<4 where !expand.exists { app.swipeUp() }
        XCTAssertTrue(expand.waitForExistence(timeout: 10))
        expand.tap()
        XCTAssertTrue(app.navigationBars["Points Graph"].waitForExistence(timeout: 10))
        let heartRate = app.buttons["heart-rate-overlay-toggle"]
        if heartRate.waitForExistence(timeout: 3) { heartRate.tap() }
        let pointsWon = app.buttons["points-won-chip"]
        XCTAssertTrue(pointsWon.waitForExistence(timeout: 5))
        pointsWon.tap()
        Thread.sleep(forTimeInterval: 0.8)
        saveScreenshot("readme-momentum")
        app.navigationBars["Points Graph"].buttons["Done"].tap()
        XCTAssertTrue(expand.waitForExistence(timeout: 10))

        let insights = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH 'Coaching Insights'")).firstMatch
        bring(insights, in: app)
        Thread.sleep(forTimeInterval: 0.5)
        saveScreenshot("readme-insights")

        bring(app.staticTexts["Pulse Coach"], in: app)
        Thread.sleep(forTimeInterval: 0.5)
        saveScreenshot("readme-pulse-zones")

        let outcomes = app.staticTexts["Outcome Breakdown"]
        bring(outcomes, in: app)
        Thread.sleep(forTimeInterval: 0.5)
        saveScreenshot("readme-stats")
    }

    /// Screens that span matches: Trends, one opponent, and Compare. Set
    /// DEUCEMATE_TARGET_MATCH_ID to a rematch and DEUCEMATE_OPPONENT_NAME to a
    /// fictional opponent with several matches. Never capture a real name.
    @MainActor
    func test_captureReadmeArchiveShots() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Matches"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 1)

        let trends = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Unforced'")).firstMatch
        XCTAssertTrue(trends.waitForExistence(timeout: 10))
        trends.tap()
        XCTAssertTrue(app.navigationBars["Trends"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1)
        saveScreenshot("readme-trends")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let opponentsLink = app.buttons["opponents-section-link"]
        XCTAssertTrue(opponentsLink.waitForExistence(timeout: 10))
        opponentsLink.tap()
        let opponentName = ProcessInfo.processInfo.environment["DEUCEMATE_OPPONENT_NAME"] ?? "Alice Morgan"
        let opponentRow = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH 'opponent-row-' AND label CONTAINS %@", opponentName))
            .firstMatch
        XCTAssertTrue(opponentRow.waitForExistence(timeout: 10))
        opponentRow.tap()
        Thread.sleep(forTimeInterval: 1)
        saveScreenshot("readme-head-to-head")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        Thread.sleep(forTimeInterval: 0.5)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        openTargetMatch(targetMatchID, in: app)
        let disclosure = app.buttons["match-info-disclosure"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 10))
        let compare = app.buttons["compare-previous-match"]
        if !compare.waitForExistence(timeout: 1) { disclosure.tap() }
        XCTAssertTrue(compare.waitForExistence(timeout: 5))
        compare.tap()
        Thread.sleep(forTimeInterval: 1)
        bring(app.staticTexts["Rates"], in: app)
        Thread.sleep(forTimeInterval: 0.5)
        saveScreenshot("readme-compare")
    }

    /// The AI Coach sheet the marketing frame composites. Run with the
    /// simulator in dark appearance (`simctl ui <udid> appearance dark`).
    @MainActor
    func test_captureAICoachSheet() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Matches"].waitForExistence(timeout: 20))
        let matchRow = app.buttons["match-row-\(targetMatchID)"]
        for _ in 0..<6 where !matchRow.exists {
            app.swipeUp()
        }
        XCTAssertTrue(matchRow.waitForExistence(timeout: 10))
        matchRow.tap()
        let aiCoach = app.buttons["AI Coach"]
        XCTAssertTrue(aiCoach.waitForExistence(timeout: 10))
        aiCoach.tap()
        // A match with recorded health data asks for consent first.
        let continueButton = app.alerts.buttons["Continue"]
        if continueButton.waitForExistence(timeout: 3) {
            continueButton.tap()
        }
        XCTAssertTrue(app.navigationBars["AI Coach"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.5)
        saveScreenshot("ai-coach-sheet")
    }
}
