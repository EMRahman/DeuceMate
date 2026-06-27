// StepsSeries.swift — single source of truth for the steps overlay series.
//
// Both the iOS Points Graph and the interactive HTML export render an optional
// steps overlay that can show either the cumulative running total or the steps
// taken per point. To avoid that domain logic diverging across surfaces, the
// derivation lives here and each surface only maps the result into its own
// rendering primitives.
//
// This is intentionally distinct from `MatchStatsSummary.stepsTimeline` /
// `sampledStepLoads`, which serve the coaching insights and text exporter:
// those are ordered chronologically, indexed over the sampled subset, carry the
// raw cumulative count, and have no match-total fallback. The overlay instead
// needs the original 0-based point index (for x-positioning), a base-normalized
// cumulative (so the line starts at 0), and the legacy `totalSteps` estimate.
// The per-point delta math (`max(0, cumulative − previous)`, first sample = 0)
// is the same in both by design.
import Foundation

/// One point in the canonical steps series. `pointIndex` is the 0-based index
/// into the match's point list. `cumulative` is normalized so the first recorded
/// sample reads 0 — steps logged before the first sample are unknowable and so
/// are excluded. `perPoint` is the delta from the previous point (the first
/// sample is 0 by definition).
public struct StepsSeriesPoint: Sendable, Equatable {
    public let pointIndex: Int
    public let cumulative: Int
    public let perPoint: Int

    public init(pointIndex: Int, cumulative: Int, perPoint: Int) {
        self.pointIndex = pointIndex
        self.cumulative = cumulative
        self.perPoint = perPoint
    }
}

public enum StepsSeries {
    /// Derives the steps series for a match.
    ///
    /// Prefers real per-point cumulative samples (`PointStat.stepsCumulative`)
    /// when at least two points carry data, normalizing to the first sample so
    /// the series starts at 0 even when step collection began mid-match. Legacy
    /// matches that only have a match-total (`MatchRecord.totalSteps`) fall back
    /// to a linear estimate spread evenly across the points. Returns an empty
    /// array when no step data is available.
    public static func make(stats: [PointStat], totalSteps: Int?) -> [StepsSeriesPoint] {
        let realSamples: [(index: Int, cumulative: Int)] = stats.enumerated().compactMap { i, s in
            guard let c = s.stepsCumulative else { return nil }
            return (i, c)
        }

        if realSamples.count >= 2 {
            let base = realSamples[0].cumulative
            var out: [StepsSeriesPoint] = []
            out.reserveCapacity(realSamples.count)
            var prev = 0
            for sample in realSamples {
                let cumulative = max(0, sample.cumulative - base)
                out.append(StepsSeriesPoint(pointIndex: sample.index,
                                            cumulative: cumulative,
                                            perPoint: max(0, cumulative - prev)))
                prev = cumulative
            }
            return out
        }

        if let total = totalSteps, total > 0, !stats.isEmpty {
            let n = stats.count
            var out: [StepsSeriesPoint] = []
            out.reserveCapacity(n)
            var prev = 0
            for i in 0..<n {
                let cumulative = Int(Double(i + 1) / Double(n) * Double(total))
                out.append(StepsSeriesPoint(pointIndex: i,
                                            cumulative: cumulative,
                                            perPoint: max(0, cumulative - prev)))
                prev = cumulative
            }
            return out
        }

        return []
    }
}
