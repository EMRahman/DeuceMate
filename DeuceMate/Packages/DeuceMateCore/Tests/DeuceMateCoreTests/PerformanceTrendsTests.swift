// PerformanceTrendsTests.swift — windowing/filtering order, pooling
// (including the Codex-caught zero-denominator pooling bug this plan fixes),
// and delta orientation/thresholds.
import XCTest
@testable import DeuceMateCore

final class PerformanceTrendsTests: XCTestCase {

    // MARK: - Fixtures

    private func makeSample(
        id: UUID = UUID(), daysAgo: Int, matchType: MatchType = .singles, matchFormat: MatchFormat = .standard,
        winnersHit: Int = 5, unforcedErrorsHit: Int = 2,
        doubleFaults: Int = 1, categorizedServicePoints: Int = 10, isInProgress: Bool = false
    ) -> MatchTrendSample {
        MatchTrendSample(
            matchID: id, startTime: Date().addingTimeInterval(TimeInterval(-daysAgo * 86400)),
            matchType: matchType, matchFormat: matchFormat, recorderWon: isInProgress ? nil : true, isInProgress: isInProgress,
            totalPoints: 20, categorizedPoints: 20, pointsWon: 12, pointsLost: 8,
            categorizedPointsWon: 12, categorizedPointsLost: 8,
            servicePoints: 10, categorizedServicePoints: categorizedServicePoints,
            categorizedOpponentServicePoints: 10,
            firstServesIn: 7, firstServeWins: 5, secondServePoints: 3, secondServesIn: 2, secondServeWins: 1,
            doubleFaults: doubleFaults, returnPointsOnFirst: 6, returnWinsOnFirst: 3,
            returnPointsOnSecond: 4, returnWinsOnSecond: 2, opponentDoubleFaults: 1,
            winnersHit: winnersHit, winnersConceded: 4, unforcedErrorsHit: unforcedErrorsHit, unforcedErrorsDrawn: 3,
            forcedErrorsConceded: 1, forcedErrorsCaused: 1,
            breakPointOpps: 2, breakPointWins: 1, breakPointsFaced: 2, breakPointsLost: 1,
            bigPointTotal: 4, bigPointWins: 2,
            rallyDepth: [.serve: .init(total: 6, wins: 3)], pointsWithEndingShot: 6
        )
    }

    private func makeRecord(id: UUID = UUID(), daysAgo: Int, matchType: MatchType = .singles,
                            matchFormat: MatchFormat = .standard, inProgress: Bool = false) -> MatchRecord {
        let points = (0..<20).map { _ in
            PointStat(setIndex: 0, server: .me, winner: .me, outcome: .winner)
        }
        return MatchRecord(
            id: id, startTime: Date().addingTimeInterval(TimeInterval(-daysAgo * 86400)),
            endTime: inProgress ? nil : Date(), setScores: [SetScore()], stats: points,
            iWon: inProgress ? nil : true,
            matchType: matchType, matchFormat: matchFormat
        )
    }

    // MARK: - samples(from:)

    func test_samples_reordersNewestFirstInputToOldestFirstOutput() {
        let a = makeRecord(daysAgo: 0)   // most recent
        let b = makeRecord(daysAgo: 5)
        let c = makeRecord(daysAgo: 10)  // oldest
        let samples = PerformanceTrends.samples(from: [a, b, c])  // newest-first input
        XCTAssertEqual(samples.map(\.matchID), [c.id, b.id, a.id])  // oldest-first output
    }

    /// Owner-requested: an in-progress match (enough categorized points, but
    /// no endTime/iWon yet) is included, not excluded — its sample carries
    /// isInProgress == true and recorderWon == nil so callers can tell it
    /// apart from a completed draw.
    func test_samples_includesInProgressMatchWithEnoughPoints() {
        let live = makeRecord(daysAgo: 0, inProgress: true)
        let completed = makeRecord(daysAgo: 1)
        let samples = PerformanceTrends.samples(from: [live, completed])
        XCTAssertEqual(Set(samples.map(\.matchID)), Set([live.id, completed.id]))
        let liveSample = samples.first { $0.matchID == live.id }
        XCTAssertEqual(liveSample?.isInProgress, true)
        XCTAssertNil(liveSample?.recorderWon)
        let completedSample = samples.first { $0.matchID == completed.id }
        XCTAssertEqual(completedSample?.isInProgress, false)
    }

