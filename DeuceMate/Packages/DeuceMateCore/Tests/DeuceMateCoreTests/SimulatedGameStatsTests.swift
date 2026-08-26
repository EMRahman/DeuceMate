// SimulatedGameStatsTests.swift — end-to-end sanity check that simulates a
// concrete sequence of points (one service game by the focal player, then a
// short return game) and asserts every field of MatchStatsSummary matches the
// values you'd tally by hand. Designed to catch structural bugs in metric
// computation that unit-level tests on isolated fields can miss — for example
// the "1st Serve In always = 100%" denominator regression.
import XCTest
@testable import DeuceMateCore

final class SimulatedGameStatsTests: XCTestCase {

    /// Builds a 12-point sample: focal serves an 8-point game that ends with
    /// the opponent breaking on a single break point, then receives a 4-point
    /// game in which the opponent double-faults once.
    ///
    ///  #  | Server | 2nd? | Winner | Outcome       | Score (S-R)  | Notes
    ///  ---|--------|------|--------|---------------|--------------|------
    ///  1  | me     | n    | me     | winner        | 0-0          |
    ///  2  | me     | n    | opp    | unforcedError | 1-0          | focal UE
    ///  3  | me     | y    | me     | forcedError   | 1-1          | opp FE
    ///  4  | me     | n    | opp    | winner        | 2-1          | opp winner
    ///  5  | me     | n    | me     | winner        | 2-2 (30-All) |
    ///  6  | me     | y    | opp    | doubleFault   | 3-2          | focal DF
    ///  7  | me     | n    | opp    | winner        | 3-3 (Deuce)  | opp winner, big point
    ///  8  | me     | n    | opp    | unforcedError | 3-4 (BP)     | focal UE on BP
    ///  9  | opp    | n    | me     | winner        | 0-0          | return winner
    /// 10  | opp    | n    | opp    | unforcedError | 0-1          | focal UE returning
    /// 11  | opp    | y    | me     | winner        | 1-1          |
    /// 12  | opp    | y    | me     | doubleFault   | 1-2          | opp DF
    private func makeStats() -> [PointStat] {
        let s = { (sv: Int, rt: Int, tb: Bool) in
            GameScoreSnapshot(server: sv, returner: rt, isTiebreak: tb)
        }
        return [
            // Game 1 — focal serves
            PointStat(setIndex: 0, server: .me,       winner: .me,       outcome: .winner,        isSecondServe: false, isBreakPoint: false, endingShot: .serve,        gameScoreAtStart: s(0,0,false)),
            PointStat(setIndex: 0, server: .me,       winner: .opponent, outcome: .unforcedError, isSecondServe: false, isBreakPoint: false, endingShot: .rally,        gameScoreAtStart: s(1,0,false)),
            PointStat(setIndex: 0, server: .me,       winner: .me,       outcome: .forcedError,   isSecondServe: true,  isBreakPoint: false, endingShot: .servePlusOne, gameScoreAtStart: s(1,1,false)),
            PointStat(setIndex: 0, server: .me,       winner: .opponent, outcome: .winner,        isSecondServe: false, isBreakPoint: false, endingShot: .return,       gameScoreAtStart: s(2,1,false)),
            PointStat(setIndex: 0, server: .me,       winner: .me,       outcome: .winner,        isSecondServe: false, isBreakPoint: false, endingShot: .rally,        gameScoreAtStart: s(2,2,false)),
            PointStat(setIndex: 0, server: .me,       winner: .opponent, outcome: .doubleFault,   isSecondServe: true,  isBreakPoint: false, endingShot: .serve,        gameScoreAtStart: s(3,2,false)),
            PointStat(setIndex: 0, server: .me,       winner: .opponent, outcome: .winner,        isSecondServe: false, isBreakPoint: false, endingShot: .return,       gameScoreAtStart: s(3,3,false)),
            PointStat(setIndex: 0, server: .me,       winner: .opponent, outcome: .unforcedError, isSecondServe: false, isBreakPoint: true,  endingShot: .rally,        gameScoreAtStart: s(3,4,false)),
            // Game 2 — opp serves, focal returns
            PointStat(setIndex: 0, server: .opponent, winner: .me,       outcome: .winner,        isSecondServe: false, isBreakPoint: false, endingShot: .return,       gameScoreAtStart: s(0,0,false)),
            PointStat(setIndex: 0, server: .opponent, winner: .opponent, outcome: .unforcedError, isSecondServe: false, isBreakPoint: false, endingShot: .return,       gameScoreAtStart: s(1,0,false)),
            PointStat(setIndex: 0, server: .opponent, winner: .me,       outcome: .winner,        isSecondServe: true,  isBreakPoint: false, endingShot: .return,       gameScoreAtStart: s(1,1,false)),
            PointStat(setIndex: 0, server: .opponent, winner: .me,       outcome: .doubleFault,   isSecondServe: true,  isBreakPoint: false, endingShot: .serve,        gameScoreAtStart: s(2,1,false)),
        ]
    }

