// TrendMetric.swift — the cross-match metric catalogue. Adding a metric is
// one case plus one switch arm plus one test, the same data-driven shape
// MatchFormatConfig uses for match formats. Platform-neutral: no SwiftUI.
// See docs/features/PERFORMANCE_TRENDS_PLAN.md §4 and §5.2.
import Foundation

/// The grouped sections a `TrendMetric` belongs to, matching the Trends
/// screen's layout (§6.2).
public enum TrendMetricGroup: String, CaseIterable, Identifiable, Sendable {
    case errors, attack, rallyDepth, serveReturn, pressure
    case rallyDepthByService, fatigue

    public var id: String { rawValue }

    public var displayLabel: String {
        switch self {
        case .errors:      return "Errors"
        case .attack:      return "Attack"
        case .rallyDepth:  return "Rally Depth"
        case .serveReturn: return "Serve & Return"
        case .pressure:    return "Pressure"
        case .rallyDepthByService: return "Rally Depth — By Service"
        case .fatigue:     return "Fatigue"
        }
    }
}

/// Whether a rising value is good, bad, or neither. Oriented once here so no
/// view can render a falling double-fault rate as bad news (§5.3).
public enum BetterDirection: Equatable, Sendable {
    case higher, lower, neutral
}

/// The full cross-match metric catalogue. All counters below are read from a
/// `MatchTrendSample`, which is itself recorder-framed — see that type's docs
/// for why `forcedErrorsCaused` is not `opponentForcedErrors` read backwards.
public enum TrendMetric: String, CaseIterable, Identifiable, Sendable {
    case doubleFaults, doubleFaultsConceded
    case unforcedErrors, unforcedErrorsDrawn
    case forcedErrorsConceded, forcedErrorsCaused
    case winners, winnersConceded, wueRatio, aggressionIndex, ownErrorShare
    case depthShareServe, depthShareReturn, depthShareServePlusOne, depthShareRally
    case depthWinServe, depthWinReturn, depthWinServePlusOne, depthWinRally
    case firstServeIn, secondServeIn, firstServeWin, secondServeWin, returnWinFirst, returnWinSecond
    case breakPointsConverted, breakPointsSaved, bigPointWin, pointsWon
    case servedShareServe, servedShareReturn, servedShareServePlusOne, servedShareRally
    case returnedShareServe, returnedShareReturn, returnedShareServePlusOne, returnedShareRally
    case winRateSet1, winRateSet2, winRateSet3, winRateDecidingTiebreak
    case stepsPerPointSet1, stepsPerPointSet2, stepsPerPointSet3, stepsPerPointDecidingTiebreak

    public var id: String { rawValue }

    /// How a metric's raw pair should be printed: as a percent, or as a bare
    /// ratio (W:UE only — plotting `Double.infinity` would destroy a chart's
    /// Y domain for the whole series, so it is never percent-formatted).
    /// `.percent` and `.ratio` describe a share; the rest name a real unit,
    /// which is what makes them un-poolable onto one Y axis with the others —
    /// `TrendChart` buckets its series by this value for exactly that reason.
    public enum Unit: Hashable, Sendable { case percent, ratio, steps }

    /// A metric's value on one match, as the pair it came from so the UI can
    /// print "12/38" as well as "32%". Mirrors `RatioDisplay`
    /// (StatFormatting.swift:41).
    public struct Ratio: Equatable, Sendable {
        public let numerator: Int
        public let denominator: Int
        public var value: Double { Double(numerator) / Double(denominator) }

        public init(numerator: Int, denominator: Int) {
            self.numerator = numerator
            self.denominator = denominator
        }
    }

    public var group: TrendMetricGroup {
        switch self {
        case .doubleFaults, .doubleFaultsConceded, .unforcedErrors, .unforcedErrorsDrawn,
             .forcedErrorsConceded, .forcedErrorsCaused:
            return .errors
        case .winners, .winnersConceded, .wueRatio, .aggressionIndex, .ownErrorShare:
            return .attack
        case .depthShareServe, .depthShareReturn, .depthShareServePlusOne, .depthShareRally,
             .depthWinServe, .depthWinReturn, .depthWinServePlusOne, .depthWinRally:
            return .rallyDepth
        case .firstServeIn, .secondServeIn, .firstServeWin, .secondServeWin, .returnWinFirst, .returnWinSecond:
            return .serveReturn
        case .breakPointsConverted, .breakPointsSaved, .bigPointWin, .pointsWon:
            return .pressure
        case .servedShareServe, .servedShareReturn, .servedShareServePlusOne, .servedShareRally,
             .returnedShareServe, .returnedShareReturn, .returnedShareServePlusOne, .returnedShareRally:
            return .rallyDepthByService
        case .winRateSet1, .winRateSet2, .winRateSet3, .winRateDecidingTiebreak,
             .stepsPerPointSet1, .stepsPerPointSet2, .stepsPerPointSet3, .stepsPerPointDecidingTiebreak:
            return .fatigue
        }
    }

