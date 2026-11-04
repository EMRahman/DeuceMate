import Foundation

/// Shared interruption descriptions and conservative sample windows. Session
/// timestamps describe observed app actions, not the precise start/stop of rallies.
public enum MatchSessions {
    public static func descriptions(_ record: MatchRecord, formatter: DateFormatter) -> [String] {
        guard !record.resumeEvents.isEmpty else { return [] }
        var lines = ["Started \(formatter.string(from: record.startTime))"]
        for event in MatchResumeEvent.merged([], record.resumeEvents) {
            let pause = event.pausedAt.map { "Parked \(formatter.string(from: $0)); " } ?? ""
            let duration = event.breakDuration.map { "Break: \(breakDescription($0))" } ?? "Break duration unknown"
            lines.append("\(pause)Resumed \(formatter.string(from: event.resumedAt)) · \(duration)")
        }
        if let parked = record.parkedAt { lines.append("Parked \(formatter.string(from: parked))") }
        if let end = record.endTime { lines.append("Finished \(formatter.string(from: end))") }
        if record.matchElapsedSeconds > 0 {
            lines.append("Recorded play time: \(MatchDurations.minutesString(record.matchElapsedSeconds))")
        }
        return lines
    }

    public static func breakDescription(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration))
        if seconds >= 86400 { let n = seconds / 86400; return "\(n) \(n == 1 ? "day" : "days")" }
        if seconds >= 3600 { let n = seconds / 3600; return "\(n) \(n == 1 ? "hour" : "hours")" }
        if seconds >= 60 { return "\(seconds / 60) min" }
        return "\(seconds) sec"
    }

    /// Per-point query intervals in original play order. Unknown parks and
    /// unresolved anchors disable querying the preceding session rather than
    /// sweeping unrelated samples into it. Callers use stored snapshots there.
    public static func heartRateWindows(_ record: MatchRecord) -> [DateInterval?] {
        let markers = ResumeMarkers.derive(record)
        if markers.contains(where: { $0.beforePointIndex == nil }) {
            return Array(repeating: nil, count: record.stats.count)
        }
        let sessions = ResumeMarkers.sessionIndices(events: record.resumeEvents, points: record.stats)
        let ordered = markers.sorted {
            let left = $0.beforePointIndex ?? Int.max, right = $1.beforePointIndex ?? Int.max
            return left != right ? left < right : $0.event.resumedAt < $1.event.resumedAt
        }
        var previous: [Int: Date] = [:]
        return record.stats.enumerated().map { index, point in
            let session = sessions[index]
            let start = session > 0 ? ordered[session - 1].event.resumedAt : record.startTime
            let next = session < ordered.count ? ordered[session].event : nil
            // The previous session's end is unknowable for a legacy resume.
            if let next, next.breakDuration == nil { return nil }
            let end = next?.pausedAt ?? record.parkedAt ?? record.endTime ?? record.stats.last?.timestamp ?? point.timestamp
            let lower = max(start, previous[session] ?? start)
            previous[session] = point.timestamp
            guard end >= start, point.timestamp >= start, point.timestamp <= end, point.timestamp > lower else { return nil }
            return DateInterval(start: lower, end: point.timestamp)
        }
    }

    public struct HeartRatePoint: Equatable, Sendable {
        public let pointIndex: Int
        public let bpm: Int
    }

    public static func bucketHeartRate(samples: [(Date, Double)], record: MatchRecord) -> [HeartRatePoint] {
        let windows = heartRateWindows(record)
        return record.stats.enumerated().compactMap { index, point in
            guard let window = windows[index] else {
                return point.heartRateBPM.flatMap { $0 > 0 ? HeartRatePoint(pointIndex: index, bpm: $0) : nil }
            }
            let values = samples.filter { $0.0 > window.start && $0.0 <= window.end && $0.1 > 0 }.map(\.1)
            guard !values.isEmpty else { return nil }
            return HeartRatePoint(pointIndex: index, bpm: Int((values.reduce(0, +) / Double(values.count)).rounded()))
        }
    }
}
