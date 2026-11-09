import XCTest
@testable import DeuceMateCore

final class ScoringEngineTests: XCTestCase {

    // MARK: - Tiebreak resolution (original tests)

    func test_standardTiebreakCanExtendToTenEightAndNextServerIsFirstReceiver() {
        var state = ScoringState(currentServer: .me)

        for _ in 0..<5 {
            winGame(&state, player: .me)
            winGame(&state, player: .opponent)
        }
        winGame(&state, player: .me)
        winGame(&state, player: .opponent)

        XCTAssertEqual(state.sets.first?.isTieBreak, true)
        XCTAssertEqual(state.sets.first?.gamesMe, 6)
        XCTAssertEqual(state.sets.first?.gamesOpponent, 6)

        let tiebreakServer = state.tiebreakStartServer
        let firstReceiver = state.tiebreakFirstPointReceiver

        winTiebreakPoints(&state, player: .me, points: 6)
        winTiebreakPoints(&state, player: .opponent, points: 6)
        point(&state, player: .me)
        point(&state, player: .opponent)
        point(&state, player: .me)
        point(&state, player: .opponent)
        winTiebreakPoints(&state, player: .me, points: 2)

        XCTAssertEqual(state.sets[0].tieBreakPointsMe, 10)
        XCTAssertEqual(state.sets[0].tieBreakPointsOpponent, 8)
        XCTAssertEqual(state.sets[0].gamesMe, 7)
        XCTAssertGreaterThanOrEqual(state.sets.count, 2)
        XCTAssertEqual(state.currentServer, firstReceiver)
        XCTAssertNotEqual(state.currentServer, tiebreakServer)
    }

    func test_superTiebreakMatchFinishesToTen() {
        var state = ScoringState(currentServer: .me)

        winGame(&state, player: .me, count: 6)
        winGame(&state, player: .opponent, count: 6)

        XCTAssertEqual(state.sets.count, 3)
        XCTAssertEqual(state.sets[2].isTieBreak, true)

        winTiebreakPoints(&state, player: .me, points: 10)

        XCTAssertTrue(ScoringEngine.isMatchComplete(state))
        XCTAssertEqual(ScoringEngine.matchWinner(state), .me)
        XCTAssertEqual(state.sets[2].tieBreakPointsMe, 10)
        XCTAssertEqual(state.sets[2].tieBreakPointsOpponent, 0)
        XCTAssertEqual(state.sets[2].gamesMe, 7)
    }

    func test_doublesServiceRotationDuringSuperTiebreak() {
        var state = ScoringState(
            currentServer: .me,
            matchType: .doubles,
            doublesServer: .me,
            doublesServiceOrder: [.me, .opponentS1, .partner, .opponentS2],
            doublesServiceIndex: 0
        )

        winGame(&state, player: .me, count: 6)
        winGame(&state, player: .opponent, count: 6)

        XCTAssertEqual(state.sets[2].isTieBreak, true)
        XCTAssertEqual(state.tiebreakStartServer, state.currentServer)

        point(&state, player: .me)
        XCTAssertEqual(state.doublesServer, .opponentS1)
        point(&state, player: .opponent)
        XCTAssertEqual(state.doublesServer, .opponentS1)
        point(&state, player: .me)
        XCTAssertEqual(state.doublesServer, .partner)
    }

    // MARK: - Basic game scoring

    func test_pointsResetAfterGameWon() {
        var state = ScoringState(currentServer: .me)
        winGame(&state, player: .me)
        XCTAssertEqual(state.currentPointsMe, 0)
        XCTAssertEqual(state.currentPointsOpponent, 0)
    }

    func test_serverAlternatesAfterEachGame() {
        var state = ScoringState(currentServer: .me)
        XCTAssertEqual(state.currentServer, .me)
        winGame(&state, player: .me)
        XCTAssertEqual(state.currentServer, .opponent)
        winGame(&state, player: .opponent)
        XCTAssertEqual(state.currentServer, .me)
        winGame(&state, player: .me)
        XCTAssertEqual(state.currentServer, .opponent)
    }

