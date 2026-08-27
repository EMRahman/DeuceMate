// TrendMetric.swift — the cross-match metric catalogue. Adding a metric is
// one case plus one switch arm plus one test, the same data-driven shape
// MatchFormatConfig uses for match formats. Platform-neutral: no SwiftUI.
// See docs/features/PERFORMANCE_TRENDS_PLAN.md §4 and §5.2.
import Foundation

/// The grouped sections a `TrendMetric` belongs to, matching the Trends
/// screen's layout (§6.2).
public enum TrendMetricGroup: String, CaseIterable, Identifiable, Sendable {
    case errors, attack, rallyDepth, serveReturn, pressure
    case heartRate, movement, fatigue

    public var id: String { rawValue }

    public var displayLabel: String {
        switch self {
        case .errors:      return "Errors"
        case .attack:      return "Attack"
        case .rallyDepth:  return "Rally Depth"
        case .serveReturn: return "Serve & Return"
        case .pressure:    return "Pressure"
        case .heartRate:   return "Heart Rate"
        case .movement:    return "Movement"
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
    case avgHeartRate, hardZoneShare, hardZoneWinRate
    case stepsPerPoint, stepsPerPointWon, metresPerPoint, minutesPerMatch
    case winRateFirstSet, winRateFinalSet
    case avgHeartRateFirstSet, avgHeartRateFinalSet
    case stepsPerPointFirstSet, stepsPerPointFinalSet

    public var id: String { rawValue }

    /// How a metric's raw pair should be printed: as a percent, or as a bare
    /// ratio (W:UE only — plotting `Double.infinity` would destroy a chart's
    /// Y domain for the whole series, so it is never percent-formatted).
    /// `.percent` and `.ratio` describe a share; the rest name a real unit,
    /// which is what makes them un-poolable onto one Y axis with the others —
    /// `TrendChart` buckets its series by this value for exactly that reason.
    public enum Unit: Hashable, Sendable { case percent, ratio, bpm, steps, metres, minutes }

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
        case .avgHeartRate, .hardZoneShare, .hardZoneWinRate:
            return .heartRate
        case .stepsPerPoint, .stepsPerPointWon, .metresPerPoint, .minutesPerMatch:
            return .movement
        case .winRateFirstSet, .winRateFinalSet, .avgHeartRateFirstSet, .avgHeartRateFinalSet,
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
        case .avgHeartRate:            return "Avg Heart Rate"
        case .hardZoneShare:           return "Time in Z4–Z5"
        case .hardZoneWinRate:         return "Win Rate in Z4–Z5"
        case .stepsPerPoint:           return "Steps per Point"
        case .stepsPerPointWon:        return "Steps per Point Won"
        case .metresPerPoint:          return "Metres per Point"
        case .minutesPerMatch:         return "Minutes per Match"
        case .winRateFirstSet:         return "Points Won — First Set"
        case .winRateFinalSet:         return "Points Won — Final Set"
        case .avgHeartRateFirstSet:    return "Avg HR — First Set"
        case .avgHeartRateFinalSet:    return "Avg HR — Final Set"
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
        case .avgHeartRate:
            return "across points with a heart-rate reading"
        case .hardZoneShare:
            return "of points with a heart-rate reading"
        case .hardZoneWinRate:
            return "of points in Z4–Z5"
        case .stepsPerPoint:
            return "across points with a step sample"
        case .stepsPerPointWon:
            return "for each point won"
        case .metresPerPoint:
            return "across all points"
        case .minutesPerMatch:
            return "per match"
        case .winRateFirstSet:
            return "of points in the first set"
        case .winRateFinalSet:
            return "of points in the final set"
        case .avgHeartRateFirstSet:
            return "across first-set points with a heart-rate reading"
        case .avgHeartRateFinalSet:
            return "across final-set points with a heart-rate reading"
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
             .bigPointWin, .pointsWon, .hardZoneWinRate, .winRateFirstSet, .winRateFinalSet:
            return .higher
        case .depthShareServe, .depthShareReturn, .depthShareServePlusOne, .depthShareRally,
             // Effort and load are context, not achievement: running more is
             // neither good nor bad without knowing what it bought. Only
             // `stepsPerPointWon` — cost per point actually won — is oriented.
             .avgHeartRate, .hardZoneShare, .stepsPerPoint, .metresPerPoint, .minutesPerMatch,
             .avgHeartRateFirstSet, .avgHeartRateFinalSet,
             .stepsPerPointFirstSet, .stepsPerPointFinalSet:
            return .neutral
        }
    }

