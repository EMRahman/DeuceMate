// MatchStatsSummaryStepsTests.swift — verifies the per-point step (movement)
// derivations in MatchStatsSummary: the delta helper and the step timeline.
import XCTest
@testable import DeuceMateCore

final class MatchStatsSummaryStepsTests: XCTestCase {

    private func point(
        _ index: Int,
        steps: Int?,
        winner: Player = .me,
        setIndex: Int = 0
    ) -> PointStat {
        PointStat(
            timestamp: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + index * 30)),
            setIndex: setIndex,
            server: .me,
            winner: winner,
            outcome: .winner,
            isSecondServe: false,
            stepsCumulative: steps
        )
    }

    // MARK: - perPointStepDeltas

    func test_perPointStepDeltas_firstIsCumulativeThenDeltas() {
        let p = [point(0, steps: 10), point(1, steps: 30), point(2, steps: 60)]
        let deltas = MatchStatsSummary.perPointStepDeltas(p)
        XCTAssertEqual(deltas[p[0].id], 10)  // first sampled = its cumulative
        XCTAssertEqual(deltas[p[1].id], 20)
        XCTAssertEqual(deltas[p[2].id], 30)
    }

    func test_perPointStepDeltas_skipsNilAndCarriesPreviousForward() {
        let p = [point(0, steps: nil), point(1, steps: 10), point(2, steps: nil), point(3, steps: 25)]
        let deltas = MatchStatsSummary.perPointStepDeltas(p)
        XCTAssertNil(deltas[p[0].id])
        XCTAssertNil(deltas[p[2].id])
        XCTAssertEqual(deltas[p[1].id], 10)
        XCTAssertEqual(deltas[p[3].id], 15)  // 25 − 10, ignoring the nil gap
    }

    func test_perPointStepDeltas_clampsNegativeJitter() {
        let p = [point(0, steps: 50), point(1, steps: 40)]
        let deltas = MatchStatsSummary.perPointStepDeltas(p)
        XCTAssertEqual(deltas[p[0].id], 50)
        XCTAssertEqual(deltas[p[1].id], 0)   // never negative
    }

    func test_perPointStepDeltas_sortsByTimestampBeforeDiffing() {
        // Supplied out of chronological order; deltas must still follow time.
        // p[1] is earliest (steps 10), p[2] next (30), p[0] latest (60).
        let p = [point(2, steps: 60), point(0, steps: 10), point(1, steps: 30)]
        let deltas = MatchStatsSummary.perPointStepDeltas(p)
        XCTAssertEqual(deltas[p[1].id], 10)  // earliest sampled = its cumulative
        XCTAssertEqual(deltas[p[2].id], 20)
        XCTAssertEqual(deltas[p[0].id], 30)  // latest
    }

    // MARK: - stepsTimeline / stepsInsights

    func test_noStepData_yieldsEmptyTimelineAndInsights() {
        let stats = (0..<5).map { point($0, steps: nil) }
        let s = MatchStatsSummary(stats: stats, focal: .me)
        XCTAssertTrue(s.stepsTimeline.isEmpty)
        XCTAssertTrue(s.stepsInsights.isEmpty)
    }

    func test_stepsTimeline_orderedDenselyIndexedAndCarriesFields() {
        let stats = [
            point(0, steps: 10, winner: .me, setIndex: 0),
            point(1, steps: nil),                              // skipped
            point(2, steps: 35, winner: .opponent, setIndex: 1)
        ]
        let s = MatchStatsSummary(stats: stats, focal: .me)
        XCTAssertEqual(s.stepsTimeline.count, 2)
        XCTAssertEqual(s.stepsTimeline.map(\.pointIndex), [0, 1])
        XCTAssertEqual(s.stepsTimeline.map(\.perPointSteps), [10, 25])
        XCTAssertEqual(s.stepsTimeline.map(\.cumulative), [10, 35])
        XCTAssertEqual(s.stepsTimeline.map(\.setIndex), [0, 1])
        XCTAssertEqual(s.stepsTimeline.map(\.wonByFocal), [true, false])
    }
}
