// MatchStatsSummaryTests.swift — parity lock between MatchStatsSummary and
// the fields displayed in the stats views.
import XCTest
@testable import DeuceMateCore

final class MatchStatsSummaryTests: XCTestCase {

    // MARK: - Fixture

    /// Builds a representative match with a mix of outcomes, serve types, and
    /// score states so every field path is exercised.
    private func makeStats() -> [PointStat] {
        let snap = { (sv: Int, rt: Int, tb: Bool) in
            GameScoreSnapshot(server: sv, returner: rt, isTiebreak: tb)
        }
        return [
            // Set 0 — focal serves, wins with a winner
            PointStat(setIndex: 0, server: .me, winner: .me,       outcome: .winner,       isSecondServe: false, isBreakPoint: false, endingShot: .serve,  gameScoreAtStart: snap(0,0,false)),
            // Focal serves, double fault (lost)
            PointStat(setIndex: 0, server: .me, winner: .opponent, outcome: .doubleFault,  isSecondServe: true,  isBreakPoint: false, endingShot: .serve,  gameScoreAtStart: snap(1,0,false)),
            // Focal serves, UE (lost)
            PointStat(setIndex: 0, server: .me, winner: .opponent, outcome: .unforcedError,isSecondServe: false, isBreakPoint: false, endingShot: .rally,  gameScoreAtStart: snap(2,1,false)),
            // Opponent serves, focal returns winner
            PointStat(setIndex: 0, server: .opponent, winner: .me, outcome: .winner,       isSecondServe: false, isBreakPoint: false, endingShot: .return, gameScoreAtStart: snap(0,0,false)),
            // Opponent serves on 2nd, focal wins
            PointStat(setIndex: 0, server: .opponent, winner: .me, outcome: .forcedError,  isSecondServe: true,  isBreakPoint: false, endingShot: .servePlusOne, gameScoreAtStart: snap(1,1,false)),
            // Break point — focal as returner wins
            PointStat(setIndex: 0, server: .opponent, winner: .me, outcome: .winner,       isSecondServe: false, isBreakPoint: true,  endingShot: nil,     gameScoreAtStart: snap(3,3,false)),
            // Break point — focal as server loses
            PointStat(setIndex: 0, server: .me, winner: .opponent, outcome: .winner,       isSecondServe: false, isBreakPoint: true,  endingShot: nil,     gameScoreAtStart: snap(3,3,false)),
            // Tiebreak point
            PointStat(setIndex: 0, server: .me, winner: .me,       outcome: .winner,       isSecondServe: false, isBreakPoint: false, endingShot: .rally,  gameScoreAtStart: snap(4,4,true)),
            // 30-All
            PointStat(setIndex: 0, server: .me, winner: .me,       outcome: .winner,       isSecondServe: false, isBreakPoint: false, endingShot: nil,     gameScoreAtStart: snap(2,2,false)),
        ]
    }

    // MARK: - Tests

    func test_pointsWon_countsCorrectly() {
        let s = MatchStatsSummary(stats: makeStats(), focal: .me)
        // Points won by me: indices 0, 3, 4, 5, 7, 8 = 6
        XCTAssertEqual(s.pointsWon, 6)
        XCTAssertEqual(s.totalPoints, 9)
    }

    func test_doubleFaults_countedCorrectly() {
        let s = MatchStatsSummary(stats: makeStats(), focal: .me)
        XCTAssertEqual(s.doubleFaults, 1)
    }

    func test_firstServe_countsCorrectly() {
        let s = MatchStatsSummary(stats: makeStats(), focal: .me)
        // Focal serves: points 0,1,2,6,7,8 (6 first-serve attempts).
        // First serves in (point decided without going to 2nd): 0,2,6,7,8 → 5.
        // Second-serve points: 1 → 1.
        XCTAssertEqual(s.firstServeTotal, 6)
        XCTAssertEqual(s.firstServeIn, 5)
        XCTAssertEqual(s.secondServeTotal, 1)
    }

    /// Regression: "1st Serve In %" used to compute as firstServeIn /
    /// firstServeTotal where both sides counted points decided on the first
    /// serve, making the metric structurally 100%. After the fix
    /// firstServeTotal counts every first-serve attempt, so the ratio must
    /// be strictly less than 1 whenever any second-serve point exists.
    func test_firstServeInPercentage_isNotStuckAt100() {
        let s = MatchStatsSummary(stats: makeStats(), focal: .me)
        XCTAssertLessThan(s.firstServeIn, s.firstServeTotal,
            "1st serves in should be less than attempts whenever any second-serve point exists")
        XCTAssertEqual(
            MatchStatsSummary.pct(num: s.firstServeIn, den: s.firstServeTotal),
            "83% (5/6)"
        )
    }

