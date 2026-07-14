import Foundation

public enum ScoringChangeoverReason: Equatable, Sendable {
    case oddGames
    case evenGames
    case setCompletePlayers
    case setCompleteBalls
    case setCompletePlayersAndBalls
    case tiebreakSixPoints
    case tiebreakOddPoint
    case tiebreakBegins(games: Int)
    case suddenDeathBegins(games: Int)
}

public struct ScoringChangeover: Equatable, Sendable {
    public let symbol: String
    public let reason: ScoringChangeoverReason

    public init(symbol: String, reason: ScoringChangeoverReason) {
        self.symbol = symbol
        self.reason = reason
    }
}

public enum ScoringAnnouncement: Equatable, Sendable {
    case regularPoint(me: Int, opponent: Int)
    case tiebreakPoint(me: Int, opponent: Int, lastServer: Player?)
    case gameWon(winner: Player, gamesMe: Int, gamesOpponent: Int)
    case tiebreakStarted(requiresTwoPointLead: Bool)
    case setWon(winner: Player, setsWonMe: Int, setsWonOpponent: Int)
    case matchWon(winner: Player)
}

public enum ScoringEvent: Equatable, Sendable {
    case announcement(ScoringAnnouncement)
    case changeover(ScoringChangeover)
    case setTimerSnapshot(index: Int)
    case setTimerStarted
    case setTimerStopped
}

public struct ScoringState: Equatable, Sendable {
    public var sets: [SetScore]
    public var currentPointsMe: Int
    public var currentPointsOpponent: Int
    public var currentServer: Player?
    public var gameCount: Int
    public var pointCountInTiebreak: Int
    public var tiebreakStartServer: Player?
    public var tiebreakFirstPointReceiver: Player?
    public var lastTiebreakPointServer: Player?
    public var matchType: MatchType
    public var matchFormat: MatchFormat
    public var doublesServer: DoublesServer?
    public var doublesServiceOrder: [DoublesServer]
    public var doublesServiceIndex: Int
    public var tiebreakStartDoublesIndex: Int
    public var needsDoublesTeamServerDecision: Bool

    public init(
        sets: [SetScore] = [SetScore()],
        currentPointsMe: Int = 0,
        currentPointsOpponent: Int = 0,
        currentServer: Player? = nil,
        gameCount: Int = 0,
        pointCountInTiebreak: Int = 0,
        tiebreakStartServer: Player? = nil,
        tiebreakFirstPointReceiver: Player? = nil,
        lastTiebreakPointServer: Player? = nil,
        matchType: MatchType = .singles,
        matchFormat: MatchFormat = .standard,
        doublesServer: DoublesServer? = nil,
        doublesServiceOrder: [DoublesServer] = [],
        doublesServiceIndex: Int = 0,
        tiebreakStartDoublesIndex: Int = 0,
        needsDoublesTeamServerDecision: Bool = false
    ) {
        self.sets = sets
        self.currentPointsMe = currentPointsMe
        self.currentPointsOpponent = currentPointsOpponent
        self.currentServer = currentServer
        self.gameCount = gameCount
        self.pointCountInTiebreak = pointCountInTiebreak
        self.tiebreakStartServer = tiebreakStartServer
        self.tiebreakFirstPointReceiver = tiebreakFirstPointReceiver
        self.lastTiebreakPointServer = lastTiebreakPointServer
        self.matchType = matchType
        self.matchFormat = matchFormat
        self.doublesServer = doublesServer
        self.doublesServiceOrder = doublesServiceOrder
        self.doublesServiceIndex = doublesServiceIndex
        self.tiebreakStartDoublesIndex = tiebreakStartDoublesIndex
        self.needsDoublesTeamServerDecision = needsDoublesTeamServerDecision
    }
}

public struct ScoringResult: Equatable, Sendable {
    public let state: ScoringState
    public let events: [ScoringEvent]

    public init(state: ScoringState, events: [ScoringEvent]) {
        self.state = state
        self.events = events
    }
}

public enum ScoringEngine {
    public static func pointWon(by player: Player, in state: ScoringState) -> ScoringResult {
        guard state.currentServer != nil, !state.sets.isEmpty else {
            return ScoringResult(state: state, events: [])
        }

        var engine = Engine(state: state)
        engine.updateScore(for: player)
        return ScoringResult(state: engine.state, events: engine.events)
    }

