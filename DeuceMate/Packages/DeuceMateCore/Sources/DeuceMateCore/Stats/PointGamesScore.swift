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
    /// `setIndex`), in chronological order.
    ///
    /// Returns no entry for a point when:
    /// - the set has no games concept (a deciding super-tiebreak set, or a
    ///   match format that never plays regular sets — `.superTiebreak`,
    ///   `.perpetualSuperTiebreak`, `.perpetualPoints`), or
    /// - `gameScoreAtStart` is missing on that point (matches recorded before
    ///   per-point score snapshotting).
    public static func atStart(
        of points: [PointStat],
        setIndex: Int,
        matchFormat: MatchFormat
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
        return result
    }
}
