// RecCoachInsightsTests.swift — exercises each rule in the recreational
// player coaching engine.
import XCTest
@testable import DeuceMateCore

final class RecCoachInsightsTests: XCTestCase {

    private func point(
        _ index: Int,
        setIndex: Int = 0,
        server: Player = .me,
        winner: Player,
        outcome: PointOutcome = .winner,
        isSecondServe: Bool = false,
        isBreakPoint: Bool = false,
        endingShot: EndingShot? = nil,
        gameScoreAtStart: GameScoreSnapshot? = nil
    ) -> PointStat {
        PointStat(
            timestamp: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + index * 30)),
            setIndex: setIndex,
            server: server,
            winner: winner,
            outcome: outcome,
            isSecondServe: isSecondServe,
            isBreakPoint: isBreakPoint,
            endingShot: endingShot,
            gameScoreAtStart: gameScoreAtStart
        )
    }

    // MARK: - Gating

    func test_returnsEmptyWhenInsufficientData() {
        let stats = (0..<10).map { point($0, winner: .me, outcome: .winner) }
        let insights = RecCoachInsights.generate(stats: stats, focal: .me)
        XCTAssertTrue(insights.isEmpty)
    }

    func test_returnsEmptyWhenAllUncategorized() {
        let stats = (0..<40).map { point($0, winner: .me, outcome: .uncategorized) }
        let insights = RecCoachInsights.generate(stats: stats, focal: .me)
        XCTAssertTrue(insights.isEmpty)
    }

    // MARK: - Rule 1: self-inflicted-loss share

    func test_emitsSelfInflictedLossInsight() {
        // 30 lost points, 20 of which are own UEs → 67% share. Plus enough wins
        // to clear the 25-categorized gate.
        var stats: [PointStat] = []
        for i in 0..<20 { stats.append(point(i, winner: .opponent, outcome: .unforcedError)) }
        for i in 0..<10 { stats.append(point(i + 20, winner: .opponent, outcome: .forcedError)) }
        for i in 0..<10 { stats.append(point(i + 30, winner: .me, outcome: .winner)) }
        let insights = RecCoachInsights.generate(stats: stats, focal: .me)
        XCTAssertTrue(
            insights.contains { $0.contains("reliability is your biggest lever") },
            "Expected self-inflicted insight, got \(insights)"
        )
    }

    func test_doesNotEmitSelfInflictedBelowThreshold() {
        // 30 lost points, only 12 own UEs → 40% share — below 55% threshold.
        var stats: [PointStat] = []
        for i in 0..<12 { stats.append(point(i, winner: .opponent, outcome: .unforcedError)) }
        for i in 0..<18 { stats.append(point(i + 12, winner: .opponent, outcome: .forcedError)) }
        for i in 0..<10 { stats.append(point(i + 30, winner: .me, outcome: .winner)) }
        let insights = RecCoachInsights.generate(stats: stats, focal: .me)
        XCTAssertFalse(insights.contains { $0.contains("reliability") })
    }

    // MARK: - Rule 2: per-set UE drift

    func test_emitsPerSetUEDriftInsight() {
        // Set 0: 15 losses, 2 UEs (~13%). Set 1: 15 losses, 7 UEs (~47%). Drift 34%.
        var stats: [PointStat] = []
        // Set 0 losses
        for i in 0..<2  { stats.append(point(i, setIndex: 0, winner: .opponent, outcome: .unforcedError)) }
        for i in 0..<13 { stats.append(point(i + 2, setIndex: 0, winner: .opponent, outcome: .forcedError)) }
        // Set 0 wins to pad
        for i in 0..<5  { stats.append(point(i + 15, setIndex: 0, winner: .me, outcome: .winner)) }
        // Set 1 losses
        for i in 0..<7  { stats.append(point(i + 20, setIndex: 1, winner: .opponent, outcome: .unforcedError)) }
        for i in 0..<8  { stats.append(point(i + 27, setIndex: 1, winner: .opponent, outcome: .forcedError)) }
        // Set 1 wins to pad
        for i in 0..<5  { stats.append(point(i + 35, setIndex: 1, winner: .me, outcome: .winner)) }
        let insights = RecCoachInsights.generate(stats: stats, focal: .me)
        XCTAssertTrue(
            insights.contains { $0.contains("set 1 to") && $0.contains("set 2") },
            "Expected UE-drift insight, got \(insights)"
        )
    }

    func test_singleSetSuppressesPerSetRule() {
        var stats: [PointStat] = []
        for i in 0..<15 { stats.append(point(i, setIndex: 0, winner: .opponent, outcome: .unforcedError)) }
        for i in 0..<15 { stats.append(point(i + 15, setIndex: 0, winner: .me, outcome: .winner)) }
        let insights = RecCoachInsights.generate(stats: stats, focal: .me)
        XCTAssertFalse(insights.contains { $0.contains("set 1 to") })
    }

    // MARK: - Rule 3: double-fault leakage

    func test_emitsDoubleFaultInsight() {
        // 4 DFs across 5 focal service games (server alternates by game).
        // Build 5 focal games and 5 opp games, alternating, each game = 4 points.
        var stats: [PointStat] = []
        var idx = 0
        for game in 0..<10 {
            let server: Player = game.isMultiple(of: 2) ? .me : .opponent
            for _ in 0..<4 {
                let isDF = (server == .me && game < 8 && (game / 2) < 4 && idx % 4 == 0)
                stats.append(point(
                    idx,
                    server: server,
                    winner: isDF ? .opponent : .me,
                    outcome: isDF ? .doubleFault : .winner,
                    isSecondServe: isDF
                ))
                idx += 1
            }
        }
        let insights = RecCoachInsights.generate(stats: stats, focal: .me)
        XCTAssertTrue(
            insights.contains { $0.contains("double faults in") && $0.contains("service games") },
            "Expected double-fault insight, got \(insights)"
        )
    }

    // MARK: - Rule 4: pressure-point drop

    func test_emitsPressurePointDropInsight() {
        // 12 big points (3 wins = 25%), 20 normal points (14 wins = 70%). Gap = 45pp.
        // Big points are tagged with isBreakPoint = true.
        var stats: [PointStat] = []
        // Big point wins
        for i in 0..<3 { stats.append(point(i, winner: .me, outcome: .winner, isBreakPoint: true)) }
        // Big point losses
        for i in 0..<9 { stats.append(point(i + 3, winner: .opponent, outcome: .unforcedError, isBreakPoint: true)) }
        // Normal point wins
        for i in 0..<14 { stats.append(point(i + 12, winner: .me, outcome: .winner)) }
        // Normal point losses
        for i in 0..<6  { stats.append(point(i + 26, winner: .opponent, outcome: .unforcedError)) }
        let insights = RecCoachInsights.generate(stats: stats, focal: .me)
        XCTAssertTrue(
            insights.contains { $0.contains("big points") && $0.contains("0-0") },
            "Expected pressure-point drop insight, got \(insights)"
        )
    }

    func test_doesNotEmitPressurePointDropBelowThreshold() {
        // 12 big points (6 wins = 50%), 20 normal (14 wins = 70%). Gap = 20pp — just at boundary,
        // must be strictly > 20pp for the rule to fire (guard uses >=0.20 so 20pp fires).
        // Use 15pp gap to confirm it stays silent.
        var stats: [PointStat] = []
        for i in 0..<7  { stats.append(point(i, winner: .me, outcome: .winner, isBreakPoint: true)) }
        for i in 0..<5  { stats.append(point(i + 7, winner: .opponent, outcome: .unforcedError, isBreakPoint: true)) }
        for i in 0..<14 { stats.append(point(i + 12, winner: .me, outcome: .winner)) }
        for i in 0..<6  { stats.append(point(i + 26, winner: .opponent, outcome: .unforcedError)) }
        // Big = 7/12 = 58%; Normal = 14/20 = 70%. Gap = 12pp — below 20pp threshold.
        let insights = RecCoachInsights.generate(stats: stats, focal: .me)
        XCTAssertFalse(
            insights.contains { $0.contains("big points") },
            "Pressure-point insight should be suppressed below 20pp gap, got \(insights)"
        )
    }

    // MARK: - Rule 6: second-serve vulnerability

    func test_emitsSecondServeVulnerabilityInsight() {
        // 10 first-serve points, 7 wins (70%). 10 second-serve points in play, 4 wins (40%). Gap = 30pp.
        var stats: [PointStat] = []
        for i in 0..<7 {
            stats.append(point(i, server: .me, winner: .me, outcome: .winner, isSecondServe: false))
        }
        for i in 0..<3 {
            stats.append(point(i + 7, server: .me, winner: .opponent, outcome: .unforcedError, isSecondServe: false))
        }
        for i in 0..<4 {
            stats.append(point(i + 10, server: .me, winner: .me, outcome: .winner, isSecondServe: true))
        }
        for i in 0..<6 {
            stats.append(point(i + 14, server: .me, winner: .opponent, outcome: .unforcedError, isSecondServe: true))
        }
        // Pad categorized count to ≥20
        for i in 0..<4 {
            stats.append(point(i + 20, server: .opponent, winner: .me, outcome: .winner, isSecondServe: false))
        }
        let insights = RecCoachInsights.generate(stats: stats, focal: .me)
        XCTAssertTrue(
            insights.contains { $0.contains("1st serve") && $0.contains("2nd serve") && $0.contains("spin-heavy") },
            "Expected second-serve vulnerability insight, got \(insights)"
        )
    }

    func test_doesNotEmitSecondServeVulnerabilityInsufficientData() {
        // Only 5 second-serve points — below the 8-point minimum.
        var stats: [PointStat] = []
        for i in 0..<10 {
            stats.append(point(i, server: .me, winner: .me, outcome: .winner, isSecondServe: false))
        }
        for i in 0..<5 {
            stats.append(point(i + 10, server: .me, winner: .opponent, outcome: .unforcedError, isSecondServe: true))
        }
        for i in 0..<10 {
            stats.append(point(i + 15, server: .opponent, winner: .me, outcome: .winner, isSecondServe: false))
        }
        let insights = RecCoachInsights.generate(stats: stats, focal: .me)
        XCTAssertFalse(
            insights.contains { $0.contains("spin-heavy") },
            "Second-serve insight should be suppressed with < 8 second-serve points, got \(insights)"
        )
    }

    // MARK: - Rule 7: return unforced errors

    func test_emitsReturnUEInsight() {
        // 12 return losses: 6 own UEs (50%) — above 40% threshold.
        var stats: [PointStat] = []
        for i in 0..<6 {
            stats.append(point(i, server: .opponent, winner: .opponent, outcome: .unforcedError))
        }
        for i in 0..<6 {
            stats.append(point(i + 6, server: .opponent, winner: .opponent, outcome: .forcedError))
        }
        // Pad wins + own serve points to reach ≥20 categorized
        for i in 0..<10 {
            stats.append(point(i + 12, server: .opponent, winner: .me, outcome: .winner))
        }
        for i in 0..<4 {
            stats.append(point(i + 22, server: .me, winner: .me, outcome: .winner))
        }
        let insights = RecCoachInsights.generate(stats: stats, focal: .me)
        XCTAssertTrue(
            insights.contains { $0.contains("return losses") && $0.contains("crosscourt") },
            "Expected return UE insight, got \(insights)"
        )
    }

    func test_doesNotEmitReturnUEBelowThreshold() {
        // 12 return losses: only 4 own UEs (33%) — below 40% threshold.
        var stats: [PointStat] = []
        for i in 0..<4 {
            stats.append(point(i, server: .opponent, winner: .opponent, outcome: .unforcedError))
        }
        for i in 0..<8 {
            stats.append(point(i + 4, server: .opponent, winner: .opponent, outcome: .forcedError))
        }
        for i in 0..<10 {
            stats.append(point(i + 12, server: .opponent, winner: .me, outcome: .winner))
        }
        for i in 0..<4 {
            stats.append(point(i + 22, server: .me, winner: .me, outcome: .winner))
        }
        let insights = RecCoachInsights.generate(stats: stats, focal: .me)
        XCTAssertFalse(
            insights.contains { $0.contains("crosscourt") },
            "Return UE insight should be suppressed below 40% share, got \(insights)"
        )
    }

    // MARK: - Rule 5: rally-length

    func test_emitsRallyLengthInsight() {
        // Need ≥20 categorized. 10 Serve+1 wins, 10 long rallies with 3 wins.
        var stats: [PointStat] = []
        for i in 0..<10 {
            stats.append(point(i, winner: .me, outcome: .winner, endingShot: .servePlusOne))
        }
        for i in 0..<10 {
            let winner: Player = i < 3 ? .me : .opponent
            let outcome: PointOutcome = winner == .me ? .winner : .unforcedError
            stats.append(point(i + 10, winner: winner, outcome: outcome, endingShot: .rally))
        }
        let insights = RecCoachInsights.generate(stats: stats, focal: .me)
        XCTAssertTrue(
            insights.contains { $0.contains("Serve+1") && $0.contains("long rallies") },
            "Expected rally-length insight, got \(insights)"
        )
    }

    // MARK: - Rule 5: set-duration energy decline

    func test_emitsSetDurationDeclineInsight() {
        // Set 0: 30 points, 20 wins (67%). Set 1: 30 points, 12 wins (40%). Drop 27%.
        // Set 0 duration: 35 min. Set 1 duration: 25 min (present).
        var stats: [PointStat] = []
        for i in 0..<20 { stats.append(point(i, setIndex: 0, winner: .me, outcome: .winner)) }
        for i in 0..<10 { stats.append(point(i + 20, setIndex: 0, winner: .opponent, outcome: .unforcedError)) }
        for i in 0..<12 { stats.append(point(i + 30, setIndex: 1, winner: .me, outcome: .winner)) }
        for i in 0..<18 { stats.append(point(i + 42, setIndex: 1, winner: .opponent, outcome: .unforcedError)) }
        let durations: [Int: TimeInterval] = [0: 35 * 60, 1: 25 * 60]
        let insights = RecCoachInsights.generate(
            stats: stats, focal: .me, setElapsedSeconds: durations
        )
        XCTAssertTrue(
            insights.contains { $0.contains("35-minute set 1") },
            "Expected energy-decline insight, got \(insights)"
        )
    }

    // MARK: - Cap & priority

    func test_capsAtThreeInsights() {
        // Build a match that triggers self-inflicted, UE drift, DFs, rally length.
        var stats: [PointStat] = []
        // Set 0: 18 points — 6 own UEs, 6 opp FE losses, 6 wins. Lost=12, UE=6 → 50% UE share.
        for i in 0..<6  { stats.append(point(i, setIndex: 0, winner: .opponent, outcome: .unforcedError)) }
        for i in 0..<6  { stats.append(point(i + 6, setIndex: 0, winner: .opponent, outcome: .forcedError)) }
        for i in 0..<6  { stats.append(point(i + 12, setIndex: 0, winner: .me, outcome: .winner, endingShot: .servePlusOne)) }
        // Set 1: 25 points — 14 own UEs, 4 opp FE losses, 4 wins, 3 rally losses.
        for i in 0..<14 { stats.append(point(i + 18, setIndex: 1, winner: .opponent, outcome: .unforcedError, endingShot: .rally)) }
        for i in 0..<4  { stats.append(point(i + 32, setIndex: 1, winner: .opponent, outcome: .forcedError, endingShot: .rally)) }
        for i in 0..<4  { stats.append(point(i + 36, setIndex: 1, winner: .me, outcome: .winner, endingShot: .servePlusOne)) }
        for i in 0..<3  { stats.append(point(i + 40, setIndex: 1, winner: .me, outcome: .winner, endingShot: .servePlusOne)) }
        let insights = RecCoachInsights.generate(stats: stats, focal: .me)
        XCTAssertLessThanOrEqual(insights.count, 3)
    }

    func test_priorityOrderingFavorsSelfInflictedFirst() {
        // Trigger both self-inflicted (≥55% UE+DF share of losses) and UE drift.
        // Set 0 lost=15 (4 UE + 11 FE), set 1 lost=16 (14 UE + 2 FE).
        // Self-inflicted share: 18 / 31 ≈ 58%. UE drift: 27% → 88%.
        var stats: [PointStat] = []
        for i in 0..<4  { stats.append(point(i, setIndex: 0, winner: .opponent, outcome: .unforcedError)) }
        for i in 0..<11 { stats.append(point(i + 4, setIndex: 0, winner: .opponent, outcome: .forcedError)) }
        for i in 0..<5  { stats.append(point(i + 15, setIndex: 0, winner: .me, outcome: .winner)) }
        for i in 0..<14 { stats.append(point(i + 20, setIndex: 1, winner: .opponent, outcome: .unforcedError)) }
        for i in 0..<2  { stats.append(point(i + 34, setIndex: 1, winner: .opponent, outcome: .forcedError)) }
        for i in 0..<5  { stats.append(point(i + 36, setIndex: 1, winner: .me, outcome: .winner)) }
        let insights = RecCoachInsights.generate(stats: stats, focal: .me)
        XCTAssertFalse(insights.isEmpty)
        XCTAssertTrue(
            insights[0].contains("reliability"),
            "Expected self-inflicted to lead, got \(insights)"
        )
    }

    // MARK: - Set scope

    func test_setScopeRetargetsDriftToSelectedSet() {
        // Three-set match. Selecting set 3 (index 2) should retarget the
        // cross-set drift rule to the set 2 → set 3 transition.
        // Set 1 (index 1): 15 losses, 2 UEs (~13%). Set 2 (index 2): 15
        // losses, 7 UEs (~47%). Drift ≈ 34%.
        var stats: [PointStat] = []
        var idx = 0
        for _ in 0..<20 { stats.append(point(idx, setIndex: 0, winner: .me, outcome: .winner)); idx += 1 }
        for _ in 0..<2  { stats.append(point(idx, setIndex: 1, winner: .opponent, outcome: .unforcedError)); idx += 1 }
        for _ in 0..<13 { stats.append(point(idx, setIndex: 1, winner: .opponent, outcome: .forcedError)); idx += 1 }
        for _ in 0..<5  { stats.append(point(idx, setIndex: 1, winner: .me, outcome: .winner)); idx += 1 }
        for _ in 0..<7  { stats.append(point(idx, setIndex: 2, winner: .opponent, outcome: .unforcedError)); idx += 1 }
        for _ in 0..<8  { stats.append(point(idx, setIndex: 2, winner: .opponent, outcome: .forcedError)); idx += 1 }
        for _ in 0..<5  { stats.append(point(idx, setIndex: 2, winner: .me, outcome: .winner)); idx += 1 }

        let insights = RecCoachInsights.generate(stats: stats, focal: .me, setScope: .set(2))
        XCTAssertTrue(
            insights.contains { $0.contains("set 2 to") && $0.contains("set 3") },
            "Expected drift retargeted to the set 2 → set 3 transition, got \(insights)"
        )
    }

    func test_setScopeZeroSuppressesCrossSetRules() {
        // Set 1 (index 0) carries a strong self-inflicted pattern. There is no
        // preceding set, so cross-set fatigue rules must stay silent while the
        // single-set rule still fires.
        var stats: [PointStat] = []
        var idx = 0
        for _ in 0..<20 { stats.append(point(idx, setIndex: 0, winner: .opponent, outcome: .unforcedError)); idx += 1 }
        for _ in 0..<10 { stats.append(point(idx, setIndex: 0, winner: .opponent, outcome: .forcedError)); idx += 1 }
        for _ in 0..<10 { stats.append(point(idx, setIndex: 0, winner: .me, outcome: .winner)); idx += 1 }
        for _ in 0..<20 { stats.append(point(idx, setIndex: 1, winner: .me, outcome: .winner)); idx += 1 }

        let insights = RecCoachInsights.generate(stats: stats, focal: .me, setScope: .set(0))
        XCTAssertTrue(
            insights.contains { $0.contains("reliability") },
            "Expected self-inflicted insight for set 1, got \(insights)"
        )
        XCTAssertFalse(
            insights.contains { $0.contains("climbed") },
            "Cross-set drift must be suppressed for the first set, got \(insights)"
        )
    }

    func test_setScopeRestrictsSingleSetRulesToSelectedSet() {
        // Set 1 (index 0) carries the self-inflicted pattern; set 2 (index 1)
        // is clean. Scoping to set 2 must not surface set 1's pattern, but the
        // whole-match scope still should.
        var stats: [PointStat] = []
        var idx = 0
        for _ in 0..<20 { stats.append(point(idx, setIndex: 0, winner: .opponent, outcome: .unforcedError)); idx += 1 }
        for _ in 0..<10 { stats.append(point(idx, setIndex: 0, winner: .opponent, outcome: .forcedError)); idx += 1 }
        for _ in 0..<10 { stats.append(point(idx, setIndex: 0, winner: .me, outcome: .winner)); idx += 1 }
        for _ in 0..<25 { stats.append(point(idx, setIndex: 1, winner: .me, outcome: .winner)); idx += 1 }

        let scoped = RecCoachInsights.generate(stats: stats, focal: .me, setScope: .set(1))
        XCTAssertFalse(
            scoped.contains { $0.contains("reliability") },
            "Set 2 scope must not surface set 1's self-inflicted pattern, got \(scoped)"
        )

        let whole = RecCoachInsights.generate(stats: stats, focal: .me, setScope: .all)
        XCTAssertTrue(
            whole.contains { $0.contains("reliability") },
            "Whole-match scope should still surface the self-inflicted pattern, got \(whole)"
        )
    }
}
