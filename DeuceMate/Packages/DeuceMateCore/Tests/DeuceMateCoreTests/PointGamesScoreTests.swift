// PointGamesScoreTests.swift — the running in-set games score derived from
// PointStat.gameScoreAtStart resets.
import XCTest
@testable import DeuceMateCore

final class PointGamesScoreTests: XCTestCase {

    private func point(
        setIndex: Int,
        winner: Player,
        server: Player = .me,
        gameScoreAtStart: GameScoreSnapshot?
    ) -> PointStat {
        PointStat(setIndex: setIndex, server: server, winner: winner, outcome: .uncategorized,
                  gameScoreAtStart: gameScoreAtStart)
    }

    private func straightGame(
        setIndex: Int,
        winner: Player,
        server: Player
    ) -> [PointStat] {
        (0..<4).map { pointIndex in
            let serverPoints = winner == server ? pointIndex : 0
            let returnerPoints = winner == server ? 0 : pointIndex
            return point(
                setIndex: setIndex,
                winner: winner,
                server: server,
                gameScoreAtStart: GameScoreSnapshot(
                    server: serverPoints,
                    returner: returnerPoints,
                    isTiebreak: false
                )
            )
        }
    }

    func test_gameByGame_incrementsCorrectPlayer() {
        let g1 = point(setIndex: 0, winner: .me,
                        gameScoreAtStart: GameScoreSnapshot(server: 0, returner: 0, isTiebreak: false))
        let g2 = point(setIndex: 0, winner: .opponent,
                        gameScoreAtStart: GameScoreSnapshot(server: 0, returner: 0, isTiebreak: false))
        let g3 = point(setIndex: 0, winner: .me,
                        gameScoreAtStart: GameScoreSnapshot(server: 0, returner: 0, isTiebreak: false))
        let points = [g1, g2, g3]
        // Two games completed so far (g1, g2); g3 is still in progress.
        let setScores = [SetScore(gamesMe: 1, gamesOpponent: 1)]

        let result = PointGamesScore.atStart(of: points, setIndex: 0, matchFormat: .standard, setScores: setScores)

        XCTAssertEqual(result[g1.id], GamesScoreSnapshot(me: 0, opponent: 0))
        XCTAssertEqual(result[g2.id], GamesScoreSnapshot(me: 1, opponent: 0))
        XCTAssertEqual(result[g3.id], GamesScoreSnapshot(me: 1, opponent: 1))
    }

    func test_midGamePoints_dontChangeGamesScore() {
        let g1p1 = point(setIndex: 0, winner: .me,
                          gameScoreAtStart: GameScoreSnapshot(server: 0, returner: 0, isTiebreak: false))
        let g1p2 = point(setIndex: 0, winner: .me,
                          gameScoreAtStart: GameScoreSnapshot(server: 1, returner: 0, isTiebreak: false))
        let g1p3 = point(setIndex: 0, winner: .me,
                          gameScoreAtStart: GameScoreSnapshot(server: 2, returner: 0, isTiebreak: false))
        let g2p1 = point(setIndex: 0, winner: .opponent,
                          gameScoreAtStart: GameScoreSnapshot(server: 0, returner: 0, isTiebreak: false))
        let points = [g1p1, g1p2, g1p3, g2p1]
        // Game 1 completed (won by me); game 2 in progress.
        let setScores = [SetScore(gamesMe: 1, gamesOpponent: 0)]

        let result = PointGamesScore.atStart(of: points, setIndex: 0, matchFormat: .standard, setScores: setScores)

        XCTAssertEqual(result[g1p1.id], GamesScoreSnapshot(me: 0, opponent: 0))
        XCTAssertEqual(result[g1p2.id], GamesScoreSnapshot(me: 0, opponent: 0))
        XCTAssertEqual(result[g1p3.id], GamesScoreSnapshot(me: 0, opponent: 0))
        XCTAssertEqual(result[g2p1.id], GamesScoreSnapshot(me: 1, opponent: 0))
    }

    func test_completedSixFourSet_reconcilesTheSetWinningPoint() {
        let winners: [Player] = [
            .me, .opponent, .me, .opponent, .me,
            .opponent, .me, .opponent, .me, .me
        ]
        let points = winners.enumerated().flatMap { gameIndex, winner in
            straightGame(
                setIndex: 0,
                winner: winner,
                server: gameIndex.isMultiple(of: 2) ? .me : .opponent
            )
        }

        let result = PointGamesScore.atStart(
            of: points,
            setIndex: 0,
            matchFormat: .standard,
            setScores: [SetScore(gamesMe: 6, gamesOpponent: 4)]
        )

        XCTAssertEqual(result.count, points.count)
        XCTAssertEqual(result[points[points.count - 4].id], GamesScoreSnapshot(me: 5, opponent: 4))
        XCTAssertEqual(result[points[points.count - 1].id], GamesScoreSnapshot(me: 5, opponent: 4))
    }