    // MARK: - Service stats (the bug that motivated this file)

    func test_simulatedGame_firstServeInPercentage_isNotStuckAt100() {
        let me = MatchStatsSummary(stats: makeStats(), focal: .me)
        // Focal served 8 points → 8 first-serve attempts. 6 landed in
        // (pts 1, 2, 4, 5, 7, 8); 2 went to the 2nd serve (pts 3, 6).
        XCTAssertEqual(me.firstServeTotal, 8)
        XCTAssertEqual(me.firstServeIn, 6)
        XCTAssertEqual(me.secondServeTotal, 2)
        // Displayed percentage = 6/8 = 75%, not 100%.
        XCTAssertEqual(
            MatchStatsSummary.pct(num: me.firstServeIn, den: me.firstServeTotal),
            "75% (6/8)"
        )
    }

    func test_simulatedGame_serveOutcomes() {
        let me = MatchStatsSummary(stats: makeStats(), focal: .me)
        // 1st-serve points won by focal: 1 and 5 = 2 out of 6 first serves in.
        XCTAssertEqual(me.firstServeWins, 2)
        // 2nd-serve points won by focal: just 3 = 1 out of 2.
        XCTAssertEqual(me.secondServeWins, 1)
        // 2nd serves that landed in (excludes the DF): 1 out of 2.
        XCTAssertEqual(me.secondServeIn, 1)
        // Double faults by focal: 1.
        XCTAssertEqual(me.doubleFaults, 1)
        XCTAssertEqual(me.myDoubleFaults, 1)
    }

    // MARK: - Return stats

    func test_simulatedGame_returnStats() {
        let me = MatchStatsSummary(stats: makeStats(), focal: .me)
        // Opp served 4 points: 2 on 1st (pts 9, 10), 2 on 2nd (pts 11, 12).
        XCTAssertEqual(me.returnOppsOnFirst, 2)
        XCTAssertEqual(me.returnWinsOnFirst, 1)        // pt 9
        XCTAssertEqual(me.returnOppsOnSecond, 2)
        XCTAssertEqual(me.returnWinsOnSecond, 2)        // pts 11, 12
        // Opp DF goes into the opponent column.
        XCTAssertEqual(me.opponentDoubleFaults, 1)
    }

    // MARK: - Break points

    func test_simulatedGame_breakPoints() {
        let me = MatchStatsSummary(stats: makeStats(), focal: .me)
        // Focal faced one BP as server (pt 8) and lost it.
        XCTAssertEqual(me.breakPointsFaced, 1)
        XCTAssertEqual(me.breakPointsLost, 1)
        // Focal had no BP chances as returner in this sample.
        XCTAssertEqual(me.breakPointOpps, 0)
        XCTAssertEqual(me.breakPointWins, 0)
    }

    // MARK: - Points / outcome breakdown

    func test_simulatedGame_pointsAndOutcomes() {
        let me = MatchStatsSummary(stats: makeStats(), focal: .me)
        XCTAssertEqual(me.totalPoints, 12)
        // Focal won pts 1, 3, 5, 9, 11, 12.
        XCTAssertEqual(me.pointsWon, 6)
        XCTAssertEqual(me.wonPoints, 6)
        XCTAssertEqual(me.lostPoints, 6)

        XCTAssertEqual(me.myWinners, 4)               // pts 1, 5, 9, 11
        XCTAssertEqual(me.myUnforcedErrors, 3)        // pts 2, 8, 10
        XCTAssertEqual(me.myForcedErrors, 0)
        XCTAssertEqual(me.opponentWinners, 2)         // pts 4, 7
        XCTAssertEqual(me.opponentForcedErrors, 1)    // pt 3 (opp made FE; focal won)
        XCTAssertEqual(me.opponentUnforcedErrors, 0)
        XCTAssertEqual(me.uncategorizedCount, 0)
    }

    // MARK: - Coaching ratios

