import Foundation

/// An explicit history resume, not inferred from app visibility or sample gaps.
public struct MatchResumeEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let resumedAt: Date
    public let pausedAt: Date?
    public let precedingPointID: UUID?

    public init(id: UUID = UUID(), resumedAt: Date, pausedAt: Date? = nil, precedingPointID: UUID? = nil) {
        self.id = id
        self.resumedAt = resumedAt
        self.pausedAt = pausedAt
        self.precedingPointID = precedingPointID
    }

    public var breakDuration: TimeInterval? {
        guard let pausedAt, resumedAt >= pausedAt else { return nil }
        return resumedAt.timeIntervalSince(pausedAt)
    }

    /// Immutable events union independently of scoring-body authority. A malformed
    /// duplicate ID resolves lexicographically by its full contents, so delivery
    /// direction/order cannot change the answer. No point histories are unioned.
    public static func merged(_ a: [Self], _ b: [Self]) -> [Self] {
        var events: [UUID: Self] = [:]
        for event in a + b {
            if let old = events[event.id], !precedes(old, event) { continue }
            events[event.id] = event
        }
        return events.values.sorted {
            $0.resumedAt != $1.resumedAt ? $0.resumedAt < $1.resumedAt : $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func precedes(_ a: Self, _ b: Self) -> Bool {
        if a.resumedAt != b.resumedAt { return a.resumedAt < b.resumedAt }
        if a.pausedAt != b.pausedAt {
            guard let left = a.pausedAt else { return true }
            guard let right = b.pausedAt else { return false }
            return left < right
        }
        return (a.precedingPointID?.uuidString ?? "") < (b.precedingPointID?.uuidString ?? "")
    }
}

extension MatchRecord {
    public func mergingResumeEvents(_ events: [MatchResumeEvent]) -> MatchRecord {
        var copy = self
        copy.resumeEvents = MatchResumeEvent.merged(resumeEvents, events)
        if !copy.isInProgress { copy.parkedAt = nil }
        return copy
    }
}

/// Full-history coordinates. Filters must never derive these from a filtered list.
public enum ResumeMarkers {
    public struct Marker: Equatable, Identifiable, Sendable {
        public var id: UUID { event.id }
        public let event: MatchResumeEvent
        /// Zero-based index of the following point; `points.count` is trailing.
        /// Nil means that the evidence cannot safely place a chart rule.
        public let beforePointIndex: Int?
    }

    public static func derive(events: [MatchResumeEvent], points: [PointStat]) -> [Marker] {
        MatchResumeEvent.merged([], events).map { event in
            let index: Int?
            if let anchor = event.precedingPointID {
                let matches = points.indices.filter { points[$0].id == anchor }
                index = matches.count == 1 ? matches.first.map { $0 + 1 } : nil
            } else {
                index = points.firstIndex { $0.timestamp >= event.resumedAt } ?? points.count
            }
            return Marker(event: event, beforePointIndex: index)
        }
    }

    public static func derive(_ record: MatchRecord) -> [Marker] {
        derive(events: record.resumeEvents, points: record.stats)
    }

    /// Session numbers for physiological series. Unplaced events conservatively
    /// isolate every point: uncertain boundaries must not imply continuity.
    public static func sessionIndices(events: [MatchResumeEvent], points: [PointStat]) -> [Int] {
        let markers = derive(events: events, points: points)
        if markers.contains(where: { $0.beforePointIndex == nil }) { return Array(points.indices) }
        return points.indices.map { index in
            markers.filter { ($0.beforePointIndex ?? Int.max) <= index }.count
        }
    }
}

/// Existing aggregate Health fields are the only fitness values on MatchRecord.
/// This additive private live-state value lets each fresh workout contribute once.
public struct MatchActivityTotals: Codable, Equatable, Sendable {
    public var steps: Int?
    public var distanceMeters: Double?
    public var caloriesKcal: Double?

    public init(steps: Int? = nil, distanceMeters: Double? = nil, caloriesKcal: Double? = nil) {
        self.steps = steps
        self.distanceMeters = distanceMeters
        self.caloriesKcal = caloriesKcal
    }

    public init(record: MatchRecord) {
        self.init(steps: record.totalSteps, distanceMeters: record.totalDistanceMeters, caloriesKcal: record.totalCaloriesKcal)
    }

    public func adding(_ current: Self) -> Self {
        func sum<T: AdditiveArithmetic>(_ a: T?, _ b: T?) -> T? {
            guard a != nil || b != nil else { return nil }
            return (a ?? .zero) + (b ?? .zero)
        }
        return Self(steps: sum(steps, current.steps), distanceMeters: sum(distanceMeters, current.distanceMeters), caloriesKcal: sum(caloriesKcal, current.caloriesKcal))
    }
}