    func test_completedTiebreakSet_reconcilesTheBreakerWinningPoint() {
        let regularWinners: [Player] = [
            .me, .opponent, .me, .opponent, .me, .opponent,
            .me, .opponent, .me, .opponent, .me, .opponent
        ]
        var points = regularWinners.enumerated().flatMap { gameIndex, winner in
            straightGame(
                setIndex: 0,
                winner: winner,
                server: gameIndex.isMultiple(of: 2) ? .me : .opponent
            )
        }
        let tiebreakWinners: [Player] = [
            .me, .opponent, .me, .opponent, .me, .opponent,
            .me, .opponent, .me, .opponent, .me, .me
        ]
        var me = 0, opponent = 0
        var tiebreakPoints: [PointStat] = []
        for winner in tiebreakWinners {
            tiebreakPoints.append(point(
                setIndex: 0,
                winner: winner,
                server: .me,
                gameScoreAtStart: GameScoreSnapshot(
                    server: me,
                    returner: opponent,
                    isTiebreak: true
                )
            ))
            if winner == .me { me += 1 } else { opponent += 1 }
        }
        points.append(contentsOf: tiebreakPoints)

        let result = PointGamesScore.atStart(
            of: points,
            setIndex: 0,
            matchFormat: .standard,
            setScores: [SetScore(
                gamesMe: 7,
                gamesOpponent: 6,
                isTieBreak: true,
                tieBreakPointsMe: 7,
                tieBreakPointsOpponent: 5
            )]
        )

        XCTAssertEqual(result.count, points.count)
        XCTAssertEqual(result[tiebreakPoints[0].id], GamesScoreSnapshot(me: 6, opponent: 6))
        XCTAssertEqual(result[tiebreakPoints[tiebreakPoints.count - 1].id], GamesScoreSnapshot(me: 6, opponent: 6))
    }

    func test_liveSetWhoseLastTrackedPointEndedAGame_reconcilesThatGame() {
        let points = straightGame(setIndex: 0, winner: .me, server: .me)

        let result = PointGamesScore.atStart(
            of: points,
            setIndex: 0,
            matchFormat: .standard,
            setScores: [SetScore(gamesMe: 1, gamesOpponent: 0)]
        )

        XCTAssertEqual(result.count, points.count)
        XCTAssertEqual(result[points[points.count - 1].id], GamesScoreSnapshot(me: 0, opponent: 0))
    }

    func test_lastTrackedPointMidGame_doesNotExcuseOneGameMismatch() {
        let point = point(
            setIndex: 0,
            winner: .me,
            gameScoreAtStart: GameScoreSnapshot(server: 1, returner: 0, isTiebreak: false)
        )

        let result = PointGamesScore.atStart(
            of: [point],
            setIndex: 0,
            matchFormat: .standard,
            setScores: [SetScore(gamesMe: 1, gamesOpponent: 0)]
        )

        XCTAssertTrue(result.isEmpty)
    }

    func test_tiebreak_freezesGamesScoreThroughout() {
        let g1 = point(setIndex: 0, winner: .me,
                        gameScoreAtStart: GameScoreSnapshot(server: 0, returner: 0, isTiebreak: false))
        let g2 = point(setIndex: 0, winner: .opponent,
                        gameScoreAtStart: GameScoreSnapshot(server: 0, returner: 0, isTiebreak: false))
        let tb1 = point(setIndex: 0, winner: .me,
                         gameScoreAtStart: GameScoreSnapshot(server: 0, returner: 0, isTiebreak: true))
        let tb2 = point(setIndex: 0, winner: .opponent,
                         gameScoreAtStart: GameScoreSnapshot(server: 1, returner: 0, isTiebreak: true))
        let tb3 = point(setIndex: 0, winner: .me,
                         gameScoreAtStart: GameScoreSnapshot(server: 1, returner: 1, isTiebreak: true))
        let points = [g1, g2, tb1, tb2, tb3]
        // Games are frozen at 1–1 through the breaker until it resolves.
        let setScores = [SetScore(gamesMe: 1, gamesOpponent: 1, isTieBreak: true)]

        let result = PointGamesScore.atStart(of: points, setIndex: 0, matchFormat: .standard, setScores: setScores)

        // Games are split 1–1 heading into the breaker (g1 won by me, g2 by
        // opponent — each is its own one-point "game" in this fixture).
        XCTAssertEqual(result[tb1.id], GamesScoreSnapshot(me: 1, opponent: 1))
        // Frozen for the rest of the breaker: the breaker is a single "game"
        // that only resolves once it ends, and there's no next point in this
        // set to reveal that.
        XCTAssertEqual(result[tb2.id], GamesScoreSnapshot(me: 1, opponent: 1))
        XCTAssertEqual(result[tb3.id], GamesScoreSnapshot(me: 1, opponent: 1))
    }