    public var displayLabel: String {
        switch self {
        case .doubleFaults:            return "Double Faults"
        case .doubleFaultsConceded:    return "Double Faults Conceded"
        case .unforcedErrors:          return "Unforced Errors"
        case .unforcedErrorsDrawn:     return "Unforced Errors Drawn"
        case .forcedErrorsConceded:    return "Forced Errors Conceded"
        case .forcedErrorsCaused:      return "Forced Errors Caused"
        case .winners:                 return "Winners"
        case .winnersConceded:         return "Winners Conceded"
        case .wueRatio:                return "W:UE Ratio"
        case .aggressionIndex:         return "Aggression Index"
        case .ownErrorShare:           return "Own-Error Share"
        case .depthShareServe:         return "Ending on Serve"
        case .depthShareReturn:        return "Ending on Return"
        case .depthShareServePlusOne:  return "Ending on S+1"
        case .depthShareRally:         return "Ending in Rally"
        case .depthWinServe:           return "Win Rate — Serve"
        case .depthWinReturn:          return "Win Rate — Return"
        case .depthWinServePlusOne:    return "Win Rate — S+1"
        case .depthWinRally:           return "Win Rate — Rally"
        case .firstServeIn:            return "1st Serve In"
        case .secondServeIn:           return "2nd Serve In"
        case .firstServeWin:           return "1st Serve Win"
        case .secondServeWin:          return "2nd Serve Win"
        case .returnWinFirst:          return "Return Win (1st)"
        case .returnWinSecond:         return "Return Win (2nd)"
        case .breakPointsConverted:    return "Break Points Converted"
        case .breakPointsSaved:        return "Break Points Saved"
        case .bigPointWin:             return "Big-Point Win %"
        case .pointsWon:               return "Points Won"
        // Deliberately the same four labels as the whole-match mix: only one
        // side is on screen at a time (the group's own picker chooses it), so
        // repeating the side in every legend entry would be noise.
        case .servedShareServe, .returnedShareServe:               return "Ending on Serve"
        case .servedShareReturn, .returnedShareReturn:             return "Ending on Return"
        case .servedShareServePlusOne, .returnedShareServePlusOne: return "Ending on S+1"
        case .servedShareRally, .returnedShareRally:               return "Ending in Rally"
        // Both fatigue charts share one vocabulary — the chart's own unit
        // caption says which quantity is being plotted, so repeating it in four
        // legend chips would be noise.
        case .winRateSet1, .stepsPerPointSet1:   return "Set 1"
        case .winRateSet2, .stepsPerPointSet2:   return "Set 2"
        case .winRateSet3, .stepsPerPointSet3:   return "Set 3"
        case .winRateDecidingTiebreak, .stepsPerPointDecidingTiebreak:
            return "Set 3 (Super TB)"
        }
    }

