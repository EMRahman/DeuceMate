// MatchDurationsTests.swift — set/match duration resolution and the minute
// strings, including the recorded-value-wins-over-point-span fallback rule.
import XCTest
@testable import DeuceMateCore

final class MatchDurationsTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func point(set: Int, at offset: TimeInterval) -> PointStat {
        PointStat(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000 + offset),
            setIndex: set,
            server: .me,
            winner: .me,
            outcome: .uncategorized
        )
    }

    private func record(
        stats: [PointStat] = [],
        setCount: Int = 1,
        setElapsed: [Int: TimeInterval] = [:],
        matchElapsed: TimeInterval = 0,
        end: Date? = nil
    ) -> MatchRecord {
        MatchRecord(
            startTime: start,
            endTime: end,
            setScores: Array(repeating: SetScore(), count: setCount),
            stats: stats,
            matchElapsedSeconds: matchElapsed,
            setElapsedSeconds: setElapsed
        )
    }

    // MARK: - Set duration

    func test_setDuration_prefersRecordedValue() {
        let secs = MatchDurations.setElapsedSeconds(
            setIndex: 0,
            stats: [point(set: 0, at: 0), point(set: 0, at: 3600)],
            stored: [0: 1200]
        )
        XCTAssertEqual(secs, 1200)
    }

    func test_setDuration_fallsBackToPointSpanOfThatSetOnly() {
        let stats = [
            point(set: 0, at: 0),
            point(set: 0, at: 600),
            point(set: 1, at: 700),
            point(set: 1, at: 1000)
        ]
        XCTAssertEqual(MatchDurations.setElapsedSeconds(setIndex: 0, stats: stats, stored: [:]), 600)
        XCTAssertEqual(MatchDurations.setElapsedSeconds(setIndex: 1, stats: stats, stored: [:]), 300)
    }

    func test_setDuration_isNilWithoutRecordedValueOrPoints() {
        XCTAssertNil(MatchDurations.setElapsedSeconds(setIndex: 2, stats: [point(set: 0, at: 0)], stored: [:]))
    }

    func test_setDuration_recordOverload_matchesComponentOverload() {
        let rec = record(stats: [point(set: 0, at: 0), point(set: 0, at: 480)], setElapsed: [:])
        XCTAssertEqual(MatchDurations.setElapsedSeconds(rec, setIndex: 0), 480)
        XCTAssertNil(MatchDurations.setElapsedSeconds(rec, setIndex: 1))
    }

    // MARK: - Match duration

    func test_matchDuration_prefersRecordedElapsed() {
        let rec = record(matchElapsed: 5400, end: start.addingTimeInterval(60))
        XCTAssertEqual(MatchDurations.matchElapsedSeconds(rec), 5400)
    }

    func test_matchDuration_fallsBackToStartEndSpan() {
        let rec = record(end: start.addingTimeInterval(3600))
        XCTAssertEqual(MatchDurations.matchElapsedSeconds(rec), 3600)
    }

    func test_matchDuration_isNilWhileInProgress() {
        XCTAssertNil(MatchDurations.matchElapsedSeconds(record()))
    }

    // MARK: - Strings

    func test_minutesString_truncatesAndTakesUnit() {
        XCTAssertEqual(MatchDurations.minutesString(3599), "59 min")
        XCTAssertEqual(MatchDurations.minutesString(3599, unit: "m"), "59 m")
        XCTAssertEqual(MatchDurations.minutesString(0), "0 min")
    }

    func test_minutesSecondsString_splitsAndClampsNegatives() {
        XCTAssertEqual(MatchDurations.minutesSecondsString(187), "3 m 7 s")
        XCTAssertEqual(MatchDurations.minutesSecondsString(-5), "0 m 0 s")
    }
}
