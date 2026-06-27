// StepsSeriesTests.swift — shared steps overlay series derivation.
import XCTest
@testable import DeuceMateCore

final class StepsSeriesTests: XCTestCase {

    private func stat(_ steps: Int?) -> PointStat {
        PointStat(setIndex: 0, server: .me, winner: .me, outcome: .winner, stepsCumulative: steps)
    }

    // MARK: - Real per-point samples

    func test_realSamples_normalizeToBaseAndStartAtZero() {
        let stats = [stat(100), stat(180), stat(260)]
        let series = StepsSeries.make(stats: stats, totalSteps: nil)
        XCTAssertEqual(series.map(\.pointIndex), [0, 1, 2])
        // Normalized so the first sample reads 0.
        XCTAssertEqual(series.map(\.cumulative), [0, 80, 160])
        // First per-point is 0 by definition; the rest are deltas.
        XCTAssertEqual(series.map(\.perPoint), [0, 80, 80])
    }

    func test_realSamples_preserveSparseIndices() {
        // Only some points carry step data; the 0-based index must follow the
        // original point position, not the compacted sample position.
        let stats = [stat(nil), stat(200), stat(nil), stat(500)]
        let series = StepsSeries.make(stats: stats, totalSteps: 1000)
        XCTAssertEqual(series.map(\.pointIndex), [1, 3])
        XCTAssertEqual(series.map(\.cumulative), [0, 300])
        XCTAssertEqual(series.map(\.perPoint), [0, 300])
    }

    func test_realSamples_clampNonMonotonicToZero() {
        // A cumulative count that dips (shouldn't happen, but be defensive)
        // never produces a negative per-point value.
        let stats = [stat(100), stat(80)]
        let series = StepsSeries.make(stats: stats, totalSteps: nil)
        XCTAssertEqual(series.map(\.cumulative), [0, 0])
        XCTAssertEqual(series.map(\.perPoint), [0, 0])
    }

    // MARK: - Legacy totalSteps fallback

    func test_legacyTotalSteps_linearEstimateWhenFewerThanTwoSamples() {
        let stats = [stat(nil), stat(nil), stat(nil), stat(nil)]
        let series = StepsSeries.make(stats: stats, totalSteps: 400)
        XCTAssertEqual(series.map(\.pointIndex), [0, 1, 2, 3])
        XCTAssertEqual(series.map(\.cumulative), [100, 200, 300, 400])
        XCTAssertEqual(series.map(\.perPoint), [100, 100, 100, 100])
    }

    func test_singleRealSample_fallsBackToTotal() {
        // One sample isn't enough to derive deltas, so the total drives it.
        let stats = [stat(50), stat(nil)]
        let series = StepsSeries.make(stats: stats, totalSteps: 200)
        XCTAssertEqual(series.count, 2)
        XCTAssertEqual(series.last?.cumulative, 200)
    }

    // MARK: - Empty

    func test_noData_returnsEmpty() {
        XCTAssertTrue(StepsSeries.make(stats: [stat(nil), stat(nil)], totalSteps: nil).isEmpty)
        XCTAssertTrue(StepsSeries.make(stats: [], totalSteps: 500).isEmpty)
        XCTAssertTrue(StepsSeries.make(stats: [stat(nil)], totalSteps: 0).isEmpty)
    }
}