    public var unit: Unit {
        switch self {
        case .wueRatio:
            return .ratio
        case .avgHeartRate, .avgHeartRateFirstSet, .avgHeartRateFinalSet:
            return .bpm
        case .stepsPerPoint, .stepsPerPointWon, .stepsPerPointFirstSet, .stepsPerPointFinalSet:
            return .steps
        case .metresPerPoint:
            return .metres
        case .minutesPerMatch:
            return .minutes
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
             // A summed bpm is not a quantity anyone wants plotted, and
             // `stepsPerPointWon`'s numerator is the same match step load
             // `stepsPerPoint` already draws — it would duplicate that line.
             .avgHeartRate, .avgHeartRateFirstSet, .avgHeartRateFinalSet,
             .hardZoneShare, .stepsPerPointWon,
             // Denominator 1: the "count" and the rate are the same number.
             .minutesPerMatch:
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

        // Health-derived metrics. Every one of these returns `nil` — never a
        // zero pair — when the match lacks the sampling the metric needs, so a
        // match recorded with Health access off leaves a visible gap instead of
        // a dot on the floor (PERFORMANCE_TRENDS_PLAN.md §3.4).
        case .avgHeartRate:
            guard sample.hrSampledPoints >= Self.minimumHRSamples else { return nil }
            return (sample.hrSumBPM, sample.hrSampledPoints)
        case .hardZoneShare:
            guard sample.hrSampledPoints >= Self.minimumHRSamples else { return nil }
            return (sample.hardZonePoints, sample.hrSampledPoints)
        case .hardZoneWinRate:
            // BOTH gates: without the sample-count one, a match with 6 HR
            // readings that all happen to be Z5 plots a win rate while its two
            // sibling metrics correctly refuse — and the section footer, which
            // counts `minimumHRSamples` coverage, says the window has no
            // heart-rate data at all.
            guard sample.hrSampledPoints >= Self.minimumHRSamples,
                  sample.hardZonePoints >= Self.minimumHardZonePoints else { return nil }
            return (sample.hardZoneWins, sample.hardZonePoints)
        case .stepsPerPoint:
            guard sample.stepSampledPoints >= Self.minimumStepSamples else { return nil }
            return (sample.stepSumLoad, sample.stepSampledPoints)
        case .stepsPerPointWon:
            // `stepSampledPointsWon`, NOT `pointsWon`: the numerator covers only
            // the sampled window, so a full-match denominator would make the
            // rate fall as step coverage falls — and this metric is oriented
            // `.lower`, so that reads as a fitness gain.
            guard sample.stepSampledPoints >= Self.minimumStepSamples,
                  sample.stepSampledPointsWon > 0 else { return nil }
            return (sample.stepSumLoad, sample.stepSampledPointsWon)
        case .metresPerPoint:
            guard let metres = sample.distanceMetres, sample.totalPoints > 0 else { return nil }
            return (metres, sample.totalPoints)
        case .minutesPerMatch:
            guard let minutes = sample.elapsedMinutes else { return nil }
            // Denominator 1: pooling a block then reduces to the mean match
            // length, which is the figure this metric is asking for.
            return (minutes, 1)

        // Fatigue pairs. Each checks BOTH slices before returning either, so a
        // set that lacks the sampling can never leave its partner drawn alone —
        // one line of a two-line comparison reads as a complete answer.
        case .winRateFirstSet, .winRateFinalSet:
            guard let split = sample.fatigue else { return nil }
            let slice = self == .winRateFirstSet ? split.firstSet : split.finalSet
            return (slice.pointsWon, slice.points)
        case .avgHeartRateFirstSet, .avgHeartRateFinalSet:
            guard let split = sample.fatigue,
                  split.firstSet.hrSampledPoints >= Self.minimumFatigueSamples,
                  split.finalSet.hrSampledPoints >= Self.minimumFatigueSamples else { return nil }
            let slice = self == .avgHeartRateFirstSet ? split.firstSet : split.finalSet
            return (slice.hrSumBPM, slice.hrSampledPoints)
        case .stepsPerPointFirstSet, .stepsPerPointFinalSet:
            guard let split = sample.fatigue,
                  split.firstSet.stepSampledPoints >= Self.minimumFatigueSamples,
                  split.finalSet.stepSampledPoints >= Self.minimumFatigueSamples else { return nil }
            let slice = self == .stepsPerPointFirstSet ? split.firstSet : split.finalSet
            return (slice.stepSumLoad, slice.stepSampledPoints)
        }
    }

    // MARK: - Health coverage gates

    /// Fewest heart-rate samples a match needs before its HR metrics mean
    /// anything. Same bar `PulseCoachInsights.generate` sets before it will say
    /// a word about heart rate (PulseCoachInsights.swift:19).
    public static let minimumHRSamples = 10
    /// Fewest Z4+Z5 points before a win rate over them is worth plotting.
    public static let minimumHardZonePoints = 5
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