    func test_simulatedGame_coachingMetrics() {
        let me = MatchStatsSummary(stats: makeStats(), focal: .me)
        // myW=4 (pts 1, 5, 9, 11), myUE=3 → 4/3 = 1.3 : 1.
        XCTAssertEqual(me.wueRatio.formatted, "1.3 : 1")
        // Aggression index = 4 / (4+3) = 4/7 = 57%.
        XCTAssertEqual(me.aggressionIndex.formatted, "57% (4/7)")
        // Own errors % = (DF + UE) / lost = (1 + 3) / 6 = 66%.
        XCTAssertEqual(me.ownErrorsPct.formatted, "66% (4/6)")
    }

    // MARK: - Pressure / score states

    func test_simulatedGame_pressureBuckets() {
        let me = MatchStatsSummary(stats: makeStats(), focal: .me)
        // Big = isBreakPoint OR (server>=3 AND returner>=3). Pts 7 (3-3) and 8 (BP).
        XCTAssertEqual(me.bigPointTotal, 2)
        XCTAssertEqual(me.bigPointWins, 0)
        XCTAssertEqual(me.normalPointTotal, 10)
        XCTAssertEqual(me.normalPointWins, 6)
    }

    func test_simulatedGame_scoreStates() {
        let me = MatchStatsSummary(stats: makeStats(), focal: .me)
        let thirtyAll = me.scoreStates.first { $0.label == "At 30-All" }
        XCTAssertNotNil(thirtyAll)
        XCTAssertEqual(thirtyAll?.total, 1)            // pt 5
        XCTAssertEqual(thirtyAll?.wins, 1)
        let deuceAd = me.scoreStates.first { $0.label == "At Deuce/Ad" }
        XCTAssertNotNil(deuceAd)
        XCTAssertEqual(deuceAd?.total, 2)              // pts 7 (3-3) and 8 (3-4)
        XCTAssertEqual(deuceAd?.wins, 0)
        XCTAssertNil(me.scoreStates.first { $0.label == "In Tiebreak" })
    }

    // MARK: - Rally depth

    func test_simulatedGame_rallyDepth() {
        let me = MatchStatsSummary(stats: makeStats(), focal: .me)
        let byShot = Dictionary(uniqueKeysWithValues: me.rallyDepth.map { ($0.shot, $0) })
        // .serve: pts 1, 6, 12 (3 total). Wins for me: pt 1 (winner) and pt 12 (opp DF) → 2.
        XCTAssertEqual(byShot[.serve]?.total, 3)
        XCTAssertEqual(byShot[.serve]?.wins, 2)
        // .rally: pts 2, 5, 8 (3). Wins for me: 5 → 1.
        XCTAssertEqual(byShot[.rally]?.total, 3)
        XCTAssertEqual(byShot[.rally]?.wins, 1)
        // .servePlusOne: pt 3. Won by me.
        XCTAssertEqual(byShot[.servePlusOne]?.total, 1)
        XCTAssertEqual(byShot[.servePlusOne]?.wins, 1)
        // .return: pts 4, 7, 9, 10, 11 (5). Wins for me: 9, 11 → 2.
        XCTAssertEqual(byShot[.return]?.total, 5)
        XCTAssertEqual(byShot[.return]?.wins, 2)
    }

    // MARK: - Symmetry: focal=opp swaps every "my/opp" pair

    func test_simulatedGame_symmetricFromOpponentPerspective() {
        let stats = makeStats()
        let me  = MatchStatsSummary(stats: stats, focal: .me)
        let opp = MatchStatsSummary(stats: stats, focal: .opponent)
        XCTAssertEqual(me.totalPoints, opp.totalPoints)
        XCTAssertEqual(me.pointsWon + opp.pointsWon, me.totalPoints)
        // myW from my POV == opp's view of "opponent winners" (= winners hit by me).
        XCTAssertEqual(me.myWinners, opp.opponentWinners)
        XCTAssertEqual(me.myUnforcedErrors, opp.opponentUnforcedErrors)
        XCTAssertEqual(me.myForcedErrors, opp.opponentForcedErrors)
        XCTAssertEqual(me.myDoubleFaults, opp.opponentDoubleFaults)
        // Return opportunities mirror the other side's first/second-serve points.
        // `firstServeIn` is "first serves that landed in" = points decided on 1st;
        // `secondServeTotal` is total 2nd-serve points.
        XCTAssertEqual(me.returnOppsOnFirst,  opp.firstServeIn)
        XCTAssertEqual(me.returnOppsOnSecond, opp.secondServeTotal)
        XCTAssertEqual(opp.returnOppsOnFirst,  me.firstServeIn)
        XCTAssertEqual(opp.returnOppsOnSecond, me.secondServeTotal)
    }
}