    func test_deuceRequiresTwoConsecutivePointsToWinGame() {
        var state = ScoringState(currentServer: .me)
        // Reach 3-3 (deuce)
        for _ in 0..<3 { point(&state, player: .me) }
        for _ in 0..<3 { point(&state, player: .opponent) }
        XCTAssertEqual(state.sets.first?.gamesMe, 0, "No game should be won at deuce")

        // Advantage me (4-3)
        point(&state, player: .me)
        XCTAssertEqual(state.currentPointsMe, 4)
        XCTAssertEqual(state.currentPointsOpponent, 3)
        XCTAssertEqual(state.sets.first?.gamesMe, 0, "4-3 is not yet a game")

        // Back to deuce (4-4)
        point(&state, player: .opponent)
        XCTAssertEqual(state.sets.first?.gamesMe, 0)

        // Two consecutive points from deuce: 5-4, then 6-4 → game
        point(&state, player: .me) // 5-4, still no game (diff=1)
        XCTAssertEqual(state.sets.first?.gamesMe, 0)
        point(&state, player: .me) // 6-4, diff=2 → game won
        XCTAssertEqual(state.sets.first?.gamesMe, 1)
        XCTAssertEqual(state.currentPointsMe, 0)
        XCTAssertEqual(state.currentPointsOpponent, 0)
    }

    func test_regularGameCompletionRule_isPerspectiveNeutral() {
        XCTAssertFalse(ScoringEngine.isRegularGameComplete(playerOnePoints: 3, playerTwoPoints: 0))
        XCTAssertFalse(ScoringEngine.isRegularGameComplete(playerOnePoints: 4, playerTwoPoints: 3))
        XCTAssertFalse(ScoringEngine.isRegularGameComplete(playerOnePoints: 5, playerTwoPoints: 4))
        XCTAssertTrue(ScoringEngine.isRegularGameComplete(playerOnePoints: 4, playerTwoPoints: 0))
        XCTAssertTrue(ScoringEngine.isRegularGameComplete(playerOnePoints: 6, playerTwoPoints: 4))
        XCTAssertTrue(ScoringEngine.isRegularGameComplete(playerOnePoints: 4, playerTwoPoints: 6))
    }

    // MARK: - Break point detection

    func test_breakPointDetection() {
        // 0-3: returner at 40, server at 0 → break point
        var state = ScoringState(currentServer: .me)
        for _ in 0..<3 { point(&state, player: .opponent) }
        XCTAssertTrue(ScoringEngine.isCurrentPointBreakPoint(state),
                      "Returner at 40, server at 0 should be a break point")

        // 3-3 deuce → not a break point
        for _ in 0..<3 { point(&state, player: .me) }
        XCTAssertFalse(ScoringEngine.isCurrentPointBreakPoint(state),
                       "Deuce is not a break point")

        // 3-4: returner has advantage → break point
        point(&state, player: .opponent)
        XCTAssertTrue(ScoringEngine.isCurrentPointBreakPoint(state),
                      "Returner advantage should be a break point")

        // Server ahead 3-2 → not a break point
        var state2 = ScoringState(currentServer: .me)
        for _ in 0..<3 { point(&state2, player: .me) }
        for _ in 0..<2 { point(&state2, player: .opponent) }
        XCTAssertFalse(ScoringEngine.isCurrentPointBreakPoint(state2),
                       "Server ahead is not a break point")

        // In a tiebreak → never a break point regardless of score
        var tbState = ScoringState(currentServer: .me)
        for _ in 0..<6 { winGame(&tbState, player: .me); winGame(&tbState, player: .opponent) }
        for _ in 0..<3 { winTiebreakPoints(&tbState, player: .opponent, points: 1) }
        XCTAssertFalse(ScoringEngine.isCurrentPointBreakPoint(tbState),
                       "Break points do not exist in a tiebreak")
    }

