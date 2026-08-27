// TrendMetric.swift — the cross-match metric catalogue. Adding a metric is
// one case plus one switch arm plus one test, the same data-driven shape
// MatchFormatConfig uses for match formats. Platform-neutral: no SwiftUI.
// See docs/features/PERFORMANCE_TRENDS_PLAN.md §4 and §5.2.
import Foundation

/// The grouped sections a `TrendMetric` belongs to, matching the Trends
/// screen's layout (§6.2).
public enum TrendMetricGroup: String, CaseIterable, Identifiable, Sendable {
    case errors, attack, rallyDepth, serveReturn, pressure
    case effort, fatigue

    public var id: String { rawValue }

    public var displayLabel: String {
        switch self {
        case .errors:      return "Errors"
        case .attack:      return "Attack"
        case .rallyDepth:  return "Rally Depth"
        case .serveReturn: return "Serve & Return"
        case .pressure:    return "Pressure"
        case .effort:      return "Effort"
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
    case rallyShareOnServe, rallyShareOnReturn, rallyWinOnServe, rallyWinOnReturn
    case stepsPerPointWon
    case winRateFirstSet, winRateFinalSet
    case stepsPerPointFirstSet, stepsPerPointFinalSet

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
        case .rallyShareOnServe, .rallyShareOnReturn, .rallyWinOnServe, .rallyWinOnReturn:
            return .rallyDepth
        case .stepsPerPointWon:
            return .effort
        case .winRateFirstSet, .winRateFinalSet,
             .stepsPerPointFirstSet, .stepsPerPointFinalSet:
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
        case .rallyShareOnServe:       return "Rallies — On My Serve"
        case .rallyShareOnReturn:      return "Rallies — On Return"
        case .rallyWinOnServe:         return "Rally Win — On My Serve"
        case .rallyWinOnReturn:        return "Rally Win — On Return"
        case .stepsPerPointWon:        return "Steps per Point Won"
        case .winRateFirstSet:         return "Points Won — First Set"
        case .winRateFinalSet:         return "Points Won — Final Set"
        case .stepsPerPointFirstSet:   return "Steps/Point — First Set"
        case .stepsPerPointFinalSet:   return "Steps/Point — Final Set"
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
        case .rallyShareOnServe:
            return "of my service points with a recorded ending shot"
        case .rallyShareOnReturn:
            return "of return points with a recorded ending shot"
        case .rallyWinOnServe:
            return "of rallies on my serve"
        case .rallyWinOnReturn:
            return "of rallies on return"
        case .stepsPerPointWon:
            return "for each point won"
        case .winRateFirstSet:
            return "of points in the first set"
        case .winRateFinalSet:
            return "of points in the final set"
        case .stepsPerPointFirstSet:
            return "across first-set points with a step sample"
        case .stepsPerPointFinalSet:
            return "across final-set points with a step sample"
        }
    }

    public var betterDirection: BetterDirection {
        switch self {
        case .doubleFaults, .unforcedErrors, .forcedErrorsConceded, .ownErrorShare, .winnersConceded,
             .stepsPerPointWon:
            return .lower
        case .doubleFaultsConceded, .unforcedErrorsDrawn, .forcedErrorsCaused, .winners,
             .wueRatio, .aggressionIndex, .firstServeIn, .secondServeIn, .firstServeWin, .secondServeWin,
             .returnWinFirst, .returnWinSecond, .depthWinServe, .depthWinReturn,
             .depthWinServePlusOne, .depthWinRally, .breakPointsConverted, .breakPointsSaved,
             .bigPointWin, .pointsWon, .winRateFirstSet, .winRateFinalSet,
             .rallyWinOnServe, .rallyWinOnReturn:
            return .higher
        case .depthShareServe, .depthShareReturn, .depthShareServePlusOne, .depthShareRally,
             // How often points reach a rally is a style, not a grade — the
             // paired win rate is what says whether that style pays. Per-set
             // step load is likewise context: moving less late is only bad if
             // the win rate fell with it, which is the chart above it.
             .rallyShareOnServe, .rallyShareOnReturn,
             .stepsPerPointFirstSet, .stepsPerPointFinalSet:
            return .neutral
        }
    }

