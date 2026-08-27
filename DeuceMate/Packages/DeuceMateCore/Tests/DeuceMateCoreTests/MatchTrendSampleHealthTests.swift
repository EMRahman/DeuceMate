// MatchTrendSampleHealthTests.swift — the movement and fatigue counters,
// and the traps docs/features/HEALTH_TRENDS_PLAN.md §2 names.
// The recurring theme: health data is SPARSE, so every assertion here is really
// about telling "no data" apart from "zero".
import XCTest
@testable import DeuceMateCore

final class MatchTrendSampleHealthTests: XCTestCase {

    // MARK: - Fixtures

    private struct SetSpec {
        var index: Int
        var points: Int
        var wins: Int
        /// Steps accumulated per point, or nil for no step sampling.
        var stepDelta: Int?
        /// How many of the set's points carry a step sample. nil == all.
        var stepsOnFirst: Int?

        init(index: Int, points: Int, wins: Int,
             stepDelta: Int? = nil, stepsOnFirst: Int? = nil) {
            self.index = index
            self.points = points
            self.wins = wins
            self.stepDelta = stepDelta
            self.stepsOnFirst = stepsOnFirst
        }
    }

    /// Builds a categorized match from set specs. Timestamps increase across
    /// the whole match so `stepsTimeline` order matches play order, and step
    /// cumulatives run continuously across sets the way a real workout's do.
    private func makeRecord(
        sets: [SetSpec],
        inProgress: Bool = false,
        totalSteps: Int? = nil,
        totalDistanceMeters: Double? = nil,
        matchElapsedSeconds: TimeInterval = 3600,
        matchFormat: MatchFormat = .standard
    ) -> MatchRecord {
        var stats: [PointStat] = []
        var cumulative = 1000
        var offset: TimeInterval = 0
        for spec in sets {
            for i in 0..<spec.points {
                let carriesSteps = spec.stepDelta != nil && i < (spec.stepsOnFirst ?? spec.points)
                if let delta = spec.stepDelta, carriesSteps { cumulative += delta }
                stats.append(PointStat(
                    timestamp: Date(timeIntervalSince1970: offset),
                    setIndex: spec.index,
                    server: i.isMultiple(of: 2) ? .me : .opponent,
                    // Wins are spread evenly across the set rather than
                    // clustered at the front, so a partially sampled window has
                    // the same win rate as the whole set. Clustering them made
                    // a coverage-sensitivity test measure the fixture instead
                    // of the metric. The per-set totals are unchanged.
                    winner: ((i + 1) * spec.wins) / spec.points > (i * spec.wins) / spec.points
                        ? .me : .opponent,
                    outcome: .winner,
                    endingShot: .rally,
                    stepsCumulative: carriesSteps ? cumulative : nil
                ))
                offset += 30
            }
        }
        return MatchRecord(
            startTime: Date(timeIntervalSince1970: 0),
            endTime: inProgress ? nil : Date(timeIntervalSince1970: offset),
            setScores: [SetScore()],
            stats: stats,
            iWon: inProgress ? nil : true,
            matchFormat: matchFormat,
            matchElapsedSeconds: matchElapsedSeconds,
            totalSteps: totalSteps,
            totalDistanceMeters: totalDistanceMeters
        )
    }

    // MARK: - Field mapping

    func test_healthCounters_mapFromTheSampledTimelines() throws {
        let record = makeRecord(
            sets: [SetSpec(index: 0, points: 30, wins: 18, stepDelta: 4)],
            matchElapsedSeconds: 3600
        )
        let sample = try XCTUnwrap(MatchTrendSample(record: record))

        XCTAssertEqual(sample.stepSampledPoints, 30)
        // The first sampled point is the BASELINE and carries a load of 0 —
        // MatchStatsSummary.sampledStepLoads' rule — so 30 samples yield 29
        // deltas. Pairing sum with count here reproduces averageSteps exactly,
        // which is what keeps the trend and the text export in agreement.
        XCTAssertEqual(sample.stepSumLoad, 4 * 29)
        let pooledAverage = Int((Double(sample.stepSumLoad) / Double(sample.stepSampledPoints)).rounded())
        XCTAssertEqual(pooledAverage,
                       MatchStatsSummary.averageSteps(
                           MatchStatsSummary(stats: record.stats, focal: .me).stepsTimeline))
    }

