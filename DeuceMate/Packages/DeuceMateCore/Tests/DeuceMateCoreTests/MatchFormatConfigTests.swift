// MatchFormatConfigTests.swift — pins the data-driven rules for every
// MatchFormat so an accidental change to a format's config is caught.
//
// The format rules are otherwise only exercised implicitly via stats tests,
// which would not necessarily fail if, say, the deciding-set tiebreak length
// changed. These assertions lock the exact values and the set-completion logic.
import XCTest
@testable import DeuceMateCore

final class MatchFormatConfigTests: XCTestCase {

    // MARK: - Per-format config values

    func test_standard_config() {
        let c = MatchFormat.standard.config
        XCTAssertEqual(c.setsToWin, 2)
        XCTAssertTrue(c.playRegularSets)
        XCTAssertEqual(c.regularSetWinAtGames, 6)
        XCTAssertEqual(c.regularSetTiebreakAtGames, 6)
        XCTAssertEqual(c.regularSetTiebreakPoints, 7)
        XCTAssertEqual(c.finalSetStyle, .superTiebreak)
        XCTAssertEqual(c.finalSetTiebreakPoints, 10)
        XCTAssertTrue(c.tiebreakRequiresTwoPointLead)
        XCTAssertFalse(c.isEndless)
        XCTAssertFalse(c.disablesPointTracking)
        XCTAssertFalse(c.fixedDeuceSide)
    }

    func test_bestOf3FullFinalSet_config() {
        let c = MatchFormat.bestOf3FullFinalSet.config
        XCTAssertEqual(c.setsToWin, 2)
        XCTAssertTrue(c.playRegularSets)
        XCTAssertEqual(c.regularSetTiebreakPoints, 7)
        XCTAssertEqual(c.finalSetStyle, .fullSetWithTiebreak)
        XCTAssertEqual(c.finalSetTiebreakPoints, 7)
        XCTAssertFalse(c.isEndless)
    }

    func test_superTiebreak_config() {
        let c = MatchFormat.superTiebreak.config
        XCTAssertEqual(c.setsToWin, 1)
        XCTAssertFalse(c.playRegularSets)
        XCTAssertEqual(c.regularSetTiebreakPoints, 10)
        XCTAssertEqual(c.finalSetStyle, .superTiebreak)
        XCTAssertEqual(c.finalSetTiebreakPoints, 10)
        XCTAssertFalse(c.isEndless)
    }

    func test_perpetualSuperTiebreak_config() {
        let c = MatchFormat.perpetualSuperTiebreak.config
        XCTAssertEqual(c.setsToWin, 1)
        XCTAssertFalse(c.playRegularSets)
        XCTAssertEqual(c.finalSetTiebreakPoints, 10)
        XCTAssertTrue(c.isEndless)
    }

    func test_quick4Games_config() {
        let c = MatchFormat.quick4Games.config
        XCTAssertEqual(c.setsToWin, 1)
        XCTAssertTrue(c.playRegularSets)
        XCTAssertEqual(c.regularSetWinAtGames, 3)
        XCTAssertEqual(c.regularSetTiebreakAtGames, 2)
        XCTAssertEqual(c.regularSetTiebreakPoints, 1)
        XCTAssertEqual(c.finalSetStyle, .fullSetWithTiebreak)
        XCTAssertEqual(c.finalSetTiebreakPoints, 1)
        XCTAssertFalse(c.tiebreakRequiresTwoPointLead)   // sudden death
        XCTAssertFalse(c.isEndless)
    }

    func test_perpetualPoints_config() {
        let c = MatchFormat.perpetualPoints.config
        XCTAssertEqual(c.setsToWin, 1)
        XCTAssertFalse(c.playRegularSets)
        XCTAssertTrue(c.isEndless)
        XCTAssertTrue(c.disablesPointTracking)
        XCTAssertTrue(c.fixedDeuceSide)
    }

    // MARK: - regularSetTiebreakWinAtGames

    func test_regularSetTiebreakWinAtGames() {
        XCTAssertEqual(MatchFormat.standard.config.regularSetTiebreakWinAtGames, 7)
        XCTAssertEqual(MatchFormat.quick4Games.config.regularSetTiebreakWinAtGames, 3)
    }

    // MARK: - isNormalSetComplete

    func test_isNormalSetComplete_standard() {
        let c = MatchFormat.standard.config
        XCTAssertTrue(c.isNormalSetComplete(gamesMe: 6, gamesOpponent: 4))   // 6–4, two-game lead
        XCTAssertFalse(c.isNormalSetComplete(gamesMe: 6, gamesOpponent: 5))  // 6–5, must continue
        XCTAssertTrue(c.isNormalSetComplete(gamesMe: 7, gamesOpponent: 5))   // 7–5
        XCTAssertTrue(c.isNormalSetComplete(gamesMe: 7, gamesOpponent: 6))   // won via tiebreak
        XCTAssertFalse(c.isNormalSetComplete(gamesMe: 6, gamesOpponent: 6))  // tiebreak pending
        XCTAssertFalse(c.isNormalSetComplete(gamesMe: 5, gamesOpponent: 5))
    }

    func test_isNormalSetComplete_quick4() {
        let c = MatchFormat.quick4Games.config
        XCTAssertTrue(c.isNormalSetComplete(gamesMe: 3, gamesOpponent: 1))   // 3–1, two-game lead
        XCTAssertTrue(c.isNormalSetComplete(gamesMe: 3, gamesOpponent: 2))   // 3–2, won via sudden death (game 3)
        XCTAssertFalse(c.isNormalSetComplete(gamesMe: 2, gamesOpponent: 2))  // sudden-death point pending
        XCTAssertFalse(c.isNormalSetComplete(gamesMe: 2, gamesOpponent: 1))
    }

    // MARK: - isDecidingSuperTiebreak

    func test_isDecidingSuperTiebreak_standard() {
        let c = MatchFormat.standard.config
        // Best-of-3: deciding set is index 2 (2 * setsToWin - 2).
        XCTAssertFalse(c.isDecidingSuperTiebreak(setIndex: 0))
        XCTAssertFalse(c.isDecidingSuperTiebreak(setIndex: 1))
        XCTAssertTrue(c.isDecidingSuperTiebreak(setIndex: 2))
    }

    func test_isDecidingSuperTiebreak_falseForNonSuperTiebreakFinals() {
        // Full final set never jumps to a standalone tiebreak set.
        XCTAssertFalse(MatchFormat.bestOf3FullFinalSet.config.isDecidingSuperTiebreak(setIndex: 2))
        // Pure-tiebreak formats don't play regular sets, so this is always false.
        XCTAssertFalse(MatchFormat.superTiebreak.config.isDecidingSuperTiebreak(setIndex: 0))
    }
}
