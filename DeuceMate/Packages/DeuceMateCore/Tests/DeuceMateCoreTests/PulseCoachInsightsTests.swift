// PulseCoachInsightsTests.swift — exercises each rule in the Pulse Coach
// auto-insight engine.
import XCTest
@testable import DeuceMateCore

final class PulseCoachInsightsTests: XCTestCase {

    private func point(
        _ index: Int,
        bpm: Int?,
        winner: Player,
        isBreakPoint: Bool = false
    ) -> PointStat {
        PointStat(
            timestamp: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + index * 30)),
            setIndex: 0,
            server: .me,
            winner: winner,
            outcome: .winner,
            isSecondServe: false,
            isBreakPoint: isBreakPoint,
            heartRateBPM: bpm
        )
    }

    func test_returnsEmptyWhenInsufficientData() {
        let stats = (0..<5).map { point($0, bpm: 130, winner: .me) }
        let insights = PulseCoachInsights.generate(stats: stats, focal: .me, maxHR: 190)
        XCTAssertTrue(insights.isEmpty)
    }

    func test_emitsZoneDeltaInsight() {
        // 6 wins in Z2, 5 losses in Z5 — clear delta.
        var stats: [PointStat] = []
        for i in 0..<6 { stats.append(point(i, bpm: 130, winner: .me))      } // Z2 wins (130/190 ≈ 68%)
        for i in 0..<5 { stats.append(point(i + 6, bpm: 175, winner: .opponent)) } // Z5 losses (175/190 ≈ 92%)
        let insights = PulseCoachInsights.generate(stats: stats, focal: .me, maxHR: 190)
        XCTAssertFalse(insights.isEmpty)
        XCTAssertTrue(insights.contains { $0.contains("Z2") && $0.contains("Z5") },
                      "Expected zone-delta insight, got \(insights)")
    }

    func test_emitsBreakPointInsightWhenLossesAboveMedian() {
        // 4 break points: 2 below median both won, 2 above median both lost.
        var stats: [PointStat] = []
        // Filler points so total ≥ 10
        for i in 0..<8 { stats.append(point(i, bpm: 130 + (i % 3), winner: .me)) }
        // Break points
        stats.append(point(8, bpm: 130, winner: .me, isBreakPoint: true))
        stats.append(point(9, bpm: 132, winner: .me, isBreakPoint: true))
        stats.append(point(10, bpm: 170, winner: .opponent, isBreakPoint: true))
        stats.append(point(11, bpm: 175, winner: .opponent, isBreakPoint: true))
        stats.append(point(12, bpm: 178, winner: .opponent, isBreakPoint: true))
        let insights = PulseCoachInsights.generate(stats: stats, focal: .me, maxHR: 190)
        XCTAssertTrue(
            insights.contains { $0.contains("break points") },
            "Expected break-point insight, got \(insights)"
        )
    }

    func test_emitsLateMatchDeclineInsight() {
        // First half: 10 wins at low HR. Second half: 10 mostly losses at high HR.
        var stats: [PointStat] = []
        for i in 0..<10 { stats.append(point(i, bpm: 120, winner: .me)) }
        for i in 0..<10 {
            let winner: Player = i < 8 ? .opponent : .me
            stats.append(point(i + 10, bpm: 160, winner: winner))
        }
        let insights = PulseCoachInsights.generate(stats: stats, focal: .me, maxHR: 190)
        XCTAssertTrue(
            insights.contains { $0.contains("Win rate dropped") },
            "Expected late-match decline insight, got \(insights)"
        )
    }

    func test_capsAtThreeInsights() {
        // Trigger all three rules simultaneously.
        var stats: [PointStat] = []
        for i in 0..<8 { stats.append(point(i, bpm: 120, winner: .me)) }            // first half wins, low HR
        for i in 0..<8 { stats.append(point(i + 8, bpm: 175, winner: .opponent)) }  // second half losses, high HR
        // Add break points above median
        stats.append(point(16, bpm: 178, winner: .opponent, isBreakPoint: true))
        stats.append(point(17, bpm: 180, winner: .opponent, isBreakPoint: true))
        stats.append(point(18, bpm: 182, winner: .opponent, isBreakPoint: true))
        stats.append(point(19, bpm: 130, winner: .me,       isBreakPoint: true))
        let insights = PulseCoachInsights.generate(stats: stats, focal: .me, maxHR: 190)
        XCTAssertLessThanOrEqual(insights.count, 3)
    }
}