    public static func completedSets(in state: ScoringState) -> [SetScore] {
        let cfg = state.matchFormat.config
        return state.sets.enumerated().compactMap { index, set in
            let normalSetDone = cfg.isNormalSetComplete(
                gamesMe: set.gamesMe,
                gamesOpponent: set.gamesOpponent
            )

            if set.isTieBreak {
                let target = tiebreakTargetPoints(forSetAt: index, in: state.sets, format: state.matchFormat)
                return isTiebreakComplete(
                    mePoints: set.tieBreakPointsMe,
                    oppPoints: set.tieBreakPointsOpponent,
                    target: target,
                    format: state.matchFormat
                ) ? set : nil
            }

            return normalSetDone ? set : nil
        }
    }

    public static func isMatchComplete(_ state: ScoringState) -> Bool {
        let cfg = state.matchFormat.config
        if cfg.isEndless { return false }
        let completed = completedSets(in: state)
        if !cfg.playRegularSets { return !completed.isEmpty }
        let setsWonMe = completed.filter { $0.gamesMe > $0.gamesOpponent }.count
        let setsWonOpponent = completed.filter { $0.gamesOpponent > $0.gamesMe }.count
        return setsWonMe >= cfg.setsToWin || setsWonOpponent >= cfg.setsToWin
    }

    public static func matchWinner(_ state: ScoringState) -> Player? {
        let cfg = state.matchFormat.config
        let completed = completedSets(in: state)
        guard !completed.isEmpty else { return nil }
        if cfg.isEndless { return nil }

        if !cfg.playRegularSets {
            guard let finishedTB = completed.last else { return nil }
            return finishedTB.tieBreakPointsMe > finishedTB.tieBreakPointsOpponent ? .me : .opponent
        }

        let setsWonMe = completed.filter { $0.gamesMe > $0.gamesOpponent }.count
        let setsWonOpponent = completed.filter { $0.gamesOpponent > $0.gamesMe }.count
        if setsWonMe >= cfg.setsToWin { return .me }
        if setsWonOpponent >= cfg.setsToWin { return .opponent }
        return nil
    }

    public static func gameScoreSnapshotAtPointStart(_ state: ScoringState) -> GameScoreSnapshot? {
        guard let server = state.currentServer else { return nil }
        let isTiebreak = state.sets.last?.isTieBreak == true
        let mePts: Int
        let oppPts: Int
        if isTiebreak, let set = state.sets.last {
            mePts = set.tieBreakPointsMe
            oppPts = set.tieBreakPointsOpponent
        } else {
            mePts = state.currentPointsMe
            oppPts = state.currentPointsOpponent
        }
        let serverPts = server == .me ? mePts : oppPts
        let returnerPts = server == .me ? oppPts : mePts
        return GameScoreSnapshot(server: serverPts, returner: returnerPts, isTiebreak: isTiebreak)
    }

    public static func isCurrentPointBreakPoint(_ state: ScoringState) -> Bool {
        guard let server = state.currentServer else { return false }
        guard state.sets.last?.isTieBreak != true else { return false }
        let serverPts = server == .me ? state.currentPointsMe : state.currentPointsOpponent
        let receiverPts = server == .me ? state.currentPointsOpponent : state.currentPointsMe
        return receiverPts >= 3 && receiverPts > serverPts
    }

    public static func tiebreakTargetPoints(
        forSetAt index: Int,
        in setScores: [SetScore],
        format: MatchFormat
    ) -> Int {
        let cfg = format.config
        if !cfg.playRegularSets { return cfg.finalSetTiebreakPoints }
        let completedBefore = setScores.prefix(index).filter {
            cfg.isNormalSetComplete(gamesMe: $0.gamesMe, gamesOpponent: $0.gamesOpponent)
        }.count
        let isDeciding = completedBefore >= cfg.setsToWin * 2 - 2
        return isDeciding ? cfg.finalSetTiebreakPoints : cfg.regularSetTiebreakPoints
    }

    public static func isTiebreakComplete(
        mePoints: Int,
        oppPoints: Int,
        target: Int,
        format: MatchFormat
    ) -> Bool {
        let reached = mePoints >= target || oppPoints >= target
        if !format.config.tiebreakRequiresTwoPointLead { return reached }
        return reached && abs(mePoints - oppPoints) >= 2
    }

