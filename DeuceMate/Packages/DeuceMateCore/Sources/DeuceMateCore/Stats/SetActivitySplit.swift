// SetActivitySplit.swift — attributes a match's whole-match activity totals
// (Steps, Calories) to individual sets, so the stats page can show set-specific
// figures when filtered to a single set. Platform-neutral: no SwiftUI.
import Foundation

/// Splits a match's whole-match activity totals across its sets.
///
/// Steps are split using per-point `PointStat.stepsCumulative` samples when at
/// least two points carry them and every played set is represented. Calories
/// carry no per-point signal, so they — and the step fallback for legacy
/// matches — prorate the match total by each set's share of active-play time,
/// falling back to its share of recorded points when per-set durations are
/// unavailable.
public struct SetActivitySplit: Sendable {
    /// Steps attributed to each set index. Empty when no match step total exists.
    public let steps: [Int: Int]
    /// Kilocalories attributed to each set index. Empty when no match calorie total exists.
    public let calories: [Int: Double]

    public init(
        setCount: Int,
        stats: [PointStat],
        setElapsedSeconds: [Int: TimeInterval],
        totalSteps: Int?,
        totalCaloriesKcal: Double?
    ) {
        guard setCount > 0 else {
            steps = [:]
            calories = [:]
            return
        }
        let sets = Array(0..<setCount)

        // Proration weights: prefer each set's active-play seconds, fall back
        // to its share of recorded points.
        var weights: [Int: Double] = [:]
        let durationTotal = sets.reduce(0.0) { $0 + max(0, setElapsedSeconds[$1] ?? 0) }
        if durationTotal > 0 {
            for i in sets { weights[i] = max(0, setElapsedSeconds[i] ?? 0) }
        } else {
            for i in sets { weights[i] = Double(stats.filter { $0.setIndex == i }.count) }
        }
        let weightTotal = sets.reduce(0.0) { $0 + (weights[$1] ?? 0) }

        // Calories: prorate the match total by weight.
        if let kcal = totalCaloriesKcal, kcal > 0, weightTotal > 0 {
            var out: [Int: Double] = [:]
            for i in sets { out[i] = kcal * (weights[i] ?? 0) / weightTotal }
            calories = out
        } else {
            calories = [:]
        }

        // Steps: prefer per-point cumulative deltas, else prorate by weight.
        if let total = totalSteps, total > 0 {
            let fractions: [Int: Double]
            if let cumulative = Self.cumulativeStepFractions(setCount: setCount, stats: stats) {
                fractions = cumulative
            } else if weightTotal > 0 {
                var f: [Int: Double] = [:]
                for i in sets { f[i] = (weights[i] ?? 0) / weightTotal }
                fractions = f
            } else {
                fractions = [:]
            }
            if fractions.isEmpty {
                steps = [:]
            } else {
                var out: [Int: Int] = [:]
                for i in sets { out[i] = Int((Double(total) * (fractions[i] ?? 0)).rounded()) }
                steps = out
            }
        } else {
            steps = [:]
        }
    }

    /// Each set's fraction of total steps, derived from per-point
    /// `stepsCumulative` samples. Returns `nil` when fewer than two points
    /// carry samples, a played set has no sample, or the samples span no steps.
    private static func cumulativeStepFractions(
        setCount: Int,
        stats: [PointStat]
    ) -> [Int: Double]? {
        let sampled = stats
            .filter { $0.stepsCumulative != nil }
            .sorted { $0.timestamp < $1.timestamp }
        guard sampled.count >= 2 else { return nil }

        // A sampled-but-incomplete match would zero-out unsampled sets, so
        // require every played set to carry at least one sample.
        for i in 0..<setCount {
            let hasPoints = stats.contains { $0.setIndex == i }
            let hasSample = sampled.contains { $0.setIndex == i }
            if hasPoints && !hasSample { return nil }
        }

        // Last cumulative sample seen in each set (samples are timestamp-sorted).
        var endBySet: [Int: Int] = [:]
        for p in sampled {
            if let c = p.stepsCumulative { endBySet[p.setIndex] = c }
        }

        // Per-set delta, carrying the running total forward across sets with
        // no samples so deltas stay non-negative.
        var deltas: [Int: Double] = [:]
        var prevEnd = 0
        for i in 0..<setCount {
            let end = endBySet[i] ?? prevEnd
            deltas[i] = Double(max(0, end - prevEnd))
            prevEnd = max(prevEnd, end)
        }
        let totalDelta = deltas.values.reduce(0, +)
        guard totalDelta > 0 else { return nil }
        return deltas.mapValues { $0 / totalDelta }
    }
}
