// PointMatchScoreTests.swift — full recorder-perspective score at each point.
import XCTest
@testable import DeuceMateCore

final class PointMatchScoreTests: XCTestCase {
    func test_standard_carriesCompletedTiebreakSetIntoNextSet() throws {
        let point = makePoint(setIndex: 1, server: .me, winner: .me, serverPoints: 0, returnerPoints: 0)
        let record = makeRecord(
            format: .standard,
            setScores: [
                SetScore(
                    gamesMe: 6,
                    gamesOpponent: 7,
                    isTieBreak: true,
                    tieBreakPointsMe: 7,
                    tieBreakPointsOpponent: 9
                ),
                SetScore()
            ],
            stats: [point]
        )

        let snapshot = try XCTUnwrap(PointMatchScore.atStart(of: record.stats, record: record)[point.id])

        XCTAssertEqual(snapshot.completedSets, ["6–7 (7–9)"])
        XCTAssertEqual(snapshot.currentSet, "0–0")
        XCTAssertEqual(snapshot.games, GamesScoreSnapshot(me: 0, opponent: 0))
        XCTAssertEqual(snapshot.label, "6–7 (7–9)  0–0")
    }

    func test_standard_inSetTiebreakKeepsGamesAndAddsBreakerPoints() throws {
        let points = pointsEnteringTiebreak(setIndex: 0, gamesEach: 6)
        let selected = makePoint(
            setIndex: 0,
            server: .opponent,
            winner: .me,
            serverPoints: 2,
            returnerPoints: 3,
            isTiebreak: true
        )
        let stats = points + [selected]
        let record = makeRecord(
            format: .standard,
            setScores: [SetScore(
                gamesMe: 6,
                gamesOpponent: 6,
                isTieBreak: true,
                tieBreakPointsMe: 4,
                tieBreakPointsOpponent: 2
            )],
            stats: stats
        )

        let snapshot = try XCTUnwrap(PointMatchScore.atStart(of: stats, record: record)[selected.id])

        XCTAssertEqual(snapshot.currentSet, "6–6 (3–2)")
        XCTAssertEqual(snapshot.games, GamesScoreSnapshot(me: 6, opponent: 6))
    }

    func test_standard_decidingSuperTiebreakUsesRawPoints() throws {
        let point = makePoint(
            setIndex: 2,
            server: .opponent,
            winner: .me,
            serverPoints: 5,
            returnerPoints: 7,
            isTiebreak: true
        )
        let record = makeRecord(
            format: .standard,
            setScores: [
                SetScore(gamesMe: 6, gamesOpponent: 4),
                SetScore(gamesMe: 4, gamesOpponent: 6),
                SetScore(isTieBreak: true, tieBreakPointsMe: 8, tieBreakPointsOpponent: 5)
            ],
            stats: [point]
        )

        let snapshot = try XCTUnwrap(PointMatchScore.atStart(of: record.stats, record: record)[point.id])

        XCTAssertEqual(snapshot.currentSet, "7–5")
        XCTAssertNil(snapshot.games)
        XCTAssertEqual(snapshot.label, "6–4  4–6  7–5")
    }

    func test_fullFinalSetFormatTreatsDeciderAsRegularSet() throws {
        let point = makePoint(setIndex: 2, server: .me, winner: .me, serverPoints: 0, returnerPoints: 0)
        let record = makeRecord(
            format: .bestOf3FullFinalSet,
            setScores: [
                SetScore(gamesMe: 6, gamesOpponent: 4),
                SetScore(gamesMe: 4, gamesOpponent: 6),
                SetScore()
            ],
            stats: [point]
        )

        let snapshot = try XCTUnwrap(PointMatchScore.atStart(of: record.stats, record: record)[point.id])

        XCTAssertEqual(snapshot.currentSet, "0–0")
        XCTAssertEqual(snapshot.games, GamesScoreSnapshot(me: 0, opponent: 0))
    }

    func test_quickFourFormatsSuddenDeathAsGamesPlusTiebreakPoints() throws {
        let points = pointsEnteringTiebreak(setIndex: 0, gamesEach: 2)
        let selected = points[points.count - 1]
        let record = makeRecord(
            format: .quick4Games,
            setScores: [SetScore(
                gamesMe: 3,
                gamesOpponent: 2,
                isTieBreak: true,
                tieBreakPointsMe: 1,
                tieBreakPointsOpponent: 0
            )],
            stats: points
        )

        let snapshot = try XCTUnwrap(PointMatchScore.atStart(of: points, record: record)[selected.id])

        XCTAssertEqual(snapshot.currentSet, "2–2 (0–0)")
        XCTAssertEqual(snapshot.games, GamesScoreSnapshot(me: 2, opponent: 2))
    }

