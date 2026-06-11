// SetActivitySplitTests.swift — per-set attribution of Steps and Calories.
import XCTest
@testable import DeuceMateCore

final class SetActivitySplitTests: XCTestCase {

    private func point(set: Int, at offset: TimeInterval, steps: Int?) -> PointStat {
        PointStat(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000 + offset),
            setIndex: set,
            server: .me,
            winner: .me,
            outcome: .uncategorized,
            isSecondServe: false,
            stepsCumulative: steps
        )
    }

    func test_steps_splitByCumulativeSamples() {
        let stats = [
            point(set: 0, at: 0,   steps: 40),
            point(set: 0, at: 60,  steps: 100),
            point(set: 1, at: 120, steps: 180),
            point(set: 1, at: 180, steps: 250)
        ]
        let split = SetActivitySplit(
            setCount: 2,
            stats: stats,
            setElapsedSeconds: [0: 600, 1: 1800],
            totalSteps: 300,
            totalCaloriesKcal: nil
        )
        // Set 0 ends at 100, set 1 ends at 250 → fractions 0.4 / 0.6.
        XCTAssertEqual(split.steps[0], 120)
        XCTAssertEqual(split.steps[1], 180)
        XCTAssertEqual((split.steps[0] ?? 0) + (split.steps[1] ?? 0), 300)
    }

    func test_calories_proratedByDuration() {
        let stats = [
            point(set: 0, at: 0,   steps: nil),
            point(set: 1, at: 120, steps: nil)
        ]
        let split = SetActivitySplit(
            setCount: 2,
            stats: stats,
            setElapsedSeconds: [0: 600, 1: 1800],
            totalSteps: nil,
            totalCaloriesKcal: 400
        )
        XCTAssertEqual(split.calories[0] ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(split.calories[1] ?? 0, 300, accuracy: 0.001)
    }

    func test_steps_fallBackToDurationWhenNoCumulative() {
        let stats = [
            point(set: 0, at: 0,   steps: nil),
            point(set: 1, at: 120, steps: nil)
        ]
        let split = SetActivitySplit(
            setCount: 2,
            stats: stats,
            setElapsedSeconds: [0: 600, 1: 1800],
            totalSteps: 300,
            totalCaloriesKcal: nil
        )
        XCTAssertEqual(split.steps[0], 75)
        XCTAssertEqual(split.steps[1], 225)
    }

    func test_steps_fallBackToPointCountWhenNoDurations() {
        let stats = [
            point(set: 0, at: 0,   steps: nil),
            point(set: 1, at: 60,  steps: nil),
            point(set: 1, at: 120, steps: nil),
            point(set: 1, at: 180, steps: nil)
        ]
        let split = SetActivitySplit(
            setCount: 2,
            stats: stats,
            setElapsedSeconds: [:],
            totalSteps: 400,
            totalCaloriesKcal: 400
        )
        // 1 point in set 0, 3 in set 1 → 1/4 and 3/4.
        XCTAssertEqual(split.steps[0], 100)
        XCTAssertEqual(split.steps[1], 300)
        XCTAssertEqual(split.calories[0] ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(split.calories[1] ?? 0, 300, accuracy: 0.001)
    }

    func test_partiallySampledMatch_fallsBackToProration() {
        // Set 1 has points but no step samples — cumulative split must not
        // zero it out; the duration fallback applies instead.
        let stats = [
            point(set: 0, at: 0,   steps: 40),
            point(set: 0, at: 60,  steps: 100),
            point(set: 1, at: 120, steps: nil),
            point(set: 1, at: 180, steps: nil)
        ]
        let split = SetActivitySplit(
            setCount: 2,
            stats: stats,
            setElapsedSeconds: [0: 600, 1: 1800],
            totalSteps: 300,
            totalCaloriesKcal: nil
        )
        XCTAssertEqual(split.steps[0], 75)
        XCTAssertEqual(split.steps[1], 225)
    }

    func test_emptyWhenNoTotals() {
        let stats = [point(set: 0, at: 0, steps: nil)]
        let split = SetActivitySplit(
            setCount: 1,
            stats: stats,
            setElapsedSeconds: [0: 600],
            totalSteps: nil,
            totalCaloriesKcal: nil
        )
        XCTAssertTrue(split.steps.isEmpty)
        XCTAssertTrue(split.calories.isEmpty)
    }
}
