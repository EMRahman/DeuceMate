// MatchTrendSample.swift — one match reduced to the raw counters trend charts
// pool and window across a whole archive. Platform-neutral: no SwiftUI.
//
// Built from a single MatchStatsSummary(focal: .me) so no counting predicate
// is ever restated — drifting from MatchStatsSummary is exactly the failure
// class CLAUDE.md §5 warns about. Field names are recorder-framed, not
// focal-relative: `forcedErrorsCaused` cannot be misread backwards the way
// `MatchStatsSummary.opponentForcedErrors` can. See
// docs/features/PERFORMANCE_TRENDS_PLAN.md §5.1.
import Foundation

/// A single eligible match, reduced to the counters `PerformanceTrends` pools
/// and windows. `init?` owns the eligibility rule (§3.5 of the plan) so no
/// call site can forget a clause — a match that fails eligibility simply
/// produces no sample and is absent from every series.
public struct MatchTrendSample: Equatable, Sendable, Identifiable {
    public var id: UUID { matchID }

    // MARK: - Identity and grouping

    public let matchID: UUID
    public let startTime: Date
    public let matchType: MatchType
    public let matchFormat: MatchFormat
    /// `nil` means a draw OR a still-in-progress match — check `isInProgress`
    /// to tell them apart. In-progress matches are eligible (as of the
    /// owner's request to include them) as long as they clear the
    /// categorized-points threshold; their stats simply reflect the match
    /// so far and grow as it continues.
    public let recorderWon: Bool?
    /// Mirrors `MatchRecord.isInProgress` at the moment this sample was
    /// built. A live match's stats grow point-by-point without `endTime`/
    /// `iWon` ever changing, so callers that need to know whether a value
    /// might still change should check this rather than inferring it from
    /// `recorderWon == nil` (which a completed draw also produces).
    public let isInProgress: Bool

    // MARK: - Volume

    /// The categorized* fields below are what outcome-mix trend metrics
    /// divide by (§3.6); these all-points fields serve the serve/return/
    /// pressure metrics, which are valid on uncategorized points too.
    public let totalPoints: Int
    public let categorizedPoints: Int
    public let pointsWon: Int
    public let pointsLost: Int
    public let categorizedPointsWon: Int
    public let categorizedPointsLost: Int

    /// `categorizedPoints / totalPoints`. `1.0` when tracking stayed on for
    /// the whole match; lower when the player toggled it off mid-match
    /// (§3.6). Surfaced so a thinly-tracked window can be labelled rather
    /// than silently averaged in (OQ-5).
    public var trackingCoverage: Double {
        totalPoints > 0 ? Double(categorizedPoints) / Double(totalPoints) : 0
    }

    // MARK: - Serve and return

    /// `summary.firstServeTotal` — ALL service points, not just first serves
    /// that landed (MatchStatsSummary.swift:151-154).
    public let servicePoints: Int
    public let categorizedServicePoints: Int
    public let categorizedOpponentServicePoints: Int
    public let firstServesIn: Int
    public let firstServeWins: Int
    public let secondServePoints: Int
    /// Second-serve points that landed in (outcome != .doubleFault) — the
    /// numerator for "2nd Serve In". `summary.secondServeIn`.
    public let secondServesIn: Int
    public let secondServeWins: Int
    public let doubleFaults: Int
    public let returnPointsOnFirst: Int
    public let returnWinsOnFirst: Int
    public let returnPointsOnSecond: Int
    public let returnWinsOnSecond: Int
    public let opponentDoubleFaults: Int
    public var opponentServicePoints: Int { returnPointsOnFirst + returnPointsOnSecond }

    // MARK: - Outcome mix — recorder-framed, deliberately renamed

    public let winnersHit: Int              // summary.myWinners
    public let winnersConceded: Int         // summary.opponentWinners
    public let unforcedErrorsHit: Int       // summary.myUnforcedErrors
    public let unforcedErrorsDrawn: Int     // summary.opponentUnforcedErrors
    public let forcedErrorsConceded: Int    // summary.myForcedErrors
    public let forcedErrorsCaused: Int      // summary.opponentForcedErrors

    // MARK: - Pressure

    public let breakPointOpps: Int
    public let breakPointWins: Int
    public let breakPointsFaced: Int
    public let breakPointsLost: Int
    public let bigPointTotal: Int
    public let bigPointWins: Int

    // MARK: - Rally depth — keyed, never positional

    /// `MatchStatsSummary.rallyDepth` omits empty buckets, so this dictionary
    /// only ever holds the `EndingShot` cases that actually occurred.
    public struct DepthCount: Equatable, Sendable {
        public let total: Int
        public let wins: Int