    // MARK: - Trap 2: never the totalSteps linear fallback

    func test_stepMetrics_areNilWhenOnlyAWholeMatchTotalExists() throws {
        // A legacy match: a workout step total, but no per-point samples.
        // StepsSeries would spread the total evenly and produce a perfectly
        // flat steps-per-point of totalSteps/n — a number that measures
        // nothing. Trends must decline to plot it.
        let record = makeRecord(
            sets: [SetSpec(index: 0, points: 30, wins: 18)],
            totalSteps: 5000
        )
        let sample = try XCTUnwrap(MatchTrendSample(record: record))

        XCTAssertEqual(sample.stepSampledPoints, 0)
        XCTAssertEqual(sample.stepSumLoad, 0)
        XCTAssertNil(TrendMetric.stepsPerPointWon.rawPair(in: sample))
        // The tennis metrics are unaffected — the families gate independently.
        XCTAssertNotNil(TrendMetric.pointsWon.rawPair(in: sample))
    }

    // MARK: - Trap 1: nil is never zero

    func test_healthFreeMatch_isStillEligibleAndSimplyHasNoHealthDots() throws {
        let record = makeRecord(sets: [SetSpec(index: 0, points: 30, wins: 18)])
        let sample = try XCTUnwrap(MatchTrendSample(record: record),
                                   "a match without Health data must still be a valid sample")

        // Tennis metrics are untouched.
        XCTAssertNotNil(TrendMetric.pointsWon.rawPair(in: sample))
        // Every movement metric declines to produce a pair.
        for metric: TrendMetric in [.stepsPerPointWon, .stepsPerPointFirstSet, .stepsPerPointFinalSet] {
            XCTAssertNil(metric.rawPair(in: sample), "\(metric) invented data from nothing")
        }
    }

    func test_pooling_skipsHealthFreeMatchesRatherThanCountingThemAsZero() throws {
        // 30 points at 4 steps each, 15 won: 116 steps over 15 sampled wins.
        let withSteps = try XCTUnwrap(MatchTrendSample(record: makeRecord(
            sets: [SetSpec(index: 0, points: 30, wins: 15, stepDelta: 4)])))
        let withoutSteps = try XCTUnwrap(MatchTrendSample(record: makeRecord(
            sets: [SetSpec(index: 0, points: 30, wins: 15)])))

        let series = try XCTUnwrap(
            PerformanceTrends.series(for: .stepsPerPointWon, in: [withoutSteps, withSteps]))
        // One plottable dot, and the pooled figure is the sampled match's own
        // rate — not halved by a phantom zero-step match.
        XCTAssertEqual(series.points.count, 1)
        XCTAssertEqual(series.pooled?.numerator, withSteps.stepSumLoad)
        XCTAssertEqual(series.pooled?.denominator, withSteps.stepSampledPointsWon)
    }

    // MARK: - The fatigue set-pair rule

    func test_fatigue_comparesTheFirstAndLastPlayedSet_notAdjacentOnes() throws {
        let record = makeRecord(sets: [
            SetSpec(index: 0, points: 30, wins: 21, stepDelta: 4),
            SetSpec(index: 1, points: 26, wins: 13, stepDelta: 5),
            SetSpec(index: 2, points: 28, wins: 11, stepDelta: 6)
        ])
        let split = try XCTUnwrap(MatchTrendSample(record: record)?.fatigue)

        XCTAssertEqual(split.firstSet.setIndex, 0)
        XCTAssertEqual(split.finalSet.setIndex, 2)
        XCTAssertEqual(split.firstSet.points, 30)
        XCTAssertEqual(split.firstSet.pointsWon, 21)
        XCTAssertEqual(split.finalSet.points, 28)
        XCTAssertEqual(split.finalSet.pointsWon, 11)
        XCTAssertEqual(split.finalSet.stepSampledPoints, 27, "the set's opening delta is dropped")
    }

    func test_fatigue_isNilWhenEitherSetIsTooShort() throws {
        // A super-tiebreak decider is a "set" by index but not by workload.
        let record = makeRecord(sets: [
            SetSpec(index: 0, points: 30, wins: 18, stepDelta: 4),
            SetSpec(index: 1, points: 15, wins: 6, stepDelta: 5)
        ])
        XCTAssertNil(MatchTrendSample(record: record)?.fatigue)
    }

