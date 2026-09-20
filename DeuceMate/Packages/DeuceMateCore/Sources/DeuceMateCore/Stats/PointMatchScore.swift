// PointMatchScore.swift — derives the full match score immediately before
// every tracked point. Platform-neutral: no SwiftUI.
import Foundation

public enum PointMatchScore {
    /// Graph totals include the selected rally, so its tennis scores must too.
    public struct PostPointSnapshot: Equatable, Sendable {
        public let gameScoreLabel: String
        public let matchScoreLabel: String?
    }

    /// Derives display-only scores after each recorded rally using the live
    /// reducer. Never changes saved snapshots or guesses a missing games offset.
    public static func afterEachPoint(
        of points: [PointStat], record: MatchRecord
    ) -> [PointStat.ID: PostPointSnapshot] {
        let startingScores = atStart(of: points, record: record)
        var scores: [PointStat.ID: PostPointSnapshot] = [:]
        for point in points {
            guard record.setScores.indices.contains(point.setIndex),
                  let game = point.gameScoreAtStart else { continue }
            let start = startingScores[point.id]
            let raw = game.recorderOriented(server: point.server)
            let current = SetScore(
                gamesMe: start?.games?.me ?? 0,
                gamesOpponent: start?.games?.opponent ?? 0,
                isTieBreak: game.isTiebreak,
                tieBreakPointsMe: game.isTiebreak ? raw.me : 0,
                tieBreakPointsOpponent: game.isTiebreak ? raw.opponent : 0
            )
            let state = ScoringState(
                sets: Array(record.setScores.prefix(point.setIndex)) + [current],
                currentPointsMe: game.isTiebreak ? 0 : raw.me,
                currentPointsOpponent: game.isTiebreak ? 0 : raw.opponent,
                currentServer: point.server,
                pointCountInTiebreak: game.isTiebreak ? raw.me + raw.opponent : 0,
                matchType: record.matchType, matchFormat: record.matchFormat
            )
            let after = ScoringEngine.pointWon(by: point.winner, in: state).state
            let displayedGame: GameScoreSnapshot
            if game.isTiebreak {
                // Keep the winning breaker's terminal points visible rather
                // than replacing them with the next set's empty game.
                displayedGame = GameScoreSnapshot(
                    server: raw.me + (point.winner == .me ? 1 : 0),
                    returner: raw.opponent + (point.winner == .opponent ? 1 : 0),
                    isTiebreak: true
                )
            } else {
                displayedGame = GameScoreSnapshot(
                    server: after.currentPointsMe, returner: after.currentPointsOpponent,
                    isTiebreak: after.sets.last?.isTieBreak ?? false
                )
            }
            let matchLabel: String
            if start?.games != nil || !record.matchFormat.config.playRegularSets
                || record.matchFormat.config.isDecidingSuperTiebreak(setIndex: point.setIndex) {
                matchLabel = after.sets.enumerated().map { index, set in
                    SetScoreLabel.string(for: set, setIndex: index, matchFormat: record.matchFormat)
                }.joined(separator: "  ")
            } else {
                matchLabel = start?.completedSets.joined(separator: "  ") ?? ""
            }
            scores[point.id] = PostPointSnapshot(
                gameScoreLabel: GameScoreLabel.string(for: displayedGame, server: .me),
                matchScoreLabel: matchLabel.isEmpty ? nil : matchLabel
            )
        }
        return scores
    }

    public struct Snapshot: Equatable, Sendable {
        /// Authoritative completed-set labels before this point's set.
        public let completedSets: [String]
        /// The live score of this point's own set. Nil when the tracked points
        /// are only a suffix and the games offset cannot be attributed safely.
        public let currentSet: String?
        /// Raw games behind `currentSet`, when this format has regular games.
        public let games: GamesScoreSnapshot?

        public var label: String {
            (completedSets + [currentSet].compactMap { $0 }).joined(separator: "  ")
        }
    }

    /// Full recorder-perspective match score immediately before each point,
    /// keyed by point id. `points` must be the match's chronological point
    /// history. Points without a pre-point game snapshot are omitted.
    public static func atStart(
        of points: [PointStat],
        record: MatchRecord
    ) -> [PointStat.ID: Snapshot] {
        let config = record.matchFormat.config
        let pointsBySet = Dictionary(grouping: points, by: \.setIndex)
        var gamesByPoint: [PointStat.ID: GamesScoreSnapshot] = [:]
        for (setIndex, setPoints) in pointsBySet {
            let derived = PointGamesScore.atStart(
                of: setPoints,
                setIndex: setIndex,
                matchFormat: record.matchFormat,
                setScores: record.setScores
            )
            gamesByPoint.merge(derived) { _, latest in latest }
        }

        var priorLabelsBySet: [Int: [String]] = [:]
        var result: [PointStat.ID: Snapshot] = [:]
        result.reserveCapacity(points.count)

        for point in points {
            guard point.setIndex >= 0,
                  let gameScore = point.gameScoreAtStart else { continue }

            let completedSets: [String]
            if let cached = priorLabelsBySet[point.setIndex] {
                completedSets = cached
            } else {
                completedSets = record.setScores.indices
                    .prefix(point.setIndex)
                    .map { index in
                        SetScoreLabel.string(
                            for: record.setScores[index],
                            setIndex: index,
                            matchFormat: record.matchFormat
                        )
                    }
                priorLabelsBySet[point.setIndex] = completedSets
            }

            if !config.playRegularSets
                || config.isDecidingSuperTiebreak(setIndex: point.setIndex) {
                let rawPoints = gameScore.recorderOriented(server: point.server)
                let current = SetScoreLabel.string(
                    for: SetScore(
                        isTieBreak: true,
                        tieBreakPointsMe: rawPoints.me,
                        tieBreakPointsOpponent: rawPoints.opponent
                    ),
                    setIndex: point.setIndex,
                    matchFormat: record.matchFormat
                )
                result[point.id] = Snapshot(
                    completedSets: completedSets,
                    currentSet: current,
                    games: nil
                )
                continue
            }

            guard let games = gamesByPoint[point.id] else {
                result[point.id] = Snapshot(
                    completedSets: completedSets,
                    currentSet: nil,
                    games: nil
                )
                continue
            }

            let rawPoints = gameScore.recorderOriented(server: point.server)
            let current = SetScoreLabel.string(
                for: SetScore(
                    gamesMe: games.me,
                    gamesOpponent: games.opponent,
                    isTieBreak: gameScore.isTiebreak,
                    tieBreakPointsMe: rawPoints.me,
                    tieBreakPointsOpponent: rawPoints.opponent
                ),
                setIndex: point.setIndex,
                matchFormat: record.matchFormat
            )
            result[point.id] = Snapshot(
                completedSets: completedSets,
                currentSet: current,
                games: games
            )
        }

        return result
    }
}