    /// True once either side has at least four points and a two-point lead.
    /// The parameters are deliberately perspective-neutral so score
    /// derivations can apply the same rule to server/returner snapshots.
    public static func isRegularGameComplete(
        playerOnePoints: Int,
        playerTwoPoints: Int
    ) -> Bool {
        max(playerOnePoints, playerTwoPoints) >= 4
            && abs(playerOnePoints - playerTwoPoints) >= 2
    }

    private struct Engine {
        var state: ScoringState
        var events: [ScoringEvent] = []

        mutating func updateScore(for player: Player) {
            var set = state.sets.removeLast()

            if set.isTieBreak {
                updateTiebreak(&set, wonBy: player)
                return
            }

            var pointsMe = state.currentPointsMe
            var pointsOpponent = state.currentPointsOpponent

            if player == .me {
                pointsMe += 1
            } else {
                pointsOpponent += 1
            }

            if ScoringEngine.isRegularGameComplete(
                playerOnePoints: pointsMe,
                playerTwoPoints: pointsOpponent
            ) {
                gameWon(by: pointsMe > pointsOpponent ? .me : .opponent, in: &set)
            } else {
                state.currentPointsMe = pointsMe
                state.currentPointsOpponent = pointsOpponent
                state.sets.append(set)
                events.append(.announcement(.regularPoint(me: pointsMe, opponent: pointsOpponent)))
            }
        }

        private mutating func updateTiebreak(_ set: inout SetScore, wonBy player: Player) {
            if player == .me {
                set.tieBreakPointsMe += 1
            } else {
                set.tieBreakPointsOpponent += 1
            }

            state.pointCountInTiebreak += 1

            if let start = state.tiebreakStartServer {
                let other: Player = start == .me ? .opponent : .me
                let pointNumber = state.pointCountInTiebreak
                let serverForThisPoint: Player
                if pointNumber == 1 {
                    serverForThisPoint = start
                } else if state.matchFormat.config.fixedDeuceSide {
                    serverForThisPoint = pointNumber % 2 == 1 ? start : other
                } else {
                    let pairIndex = (pointNumber - 2) / 2
                    serverForThisPoint = pairIndex % 2 == 0 ? other : start
                }
                state.lastTiebreakPointServer = serverForThisPoint
            }

            let mePoints = set.tieBreakPointsMe
            let oppPoints = set.tieBreakPointsOpponent
            let currentSetIndex = state.sets.count
            let targetPoints = ScoringEngine.tiebreakTargetPoints(
                forSetAt: currentSetIndex,
                in: state.sets + [set],
                format: state.matchFormat
            )

            let cfg = state.matchFormat.config
            if !cfg.isEndless,
               ScoringEngine.isTiebreakComplete(
                   mePoints: mePoints,
                   oppPoints: oppPoints,
                   target: targetPoints,
                   format: state.matchFormat
               ) {
                if cfg.playRegularSets {
                    let tbWinAt = cfg.regularSetTiebreakWinAtGames
                    if mePoints > oppPoints {
                        set.gamesMe = tbWinAt
                    } else {
                        set.gamesOpponent = tbWinAt
                    }
                }

                let totalGames = set.gamesMe + set.gamesOpponent
                let playersChange = totalGames % 2 == 1

                completeSet(winner: mePoints > oppPoints ? .me : .opponent, finishedSet: set)
                handleSideChangesAfterTiebreakSetEnd(
                    totalGames: totalGames,
                    playersChangeEnds: playersChange,
                    lastBallHolder: state.lastTiebreakPointServer,
                    nextServer: state.tiebreakFirstPointReceiver
                )

                if let nextSetServer = state.tiebreakFirstPointReceiver {
                    state.currentServer = nextSetServer
                }
                if state.matchType == .doubles, !state.doublesServiceOrder.isEmpty {
                    let nextIdx = (state.tiebreakStartDoublesIndex + 1) % state.doublesServiceOrder.count
                    state.doublesServiceIndex = nextIdx
                    state.doublesServer = state.doublesServiceOrder[nextIdx]
                    state.tiebreakStartDoublesIndex = 0
                }
                state.tiebreakStartServer = nil
                state.tiebreakFirstPointReceiver = nil
                if state.sets.last?.isTieBreak == true {
                    state.tiebreakStartServer = state.currentServer
                    state.tiebreakFirstPointReceiver = state.currentServer == .me ? .opponent : .me
                    if state.matchType == .doubles {
                        state.tiebreakStartDoublesIndex = state.doublesServiceIndex
                    }
                }
                return
            }

            events.append(.announcement(.tiebreakPoint(
                me: mePoints,
                opponent: oppPoints,
                lastServer: state.lastTiebreakPointServer ?? state.currentServer
            )))

            if !state.matchFormat.config.fixedDeuceSide, state.pointCountInTiebreak % 6 == 0 {
                events.append(.changeover(ScoringChangeover(
                    symbol: "🔁 🎾 👥",
                    reason: .tiebreakSixPoints
                )))
            } else if state.pointCountInTiebreak % 2 == 1 {
                events.append(.changeover(ScoringChangeover(
                    symbol: "🔁 🎾",
                    reason: .tiebreakOddPoint
                )))
            }

            advanceTiebreakServerForNextPoint()
            state.sets.append(set)
        }

