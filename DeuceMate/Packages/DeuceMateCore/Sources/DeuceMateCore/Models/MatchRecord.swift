// MatchRecord.swift — one persisted match, shared between watch and phone.
import Foundation

/// One persisted match. May be completed (`iWon != nil`) or in-progress
/// (`iWon == nil`). The watch is the sole source of truth for any match it has
/// touched; the phone is a read-only durable archive.
public struct MatchRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let startTime: Date
    public var endTime: Date?
    public var setScores: [SetScore]
    public var stats: [PointStat]
    /// `nil` = in-progress; `true` = user won; `false` = opponent won.
    public var iWon: Bool?

    // Resume-state fields. Meaningful for in-progress matches; on completed
    // matches they reflect the final-point state.
    public var currentPointsMe: Int
    public var currentPointsOpponent: Int
    public var currentServer: Player?
    public var gameCount: Int
    public var pointCountInTiebreak: Int
    public var tiebreakStartServer: Player?
    public var tiebreakFirstPointReceiver: Player?
    public var lastTiebreakPointServer: Player?
    public var isOnSecondServe: Bool
    public var matchType: MatchType
    public var matchFormat: MatchFormat
    public var doublesServer: DoublesServer?
    public var doublesServiceOrder: [DoublesServer]
    public var doublesServiceIndex: Int
    public var tiebreakStartDoublesIndex: Int
    /// Total seconds of active play accumulated across all sessions.
    public var matchElapsedSeconds: TimeInterval
    /// Per-set accumulated active-play seconds, keyed by set index.
    public var setElapsedSeconds: [Int: TimeInterval]
    /// Step count recorded by HealthKit during the match, if available.
    public var totalSteps: Int?
    /// Total distance in metres recorded by HealthKit during the match, if available.
    public var totalDistanceMeters: Double?
    /// Total kilocalories burned (active + basal) recorded by HealthKit, if available.
    public var totalCaloriesKcal: Double?
    /// The last (up to) 8 point winners in chronological order, oldest first.
    /// Used to display the momentum strip on the live scoreboards.
    public var recentPoints: [Player]
    /// Whether the momentum strip was enabled when this record was saved (always true for new records).
    public var momentumEnabled: Bool

    public init(
        id: UUID = UUID(),
        startTime: Date,
        endTime: Date? = nil,
        setScores: [SetScore],
        stats: [PointStat],
        iWon: Bool? = nil,
        currentPointsMe: Int = 0,
        currentPointsOpponent: Int = 0,
        currentServer: Player? = nil,
        gameCount: Int = 0,
        pointCountInTiebreak: Int = 0,
        tiebreakStartServer: Player? = nil,
        tiebreakFirstPointReceiver: Player? = nil,
        lastTiebreakPointServer: Player? = nil,
        isOnSecondServe: Bool = false,
        matchType: MatchType = .singles,
        matchFormat: MatchFormat = .standard,
        doublesServer: DoublesServer? = nil,
        doublesServiceOrder: [DoublesServer] = [],
        doublesServiceIndex: Int = 0,
        tiebreakStartDoublesIndex: Int = 0,
        matchElapsedSeconds: TimeInterval = 0,
        setElapsedSeconds: [Int: TimeInterval] = [:],
        totalSteps: Int? = nil,
        totalDistanceMeters: Double? = nil,
        totalCaloriesKcal: Double? = nil,
        recentPoints: [Player] = [],
        momentumEnabled: Bool = true
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.setScores = setScores
        self.stats = stats
        self.iWon = iWon
        self.currentPointsMe = currentPointsMe
        self.currentPointsOpponent = currentPointsOpponent
        self.currentServer = currentServer
        self.gameCount = gameCount
        self.pointCountInTiebreak = pointCountInTiebreak
        self.tiebreakStartServer = tiebreakStartServer
        self.tiebreakFirstPointReceiver = tiebreakFirstPointReceiver
        self.lastTiebreakPointServer = lastTiebreakPointServer
        self.isOnSecondServe = isOnSecondServe
        self.matchType = matchType
        self.matchFormat = matchFormat
        self.doublesServer = doublesServer
        self.doublesServiceOrder = doublesServiceOrder
        self.doublesServiceIndex = doublesServiceIndex
        self.tiebreakStartDoublesIndex = tiebreakStartDoublesIndex
        self.matchElapsedSeconds = matchElapsedSeconds
        self.setElapsedSeconds = setElapsedSeconds
        self.totalSteps = totalSteps
        self.totalDistanceMeters = totalDistanceMeters
        self.totalCaloriesKcal = totalCaloriesKcal
        self.recentPoints = recentPoints
        self.momentumEnabled = momentumEnabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                       = try c.decode(UUID.self, forKey: .id)
        startTime                = try c.decode(Date.self, forKey: .startTime)
        endTime                  = try c.decodeIfPresent(Date.self, forKey: .endTime)
        setScores                = try c.decode([SetScore].self, forKey: .setScores)
        stats                    = try c.decode([PointStat].self, forKey: .stats)
        iWon                     = try c.decodeIfPresent(Bool.self, forKey: .iWon)
        currentPointsMe          = try c.decode(Int.self, forKey: .currentPointsMe)
        currentPointsOpponent    = try c.decode(Int.self, forKey: .currentPointsOpponent)
        currentServer            = try c.decodeIfPresent(Player.self, forKey: .currentServer)
        gameCount                = try c.decode(Int.self, forKey: .gameCount)
        pointCountInTiebreak     = try c.decode(Int.self, forKey: .pointCountInTiebreak)
        tiebreakStartServer      = try c.decodeIfPresent(Player.self, forKey: .tiebreakStartServer)
        tiebreakFirstPointReceiver = try c.decodeIfPresent(Player.self, forKey: .tiebreakFirstPointReceiver)
        lastTiebreakPointServer  = try c.decodeIfPresent(Player.self, forKey: .lastTiebreakPointServer)
        isOnSecondServe          = try c.decodeIfPresent(Bool.self, forKey: .isOnSecondServe) ?? false
        matchType                = try c.decodeIfPresent(MatchType.self, forKey: .matchType) ?? .singles
        matchFormat              = try c.decodeIfPresent(MatchFormat.self, forKey: .matchFormat) ?? .standard
        doublesServer            = try c.decodeIfPresent(DoublesServer.self, forKey: .doublesServer)
        doublesServiceOrder      = try c.decodeIfPresent([DoublesServer].self, forKey: .doublesServiceOrder) ?? []
        doublesServiceIndex      = try c.decodeIfPresent(Int.self, forKey: .doublesServiceIndex) ?? 0
        tiebreakStartDoublesIndex = try c.decodeIfPresent(Int.self, forKey: .tiebreakStartDoublesIndex) ?? 0
        matchElapsedSeconds      = try c.decodeIfPresent(TimeInterval.self, forKey: .matchElapsedSeconds) ?? 0
        setElapsedSeconds        = try c.decodeIfPresent([Int: TimeInterval].self, forKey: .setElapsedSeconds) ?? [:]
        totalSteps               = try c.decodeIfPresent(Int.self,    forKey: .totalSteps)
        totalDistanceMeters      = try c.decodeIfPresent(Double.self, forKey: .totalDistanceMeters)
        totalCaloriesKcal        = try c.decodeIfPresent(Double.self, forKey: .totalCaloriesKcal)
        recentPoints             = try c.decodeIfPresent([Player].self, forKey: .recentPoints) ?? []
        momentumEnabled          = try c.decodeIfPresent(Bool.self, forKey: .momentumEnabled) ?? true
    }

    /// Converts raw game point counters (0–4+) to a tennis score string,
    /// e.g. "30–0", "Deuce", "AD–40". Returns nil when both counters are zero.
    public static func gameScoreString(mePoints: Int, oppPoints: Int) -> String? {
        guard mePoints > 0 || oppPoints > 0 else { return nil }
        if mePoints >= 3 && oppPoints >= 3 {
            if mePoints == oppPoints { return "Deuce" }
            return mePoints > oppPoints ? "AD–40" : "40–AD"
        }
        let labels = ["0", "15", "30", "40"]
        let meLabel  = mePoints  < labels.count ? labels[mePoints]  : "\(mePoints)"
        let oppLabel = oppPoints < labels.count ? labels[oppPoints] : "\(oppPoints)"
        return "\(meLabel)–\(oppLabel)"
    }

    /// Formats a distance in metres to a locale-appropriate string (e.g. "1.2 km" or "0.75 mi").
    public static func formattedDistance(_ meters: Double) -> String {
        let m = Measurement(value: meters, unit: UnitLength.meters)
        let f = MeasurementFormatter()
        f.unitOptions = .naturalScale
        f.numberFormatter.maximumFractionDigits = 2
        return f.string(from: m)
    }

    /// Formats kilocalories using MeasurementFormatter for locale-appropriate unit label (e.g. "312 kcal").
    public static func formattedCalories(_ kcal: Double) -> String {
        let energy = Measurement(value: kcal, unit: UnitEnergy.kilocalories)
        let f = MeasurementFormatter()
        f.unitOptions = .providedUnit
        f.numberFormatter.maximumFractionDigits = 0
        return f.string(from: energy)
    }

    /// True while a match is actively being played. A draw (perpetual tiebreak
    /// ending with equal tiebreaks won) has `iWon == nil` but a non-nil `endTime`,
    /// so this correctly returns false for draws.
    public var isInProgress: Bool { iWon == nil && endTime == nil }

    // App Store Review Guideline 5.1.3(ii): the iCloud backup must never contain
    // health measurements. Strip all five HealthKit-derived fields before pushing.
    public func strippingHealthData() -> MatchRecord {
        var stripped = self
        stripped.totalSteps = nil
        stripped.totalDistanceMeters = nil
        stripped.totalCaloriesKcal = nil
        stripped.stats = stats.map { $0.strippingHealthData() }
        return stripped
    }

    /// Backfills nil HealthKit-derived fields from `source` where point IDs match.
    /// Returns self unchanged when IDs differ.
    public func fillingMissingHealthData(from source: MatchRecord) -> MatchRecord {
        guard id == source.id else { return self }
        var filled = self
        filled.totalSteps = filled.totalSteps ?? source.totalSteps
        filled.totalDistanceMeters = filled.totalDistanceMeters ?? source.totalDistanceMeters
        filled.totalCaloriesKcal = filled.totalCaloriesKcal ?? source.totalCaloriesKcal
        let sourceStats = Dictionary(source.stats.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        filled.stats = filled.stats.map { point in
            guard let sourcePoint = sourceStats[point.id] else { return point }
            return point.fillingMissingHealthData(from: sourcePoint)
        }
        return filled
    }
}
