// MatchChronology.swift — display chronology, independent of sync authority.
import Foundation

public enum MatchChronology {
    /// Actual recorded play, never the administrative completion or receipt time.
    public static func activityDate(_ record: MatchRecord) -> Date {
        ([record.startTime] + record.stats.map(\.timestamp) + record.resumeEvents.map(\.resumedAt) + [record.parkedAt].compactMap { $0 }).max() ?? record.startTime
    }

    public static func date(_ record: MatchRecord) -> Date {
        record.isInProgress ? activityDate(record) : (record.endTime ?? record.startTime)
    }

    public static func label(_ record: MatchRecord) -> String {
        if record.isInProgress { return record.stats.isEmpty && record.resumeEvents.isEmpty && record.parkedAt == nil ? "Started" : "Last activity" }
        return record.endTime == nil ? "Played" : "Finished"
    }

    public static func newestFirst(_ a: MatchRecord, _ b: MatchRecord) -> Bool {
        date(a) != date(b) ? date(a) > date(b) : a.id.uuidString < b.id.uuidString
    }

    public static func oldestFirst(_ a: MatchRecord, _ b: MatchRecord) -> Bool {
        date(a) != date(b) ? date(a) < date(b) : a.id.uuidString < b.id.uuidString
    }

    public static func caption(_ record: MatchRecord, formatter: DateFormatter) -> String {
        "\(label(record)) \(formatter.string(from: date(record)))"
    }

    /// Local dates for presentation; comparisons above always use absolute instants.
    /// Multi-day records retain their original start alongside the result/activity.
    public static func description(_ record: MatchRecord, formatter: DateFormatter,
                                   calendar: Calendar = .current) -> String {
        let main = caption(record, formatter: formatter)
        guard !calendar.isDate(record.startTime, inSameDayAs: date(record)) else { return main }
        return "Started \(formatter.string(from: record.startTime)) · \(main)"
    }
}