        private mutating func advanceTiebreakServerForNextPoint() {
            guard let start = state.tiebreakStartServer else { return }
            let other: Player = start == .me ? .opponent : .me
            let nextPointNumber = state.pointCountInTiebreak + 1

            if nextPointNumber == 1 {
                state.currentServer = start
            } else if state.matchFormat.config.fixedDeuceSide {
                state.currentServer = nextPointNumber % 2 == 1 ? start : other
            } else {
                let pairIndex = (nextPointNumber - 2) / 2
                state.currentServer = pairIndex % 2 == 0 ? other : start
            }

            if state.matchType == .doubles, !state.doublesServiceOrder.isEmpty {
                let offset: Int
                if state.matchFormat.config.fixedDeuceSide {
                    offset = nextPointNumber - 1
                } else {
                    offset = nextPointNumber == 1 ? 0 : ((nextPointNumber - 2) / 2 + 1)
                }
                let idx = (state.tiebreakStartDoublesIndex + offset) % state.doublesServiceOrder.count
                state.doublesServiceIndex = idx
                state.doublesServer = state.doublesServiceOrder[idx]
            }
        }

        private mutating func gameWon(by player: Player, in set: inout SetScore) {
            if player == .me {
                set.gamesMe += 1
            } else {
                set.gamesOpponent += 1
            }
            let totalGames = set.gamesMe + set.gamesOpponent
            state.gameCount += 1
            state.currentServer = state.currentServer == .me ? .opponent : .me

            if state.matchType == .doubles, !state.doublesServiceOrder.isEmpty {
                if !state.needsDoublesTeamServerDecision {
                    state.doublesServiceIndex = (state.doublesServiceIndex + 1) % state.doublesServiceOrder.count
                    state.doublesServer = state.doublesServiceOrder[state.doublesServiceIndex]
                }
            }

            let cfg = state.matchFormat.config
            let tbAt = cfg.regularSetTiebreakAtGames
            if set.gamesMe == tbAt && set.gamesOpponent == tbAt {
                set.isTieBreak = true
                set.tieBreakPointsMe = 0
                set.tieBreakPointsOpponent = 0
                state.pointCountInTiebreak = 0
                state.tiebreakStartServer = state.currentServer
                state.tiebreakFirstPointReceiver = state.currentServer == .me ? .opponent : .me
                if state.matchType == .doubles {
                    state.tiebreakStartDoublesIndex = state.doublesServiceIndex
                }

                let tbReason: ScoringChangeoverReason = cfg.tiebreakRequiresTwoPointLead
                    ? .tiebreakBegins(games: tbAt)
                    : .suddenDeathBegins(games: tbAt)
                events.append(.changeover(ScoringChangeover(symbol: "Tiebreak 🔁 🎾", reason: tbReason)))
                events.append(.announcement(.tiebreakStarted(
                    requiresTwoPointLead: cfg.tiebreakRequiresTwoPointLead
                )))
                state.sets.append(set)
                return
            } else if cfg.isNormalSetComplete(gamesMe: set.gamesMe, gamesOpponent: set.gamesOpponent) {
                completeSet(winner: player, finishedSet: set)
                handleSideChangesAfterSet(totalGames: totalGames)
                if state.sets.last?.isTieBreak == true {
                    state.tiebreakStartServer = state.currentServer
                    state.tiebreakFirstPointReceiver = state.currentServer == .me ? .opponent : .me
                    if state.matchType == .doubles {
                        state.tiebreakStartDoublesIndex = state.doublesServiceIndex
                    }
                }
                return
            }

            state.currentPointsMe = 0
            state.currentPointsOpponent = 0
            events.append(.announcement(.gameWon(
                winner: player,
                gamesMe: set.gamesMe,
                gamesOpponent: set.gamesOpponent
            )))
            handleSideChangesAfterGame(gamesInCurrentSet: totalGames)
            state.sets.append(set)
        }

