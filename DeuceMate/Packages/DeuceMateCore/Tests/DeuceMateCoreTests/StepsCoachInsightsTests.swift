// StepsCoachInsightsTests.swift — exercises each rule in the steps-based
// movement/fatigue auto-insight engine. The engine operates on a pre-built
// step timeline, so tests construct StepPoints directly.
import XCTest
@testable import DeuceMateCore

final class StepsCoachInsightsTests: XCTestCase {

    private func stepPoint(
        _ index: Int,
        perPointSteps: Int,
        cumulative: Int,
        wonByFocal: Bool = true
    ) -> MatchStatsSummary.StepPoint {
        MatchStatsSummary.StepPoint(
            pointIndex: index,
            perPointSteps: perPointSteps,
            cumulative: cumulative,
            setIndex: 0,
            wonByFocal: wonByFocal
        )
    }

    func test_returnsEmptyWhenInsufficientPoints() {
        let timeline = (0..<5).map { stepPoint($0, perPointSteps: 20, cumulative: ($0 + 1) * 20) }
        XCTAssertTrue(StepsCoachInsights.generate(timeline: timeline).isEmpty)
    }

    func test_returnsEmptyWhenTimelineEmpty() {
        XCTAssertTrue(StepsCoachInsights.generate(timeline: []).isEmpty)
    }

    func test_emitsFatigueDeclineInsight() {
        // 20 points, +20 steps each. First half all won; second half mostly lost.
        var timeline: [MatchStatsSummary.StepPoint] = []
        for i in 0..<10 {
            timeline.append(stepPoint(i, perPointSteps: 20, cumulative: (i + 1) * 20, wonByFocal: true))
        }
        for i in 0..<10 {
            let won = i >= 8
            timeline.append(stepPoint(i + 10, perPointSteps: 20, cumulative: (i + 11) * 20, wonByFocal: won))
        }
        let insights = StepsCoachInsights.generate(timeline: timeline)
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
        var timeline: [MatchStatsSummary.StepPoint] = []
        var cumulative = 0
        for i in 0..<6 {
            cumulative += 5
            timeline.append(stepPoint(i, perPointSteps: 5, cumulative: cumulative, wonByFocal: true))
        }
        for i in 0..<6 {
            cumulative += 30
            timeline.append(stepPoint(i + 6, perPointSteps: 30, cumulative: cumulative, wonByFocal: false))
        }
        let insights = StepsCoachInsights.generate(timeline: timeline)
        XCTAssertTrue(
            insights.contains { $0.contains("high-movement points") },
            "Expected high-movement insight, got \(insights)"
        )
    }

    func test_bothRulesCanFireAndStayWithinCap() {
        // First half: low-movement wins. Second half: high-movement losses.
        var timeline: [MatchStatsSummary.StepPoint] = []
        var cumulative = 0
        for i in 0..<10 {
            cumulative += 5
            timeline.append(stepPoint(i, perPointSteps: 5, cumulative: cumulative, wonByFocal: true))
        }
        for i in 0..<10 {
            cumulative += 30
            timeline.append(stepPoint(i + 10, perPointSteps: 30, cumulative: cumulative, wonByFocal: false))
        }
        let insights = StepsCoachInsights.generate(timeline: timeline)
        XCTAssertLessThanOrEqual(insights.count, 3)
        XCTAssertTrue(insights.contains { $0.contains("Your win rate fell from") })
        XCTAssertTrue(insights.contains { $0.contains("high-movement points") })
    }
}
