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
        bigPointWins: Int, rallyDepth: [EndingShot: DepthCount], pointsWithEndingShot: Int
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

        var depth: [EndingShot: DepthCount] = [:]
        for stat in summary.rallyDepth {
            depth[stat.shot] = DepthCount(total: stat.total, wins: stat.wins)
        }
        let pointsWithShot = summary.rallyDepth.reduce(0) { $0 + $1.total }

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
            rallyDepth: depth, pointsWithEndingShot: pointsWithShot
        )
    }
}