        private mutating func completeSet(winner: Player, finishedSet: SetScore) {
            let finishedSetIndex = state.sets.count
            state.sets.append(finishedSet)
            events.append(.setTimerSnapshot(index: finishedSetIndex))

            let cfg = state.matchFormat.config
            if !cfg.playRegularSets && !cfg.isEndless {
                events.append(.announcement(.matchWon(winner: winner)))
                events.append(.setTimerStopped)
                state.currentPointsMe = 0
                state.currentPointsOpponent = 0
                return
            }

            let setsWonMe = state.sets.filter { $0.gamesMe > $0.gamesOpponent }.count
            let setsWonOpponent = state.sets.filter { $0.gamesOpponent > $0.gamesMe }.count
            let matchOver = setsWonMe >= cfg.setsToWin || setsWonOpponent >= cfg.setsToWin

            events.append(matchOver ? .setTimerStopped : .setTimerStarted)
            if matchOver {
                let matchWinner: Player = setsWonMe >= cfg.setsToWin ? .me : .opponent
                events.append(.announcement(.matchWon(winner: matchWinner)))
            } else {
                events.append(.announcement(.setWon(
                    winner: winner,
                    setsWonMe: setsWonMe,
                    setsWonOpponent: setsWonOpponent
                )))
            }

            if setsWonMe < cfg.setsToWin && setsWonOpponent < cfg.setsToWin {
                let bothNeedOneMore = setsWonMe == cfg.setsToWin - 1
                    && setsWonOpponent == cfg.setsToWin - 1
                if bothNeedOneMore && cfg.finalSetStyle == .superTiebreak {
                    state.pointCountInTiebreak = 0
                    state.sets.append(SetScore(isTieBreak: true))
                } else {
                    state.sets.append(SetScore())
                }
            }

            state.currentPointsMe = 0
            state.currentPointsOpponent = 0
        }

        private mutating func handleSideChangesAfterGame(gamesInCurrentSet: Int) {
            guard gamesInCurrentSet > 0 else { return }
            if gamesInCurrentSet % 2 == 1 {
                events.append(.changeover(ScoringChangeover(
                    symbol: "🔁 👥",
                    reason: .oddGames
                )))
            } else {
                events.append(.changeover(ScoringChangeover(
                    symbol: "🔁 🎾",
                    reason: .evenGames
                )))
            }
        }

        private mutating func handleSideChangesAfterSet(totalGames: Int) {
            if totalGames % 2 == 1 {
                events.append(.changeover(ScoringChangeover(
                    symbol: "🔁 👥",
                    reason: .setCompletePlayers
                )))
            } else {
                events.append(.changeover(ScoringChangeover(
                    symbol: "🔁 🎾",
                    reason: .setCompleteBalls
                )))
            }
        }

        private mutating func handleSideChangesAfterTiebreakSetEnd(
            totalGames: Int,
            playersChangeEnds: Bool,
            lastBallHolder: Player?,
            nextServer: Player?
        ) {
            guard let lastBallHolder, let nextServer else {
                handleSideChangesAfterSet(totalGames: totalGames)
                return
            }

            let ballsEndOwnerAfterOptionalPlayerSwap: Player =
                playersChangeEnds ? (lastBallHolder == .me ? .opponent : .me) : lastBallHolder
            let ballsNeedToMove = ballsEndOwnerAfterOptionalPlayerSwap != nextServer

            switch (playersChangeEnds, ballsNeedToMove) {
            case (true, true):
                events.append(.changeover(ScoringChangeover(
                    symbol: "🔁 🎾 👥",
                    reason: .setCompletePlayersAndBalls
                )))
            case (true, false):
                events.append(.changeover(ScoringChangeover(
                    symbol: "🔁 👥",
                    reason: .setCompletePlayers
                )))
            case (false, true):
                events.append(.changeover(ScoringChangeover(
                    symbol: "🔁 🎾",
                    reason: .setCompleteBalls
                )))
            case (false, false):
                break
            }
        }
    }
}
