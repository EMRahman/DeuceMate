// PerformanceTrends.swift — windowing, filtering, pooling and deltas across a
// whole archive of matches. Platform-neutral: no SwiftUI. See
// docs/features/PERFORMANCE_TRENDS_PLAN.md §3 and §5.3.
import Foundation

/// How many recent matches to include. Modelled on `SetFilter`
/// (Stats/SetFilter.swift).
public enum TrendWindow: Hashable, Sendable {
    case last(Int)
    case all

    public var label: String {
        switch self {
        case .all: return "All"
        case .last(let n): return "Last \(n)"
        }
    }

    /// The window picker's contents (§6.2).
    public static let presets: [TrendWindow] = [.last(5), .last(10), .last(20), .all]
}

/// Which matches are in scope, independent of the window. `nil` on
/// `matchType`/`matchFormat` means "all" for that axis.
public struct TrendFilter: Hashable, Sendable {
    public var matchType: MatchType?
    public var matchFormat: MatchFormat?
    /// Whether an in-progress match's sample is in scope. `false` by
    /// default — completed matches only, the feature's default posture
    /// everywhere (owner request). `MatchTrendSample.isInProgress` is the
    /// field this checks.
    public var includeInProgress: Bool

    public init(matchType: MatchType? = nil, matchFormat: MatchFormat? = nil,
                includeInProgress: Bool = false) {
        self.matchType = matchType
        self.matchFormat = matchFormat
        self.includeInProgress = includeInProgress
    }

    /// Every match type and format, completed only — the default posture,
    /// not an unconditional "everything." Pass `includeInProgress: true`
    /// explicitly to also see in-progress matches.
    public static let all = TrendFilter()

    public func includes(_ sample: MatchTrendSample) -> Bool {
        if !includeInProgress && sample.isInProgress { return false }
        if let matchType, sample.matchType != matchType { return false }
        if let matchFormat, sample.matchFormat != matchFormat { return false }
        return true
    }
}

/// One match's plottable dot for one metric. `index` is the sample's ordinal
/// position within the scoped series (oldest == 0) — NOT the array index
/// within `points`, so a coverage gap (a match with no dot for this metric)
/// leaves a real gap on the X axis rather than compressing it away (§6.3).
public struct TrendPoint: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let index: Int
    public let date: Date
    public let ratio: TrendMetric.Ratio
    public var value: Double { ratio.value }

    public init(id: UUID, index: Int, date: Date, ratio: TrendMetric.Ratio) {
        self.id = id
        self.index = index
        self.date = date
        self.ratio = ratio
    }
}

/// The recent-vs-prior comparison shown as the headline arrow (§3.3, §5.3).
/// `direction` is already oriented by the metric's `betterDirection`, so a
/// falling double-fault rate is `.improving` — no view can get this backwards.
public struct TrendDelta: Equatable, Sendable {
    public enum Direction: Sendable { case improving, declining, flat }

    public let direction: Direction
    /// `recent − prior`, signed, in the metric's display unit: percentage
    /// points for `.percent` metrics, raw ratio units for `.ratio` metrics.
    public let change: Double
    /// Pooled ratio (§3.3) over the more-recent half of the block.
    public let recent: TrendMetric.Ratio
    /// Pooled ratio over the earlier half of the block.
    public let prior: TrendMetric.Ratio

    public init(direction: Direction, change: Double, recent: TrendMetric.Ratio, prior: TrendMetric.Ratio) {
        self.direction = direction
        self.change = change
        self.recent = recent
        self.prior = prior
    }
}

/// One metric's full picture over a scoped window: the plottable dots, the
/// pooled headline figure, and the delta.
public struct TrendSeries: Equatable, Sendable, Identifiable {
    public var id: TrendMetric { metric }
    public let metric: TrendMetric
    /// Oldest-first; matches with no plottable dot for this metric are
    /// omitted (§3.4) — see `TrendPoint.index` for how gaps stay visible.
    public let points: [TrendPoint]
    /// Σnumerator / Σdenominator over EVERY sample in the window — including
    /// samples with no plottable dot (§3.3). Built from `rawPair`, never from
    /// `points`. `nil` only when the aggregate denominator is 0.
    /// **This is not a mean of `points`.**
    public let pooled: TrendMetric.Ratio?
    /// `nil` when either half of the block has fewer than
    /// `PerformanceTrends.minimumBlockMatches` samples.
    public let delta: TrendDelta?

    public init(metric: TrendMetric, points: [TrendPoint], pooled: TrendMetric.Ratio?, delta: TrendDelta?) {
        self.metric = metric
        self.points = points
        self.pooled = pooled
        self.delta = delta
    }
}

public enum PerformanceTrends {

    /// Fewest eligible matches before the feature says anything at all (§6.6).
    public static let minimumMatches = 3
    /// Fewest matches in EACH half of a block before a delta is emitted.
    public static let minimumBlockMatches = 2

    /// Below this, a change is reported `.flat`. One threshold per unit, each
    /// set at roughly "smaller than this is measurement noise, not a trend":
    /// a percentage point, a tenth of a ratio, two bpm, half a step, half a
    /// metre, two minutes.
    ///
    /// `delta(for:in:)` returns `.flat` for a `.neutral` metric before it gets
    /// here, so today only `.percent`, `.ratio` and `.steps` are ever consulted
    /// — every `.bpm`/`.metres`/`.minutes` metric is currently neutral. The
    /// other three are kept, and correct, for the moment one of those units
    /// gains an orientation.
    public static func minimumChange(for unit: TrendMetric.Unit) -> Double {
        switch unit {
        case .percent: return 1.0
        case .ratio:   return 0.1
        case .bpm:     return 2.0
        case .steps:   return 0.5
        case .metres:  return 0.5
        case .minutes: return 2.0
        }
    }

