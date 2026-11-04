// MatchComparison.swift — "Compare with previous match": baseline selection
// and the pairwise metric table. Platform-neutral: no SwiftUI.
//
// Every rate is read through the Trends catalogue (`TrendMetric.rawPair`) over
// a `MatchTrendSample` projected from ONE `MatchStatsSummary` per match, so
// the denominators and better-direction semantics are the existing ones and
// there is no second counting pass. No archive-size or point-count minimum
// gates a pairwise comparison; a zero denominator is "Not recorded" (`nil`),
// never zero. See MATCH_TAGS_PLAN.md §7.1.
import Foundation

// MARK: - Baseline selection

public enum PreviousMatchBaseline {

    /// The automatically offered baseline for a match.
    public enum Selection: Equatable, Sendable {
        /// The current match has a complete identity (`Matchup`) and this is
        /// the most recent EARLIER completed match against the same opponent(s)
        /// — in doubles the same unordered pair with the same partner.
        case rematch(MatchRecord, Matchup)
        /// Complete identity, but no earlier completed match against it. Show
        /// "No previous match against this opponent" and offer the same-type
        /// picker; never silently label another opponent as a rematch.
        case noRematch(Matchup)
        /// The current match is untagged or its identity is incomplete: the
        /// most recent earlier completed match of the same singles/doubles type.
        case sameType(MatchRecord)
        /// No earlier completed match of this type exists.
        case noHistory

        /// The record to compare against, when one was chosen automatically.
        public var baseline: MatchRecord? {
            switch self {
            case .rematch(let record, _), .sameType(let record): return record
            case .noRematch, .noHistory: return nil
            }
        }
    }

    /// Chooses the default baseline for `current` from `records` (the whole
    /// archive; `current` itself is excluded by id). Only completed records
    /// strictly earlier than `current` — by result/activity date, then id — qualify.
    public static func select(for current: MatchRecord, in records: [MatchRecord]) -> Selection {
        let earlierCompleted = records
            .filter { $0.id != current.id && !$0.isInProgress && $0.matchType == current.matchType
                && isOrderedBefore($0, current) }
            .sorted(by: MatchChronology.newestFirst)   // newest first

        if let matchup = Matchup(record: current) {
            if let rematch = earlierCompleted.first(where: { Matchup(record: $0) == matchup }) {
                return .rematch(rematch, matchup)
            }
            return .noRematch(matchup)
        }
        if let previous = earlierCompleted.first {
            return .sameType(previous)
        }
        return .noHistory
    }

    /// "Choose another match": every other record of the same singles/doubles
    /// type, newest first. Completed only by default; `includeInProgress`
    /// adds in-progress records, which the UI must label as partial.
    public static func pickerCandidates(
        for current: MatchRecord,
        in records: [MatchRecord],
        includeInProgress: Bool = false
    ) -> [MatchRecord] {
        records
            .filter { $0.id != current.id && $0.matchType == current.matchType
                && (includeInProgress || !$0.isInProgress) }
            .sorted(by: MatchChronology.newestFirst)
    }

    /// Chronological order: result/activity date, then id string as a stable tie-break.
    public static func isOrderedBefore(_ a: MatchRecord, _ b: MatchRecord) -> Bool {
        MatchChronology.oldestFirst(a, b)
    }
}

// MARK: - Pairwise comparison

public struct MatchComparison: Sendable {

    /// One column of the comparison: what each match recorded and how much of
    /// it can be trusted.
    public struct Side: Equatable, Sendable {
        public let matchID: UUID
        public let startTime: Date
        public let date: Date
        public let dateLabel: String
        public let matchType: MatchType
        public let matchFormat: MatchFormat
        /// In progress — label "In Progress — partial stats"; never infer a result.
        public let isPartial: Bool
        /// `nil` while partial.
        public let result: MatchResult?
        /// Recorder-framed set scores ("6–4", "7–6 (7–3)"); a trailing
        /// not-yet-started set of an in-progress match is omitted.
        public let setScoreLabels: [String]
        /// `nil` when no duration was recorded.
        public let durationSeconds: TimeInterval?
        /// Points with a saved point record (0 for a score-only match).
        public let pointsTracked: Int
        /// Of those, points with a recorded outcome.
        public let outcomeTrackedPoints: Int

        /// Whether this match saved point-by-point data at all.
        public var hasPointData: Bool { pointsTracked > 0 }
        /// Whether outcome (winner / error / serve) tracking was on for any point.
        public var hasOutcomeTracking: Bool { outcomeTrackedPoints > 0 }
        /// `outcomeTrackedPoints / pointsTracked`, `nil` without point data.
        public var outcomeCoverage: Double? {
            pointsTracked > 0 ? Double(outcomeTrackedPoints) / Double(pointsTracked) : nil
        }
    }

    /// One metric across both matches.
    public struct Row: Equatable, Sendable, Identifiable {
        public var id: TrendMetric { metric }
        public let metric: TrendMetric
        /// `nil` = "Not recorded" (a gap, never zero). Display as
        /// "60% — 12/20" from `numerator`/`denominator`.
        public let current: TrendMetric.Ratio?
        public let baseline: TrendMetric.Ratio?
        /// `current − baseline` in percentage points; `nil` unless both recorded.
        public let percentagePointChange: Double?
        /// Oriented by `metric.betterDirection` exactly like Trends
        /// (`.improving` for a falling double-fault rate); changes under
        /// `PerformanceTrends.minimumChange` are `.flat`. `nil` unless both recorded.
        public let direction: TrendDelta.Direction?
    }

