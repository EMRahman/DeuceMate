// TrendMetricTests.swift — per-metric ratio derivation, the nil-not-zero
// rule (§3.4), and the categorized-denominator fix (§3.6) at the metric
// layer, isolated from MatchRecord/MatchStatsSummary via MatchTrendSample's
// public memberwise init.
import XCTest
@testable import DeuceMateCore

final class TrendMetricTests: XCTestCase {

    // MARK: - Fixture

    /// A fully-specified sample with every counter at a small, deliberately
    /// distinct value so cross-field mixups are easy to catch. Callers
    /// override only the fields their test cares about.
    private func makeSample(
        matchID: UUID = UUID(), startTime: Date = Date(),
        matchType: MatchType = .singles, matchFormat: MatchFormat = .standard,
        recorderWon: Bool? = true, isInProgress: Bool = false,
        totalPoints: Int = 40, categorizedPoints: Int = 40, pointsWon: Int = 22, pointsLost: Int = 18,
        categorizedPointsWon: Int = 22, categorizedPointsLost: Int = 18,
        servicePoints: Int = 20, categorizedServicePoints: Int = 20, categorizedOpponentServicePoints: Int = 20,
        firstServesIn: Int = 14, firstServeWins: Int = 10, secondServePoints: Int = 6, secondServesIn: Int = 4, secondServeWins: Int = 3,
        doubleFaults: Int = 1, returnPointsOnFirst: Int = 12, returnWinsOnFirst: Int = 5,
        returnPointsOnSecond: Int = 8, returnWinsOnSecond: Int = 4, opponentDoubleFaults: Int = 2,
        winnersHit: Int = 9, winnersConceded: Int = 7, unforcedErrorsHit: Int = 6, unforcedErrorsDrawn: Int = 5,
        forcedErrorsConceded: Int = 3, forcedErrorsCaused: Int = 4,
        breakPointOpps: Int = 5, breakPointWins: Int = 2, breakPointsFaced: Int = 4, breakPointsLost: Int = 1,
        bigPointTotal: Int = 9, bigPointWins: Int = 5,
        rallyDepth: [EndingShot: MatchTrendSample.DepthCount] = [
            .serve: .init(total: 10, wins: 6),
            .rally: .init(total: 8, wins: 3)
        ],
        pointsWithEndingShot: Int = 18
    ) -> MatchTrendSample {
        MatchTrendSample(
            matchID: matchID, startTime: startTime, matchType: matchType, matchFormat: matchFormat,
            recorderWon: recorderWon, isInProgress: isInProgress, totalPoints: totalPoints, categorizedPoints: categorizedPoints,
            pointsWon: pointsWon, pointsLost: pointsLost,
            categorizedPointsWon: categorizedPointsWon, categorizedPointsLost: categorizedPointsLost,
            servicePoints: servicePoints, categorizedServicePoints: categorizedServicePoints,
            categorizedOpponentServicePoints: categorizedOpponentServicePoints,
            firstServesIn: firstServesIn, firstServeWins: firstServeWins,
            secondServePoints: secondServePoints, secondServesIn: secondServesIn, secondServeWins: secondServeWins,
            doubleFaults: doubleFaults, returnPointsOnFirst: returnPointsOnFirst, returnWinsOnFirst: returnWinsOnFirst,
            returnPointsOnSecond: returnPointsOnSecond, returnWinsOnSecond: returnWinsOnSecond,
            opponentDoubleFaults: opponentDoubleFaults,
            winnersHit: winnersHit, winnersConceded: winnersConceded,
            unforcedErrorsHit: unforcedErrorsHit, unforcedErrorsDrawn: unforcedErrorsDrawn,
            forcedErrorsConceded: forcedErrorsConceded, forcedErrorsCaused: forcedErrorsCaused,
            breakPointOpps: breakPointOpps, breakPointWins: breakPointWins,
            breakPointsFaced: breakPointsFaced, breakPointsLost: breakPointsLost,
            bigPointTotal: bigPointTotal, bigPointWins: bigPointWins,
            rallyDepth: rallyDepth, pointsWithEndingShot: pointsWithEndingShot
        )
    }

    // MARK: - nil, not zero (§3.4)

    func test_ratio_nilOnEmptyDenominator() {
        let s = makeSample(categorizedServicePoints: 0)
        XCTAssertNil(TrendMetric.doubleFaults.ratio(in: s))
    }

    func test_ratio_nilWhenRallyDepthBucketMissing() {
        let s = makeSample(rallyDepth: [.serve: .init(total: 10, wins: 6)])
        XCTAssertNil(TrendMetric.depthWinReturn.ratio(in: s))
        XCTAssertNotNil(TrendMetric.depthWinServe.ratio(in: s))
    }

    func test_ratio_nilWhenNoEndingShotDataAtAll() {
        let s = makeSample(rallyDepth: [:], pointsWithEndingShot: 0)
        XCTAssertNil(TrendMetric.depthShareServe.ratio(in: s))
        XCTAssertNil(TrendMetric.depthWinServe.ratio(in: s))
    }

    /// wueRatio is nil at zero unforced errors — meaning "no errors", not
    /// "no data" — but rawPair must still report the winners, because
    /// pooling (§3.3) sums rawPair, never ratio.
    func test_wueRatio_nilAtZeroUE_butRawPairReportsWinners() {
        let s = makeSample(winnersHit: 10, unforcedErrorsHit: 0)
        XCTAssertNil(TrendMetric.wueRatio.ratio(in: s))
        let pair = TrendMetric.wueRatio.rawPair(in: s)
        XCTAssertEqual(pair?.numerator, 10)
        XCTAssertEqual(pair?.denominator, 0)
    }

