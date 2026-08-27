// MatchTrendSampleHealthTests.swift — the heart-rate, movement and fatigue
// counters, and the five traps docs/features/HEALTH_TRENDS_PLAN.md §2 names.
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
        /// bpm stamped on this set's points, or nil for no HR at all.
        var bpm: Int?
        /// How many of the set's points carry `bpm`. nil == all of them.
        var bpmOnFirst: Int?
        /// Steps accumulated per point, or nil for no step sampling.
        var stepDelta: Int?
        /// How many of the set's points carry a step sample. nil == all.
        var stepsOnFirst: Int?

        init(index: Int, points: Int, wins: Int, bpm: Int? = nil,
             bpmOnFirst: Int? = nil, stepDelta: Int? = nil, stepsOnFirst: Int? = nil) {
            self.index = index
            self.points = points
            self.wins = wins
            self.bpm = bpm
            self.bpmOnFirst = bpmOnFirst
            self.stepDelta = stepDelta
            self.stepsOnFirst = stepsOnFirst
        }
    }

    /// Builds a categorized match from set specs. Timestamps increase across
    /// the whole match so `hrTimeline` / `stepsTimeline` order matches play
    /// order, and step cumulatives run continuously across sets the way a real
    /// workout's do.
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
                let carriesBPM = spec.bpm != nil && i < (spec.bpmOnFirst ?? spec.points)
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
                    heartRateBPM: carriesBPM ? spec.bpm : nil,
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
            sets: [SetSpec(index: 0, points: 30, wins: 18, bpm: 150, stepDelta: 4)],
            totalDistanceMeters: 900.4,
            matchElapsedSeconds: 3600
        )
        let sample = try XCTUnwrap(MatchTrendSample(record: record))

        XCTAssertEqual(sample.hrSampledPoints, 30)
        XCTAssertEqual(sample.hrSumBPM, 30 * 150)
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
        XCTAssertEqual(sample.distanceMetres, 900)
        XCTAssertEqual(sample.elapsedMinutes, 60)
    }

    // MARK: - Trap 2: never the totalSteps linear fallback

    func test_stepMetrics_areNilWhenOnlyAWholeMatchTotalExists() throws {
        // A legacy match: a workout step total, but no per-point samples.
        // StepsSeries would spread the total evenly and produce a perfectly
        // flat steps-per-point of totalSteps/n — a number that measures
        // nothing. Trends must decline to plot it.
        let record = makeRecord(
            sets: [SetSpec(index: 0, points: 30, wins: 18, bpm: 150)],
            totalSteps: 5000
        )
        let sample = try XCTUnwrap(MatchTrendSample(record: record))

        XCTAssertEqual(sample.stepSampledPoints, 0)
        XCTAssertEqual(sample.stepSumLoad, 0)
        XCTAssertNil(TrendMetric.stepsPerPoint.rawPair(in: sample))
        XCTAssertNil(TrendMetric.stepsPerPointWon.rawPair(in: sample))
        // HR is unaffected — the two families gate independently.
        XCTAssertNotNil(TrendMetric.avgHeartRate.rawPair(in: sample))
    }

    // MARK: - Trap 1: nil is never zero

    func test_healthFreeMatch_isStillEligibleAndSimplyHasNoHealthDots() throws {
        let record = makeRecord(sets: [SetSpec(index: 0, points: 30, wins: 18)])
        let sample = try XCTUnwrap(MatchTrendSample(record: record),
                                   "a match without Health data must still be a valid sample")

        // Tennis metrics are untouched.
        XCTAssertNotNil(TrendMetric.pointsWon.rawPair(in: sample))
        // Every health metric declines to produce a pair.
        for metric: TrendMetric in [.avgHeartRate, .hardZoneShare, .hardZoneWinRate,
                                    .stepsPerPoint, .stepsPerPointWon, .metresPerPoint] {
            XCTAssertNil(metric.rawPair(in: sample), "\(metric) invented data from nothing")
        }
    }

    func test_pooling_skipsHealthFreeMatchesRatherThanCountingThemAsZero() throws {
        let withHR = try XCTUnwrap(MatchTrendSample(record: makeRecord(
            sets: [SetSpec(index: 0, points: 30, wins: 18, bpm: 150)],
            matchElapsedSeconds: 3600)))
        let withoutHR = try XCTUnwrap(MatchTrendSample(record: makeRecord(
            sets: [SetSpec(index: 0, points: 30, wins: 18)],
            matchElapsedSeconds: 3600)))

        let series = try XCTUnwrap(
            PerformanceTrends.series(for: .avgHeartRate, in: [withoutHR, withHR]))
        // One plottable dot, and the pooled figure is the HR match's own
        // average — not halved by a phantom 0 bpm match.
        XCTAssertEqual(series.points.count, 1)
        XCTAssertEqual(series.pooled?.value ?? 0, 150, accuracy: 0.001)
    }

    // MARK: - The fatigue set-pair rule

    func test_fatigue_comparesTheFirstAndLastPlayedSet_notAdjacentOnes() throws {
        let record = makeRecord(sets: [
            SetSpec(index: 0, points: 30, wins: 21, bpm: 140, stepDelta: 4),
            SetSpec(index: 1, points: 26, wins: 13, bpm: 150, stepDelta: 5),
            SetSpec(index: 2, points: 28, wins: 11, bpm: 160, stepDelta: 6)
        ])
        let split = try XCTUnwrap(MatchTrendSample(record: record)?.fatigue)

        XCTAssertEqual(split.firstSet.setIndex, 0)
        XCTAssertEqual(split.finalSet.setIndex, 2)
        XCTAssertEqual(split.firstSet.points, 30)
        XCTAssertEqual(split.firstSet.pointsWon, 21)
        XCTAssertEqual(split.finalSet.points, 28)
        XCTAssertEqual(split.finalSet.pointsWon, 11)
        XCTAssertEqual(split.finalSet.hrSumBPM, 28 * 160)
    }

    func test_fatigue_isNilWhenEitherSetIsTooShort() throws {
        // A super-tiebreak decider is a "set" by index but not by workload.
        let record = makeRecord(sets: [
            SetSpec(index: 0, points: 30, wins: 18, bpm: 150, stepDelta: 4),
            SetSpec(index: 1, points: 15, wins: 6, bpm: 160, stepDelta: 5)
        ])
        XCTAssertNil(MatchTrendSample(record: record)?.fatigue)
    }

    func test_fatigue_isNilForASingleSetMatch() throws {
        let record = makeRecord(sets: [SetSpec(index: 0, points: 30, wins: 18, bpm: 150, stepDelta: 4)])
        XCTAssertNil(MatchTrendSample(record: record)?.fatigue)
    }

    func test_fatigue_isNilForAnInProgressMatch_butTheOtherCountersSurvive() throws {
        let record = makeRecord(sets: [
            SetSpec(index: 0, points: 30, wins: 18, bpm: 150, stepDelta: 4),
            SetSpec(index: 1, points: 24, wins: 10, bpm: 160, stepDelta: 5)
        ], inProgress: true)
        let sample = try XCTUnwrap(MatchTrendSample(record: record))

        XCTAssertTrue(sample.isInProgress)
        XCTAssertNil(sample.fatigue, "a set still being played is a partial reading")
        // The live match still contributes to every non-fatigue health metric.
        XCTAssertNotNil(TrendMetric.avgHeartRate.rawPair(in: sample))
        XCTAssertNotNil(TrendMetric.stepsPerPoint.rawPair(in: sample))
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
        // HR sampling only started in the second set — a real pattern when the
        // watch's HR stream drops out early on. The win-rate pair is unaffected.
        let record = makeRecord(sets: [
            SetSpec(index: 0, points: 30, wins: 21),
            SetSpec(index: 1, points: 26, wins: 10, bpm: 160)
        ])
        let sample = try XCTUnwrap(MatchTrendSample(record: record))

        XCTAssertNotNil(sample.fatigue)
        XCTAssertNil(TrendMetric.avgHeartRateFirstSet.rawPair(in: sample))
        XCTAssertNil(TrendMetric.avgHeartRateFinalSet.rawPair(in: sample),
                     "the covered half must not be plotted without its partner")
        XCTAssertNotNil(TrendMetric.winRateFirstSet.rawPair(in: sample))
        XCTAssertNotNil(TrendMetric.winRateFinalSet.rawPair(in: sample))
    }

    // MARK: - Trap 5: zones follow the supplied yardstick

    func test_hardZoneCounters_followTheSuppliedMaxHR() throws {
        let record = makeRecord(sets: [SetSpec(index: 0, points: 30, wins: 18, bpm: 150)])

        // 150/190 = 79% — Z3, below the hard zones.
        let untrained = try XCTUnwrap(MatchTrendSample(record: record, maxHR: 190))
        XCTAssertEqual(untrained.hardZonePoints, 0)
        XCTAssertNil(TrendMetric.hardZoneWinRate.rawPair(in: untrained))
        XCTAssertEqual(TrendMetric.hardZoneShare.rawPair(in: untrained)?.numerator, 0)

        // 150/175 = 86% — Z4. Same match, different resolved max HR.
        let older = try XCTUnwrap(MatchTrendSample(record: record, maxHR: 175))
        XCTAssertEqual(older.hardZonePoints, 30)
        XCTAssertEqual(older.hardZoneWins, 18)
        XCTAssertEqual(TrendMetric.hardZoneShare.rawPair(in: older)?.numerator, 30)

        // The bpm average is yardstick-free and must NOT move.
        XCTAssertEqual(untrained.hrSumBPM, older.hrSumBPM)
    }

    // MARK: - Coverage gates

    func test_hrMetrics_gateAtTenSamples() throws {
        let thin = makeRecord(sets: [SetSpec(index: 0, points: 30, wins: 18, bpm: 150, bpmOnFirst: 9)])
        let thinSample = try XCTUnwrap(MatchTrendSample(record: thin))
        XCTAssertEqual(thinSample.hrSampledPoints, 9)
        XCTAssertNil(TrendMetric.avgHeartRate.rawPair(in: thinSample))

        let enough = makeRecord(sets: [SetSpec(index: 0, points: 30, wins: 18, bpm: 150, bpmOnFirst: 10)])
        let enoughSample = try XCTUnwrap(MatchTrendSample(record: enough))
        XCTAssertEqual(enoughSample.hrSampledPoints, 10)
        XCTAssertNotNil(TrendMetric.avgHeartRate.rawPair(in: enoughSample))
    }

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

    /// `hardZoneWinRate` gated only on hard-zone points, so it drew a dot from
    /// a sample its two sibling metrics — and the screen's coverage footer —
    /// both considered too thin to exist.
    func test_hardZoneWinRate_requiresTheSameHRCoverageAsItsSiblings() throws {
        // 6 readings at 180 bpm: Z5 at maxHR 190, but below minimumHRSamples.
        let record = makeRecord(sets: [SetSpec(index: 0, points: 40, wins: 20, bpm: 180, bpmOnFirst: 6)])
        let sample = try XCTUnwrap(MatchTrendSample(record: record, maxHR: 190))

        XCTAssertEqual(sample.hardZonePoints, 6, "the readings are in Z5")
        XCTAssertNil(TrendMetric.avgHeartRate.rawPair(in: sample))
        XCTAssertNil(TrendMetric.hardZoneShare.rawPair(in: sample))
        XCTAssertNil(TrendMetric.hardZoneWinRate.rawPair(in: sample),
                     "must not plot under a footer that says there is no HR data")
    }

    /// `minutesPerMatch` is the only metric whose numerator is a whole-match
    /// absolute, so a still-growing duration can't be plotted beside finished
    /// matches — and a sub-minute duration must be absent, not zero.
    func test_minutesPerMatch_isNilForInProgressAndSubMinuteMatches() throws {
        let live = makeRecord(sets: [SetSpec(index: 0, points: 30, wins: 18)],
                              inProgress: true, matchElapsedSeconds: 480)
        let liveSample = try XCTUnwrap(MatchTrendSample(record: live))
        XCTAssertNil(liveSample.elapsedMinutes)
        XCTAssertNil(TrendMetric.minutesPerMatch.rawPair(in: liveSample),
                     "8 minutes so far is not a match length")

        let brief = makeRecord(sets: [SetSpec(index: 0, points: 30, wins: 18)],
                               matchElapsedSeconds: 45)
        let briefSample = try XCTUnwrap(MatchTrendSample(record: brief))
        XCTAssertNil(briefSample.elapsedMinutes, "truncating 45s to 0 minutes must yield nil, not 0")
        XCTAssertNil(TrendMetric.minutesPerMatch.rawPair(in: briefSample))

        let normal = makeRecord(sets: [SetSpec(index: 0, points: 30, wins: 18)],
                                matchElapsedSeconds: 3600)
        XCTAssertEqual(try XCTUnwrap(MatchTrendSample(record: normal)).elapsedMinutes, 60)
    }
}