    func test_fatigue_isNilForASingleSetMatch() throws {
        let record = makeRecord(sets: [SetSpec(index: 0, points: 30, wins: 18, stepDelta: 4)])
        XCTAssertNil(MatchTrendSample(record: record)?.fatigue)
    }

    func test_fatigue_isNilForAnInProgressMatch_butTheOtherCountersSurvive() throws {
        let record = makeRecord(sets: [
            SetSpec(index: 0, points: 30, wins: 18, stepDelta: 4),
            SetSpec(index: 1, points: 24, wins: 10, stepDelta: 5)
        ], inProgress: true)
        let sample = try XCTUnwrap(MatchTrendSample(record: record))

        XCTAssertTrue(sample.isInProgress)
        XCTAssertNil(sample.fatigue, "a set still being played is a partial reading")
        // The live match still contributes to every non-fatigue metric.
        XCTAssertNotNil(TrendMetric.stepsPerPointWon.rawPair(in: sample))
        XCTAssertNil(TrendMetric.winRateFirstSet.rawPair(in: sample))
    }

    func test_fatigueSetPoints_gateAtTwentyPoints() throws {
        let short = makeRecord(sets: [
            SetSpec(index: 0, points: 30, wins: 18),
            SetSpec(index: 1, points: 19, wins: 9)
        ])
        XCTAssertNil(MatchTrendSample(record: short)?.fatigue)

        let long = makeRecord(sets: [
            SetSpec(index: 0, points: 30, wins: 18),
            SetSpec(index: 1, points: 20, wins: 9)
        ])
        XCTAssertNotNil(MatchTrendSample(record: long)?.fatigue)
    }

    // MARK: - Trap 3: each family gates on its own denominator

    func test_fatiguePairs_requireCoverageInBothSets_neverDrawOneLineAlone() throws {
        // Step sampling only started in the second set — a real pattern when the
        // watch's stream drops out early on. The win-rate pair is unaffected,
        // because it counts every point rather than the sampled ones.
        let record = makeRecord(sets: [
            SetSpec(index: 0, points: 30, wins: 21),
            SetSpec(index: 1, points: 26, wins: 10, stepDelta: 5)
        ])
        let sample = try XCTUnwrap(MatchTrendSample(record: record))

        XCTAssertNotNil(sample.fatigue)
        XCTAssertNil(TrendMetric.stepsPerPointFirstSet.rawPair(in: sample))
        XCTAssertNil(TrendMetric.stepsPerPointFinalSet.rawPair(in: sample),
                     "the covered half must not be plotted without its partner")
        XCTAssertNotNil(TrendMetric.winRateFirstSet.rawPair(in: sample))
        XCTAssertNotNil(TrendMetric.winRateFinalSet.rawPair(in: sample))
    }

    // MARK: - Trap 5: zones follow the supplied yardstick

    // MARK: - Coverage gates

    // MARK: - Orientation

    func test_stepsPerPointWon_fallingIsImproving() throws {
        // Four matches, each winning its points progressively more cheaply.
        let samples = try [9, 8, 5, 4].map { delta in
            try XCTUnwrap(MatchTrendSample(record: makeRecord(
                sets: [SetSpec(index: 0, points: 30, wins: 15, stepDelta: delta)])))
        }
        let series = try XCTUnwrap(PerformanceTrends.series(for: .stepsPerPointWon, in: samples))
        let delta = try XCTUnwrap(series.delta)

        XCTAssertLessThan(delta.change, 0, "steps per point won fell")
        XCTAssertEqual(delta.direction, .improving,
                       "running less for the same points is an improvement, not a decline")
    }

    // MARK: - Regressions: numerator and denominator must cover the same window