    // MARK: - Game score snapshot

    func test_gameScoreSnapshotDuringRegularPlay() throws {
        var state = ScoringState(currentServer: .me)
        point(&state, player: .me)
        point(&state, player: .me)
        point(&state, player: .opponent)
        // Server (me) has 2 pts; returner (opponent) has 1

        let snap = try XCTUnwrap(ScoringEngine.gameScoreSnapshotAtPointStart(state))
        XCTAssertEqual(snap.isTiebreak, false)
        XCTAssertEqual(snap.server, 2)
        XCTAssertEqual(snap.returner, 1)
    }

    func test_gameScoreSnapshotDuringTiebreakUsesTiebreakPoints() throws {
        var state = ScoringState(currentServer: .me)
        for _ in 0..<6 { winGame(&state, player: .me); winGame(&state, player: .opponent) }
        XCTAssertEqual(state.sets.last?.isTieBreak, true)

        winTiebreakPoints(&state, player: .me, points: 3)

        let snap = try XCTUnwrap(ScoringEngine.gameScoreSnapshotAtPointStart(state))
        XCTAssertEqual(snap.isTiebreak, true)

        let server = try XCTUnwrap(state.currentServer)
        let tbSet = try XCTUnwrap(state.sets.last)
        let expectedServerPts = server == .me ? tbSet.tieBreakPointsMe : tbSet.tieBreakPointsOpponent
        let expectedReturnerPts = server == .me ? tbSet.tieBreakPointsOpponent : tbSet.tieBreakPointsMe
        XCTAssertEqual(snap.server, expectedServerPts)
        XCTAssertEqual(snap.returner, expectedReturnerPts)
    }

    func test_gameScoreSnapshotReturnsNilWithNoServer() {
        let state = ScoringState() // currentServer defaults to nil
        XCTAssertNil(ScoringEngine.gameScoreSnapshotAtPointStart(state))
    }

    // MARK: - Ends-switch reminder

    func test_nextSetRequiresEndsSwitchNilBeforeAnySetCompletes() {
        var state = ScoringState(currentServer: .me)
        point(&state, player: .me)
        XCTAssertNil(ScoringEngine.nextSetRequiresEndsSwitch(state))
    }

    func test_nextSetRequiresEndsSwitchTrueAfterOddGamesSet() {
        // 6-1 → 7 total games (odd) → switch
        var state = ScoringState(currentServer: .me)
        winGame(&state, player: .me, count: 5)
        winGame(&state, player: .opponent, count: 1)
        for _ in 0..<3 { point(&state, player: .me) }
        state = ScoringEngine.pointWon(by: .me, in: state).state

        XCTAssertEqual(state.sets.count, 2)
        XCTAssertEqual(ScoringEngine.nextSetRequiresEndsSwitch(state), true)
    }

    func test_nextSetRequiresEndsSwitchFalseAfterEvenGamesSet() {
        // 6-0 → 6 total games (even) → stay
        var state = ScoringState(currentServer: .me)
        winGame(&state, player: .me, count: 5)
        for _ in 0..<3 { point(&state, player: .me) }
        state = ScoringEngine.pointWon(by: .me, in: state).state

        XCTAssertEqual(state.sets.count, 2)
        XCTAssertEqual(ScoringEngine.nextSetRequiresEndsSwitch(state), false)
    }

    func test_nextSetRequiresEndsSwitchTrueAfterTiebreakDecidedSet() {
        // A tiebreak winner always records loserGames + 1 games, so the
        // finished set's total is always odd — switching is a certainty,
        // not just a common case (see plan §3).
        var state = ScoringState(currentServer: .me)
        for _ in 0..<6 { winGame(&state, player: .me); winGame(&state, player: .opponent) }
        XCTAssertEqual(state.sets.first?.isTieBreak, true)
        winTiebreakPoints(&state, player: .me, points: 7)

        XCTAssertEqual(state.sets.count, 2)
        XCTAssertEqual(ScoringEngine.nextSetRequiresEndsSwitch(state), true)
    }

