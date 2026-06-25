// StepsCoachInsights.swift — deterministic rule engine that converts a
// per-point step (movement) timeline into ≤3 short, fatigue-oriented coaching
// observations. Mirrors PulseCoachInsights, which does the same for heart rate.
//
// Operates on a pre-built `[MatchStatsSummary.StepPoint]` timeline (already
// filtered to sampled points, chronologically ordered, and carrying each
// point's `wonByFocal` flag) so the engine stays decoupled from the raw models
// and does no sorting/filtering of its own.
import Foundation

public enum StepsCoachInsights {

    /// Returns up to three short coaching sentences derived from a per-point
    /// step timeline. Always returns an empty array when there is insufficient
    /// data so callers can safely treat empty as "hide the section."
    public static func generate(
        timeline: [MatchStatsSummary.StepPoint]
    ) -> [String] {
        guard timeline.count >= 10 else { return [] }

        var insights: [String] = []
        if let fatigue = fatigueDeclineInsight(timeline: timeline) {
            insights.append(fatigue)
        }
        if let movement = highMovementInsight(timeline: timeline) {
            insights.append(movement)
        }
        return Array(insights.prefix(3))
    }

    // MARK: - Rule 1: accumulated-step fatigue (late-match decline)

    /// Splits the match in half chronologically; if the focal player's win rate
    /// drops by ≥15 points from first to second half, ties that decline to the
    /// step burden already accumulated by the midpoint.
    private static func fatigueDeclineInsight(
        timeline: [MatchStatsSummary.StepPoint]
    ) -> String? {
        guard timeline.count >= 20 else { return nil }
        let half = timeline.count / 2
        let firstHalf = Array(timeline.prefix(half))
        let secondHalf = Array(timeline.suffix(timeline.count - half))
        let firstWinRate = winRate(firstHalf)
        let secondWinRate = winRate(secondHalf)
        guard firstWinRate - secondWinRate >= 0.15 else { return nil }
        // Cumulative steps already covered by the midpoint — the load the
        // player was carrying as the decline set in. Fall back to summing the
        // first-half deltas if the midpoint sample is somehow missing.
        let coveredByMidpoint = firstHalf.last?.cumulative
            ?? firstHalf.reduce(0) { $0 + $1.perPointSteps }
        let firstPct = Int((firstWinRate * 100).rounded())
        let secondPct = Int((secondWinRate * 100).rounded())
        return "Your win rate fell from \(firstPct)% to \(secondPct)% in the second half, " +
               "after you'd already covered about \(coveredByMidpoint) steps."
    }

    // MARK: - Rule 2: high-movement points

    /// Compares win rate on the points where you ran the most (per-point steps
    /// above the median) against the points where you ran less.
    private static func highMovementInsight(
        timeline: [MatchStatsSummary.StepPoint]
    ) -> String? {
        let med = median(timeline.map(\.perPointSteps))
        guard med > 0 else { return nil }
        let high = timeline.filter { $0.perPointSteps > med }
        let low = timeline.filter { $0.perPointSteps <= med }
        guard high.count >= 3, low.count >= 3 else { return nil }
        let highRate = winRate(high)
        let lowRate = winRate(low)
        guard lowRate - highRate >= 0.15 else { return nil }
        let highPct = Int((highRate * 100).rounded())
        let lowPct = Int((lowRate * 100).rounded())
        return "You won only \(highPct)% of high-movement points (over \(med) steps) " +
               "versus \(lowPct)% when you moved less."
    }

    // MARK: - Helpers

    private static func winRate(_ points: [MatchStatsSummary.StepPoint]) -> Double {
        guard !points.isEmpty else { return 0 }
        let wins = points.filter { $0.wonByFocal }.count
        return Double(wins) / Double(points.count)
    }

    private static func median(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