    // MARK: - Categorized denominators (§3.6 regression, at the metric layer)

    /// Two samples share identical CATEGORIZED counters but differ wildly in
    /// their ALL-POINTS totals (simulating a match with tracking toggled off
    /// mid-match, padding pointsWon/pointsLost with untracked points). Every
    /// outcome-mix metric must report the SAME ratio for both — proof the
    /// metric divides by the categorized denominator, not the all-points one.
    func test_outcomeMixMetrics_usesCategorizedDenominator_immuneToUntrackedPadding() {
        let fullyTracked = makeSample(
            totalPoints: 20, categorizedPoints: 20, pointsWon: 12, pointsLost: 8,
            categorizedPointsWon: 12, categorizedPointsLost: 8,
            categorizedServicePoints: 10, categorizedOpponentServicePoints: 10,
            doubleFaults: 2, opponentDoubleFaults: 1,
            winnersHit: 6, winnersConceded: 4, unforcedErrorsHit: 3, unforcedErrorsDrawn: 2,
            forcedErrorsConceded: 1, forcedErrorsCaused: 1
        )
        let heavilyPadded = makeSample(
            // 200 untracked points bloat totalPoints/pointsWon/pointsLost,
            // but the categorized subset — and every numerator — is IDENTICAL.
            totalPoints: 220, categorizedPoints: 20, pointsWon: 112, pointsLost: 108,
            categorizedPointsWon: 12, categorizedPointsLost: 8,
            categorizedServicePoints: 10, categorizedOpponentServicePoints: 10,
            doubleFaults: 2, opponentDoubleFaults: 1,
            winnersHit: 6, winnersConceded: 4, unforcedErrorsHit: 3, unforcedErrorsDrawn: 2,
            forcedErrorsConceded: 1, forcedErrorsCaused: 1
        )
        let outcomeMixMetrics: [TrendMetric] = [
            .doubleFaults, .doubleFaultsConceded, .unforcedErrors, .unforcedErrorsDrawn,
            .forcedErrorsConceded, .forcedErrorsCaused, .winners, .winnersConceded, .ownErrorShare
        ]
        for metric in outcomeMixMetrics {
            let a = metric.ratio(in: fullyTracked)
            let b = metric.ratio(in: heavilyPadded)
            XCTAssertEqual(a?.value ?? -1, b?.value ?? -2, accuracy: 0.0001,
                "\(metric) diverged between identical-categorized samples — it is reading an all-points field")
        }
    }

    // MARK: - Catalogue integrity

    func test_everyMetric_hasNonEmptyLabelsAndAGroup() {
        for metric in TrendMetric.allCases {
            XCTAssertFalse(metric.displayLabel.isEmpty, "\(metric)")
            XCTAssertFalse(metric.denominatorLabel.isEmpty, "\(metric)")
            XCTAssertTrue(TrendMetric.metrics(in: metric.group).contains(metric), "\(metric)")
        }
    }

    func test_rallyDepthShareMetrics_areNeutral() {
        for metric: TrendMetric in [.depthShareServe, .depthShareReturn, .depthShareServePlusOne, .depthShareRally] {
            XCTAssertEqual(metric.betterDirection, .neutral, "\(metric)")
        }
    }

    func test_rallyDepthWinMetrics_areHigherIsBetter() {
        for metric: TrendMetric in [.depthWinServe, .depthWinReturn, .depthWinServePlusOne, .depthWinRally] {
            XCTAssertEqual(metric.betterDirection, .higher, "\(metric)")
        }
    }

    func test_supportsCountMode_falseExactlyForMetricsWithNoMeaningfulCount() {
        let expectedFalse: Set<TrendMetric> = [
            .wueRatio, .aggressionIndex, .ownErrorShare,
            .depthShareServe, .depthShareReturn, .depthShareServePlusOne, .depthShareRally,
            // A rally SHARE is a style, not a count anyone wants plotted raw —
            // on either side of the serve.
            .servedShareServe, .servedShareReturn, .servedShareServePlusOne, .servedShareRally,
            .returnedShareServe, .returnedShareReturn, .returnedShareServePlusOne, .returnedShareRally
        ]
        for metric in TrendMetric.allCases {
            XCTAssertEqual(metric.supportsCountMode, !expectedFalse.contains(metric), "\(metric)")
        }
    }

    /// Pins every non-percent metric to its unit. `TrendChart` buckets its
    /// series by `unit` and gives each bucket its own Y axis, so a metric
    /// silently landing in the wrong bucket is a chart that plots bpm against a
    /// percentage scale — visible only to someone who happens to look.
    func test_everyMetric_hasItsExpectedUnit() {
        let nonPercent: [TrendMetric: TrendMetric.Unit] = [
            .wueRatio: .ratio,
            .stepsPerPointFirstSet: .steps,
            .stepsPerPointFinalSet: .steps
        ]
        for metric in TrendMetric.allCases {
            XCTAssertEqual(metric.unit, nonPercent[metric] ?? .percent, "\(metric)")
        }
    }

    /// A `switch` exhaustiveness canary: adding a `Unit` case without giving it
    /// a flat-change threshold would otherwise fail to compile here rather than
    /// silently defaulting, but this also pins the values themselves.
    func test_minimumChange_isDefinedForEveryUnit() {
        for unit: TrendMetric.Unit in [.percent, .ratio, .steps] {
            XCTAssertGreaterThan(PerformanceTrends.minimumChange(for: unit), 0, "\(unit)")
        }
    }

    func test_headline_isDoubleFaultsUnforcedErrorsWinnersWUE() {
        XCTAssertEqual(TrendMetric.headline, [.doubleFaults, .unforcedErrors, .winners, .wueRatio])
    }
}