    func test_nextSetRequiresEndsSwitchNilBeforeMatchDecidingSuperTiebreak() {
        // 1-1 sets in .standard → the "next set" is a super tiebreak, not a
        // regular set; the one-time switch/stay reminder doesn't apply
        // (deferred scope, see plan §6).
        var state = ScoringState(currentServer: .me)
        winGame(&state, player: .me, count: 6)
        winGame(&state, player: .opponent, count: 6)

        XCTAssertEqual(state.sets.count, 3)
        XCTAssertEqual(state.sets[2].isTieBreak, true)
        XCTAssertNil(ScoringEngine.nextSetRequiresEndsSwitch(state))
    }

    func test_nextSetRequiresEndsSwitchNilAfterFirstPointOfNewSet() {
        var state = ScoringState(currentServer: .me)
        winGame(&state, player: .me, count: 5)
        winGame(&state, player: .opponent, count: 1)
        for _ in 0..<3 { point(&state, player: .me) }
        state = ScoringEngine.pointWon(by: .me, in: state).state
        XCTAssertEqual(ScoringEngine.nextSetRequiresEndsSwitch(state), true)

        point(&state, player: .me)
        XCTAssertNil(ScoringEngine.nextSetRequiresEndsSwitch(state))
    }

    func test_nextSetRequiresEndsSwitchNilOnceMatchComplete() {
        var state = ScoringState(currentServer: .me)
        winGame(&state, player: .me, count: 6)
        winGame(&state, player: .me, count: 6)

        XCTAssertTrue(ScoringEngine.isMatchComplete(state))
        XCTAssertNil(ScoringEngine.nextSetRequiresEndsSwitch(state))
    }

    // MARK: - Changeover events

    func test_changeoverReasonAfterOddAndEvenGamesInSet() {
        var state = ScoringState(currentServer: .me)

        // Game 1 (1 total game in set, odd) → .oddGames
        for _ in 0..<3 { point(&state, player: .me) }
        let r1 = ScoringEngine.pointWon(by: .me, in: state)
        state = r1.state
        XCTAssertTrue(changeoverReasons(in: r1.events).contains(.oddGames),
                      "Game 1 (odd total) should emit oddGames changeover")

        // Game 2 (2 total games, even) → .evenGames
        for _ in 0..<3 { point(&state, player: .opponent) }
        let r2 = ScoringEngine.pointWon(by: .opponent, in: state)
        state = r2.state
        XCTAssertTrue(changeoverReasons(in: r2.events).contains(.evenGames),
                      "Game 2 (even total) should emit evenGames changeover")

        // Game 3 (3 total games, odd) → .oddGames
        for _ in 0..<3 { point(&state, player: .me) }
        let r3 = ScoringEngine.pointWon(by: .me, in: state)
        state = r3.state
        XCTAssertTrue(changeoverReasons(in: r3.events).contains(.oddGames),
                      "Game 3 (odd total) should emit oddGames changeover")
    }

    func test_changeoverReasonAfterSetCompletion() {
        // 6-0 set → 6 total games (even) → .setCompleteBalls
        var s1 = ScoringState(currentServer: .me)
        winGame(&s1, player: .me, count: 5)
        for _ in 0..<3 { point(&s1, player: .me) }
        let r1 = ScoringEngine.pointWon(by: .me, in: s1)
        XCTAssertTrue(changeoverReasons(in: r1.events).contains(.setCompleteBalls),
                      "6-0 set (6 total games, even) should emit setCompleteBalls")

        // 6-1 set → 7 total games (odd) → .setCompletePlayers
        var s2 = ScoringState(currentServer: .me)
        winGame(&s2, player: .me, count: 5)
        winGame(&s2, player: .opponent, count: 1)
        for _ in 0..<3 { point(&s2, player: .me) }
        let r2 = ScoringEngine.pointWon(by: .me, in: s2)
        XCTAssertTrue(changeoverReasons(in: r2.events).contains(.setCompletePlayers),
                      "6-1 set (7 total games, odd) should emit setCompletePlayers")
    }