    /// The compared rates, in display order: score/serve/return/pressure, then
    /// winners and errors. Rates take priority over raw counts.
    public static let metrics: [TrendMetric] = [
        .pointsWon,
        .firstServeIn, .firstServeWin, .secondServeWin,
        .returnWinFirst, .returnWinSecond,
        .breakPointsConverted, .breakPointsSaved,
        .winners, .unforcedErrors, .doubleFaults
    ]

    public let current: Side
    public let baseline: Side
    public let rows: [Row]

    /// The two matches were played to different formats — explain it; set
    /// counts and durations are not like-for-like.
    public var formatsDiffer: Bool { current.matchFormat != baseline.matchFormat }
    /// Singles vs doubles (only reachable through an explicit picker choice).
    public var matchTypesDiffer: Bool { current.matchType != baseline.matchType }

    public init(current: MatchRecord, baseline: MatchRecord) {
        let currentSample = Self.sample(current)
        let baselineSample = Self.sample(baseline)
        let currentServe = Self.sample(current, categorizedOnly: true)
        let baselineServe = Self.sample(baseline, categorizedOnly: true)
        self.current = Self.side(current, sample: currentSample)
        self.baseline = Self.side(baseline, sample: baselineSample)
        self.rows = Self.metrics.map { metric in
            let serveSplit = Self.requiresOutcomeTracking(metric)
            let a = Self.ratio(metric, in: serveSplit ? currentServe : currentSample)
            let b = Self.ratio(metric, in: serveSplit ? baselineServe : baselineSample)
            guard let a, let b else {
                return Row(metric: metric, current: a, baseline: b, percentagePointChange: nil, direction: nil)
            }
            let change = (a.value - b.value) * 100
            return Row(metric: metric, current: a, baseline: b,
                       percentagePointChange: change, direction: Self.direction(metric, change: change))
        }
    }

    // MARK: Derivation

    /// Serve-split and return-split metrics read `PointStat.isSecondServe`,
    /// whose default `false` on an untracked point is not evidence of a first
    /// serve (same rule as `ServingPointCategory`). They therefore need SOME
    /// outcome tracking; outcome-mix metrics already divide by categorized-only
    /// denominators; points won and break points are valid on every point.
    static func requiresOutcomeTracking(_ metric: TrendMetric) -> Bool {
        switch metric {
        case .firstServeIn, .secondServeIn, .firstServeWin, .secondServeWin,
             .returnWinFirst, .returnWinSecond:
            return true
        default:
            return false
        }
    }

    /// `categorizedOnly` projects the record through a summary of its
    /// categorized points, for the serve/return splits: an uncategorized
    /// point's default `isSecondServe == false` would otherwise be counted as a
    /// first serve (1 tracked second serve + 9 untracked service points would
    /// read as 90% first-serve-in). A split with no categorized denominator
    /// stays nil ("Not recorded"), never zero.
    private static func sample(_ record: MatchRecord, categorizedOnly: Bool = false) -> MatchTrendSample {
        let stats = categorizedOnly ? record.stats.filter { $0.outcome != .uncategorized } : record.stats
        let summary = MatchStatsSummary(stats: stats, focal: .me,
                                        setElapsedSeconds: record.setElapsedSeconds,
                                        resumeEvents: record.resumeEvents, sessionPoints: record.stats)
        return MatchTrendSample(record: record, summary: summary)
    }

    private static func ratio(_ metric: TrendMetric, in sample: MatchTrendSample) -> TrendMetric.Ratio? {
        if requiresOutcomeTracking(metric) && sample.totalPoints == 0 { return nil }
        return metric.ratio(in: sample)
    }

    private static func direction(_ metric: TrendMetric, change: Double) -> TrendDelta.Direction {
        guard metric.betterDirection != .neutral,
              abs(change) >= PerformanceTrends.minimumChange(for: metric.unit) else { return .flat }
        let improved = metric.betterDirection == .higher ? change > 0 : change < 0
        return improved ? .improving : .declining
    }

    private static func side(_ record: MatchRecord, sample: MatchTrendSample) -> Side {
        var sets = record.setScores
        if record.isInProgress, sets.count > 1, let last = sets.last,
           last.gamesMe + last.gamesOpponent + last.tieBreakPointsMe + last.tieBreakPointsOpponent == 0 {
            sets.removeLast()
        }
        let labels = sets.enumerated().map { index, set in
            SetScoreLabel.string(for: set, setIndex: index, matchFormat: record.matchFormat)
        }
        return Side(
            matchID: record.id,
            startTime: record.startTime,
            date: MatchChronology.date(record),
            dateLabel: MatchChronology.label(record),
            matchType: record.matchType,
            matchFormat: record.matchFormat,
            isPartial: record.isInProgress,
            result: MatchResult(record: record),
            setScoreLabels: labels,
            durationSeconds: MatchDurations.matchElapsedSeconds(record),
            pointsTracked: sample.totalPoints,
            outcomeTrackedPoints: sample.categorizedPoints
        )
    }
}