    public var denominatorLabel: String {
        switch self {
        case .doubleFaults, .firstServeIn, .firstServeWin:
            return "of service points"
        case .secondServeIn:
            return "of 2nd-serve points"
        case .doubleFaultsConceded, .returnWinFirst:
            return "of return points"
        case .unforcedErrors, .forcedErrorsConceded, .ownErrorShare:
            return "of points lost"
        case .unforcedErrorsDrawn, .forcedErrorsCaused, .winners, .aggressionIndex:
            return "of points won"
        case .winnersConceded:
            return "of points lost"
        case .wueRatio:
            return "winners to unforced errors"
        case .depthShareServe, .depthShareReturn, .depthShareServePlusOne, .depthShareRally:
            return "of points with a recorded ending shot"
        case .depthWinServe, .depthWinReturn, .depthWinServePlusOne, .depthWinRally:
            return "of points ending there"
        case .secondServeWin:
            return "of 2nd-serve points"
        case .returnWinSecond:
            return "of 2nd-serve return points"
        case .breakPointsConverted:
            return "of break-point opportunities"
        case .breakPointsSaved:
            return "of break points faced"
        case .bigPointWin:
            return "of big points"
        case .pointsWon:
            return "of all points"
        case .servedShareServe, .servedShareReturn, .servedShareServePlusOne, .servedShareRally:
            return "of my service points with a recorded ending shot"
        case .returnedShareServe, .returnedShareReturn, .returnedShareServePlusOne, .returnedShareRally:
            return "of return points with a recorded ending shot"
        case .winRateSet1:  return "of points in set 1"
        case .winRateSet2:  return "of points in set 2"
        case .winRateSet3:  return "of points in set 3"
        case .winRateDecidingTiebreak:
            return "of points in the deciding super tiebreak"
        case .stepsPerPointSet1: return "across set 1 points with a step sample"
        case .stepsPerPointSet2: return "across set 2 points with a step sample"
        case .stepsPerPointSet3: return "across set 3 points with a step sample"
        case .stepsPerPointDecidingTiebreak:
            return "across super-tiebreak points with a step sample"
        }
    }

    public var betterDirection: BetterDirection {
        switch self {
        case .doubleFaults, .unforcedErrors, .forcedErrorsConceded, .ownErrorShare, .winnersConceded:
            return .lower
        case .doubleFaultsConceded, .unforcedErrorsDrawn, .forcedErrorsCaused, .winners,
             .wueRatio, .aggressionIndex, .firstServeIn, .secondServeIn, .firstServeWin, .secondServeWin,
             .returnWinFirst, .returnWinSecond, .depthWinServe, .depthWinReturn,
             .depthWinServePlusOne, .depthWinRally, .breakPointsConverted, .breakPointsSaved,
             .bigPointWin, .pointsWon,
             .winRateSet1, .winRateSet2, .winRateSet3, .winRateDecidingTiebreak:
            return .higher
        case .depthShareServe, .depthShareReturn, .depthShareServePlusOne, .depthShareRally,
             // Where points END is a style, not a grade — on either side of
             // the serve. Per-set step load is likewise context: moving less
             // late is only bad if the win rate fell with it, which is the
             // chart above it.
             .servedShareServe, .servedShareReturn, .servedShareServePlusOne, .servedShareRally,
             .returnedShareServe, .returnedShareReturn, .returnedShareServePlusOne, .returnedShareRally,
             .stepsPerPointSet1, .stepsPerPointSet2, .stepsPerPointSet3,
             .stepsPerPointDecidingTiebreak:
            return .neutral
        }
    }

    public var unit: Unit {
        switch self {
        case .wueRatio:
            return .ratio
        case .stepsPerPointSet1, .stepsPerPointSet2, .stepsPerPointSet3,
             .stepsPerPointDecidingTiebreak:
            return .steps
        default:
            return .percent
        }
    }

    /// `false` for the ratio metric and the two share/index metrics whose
    /// numerator is not independently meaningful as a raw count. Everything
    /// else can render its numerator alone in the screen's Count mode.
    public var supportsCountMode: Bool {
        switch self {
        case .wueRatio, .aggressionIndex, .ownErrorShare,
             .depthShareServe, .depthShareReturn, .depthShareServePlusOne, .depthShareRally,
             .servedShareServe, .servedShareReturn, .servedShareServePlusOne, .servedShareRally,
             .returnedShareServe, .returnedShareReturn, .returnedShareServePlusOne, .returnedShareRally:
            return false
        default:
            return true
        }
    }