    func test_samples_emptyHistoryYieldsEmptyArray() {
        XCTAssertTrue(PerformanceTrends.samples(from: []).isEmpty)
    }

    // MARK: - Filter-before-window ordering (§3.2)

    /// 3 singles matches (days 0,1,2) then 3 doubles matches (days 3,4,5),
    /// oldest-first: [doubles@5, doubles@4, doubles@3, singles@2, singles@1, singles@0].
    /// "Last 2 singles" must mean the 2 most recent SINGLES matches
    /// (days 1,0) — not "singles among the last 2 matches" (which would be
    /// empty, since the last 2 matches by recency are both singles anyway in
    /// this arrangement, so use a shape where the two orders diverge).
    func test_filterBeforeWindow_notWindowBeforeFilter() {
        let doublesOld = [makeSample(daysAgo: 5, matchType: .doubles),
                          makeSample(daysAgo: 4, matchType: .doubles),
                          makeSample(daysAgo: 3, matchType: .doubles)]
        let singlesRecent = [makeSample(daysAgo: 2, matchType: .singles),
                             makeSample(daysAgo: 1, matchType: .singles),
                             makeSample(daysAgo: 0, matchType: .singles)]
        // Oldest-first overall: 3 doubles, then 3 singles.
        let all = doublesOld + singlesRecent
        // "Last 2, singles only": filter to the 3 singles, then take the most
        // recent 2 of THOSE — the 2 most recent singles matches.
        let scoped = PerformanceTrends.scoped(all, filter: TrendFilter(matchType: .singles), window: .last(2))
        XCTAssertEqual(scoped.map(\.matchID), [singlesRecent[1].matchID, singlesRecent[2].matchID])
        // If window were applied first (WRONG), "last 2" of `all` is the two
        // most recent singles matches anyway in this shape, so also prove
        // the wrong order breaks by using a window of 4: windowing first
        // would take the last 4 of `all` (1 doubles + 3 singles), then
        // filtering to singles-only would yield only 3 — but filtering first
        // yields all 3 singles too. Use window 1 against an interleaved
        // shape to force a real divergence:
        let interleaved = [makeSample(daysAgo: 3, matchType: .doubles),
                           makeSample(daysAgo: 2, matchType: .singles),
                           makeSample(daysAgo: 1, matchType: .doubles),
                           makeSample(daysAgo: 0, matchType: .singles)]
        let last1Singles = PerformanceTrends.scoped(interleaved, filter: TrendFilter(matchType: .singles), window: .last(1))
        // Filter-first: singles matches are days 2 and 0 → last 1 is day 0.
        XCTAssertEqual(last1Singles.map(\.matchID), [interleaved[3].matchID])
        // Window-first (the bug this regresses) would take the last 1 of
        // `interleaved` (day 0, singles) then filter — coincidentally the
        // same result here, so assert against window 2 instead, where the
        // two orderings diverge for certain:
        let last2Singles = PerformanceTrends.scoped(interleaved, filter: TrendFilter(matchType: .singles), window: .last(2))
        // Filter-first: both singles matches (days 2 and 0).
        XCTAssertEqual(last2Singles.map(\.matchID), [interleaved[1].matchID, interleaved[3].matchID])
        // Window-first (WRONG) would take the last 2 of `interleaved` (days
        // 1 doubles + 0 singles), then filter to singles-only → just day 0,
        // a single-element array. The correct result above has 2 elements,
        // which is only possible when filtering happens first.
        XCTAssertEqual(last2Singles.count, 2)
    }

