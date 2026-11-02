import XCTest
@testable import DeuceMateCore

final class RecCoachRedesignTests: XCTestCase {
    private func p(_ i: Int, server: Player = .me, won: Bool = true,
                   second: Bool = false, outcome: PointOutcome = .winner,
                   shot: EndingShot? = nil, set: Int = 0,
                   score: GameScoreSnapshot? = nil, hr: Int? = nil, steps: Int? = nil) -> PointStat {
        PointStat(timestamp: Date(timeIntervalSince1970: 1_700_000_000 + Double(i * 30)),
                  setIndex: set, server: server, winner: won ? .me : .opponent,
                  outcome: outcome, isSecondServe: second, endingShot: shot,
                  gameScoreAtStart: score, heartRateBPM: hr, stepsCumulative: steps)
    }
    private func lowFirst(_ count: Int = 40, strongSecond: Bool = false) -> [PointStat] {
        (0..<count).map { i in p(i, won: i < 18 || (strongSecond ? i < 36 : i < 25), second: i >= 18) }
    }
    private func balance() -> [PointStat] {
        (0..<50).map { p($0, won: $0 < 31) }
        + (50..<100).map { p($0, server: .opponent, won: $0 < 64) }
    }
    private func returnErrors(_ shot: EndingShot?) -> [PointStat] {
        (0..<20).map { p($0, server: .opponent, won: $0 >= 10,
                         outcome: $0 < 6 ? .unforcedError : .winner, shot: shot) }
    }
    // Twelve complete service games. The effort recorded on point N predicts
    // the second-serve flag on N+1, not N. Inter-game score resets break pairs.
    private func effort(health: String = "both", mode: String = "first", brokenScores: Bool = false, longGaps: Bool = false) -> [PointStat] {
        var result: [PointStat] = []
        var steps = 0
        for game in 0..<12 {
            var a = 0, b = 0
            for j in 0..<8 {
                let i = game * 8 + j
                let won = j.isMultiple(of: 2) || j == 7
                let high = mode == "first" ? !j.isMultiple(of: 2) : j.isMultiple(of: 2)
                steps += high ? 25 : 5
                let hasHR = health == "both" || health == "hr"
                let hasSteps = health == "both" || health == "steps"
                result.append(p(longGaps ? i * 4 : i, won: won, second: mode == "first" ? j.isMultiple(of: 2) : mode == "fault",
                                outcome: mode == "fault" && !won ? .doubleFault : .winner, set: game < 6 ? 0 : 1,
                                score: brokenScores ? nil : GameScoreSnapshot(server: a, returner: b, isTiebreak: false),
                                hr: hasHR ? (high ? 165 : 125) : nil, steps: hasSteps ? steps : nil))
                if won { a += 1 } else { b += 1 }
            }
        }
        return result
    }
    private func lines(_ points: [PointStat], type: MatchType? = nil, focal: Player = .me,
                       scope: RecCoachInsights.SetScope = .all) -> [String] {
        RecCoachInsights.generate(stats: points, focal: focal, setScope: scope, matchType: type)
    }

    func test_firstServeUsesThirtyAttemptsAndSecondServeResults() {
        XCTAssertTrue(lines(lowFirst()).contains {
            $0.contains("45% (18/40)") && $0.contains("32% (7/22)") && $0.contains("less pace or a familiar spin")
        })
        XCTAssertFalse(lines(lowFirst(29)).contains { $0.contains("First serves in:") })
        let strong = lines(lowFirst(strongSecond: true))
        XCTAssertTrue(strong.contains { $0.contains("First serves in:") && $0.contains("compare your service-point results") })
        XCTAssertFalse(strong.contains { $0.contains("less pace") || $0.contains("kick") })
    }

    func test_untrackedFirstServeDefaultsDoNotImproveOrTriggerRates() {
        let unknown = (40..<100).map { p($0, outcome: .uncategorized) }
        XCTAssertFalse(lines(lowFirst() + unknown).contains { $0.contains("First serves in:") || $0.contains("on first serve") })
        let fiftyPercent = (0..<40).map { p($0, second: $0 >= 20) }
        XCTAssertFalse(lines(fiftyPercent).contains { $0.contains("First serves in:") })
    }