        public init(total: Int, wins: Int) {
            self.total = total
            self.wins = wins
        }
    }
    public let rallyDepth: [EndingShot: DepthCount]
    public let pointsWithEndingShot: Int
    /// `rallyDepth` split by who served. The split is on `PointStat.server`,
    /// NOT on `EndingShot.serve` — that case is the *phase* a point ended in, so
    /// a point ending on the return shot is still a point I served. Getting
    /// those two axes confused is the easiest mistake available here.
    public let rallyDepthOnServe: [EndingShot: DepthCount]
    public let rallyDepthOnReturn: [EndingShot: DepthCount]
    /// Denominators for the share metrics: points on that side that carry an
    /// ending shot at all. Zero means no coverage, never "no rallies".
    public let pointsWithEndingShotOnServe: Int
    public let pointsWithEndingShotOnReturn: Int


    // MARK: - Fatigue — one slice per played set

    /// One played set's counters. Each family carries its own denominator: win
    /// rate counts every point in the set, movement only the step-sampled ones.
    /// Sharing one denominator across both would repeat §3.6's
    /// mixed-denominator mistake in a new place.
    public struct SetSlice: Equatable, Sendable {
        public let setIndex: Int
        public let points: Int
        public let pointsWon: Int
        public let stepSampledPoints: Int
        public let stepSumLoad: Int
        /// `true` when this set is the match's decider AND the format plays the
        /// decider as a 10-point super-tiebreak rather than a full set — which
        /// `.standard`, the default format, does. A super-tiebreak is a third
        /// set by position but not by workload (a dozen-odd points against
        /// sixty), so it plots as its own series rather than being averaged in
        /// with true third sets.
        public let isDecidingTiebreak: Bool

        public init(setIndex: Int, points: Int, pointsWon: Int,
                    stepSampledPoints: Int, stepSumLoad: Int,
                    isDecidingTiebreak: Bool = false) {
            self.setIndex = setIndex
            self.points = points
            self.pointsWon = pointsWon
            self.stepSampledPoints = stepSampledPoints
            self.stepSumLoad = stepSumLoad
            self.isDecidingTiebreak = isDecidingTiebreak
        }
    }

    /// One slice per played set, ordered by `setIndex`. Empty when the match
    /// can't support a per-set reading at all — see `setSlices(record:summary:)`.
    /// Coverage minimums are NOT applied here; they belong to the metrics, which
    /// need different ones for a full set and a super-tiebreak.
    public let setSlices: [SetSlice]

    /// The slice for `index`, but only when it is a genuine full set — a
    /// deciding super-tiebreak is excluded so it can't also be plotted as
    /// "Set 3".
    public func fullSetSlice(_ index: Int) -> SetSlice? {
        setSlices.first { $0.setIndex == index && !$0.isDecidingTiebreak }
    }

    /// The deciding set when the format played it as a super-tiebreak.
    public var decidingTiebreakSlice: SetSlice? {
        setSlices.first(where: \.isDecidingTiebreak)
    }

    // MARK: - Eligibility

    /// Minimum categorized points for a match to be worth trending. Same
    /// threshold `RecCoachInsights.generate` already uses to refuse thin
    /// data (RecCoachInsights.swift:78) — one number, cited not re-invented.
    public static let minimumCategorizedPoints = 20


