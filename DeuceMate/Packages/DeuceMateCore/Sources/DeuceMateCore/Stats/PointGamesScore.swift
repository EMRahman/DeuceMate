// PointGamesScore.swift — derives the running games score within a set at the
// start of each point, purely from an ordered [PointStat] array. No stored
// field carries this; it's inferred because in-game score only ever
// increases, so a point whose gameScoreAtStart resets to 0–0 always marks the
// first point of a new game. Platform-neutral: no SwiftUI.
import Foundation

/// Games won so far in the current set, from each side's perspective.
public struct GamesScoreSnapshot: Equatable, Sendable {
    public let me: Int
    public let opponent: Int
}

public enum PointGamesScore {
    /// Me–Opponent games score immediately before each point in `points`,
    /// keyed by point id. `points` must be a single set's points (all sharing
    /// `setIndex`), in chronological order. `setScores` is the match's known
    /// per-set tallies (`MatchRecord.setScores`), used to sanity-check the
    /// derivation below.
    ///
    /// Returns no entry for any point in the set when:
    /// - the set has no games concept (a deciding super-tiebreak set, or a
    ///   match format that never plays regular sets — `.superTiebreak`,
    ///   `.perpetualSuperTiebreak`, `.perpetualPoints`), or
    /// - the boundary-detected completed-games count disagrees with
    ///   `setScores[setIndex]`'s known completed-games count. This happens
    ///   when `points` is only a suffix of the set rather than its full
    ///   history — e.g. a match reconstructed via `ManualMatchEntryView` at a
    ///   non-zero games score and then resumed on the watch, where only the
    ///   resumed points are tracked. The offset can't be safely attributed to
    ///   either player, so the whole set is suppressed rather than mislabeled.
    ///
    /// Returns no entry for an individual point when its `gameScoreAtStart`
    /// is missing (matches recorded before per-point score snapshotting).
    public static func atStart(
        of points: [PointStat],
        setIndex: Int,
        matchFormat: MatchFormat,
        setScores: [SetScore]
    ) -> [PointStat.ID: GamesScoreSnapshot] {
        let cfg = matchFormat.config
        guard cfg.playRegularSets, !cfg.isDecidingSuperTiebreak(setIndex: setIndex) else {
            return [:]
        }

        var result: [PointStat.ID: GamesScoreSnapshot] = [:]
        var me = 0, opponent = 0
        for (i, point) in points.enumerated() {
            guard let snap = point.gameScoreAtStart else { continue }
            if i > 0, snap.server == 0, snap.returner == 0 {
                if points[i - 1].winner == .me { me += 1 } else { opponent += 1 }
            }
            result[point.id] = GamesScoreSnapshot(me: me, opponent: opponent)
        }

        let known = setIndex < setScores.count ? setScores[setIndex] : SetScore()
        if me == known.gamesMe, opponent == known.gamesOpponent {
            return result
        }

        // A new-game boundary is the only evidence the loop normally has that
        // the preceding point completed a game. There is no later point after
        // the final tracked point, so reconcile once more with that point's
        // post-point score — but only when its snapshot proves that it really
        // completed the regular game or tiebreak. Blindly crediting its winner
        // would make a one-game gap in a resumed history look trustworthy.
        guard let last = points.last,
              completesGame(last, setIndex: setIndex, matchFormat: matchFormat, setScores: setScores) else {
            return [:]
        }
        let finalMe = me + (last.winner == .me ? 1 : 0)
        let finalOpponent = opponent + (last.winner == .opponent ? 1 : 0)
        guard finalMe == known.gamesMe, finalOpponent == known.gamesOpponent else {
            return [:]
        }
        return result
    }

    private static func completesGame(
        _ point: PointStat,
        setIndex: Int,
        matchFormat: MatchFormat,
        setScores: [SetScore]
    ) -> Bool {
        guard let snapshot = point.gameScoreAtStart else { return false }

        var serverPoints = snapshot.server
        var returnerPoints = snapshot.returner
        if point.winner == point.server {
            serverPoints += 1
        } else {
            returnerPoints += 1
        }

        if snapshot.isTiebreak {
            guard !matchFormat.config.isEndless else { return false }
            let target = ScoringEngine.tiebreakTargetPoints(
                forSetAt: setIndex,
                in: setScores,
                format: matchFormat
            )
            return ScoringEngine.isTiebreakComplete(
                mePoints: serverPoints,
                oppPoints: returnerPoints,
                target: target,
                format: matchFormat
            )
        }

        return ScoringEngine.isRegularGameComplete(
            playerOnePoints: serverPoints,
            playerTwoPoints: returnerPoints
        )
    }
}
