import Foundation

/// Scripted, disposable guide. A tap starts each demonstration; its beats then advance automatically.
/// No match records, storage, transport, settings or sensors.
public struct WalkthroughSession: Sendable {
    public enum Phase: Equatable, Sendable {
        case situation, secondServeTap, gesture, outcome, endingShot, stats, changeover, postChangeoverScore, reminder, nextSetGesture, result, done
    }
    public private(set) var step: WalkthroughStep
    public private(set) var state: ScoringState
    public private(set) var points: [PointStat] = []
    public private(set) var recentWinners: [Player]
    public private(set) var pendingPoint: PendingPointInfo?
    public private(set) var isOnSecondServe = false
    public private(set) var changeover: ScoringChangeover?
    public private(set) var phase: Phase = .situation
    /// Navigation replaces the generation so old animation callbacks cannot affect a new page.
    public private(set) var generation = UUID()

    public init(step: WalkthroughStep = .winPoint) {
        self.step = step
        state = WalkthroughFixtures.state(for: step)
        recentWinners = WalkthroughFixtures.recentWinners(for: step)
        if step == .secondServe || step == .doubleFault { points = [WalkthroughFixtures.errorPoint] }
        if step == .findStat { points = [WalkthroughFixtures.errorPoint, WalkthroughFixtures.doubleFaultPoint] }
        isOnSecondServe = step == .doubleFault
    }
    public var reminder: Bool? { ScoringEngine.nextSetRequiresEndsSwitch(state) }
    public var isDeuceSide: Bool { (state.currentPointsMe + state.currentPointsOpponent) % 2 == 0 }
    public var summary: MatchStatsSummary { MatchStatsSummary(stats: points, focal: .me) }
    public var demonstrationFinished: Bool { phase == .result || phase == .stats || phase == .done }
    public var gesture: ScoreInputAction {
        if phase == .nextSetGesture { return .win }
        switch step {
        case .winPoint, .winGame, .oddSet: return .win
        case .losePoint, .unforcedError, .doubleFault: return .lose
        case .secondServe: return .lose // No swipe occurs in this step; the score is double tapped.
        case .undoPoint: return .undo
        case .findStat: return .stats
        }
    }
    public var scoreDescription: String {
        let games = state.sets.map { "\($0.gamesMe)–\($0.gamesOpponent)" }.joined(separator: ", ")
        return "Games \(games). Points \(pointLabel(state.currentPointsMe))–\(pointLabel(state.currentPointsOpponent)). Next: \(state.currentServer == .me ? "Me" : "Opp") serves\(isOnSecondServe ? ", second serve" : ""), \(isDeuceSide ? "right/deuce" : "left/ad")."
    }
    public func pointLabel(_ points: Int) -> String {
        switch points {
        case 0: return "0"
        case 1: return "15"
        case 2: return "30"
        default: return "40"
        }
    }
    public var feedback: String {
        switch phase {
        case .situation: return step.introduction
        case .secondServeTap: return "Double tap the score to mark the second serve."
        case .gesture: return "Showing \(gesture.instruction.lowercased())."
        case .outcome: return step == .doubleFault ? "Double Fault is selected for your second serve." : "Unforced Error is selected for you, the losing player."
        case .endingShot: return "Rally is selected for the shot you hit out."
        case .stats: return "Live Stats. Unforced Errors: Me 1, Opp 0. Double Faults: Me 1, Opp 0."
        case .changeover: return changeover?.reason.displayText ?? ""
        case .postChangeoverScore: return scoreDescription
        case .reminder: return "OK closes the message. The reminder stays until the first point of the new set."
        case .nextSetGesture: return "An upward swipe scores the first point of set two. Watch the reminder clear."
        case .done: return "Ready to play. Enable Track point outcome in Settings to collect error stats."
        case .result:
            switch step {
            case .winPoint: return "15–0. You still serve, now from left/ad. The ball marks who serves next."
            case .losePoint: return "15–15. You still serve, now from right/deuce. Swipes award points regardless of who served."
            case .undoPoint: return "Back to 15–0 and left/ad. Undo restores score, server and tracked stats together."
            case .unforcedError: return "0–15. One rally unforced error recorded for Me. Your real tracking settings haven’t changed."
            case .secondServe: return "Second serve marked. The score remains 0–15."
            case .doubleFault: return "0–30. One double fault recorded for Me."
            case .findStat: return "Unforced Errors and Double Faults: Me 1, Opp 0 each."
            case .winGame: return "Games 2–0; points 0–0. Opp serves next. Players stay; get the balls to Opp."
            case .oddSet: return "6–3: nine games, so players change ends. Opp serves set two. Its first point clears the sticky reminder."
            }
        }
    }

