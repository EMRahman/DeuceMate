// LiveMatchState.swift — bounded, transient Watch-owned scoreboard state.
// Never merge its deliberately stats-free record into the match archive.
import Foundation

public struct LiveMatchRequest: Codable, Equatable {
    public var action: String?
    public var matchID: UUID?
    public var outcome: PointOutcome?
    public var endingShot: EndingShot?
    public var pendingPoint: PendingPointInfo?
    public var pendingOutcome: PointOutcome?

    public init(action: String? = nil, matchID: UUID? = nil,
                outcome: PointOutcome? = nil, endingShot: EndingShot? = nil,
                pendingPoint: PendingPointInfo? = nil, pendingOutcome: PointOutcome? = nil) {
        self.action = action
        self.matchID = matchID
        self.outcome = outcome
        self.endingShot = endingShot
        self.pendingPoint = pendingPoint
        self.pendingOutcome = pendingOutcome
    }
}

public struct LiveMatchState: Codable, Equatable {
    public let record: MatchRecord?
    public let pendingPoint: PendingPointInfo?
    public let pendingOutcome: PointOutcome?
    public let inputEnabled: Bool
    public let blockingReason: String?

    public init(record: MatchRecord?, pendingPoint: PendingPointInfo? = nil,
                pendingOutcome: PointOutcome? = nil, inputEnabled: Bool,
                blockingReason: String? = nil) {
        // Project only the fields the board needs. Full records travel separately
        // using the reliable archive path, including for long live matches.
        self.record = record.map { r in
            MatchRecord(id: r.id, startTime: r.startTime,
                        setScores: r.setScores, stats: [], iWon: nil,
                        currentPointsMe: r.currentPointsMe,
                        currentPointsOpponent: r.currentPointsOpponent,
                        currentServer: r.currentServer, isOnSecondServe: r.isOnSecondServe,
                        matchType: r.matchType, matchFormat: r.matchFormat,
                        recentPoints: Array(r.recentPoints.suffix(8)),
                        momentumEnabled: r.momentumEnabled)
        }
        self.pendingPoint = record == nil ? nil : pendingPoint
        self.pendingOutcome = record == nil ? nil : pendingOutcome
        self.inputEnabled = inputEnabled
        self.blockingReason = blockingReason
    }
}

public struct LiveMatchReply: Codable, Equatable {
    public let version: Int
    /// nil means unavailable/error; a non-nil state with no record means idle.
    public let state: LiveMatchState?
    public let message: String?
    /// Transport-lifetime ordering only; never persisted or used for archive merges.
    public let sessionID: UUID?
    public let sequence: UInt64

    public init(state: LiveMatchState?, message: String? = nil,
                sessionID: UUID? = nil, sequence: UInt64 = 0) {
        version = 1
        self.state = state
        self.message = message
        self.sessionID = sessionID
        self.sequence = sequence
    }
}
