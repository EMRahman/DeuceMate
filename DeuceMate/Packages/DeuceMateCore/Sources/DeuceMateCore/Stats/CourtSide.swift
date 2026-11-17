// CourtSide.swift — which half of the court a point was served from, derived
// from the game score saved before it. Platform-neutral: no SwiftUI.
//
// Deliberately NOT Codable and never persisted: it is a pure projection of
// `PointStat.gameScoreAtStart`, so there is no schema to keep compatible.
import Foundation

/// The service court a point was played from. The server and returner are
/// always on the same side (diagonally across the net), so a point's side
/// answers both "where did I serve from?" and "where did I return from?".
public enum CourtSide: String, CaseIterable, Identifiable, Sendable {
    case deuce, ad

    public var id: String { rawValue }

    public var displayLabel: String {
        switch self {
        case .deuce: return "Deuce"
        case .ad:    return "Ad"
        }
    }

    /// The side `point` was served from, or `nil` when it can't be known.
    ///
    /// The first point of every game and tiebreak is served from the deuce
    /// side, and the server then alternates every point — so an even number of
    /// points already played in the game (or tiebreak) means deuce, odd means
    /// ad. That holds through deuce/advantage (3–3 is even, 4–3 odd, 4–4 even)
    /// and through tiebreak server rotation, in singles and doubles alike.
    ///
    /// `nil` when:
    /// - the point carries no `gameScoreAtStart` (matches recorded before
    ///   per-point score capture), or
    /// - it is a no-ad deciding point (40–40 outside a tiebreak with
    ///   `noAdScoring`), where the RECEIVER chooses the side and the archive
    ///   doesn't record the choice. Guessing deuce would quietly misfile it.
    public static func of(_ point: PointStat, noAdScoring: Bool) -> CourtSide? {
        guard let score = point.gameScoreAtStart else { return nil }
        if noAdScoring, !score.isTiebreak, score.server >= 3, score.returner >= 3 {
            return nil
        }
        return (score.server + score.returner) % 2 == 0 ? .deuce : .ad
    }
}
