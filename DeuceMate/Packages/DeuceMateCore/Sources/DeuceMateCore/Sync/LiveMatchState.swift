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
    /// The Watch prompt this request answers, exactly as the phone displayed it.
    /// The Watch refuses the answer unless the same prompt is still open, so a
    /// late tap can never dismiss a different changeover.
    public var prompt: LiveWatchPrompt?
    /// The answer to a `.doublesServer` prompt: `.me` or `.partner`.
    public var doublesServer: DoublesServer?

    public init(action: String? = nil, matchID: UUID? = nil,
                outcome: PointOutcome? = nil, endingShot: EndingShot? = nil,
                pendingPoint: PendingPointInfo? = nil, pendingOutcome: PointOutcome? = nil,
                prompt: LiveWatchPrompt? = nil, doublesServer: DoublesServer? = nil) {
        self.action = action
        self.matchID = matchID
        self.outcome = outcome
        self.endingShot = endingShot
        self.pendingPoint = pendingPoint
        self.pendingOutcome = pendingOutcome
        self.prompt = prompt
        self.doublesServer = doublesServer
    }
}

/// A Watch screen that pauses scoring until someone answers it — the
/// changeover reminder ("Even games – balls change ends") or doubles' "Who
/// serves next?". Carried in `LiveMatchState` so the iPhone can show the same
/// question and answer it *through* the Watch, which applies the answer with
/// the same method as its own button. Both screens then clear together.
///
/// The kind travels as a raw string so an older phone that meets a newer kind
/// keeps working: `kind` is nil, the phone offers no answer and falls back to
/// `LiveMatchState.blockingReason` ("Continue on the Watch…").
public struct LiveWatchPrompt: Codable, Equatable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case changeover
        case doublesServer
    }

    public let kindRaw: String
    /// The large line: the changeover symbol ("🔁 🎾") or the question.
    public let title: String
    /// The smaller line under it: the changeover reason, when there is one.
    public let detail: String?
    /// Which appearance of the screen this is. The Watch issues a new one each
    /// time a prompt opens, so an answer to an earlier screen with the same
    /// words (every odd-game changeover reads alike) can never close this one.
    /// Nil only from a build that predates it.
    public let occurrence: UUID?

    public init(kindRaw: String, title: String, detail: String? = nil, occurrence: UUID? = nil) {
        self.kindRaw = kindRaw
        self.title = title
        self.detail = detail
        self.occurrence = occurrence
    }

    /// This prompt as one particular appearance on the Watch.
    public func occurring(_ id: UUID) -> LiveWatchPrompt {
        LiveWatchPrompt(kindRaw: kindRaw, title: title, detail: detail, occurrence: id)
    }

    public var kind: Kind? { Kind(rawValue: kindRaw) }

    /// The Watch's `ChangeoverAckOverlay`: symbol on top, reason underneath.
    public static func changeover(symbol: String, reason: String) -> LiveWatchPrompt {
        LiveWatchPrompt(kindRaw: Kind.changeover.rawValue, title: symbol, detail: reason)
    }

    /// The Watch's `DoublesTeamServerDecisionOverlay`, shown after the
    /// opponents' first service game to fix the four-player rotation.
    public static let doublesServer = LiveWatchPrompt(
        kindRaw: Kind.doublesServer.rawValue, title: "Who serves next?",
        detail: "Your team's first service game")

    /// One button the phone offers, with the request that applies it.
    public struct Answer: Equatable, Sendable, Identifiable {
        public let label: String
        public let action: String
        public let doublesServer: DoublesServer?
        public var id: String { action + (doublesServer?.rawValue ?? "") }
    }

    /// The same buttons as the Watch screen, in the same order. Empty for a
    /// kind this build doesn't understand: never guess an answer.
    public var answers: [Answer] {
        switch kind {
        case .changeover:
            return [Answer(label: "OK", action: MatchSyncKey.promptActionAcknowledgeChangeover,
                           doublesServer: nil)]
        case .doublesServer:
            return [DoublesServer.me, .partner].map {
                Answer(label: $0.displayName, action: MatchSyncKey.promptActionChooseDoublesServer,
                       doublesServer: $0)
            }
        case nil:
            return []
        }
    }

    /// The request that sends `answer` for this prompt in match `matchID`.
    public func request(for answer: Answer, matchID: UUID?) -> LiveMatchRequest {
        LiveMatchRequest(action: answer.action, matchID: matchID,
                         prompt: self, doublesServer: answer.doublesServer)
    }
}

public struct LiveMatchState: Codable, Equatable {
    public let record: MatchRecord?
    public let pendingPoint: PendingPointInfo?
    public let pendingOutcome: PointOutcome?
    public let inputEnabled: Bool
    public let blockingReason: String?
    /// The Watch screen currently pausing scoring, if the phone may answer it.
    /// Optional on the wire: an older Watch never sends it, and the phone then
    /// shows only `blockingReason`.
    public let prompt: LiveWatchPrompt?

    public init(record: MatchRecord?, pendingPoint: PendingPointInfo? = nil,
                pendingOutcome: PointOutcome? = nil, inputEnabled: Bool,
                blockingReason: String? = nil, prompt: LiveWatchPrompt? = nil) {
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
                        momentumEnabled: r.momentumEnabled, checkpointRevision: r.checkpointRevision)
        }
        self.pendingPoint = record == nil ? nil : pendingPoint
        self.pendingOutcome = record == nil ? nil : pendingOutcome
        self.inputEnabled = inputEnabled
        self.blockingReason = blockingReason
        self.prompt = record == nil ? nil : prompt
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