    /// The raw pair for this metric on one match, WITHOUT the empty-
    /// denominator guard. `nil` only when the sample lacks the coverage the
    /// metric needs at all (e.g. no ending-shot data for a rally-depth
    /// metric). Pooling sums these across a block — see `ratio(in:)` below
    /// for why pooling must use this accessor, never the plotting one.
    public func rawPair(in sample: MatchTrendSample) -> (numerator: Int, denominator: Int)? {
        switch self {
        case .doubleFaults:
            return (sample.doubleFaults, sample.categorizedServicePoints)
        case .doubleFaultsConceded:
            return (sample.opponentDoubleFaults, sample.categorizedOpponentServicePoints)
        case .unforcedErrors:
            return (sample.unforcedErrorsHit, sample.categorizedPointsLost)
        case .unforcedErrorsDrawn:
            return (sample.unforcedErrorsDrawn, sample.categorizedPointsWon)
        case .forcedErrorsConceded:
            return (sample.forcedErrorsConceded, sample.categorizedPointsLost)
        case .forcedErrorsCaused:
            return (sample.forcedErrorsCaused, sample.categorizedPointsWon)
        case .winners:
            return (sample.winnersHit, sample.categorizedPointsWon)
        case .winnersConceded:
            return (sample.winnersConceded, sample.categorizedPointsLost)
        case .wueRatio:
            return (sample.winnersHit, sample.unforcedErrorsHit)
        case .aggressionIndex:
            return (sample.winnersHit, sample.winnersHit + sample.unforcedErrorsHit)
        case .ownErrorShare:
            return (sample.doubleFaults + sample.unforcedErrorsHit, sample.categorizedPointsLost)
        case .depthShareServe:
            return depthSharePair(.serve, in: sample)
        case .depthShareReturn:
            return depthSharePair(.return, in: sample)
        case .depthShareServePlusOne:
            return depthSharePair(.servePlusOne, in: sample)
        case .depthShareRally:
            return depthSharePair(.rally, in: sample)
        case .depthWinServe:
            return depthWinPair(.serve, in: sample)
        case .depthWinReturn:
            return depthWinPair(.return, in: sample)
        case .depthWinServePlusOne:
            return depthWinPair(.servePlusOne, in: sample)
        case .depthWinRally:
            return depthWinPair(.rally, in: sample)
        case .firstServeIn:
            return (sample.firstServesIn, sample.servicePoints)
        case .secondServeIn:
            return (sample.secondServesIn, sample.secondServePoints)
        case .firstServeWin:
            return (sample.firstServeWins, sample.firstServesIn)
        case .secondServeWin:
            return (sample.secondServeWins, sample.secondServePoints)
        case .returnWinFirst:
            return (sample.returnWinsOnFirst, sample.returnPointsOnFirst)
        case .returnWinSecond:
            return (sample.returnWinsOnSecond, sample.returnPointsOnSecond)
        case .breakPointsConverted:
            return (sample.breakPointWins, sample.breakPointOpps)
        case .breakPointsSaved:
            return (sample.breakPointsFaced - sample.breakPointsLost, sample.breakPointsFaced)
        case .bigPointWin:
            return (sample.bigPointWins, sample.bigPointTotal)
        case .pointsWon:
            return (sample.pointsWon, sample.totalPoints)

        // The whole-match mix, partitioned by WHO SERVED. That split is on
        // `PointStat.server`, a different axis from `EndingShot` — `.serve` is
        // the phase a point ended in, so a point ending on the return shot is
        // still a point I served. `nil` (not zero) when that side carries no
        // ending-shot data, which is every match archived before
        // `PointStat.endingShot` existed.
        case .servedShareServe:         return servedSharePair(.serve, in: sample)
        case .servedShareReturn:        return servedSharePair(.return, in: sample)
        case .servedShareServePlusOne:  return servedSharePair(.servePlusOne, in: sample)
        case .servedShareRally:         return servedSharePair(.rally, in: sample)
        case .returnedShareServe:        return returnedSharePair(.serve, in: sample)
        case .returnedShareReturn:       return returnedSharePair(.return, in: sample)
        case .returnedShareServePlusOne: return returnedSharePair(.servePlusOne, in: sample)
        case .returnedShareRally:        return returnedSharePair(.rally, in: sample)

        // Fatigue, one series per set. Each set gates independently: a match
        // that only went two sets has no set-3 dot, and that gap is the honest
        // reading rather than missing data.
        case .winRateSet1: return winRatePair(sample.fullSetSlice(0))
        case .winRateSet2: return winRatePair(sample.fullSetSlice(1))
        case .winRateSet3: return winRatePair(sample.fullSetSlice(2))
        case .winRateDecidingTiebreak: return winRatePair(sample.decidingTiebreakSlice)
        case .stepsPerPointSet1: return setStepsPair(sample.fullSetSlice(0))
        case .stepsPerPointSet2: return setStepsPair(sample.fullSetSlice(1))
        case .stepsPerPointSet3: return setStepsPair(sample.fullSetSlice(2))
        case .stepsPerPointDecidingTiebreak: return setStepsPair(sample.decidingTiebreakSlice)
        }
    }