    // MARK: - Format: quick4Games (legacy), shortSets (Short Sets) & fast4 (FAST4)

    func test_quick4GamesFirstToThreeGamesSuddenDeath() {
        // Win 3-0 outright
        var s1 = ScoringState(currentServer: .me, matchFormat: .quick4Games)
        winGame(&s1, player: .me, count: 3)
        XCTAssertTrue(ScoringEngine.isMatchComplete(s1))
        XCTAssertEqual(ScoringEngine.matchWinner(s1), .me)

        // 2-2 triggers the sudden-death tiebreak
        var s2 = ScoringState(currentServer: .me, matchFormat: .quick4Games)
        winGame(&s2, player: .me)
        winGame(&s2, player: .me)
        winGame(&s2, player: .opponent)
        winGame(&s2, player: .opponent)
        XCTAssertEqual(s2.sets.first?.isTieBreak, true, "Tiebreak should start at 2-2")
        XCTAssertFalse(ScoringEngine.isMatchComplete(s2))

        // A single point ends the match (sudden death — no two-point lead required)
        let r = ScoringEngine.pointWon(by: .me, in: s2)
        XCTAssertTrue(ScoringEngine.isMatchComplete(r.state),
                      "Single sudden-death point should complete the match")
        XCTAssertEqual(ScoringEngine.matchWinner(r.state), .me)
    }

    func test_shortSetsAndNoAdDeuce() {
        // Win 4-0 outright
        var s1 = ScoringState(currentServer: .me, matchFormat: .shortSets)
        winGame(&s1, player: .me, count: 4)
        XCTAssertTrue(ScoringEngine.isMatchComplete(s1))
        XCTAssertEqual(ScoringEngine.matchWinner(s1), .me)

        // At 3-3, play continues to 5-3 if a player wins two games in a row
        var s2 = ScoringState(currentServer: .me, matchFormat: .shortSets)
        for _ in 0..<3 {
            winGame(&s2, player: .me)
            winGame(&s2, player: .opponent)
        }
        XCTAssertEqual(s2.sets.first?.isTieBreak, false, "Short Sets continues at 3-3")
        winGame(&s2, player: .me) // 4-3
        XCTAssertFalse(ScoringEngine.isMatchComplete(s2), "4-3 does not complete Short Sets")
        winGame(&s2, player: .me) // 5-3
        XCTAssertTrue(ScoringEngine.isMatchComplete(s2), "5-3 completes Short Sets")
        XCTAssertEqual(ScoringEngine.matchWinner(s2), .me)

        // At 4-4, a 7-point tiebreak (win by 2) decides the set 5-4
        var s3 = ScoringState(currentServer: .me, matchFormat: .shortSets)
        for _ in 0..<4 {
            winGame(&s3, player: .me)
            winGame(&s3, player: .opponent)
        }
        XCTAssertEqual(s3.sets.first?.isTieBreak, true, "Tiebreak should start at 4-4")
        winTiebreakPoints(&s3, player: .me, points: 6)
        winTiebreakPoints(&s3, player: .opponent, points: 6)
        XCTAssertFalse(ScoringEngine.isMatchComplete(s3), "6-6 in 7-pt tiebreak requires 2-point lead")
        winTiebreakPoints(&s3, player: .me, points: 2)
        XCTAssertTrue(ScoringEngine.isMatchComplete(s3))
        XCTAssertEqual(s3.sets.first?.gamesMe, 5)
        XCTAssertEqual(s3.sets.first?.gamesOpponent, 4)
        XCTAssertEqual(s3.sets.first?.tieBreakPointsMe, 8)
        XCTAssertEqual(s3.sets.first?.tieBreakPointsOpponent, 6)
    }

