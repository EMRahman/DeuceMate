// MatchComparisonFormatTests.swift — wording for the comparison screen and the
// head-to-head line (MATCH_TAGS_PLAN.md §7.1).
import XCTest
@testable import DeuceMateCore

final class MatchComparisonFormatTests: XCTestCase {

    func test_ratio_showsPercentWithNumeratorAndDenominator() {
        XCTAssertEqual(MatchComparisonFormat.ratio(.init(numerator: 12, denominator: 20)), "60% — 12/20")
        XCTAssertEqual(MatchComparisonFormat.ratio(.init(numerator: 1, denominator: 3)), "33% — 1/3")
    }

    func test_ratio_missingOrZeroDenominator_isNotRecordedNeverZero() {
        XCTAssertEqual(MatchComparisonFormat.ratio(nil), "Not recorded")
        XCTAssertEqual(MatchComparisonFormat.ratio(.init(numerator: 0, denominator: 0)), "Not recorded")
        XCTAssertEqual(MatchComparisonFormat.ratio(.init(numerator: 0, denominator: 5)), "0% — 0/5")
    }

    func test_change_isSignedPercentagePoints() {
        XCTAssertEqual(MatchComparisonFormat.change(5.4), "+5 pts")
        XCTAssertEqual(MatchComparisonFormat.change(-3.6), "\u{2212}4 pts")
        XCTAssertEqual(MatchComparisonFormat.change(0.2), "\u{00B1}0 pts")
        XCTAssertNil(MatchComparisonFormat.change(nil))
    }

    func test_duration_formatsMinutesAndHours() {
        XCTAssertEqual(MatchComparisonFormat.duration(48 * 60 + 30), "48 min")
        XCTAssertEqual(MatchComparisonFormat.duration(65 * 60), "1 h 05 min")
        XCTAssertEqual(MatchComparisonFormat.duration(25), "< 1 min")
        XCTAssertEqual(MatchComparisonFormat.duration(nil), "Not recorded")
        XCTAssertEqual(MatchComparisonFormat.duration(0), "Not recorded")
    }

    func test_headToHead_summarisesTallyAndForm() {
        let record = HeadToHeadRecord(wins: 3, losses: 2, draws: 0,
                                      recentResults: [.win, .win, .loss, .win, .loss],
                                      lastPlayed: Date())
        XCTAssertEqual(MatchComparisonFormat.headToHeadSummary(record, recentCount: 3),
                       "3\u{2013}2 in 5 matches · last 3: W W L")
    }

    func test_headToHead_showsDrawsOnlyWhenPresent_andSingular() {
        let one = HeadToHeadRecord(wins: 0, losses: 0, draws: 1, recentResults: [.draw], lastPlayed: Date())
        XCTAssertEqual(MatchComparisonFormat.headToHeadSummary(one), "0\u{2013}0\u{2013}1 in 1 match · last 1: D")
        XCTAssertEqual(MatchComparisonFormat.headToHeadSummary(.empty), "No completed matches yet")
    }

    func test_resultAndCoverage_neverInferAResultForAPartialSide() {
        let current = MatchRecord(
            startTime: Date(timeIntervalSince1970: 2_000), endTime: nil,
            setScores: [SetScore(gamesMe: 3, gamesOpponent: 1)], stats: [], iWon: nil
        )
        let baseline = MatchRecord(
            startTime: Date(timeIntervalSince1970: 1_000), endTime: Date(timeIntervalSince1970: 1_500),
            setScores: [SetScore(gamesMe: 6, gamesOpponent: 4)], stats: [], iWon: true
        )
        let comparison = MatchComparison(current: current, baseline: baseline)
        XCTAssertEqual(MatchComparisonFormat.result(comparison.current), "In progress")
        XCTAssertEqual(MatchComparisonFormat.result(comparison.baseline), "Won")
        XCTAssertEqual(MatchComparisonFormat.coverage(comparison.current), "Score only")
    }
}