    /// `stepsPerPointWon` paired a sampled-window numerator with an all-match
    /// denominator, so the rate fell purely as step coverage fell — and it is
    /// the one health metric with an orientation, so that read as `.improving`.
    func test_stepsPerPointWon_isUnaffectedByStepCoverage() throws {
        // Same movement and the same 50% win rate throughout; the only
        // difference is how much of the match the watch sampled.
        let fullyCovered = makeRecord(sets: [
            SetSpec(index: 0, points: 60, wins: 30, stepDelta: 10)
        ])
        let halfCovered = makeRecord(sets: [
            SetSpec(index: 0, points: 60, wins: 30, stepDelta: 10, stepsOnFirst: 20)
        ])

        let full = try XCTUnwrap(MatchTrendSample(record: fullyCovered))
        let half = try XCTUnwrap(MatchTrendSample(record: halfCovered))

        let fullPair = try XCTUnwrap(TrendMetric.stepsPerPointWon.rawPair(in: full))
        let halfPair = try XCTUnwrap(TrendMetric.stepsPerPointWon.rawPair(in: half))

        // Denominators are wins WITHIN the sampled window, so both read the
        // same true cost per point won even though the windows differ in size.
        // Both land near the true 20 steps per point won (10 steps/point at a
        // 50% win rate), approaching it from below because the timeline's
        // baseline entry contributes a zero. Before the fix the half-covered
        // match read 6.3 against the full match's 19.7 — a third of the cost,
        // reported as an improvement.
        XCTAssertEqual(Double(fullPair.numerator) / Double(fullPair.denominator),
                       Double(halfPair.numerator) / Double(halfPair.denominator),
                       accuracy: 1.0,
                       "a shorter sampling window must not look like a fitness gain")
        XCTAssertEqual(halfPair.denominator, half.stepSampledPointsWon)
        XCTAssertNotEqual(halfPair.denominator, half.pointsWon,
                          "the all-match win count is the wrong denominator here")
    }

    /// The fatigue steps pair compared a first set carrying the match-wide
    /// baseline (load 0) against a final set whose opening delta spans the
    /// changeover, so identical movement read as a rise in effort.
    func test_fatigueSteps_readEqualWhenMovementIsIdentical() throws {
        let record = makeRecord(sets: [
            SetSpec(index: 0, points: 30, wins: 18, stepDelta: 4),
            SetSpec(index: 1, points: 30, wins: 12, stepDelta: 4)
        ])
        let split = try XCTUnwrap(MatchTrendSample(record: record)?.fatigue)

        let first = Double(split.firstSet.stepSumLoad) / Double(split.firstSet.stepSampledPoints)
        let final = Double(split.finalSet.stepSumLoad) / Double(split.finalSet.stepSampledPoints)
        XCTAssertEqual(first, 4.0, accuracy: 0.001)
        XCTAssertEqual(final, 4.0, accuracy: 0.001,
                       "the final set's opening delta spans the changeover and must be dropped")
        XCTAssertEqual(first, final, accuracy: 0.001,
                       "identical movement must not plot as a fatigue signal")
    }

    // MARK: - Rally length by serving side

    /// Points with an explicit server / ending-shot / won triple, so a test can
    /// state the exact shape it needs. 24 points clears the 20-point
    /// categorized-eligibility bar.
    private func makeMixedRecord(_ points: [(server: Player, shot: EndingShot?, won: Bool)]) -> MatchRecord {
        let stats = points.enumerated().map { i, p in
            PointStat(
                timestamp: Date(timeIntervalSince1970: Double(i) * 30),
                setIndex: 0,
                server: p.server,
                winner: p.won ? .me : .opponent,
                outcome: .winner,
                endingShot: p.shot
            )
        }
        return MatchRecord(
            startTime: Date(timeIntervalSince1970: 0),
            endTime: Date(timeIntervalSince1970: 3600),
            setScores: [SetScore()], stats: stats, iWon: true
        )
    }

    /// 12 points on my serve (6 rallies, 2 of them won) and 12 on return
    /// (8 rallies, 6 of them won) — the owner's scenario: rallies on my serve
    /// go badly, rallies on their serve go well.
    private func makeServerSplitRecord() -> MatchRecord {
        var points: [(server: Player, shot: EndingShot?, won: Bool)] = []
        // My serve: 6 rally (2 won), 4 ending on the serve, 2 on the return.
        for i in 0..<6 { points.append((.me, .rally, i < 2)) }
        for _ in 0..<4 { points.append((.me, .serve, true)) }
        for _ in 0..<2 { points.append((.me, .return, false)) }
        // Their serve: 8 rally (6 won), 4 ending on the serve.
        for i in 0..<8 { points.append((.opponent, .rally, i < 6)) }
        for _ in 0..<4 { points.append((.opponent, .serve, false)) }
        return makeMixedRecord(points)
    }

