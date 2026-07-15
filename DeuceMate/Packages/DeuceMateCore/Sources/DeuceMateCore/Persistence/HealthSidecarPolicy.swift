// HealthSidecarPolicy.swift — pure split/merge rules for device-local Health data.
import Foundation

/// The HealthKit-derived values stored for one point outside the backed-up
/// canonical match archive.
public struct PointHealthData: Codable, Equatable, Sendable {
    public let pointID: UUID
    public let heartRateBPM: Int?
    public let stepsCumulative: Int?

    public init(pointID: UUID, heartRateBPM: Int? = nil, stepsCumulative: Int? = nil) {
        self.pointID = pointID
        self.heartRateBPM = heartRateBPM
        self.stepsCumulative = stepsCumulative
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pointID = try container.decode(UUID.self, forKey: .pointID)
        heartRateBPM = try container.decodeIfPresent(Int.self, forKey: .heartRateBPM)
        stepsCumulative = try container.decodeIfPresent(Int.self, forKey: .stepsCumulative)
    }
}

/// The five HealthKit-derived match values, projected into a backup-excluded
/// sidecar so the normally backed-up `MatchRecord` stays health-free.
public struct MatchHealthData: Codable, Equatable, Sendable {
    public let matchID: UUID
    public let totalSteps: Int?
    public let totalDistanceMeters: Double?
    public let totalCaloriesKcal: Double?
    public let points: [PointHealthData]

    public init(
        matchID: UUID,
        totalSteps: Int? = nil,
        totalDistanceMeters: Double? = nil,
        totalCaloriesKcal: Double? = nil,
        points: [PointHealthData] = []
    ) {
        self.matchID = matchID
        self.totalSteps = totalSteps
        self.totalDistanceMeters = totalDistanceMeters
        self.totalCaloriesKcal = totalCaloriesKcal
        self.points = points
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        matchID = try container.decode(UUID.self, forKey: .matchID)
        totalSteps = try container.decodeIfPresent(Int.self, forKey: .totalSteps)
        totalDistanceMeters = try container.decodeIfPresent(Double.self, forKey: .totalDistanceMeters)
        totalCaloriesKcal = try container.decodeIfPresent(Double.self, forKey: .totalCaloriesKcal)
        points = try container.decodeIfPresent([PointHealthData].self, forKey: .points) ?? []
    }
}

/// Pure projection and reconstruction rules for the iPhone's device-local
/// Health sidecar. This policy deliberately has no file-system behavior.
public enum HealthSidecarPolicy {
    public static func split(
        _ records: [MatchRecord]
    ) -> (stripped: [MatchRecord], health: [MatchHealthData]) {
        let stripped = records.map { $0.strippingHealthData() }
        let health = records.compactMap { record -> MatchHealthData? in
            let points = record.stats.compactMap { point -> PointHealthData? in
                guard point.heartRateBPM != nil || point.stepsCumulative != nil else { return nil }
                return PointHealthData(
                    pointID: point.id,
                    heartRateBPM: point.heartRateBPM,
                    stepsCumulative: point.stepsCumulative
                )
            }
            guard record.totalSteps != nil
                    || record.totalDistanceMeters != nil
                    || record.totalCaloriesKcal != nil
                    || !points.isEmpty else { return nil }
            return MatchHealthData(
                matchID: record.id,
                totalSteps: record.totalSteps,
                totalDistanceMeters: record.totalDistanceMeters,
                totalCaloriesKcal: record.totalCaloriesKcal,
                points: points
            )
        }
        return (stripped, health)
    }

    /// Backfills only missing Health values. Existing non-nil values in
    /// `stripped` win, which also makes this safe for migration and import repair.
    public static func merge(
        stripped records: [MatchRecord],
        health: [MatchHealthData]
    ) -> [MatchRecord] {
        let healthByMatchID = Dictionary(
            health.map { ($0.matchID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return records.map { record in
            guard let matchHealth = healthByMatchID[record.id] else { return record }
            let healthByPointID = Dictionary(
                matchHealth.points.map { ($0.pointID, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            var source = record.strippingHealthData()
            source.totalSteps = matchHealth.totalSteps
            source.totalDistanceMeters = matchHealth.totalDistanceMeters
            source.totalCaloriesKcal = matchHealth.totalCaloriesKcal
            source.stats = source.stats.map { point in
                guard let pointHealth = healthByPointID[point.id] else { return point }
                return PointStat(
                    id: point.id,
                    timestamp: point.timestamp,
                    setIndex: point.setIndex,
                    server: point.server,
                    winner: point.winner,
                    outcome: point.outcome,
                    isSecondServe: point.isSecondServe,
                    isBreakPoint: point.isBreakPoint,
                    endingShot: point.endingShot,
                    gameScoreAtStart: point.gameScoreAtStart,
                    heartRateBPM: pointHealth.heartRateBPM,
                    stepsCumulative: pointHealth.stepsCumulative
                )
            }
            return record.fillingMissingHealthData(from: source)
        }
    }
}
