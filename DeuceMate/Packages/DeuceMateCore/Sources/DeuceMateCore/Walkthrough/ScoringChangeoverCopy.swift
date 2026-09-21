public extension ScoringChangeoverReason {
    var displayText: String {
        switch self {
        case .oddGames:
            return "Odd games – players change ends"
        case .evenGames:
            return "Even games – balls change ends"
        case .setCompletePlayers:
            return "Set complete – players change ends"
        case .setCompleteBalls:
            return "Set complete – balls change ends"
        case .setCompletePlayersAndBalls:
            return "Set complete – players & balls change ends"
        case .tiebreakSixPoints:
            return "Every 6 tiebreak points – players & balls change ends"
        case .tiebreakOddPoint:
            return "Odd tiebreak point – balls change ends"
        case .tiebreakBegins(let games):
            return "Games at \(games)-\(games) – tiebreak begins"
        case .suddenDeathBegins(let games):
            return "Games at \(games)-\(games) – sudden death point"
        }
    }
}
