import Foundation

public enum WalkthroughStep: Int, CaseIterable, Identifiable, Sendable {
    case winPoint = 1, losePoint, undoPoint, unforcedError, secondServe, doubleFault, findStat, winGame, oddSet
    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .winPoint: return "Win a point"
        case .losePoint: return "Lose a point"
        case .undoPoint: return "Correct a mistake"
        case .unforcedError: return "Record your error"
        case .secondServe: return "Mark a second serve"
        case .doubleFault: return "Record a double fault"
        case .findStat: return "Find that stat"
        case .winGame: return "Win a game"
        case .oddSet: return "Set: change ends"
        }
    }
    public var introduction: String {
        switch self {
        case .winPoint: return "Swipe up when you win a point."
        case .losePoint: return "Swipe down when you lose a point."
        case .undoPoint: return "Made a mistake? Swipe left to undo the last point."
        case .unforcedError: return "If point tracking enabled; record your loss for an unforced error during a rally."
        case .secondServe: return "If point tracking enabled; double tap to record a second serve"
        case .doubleFault: return "If point tracking enabled; double fault can be logged."
        case .findStat: return "If point tracking enabled; swipe right to open Live Stats and reveal Errors."
        case .winGame: return "You lead 1–0 in games and serve at 40–0. Watch the game-winning point."
        case .oddSet: return "40–0 at 5–3. One point wins the set. Notice the sticky reminder until the next point"
        }
    }
}

/// Valid pre-point fixtures; deliberately separate later-match examples.
public enum WalkthroughFixtures {
    /// Display-only values. They are never written to a match or read from HealthKit.
    public static func demoMetrics(for step: WalkthroughStep) -> (heartRate: Int, kilocalories: Int, elapsedSeconds: Int) {
        switch step {
        case .winPoint: return (128, 18, 8 * 60 + 12)
        case .losePoint: return (131, 19, 8 * 60 + 34)
        case .undoPoint: return (132, 20, 8 * 60 + 49)
        case .unforcedError: return (135, 21, 9 * 60 + 6)
        case .secondServe: return (136, 22, 9 * 60 + 20)
        case .doubleFault: return (137, 23, 9 * 60 + 34)
        case .findStat: return (138, 24, 9 * 60 + 47)
        case .winGame: return (143, 68, 31 * 60 + 42)
        case .oddSet: return (151, 192, 88 * 60 + 5)
        }
    }
    /// Recent winners are synthetic but agree with the visible fixture score.
    public static func recentWinners(for step: WalkthroughStep) -> [Player] {
        switch step {
        case .winPoint, .unforcedError: return []
        case .losePoint: return [.me]
        case .undoPoint: return [.me, .opponent]
        case .secondServe, .doubleFault: return [.opponent]
        case .findStat: return [.opponent, .opponent]
        case .winGame, .oddSet: return [.opponent, .me, .me, .me]
        }
    }
    public static func setID(_ index: Int) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, UInt8(clamping: index)))
    }
    public static func state(for step: WalkthroughStep) -> ScoringState {
        switch step {
        case .winPoint, .unforcedError: return ScoringState(sets: [SetScore(id: setID(0))], currentServer: .me)
        case .losePoint: return ScoringState(sets: [SetScore(id: setID(0))], currentPointsMe: 1, currentServer: .me)
        case .undoPoint: return ScoringState(sets: [SetScore(id: setID(0))], currentPointsMe: 1, currentPointsOpponent: 1, currentServer: .me)
        case .secondServe, .doubleFault: return ScoringState(sets: [SetScore(id: setID(0))], currentPointsOpponent: 1, currentServer: .me)
        case .findStat: return ScoringState(sets: [SetScore(id: setID(0))], currentPointsOpponent: 2, currentServer: .me)
        case .winGame: return later(gamesMe: 1, gamesOpponent: 0)
        case .oddSet: return later(gamesMe: 5, gamesOpponent: 3)
        }
    }
    private static func later(gamesMe: Int, gamesOpponent: Int) -> ScoringState {
        ScoringState(sets: [SetScore(id: setID(0), gamesMe: gamesMe, gamesOpponent: gamesOpponent)],
                     currentPointsMe: 3, currentServer: .me, gameCount: gamesMe + gamesOpponent)
    }
    public static var errorPoint: PointStat {
        PointStat(id: setID(100), timestamp: Date(timeIntervalSince1970: 0), setIndex: 0, server: .me,
                  winner: .opponent, outcome: .unforcedError, endingShot: .rally,
                  gameScoreAtStart: GameScoreSnapshot(server: 0, returner: 0, isTiebreak: false))
    }
    public static var doubleFaultPoint: PointStat {
        PointStat(id: setID(101), timestamp: Date(timeIntervalSince1970: 1), setIndex: 0,
                  server: .me, winner: .opponent, outcome: .doubleFault,
                  isSecondServe: true, endingShot: .serve,
                  gameScoreAtStart: GameScoreSnapshot(server: 0, returner: 1, isTiebreak: false))
    }
}