    /// Eligible samples, **oldest-first**. `records` may be newest-first
    /// (`PhoneStatsStore.history` is) — this is the one place the order
    /// flips. Ineligibility (tracking-disabled format, too few categorized
    /// points) is entirely `MatchTrendSample.init?`'s job — including an
    /// in-progress match, which is eligible once it clears the categorized-
    /// points threshold, its `isInProgress` flag telling callers apart from
    /// a completed match.
    ///
    /// `maxHR` is the player's currently resolved maximum heart rate and feeds
    /// only the hard-zone counters. It is a live setting applied retroactively
    /// to archived matches, so a caller caching the result must invalidate on
    /// it as well as on `records` — see `MatchTrendSample.init?(record:maxHR:)`.
    public static func samples(from records: [MatchRecord], maxHR: Int = 190) -> [MatchTrendSample] {
        records
            .compactMap { MatchTrendSample(record: $0, maxHR: maxHR) }
            .sorted { $0.startTime < $1.startTime }
    }

    /// Filter first, then window (§3.2) — "last 10 singles" means the last
    /// 10 singles matches, not the singles among the last 10. `samples` is
    /// assumed oldest-first; `.last(n)` takes the most recent `n` via
    /// `suffix`, which on an oldest-first array is exactly "most recent".
    public static func scoped(_ samples: [MatchTrendSample], filter: TrendFilter, window: TrendWindow) -> [MatchTrendSample] {
        let filtered = samples.filter { filter.includes($0) }
        switch window {
        case .all:
            return filtered
        case .last(let n):
            return Array(filtered.suffix(max(0, n)))
        }
    }

    /// Builds one metric's series over an already-scoped, oldest-first
    /// sample list. `nil` only when `samples` is empty — a metric with valid
    /// samples but no coverage still returns a series with empty `points`
    /// and a `nil` `pooled`, so the caller can distinguish "no matches in
    /// this window" from "matches exist but none carry this metric's data."
    public static func series(for metric: TrendMetric, in samples: [MatchTrendSample]) -> TrendSeries? {
        guard !samples.isEmpty else { return nil }

        let points: [TrendPoint] = samples.enumerated().compactMap { index, sample in
            guard let ratio = metric.ratio(in: sample) else { return nil }
            return TrendPoint(id: sample.matchID, index: index, date: sample.startTime, ratio: ratio)
        }

        let pooled = pooledRatio(for: metric, in: samples)
        let delta = delta(for: metric, in: samples)

        return TrendSeries(metric: metric, points: points, pooled: pooled, delta: delta)
    }

    public static func series(for group: TrendMetricGroup, in samples: [MatchTrendSample]) -> [TrendSeries] {
        TrendMetric.metrics(in: group).compactMap { series(for: $0, in: samples) }
    }

    /// The four rows on the archive screen (§1.1).
    public static func headline(in samples: [MatchTrendSample]) -> [TrendSeries] {
        TrendMetric.headline.compactMap { series(for: $0, in: samples) }
    }

    // MARK: - Pooling and deltas

    /// Σnumerator / Σdenominator over every sample, via `rawPair` — never via
    /// `ratio`, which would discard the numerator of any zero-denominator
    /// sample (§3.3, §4.2's `10W/0UE` example).
    private static func pooledRatio(for metric: TrendMetric, in samples: [MatchTrendSample]) -> TrendMetric.Ratio? {
        var num = 0, den = 0
        for sample in samples {
            guard let pair = metric.rawPair(in: sample) else { continue }
            num += pair.numerator
            den += pair.denominator
        }
        guard den > 0 else { return nil }
        return TrendMetric.Ratio(numerator: num, denominator: den)
    }

    /// Splits `samples` (oldest-first) into an earlier half and a
    /// more-recent half. When the count is odd, the extra sample goes to the
    /// recent half. `nil` when either half has fewer than
    /// `minimumBlockMatches` samples, or when either half's pooled ratio has
    /// a zero denominator.
    private static func delta(for metric: TrendMetric, in samples: [MatchTrendSample]) -> TrendDelta? {
        let mid = samples.count / 2
        let priorSlice = Array(samples[..<mid])
        let recentSlice = Array(samples[mid...])
        guard priorSlice.count >= minimumBlockMatches, recentSlice.count >= minimumBlockMatches else { return nil }
        guard let prior = pooledRatio(for: metric, in: priorSlice),
              let recent = pooledRatio(for: metric, in: recentSlice) else { return nil }

        let rawChange = recent.value - prior.value
        let scaledChange = metric.unit == .percent ? rawChange * 100 : rawChange

        let direction: TrendDelta.Direction
        if metric.betterDirection == .neutral {
            direction = .flat
        } else if abs(scaledChange) < minimumChange(for: metric.unit) {
            direction = .flat
        } else {
            let isImprovement = metric.betterDirection == .higher ? scaledChange > 0 : scaledChange < 0
            direction = isImprovement ? .improving : .declining
        }

        return TrendDelta(direction: direction, change: scaledChange, recent: recent, prior: prior)
    }
}
