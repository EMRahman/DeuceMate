// MatchRecordFormattingTests.swift — pure display helpers on MatchRecord.
//
// gameScoreString carries the only non-trivial logic (deuce/advantage handling
// and the raw fallback for tiebreak-style high counts); the distance/calorie
// formatters are framework-backed, so they're asserted only for not-crashing /
// non-empty output to stay locale-independent.
import XCTest
@testable import DeuceMateCore

final class MatchRecordFormattingTests: XCTestCase {

    // Note: the source uses an en dash (U+2013) between the two scores.
    private let dash = "\u{2013}"

    // MARK: - gameScoreString

    func test_gameScore_zeroZero_isNil() {
        XCTAssertNil(MatchRecord.gameScoreString(mePoints: 0, oppPoints: 0))
    }

    func test_gameScore_basicLabels() {
        XCTAssertEqual(MatchRecord.gameScoreString(mePoints: 1, oppPoints: 0), "15\(dash)0")
        XCTAssertEqual(MatchRecord.gameScoreString(mePoints: 2, oppPoints: 1), "30\(dash)15")
        XCTAssertEqual(MatchRecord.gameScoreString(mePoints: 3, oppPoints: 0), "40\(dash)0")
        XCTAssertEqual(MatchRecord.gameScoreString(mePoints: 0, oppPoints: 2), "0\(dash)30")
    }

    func test_gameScore_deuceAndAdvantage() {
        XCTAssertEqual(MatchRecord.gameScoreString(mePoints: 3, oppPoints: 3), "Deuce")
        XCTAssertEqual(MatchRecord.gameScoreString(mePoints: 4, oppPoints: 4), "Deuce")
        XCTAssertEqual(MatchRecord.gameScoreString(mePoints: 4, oppPoints: 3), "AD\(dash)40")
        XCTAssertEqual(MatchRecord.gameScoreString(mePoints: 3, oppPoints: 4), "40\(dash)AD")
    }

    func test_gameScore_highCountsFallBackToRawNumbers() {
        // Beyond the 0/15/30/40 ladder (e.g. tiebreak point counts) the raw
        // number is shown. Only reachable when one side is below 3 (otherwise
        // the deuce/advantage branch handles it).
        XCTAssertEqual(MatchRecord.gameScoreString(mePoints: 5, oppPoints: 0), "5\(dash)0")
        XCTAssertEqual(MatchRecord.gameScoreString(mePoints: 0, oppPoints: 7), "0\(dash)7")
    }

    // MARK: - Activity formatters (locale-independent smoke checks)

    func test_formattedDistance_nonEmpty() {
        XCTAssertFalse(MatchRecord.formattedDistance(1500).isEmpty)
        XCTAssertFalse(MatchRecord.formattedDistance(0).isEmpty)
    }

    func test_formattedCalories_nonEmpty() {
        XCTAssertFalse(MatchRecord.formattedCalories(312).isEmpty)
        XCTAssertFalse(MatchRecord.formattedCalories(0).isEmpty)
    }

    // MARK: - isInProgress

    func test_isInProgress() {
        let base = MatchRecord(startTime: Date(timeIntervalSince1970: 1_700_000_000),
                               setScores: [], stats: [])

        // No result, no end time → live.
        XCTAssertTrue(base.isInProgress)

        // Completed match.
        var won = base
        won.iWon = true
        XCTAssertFalse(won.isInProgress)

        // Draw: no winner but a recorded end time.
        var draw = base
        draw.endTime = Date(timeIntervalSince1970: 1_700_003_600)
        XCTAssertFalse(draw.isInProgress)
    }
}