    func test_noAdDecidingPointAtDeuceAndReceiverChoosesSide() {
        var state = ScoringState(currentServer: .me, matchFormat: .shortSets)
        for _ in 0..<3 {
            point(&state, player: .me)
            point(&state, player: .opponent)
        }
        // At 40-40 (3-3) in a No-Ad format:
        XCTAssertTrue(ScoringEngine.receiverChoosesServiceSide(state),
                      "Receiver chooses service side at 40-40 in No-Ad formats")
        XCTAssertTrue(ScoringEngine.isCurrentPointBreakPoint(state),
                      "Deciding point at 40-40 is also a break point for the receiver")

        // Standard format at 40-40 does not show receiver chooses side
        let stdDeuce = ScoringState(currentPointsMe: 3, currentPointsOpponent: 3, currentServer: .me, matchFormat: .standard)
        XCTAssertFalse(ScoringEngine.receiverChoosesServiceSide(stdDeuce))

        // Winning the single deciding point at 40-40 completes the game immediately
        let r = ScoringEngine.pointWon(by: .opponent, in: state)
        XCTAssertEqual(r.state.sets.first?.gamesOpponent, 1)
        XCTAssertEqual(r.state.currentPointsMe, 0)
        XCTAssertEqual(r.state.currentPointsOpponent, 0)
        XCTAssertFalse(ScoringEngine.receiverChoosesServiceSide(r.state))
    }

    func test_fast4TiebreakAtThreeAllFirstToFivePoints() {
        var state = ScoringState(currentServer: .me, matchFormat: .fast4)
        for _ in 0..<3 {
            winGame(&state, player: .me)
            winGame(&state, player: .opponent)
        }
        XCTAssertEqual(state.sets.first?.isTieBreak, true, "FAST4 tiebreak should start at 3-3")

        // Reach 4-4 in tiebreak points: next point wins immediately (sudden death at 4-4)
        winTiebreakPoints(&state, player: .me, points: 4)
        winTiebreakPoints(&state, player: .opponent, points: 4)
        XCTAssertFalse(ScoringEngine.isMatchComplete(state))

        let r = ScoringEngine.pointWon(by: .opponent, in: state)
        XCTAssertTrue(ScoringEngine.isMatchComplete(r.state))
        XCTAssertEqual(ScoringEngine.matchWinner(r.state), .opponent)
        XCTAssertEqual(r.state.sets.first?.gamesMe, 3)
        XCTAssertEqual(r.state.sets.first?.gamesOpponent, 4)
        XCTAssertEqual(r.state.sets.first?.tieBreakPointsMe, 4)
        XCTAssertEqual(r.state.sets.first?.tieBreakPointsOpponent, 5)
    }

    // MARK: - Format: bestOf3FullFinalSet

    func test_bestOf3FullFinalSetDecidingSetIsFullNotSuperTiebreak() {
        var state = ScoringState(currentServer: .me, matchFormat: .bestOf3FullFinalSet)
        // Set 1 → me (6-0); set 2 → opponent (6-0)
        winGame(&state, player: .me, count: 6)
        winGame(&state, player: .opponent, count: 6)

        // Third set must be a regular set, not a tiebreak
        XCTAssertEqual(state.sets.count, 3)
        XCTAssertFalse(state.sets[2].isTieBreak,
                       "Deciding set in bestOf3FullFinalSet must be a full regular set")

        // Play the third set to 6-6 and confirm the regular tiebreak starts
        for _ in 0..<6 {
            winGame(&state, player: .me)
            winGame(&state, player: .opponent)
        }
        XCTAssertEqual(state.sets[2].isTieBreak, true)

        // The deciding tiebreak target is 7 points (not 10 like a super tiebreak)
        winTiebreakPoints(&state, player: .me, points: 7)
        XCTAssertTrue(ScoringEngine.isMatchComplete(state))
        XCTAssertEqual(ScoringEngine.matchWinner(state), .me)
        XCTAssertEqual(state.sets[2].tieBreakPointsMe, 7)
        XCTAssertEqual(state.sets[2].tieBreakPointsOpponent, 0)
    }

