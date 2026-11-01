// MatchComparisonFormat.swift — display strings for the "Compare with previous
// match" screen and the match-detail head-to-head line. Pure and
// platform-neutral so the wording is tested once, and so PR 4's AI prompt can
// reuse the exact same head-to-head summary the user sees on screen
// (MATCH_TAGS_PLAN.md §7.1: "Keep the AI head-to-head scope identical").
import Foundation

public enum MatchComparisonFormat {

    /// Shown for a metric a match did not record — a gap, never "0%".
    public static let notRecorded = "Not recorded"

    /// "60% — 12/20", or "Not recorded" for `nil`. Rounded to a whole percent.
    public static func ratio(_ ratio: TrendMetric.Ratio?) -> String {
        guard let ratio, ratio.denominator > 0 else { return notRecorded }
        let percent = Int((ratio.value * 100).rounded())
        return "\(percent)% — \(ratio.numerator)/\(ratio.denominator)"
    }

    /// "+5 pts" / "−3 pts" / "±0 pts" (percentage points, rounded), or `nil`
    /// when either side was not recorded.
    public static func change(_ percentagePoints: Double?) -> String? {
        guard let percentagePoints else { return nil }
        let rounded = Int(percentagePoints.rounded())
        if rounded > 0 { return "+\(rounded) pts" }
        if rounded < 0 { return "\u{2212}\(abs(rounded)) pts" }
        return "\u{00B1}0 pts"
    }

    /// "1 h 05 min" / "48 min" / "< 1 min" (never a misleading "0 min"), or
    /// "Not recorded".
    public static func duration(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds > 0 else { return notRecorded }
        let minutes = Int(seconds) / 60
        if minutes == 0 { return "< 1 min" }
        if minutes >= 60 {
            return String(format: "%d h %02d min", minutes / 60, minutes % 60)
        }
        return "\(minutes) min"
    }

    /// "Won" / "Lost" / "Draw", or "In progress" for a partial side — never
    /// an inferred result.
    public static func result(_ side: MatchComparison.Side) -> String {
        guard let result = side.result else { return "In progress" }
        switch result {
        case .win:  return "Won"
        case .loss: return "Lost"
        case .draw: return "Draw"
        }
    }

    /// Point-tracking coverage for one side: "Score only" (no point data),
    /// "40 points · no outcomes" or "40 points · outcomes on 75%".
    public static func coverage(_ side: MatchComparison.Side) -> String {
        guard side.hasPointData else { return "Score only" }
        let points = side.pointsTracked == 1 ? "1 point" : "\(side.pointsTracked) points"
        guard let coverage = side.outcomeCoverage, side.hasOutcomeTracking else {
            return "\(points) · no outcomes"
        }
        return "\(points) · outcomes on \(Int((coverage * 100).rounded()))%"
    }

    /// Completed-only head-to-head: "3–2 in 5 matches · last 3: W W L".
    /// Draws appear only when there are any ("3–2–1 in 6 matches"). The form
    /// guide shows at most `recentCount` results, newest first. Empty record ⇒
    /// "No completed matches yet".
    public static func headToHeadSummary(_ record: HeadToHeadRecord, recentCount: Int = 5) -> String {
        guard record.played > 0 else { return "No completed matches yet" }
        var tally = "\(record.wins)\u{2013}\(record.losses)"
        if record.draws > 0 { tally += "\u{2013}\(record.draws)" }
        let matches = record.played == 1 ? "1 match" : "\(record.played) matches"
        let recent = record.recentResults.prefix(max(0, recentCount))
        guard !recent.isEmpty else { return "\(tally) in \(matches)" }
        let form = recent.map(\.shortLabel).joined(separator: " ")
        return "\(tally) in \(matches) · last \(recent.count): \(form)"
    }
}
