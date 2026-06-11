// MatchStatsSummaryHRTests.swift — verifies that the heart-rate aggregations
// in MatchStatsSummary correctly partition points by zone and build a timeline.
import XCTest
@testable import DeuceMateCore

final class MatchStatsSummaryHRTests: XCTestCase {

    // MARK: - Helpers

    private func point(
        _ index: Int,
        bpm: Int?,
        winner: Player = .me,
        setIndex: Int = 0,
        outcome: PointOutcome = .winner,
        isBreakPoint: Bool = false
    ) -> PointStat {
        PointStat(
            timestamp: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + index * 30)),
            setIndex: setIndex,
            server: .me,
            winner: winner,
            outcome: outcome,
            isSecondServe: false,
            isBreakPoint: isBreakPoint,
            heartRateBPM: bpm
        )
    }

    // MARK: - Tests

    func test_noHRData_yieldsEmptyAggregations() {
        let stats = (0..<5).map { point($0, bpm: nil) }
        let s = MatchStatsSummary(stats: stats, focal: .me, maxHR: 190)
        XCTAssertTrue(s.zoneWinRates.isEmpty)
        XCTAssertTrue(s.hrTimeline.isEmpty)
        XCTAssertTrue(s.autoInsights.isEmpty)
    }

    func test_zoneWinRates_partitionsByZone() {
        // maxHR 200 → Z1<120, Z2 120-139, Z3 140-159, Z4 160-179, Z5 ≥180
        let stats: [PointStat] = [
            point(0, bpm: 110, winner: .me),       // Z1 win
            point(1, bpm: 115, winner: .opponent), // Z1 loss
            point(2, bpm: 130, winner: .me),       // Z2 win
            point(3, bpm: 130, winner: .me),       // Z2 win
            point(4, bpm: 165, winner: .opponent), // Z4 loss
            point(5, bpm: 185, winner: .opponent)  // Z5 loss
        ]
        let s = MatchStatsSummary(stats: stats, focal: .me, maxHR: 200)
        let byZone = Dictionary(uniqueKeysWithValues: s.zoneWinRates.map { ($0.zone, $0) })
        XCTAssertEqual(byZone[.z1]?.total, 2)
        XCTAssertEqual(byZone[.z1]?.wins, 1)
        XCTAssertEqual(byZone[.z2]?.total, 2)
        XCTAssertEqual(byZone[.z2]?.wins, 2)
        XCTAssertNil(byZone[.z3])
        XCTAssertEqual(byZone[.z4]?.total, 1)
        XCTAssertEqual(byZone[.z4]?.wins, 0)
        XCTAssertEqual(byZone[.z5]?.total, 1)
        XCTAssertEqual(byZone[.z5]?.wins, 0)
    }

    func test_hrTimeline_isOrderedAndDenselyIndexed() {
        let stats: [PointStat] = [
            point(0, bpm: 120),
            point(1, bpm: nil),  // skipped
            point(2, bpm: 130),
            point(3, bpm: 140)
        ]
        let s = MatchStatsSummary(stats: stats, focal: .me, maxHR: 190)
        XCTAssertEqual(s.hrTimeline.count, 3)
        XCTAssertEqual(s.hrTimeline.map(\.pointIndex), [0, 1, 2])
        XCTAssertEqual(s.hrTimeline.map(\.bpm), [120, 130, 140])
    }

    func test_resolvedMaxHR_storedOnSummary() {
        let stats = [point(0, bpm: 130)]
        let s = MatchStatsSummary(stats: stats, focal: .me, maxHR: 175)
        XCTAssertEqual(s.resolvedMaxHR, 175)
    }
}