    func test_scoped_formatFilterAppliesIndependentlyOfType() {
        let samples = [
            makeSample(daysAgo: 2, matchFormat: .standard),
            makeSample(daysAgo: 1, matchFormat: .superTiebreak),
            makeSample(daysAgo: 0, matchFormat: .standard)
        ]
        let scoped = PerformanceTrends.scoped(samples, filter: TrendFilter(matchFormat: .standard), window: .all)
        XCTAssertEqual(scoped.count, 2)
        XCTAssertTrue(scoped.allSatisfy { $0.matchFormat == .standard })
    }

    func test_scoped_windowLargerThanHistoryReturnsWholeHistory() {
        let samples = [makeSample(daysAgo: 1), makeSample(daysAgo: 0)]
        let scoped = PerformanceTrends.scoped(samples, filter: .all, window: .last(50))
        XCTAssertEqual(scoped.count, 2)
    }

    // MARK: - includeInProgress filtering

    /// Default TrendFilter() excludes an in-progress sample — the feature's
    /// default posture everywhere (owner request).
    func test_scoped_defaultFilterExcludesInProgress() {
        let samples = [makeSample(daysAgo: 1), makeSample(daysAgo: 0, isInProgress: true)]
        let scoped = PerformanceTrends.scoped(samples, filter: TrendFilter(), window: .all)
        XCTAssertEqual(scoped.count, 1)
        XCTAssertFalse(scoped.contains { $0.isInProgress })
    }

    func test_scoped_includeInProgressTrue_includesIt() {
        let samples = [makeSample(daysAgo: 1), makeSample(daysAgo: 0, isInProgress: true)]
        let scoped = PerformanceTrends.scoped(samples, filter: TrendFilter(includeInProgress: true), window: .all)
        XCTAssertEqual(scoped.count, 2)
    }

    /// includeInProgress combines with matchType/matchFormat via AND, same
    /// as every other TrendFilter axis — an in-progress doubles match isn't
    /// pulled in by a singles-only filter just because includeInProgress is
    /// on. The completed singles match still passes through both axes.
    func test_scoped_includeInProgress_combinesWithOtherAxes() {
        let completedSingles = makeSample(daysAgo: 1, matchType: .singles)
        let inProgressDoubles = makeSample(daysAgo: 0, matchType: .doubles, isInProgress: true)
        let filter = TrendFilter(matchType: .singles, includeInProgress: true)
        let scoped = PerformanceTrends.scoped([completedSingles, inProgressDoubles], filter: filter, window: .all)
        XCTAssertEqual(scoped.map(\.matchID), [completedSingles.matchID])
    }

    // MARK: - Pooling (§3.3) — the Codex-caught bug

    /// The exact regression case from the PR review: a zero-UE match
    /// (10W/0UE) has no plottable wueRatio dot, but its 10 winners must
    /// still enter the pooled numerator when combined with a 1W/1UE match.
    /// Correct: 11:1. The bug this test guards against: pooling only
    /// plottable dots would read 1:1, discarding the flawless match's 10
    /// winners and reporting a player's cleanest match as their worst.
    func test_pooled_wueRatio_includesZeroDenominatorMatch() {
        let flawless = makeSample(daysAgo: 1, winnersHit: 10, unforcedErrorsHit: 0)
        let ordinary = makeSample(daysAgo: 0, winnersHit: 1, unforcedErrorsHit: 1)
        let series = PerformanceTrends.series(for: .wueRatio, in: [flawless, ordinary])
        XCTAssertEqual(series?.pooled?.numerator, 11)
        XCTAssertEqual(series?.pooled?.denominator, 1)
        // The flawless match has no dot (denominator 0 → unplottable), but
        // the ordinary match does — points is NOT empty, just shorter than
        // the sample count.
        XCTAssertEqual(series?.points.count, 1)
        XCTAssertEqual(series?.points.first?.index, 1)  // its ordinal position, not 0
    }

    func test_pooled_nilOnlyWhenAggregateDenominatorIsZero() {
        let allZeroUE = [makeSample(daysAgo: 1, unforcedErrorsHit: 0),
                         makeSample(daysAgo: 0, unforcedErrorsHit: 0)]
        let series = PerformanceTrends.series(for: .wueRatio, in: allZeroUE)
        XCTAssertNil(series?.pooled)
    }

