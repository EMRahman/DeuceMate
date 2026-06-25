// StepsCoachInsights.swift — deterministic rule engine that converts per-point
// step (movement) data into ≤3 short, fatigue-oriented coaching observations.
// Mirrors PulseCoachInsights, which does the same for heart rate.
import Foundation

public enum StepsCoachInsights {

    /// Returns up to three short coaching sentences derived from per-point
    /// cumulative step data. Always returns an empty array when there is
    /// insufficient data so callers can safely treat empty as "hide the
    /// section."
    public static func generate(
        stats: [PointStat],
        focal: Player
    ) -> [String] {
        // Per-point movement load (steps taken during each point), paired with
        // its point and timestamp-sorted so "first/second half" is chronological.
        let deltas = MatchStatsSummary.perPointStepDeltas(stats)
        let moved = stats
            .filter { deltas[$0.id] != nil }
            .sorted { $0.timestamp < $1.timestamp }
            .map { (pt: $0, steps: deltas[$0.id] ?? 0) }
        guard moved.count >= 10 else { return [] }

        var insights: [String] = []
        if let fatigue = fatigueDeclineInsight(moved: moved, focal: focal) {
            insights.append(fatigue)
        }
        if let movement = highMovementInsight(moved: moved, focal: focal) {
            insights.append(movement)
        }
        return Array(insights.prefix(3))
    }

    // MARK: - Rule 1: accumulated-step fatigue (late-match decline)

    /// Splits the match in half chronologically; if the focal player's win rate
    /// drops by ≥15 points from first to second half, ties that decline to the
    /// step burden already accumulated by the midpoint.
    private static func fatigueDeclineInsight(
        moved: [(pt: PointStat, steps: Int)],
        focal: Player
    ) -> String? {
        guard moved.count >= 20 else { return nil }
        let half = moved.count / 2
        let firstHalf = Array(moved.prefix(half))
        let secondHalf = Array(moved.suffix(moved.count - half))
        let firstWinRate = winRate(firstHalf.map(\.pt), focal: focal)
        let secondWinRate = winRate(secondHalf.map(\.pt), focal: focal)
        guard firstWinRate - secondWinRate >= 0.15 else { return nil }
        // Cumulative steps already covered by the midpoint — the load the
        // player was carrying as the decline set in. Fall back to summing the
        // first-half deltas if the midpoint sample lacks a cumulative value.
        let coveredByMidpoint = firstHalf.last?.pt.stepsCumulative
            ?? firstHalf.reduce(0) { $0 + $1.steps }
        let firstPct = Int((firstWinRate * 100).rounded())
        let secondPct = Int((secondWinRate * 100).rounded())
        return "Your win rate fell from \(firstPct)% to \(secondPct)% in the second half, " +
               "after you'd already covered about \(coveredByMidpoint) steps."
    }

    // MARK: - Rule 2: high-movement points

    /// Compares win rate on the points where you ran the most (per-point steps
    /// above the median) against the points where you ran less.
    private static func highMovementInsight(
        moved: [(pt: PointStat, steps: Int)],
        focal: Player
    ) -> String? {
        let med = median(moved.map(\.steps))
        guard med > 0 else { return nil }
        let high = moved.filter { $0.steps > med }
        let low = moved.filter { $0.steps <= med }
        guard high.count >= 3, low.count >= 3 else { return nil }
        let highRate = winRate(high.map(\.pt), focal: focal)
        let lowRate = winRate(low.map(\.pt), focal: focal)
        guard lowRate - highRate >= 0.15 else { return nil }
        let highPct = Int((highRate * 100).rounded())
        let lowPct = Int((lowRate * 100).rounded())
        return "You won only \(highPct)% of high-movement points (over \(med) steps) " +
               "versus \(lowPct)% when you moved less."
    }

    // MARK: - Helpers

    private static func winRate(_ points: [PointStat], focal: Player) -> Double {
        guard !points.isEmpty else { return 0 }
        let wins = points.filter { $0.winner == focal }.count
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
