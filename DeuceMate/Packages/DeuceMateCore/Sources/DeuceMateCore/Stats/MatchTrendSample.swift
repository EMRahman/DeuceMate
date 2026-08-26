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

    // MARK: - Heart rate — recorder-only, sampled

    /// Points carrying a usable `heartRateBPM` reading. This is the ONLY valid
    /// denominator for the HR metrics: a match recorded with Health access off
    /// has 0 here and must produce no dot at all, never a 0 bpm one
    /// (docs/features/PERFORMANCE_TRENDS_PLAN.md §3.4). `TrendMetric`'s gates
    /// enforce that; these counters stay raw.
    public let hrSampledPoints: Int
    public let hrSumBPM: Int
    /// Points spent in Z4 or Z5 — "the hard zones" — and how many were won.
    /// Zone attribution depends on the `maxHR` this sample was built with, so
    /// two samples of the same match built with different `maxHR` values
    /// legitimately differ here. See `init?(record:maxHR:)`.
    public let hardZonePoints: Int
    public let hardZoneWins: Int

    // MARK: - Movement

    /// Entries in `MatchStatsSummary.stepsTimeline` — points that carried a
    /// real `stepsCumulative` sample. Deliberately NOT `StepsSeries.make`'s
    /// output: that falls back to spreading `MatchRecord.totalSteps` evenly
    /// across points (StepsSeries.swift:66-79), under which "steps per point"
    /// is `totalSteps / n` by construction — a constant, not a measurement.
    public let stepSampledPoints: Int
    /// Σ `perPointSteps` over the timeline, including its baseline first entry
    /// (which carries a load of 0). Pairing it with `stepSampledPoints`
    /// reproduces `MatchStatsSummary.averageSteps` exactly, so the trend and
    /// the text export's "Avg Steps / Point" can never disagree.
    public let stepSumLoad: Int
    /// `MatchRecord.totalDistanceMeters` rounded to whole metres, so trend
    /// ratios stay `Int`/`Int`. `nil` when the match recorded no distance.
    public let distanceMetres: Int?
    /// Whole minutes of match play, truncated to match `MatchDurations
    /// .minutesString`. `nil` when no duration is resolvable. Not HealthKit
    /// data — this is the one Movement counter that survives an iCloud
    /// restore and exists without Health access.
    public let elapsedMinutes: Int?

    // MARK: - Fatigue — first played set vs last played set

    /// One side of the fatigue comparison. Each family carries its own
    /// denominator: win rate counts every point in the set, HR counts only
    /// HR-sampled points, movement only step-sampled ones. Sharing one
    /// denominator across the three would repeat §3.6's mixed-denominator
    /// mistake in a new place.
    public struct SetSlice: Equatable, Sendable {
        public let setIndex: Int
        public let points: Int
        public let pointsWon: Int
        public let hrSampledPoints: Int
        public let hrSumBPM: Int
        public let stepSampledPoints: Int
        public let stepSumLoad: Int

        public init(setIndex: Int, points: Int, pointsWon: Int, hrSampledPoints: Int,
                    hrSumBPM: Int, stepSampledPoints: Int, stepSumLoad: Int) {
            self.setIndex = setIndex
            self.points = points
            self.pointsWon = pointsWon
            self.hrSampledPoints = hrSampledPoints
            self.hrSumBPM = hrSumBPM
            self.stepSampledPoints = stepSampledPoints
            self.stepSumLoad = stepSumLoad
        }
    }

    /// The two sets the fatigue metrics compare, or `nil` when this match
    /// can't support the comparison at all. See `fatigueSplit(record:summary:)`
    /// for the rule — it is resolved once, here, rather than re-derived per
    /// metric.
    public struct FatigueSplit: Equatable, Sendable {
        public let firstSet: SetSlice
        public let finalSet: SetSlice

        public init(firstSet: SetSlice, finalSet: SetSlice) {
            self.firstSet = firstSet
            self.finalSet = finalSet
        }
    }

    public let fatigue: FatigueSplit?

    // MARK: - Eligibility

    /// Minimum categorized points for a match to be worth trending. Same
    /// threshold `RecCoachInsights.generate` already uses to refuse thin
    /// data (RecCoachInsights.swift:78) — one number, cited not re-invented.
    public static let minimumCategorizedPoints = 20

    /// Fewest points a set must contain to take part in the fatigue
    /// comparison. Same number `RecCoachInsights`' set-duration decline rule
    /// already requires of both sets (RecCoachInsights.swift:276) — one
    /// threshold, cited rather than re-invented. It also keeps a full set from
    /// being compared against a ~15-point super-tiebreak decider, which is a
    /// "set" by index but not by workload.
    public static let minimumFatigueSetPoints = 20

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
        // Health-derived counters default to "absent" so a caller that only
        // cares about the tennis metrics (every existing test) stays valid and
        // gets a sample with no health coverage — which is exactly what a match
        // recorded without Health access produces.
        hrSampledPoints: Int = 0, hrSumBPM: Int = 0,
        hardZonePoints: Int = 0, hardZoneWins: Int = 0,
        stepSampledPoints: Int = 0, stepSumLoad: Int = 0,
        distanceMetres: Int? = nil, elapsedMinutes: Int? = nil,
        fatigue: FatigueSplit? = nil
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
        self.hrSampledPoints = hrSampledPoints
        self.hrSumBPM = hrSumBPM
        self.hardZonePoints = hardZonePoints
        self.hardZoneWins = hardZoneWins
        self.stepSampledPoints = stepSampledPoints
        self.stepSumLoad = stepSumLoad
        self.distanceMetres = distanceMetres
        self.elapsedMinutes = elapsedMinutes
        self.fatigue = fatigue
    }

    /// `nil` when the match is ineligible (§3.5): a format that disables
    /// point tracking, or too few categorized points so far. In-progress
    /// matches ARE eligible once they clear the categorized-points
    /// threshold — their stats simply reflect the match as scored so far.
    /// `maxHR` is the player's currently resolved maximum heart rate
    /// (`HRZone.resolveMaxHR`). It affects ONLY the hard-zone counters — every
    /// other field, including `hrSumBPM`, is yardstick-free. Because it is a
    /// live setting applied retroactively to archived matches, a caller that
    /// caches samples must invalidate on it changing as well as on the records
    /// changing (the iOS `TrendsSamples` cache does).
    public init?(record: MatchRecord, maxHR: Int = 190) {
        guard !record.matchFormat.config.disablesPointTracking else { return nil }

        let summary = MatchStatsSummary(stats: record.stats, focal: .me,
                                        setElapsedSeconds: record.setElapsedSeconds,
                                        maxHR: maxHR)
        // MatchStatsSummary has no direct categorizedPoints field; derive it
        // from the two it does expose.
        let categorizedTotal = summary.totalPoints - summary.uncategorizedCount
        guard categorizedTotal >= Self.minimumCategorizedPoints else { return nil }

        var depth: [EndingShot: DepthCount] = [:]
        for stat in summary.rallyDepth {
            depth[stat.shot] = DepthCount(total: stat.total, wins: stat.wins)
        }
        let pointsWithShot = summary.rallyDepth.reduce(0) { $0 + $1.total }

        // Heart rate. `hrTimeline` holds exactly the points that carried a
        // usable reading, so its count is the honest denominator; a match with
        // Health off yields 0 and therefore no dots at all.
        let hrPoints = summary.hrTimeline
        let hardZoneStats = summary.zoneWinRates.filter { Self.hardZones.contains($0.zone) }

        // Movement. The sampled timeline only — never StepsSeries' totalSteps
        // fallback, which would make steps-per-point a constant by construction.
        let stepPoints = summary.stepsTimeline

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
            hrSampledPoints: hrPoints.count,
            hrSumBPM: hrPoints.reduce(0) { $0 + $1.bpm },
            hardZonePoints: hardZoneStats.reduce(0) { $0 + $1.total },
            hardZoneWins: hardZoneStats.reduce(0) { $0 + $1.wins },
            stepSampledPoints: stepPoints.count,
            stepSumLoad: stepPoints.reduce(0) { $0 + $1.perPointSteps },
            distanceMetres: record.totalDistanceMeters.flatMap { $0 > 0 ? Int($0.rounded()) : nil },
            elapsedMinutes: MatchDurations.matchElapsedSeconds(record)
                .flatMap { $0 > 0 ? Int($0) / 60 : nil },
            fatigue: Self.fatigueSplit(record: record, summary: summary)
        )
    }

    // MARK: - Fatigue split

    /// Z4 and Z5 — "the hard zones", pooled because either alone is too thin
    /// on a recreational match to trend.
    private static let hardZones: Set<HRZone> = [.z4, .z5]

    /// The two sets the fatigue metrics compare: the **first played set** and
    /// the **last played set**, both needing `minimumFatigueSetPoints`. `nil`
    /// when the match can't support the comparison.
    ///
    /// It is a rule, not a search: hunting for "the first two sets that
    /// qualify" would let the metric mean set 1 vs set 3 on one match and set
    /// 2 vs set 3 on the next, which is not a comparable observation.
    ///
    /// In-progress matches are excluded outright, even though they are
    /// otherwise eligible samples: their last set is still being played, so its
    /// rates are a partial reading that would drift point by point. Every other
    /// counter on the sample stays valid for a live match.
    ///
    /// `record.stats` needs no sorting here — every figure is a per-set count,
    /// so point order within a set is irrelevant.
    private static func fatigueSplit(record: MatchRecord, summary: MatchStatsSummary) -> FatigueSplit? {
        guard !record.isInProgress else { return nil }

        var pointsBySet: [Int: (points: Int, won: Int)] = [:]
        for stat in record.stats {
            var entry = pointsBySet[stat.setIndex] ?? (points: 0, won: 0)
            entry.points += 1
            if stat.winner == .me { entry.won += 1 }
            pointsBySet[stat.setIndex] = entry
        }

        let playedSets = pointsBySet.keys.sorted()
        guard let firstIndex = playedSets.first,
              let finalIndex = playedSets.last,
              firstIndex != finalIndex,
              let firstCounts = pointsBySet[firstIndex],
              let finalCounts = pointsBySet[finalIndex],
              firstCounts.points >= minimumFatigueSetPoints,
              finalCounts.points >= minimumFatigueSetPoints else { return nil }

        func slice(_ index: Int, _ counts: (points: Int, won: Int)) -> SetSlice {
            let hr = summary.hrTimeline.filter { $0.setIndex == index }
            let steps = summary.stepsTimeline.filter { $0.setIndex == index }
            return SetSlice(
                setIndex: index,
                points: counts.points,
                pointsWon: counts.won,
                hrSampledPoints: hr.count,
                hrSumBPM: hr.reduce(0) { $0 + $1.bpm },
                stepSampledPoints: steps.count,
                stepSumLoad: steps.reduce(0) { $0 + $1.perPointSteps }
            )
        }

        return FatigueSplit(firstSet: slice(firstIndex, firstCounts),
                            finalSet: slice(finalIndex, finalCounts))
    }
}
