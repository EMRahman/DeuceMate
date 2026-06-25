// StepsCoachInsightsTests.swift — exercises each rule in the steps-based
// movement/fatigue auto-insight engine.
import XCTest
@testable import DeuceMateCore

final class StepsCoachInsightsTests: XCTestCase {

    /// `steps` is the cumulative match-start total at this point (what the
    /// watch stores); the engine derives the per-point load from consecutive
    /// cumulative values.
    private func point(
        _ index: Int,
        steps: Int?,
        winner: Player
    ) -> PointStat {
        PointStat(
            timestamp: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + index * 30)),
            setIndex: 0,
            server: .me,
            winner: winner,
            outcome: .winner,
            isSecondServe: false,
            stepsCumulative: steps
        )
    }

    func test_returnsEmptyWhenInsufficientPoints() {
        let stats = (0..<5).map { point($0, steps: ($0 + 1) * 20, winner: .me) }
        XCTAssertTrue(StepsCoachInsights.generate(stats: stats, focal: .me).isEmpty)
    }

    func test_returnsEmptyWhenNoStepData() {
        let stats = (0..<15).map { point($0, steps: nil, winner: $0.isMultiple(of: 2) ? .me : .opponent) }
        XCTAssertTrue(StepsCoachInsights.generate(stats: stats, focal: .me).isEmpty)
    }

    func test_emitsFatigueDeclineInsight() {
        // 20 points, +20 steps each. First half all won; second half mostly lost.
        var stats: [PointStat] = []
        for i in 0..<10 { stats.append(point(i, steps: (i + 1) * 20, winner: .me)) }
        for i in 0..<10 {
            let winner: Player = i < 8 ? .opponent : .me
            stats.append(point(i + 10, steps: (i + 11) * 20, winner: winner))
        }
        let insights = StepsCoachInsights.generate(stats: stats, focal: .me)
        XCTAssertTrue(
            insights.contains { $0.contains("Your win rate fell from") && $0.contains("steps") },
            "Expected accumulated-step fatigue insight, got \(insights)"
        )
        // Steps covered by the midpoint = cumulative at point index 9 = 200.
        XCTAssertTrue(
            insights.contains { $0.contains("200 steps") },
            "Expected midpoint step burden of 200, got \(insights)"
        )
    }

    func test_emitsHighMovementInsight() {
        // 12 points: six low-movement (+5) won, six high-movement (+30) lost.
        var stats: [PointStat] = []
        var cumulative = 0
        for i in 0..<6 { cumulative += 5;  stats.append(point(i, steps: cumulative, winner: .me)) }
        for i in 0..<6 { cumulative += 30; stats.append(point(i + 6, steps: cumulative, winner: .opponent)) }
        let insights = StepsCoachInsights.generate(stats: stats, focal: .me)
        XCTAssertTrue(
            insights.contains { $0.contains("high-movement points") },
            "Expected high-movement insight, got \(insights)"
        )
    }

    func test_bothRulesCanFireAndStayWithinCap() {
        // First half: low-movement wins. Second half: high-movement losses.
        var stats: [PointStat] = []
        var cumulative = 0
        for i in 0..<10 { cumulative += 5;  stats.append(point(i, steps: cumulative, winner: .me)) }
        for i in 0..<10 { cumulative += 30; stats.append(point(i + 10, steps: cumulative, winner: .opponent)) }
        let insights = StepsCoachInsights.generate(stats: stats, focal: .me)
        XCTAssertLessThanOrEqual(insights.count, 3)
        XCTAssertTrue(insights.contains { $0.contains("Your win rate fell from") })
        XCTAssertTrue(insights.contains { $0.contains("high-movement points") })
    }
}