    func test_decidingSuperTiebreakSet_hasNoGamesScore() {
        let decidingSetIndex = MatchFormat.standard.config.setsToWin * 2 - 2
        let p1 = point(setIndex: decidingSetIndex, winner: .me,
                        gameScoreAtStart: GameScoreSnapshot(server: 0, returner: 0, isTiebreak: true))
        let p2 = point(setIndex: decidingSetIndex, winner: .opponent,
                        gameScoreAtStart: GameScoreSnapshot(server: 1, returner: 0, isTiebreak: true))

        let result = PointGamesScore.atStart(of: [p1, p2], setIndex: decidingSetIndex, matchFormat: .standard,
                                              setScores: [])

        XCTAssertTrue(result.isEmpty)
    }

    func test_noGamesFormats_alwaysEmpty() {
        let p1 = point(setIndex: 0, winner: .me,
                        gameScoreAtStart: GameScoreSnapshot(server: 0, returner: 0, isTiebreak: true))

        XCTAssertTrue(PointGamesScore.atStart(of: [p1], setIndex: 0, matchFormat: .superTiebreak, setScores: []).isEmpty)
        XCTAssertTrue(PointGamesScore.atStart(of: [p1], setIndex: 0, matchFormat: .perpetualSuperTiebreak, setScores: []).isEmpty)
        XCTAssertTrue(PointGamesScore.atStart(of: [p1], setIndex: 0, matchFormat: .perpetualPoints, setScores: []).isEmpty)
    }

    func test_missingGameScoreAtStart_producesNoEntryAndDoesNotCrash() {
        let legacy = point(setIndex: 0, winner: .me, gameScoreAtStart: nil)
        let next = point(setIndex: 0, winner: .opponent,
                          gameScoreAtStart: GameScoreSnapshot(server: 0, returner: 0, isTiebreak: false))
        let setScores = [SetScore(gamesMe: 1, gamesOpponent: 0)]

        let result = PointGamesScore.atStart(of: [legacy, next], setIndex: 0, matchFormat: .standard,
                                              setScores: setScores)

        XCTAssertNil(result[legacy.id])
        XCTAssertNotNil(result[next.id])
    }

    // MARK: - Resumed mid-set (ManualMatchEntryView → watch handoff)

    func test_trackedPointsAreSuffixOfSet_suppressesWholeSet() {
        // A match reconstructed via ManualMatchEntryView at 4–2 games, then
        // resumed on the watch: only the resumed suffix is tracked, so these
        // two points look like the start of a fresh game (0–0, then 1–0) but
        // are really deep into the set.
        let p1 = point(setIndex: 0, winner: .me,
                        gameScoreAtStart: GameScoreSnapshot(server: 0, returner: 0, isTiebreak: false))
        let p2 = point(setIndex: 0, winner: .me,
                        gameScoreAtStart: GameScoreSnapshot(server: 1, returner: 0, isTiebreak: false))
        let setScores = [SetScore(gamesMe: 4, gamesOpponent: 2)]

        let result = PointGamesScore.atStart(of: [p1, p2], setIndex: 0, matchFormat: .standard,
                                              setScores: setScores)

        XCTAssertTrue(result.isEmpty)
    }

    func test_resumedAtFreshGameBoundary_stillSuppressedWhenPriorGamesUntracked() {
        // The resumed suffix happens to start exactly at a 0–0 game boundary
        // (a coincidence — resumption landed between games), which could fool
        // a check based only on the first point's snapshot. The completed-
        // games reconciliation against setScores still catches it.
        let p1 = point(setIndex: 0, winner: .me,
                        gameScoreAtStart: GameScoreSnapshot(server: 0, returner: 0, isTiebreak: false))
        let setScores = [SetScore(gamesMe: 3, gamesOpponent: 0)]

        let result = PointGamesScore.atStart(of: [p1], setIndex: 0, matchFormat: .standard, setScores: setScores)

        XCTAssertTrue(result.isEmpty)
    }
}