    /// Metrics that start hidden behind a legend tap: the opponent-framed
    /// counters, whose trend is one tap away rather than the headline.
    public var startsHidden: Bool { isOpponentFramed }

    /// The metric counts something that happened to/because of the OPPONENT
    /// rather than the recorder's own shot.
    public var isOpponentFramed: Bool {
        switch self {
        case .doubleFaultsConceded, .unforcedErrorsDrawn, .forcedErrorsCaused, .winnersConceded:
            return true
        default:
            return false
        }
    }

    // MARK: - Health coverage gates

    /// Fewest samples a set needs before its step figure is worth plotting.
    public static let minimumFatigueSamples = 5
    /// Fewest points a FULL set must contain to be plotted. Same number
    /// `RecCoachInsights`' set-duration decline rule requires
    /// (RecCoachInsights.swift:277) — one threshold, cited rather than
    /// re-invented.
    public static let minimumFullSetPoints = 20
    /// The same bar for a deciding super-tiebreak, which is a complete set at
    /// around a dozen points. Holding it to the full-set minimum would silently
    /// drop the decider from every `.standard` three-setter — the format the app
    /// defaults to.
    public static let minimumTiebreakPoints = 10

    /// A set's win rate, gated on the point count appropriate to its kind.
    private func winRatePair(_ slice: MatchTrendSample.SetSlice?) -> (Int, Int)? {
        guard let slice else { return nil }
        let minimum = slice.isDecidingTiebreak ? Self.minimumTiebreakPoints : Self.minimumFullSetPoints
        guard slice.points >= minimum else { return nil }
        return (slice.pointsWon, slice.points)
    }

    /// A set's steps per point. Gated on step SAMPLES, not on the set's point
    /// count — the two denominators are different things.
    private func setStepsPair(_ slice: MatchTrendSample.SetSlice?) -> (Int, Int)? {
        guard let slice, slice.stepSampledPoints >= Self.minimumFatigueSamples else { return nil }
        return (slice.stepSumLoad, slice.stepSampledPoints)
    }

    private func depthSharePair(_ shot: EndingShot, in sample: MatchTrendSample) -> (Int, Int)? {
        guard sample.pointsWithEndingShot > 0 else { return nil }
        let count = sample.rallyDepth[shot]?.total ?? 0
        return (count, sample.pointsWithEndingShot)
    }

    private func depthWinPair(_ shot: EndingShot, in sample: MatchTrendSample) -> (Int, Int)? {
        guard let depth = sample.rallyDepth[shot] else { return nil }
        return (depth.wins, depth.total)
    }

    /// Mirrors `depthSharePair`, scoped to the points the recorder served.
    private func servedSharePair(_ shot: EndingShot, in sample: MatchTrendSample) -> (Int, Int)? {
        guard sample.pointsWithEndingShotOnServe > 0 else { return nil }
        return (sample.rallyDepthOnServe[shot]?.total ?? 0, sample.pointsWithEndingShotOnServe)
    }

    /// Mirrors `depthSharePair`, scoped to the points the opponent served.
    private func returnedSharePair(_ shot: EndingShot, in sample: MatchTrendSample) -> (Int, Int)? {
        guard sample.pointsWithEndingShotOnReturn > 0 else { return nil }
        return (sample.rallyDepthOnReturn[shot]?.total ?? 0, sample.pointsWithEndingShotOnReturn)
    }

    /// One match's plottable value: `rawPair` plus the empty-denominator
    /// guard, so a 0-denominator match yields no dot (§3.4). Never use this
    /// for pooling — it would discard the numerator of a zero-denominator
    /// match (e.g. a flawless 10-winner, 0-UE match has no `wueRatio` dot,
    /// but its 10 winners must still enter a pooled block; §3.3, §4.2).
    public func ratio(in sample: MatchTrendSample) -> Ratio? {
        guard let pair = rawPair(in: sample), pair.denominator > 0 else { return nil }
        return Ratio(numerator: pair.numerator, denominator: pair.denominator)
    }

    public static func metrics(in group: TrendMetricGroup) -> [TrendMetric] {
        allCases.filter { $0.group == group }
    }

    /// The four rows on the archive screen (§1.1).
    public static let headline: [TrendMetric] = [.doubleFaults, .unforcedErrors, .winners, .wueRatio]
}