    func test_superTiebreakFormatUsesRawPoints() throws {
        let point = makePoint(
            setIndex: 0,
            server: .me,
            winner: .opponent,
            serverPoints: 6,
            returnerPoints: 4,
            isTiebreak: true
        )
        let record = makeRecord(
            format: .superTiebreak,
            setScores: [SetScore(isTieBreak: true, tieBreakPointsMe: 6, tieBreakPointsOpponent: 5)],
            stats: [point]
        )

        let snapshot = try XCTUnwrap(PointMatchScore.atStart(of: record.stats, record: record)[point.id])

        XCTAssertEqual(snapshot.currentSet, "6–4")
        XCTAssertNil(snapshot.games)
    }

    func test_perpetualSuperTiebreakCarriesPriorBreakerScores() throws {
        let point = makePoint(
            setIndex: 2,
            server: .opponent,
            winner: .me,
            serverPoints: 3,
            returnerPoints: 4,
            isTiebreak: true
        )
        let record = makeRecord(
            format: .perpetualSuperTiebreak,
            setScores: [
                SetScore(isTieBreak: true, tieBreakPointsMe: 10, tieBreakPointsOpponent: 8),
                SetScore(isTieBreak: true, tieBreakPointsMe: 10, tieBreakPointsOpponent: 7),
                SetScore(isTieBreak: true, tieBreakPointsMe: 5, tieBreakPointsOpponent: 3)
            ],
            stats: [point]
        )

        let snapshot = try XCTUnwrap(PointMatchScore.atStart(of: record.stats, record: record)[point.id])

        XCTAssertEqual(snapshot.label, "10–8  10–7  4–3")
    }

    func test_perpetualPointsHasNoTrackedPointSnapshotsToFormat() {
        let record = makeRecord(
            format: .perpetualPoints,
            setScores: [SetScore(isTieBreak: true, tieBreakPointsMe: 20, tieBreakPointsOpponent: 18)],
            stats: []
        )

        XCTAssertTrue(PointMatchScore.atStart(of: record.stats, record: record).isEmpty)
    }

    func test_suffixHistoryKeepsPriorSetsAndOmitsUnknownCurrentSet() throws {
        let point = makePoint(setIndex: 1, server: .me, winner: .me, serverPoints: 1, returnerPoints: 0)
        let record = makeRecord(
            format: .standard,
            setScores: [
                SetScore(gamesMe: 6, gamesOpponent: 4),
                SetScore(gamesMe: 4, gamesOpponent: 2)
            ],
            stats: [point]
        )

        let snapshot = try XCTUnwrap(PointMatchScore.atStart(of: record.stats, record: record)[point.id])

        XCTAssertEqual(snapshot.completedSets, ["6–4"])
        XCTAssertNil(snapshot.currentSet)
        XCTAssertNil(snapshot.games)
        XCTAssertEqual(snapshot.label, "6–4")
    }

    func test_legacyPointWithoutSnapshotIsOmitted() {
        let point = PointStat(
            setIndex: 0,
            server: .me,
            winner: .me,
            outcome: .uncategorized,
            gameScoreAtStart: nil
        )
        let record = makeRecord(
            format: .standard,
            setScores: [SetScore(gamesMe: 6, gamesOpponent: 4)],
            stats: [point]
        )

        XCTAssertTrue(PointMatchScore.atStart(of: record.stats, record: record).isEmpty)
    }

    private func makePoint(
        setIndex: Int,
        server: Player,
        winner: Player,
        serverPoints: Int,
        returnerPoints: Int,
        isTiebreak: Bool = false
    ) -> PointStat {
        PointStat(
            setIndex: setIndex,
            server: server,
            winner: winner,
            outcome: .uncategorized,
            gameScoreAtStart: GameScoreSnapshot(
                server: serverPoints,
                returner: returnerPoints,
                isTiebreak: isTiebreak
            )
        )
    }

    /// Synthetic one-point game boundaries are sufficient here because these
    /// tests exercise full-match composition; realistic game completion is
    /// covered separately by PointGamesScoreTests.
    private func pointsEnteringTiebreak(setIndex: Int, gamesEach: Int) -> [PointStat] {
        var points: [PointStat] = []
        for gameIndex in 0..<(gamesEach * 2) {
            let winner: Player = gameIndex.isMultiple(of: 2) ? .me : .opponent
            points.append(makePoint(
                setIndex: setIndex,
                server: winner,
                winner: winner,
                serverPoints: 0,
                returnerPoints: 0
            ))
        }
        points.append(makePoint(
            setIndex: setIndex,
            server: .me,
            winner: .me,
            serverPoints: 0,
            returnerPoints: 0,
            isTiebreak: true
        ))
        return points
    }

    private func makeRecord(
        format: MatchFormat,
        setScores: [SetScore],
        stats: [PointStat]
    ) -> MatchRecord {
        MatchRecord(
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            setScores: setScores,
            stats: stats,
            matchFormat: format
        )
    }
}
