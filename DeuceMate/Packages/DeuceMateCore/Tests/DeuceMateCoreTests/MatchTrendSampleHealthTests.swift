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
    /// Defaults to `.bestOf3FullFinalSet` so a third set in these fixtures is a
    /// TRUE third set. `.standard` — the app's default — plays its decider as a
    /// super-tiebreak, which is a different series; the tests that care pass it
    /// explicitly.
    private func makeRecord(
        sets: [SetSpec],
        inProgress: Bool = false,
        totalSteps: Int? = nil,
        totalDistanceMeters: Double? = nil,
        matchElapsedSeconds: TimeInterval = 3600,
        matchFormat: MatchFormat = .bestOf3FullFinalSet
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

    /// Each set slice carries TWO denominators that must not be conflated: the
    /// win rate counts every point in the set, while the step figures count only
    /// the sampled ones — one fewer than sampled, since the set's opening delta
    /// is dropped as non-comparable. Pairing the wrong two is the
    /// mixed-denominator mistake in miniature.
    func test_setSliceCounters_countAllPointsAndSampledStepsSeparately() throws {
        let record = makeRecord(sets: [
            SetSpec(index: 0, points: 30, wins: 18, stepDelta: 4),
            SetSpec(index: 1, points: 30, wins: 12, stepDelta: 4)
        ])
        let slices = try XCTUnwrap(MatchTrendSample(record: record)).setSlices

        XCTAssertEqual(slices.map(\.setIndex), [0, 1])
        XCTAssertEqual(slices[0].points, 30)
        XCTAssertEqual(slices[0].pointsWon, 18)
        XCTAssertEqual(slices[1].points, 30)
        XCTAssertEqual(slices[1].pointsWon, 12)

        // 30 samples each, less each set's own opening delta.
        XCTAssertEqual(slices[0].stepSampledPoints, 29)
        XCTAssertEqual(slices[1].stepSampledPoints, 29)
        XCTAssertEqual(slices[0].stepSumLoad, 4 * 29)
        XCTAssertEqual(slices[1].stepSumLoad, 4 * 29)
        XCTAssertNotEqual(slices[0].points, slices[0].stepSampledPoints,
                          "the two families must not share a denominator")
    }

    // MARK: - Trap 1: nil is never zero

    func test_healthFreeMatch_isStillEligibleAndSimplyHasNoHealthDots() throws {
        let record = makeRecord(sets: [SetSpec(index: 0, points: 30, wins: 18)])
        let sample = try XCTUnwrap(MatchTrendSample(record: record),
                                   "a match without Health data must still be a valid sample")

        // Tennis metrics are untouched.
        XCTAssertNotNil(TrendMetric.pointsWon.rawPair(in: sample))
        // Every movement metric declines to produce a pair.
        for metric: TrendMetric in [.stepsPerPointSet1, .stepsPerPointSet2] {
            XCTAssertNil(metric.rawPair(in: sample), "\(metric) invented data from nothing")
        }
    }

    func test_pooling_skipsUncoveredMatchesRatherThanCountingThemAsZero() throws {
        let covered = try XCTUnwrap(MatchTrendSample(record: makeServerSplitRecord()))
        // Same shape, but archived before `PointStat.endingShot` existed.
        let legacy = try XCTUnwrap(MatchTrendSample(record: makeMixedRecord(
            (0..<24).map { i in (i.isMultiple(of: 2) ? .me : .opponent, nil, i < 12) })))

        let series = try XCTUnwrap(
            PerformanceTrends.series(for: .servedShareRally, in: [legacy, covered]))
        // One plottable dot, and the pooled figure is the covered match's own
        // share — not halved by a phantom zero-rally match.
        XCTAssertEqual(series.points.count, 1)
        XCTAssertEqual(series.pooled?.numerator, 6)
        XCTAssertEqual(series.pooled?.denominator, 12)
    }

    // MARK: - The fatigue set-pair rule

    /// Every played set gets its own series — the middle set is no longer
    /// collapsed away into a first-vs-last comparison.
    func test_everyPlayedSet_getsItsOwnSeries() throws {
        let record = makeRecord(sets: [
            SetSpec(index: 0, points: 30, wins: 21, stepDelta: 4),
            SetSpec(index: 1, points: 26, wins: 13, stepDelta: 5),
            SetSpec(index: 2, points: 28, wins: 11, stepDelta: 6)
        ])
        let sample = try XCTUnwrap(MatchTrendSample(record: record))

        XCTAssertEqual(sample.setSlices.map(\.setIndex), [0, 1, 2])
        XCTAssertEqual(TrendMetric.winRateSet1.rawPair(in: sample)?.numerator, 21)
        XCTAssertEqual(TrendMetric.winRateSet2.rawPair(in: sample)?.numerator, 13)
        XCTAssertEqual(TrendMetric.winRateSet3.rawPair(in: sample)?.numerator, 11)
        XCTAssertEqual(TrendMetric.winRateSet3.rawPair(in: sample)?.denominator, 28)
        // A full third set is not a super-tiebreak, so that series stays empty.
        XCTAssertNil(TrendMetric.winRateDecidingTiebreak.rawPair(in: sample))
        XCTAssertEqual(sample.setSlices[2].stepSampledPoints, 27, "the set's opening delta is dropped")
    }

    /// `.standard` — the app's DEFAULT format — plays its third set as a
    /// 10-point super-tiebreak. Averaging that in with true third sets would
    /// compare a dozen-odd points against sixty, so it plots as its own series
    /// (and, in the chart, its own colour).
    func test_decidingSuperTiebreak_plotsSeparatelyFromATrueThirdSet() throws {
        let superTB = makeRecord(sets: [
            SetSpec(index: 0, points: 30, wins: 18),
            SetSpec(index: 1, points: 28, wins: 12),
            SetSpec(index: 2, points: 14, wins: 6)      // a 10-point tiebreak
        ], matchFormat: .standard)
        let sample = try XCTUnwrap(MatchTrendSample(record: superTB))

        XCTAssertTrue(try XCTUnwrap(sample.decidingTiebreakSlice).isDecidingTiebreak)
        XCTAssertEqual(sample.decidingTiebreakSlice?.setIndex, 2)
        XCTAssertNil(sample.fullSetSlice(2), "a super-tiebreak must not also count as Set 3")
        XCTAssertNil(TrendMetric.winRateSet3.rawPair(in: sample))
        XCTAssertEqual(TrendMetric.winRateDecidingTiebreak.rawPair(in: sample)?.numerator, 6)
        XCTAssertEqual(TrendMetric.winRateDecidingTiebreak.rawPair(in: sample)?.denominator, 14)

        // The two earlier sets are ordinary full sets in both formats.
        XCTAssertNotNil(TrendMetric.winRateSet1.rawPair(in: sample))
        XCTAssertNotNil(TrendMetric.winRateSet2.rawPair(in: sample))
    }

    /// A straight-sets win never reaches the decider. `.standard`'s
    /// `finalSetStyle` says the decider WOULD be a super-tiebreak, but a match
    /// that ends 6-4 6-3 stops at set index 1, and that set is an ordinary
    /// second set. Classifying it by "is this the last set played" mislabels
    /// every straight-sets match: Set 2 vanishes and the Super TB series fills
    /// up with regular second sets.
    func test_straightSetsWin_hasNoDecidingTiebreak() throws {
        let record = makeRecord(sets: [
            SetSpec(index: 0, points: 30, wins: 18),
            SetSpec(index: 1, points: 28, wins: 17)
        ], matchFormat: .standard)
        let sample = try XCTUnwrap(MatchTrendSample(record: record))

        XCTAssertNil(sample.decidingTiebreakSlice, "the match never reached a decider")
        XCTAssertNotNil(sample.fullSetSlice(1), "set 2 is an ordinary set here")
        XCTAssertEqual(TrendMetric.winRateSet2.rawPair(in: sample)?.numerator, 17)
        XCTAssertEqual(TrendMetric.winRateSet2.rawPair(in: sample)?.denominator, 28)
        XCTAssertNil(TrendMetric.winRateDecidingTiebreak.rawPair(in: sample))
    }

    /// A super-tiebreak is a complete set at ~12 points, so holding it to the
    /// 20-point full-set bar would silently drop the decider from every
    /// `.standard` three-setter.
    func test_tiebreakDecider_isGatedAtItsOwnMinimum() throws {
        func decider(points: Int) throws -> TrendMetric.Ratio? {
            let record = makeRecord(sets: [
                SetSpec(index: 0, points: 30, wins: 18),
                SetSpec(index: 1, points: 28, wins: 12),
                SetSpec(index: 2, points: points, wins: points / 2)
            ], matchFormat: .standard)
            return TrendMetric.winRateDecidingTiebreak.ratio(in: try XCTUnwrap(MatchTrendSample(record: record)))
        }
        XCTAssertNil(try decider(points: 9), "below the tiebreak minimum")
        XCTAssertNotNil(try decider(points: 10), "a 10-point tiebreak is a complete set")
        // And a full set is still held to the higher bar.
        let shortFullSet = makeRecord(sets: [
            SetSpec(index: 0, points: 30, wins: 18),
            SetSpec(index: 1, points: 19, wins: 9)
        ])
        XCTAssertNil(TrendMetric.winRateSet2.rawPair(in: try XCTUnwrap(MatchTrendSample(record: shortFullSet))))
    }

    func test_setSlices_areEmptyForASingleSetMatch() throws {
        let record = makeRecord(sets: [SetSpec(index: 0, points: 30, wins: 18, stepDelta: 4)])
        XCTAssertEqual(MatchTrendSample(record: record)?.setSlices, [],
                       "one set has nothing to compare across")
    }

    /// Only the set actually in play is a partial reading. A live match's
    /// EARLIER sets are finished and are as good as any completed match's, so
    /// dropping the whole match made the screen's "Include In-Progress Matches"
    /// toggle a lie for this group alone — it plotted nothing at all.
    func test_inProgressMatch_keepsCompletedSets_andDropsOnlyTheSetInPlay() throws {
        let record = makeRecord(sets: [
            SetSpec(index: 0, points: 30, wins: 18, stepDelta: 4),
            SetSpec(index: 1, points: 28, wins: 12, stepDelta: 5),
            SetSpec(index: 2, points: 9, wins: 5, stepDelta: 6)   // still being played
        ], inProgress: true)
        let sample = try XCTUnwrap(MatchTrendSample(record: record))

        XCTAssertTrue(sample.isInProgress)
        XCTAssertEqual(sample.setSlices.map(\.setIndex), [0, 1])
        XCTAssertEqual(TrendMetric.winRateSet1.rawPair(in: sample)?.numerator, 18)
        XCTAssertEqual(TrendMetric.winRateSet2.rawPair(in: sample)?.numerator, 12)
        XCTAssertNil(TrendMetric.winRateSet3.rawPair(in: sample),
                     "the set in play would drift point by point")
        // The live match still contributes to every non-fatigue metric.
        XCTAssertNotNil(TrendMetric.pointsWon.rawPair(in: sample))
    }

    /// A live match still in its second set has exactly one finished set, which
    /// is nothing to compare across — the same bar a completed one-set match
    /// fails.
    func test_inProgressMatch_inItsSecondSet_hasNothingToCompare() throws {
        let record = makeRecord(sets: [
            SetSpec(index: 0, points: 30, wins: 18),
            SetSpec(index: 1, points: 12, wins: 7)               // still being played
        ], inProgress: true)
        XCTAssertEqual(MatchTrendSample(record: record)?.setSlices, [])
    }

    /// The decider only exists once the match reaches it, so a live match's
    /// last FINISHED set is never classified as one.
    func test_inProgressMatch_neverClassifiesAFinishedSetAsTheDecider() throws {
        let record = makeRecord(sets: [
            SetSpec(index: 0, points: 30, wins: 18),
            SetSpec(index: 1, points: 28, wins: 12),
            SetSpec(index: 2, points: 6, wins: 3)                // super-tiebreak in play
        ], inProgress: true, matchFormat: .standard)
        let sample = try XCTUnwrap(MatchTrendSample(record: record))

        XCTAssertNil(sample.decidingTiebreakSlice)
        XCTAssertNotNil(sample.fullSetSlice(1), "set 2 stays an ordinary set")
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

        XCTAssertEqual(sample.setSlices.count, 2)
        // Each set gates on its OWN sampling now that every set is its own named
        // series: an uncovered set leaves a visible gap in the Set 1 line rather
        // than suppressing Set 2's real reading. (The old first-vs-final pair
        // suppressed both, because half of a two-line comparison reads as the
        // whole answer — with named per-set lines it does not.)
        XCTAssertNil(TrendMetric.stepsPerPointSet1.rawPair(in: sample))
        XCTAssertNotNil(TrendMetric.stepsPerPointSet2.rawPair(in: sample))
        // Win rate counts every point, so it is unaffected by step sampling.
        XCTAssertNotNil(TrendMetric.winRateSet1.rawPair(in: sample))
        XCTAssertNotNil(TrendMetric.winRateSet2.rawPair(in: sample))
    }

    /// The step slices once compared an opening set carrying the match-wide
    /// baseline (load 0) against a later set whose opening delta spans the
    /// changeover, so identical movement read as a rise in effort.
    func test_fatigueSteps_readEqualWhenMovementIsIdentical() throws {
        let record = makeRecord(sets: [
            SetSpec(index: 0, points: 30, wins: 18, stepDelta: 4),
            SetSpec(index: 1, points: 30, wins: 12, stepDelta: 4)
        ])
        let slices = try XCTUnwrap(MatchTrendSample(record: record)).setSlices

        let first = Double(slices[0].stepSumLoad) / Double(slices[0].stepSampledPoints)
        let final = Double(slices[1].stepSumLoad) / Double(slices[1].stepSampledPoints)
        XCTAssertEqual(first, 4.0, accuracy: 0.001)
        XCTAssertEqual(final, 4.0, accuracy: 0.001,
                       "the later set's opening delta spans the changeover and must be dropped")
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

    /// Each side's four shares are taken against that side's own denominator,
    /// and each side's four sum to its whole — that is what makes the stacked
    /// mix chart add up to 100% rather than to some fraction of the match.
    func test_perSideMix_usesItsOwnDenominatorAndSumsToTheWhole() throws {
        let sample = try XCTUnwrap(MatchTrendSample(record: makeServerSplitRecord()))

        // On my serve: 6 rally, 4 ending on the serve, 2 on the return, of 12.
        XCTAssertEqual(TrendMetric.servedShareRally.rawPair(in: sample)?.numerator, 6)
        XCTAssertEqual(TrendMetric.servedShareServe.rawPair(in: sample)?.numerator, 4)
        XCTAssertEqual(TrendMetric.servedShareReturn.rawPair(in: sample)?.numerator, 2)
        XCTAssertEqual(TrendMetric.servedShareServePlusOne.rawPair(in: sample)?.numerator, 0)

        // On return: 8 rally, 4 ending on their serve, of 12.
        XCTAssertEqual(TrendMetric.returnedShareRally.rawPair(in: sample)?.numerator, 8)
        XCTAssertEqual(TrendMetric.returnedShareServe.rawPair(in: sample)?.numerator, 4)

        for side: [TrendMetric] in [[.servedShareServe, .servedShareReturn,
                                     .servedShareServePlusOne, .servedShareRally],
                                    [.returnedShareServe, .returnedShareReturn,
                                     .returnedShareServePlusOne, .returnedShareRally]] {
            let pairs = side.compactMap { $0.rawPair(in: sample) }
            XCTAssertEqual(pairs.count, 4)
            XCTAssertEqual(pairs.reduce(0) { $0 + $1.numerator }, 12, "the side's shares must sum to its own total")
            XCTAssertTrue(pairs.allSatisfy { $0.denominator == 12 })
        }
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
        for metric in TrendMetric.metrics(in: .rallyDepthByService) {
            XCTAssertNil(metric.rawPair(in: sample), "\(metric) invented a rally count")
        }
    }
}
