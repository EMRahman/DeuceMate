// GamePlanText.swift — small, deterministic labels shared by the game plan
// pack builder and the iPhone preparation screen.
import Foundation

public enum GamePlanText {

    /// "Best of 3", "Super Tiebreak", … — the same names the archive uses.
    public static func formatLabel(_ format: MatchFormat) -> String {
        switch format {
        case .standard:               return "Best of 3"
        case .bestOf3FullFinalSet:    return "Best of 3 (Full Final Set)"
        case .superTiebreak:          return "Super Tiebreak"
        case .perpetualSuperTiebreak: return "Perpetual Tiebreak"
        case .quick4Games:            return "Quick 4 Games"
        case .perpetualPoints:        return "Perpetual Points"
        }
    }

    /// Formats offered for the upcoming match, in picker order.
    public static let selectableFormats: [MatchFormat] = [
        .standard, .bestOf3FullFinalSet, .superTiebreak, .perpetualSuperTiebreak, .quick4Games, .perpetualPoints
    ]

    /// "2026-10-03" in `timeZone` — unambiguous for any reader or AI.
    public static func day(_ date: Date, timeZone: TimeZone) -> String {
        formatter("yyyy-MM-dd", timeZone).string(from: date)
    }

    /// "2026-10-03 18:30".
    public static func dayTime(_ date: Date, timeZone: TimeZone) -> String {
        formatter("yyyy-MM-dd HH:mm", timeZone).string(from: date)
    }

    /// "2026-03-01 to 2026-10-03", one day when both match, or "—".
    public static func dateRange(_ first: Date?, _ last: Date?, timeZone: TimeZone) -> String {
        guard let first, let last else { return "—" }
        let a = day(first, timeZone: timeZone), b = day(last, timeZone: timeZone)
        return a == b ? a : "\(a) to \(b)"
    }

    /// "62% — 31/50", or "Not recorded".
    public static func ratio(_ ratio: TrendMetric.Ratio?) -> String {
        MatchComparisonFormat.ratio(ratio)
    }

    /// "62% — 31/50" when every match in scope recorded the figure, else
    /// "62% — 31/50 (4 of 5 matches)" / "Not recorded (0 of 5 matches)".
    public static func pooled(_ value: GamePlanPooledValue) -> String {
        let base = ratio(value.ratio)
        guard value.contributingMatches < value.matchesInScope else { return base }
        return "\(base) (\(value.contributingMatches) of \(value.matchesInScope) \(value.matchesInScope == 1 ? "match" : "matches"))"
    }

    /// The pack's own figure names, each stating exactly what it divides by
    /// (the serve/return splits count only points with a recorded outcome).
    public static func figureLabel(_ metric: TrendMetric) -> String {
        switch metric {
        case .pointsWon:            return "Points won (of all saved points)"
        case .firstServeIn:         return "1st serve in (of service points with an outcome)"
        case .firstServeWin:        return "Won on 1st serve (of 1st serves in)"
        case .secondServeWin:       return "Won on 2nd serve (of 2nd-serve points with an outcome)"
        case .doubleFaults:         return "Double faults (of service points with an outcome)"
        case .returnWinFirst:       return "Return won vs 1st serve (of those return points with an outcome)"
        case .returnWinSecond:      return "Return won vs 2nd serve (of those return points with an outcome)"
        case .breakPointsConverted: return "Break points converted (of break-point chances)"
        case .breakPointsSaved:     return "Break points saved (of break points faced)"
        case .bigPointWin:          return "Big points won (break points, deuce/ad and tiebreak points)"
        case .winners:              return "Winners hit (of points won with an outcome)"
        case .unforcedErrors:       return "Unforced errors made (of points lost with an outcome)"
        case .forcedErrorsConceded: return "Forced errors made (of points lost with an outcome)"
        case .depthShareServe:      return "Points ending in the Serve phase (of phase-recorded points)"
        case .depthShareReturn:     return "Points ending in the Return phase (of phase-recorded points)"
        case .depthShareServePlusOne: return "Points ending in the S+1 phase (of phase-recorded points)"
        case .depthShareRally:      return "Points ending in the Rally phase (of phase-recorded points)"
        case .depthWinServe:        return "Won when ending in the Serve phase"
        case .depthWinReturn:       return "Won when ending in the Return phase"
        case .depthWinServePlusOne: return "Won when ending in the S+1 phase"
        case .depthWinRally:        return "Won when ending in the Rally phase"
        default:                    return "\(metric.displayLabel) (\(metric.denominatorLabel))"
        }
    }

    /// Short dossier row names; section 3 carries the full definitions.
    public static func shortFigureLabel(_ metric: TrendMetric) -> String {
        switch metric {
        case .pointsWon:            return "Points won"
        case .firstServeIn:         return "1st serve in"
        case .firstServeWin:        return "Won on 1st serve"
        case .secondServeWin:       return "Won on 2nd serve"
        case .doubleFaults:         return "Double faults"
        case .returnWinFirst:       return "Return won vs 1st"
        case .returnWinSecond:      return "Return won vs 2nd"
        case .breakPointsConverted: return "Break points converted"
        case .breakPointsSaved:     return "Break points saved"
        case .bigPointWin:          return "Big points won"
        case .winners:              return "Winners hit"
        case .unforcedErrors:       return "Unforced errors made"
        case .forcedErrorsConceded: return "Forced errors made"
        case .depthShareServe:      return "Ending in Serve"
        case .depthShareReturn:     return "Ending in Return"
        case .depthShareServePlusOne: return "Ending in S+1"
        case .depthShareRally:      return "Ending in Rally"
        case .depthWinServe:        return "Won in Serve"
        case .depthWinReturn:       return "Won in Return"
        case .depthWinServePlusOne: return "Won in S+1"
        case .depthWinRally:        return "Won in Rally"
        default:                    return metric.displayLabel
        }
    }

    /// "3 W · 2 L" plus draws when any.
    public static func tally(_ record: HeadToHeadRecord) -> String {
        guard record.played > 0 else { return "no completed results" }
        var parts = ["\(record.wins) W", "\(record.losses) L"]
        if record.draws > 0 { parts.append("\(record.draws) D") }
        return parts.joined(separator: " · ")
    }

    public static func plural(_ count: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(count) \(count == 1 ? singular : (plural ?? singular + "s"))"
    }

    public static func percent(_ numerator: Int, of denominator: Int) -> String {
        guard denominator > 0 else { return "—" }
        return "\(Int((Double(numerator) / Double(denominator) * 100).rounded()))%"
    }

    static func outcomeLabel(_ outcome: PointOutcome) -> String {
        switch outcome {
        case .winner:        return "Winner"
        case .unforcedError: return "UE"
        case .forcedError:   return "FE"
        case .doubleFault:   return "DF"
        case .uncategorized: return "—"
        }
    }

    static func phaseLabel(_ shot: EndingShot?) -> String {
        guard let shot else { return "—" }
        switch shot {
        case .serve:        return "Serve"
        case .return:       return "Return"
        case .servePlusOne: return "S+1"
        case .rally:        return "Rally"
        }
    }

    static func side(_ player: Player) -> String { player == .me ? "Me" : "Opp" }

    private static func formatter(_ pattern: String, _ timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = timeZone
        f.dateFormat = pattern
        return f
    }
}