    func test_breakPointOpps_counted() {
        let s = MatchStatsSummary(stats: makeStats(), focal: .me)
        XCTAssertEqual(s.breakPointOpps, 1)   // pt 5: opp serves, bp, focal wins
        XCTAssertEqual(s.breakPointWins, 1)
        XCTAssertEqual(s.breakPointsFaced, 1) // pt 6: focal serves, bp, focal loses
        XCTAssertEqual(s.breakPointsLost, 1)
    }

    func test_wueRatio_format() {
        let s = MatchStatsSummary(stats: makeStats(), focal: .me)
        // myWinners = pts 0,3,5,7,8 (outcome=winner AND winner==me)
        // myUE = pts where winner=opp, outcome=UE → pt 2 (1)
        // wue = 5/1 = 5.0 : 1
        XCTAssertEqual(s.wueRatio, "5.0 : 1")
    }

    func test_rallyDepth_populated() {
        let s = MatchStatsSummary(stats: makeStats(), focal: .me)
        XCTAssertFalse(s.rallyDepth.isEmpty)
        let serveShot = s.rallyDepth.first { $0.shot == .serve }
        XCTAssertNotNil(serveShot)
    }

    func test_scoreStates_tiebreakPresent() {
        let s = MatchStatsSummary(stats: makeStats(), focal: .me)
        let tb = s.scoreStates.first { $0.label == "In Tiebreak" }
        XCTAssertNotNil(tb)
        XCTAssertEqual(tb?.total, 1)
        XCTAssertEqual(tb?.wins, 1)
    }

    func test_scoreStates_thirtyAllPresent() {
        let s = MatchStatsSummary(stats: makeStats(), focal: .me)
        let ta = s.scoreStates.first { $0.label == "At 30-All" }
        XCTAssertNotNil(ta)
    }

    func test_emptyStats_noGarbage() {
        let s = MatchStatsSummary(stats: [], focal: .me)
        XCTAssertEqual(s.totalPoints, 0)
        XCTAssertEqual(s.wueRatio, "—")
        XCTAssertEqual(s.aggressionIndex, "—")
        XCTAssertEqual(s.ownErrorsPct, "—")
    }

    func test_pct_formatting() {
        XCTAssertEqual(MatchStatsSummary.pct(num: 1, den: 2), "50% (1/2)")
        XCTAssertEqual(MatchStatsSummary.pct(num: 0, den: 0), "—")
        XCTAssertEqual(MatchStatsSummary.pct(num: 3, den: 4), "75% (3/4)")
    }

    // MARK: - Service wins and second-serve in

    func test_serviceWins_andSecondServeIn_correct() {
        let s = MatchStatsSummary(stats: makeStats(), focal: .me)
        // firstServeWins: pts 0,7,8 (server=me, !isSecondServe, winner=me) = 3
        XCTAssertEqual(s.firstServeWins, 3)
        // secondServeIn: pt 1 is isSecondServe but outcome=doubleFault, so 0
        XCTAssertEqual(s.secondServeIn, 0)
        // secondServeWins: pt 1 won by opponent = 0
        XCTAssertEqual(s.secondServeWins, 0)
    }

    // MARK: - Return stats

    func test_returnStats_correct() {
        let s = MatchStatsSummary(stats: makeStats(), focal: .me)
        // returnOppsOnFirst: pts 3,5 (server=opponent, !isSecondServe) = 2
        XCTAssertEqual(s.returnOppsOnFirst, 2)
        // returnWinsOnFirst: both pts 3,5 won by me = 2
        XCTAssertEqual(s.returnWinsOnFirst, 2)
        // returnOppsOnSecond: pt 4 (server=opponent, isSecondServe) = 1
        XCTAssertEqual(s.returnOppsOnSecond, 1)
        // returnWinsOnSecond: pt 4 won by me = 1
        XCTAssertEqual(s.returnWinsOnSecond, 1)
    }

    // MARK: - Outcome breakdown