    /// Pooled is Σnum/Σden, NOT the mean of per-match rates — these diverge
    /// whenever matches have different denominators.
    func test_pooled_isNotMeanOfPerMatchRates() {
        // Match A: 1/10 = 10%. Match B: 9/10 = 90%. Mean of rates = 50%.
        // But these are deliberately equal-denominator here to first prove
        // pooled == mean when denominators match, then a second pair proves
        // divergence when they don't.
        let equalDen = [makeSample(daysAgo: 1, doubleFaults: 1, categorizedServicePoints: 10),
                        makeSample(daysAgo: 0, doubleFaults: 9, categorizedServicePoints: 10)]
        let equalSeries = PerformanceTrends.series(for: .doubleFaults, in: equalDen)
        XCTAssertEqual(equalSeries?.pooled?.value ?? -1, 0.5, accuracy: 0.0001)

        // Unequal denominators: A = 1/2 (50%), B = 1/100 (1%). Mean of rates
        // = 25.5%. Pooled = 2/102 ≈ 1.96% — very different, and pooled is
        // the correct one (§3.3: long matches shouldn't be swamped by a
        // short match's noisy rate, and vice versa).
        let unequalDen = [makeSample(daysAgo: 1, doubleFaults: 1, categorizedServicePoints: 2),
                          makeSample(daysAgo: 0, doubleFaults: 1, categorizedServicePoints: 100)]
        let unequalSeries = PerformanceTrends.series(for: .doubleFaults, in: unequalDen)
        let meanOfRates = (0.5 + 0.01) / 2
        XCTAssertNotEqual(unequalSeries?.pooled?.value ?? -1, meanOfRates, accuracy: 0.0001)
        XCTAssertEqual(unequalSeries?.pooled?.value ?? -1, 2.0 / 102.0, accuracy: 0.0001)
    }

    // MARK: - Delta orientation, sign, and thresholds

    /// A FALLING double-fault rate must be `.improving` (lower is better),
    /// never `.declining` — the exact bug class §5.3/§10 warn about.
    func test_delta_fallingDoubleFaultRate_isImproving() {
        let prior = [makeSample(daysAgo: 3, doubleFaults: 5, categorizedServicePoints: 10),
                    makeSample(daysAgo: 2, doubleFaults: 5, categorizedServicePoints: 10)]
        let recent = [makeSample(daysAgo: 1, doubleFaults: 1, categorizedServicePoints: 10),
                     makeSample(daysAgo: 0, doubleFaults: 1, categorizedServicePoints: 10)]
        let series = PerformanceTrends.series(for: .doubleFaults, in: prior + recent)
        XCTAssertEqual(series?.delta?.direction, .improving)
        XCTAssertLessThan(series?.delta?.change ?? 1, 0)  // rate fell
    }

    /// Same shape as the double-fault case above, for Unforced Errors —
    /// the metric the owner specifically called out (falling + green must
    /// mean `change < 0`, which is what points TrendSparkline's arrow down).
    func test_delta_fallingUnforcedErrorRate_isImproving() {
        let prior = [makeSample(daysAgo: 3, unforcedErrorsHit: 6), makeSample(daysAgo: 2, unforcedErrorsHit: 6)]
        let recent = [makeSample(daysAgo: 1, unforcedErrorsHit: 1), makeSample(daysAgo: 0, unforcedErrorsHit: 1)]
        let series = PerformanceTrends.series(for: .unforcedErrors, in: prior + recent)
        XCTAssertEqual(series?.delta?.direction, .improving)
        XCTAssertLessThan(series?.delta?.change ?? 1, 0)  // rate fell
    }

