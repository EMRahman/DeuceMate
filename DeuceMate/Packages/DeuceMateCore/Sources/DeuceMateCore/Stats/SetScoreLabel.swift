// SetScoreLabel.swift — canonical recorder/opponent-oriented tennis score
// formatting shared by the apps, text export, and web export.
import Foundation

public enum SetScoreLabel {
    /// Formats one set from `focal`'s perspective.
    ///
    /// Regular sets use games (and parenthesised tiebreak points when present),
    /// while tiebreak-only formats and a deciding super-tiebreak use raw points.
    public static func string(
        for set: SetScore,
        setIndex: Int,
        matchFormat: MatchFormat,
        focal: Player = .me
    ) -> String {
        let config = matchFormat.config
        if !config.playRegularSets
            || (config.isDecidingSuperTiebreak(setIndex: setIndex) && set.isTieBreak) {
            return oriented(
                me: set.tieBreakPointsMe,
                opponent: set.tieBreakPointsOpponent,
                focal: focal
            )
        }

        let games = oriented(
            me: set.gamesMe,
            opponent: set.gamesOpponent,
            focal: focal
        )
        if set.isTieBreak && set.gamesMe + set.gamesOpponent > 0 {
            let tiebreak = oriented(
                me: set.tieBreakPointsMe,
                opponent: set.tieBreakPointsOpponent,
                focal: focal
            )
            return "\(games) (\(tiebreak))"
        }
        return games
    }

    private static func oriented(me: Int, opponent: Int, focal: Player) -> String {
        focal == .me ? "\(me)–\(opponent)" : "\(opponent)–\(me)"
    }
}

public enum GameScoreLabel {
    /// Formats a point's pre-point game score in the recorder's Me–Opponent
    /// frame. `GameScoreSnapshot` is stored Server–Returner, so every caller
    /// must supply the side that served the point.
    public static func string(for snapshot: GameScoreSnapshot, server: Player) -> String {
        let points = snapshot.recorderOriented(server: server)
        if snapshot.isTiebreak {
            return "\(points.me)–\(points.opponent)"
        }

        if points.me >= 3 && points.opponent >= 3 {
            if points.me == points.opponent { return "Deuce" }
            return points.me > points.opponent ? "Ad Me" : "Ad Opp"
        }

        let labels = ["0", "15", "30", "40"]
        let me = points.me < labels.count ? labels[points.me] : "\(points.me)"
        let opponent = points.opponent < labels.count ? labels[points.opponent] : "\(points.opponent)"
        return "\(me)–\(opponent)"
    }
}

extension GameScoreSnapshot {
    func recorderOriented(server: Player) -> (me: Int, opponent: Int) {
        server == .me
            ? (me: self.server, opponent: returner)
            : (me: returner, opponent: self.server)
    }
}