    public init(
        matchID: UUID, startTime: Date, matchType: MatchType, matchFormat: MatchFormat,
        recorderWon: Bool?, isInProgress: Bool, totalPoints: Int, categorizedPoints: Int, pointsWon: Int,
        pointsLost: Int, categorizedPointsWon: Int, categorizedPointsLost: Int,
        servicePoints: Int, categorizedServicePoints: Int, categorizedOpponentServicePoints: Int,
        firstServesIn: Int, firstServeWins: Int, secondServePoints: Int, secondServesIn: Int, secondServeWins: Int,
        doubleFaults: Int, returnPointsOnFirst: Int, returnWinsOnFirst: Int,
        returnPointsOnSecond: Int, returnWinsOnSecond: Int, opponentDoubleFaults: Int,
        winnersHit: Int, winnersConceded: Int, unforcedErrorsHit: Int, unforcedErrorsDrawn: Int,
        forcedErrorsConceded: Int, forcedErrorsCaused: Int, breakPointOpps: Int,
        breakPointWins: Int, breakPointsFaced: Int, breakPointsLost: Int, bigPointTotal: Int,
        bigPointWins: Int, rallyDepth: [EndingShot: DepthCount], pointsWithEndingShot: Int,
        rallyDepthOnServe: [EndingShot: DepthCount] = [:],
        rallyDepthOnReturn: [EndingShot: DepthCount] = [:],
        pointsWithEndingShotOnServe: Int = 0, pointsWithEndingShotOnReturn: Int = 0,
        setSlices: [SetSlice] = []
    ) {
        self.matchID = matchID
        self.startTime = startTime
        self.matchType = matchType
        self.matchFormat = matchFormat
        self.recorderWon = recorderWon
        self.isInProgress = isInProgress
        self.totalPoints = totalPoints
        self.categorizedPoints = categorizedPoints
        self.pointsWon = pointsWon
        self.pointsLost = pointsLost
        self.categorizedPointsWon = categorizedPointsWon
        self.categorizedPointsLost = categorizedPointsLost
        self.servicePoints = servicePoints
        self.categorizedServicePoints = categorizedServicePoints
        self.categorizedOpponentServicePoints = categorizedOpponentServicePoints
        self.firstServesIn = firstServesIn
        self.firstServeWins = firstServeWins
        self.secondServePoints = secondServePoints
        self.secondServesIn = secondServesIn
        self.secondServeWins = secondServeWins
        self.doubleFaults = doubleFaults
        self.returnPointsOnFirst = returnPointsOnFirst
        self.returnWinsOnFirst = returnWinsOnFirst
        self.returnPointsOnSecond = returnPointsOnSecond
        self.returnWinsOnSecond = returnWinsOnSecond
        self.opponentDoubleFaults = opponentDoubleFaults
        self.winnersHit = winnersHit
        self.winnersConceded = winnersConceded
        self.unforcedErrorsHit = unforcedErrorsHit
        self.unforcedErrorsDrawn = unforcedErrorsDrawn
        self.forcedErrorsConceded = forcedErrorsConceded
        self.forcedErrorsCaused = forcedErrorsCaused
        self.breakPointOpps = breakPointOpps
        self.breakPointWins = breakPointWins
        self.breakPointsFaced = breakPointsFaced
        self.breakPointsLost = breakPointsLost
        self.bigPointTotal = bigPointTotal
        self.bigPointWins = bigPointWins
        self.rallyDepth = rallyDepth
        self.pointsWithEndingShot = pointsWithEndingShot
        self.rallyDepthOnServe = rallyDepthOnServe
        self.rallyDepthOnReturn = rallyDepthOnReturn
        self.pointsWithEndingShotOnServe = pointsWithEndingShotOnServe
        self.pointsWithEndingShotOnReturn = pointsWithEndingShotOnReturn
        self.setSlices = setSlices
    }

    /// `nil` when the match is ineligible (§3.5): a format that disables
    /// point tracking, or too few categorized points so far. In-progress
    /// matches ARE eligible once they clear the categorized-points
    /// threshold — their stats simply reflect the match as scored so far.
    public init?(record: MatchRecord) {
        guard !record.matchFormat.config.disablesPointTracking else { return nil }

        let summary = MatchStatsSummary(stats: record.stats, focal: .me,
                                        setElapsedSeconds: record.setElapsedSeconds)
        // MatchStatsSummary has no direct categorizedPoints field; derive it
        // from the two it does expose.
        let categorizedTotal = summary.totalPoints - summary.uncategorizedCount
        guard categorizedTotal >= Self.minimumCategorizedPoints else { return nil }

        func depthDictionary(_ stats: [MatchStatsSummary.RallyDepthStat]) -> [EndingShot: DepthCount] {
            var out: [EndingShot: DepthCount] = [:]
            for stat in stats {
                out[stat.shot] = DepthCount(total: stat.total, wins: stat.wins)
            }
            return out
        }
        let depth = depthDictionary(summary.rallyDepth)
        let pointsWithShot = summary.rallyDepth.reduce(0) { $0 + $1.total }
        let serveDepth = depthDictionary(summary.rallyDepthOnServe)
        let returnDepth = depthDictionary(summary.rallyDepthOnReturn)

        self.init(
            matchID: record.id, startTime: record.startTime, matchType: record.matchType,
            matchFormat: record.matchFormat, recorderWon: record.iWon,
            isInProgress: record.isInProgress,
            totalPoints: summary.totalPoints, categorizedPoints: categorizedTotal,
            pointsWon: summary.pointsWon, pointsLost: summary.lostPoints,
            categorizedPointsWon: summary.categorizedPointsWon,
            categorizedPointsLost: summary.categorizedPointsLost,
            servicePoints: summary.firstServeTotal,
            categorizedServicePoints: summary.categorizedServicePoints,
            categorizedOpponentServicePoints: summary.categorizedOpponentServicePoints,
            firstServesIn: summary.firstServeIn, firstServeWins: summary.firstServeWins,
            secondServePoints: summary.secondServeTotal, secondServesIn: summary.secondServeIn,
            secondServeWins: summary.secondServeWins,
            doubleFaults: summary.doubleFaults,
            returnPointsOnFirst: summary.returnOppsOnFirst, returnWinsOnFirst: summary.returnWinsOnFirst,
            returnPointsOnSecond: summary.returnOppsOnSecond, returnWinsOnSecond: summary.returnWinsOnSecond,
            opponentDoubleFaults: summary.opponentDoubleFaults,
            winnersHit: summary.myWinners, winnersConceded: summary.opponentWinners,
            unforcedErrorsHit: summary.myUnforcedErrors, unforcedErrorsDrawn: summary.opponentUnforcedErrors,
            forcedErrorsConceded: summary.myForcedErrors, forcedErrorsCaused: summary.opponentForcedErrors,
            breakPointOpps: summary.breakPointOpps, breakPointWins: summary.breakPointWins,
            breakPointsFaced: summary.breakPointsFaced, breakPointsLost: summary.breakPointsLost,
            bigPointTotal: summary.bigPointTotal, bigPointWins: summary.bigPointWins,
            rallyDepth: depth, pointsWithEndingShot: pointsWithShot,
            rallyDepthOnServe: serveDepth, rallyDepthOnReturn: returnDepth,
            pointsWithEndingShotOnServe: summary.rallyDepthOnServe.reduce(0) { $0 + $1.total },
            pointsWithEndingShotOnReturn: summary.rallyDepthOnReturn.reduce(0) { $0 + $1.total },
            setSlices: Self.setSlices(record: record, summary: summary)
        )
    }