    /// The split axis is `PointStat.server`, NOT `EndingShot.serve`. A point
    /// ending on the RETURN shot is still a point I served — reading the side
    /// off the phase is the easiest mistake available here, and it would put
    /// those two points on the wrong side of the comparison.
    func test_rallyDepthBySide_partitionsOnServerNotOnEndingShot() throws {
        let sample = try XCTUnwrap(MatchTrendSample(record: makeServerSplitRecord()))

        // The two `.return`-phase points were served by me, so they belong to
        // the serve side and count toward its denominator.
        XCTAssertEqual(sample.rallyDepthOnServe[.return]?.total, 2)
        XCTAssertNil(sample.rallyDepthOnReturn[.return],
                     "no point on their serve ended on the return shot")
        XCTAssertEqual(sample.pointsWithEndingShotOnServe, 12)
        XCTAssertEqual(sample.pointsWithEndingShotOnReturn, 12)

        // Summing the two sides reproduces the unsplit breakdown exactly.
        for shot in EndingShot.allCases {
            let split = (sample.rallyDepthOnServe[shot]?.total ?? 0)
                + (sample.rallyDepthOnReturn[shot]?.total ?? 0)
            XCTAssertEqual(split, sample.rallyDepth[shot]?.total ?? 0, "\(shot)")
        }
        XCTAssertEqual(sample.pointsWithEndingShotOnServe + sample.pointsWithEndingShotOnReturn,
                       sample.pointsWithEndingShot)
    }

    func test_rallyMetrics_readTheirOwnSide() throws {
        let sample = try XCTUnwrap(MatchTrendSample(record: makeServerSplitRecord()))

        let shareServe = try XCTUnwrap(TrendMetric.rallyShareOnServe.rawPair(in: sample))
        XCTAssertEqual(shareServe.numerator, 6)
        XCTAssertEqual(shareServe.denominator, 12)

        let winServe = try XCTUnwrap(TrendMetric.rallyWinOnServe.rawPair(in: sample))
        XCTAssertEqual(winServe.numerator, 2)
        XCTAssertEqual(winServe.denominator, 6)

        let shareReturn = try XCTUnwrap(TrendMetric.rallyShareOnReturn.rawPair(in: sample))
        XCTAssertEqual(shareReturn.numerator, 8)
        XCTAssertEqual(shareReturn.denominator, 12)

        let winReturn = try XCTUnwrap(TrendMetric.rallyWinOnReturn.rawPair(in: sample))
        XCTAssertEqual(winReturn.numerator, 6)
        XCTAssertEqual(winReturn.denominator, 8)
    }

    /// `PointStat.endingShot` is optional and decoded with `decodeIfPresent`, so
    /// matches archived before it existed carry none. Those must gap, not read
    /// as "you never played a rally".
    func test_rallyMetrics_areNilWithoutEndingShotData() throws {
        let legacy = makeMixedRecord((0..<24).map { i in
            (i.isMultiple(of: 2) ? .me : .opponent, nil, i < 12)
        })
        let sample = try XCTUnwrap(MatchTrendSample(record: legacy))

        XCTAssertEqual(sample.pointsWithEndingShotOnServe, 0)
        for metric: TrendMetric in [.rallyShareOnServe, .rallyShareOnReturn,
                                    .rallyWinOnServe, .rallyWinOnReturn] {
            XCTAssertNil(metric.rawPair(in: sample), "\(metric) invented a rally count")
        }
    }

    /// The share lines carry the context and the win lines carry the verdict, so
    /// only the win lines are on screen before the reader asks for more.
    func test_rallyShareMetrics_startHidden_winRatesDoNot() {
        XCTAssertTrue(TrendMetric.rallyShareOnServe.startsHidden)
        XCTAssertTrue(TrendMetric.rallyShareOnReturn.startsHidden)
        XCTAssertFalse(TrendMetric.rallyWinOnServe.startsHidden)
        XCTAssertFalse(TrendMetric.rallyWinOnReturn.startsHidden)
    }
}
