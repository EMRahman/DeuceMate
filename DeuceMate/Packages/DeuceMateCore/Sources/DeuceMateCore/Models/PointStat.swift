// PointStat.swift — point-level data models shared between the watch and phone.
import Foundation

/// Outcome category for a scored point.
public enum PointOutcome: String, Codable, CaseIterable, Identifiable, Sendable {
    case doubleFault
    case winner
    case forcedError
    case unforcedError
    case uncategorized

    public var id: String { rawValue }

    public var displayLabel: String {
        switch self {
        case .doubleFault:   return "Double Fault"
        case .forcedError:   return "Forced Error"
        case .unforcedError: return "Unforced Error"
        case .winner:        return "Winner"
        case .uncategorized: return "—"
        }
    }

    public static var userSelectable: [PointOutcome] {
        [.doubleFault, .unforcedError, .forcedError, .winner]
    }
}

/// Where in the rally the point ended.
public enum EndingShot: String, Codable, CaseIterable, Identifiable, Sendable {
    case serve
    case `return`
    case servePlusOne
    case rally

    public var id: String { rawValue }

    public var displayLabel: String {
        switch self {
        case .serve:        return "Serve"
        case .return:       return "Return"
        case .servePlusOne: return "S+1"
        case .rally:        return "Rally"
        }
    }
}

/// Game score at the start of a point, from the server's perspective.
public struct GameScoreSnapshot: Codable, Equatable, Sendable {
    public let server: Int
    public let returner: Int
    public let isTiebreak: Bool

    public init(server: Int, returner: Int, isTiebreak: Bool) {
        self.server = server
        self.returner = returner
        self.isTiebreak = isTiebreak
    }
}

/// Transient state carried between "point scored" and "point classified."
/// Persisted in AppState so a kill mid-categorization resurfaces the sheet.
public struct PendingPointInfo: Codable, Equatable, Sendable {
    public let server: Player
    public let winner: Player
    public let setIndex: Int
    public let isSecondServe: Bool
    public let isBreakPoint: Bool
    public let gameScoreAtStart: GameScoreSnapshot?

    public init(
        server: Player,
        winner: Player,
        setIndex: Int,
        isSecondServe: Bool,
        isBreakPoint: Bool = false,
        gameScoreAtStart: GameScoreSnapshot? = nil
    ) {
        self.server = server
        self.winner = winner
        self.setIndex = setIndex
        self.isSecondServe = isSecondServe
        self.isBreakPoint = isBreakPoint
        self.gameScoreAtStart = gameScoreAtStart
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        server        = try c.decode(Player.self, forKey: .server)
        winner        = try c.decode(Player.self, forKey: .winner)
        setIndex      = try c.decode(Int.self, forKey: .setIndex)
        isSecondServe = try c.decode(Bool.self, forKey: .isSecondServe)
        isBreakPoint  = try c.decodeIfPresent(Bool.self, forKey: .isBreakPoint) ?? false
        gameScoreAtStart = try c.decodeIfPresent(GameScoreSnapshot.self, forKey: .gameScoreAtStart)
    }
}

/// A single classified point in a match. All derived statistics fall out of
/// a collection of these.
public struct PointStat: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let setIndex: Int
    public let server: Player
    public let winner: Player
    public let outcome: PointOutcome
    public let isSecondServe: Bool
    public let isBreakPoint: Bool
    public let endingShot: EndingShot?
    public let gameScoreAtStart: GameScoreSnapshot?
    public let heartRateBPM: Int?
    /// Cumulative step count from match start through this point, snapshotted
    /// from the live workout builder when the point was committed. `nil` for
    /// matches recorded before per-point step capture, or when no workout
    /// session was active.
    public let stepsCumulative: Int?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        setIndex: Int,
        server: Player,
        winner: Player,
        outcome: PointOutcome,
        isSecondServe: Bool = false,
        isBreakPoint: Bool = false,
        endingShot: EndingShot? = nil,
        gameScoreAtStart: GameScoreSnapshot? = nil,
        heartRateBPM: Int? = nil,
        stepsCumulative: Int? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.setIndex = setIndex
        self.server = server
        self.winner = winner
        self.outcome = outcome
        self.isSecondServe = isSecondServe
        self.isBreakPoint = isBreakPoint
        self.endingShot = endingShot
        self.gameScoreAtStart = gameScoreAtStart
        self.heartRateBPM = heartRateBPM
        self.stepsCumulative = stepsCumulative
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(UUID.self, forKey: .id)
        timestamp     = try c.decode(Date.self, forKey: .timestamp)
        setIndex      = try c.decode(Int.self, forKey: .setIndex)
        server        = try c.decode(Player.self, forKey: .server)
        winner        = try c.decode(Player.self, forKey: .winner)
        outcome       = try c.decode(PointOutcome.self, forKey: .outcome)
        // decodeIfPresent (not decode) so matches archived before per-point
        // second-serve capture still decode — §4 backward-compat rule.
        isSecondServe = try c.decodeIfPresent(Bool.self, forKey: .isSecondServe) ?? false
        isBreakPoint  = try c.decodeIfPresent(Bool.self, forKey: .isBreakPoint) ?? false
        endingShot    = try c.decodeIfPresent(EndingShot.self, forKey: .endingShot)
        gameScoreAtStart = try c.decodeIfPresent(GameScoreSnapshot.self, forKey: .gameScoreAtStart)
        heartRateBPM = try c.decodeIfPresent(Int.self, forKey: .heartRateBPM)
        stepsCumulative = try c.decodeIfPresent(Int.self, forKey: .stepsCumulative)
    }

    public var isDoubleFault: Bool { outcome == .doubleFault }
    public func wasServing(_ p: Player) -> Bool { server == p }
    public func wasWonBy(_ p: Player) -> Bool { winner == p }

    public func strippingHealthData() -> PointStat {
        PointStat(
            id: id, timestamp: timestamp, setIndex: setIndex,
            server: server, winner: winner, outcome: outcome,
            isSecondServe: isSecondServe, isBreakPoint: isBreakPoint,
            endingShot: endingShot, gameScoreAtStart: gameScoreAtStart,
            heartRateBPM: nil, stepsCumulative: nil
        )
    }

    public func fillingMissingHealthData(from source: PointStat) -> PointStat {
        PointStat(
            id: id, timestamp: timestamp, setIndex: setIndex,
            server: server, winner: winner, outcome: outcome,
            isSecondServe: isSecondServe, isBreakPoint: isBreakPoint,
            endingShot: endingShot, gameScoreAtStart: gameScoreAtStart,
            heartRateBPM: heartRateBPM ?? source.heartRateBPM,
            stepsCumulative: stepsCumulative ?? source.stepsCumulative
        )
    }
}