    // MARK: - Format: standalone superTiebreak

    func test_standaloneSuperTiebreakMatchIsOneTiebreak() {
        var state = ScoringState(
            sets: [SetScore(isTieBreak: true)],
            currentServer: .me,
            tiebreakStartServer: .me,
            tiebreakFirstPointReceiver: .opponent,
            matchFormat: .superTiebreak
        )

        winTiebreakPoints(&state, player: .me, points: 9)
        XCTAssertFalse(ScoringEngine.isMatchComplete(state),
                       "9 points should not be enough (need 10 with a 2-pt lead)")

        let r = ScoringEngine.pointWon(by: .me, in: state)
        XCTAssertTrue(ScoringEngine.isMatchComplete(r.state))
        XCTAssertEqual(ScoringEngine.matchWinner(r.state), .me)
        XCTAssertEqual(r.state.sets.last?.tieBreakPointsMe, 10)
        XCTAssertEqual(r.state.sets.last?.tieBreakPointsOpponent, 0)
    }

    // MARK: - Format: perpetualSuperTiebreak

    func test_perpetualSuperTiebreakNeverCompletes() {
        var state = ScoringState(
            sets: [SetScore(isTieBreak: true)],
            currentServer: .me,
            tiebreakStartServer: .me,
            tiebreakFirstPointReceiver: .opponent,
            matchFormat: .perpetualSuperTiebreak
        )
        winTiebreakPoints(&state, player: .me, points: 20)
        XCTAssertFalse(ScoringEngine.isMatchComplete(state))
        XCTAssertNil(ScoringEngine.matchWinner(state))
    }

    // MARK: - Ending before the configured win condition

    func test_leaderWhenStoppedUsesSetsBeforeCurrentSet() {
        let state = ScoringState(
            sets: [
                SetScore(gamesMe: 6, gamesOpponent: 1),
                SetScore(gamesMe: 2, gamesOpponent: 5)
            ],
            currentServer: .me
        )

        XCTAssertEqual(ScoringEngine.leaderWhenStopped(state), .me)
    }

    func test_leaderWhenStoppedUsesGamesThenCurrentPoints() {
        let gamesLeader = ScoringState(
            sets: [SetScore(gamesMe: 2, gamesOpponent: 0)],
            currentPointsMe: 0,
            currentPointsOpponent: 3,
            currentServer: .me
        )
        XCTAssertEqual(ScoringEngine.leaderWhenStopped(gamesLeader), .me)

        let pointsLeader = ScoringState(
            sets: [SetScore(gamesMe: 2, gamesOpponent: 2)],
            currentPointsMe: 1,
            currentPointsOpponent: 3,
            currentServer: .me
        )
        XCTAssertEqual(ScoringEngine.leaderWhenStopped(pointsLeader), .opponent)
    }

    func test_leaderWhenStoppedReturnsNilForLevelScore() {
        let state = ScoringState(
            sets: [SetScore(gamesMe: 1, gamesOpponent: 1)],
            currentPointsMe: 2,
            currentPointsOpponent: 2,
            currentServer: .me
        )

        XCTAssertNil(ScoringEngine.leaderWhenStopped(state))
    }

    // MARK: - Helpers

    private func point(_ state: inout ScoringState, player: Player) {
        state = ScoringEngine.pointWon(by: player, in: state).state
    }

    private func winGame(_ state: inout ScoringState, player: Player, count: Int = 1) {
        for _ in 0..<count {
            for _ in 0..<4 {
                point(&state, player: player)
            }
        }
    }

    private func winTiebreakPoints(_ state: inout ScoringState, player: Player, points: Int) {
        for _ in 0..<points {
            point(&state, player: player)
        }
    }

    private func changeoverReasons(in events: [ScoringEvent]) -> [ScoringChangeoverReason] {
        events.compactMap {
            if case .changeover(let c) = $0 { return c.reason }
            return nil
        }
    }
}