    public var unit: Unit {
        switch self {
        case .wueRatio:
            return .ratio
        case .stepsPerPointWon, .stepsPerPointFirstSet, .stepsPerPointFinalSet:
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
             .rallyShareOnServe, .rallyShareOnReturn:
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

        // Rally length by SERVING SIDE. The split is on who served, which is a
        // different axis from `EndingShot` — `.serve` is the phase a point
        // ended in, so a point ending on the return shot is still a point I
        // served. `nil` (not zero) when that side carries no ending-shot data,
        // which is every match archived before `PointStat.endingShot` existed.
        case .rallyShareOnServe:
            guard sample.pointsWithEndingShotOnServe > 0 else { return nil }
            return (sample.rallyDepthOnServe[.rally]?.total ?? 0, sample.pointsWithEndingShotOnServe)
        case .rallyShareOnReturn:
            guard sample.pointsWithEndingShotOnReturn > 0 else { return nil }
            return (sample.rallyDepthOnReturn[.rally]?.total ?? 0, sample.pointsWithEndingShotOnReturn)
        case .rallyWinOnServe:
            guard let depth = sample.rallyDepthOnServe[.rally] else { return nil }
            return (depth.wins, depth.total)
        case .rallyWinOnReturn:
            guard let depth = sample.rallyDepthOnReturn[.rally] else { return nil }
            return (depth.wins, depth.total)

        // Movement. `nil` — never a zero pair — when the match lacks the step
        // sampling the metric needs, so a match recorded with Health access off
        // leaves a visible gap (PERFORMANCE_TRENDS_PLAN.md §3.4).
        case .stepsPerPointWon:
            // `stepSampledPointsWon`, NOT `pointsWon`: the numerator covers only
            // the sampled window, so a full-match denominator would make the
            // rate fall as step coverage falls — and this metric is oriented
            // `.lower`, so that reads as a fitness gain.
            guard sample.stepSampledPoints >= Self.minimumStepSamples,
                  sample.stepSampledPointsWon > 0 else { return nil }
            return (sample.stepSumLoad, sample.stepSampledPointsWon)

        // Fatigue pairs. Each checks BOTH slices before returning either, so a
        // set that lacks the sampling can never leave its partner drawn alone —
        // one line of a two-line comparison reads as a complete answer.
        case .winRateFirstSet, .winRateFinalSet:
            guard let split = sample.fatigue else { return nil }
            let slice = self == .winRateFirstSet ? split.firstSet : split.finalSet
            return (slice.pointsWon, slice.points)
        case .stepsPerPointFirstSet, .stepsPerPointFinalSet:
            guard let split = sample.fatigue,
                  split.firstSet.stepSampledPoints >= Self.minimumFatigueSamples,
                  split.finalSet.stepSampledPoints >= Self.minimumFatigueSamples else { return nil }
            let slice = self == .stepsPerPointFirstSet ? split.firstSet : split.finalSet
            return (slice.stepSumLoad, slice.stepSampledPoints)
        }
    }

    /// Metrics that start hidden behind a legend tap. Two families: the
    /// opponent-framed counters (their trend is one tap away, not the headline),
    /// and the rally SHARE lines, whose paired win rates carry the actionable
    /// half of the same question.
    public var startsHidden: Bool {
        isOpponentFramed || self == .rallyShareOnServe || self == .rallyShareOnReturn
    }

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

    /// Fewest sampled step points, matching `StepsCoachInsights`' own
    /// `timeline.count >= 10`.
    public static let minimumStepSamples = 10
    /// Fewest samples in EACH of the two compared sets, per family.
    public static let minimumFatigueSamples = 5

    private func depthSharePair(_ shot: EndingShot, in sample: MatchTrendSample) -> (Int, Int)? {
        guard sample.pointsWithEndingShot > 0 else { return nil }
        let count = sample.rallyDepth[shot]?.total ?? 0
        return (count, sample.pointsWithEndingShot)
    }

    private func depthWinPair(_ shot: EndingShot, in sample: MatchTrendSample) -> (Int, Int)? {
        guard let depth = sample.rallyDepth[shot] else { return nil }
        return (depth.wins, depth.total)
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