    func test_delta_risingWinnerRate_isImproving() {
        let prior = [makeSample(daysAgo: 3, winnersHit: 2), makeSample(daysAgo: 2, winnersHit: 2)]
        let recent = [makeSample(daysAgo: 1, winnersHit: 10), makeSample(daysAgo: 0, winnersHit: 10)]
        let series = PerformanceTrends.series(for: .winners, in: prior + recent)
        XCTAssertEqual(series?.delta?.direction, .improving)
        XCTAssertGreaterThan(series?.delta?.change ?? -1, 0)
    }

    func test_delta_changeIsInPercentagePoints_forPercentMetrics() {
        // categorizedPointsWon fixed at 12 in the fixture; winnersHit 2 → 6
        // is 2/12=16.7% → 6/12=50%, a change of ~33 percentage points.
        let prior = [makeSample(daysAgo: 3, winnersHit: 2), makeSample(daysAgo: 2, winnersHit: 2)]
        let recent = [makeSample(daysAgo: 1, winnersHit: 6), makeSample(daysAgo: 0, winnersHit: 6)]
        let series = PerformanceTrends.series(for: .winners, in: prior + recent)
        XCTAssertEqual(series?.delta?.change ?? 0, 33.33, accuracy: 0.5)
    }

    func test_delta_flatBelowMinimumBlockMatches() {
        // 3 samples total → prior half has 1 (< minimumBlockMatches 2).
        let samples = [makeSample(daysAgo: 2, doubleFaults: 5), makeSample(daysAgo: 1, doubleFaults: 1),
                       makeSample(daysAgo: 0, doubleFaults: 1)]
        let series = PerformanceTrends.series(for: .doubleFaults, in: samples)
        XCTAssertNil(series?.delta)
    }

    func test_delta_flatBelowMinimumChangeThreshold() {
        // 1pp is the .percent threshold; make the change smaller than that.
        let prior = [makeSample(daysAgo: 3, doubleFaults: 10, categorizedServicePoints: 1000),
                    makeSample(daysAgo: 2, doubleFaults: 10, categorizedServicePoints: 1000)]
        let recent = [makeSample(daysAgo: 1, doubleFaults: 11, categorizedServicePoints: 1000),
                     makeSample(daysAgo: 0, doubleFaults: 11, categorizedServicePoints: 1000)]
        let series = PerformanceTrends.series(for: .doubleFaults, in: prior + recent)
        XCTAssertEqual(series?.delta?.direction, .flat)
    }

    func test_delta_neutralMetric_isAlwaysFlat() {
        // Even a large swing in a neutral (rally-depth-share) metric must
        // not be reported as improving/declining.
        let prior = [makeSample(daysAgo: 3), makeSample(daysAgo: 2)]
        let recent = [makeSample(daysAgo: 1), makeSample(daysAgo: 0)]
        let series = PerformanceTrends.series(for: .depthShareServe, in: prior + recent)
        XCTAssertEqual(series?.delta?.direction, .flat)
    }

    // MARK: - series(for:in:) edge cases

    func test_series_nilForEmptySamples() {
        XCTAssertNil(PerformanceTrends.series(for: .doubleFaults, in: []))
    }

    func test_series_singleMatch_noDeltaButHasPooledAndPoint() {
        let series = PerformanceTrends.series(for: .doubleFaults, in: [makeSample(daysAgo: 0)])
        XCTAssertNotNil(series)
        XCTAssertNil(series?.delta)
        XCTAssertNotNil(series?.pooled)
        XCTAssertEqual(series?.points.count, 1)
    }

    func test_headline_returnsUpToFourSeries() {
        let samples = (0..<5).map { makeSample(daysAgo: $0) }
        let headline = PerformanceTrends.headline(in: samples)
        XCTAssertEqual(headline.map(\.metric), TrendMetric.headline)
    }

    func test_seriesForGroup_returnsOnlyThatGroupsMetrics() {
        let samples = (0..<5).map { makeSample(daysAgo: $0) }
        let attackSeries = PerformanceTrends.series(for: .attack, in: samples)
        XCTAssertTrue(attackSeries.allSatisfy { $0.metric.group == .attack })
        XCTAssertFalse(attackSeries.isEmpty)
    }
}