    func test_outcomeBreakdown_correct() {
        let s = MatchStatsSummary(stats: makeStats(), focal: .me)
        // myWinners: pts 0,3,5,7,8 (winner=me, outcome=winner) = 5
        XCTAssertEqual(s.myWinners, 5)
        // myUnforcedErrors: pt 2 (winner=opponent, outcome=unforcedError) = 1
        XCTAssertEqual(s.myUnforcedErrors, 1)
        // myForcedErrors: no point where opponent wins via forcedError = 0
        XCTAssertEqual(s.myForcedErrors, 0)
        // opponentWinners: pt 6 (winner=opponent, outcome=winner) = 1
        XCTAssertEqual(s.opponentWinners, 1)
        // opponentDoubleFaults: opponent never serves DF in fixture = 0
        XCTAssertEqual(s.opponentDoubleFaults, 0)
        // opponentUnforcedErrors: no point where me wins via opponentUE = 0
        XCTAssertEqual(s.opponentUnforcedErrors, 0)
        // opponentForcedErrors: pt 4 (winner=me, outcome=forcedError) = 1
        XCTAssertEqual(s.opponentForcedErrors, 1)
    }

    // MARK: - Pressure / normal points

    func test_pressurePoints_correct() {
        let s = MatchStatsSummary(stats: makeStats(), focal: .me)
        // bigPts: pts 5,6 (isBreakPoint) + pt 7 (isTiebreak) = 3
        XCTAssertEqual(s.bigPointTotal, 3)
        // bigPointWins: pts 5,7 won by me = 2
        XCTAssertEqual(s.bigPointWins, 2)
        // normalPts: pts 0,1,2,3,4,8 = 6
        XCTAssertEqual(s.normalPointTotal, 6)
        // normalPointWins: pts 0,3,4,8 = 4
        XCTAssertEqual(s.normalPointWins, 4)
    }

    // MARK: - Coaching metrics with real data

    func test_coachingMetrics_correct() {
        let s = MatchStatsSummary(stats: makeStats(), focal: .me)
        // aggressionIndex: myW=5, myW+myUE=6 → 83% (5/6)
        XCTAssertEqual(s.aggressionIndex, "83% (5/6)")
        // ownErrorsPct: df+myUE=2, lostPoints=3 → Int(66.6…) = 66% (2/3)
        XCTAssertEqual(s.ownErrorsPct, "66% (2/3)")
    }

    // MARK: - Deuce/Ad score state

    func test_scoreStates_deuceAdPresent() {
        let s = MatchStatsSummary(stats: makeStats(), focal: .me)
        // pts 5,6 both have score (3,3,false) = deuce
        let da = s.scoreStates.first { $0.label == "At Deuce/Ad" }
        XCTAssertNotNil(da)
        XCTAssertEqual(da?.total, 2)
        // pt 5 won by me, pt 6 won by opponent → 1 win
        XCTAssertEqual(da?.wins, 1)
    }

    // MARK: - Rally depth per-shot accuracy

    func test_rallyDepth_countsAreCorrect() {
        let s = MatchStatsSummary(stats: makeStats(), focal: .me)
        // endingShot=.serve: pts 0,1 → total=2, wins=1 (pt 0 only)
        let serveStat = s.rallyDepth.first { $0.shot == .serve }
        XCTAssertNotNil(serveStat)
        XCTAssertEqual(serveStat?.total, 2)
        XCTAssertEqual(serveStat?.wins, 1)
        // endingShot=.rally: pts 2,7 → total=2, wins=1 (pt 7 only)
        let rallyStat = s.rallyDepth.first { $0.shot == .rally }
        XCTAssertNotNil(rallyStat)
        XCTAssertEqual(rallyStat?.total, 2)
        XCTAssertEqual(rallyStat?.wins, 1)
    }

    // MARK: - Focal = opponent symmetry

    func test_focalOpponent_symmetric() {
        let s = MatchStatsSummary(stats: makeStats(), focal: .opponent)
        // opponent wins pts 1,2,6 = 3
        XCTAssertEqual(s.pointsWon, 3)
        XCTAssertEqual(s.totalPoints, 9)
        // opponent as returner break points: pt 6 (server=me, isBreakPoint)
        XCTAssertEqual(s.breakPointOpps, 1)
        XCTAssertEqual(s.breakPointWins, 1)
        // opponent as server break points: pt 5 (server=opponent, isBreakPoint, won by me)
        XCTAssertEqual(s.breakPointsFaced, 1)
        XCTAssertEqual(s.breakPointsLost, 1)
    }
}