    // MARK: - Per-set slices

    /// One slice per played set, ordered by `setIndex`, or empty when the match
    /// can't support a per-set reading.
    ///
    /// Two structural rules live here rather than in the metrics:
    ///
    /// - **At least two sets.** A single-set match has nothing to compare
    ///   across, so it contributes no fatigue data at all. This also excludes
    ///   the tiebreak-only formats (`.superTiebreak`, `.perpetualSuperTiebreak`)
    ///   and `.quick4Games`, all of which play one set.
    /// - **Nothing from an in-progress match.** Its last set is still being
    ///   played, so its rates would drift point by point. Every other counter on
    ///   the sample stays valid for a live match.
    ///
    /// Point-count minimums are deliberately NOT applied here: a full set and a
    /// 10-point super-tiebreak need different ones, and that is the metrics'
    /// business (`TrendMetric.minimumFullSetPoints` / `minimumTiebreakPoints`).
    ///
    /// `record.stats` needs no sorting — every figure is a per-set count, so
    /// point order within a set is irrelevant.
    ///
    /// The step slices deliberately **drop each set's first sample**. A
    /// `stepsTimeline` entry's load is measured from the previous sample, so a
    /// set's first entry is not comparable to the rest: in the opening set it is
    /// the match-wide baseline (load 0 by definition), and in every later set it
    /// spans the whole inter-set changeover. Both distortions push the same way
    /// — "you moved more when tired" — in the metric that exists to answer that
    /// question. Two sets of identical movement read 3.87 vs 4.00 before this
    /// drop and equal after it.
    private static func setSlices(record: MatchRecord, summary: MatchStatsSummary) -> [SetSlice] {
        guard !record.isInProgress else { return [] }

        var pointsBySet: [Int: (points: Int, won: Int)] = [:]
        for stat in record.stats {
            var entry = pointsBySet[stat.setIndex] ?? (points: 0, won: 0)
            entry.points += 1
            if stat.winner == .me { entry.won += 1 }
            pointsBySet[stat.setIndex] = entry
        }

        let playedSets = pointsBySet.keys.sorted()
        guard playedSets.count >= 2, let decidingIndex = playedSets.last else { return [] }

        // The decider is a super-tiebreak when the FORMAT says so — `.standard`,
        // the default, plays its third set as a 10-point tiebreak, while
        // `.bestOf3FullFinalSet` plays a real one. This is exact for a completed
        // match: the deciding set only exists when the match went the distance.
        let decidesWithTiebreak = record.matchFormat.config.finalSetStyle == .superTiebreak

        // Bucket the timeline once rather than re-filtering it per set.
        let stepsBySet = Dictionary(grouping: summary.stepsTimeline, by: \.setIndex)

        return playedSets.map { index in
            let counts = pointsBySet[index] ?? (points: 0, won: 0)
            // `stepsTimeline` is chronological, so `dropFirst` removes this
            // set's non-comparable opening delta (see the note above).
            let steps = (stepsBySet[index] ?? []).dropFirst()
            return SetSlice(
                setIndex: index,
                points: counts.points,
                pointsWon: counts.won,
                stepSampledPoints: steps.count,
                stepSumLoad: steps.reduce(0) { $0 + $1.perPointSteps },
                isDecidingTiebreak: index == decidingIndex && decidesWithTiebreak
            )
        }
    }

}
