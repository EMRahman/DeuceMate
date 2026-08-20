// CompactScoreLine.swift — the narrow, hyphen-separated score line the watch
// prints where `SetScoreLabel`'s en-dashed, space-padded form would not fit
// (the stats header and the history rows, which built the same string twice).
//
// The recorder is always on the left ("Me–Opponent"); the phone, the text
// export and the web export use `SetScoreLabel` instead.
import Foundation

public enum CompactScoreLine {

    /// One set: games, games with the tiebreak parenthetical, or raw tiebreak
    /// points for tiebreak-only formats and a deciding super-tiebreak.
    public static func setScore(_ set: SetScore, setIndex: Int, matchFormat: MatchFormat) -> String {
        let config = matchFormat.config
        if !config.playRegularSets
            || (config.isDecidingSuperTiebreak(setIndex: setIndex) && set.isTieBreak) {
            return "\(set.tieBreakPointsMe)-\(set.tieBreakPointsOpponent)"
        }
        if set.isTieBreak && set.gamesMe + set.gamesOpponent > 0 {
            return "\(set.gamesMe)-\(set.gamesOpponent)(\(set.tieBreakPointsMe)-\(set.tieBreakPointsOpponent))"
        }
        if set.isTieBreak {
            return "\(set.tieBreakPointsMe)-\(set.tieBreakPointsOpponent)"
        }
        return "\(set.gamesMe)-\(set.gamesOpponent)"
    }

    /// Every set of a finished match, e.g. "6-4  4-6  10-8".
    public static func completed(
        setScores: [SetScore],
        matchFormat: MatchFormat,
        separator: String = "  "
    ) -> String {
        setScores.enumerated()
            .map { setScore($1, setIndex: $0, matchFormat: matchFormat) }
            .joined(separator: separator)
    }

    /// Completed sets plus the live one, e.g. "6-4  3-2  (40-30)" or
    /// "6-4  TB 5-3". `nil` when no set has been started yet.
    public static func inProgress(_ record: MatchRecord, separator: String = "  ") -> String? {
        guard !record.setScores.isEmpty else { return nil }
        var parts = record.setScores.dropLast().enumerated().map {
            setScore($1, setIndex: $0, matchFormat: record.matchFormat)
        }
        if let current = record.setScores.last {
            if current.isTieBreak {
                parts.append("TB \(current.tieBreakPointsMe)-\(current.tieBreakPointsOpponent)")
            } else {
                parts.append("\(current.gamesMe)-\(current.gamesOpponent)")
                if let gameScore = MatchRecord.gameScoreString(
                    mePoints: record.currentPointsMe,
                    oppPoints: record.currentPointsOpponent
                ) {
                    parts.append("(\(gameScore))")
                }
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: separator)
    }
}