    /// The only action accepted during commentary. Repeated taps cannot score or skip a beat.
    public mutating func beginExample() {
        guard phase == .situation else { return }
        phase = step == .secondServe ? .secondServeTap : .gesture
    }

    /// Advance one animation beat, never the page. Repeated/stale callbacks are harmless.
    public mutating func advanceDemonstration(generation: UUID) {
        guard generation == self.generation else { return }
        switch phase {
        case .situation: break
        case .secondServeTap:
            isOnSecondServe = true
            phase = .result
        case .gesture:
            switch gesture {
            case .stats: phase = .stats
            case .undo:
                state = WalkthroughFixtures.state(for: .losePoint)
                if !recentWinners.isEmpty { recentWinners.removeLast() }
                phase = .result
            case .win, .lose:
                score(winner: gesture == .win ? .me : .opponent)
                phase = step == .unforcedError || step == .doubleFault ? .outcome : (changeover == nil ? .result : .changeover)
            }
        case .outcome:
            if step == .doubleFault, let pending = pendingPoint {
                points.append(PointStat(id: WalkthroughFixtures.setID(101), timestamp: Date(timeIntervalSince1970: 1),
                    setIndex: pending.setIndex, server: pending.server, winner: pending.winner,
                    outcome: .doubleFault, isSecondServe: pending.isSecondServe,
                    isBreakPoint: pending.isBreakPoint, endingShot: .serve,
                    gameScoreAtStart: pending.gameScoreAtStart))
                pendingPoint = nil
                phase = .result
            } else {
                phase = .endingShot
            }
        case .endingShot:
            guard let pending = pendingPoint else { return }
            points = [PointStat(id: WalkthroughFixtures.setID(100), timestamp: Date(timeIntervalSince1970: 0),
                setIndex: pending.setIndex, server: pending.server, winner: pending.winner,
                outcome: .unforcedError, isSecondServe: false, isBreakPoint: pending.isBreakPoint,
                endingShot: .rally, gameScoreAtStart: pending.gameScoreAtStart)]
            pendingPoint = nil
            phase = .result
        case .changeover:
            changeover = nil
            phase = step == .oddSet ? .postChangeoverScore : .result
        case .postChangeoverScore: phase = .reminder
        case .reminder: phase = .nextSetGesture
        case .nextSetGesture:
            score(winner: .me)
            phase = .result
        case .stats, .result, .done: break
        }
    }
    private mutating func score(winner: Player) {
        if step == .unforcedError || step == .doubleFault {
            pendingPoint = PendingPointInfo(server: state.currentServer ?? .me, winner: winner,
                setIndex: state.sets.count - 1, isSecondServe: isOnSecondServe,
                isBreakPoint: ScoringEngine.isCurrentPointBreakPoint(state),
                gameScoreAtStart: ScoringEngine.gameScoreSnapshotAtPointStart(state))
        }
        let result = ScoringEngine.pointWon(by: winner, in: state)
        state = result.state
        isOnSecondServe = false
        recentWinners.append(winner)
        recentWinners = Array(recentWinners.suffix(8))
        state.sets = state.sets.enumerated().map { index, set in
            SetScore(id: WalkthroughFixtures.setID(index), gamesMe: set.gamesMe,
                gamesOpponent: set.gamesOpponent, isTieBreak: set.isTieBreak,
                tieBreakPointsMe: set.tieBreakPointsMe, tieBreakPointsOpponent: set.tieBreakPointsOpponent)
        }
        changeover = result.events.compactMap { if case .changeover(let c) = $0 { return c }; return nil }.first
    }
    public mutating func next() {
        guard phase != .done else { return }
        if let next = WalkthroughStep(rawValue: step.rawValue + 1) {
            self = WalkthroughSession(step: next)
        } else {
            phase = .done
            generation = UUID()
        }
    }
    /// Used by deterministic tests to run every automatic beat without waiting.
    mutating func finishDemonstration() {
        beginExample()
        let currentGeneration = generation
        for _ in 0..<8 where !demonstrationFinished {
            advanceDemonstration(generation: currentGeneration)
        }
    }
    /// The presenter calls this after showing the finished result.
    public mutating func advanceAfterResult() {
        guard demonstrationFinished else { return }
        next()
    }
    public mutating func previous() {
        if phase == .done { self = WalkthroughSession(step: .oddSet) }
        else if let previous = WalkthroughStep(rawValue: step.rawValue - 1) {
            self = WalkthroughSession(step: previous)
        }
    }
    /// An interrupted example restarts at its commentary, keeping its place in the guide.
    public mutating func restartCurrentExample() {
        guard phase != .done else { return }
        self = WalkthroughSession(step: step)
    }
}
