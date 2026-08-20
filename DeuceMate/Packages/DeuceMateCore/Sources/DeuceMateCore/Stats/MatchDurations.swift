// MatchDurations.swift — canonical duration resolution for a match and its
// sets, plus the minute-granularity strings every surface renders.
//
// The fallback rule matters: a set's duration is the value the watch recorded
// while playing it, and only when that is missing is it derived from the span
// between the set's first and last categorised point. Four surfaces (iOS
// MatchDetailView, watch MatchStatsView, text export, web export) each carried
// their own copy of that rule.
import Foundation

public enum MatchDurations {

    /// Seconds elapsed in `setIndex`, or `nil` when neither a recorded value nor
    /// any point of that set exists.
    public static func setElapsedSeconds(
        setIndex: Int,
        stats: [PointStat],
        stored: [Int: TimeInterval]
    ) -> TimeInterval? {
        if let recorded = stored[setIndex] { return recorded }
        let timestamps = stats.filter { $0.setIndex == setIndex }.map(\.timestamp)
        guard let first = timestamps.min(), let last = timestamps.max() else { return nil }
        return last.timeIntervalSince(first)
    }

    public static func setElapsedSeconds(_ record: MatchRecord, setIndex: Int) -> TimeInterval? {
        setElapsedSeconds(setIndex: setIndex, stats: record.stats, stored: record.setElapsedSeconds)
    }

    /// Whole-match seconds: the recorded elapsed time when the watch kept one,
    /// otherwise the start→end span. `nil` while a match is still in progress
    /// without a recorded elapsed time.
    public static func matchElapsedSeconds(_ record: MatchRecord) -> TimeInterval? {
        if record.matchElapsedSeconds > 0 { return record.matchElapsedSeconds }
        if let end = record.endTime { return end.timeIntervalSince(record.startTime) }
        return nil
    }

    /// "42 min" — minutes, truncated. The watch passes `unit: "m"` to fit.
    public static func minutesString(_ seconds: TimeInterval, unit: String = "min") -> String {
        "\(Int(seconds) / 60) \(unit)"
    }

    /// "3 m 7 s" live counter — minutes plus the remaining seconds.
    public static func minutesSecondsString(
        _ seconds: TimeInterval,
        minuteUnit: String = "m",
        secondUnit: String = "s"
    ) -> String {
        let total = max(0, Int(seconds))
        return "\(total / 60) \(minuteUnit) \(total % 60) \(secondUnit)"
    }
}
