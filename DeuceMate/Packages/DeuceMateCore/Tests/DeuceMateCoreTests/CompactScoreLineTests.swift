// CompactScoreLineTests.swift — the narrow hyphen-separated score line the
// watch stats header and history rows render.
import XCTest
@testable import DeuceMateCore

final class CompactScoreLineTests: XCTestCase {

    // MatchRecord.gameScoreString uses an en dash between the two point scores.
    private let dash = "\u{2013}"

    private func regular(_ me: Int, _ opp: Int) -> SetScore {
        SetScore(gamesMe: me, gamesOpponent: opp)
    }

    private func tiebreak(games: (Int, Int), points: (Int, Int)) -> SetScore {
        SetScore(
            gamesMe: games.0,
            gamesOpponent: games.1,
            isTieBreak: true,
            tieBreakPointsMe: points.0,
            tieBreakPointsOpponent: points.1
        )
    }

    // MARK: - Single set

    func test_setScore_regularSet() {
        XCTAssertEqual(CompactScoreLine.setScore(regular(6, 4), setIndex: 0, matchFormat: .standard), "6-4")
    }

    func test_setScore_regularSetTiebreak_appendsParenthetical() {
        let set = tiebreak(games: (7, 6), points: (7, 5))
        XCTAssertEqual(CompactScoreLine.setScore(set, setIndex: 0, matchFormat: .standard), "7-6(7-5)")
    }

    func test_setScore_decidingSuperTiebreak_usesRawPoints() {
        // .standard's third set is a 10-point super-tiebreak with no games.
        let set = tiebreak(games: (0, 0), points: (10, 8))
        XCTAssertEqual(CompactScoreLine.setScore(set, setIndex: 2, matchFormat: .standard), "10-8")
    }

    func test_setScore_tiebreakOnlyFormats_useRawPoints() {
        let set = tiebreak(games: (0, 0), points: (10, 6))
        XCTAssertEqual(CompactScoreLine.setScore(set, setIndex: 0, matchFormat: .superTiebreak), "10-6")
        XCTAssertEqual(CompactScoreLine.setScore(set, setIndex: 1, matchFormat: .perpetualSuperTiebreak), "10-6")
    }

    // MARK: - Completed match

    func test_completed_joinsEverySetWithTheGivenSeparator() {
        let sets = [regular(6, 4), regular(4, 6), tiebreak(games: (0, 0), points: (10, 8))]
        XCTAssertEqual(
            CompactScoreLine.completed(setScores: sets, matchFormat: .standard),
            "6-4  4-6  10-8"
        )
        XCTAssertEqual(
            CompactScoreLine.completed(setScores: sets, matchFormat: .standard, separator: ", "),
            "6-4, 4-6, 10-8"
        )
        XCTAssertEqual(CompactScoreLine.completed(setScores: [], matchFormat: .standard), "")
    }

    // MARK: - In-progress match

    func test_inProgress_appendsCurrentGameScore() {
        let record = MatchRecord(
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            setScores: [regular(6, 4), regular(3, 2)],
            stats: [],
            currentPointsMe: 3,
            currentPointsOpponent: 1
        )
        XCTAssertEqual(CompactScoreLine.inProgress(record), "6-4  3-2  (40\(dash)15)")
    }

    func test_inProgress_omitsParentheticalAtLoveAll() {
        let record = MatchRecord(
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            setScores: [regular(2, 1)],
            stats: []
        )
        XCTAssertEqual(CompactScoreLine.inProgress(record), "2-1")
    }

    func test_inProgress_currentTiebreakIsPrefixed() {
        let record = MatchRecord(
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            setScores: [regular(6, 4), tiebreak(games: (6, 6), points: (5, 3))],
            stats: [],
            currentPointsMe: 5,
            currentPointsOpponent: 3
        )
        XCTAssertEqual(CompactScoreLine.inProgress(record), "6-4  TB 5-3")
    }

    func test_inProgress_isNilBeforeAnySetExists() {
        let record = MatchRecord(
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            setScores: [],
            stats: []
        )
        XCTAssertNil(CompactScoreLine.inProgress(record))
    }
}