    func test_balanceShowsBothSampleSizesWithoutDiagnosingReturns() {
        XCTAssertTrue(lines(balance()).contains {
            $0.contains("62% (31/50) serving vs 28% (14/50) receiving") && $0.contains("gap alone")
        })
        XCTAssertFalse(lines(Array(balance().prefix(69))).contains { $0.contains("gap alone") })
        XCTAssertTrue(lines(balance(), focal: .opponent).contains { $0.contains("72% (36/50) serving vs 38% (19/50) receiving") })
    }

    func test_missedReturnsAndLaterErrorsHaveDifferentAdvice() {
        XCTAssertEqual(lines(returnErrors(.return)), [
            "6/20 tracked return attempts ended in an unforced error — review return position, split-step timing and preparation."
        ])
        XCTAssertEqual(lines(returnErrors(.rally)), [
            "6/10 tracked losses while receiving were unforced errors after the return — review recovery position, spacing and shot selection."
        ])
        XCTAssertTrue(lines(returnErrors(nil)).isEmpty)
    }

    func test_returnAttemptsExcludeAcesAndOpponentDoubleFaults() {
        var points = returnErrors(.return)
        points += (20..<30).map { p($0, server: .opponent, won: false, shot: .serve) }
        points += (30..<40).map { p($0, server: .opponent, outcome: .doubleFault, shot: .serve) }
        XCTAssertTrue(lines(points).contains { $0.hasPrefix("6/20 tracked return attempts") })
    }

    func test_pressureDoesNotConfuseServingMixWithPressureDrop() {
        // Winning all serve points and losing all return points creates a
        // pooled pressure drop, but neither side has a within-side decline.
        let ordinary = GameScoreSnapshot(server: 0, returner: 0, isTiebreak: false)
        let deuce = GameScoreSnapshot(server: 3, returner: 3, isTiebreak: false)
        let points = (0..<20).map { p($0, score: ordinary) }
            + (20..<28).map { p($0, server: .opponent, won: false, score: deuce) }
        XCTAssertFalse(lines(points).contains { $0.contains("under pressure vs") })
        let missing = (0..<20).map { p($0) }
            + (20..<28).map { p($0, won: false, score: deuce) }
        XCTAssertFalse(lines(missing).contains { $0.contains("under pressure vs") })
    }

    func test_setDeclineCombinesBothFactsAndChecksLaterTransitions() {
        var points: [PointStat] = []
        points += (0..<30).map { p($0, won: $0 >= 12, outcome: $0 < 2 ? .unforcedError : .winner) }
        points += (30..<60).map { p($0, won: $0 >= 50, outcome: $0 < 44 ? .unforcedError : .winner, set: 1) }
        let result = RecCoachInsights.generate(stats: points, focal: .me, setElapsedSeconds: [0: 2100, 1: 1500])
        XCTAssertEqual(result.filter { $0.contains("set 1") }.count, 1)
        XCTAssertTrue(result.contains { $0.contains("Unforced errors rose") && $0.contains("points won fell") })
        XCTAssertFalse(result.contains { $0.contains("fatigue") })
        let later = points.map { point in p(Int(point.timestamp.timeIntervalSince1970 - 1_700_000_000) / 30,
                                           won: point.winner == .me, outcome: point.outcome, set: point.setIndex + 1) }
        XCTAssertTrue(lines(later).contains { $0.contains("set 2 to") && $0.contains("set 3") })
    }

    func test_rallyAdviceUsesOwnServicePointsAndDoesNotPrescribeWinners() {
        let own = (0..<10).map { p($0, shot: .servePlusOne) }
            + (10..<20).map { p($0, won: $0 < 13, shot: .rally) }
        XCTAssertTrue(lines(own).contains { $0.contains("review how rallies were lost") })
        let receiving = own.map { p(Int($0.timestamp.timeIntervalSince1970 - 1_700_000_000) / 30,
                                   server: .opponent, won: $0.winner == .me, shot: $0.endingShot) }
        XCTAssertFalse(lines(receiving).contains { $0.contains("On serve") })
    }

    func test_healthUsesPreviousPointAndOnlyRecorderSingles() {
        let points = effort()
        let result = lines(points, type: .singles)
        XCTAssertTrue(result.contains { $0.hasPrefix("First serves in after") && $0.contains("0%") && $0.contains("100%") })
        XCTAssertEqual(result.filter { $0.contains("after higher-movement") || $0.contains("after points with higher") }.count, 1)
        for type: MatchType? in [nil, .doubles] {
            XCTAssertFalse(lines(points, type: type).contains { $0.contains("First serves in after") })
        }
        XCTAssertFalse(lines(points, type: .singles, focal: .opponent).contains { $0.contains("First serves in after") })
        XCTAssertTrue(lines(points, type: .singles, scope: .set(1)).contains { $0.contains("First serves in after") })
    }

    func test_healthSupportsEachSensorButNotMissingScoresGapsOrSparseData() {
        XCTAssertTrue(lines(effort(health: "steps"), type: .singles).contains { $0.contains("after higher-movement points") })
        XCTAssertTrue(lines(effort(health: "hr"), type: .singles).contains { $0.contains("higher recorded heart rate") })
        for points in [effort(health: "none"), effort(brokenScores: true), effort(longGaps: true), Array(effort().prefix(16))] {
            XCTAssertFalse(lines(points, type: .singles).contains { $0.contains("First serves in after") })
        }
    }

    func test_exertionCanIdentifyDoubleFaultsOrServicePointResults() {
        XCTAssertTrue(lines(effort(mode: "fault"), type: .singles).contains { $0.hasPrefix("Double faults after") })
        XCTAssertTrue(lines(effort(mode: "win"), type: .singles).contains { $0.hasPrefix("Service points won after") })
        let resets = effort(health: "steps").enumerated().map { i, point in
            p(i, won: point.winner == .me, second: point.isSecondServe, set: point.setIndex,
              score: point.gameScoreAtStart, steps: 1000 - i)
        }
        XCTAssertFalse(lines(resets, type: .singles).contains { $0.contains("higher-movement") })
    }

    func test_deduplicationAndDeterministicCap() {
        let points = lowFirst() + balance().enumerated().map { index, point in
            p(index + 40, server: point.server, won: point.winner == .me)
        }
        let result = lines(points)
        XCTAssertLessThanOrEqual(result.count, 3)
        XCTAssertEqual(result, lines(Array(points.reversed())))
        let first = lines(lowFirst())
        XCTAssertEqual(first.count, 1, "Weak second-serve results already appear in the first-serve advice")
    }

    func test_exportsDoNotGiveRecorderHealthAdviceToTheOpponent() throws {
        let record = MatchRecord(startTime: Date(), endTime: Date(), setScores: [],
                                 stats: effort(), iWon: true, matchType: .singles)
        let mine = MatchWebViewModel.make(from: record, perspective: .me)
        let theirs = MatchWebViewModel.make(from: record, perspective: .opponent)
        let encoder = JSONEncoder()
        let mineText = String(decoding: try encoder.encode(mine), as: UTF8.self)
        let theirText = String(decoding: try encoder.encode(theirs), as: UTF8.self)
        XCTAssertTrue(mineText.contains("First serves in after"))
        XCTAssertFalse(theirText.contains("First serves in after"))
    }

    // Opt-in Swift/browser parity oracle, consumed by the JS QA script. Normal
    // test runs have no filesystem side effect. Fixtures are fictional.
    func test_browserParityFixtures() throws {
        guard let path = ProcessInfo.processInfo.environment["COACHING_PARITY_OUTPUT"] else { return }
        struct Fixture: Encodable {
            let name: String
            let stats: [PointStat]
            let expected: [String]
            let matchType: MatchType?
            let focal: Player
            let setFilter: Int?
        }
        var fixtures: [Fixture] = []
        let cases = [("first", lowFirst()), ("balance", balance()), ("return", returnErrors(.return)),
                     ("rallyErrors", returnErrors(.rally)), ("effort", effort()),
                     ("steps", effort(health: "steps")), ("hr", effort(health: "hr")), ("faultEffort", effort(mode: "fault")), ("winEffort", effort(mode: "win")),
                     ("gap", effort(longGaps: true)), ("missing", effort(brokenScores: true))]
        for (name, stats) in cases {
            for type: MatchType? in [nil, .singles, .doubles] {
                for focal: Player in [.me, .opponent] {
                    for set: Int? in [nil, 0, 1] {
                        fixtures.append(Fixture(name: name, stats: stats,
                                                expected: lines(stats, type: type, focal: focal, scope: set.map { .set($0) } ?? .all),
                                                matchType: type, focal: focal, setFilter: set))
                    }
                }
            }
        }
        try JSONEncoder().encode(fixtures).write(to: URL(fileURLWithPath: path))
    }
}
