// MatchComparisonTests.swift — "Compare with previous match": baseline
// selection and the pairwise metric table. MATCH_TAGS_PLAN.md §7.1, §12.1.
import XCTest
@testable import DeuceMateCore

final class MatchComparisonTests: XCTestCase {

    private typealias F = TagFixtures

    private let alex = TagFixtures.player("Alex", id: TagFixtures.uuid(1))
    private let jo = TagFixtures.player("Jo", id: TagFixtures.uuid(2))
    private let sam = TagFixtures.player("Sam", id: TagFixtures.uuid(3))
    private let kim = TagFixtures.player("Kim", id: TagFixtures.uuid(4))

    // MARK: - Baseline selection

    func test_select_sameOpponent_prefersMostRecentEarlierCompletedRematch() {
        let current = F.record(start: 1_000, tags: F.tags(opponents: [alex]))
        let olderRematch = F.record(start: 100, tags: F.tags(opponents: [alex]))
        let recentRematch = F.record(start: 500, tags: F.tags(opponents: [alex]))
        let moreRecentOther = F.record(start: 900, tags: F.tags(opponents: [jo]))
        let laterRematch = F.record(start: 2_000, tags: F.tags(opponents: [alex]))
        let liveRematch = F.record(start: 800, end: nil, iWon: nil, tags: F.tags(opponents: [alex]))

        let selection = PreviousMatchBaseline.select(
            for: current,
            in: [current, olderRematch, recentRematch, moreRecentOther, laterRematch, liveRematch]
        )
        XCTAssertEqual(selection.baseline?.id, recentRematch.id)
        guard case .rematch(_, let matchup) = selection else { return XCTFail("expected rematch") }
        XCTAssertEqual(matchup.opponentIDs, [alex.id])
    }

    func test_select_completeIdentityWithoutRematch_isNoRematch_notAnotherOpponent() {
        let current = F.record(start: 1_000, tags: F.tags(opponents: [alex]))
        let other = F.record(start: 500, tags: F.tags(opponents: [jo]))
        let selection = PreviousMatchBaseline.select(for: current, in: [current, other])
        XCTAssertEqual(selection, .noRematch(Matchup(matchType: .singles, opponentIDs: [alex.id], partnerID: nil)))
        XCTAssertNil(selection.baseline, "never silently label another opponent as a rematch")
        XCTAssertEqual(PreviousMatchBaseline.pickerCandidates(for: current, in: [current, other]).map(\.id),
                       [other.id], "the same-type picker is still offered")
    }

    func test_select_untaggedCurrent_fallsBackToSameTypeOnly() {
        let current = F.record(start: 1_000, tags: nil)
        let doubles = F.record(start: 900, type: .doubles)
        let singles = F.record(start: 400, tags: F.tags(opponents: [jo]))
        XCTAssertEqual(PreviousMatchBaseline.select(for: current, in: [current, doubles, singles]),
                       .sameType(singles))
    }

    func test_select_incompleteDoublesIdentity_fallsBackToSameType() {
        let current = F.record(start: 1_000, type: .doubles, tags: F.tags(opponents: [alex, jo]))   // no partner
        let previous = F.record(start: 500, type: .doubles, tags: F.tags(opponents: [alex, jo], partner: sam))
        XCTAssertEqual(PreviousMatchBaseline.select(for: current, in: [current, previous]), .sameType(previous))
    }

    func test_select_doublesUsesUnorderedPairAndSamePartner() {
        let current = F.record(start: 1_000, type: .doubles, tags: F.tags(opponents: [alex, jo], partner: sam))
        let otherPartner = F.record(start: 900, type: .doubles, tags: F.tags(opponents: [alex, jo], partner: kim))
        let samePairReversed = F.record(start: 600, type: .doubles, tags: F.tags(opponents: [jo, alex], partner: sam))
        XCTAssertEqual(PreviousMatchBaseline.select(for: current, in: [current, otherPartner, samePairReversed])
                        .baseline?.id, samePairReversed.id)
    }

    func test_select_noHistory() {
        let current = F.record(tags: nil)
        XCTAssertEqual(PreviousMatchBaseline.select(for: current, in: [current]), .noHistory)
        XCTAssertEqual(PreviousMatchBaseline.select(for: current, in: []), .noHistory)
    }

    func test_select_excludesCurrentUUID_andBreaksStartTimeTiesByID() {
        let current = F.record(id: F.uuid(50), start: 100, tags: nil)
        let sameStartLowerID = F.record(id: F.uuid(10), start: 100)
        let sameStartHigherID = F.record(id: F.uuid(90), start: 100)
        XCTAssertEqual(
            PreviousMatchBaseline.select(for: current, in: [sameStartHigherID, current, sameStartLowerID]),
            .sameType(sameStartLowerID),
            "only the record ordered before the current one by (start, id) is 'earlier'"
        )
    }

    func test_pickerCandidates_completedByDefault_inProgressOnRequest_newestFirst() {
        let current = F.record(start: 500, tags: nil)
        let older = F.record(start: 100)
        let later = F.record(start: 900)
        let live = F.record(start: 700, end: nil, iWon: nil)
        let doubles = F.record(start: 300, type: .doubles)
        let all = [current, older, later, live, doubles]
        XCTAssertEqual(PreviousMatchBaseline.pickerCandidates(for: current, in: all).map(\.id), [later.id, older.id])
        XCTAssertEqual(PreviousMatchBaseline.pickerCandidates(for: current, in: all, includeInProgress: true).map(\.id),
                       [later.id, live.id, older.id])
    }

    // MARK: - Comparison table

    func test_comparison_usesExistingDenominators_andOrientsDeltas() throws {
        // Current: 10 service points, 8 first serves in (2 second serves), 6
        // first-serve points won; 4 unforced errors from 5 categorized points lost.
        let currentStats =
            F.points(8, won: 6, server: .me, outcome: .winner)
            + F.points(2, won: 2, server: .me, outcome: .winner, secondServe: true)
            + F.points(5, won: 1, server: .opponent, outcome: .unforcedError)
        // Baseline: 10 service points, 5 first serves in.
        let baselineStats =
            F.points(5, won: 5, server: .me, outcome: .winner)
            + F.points(5, won: 2, server: .me, outcome: .winner, secondServe: true)
        let comparison = MatchComparison(
            current: F.record(start: 1_000, stats: currentStats),
            baseline: F.record(start: 0, stats: baselineStats)
        )
        let firstServeIn = try XCTUnwrap(comparison.rows.first { $0.metric == .firstServeIn })
        XCTAssertEqual(firstServeIn.current, TrendMetric.Ratio(numerator: 8, denominator: 10))
        XCTAssertEqual(firstServeIn.baseline, TrendMetric.Ratio(numerator: 5, denominator: 10))
        XCTAssertEqual(try XCTUnwrap(firstServeIn.percentagePointChange), 30, accuracy: 0.0001)
        XCTAssertEqual(firstServeIn.direction, .improving)

        // Unforced errors divide by categorized points LOST (TrendMetric's
        // denominator): current lost 2 to opponent winners + 4 to my UEs.
        let ue = try XCTUnwrap(comparison.rows.first { $0.metric == .unforcedErrors })
        XCTAssertEqual(ue.current, TrendMetric.Ratio(numerator: 4, denominator: 6))
        XCTAssertEqual(ue.baseline, TrendMetric.Ratio(numerator: 0, denominator: 3),
                       "a recorded zero is a real 0%, distinct from 'Not recorded'")
        XCTAssertEqual(ue.direction, .declining, "more unforced errors is worse (lower is better)")
    }

    func test_comparison_missingDataIsNil_neverZero_forScoreOnlyMatch() {
        let scoreOnly = F.record(start: 0, stats: [])
        let tracked = F.record(start: 100, stats: F.points(10, won: 6))
        let comparison = MatchComparison(current: tracked, baseline: scoreOnly)
        XCTAssertFalse(comparison.baseline.hasPointData)
        XCTAssertNil(comparison.baseline.outcomeCoverage)
        for row in comparison.rows {
            XCTAssertNil(row.baseline, "\(row.metric) must be 'Not recorded' on a score-only match")
            XCTAssertNil(row.percentagePointChange)
            XCTAssertNil(row.direction)
        }
        XCTAssertEqual(comparison.baseline.setScoreLabels, ["6–4"], "scores still compare")
        XCTAssertEqual(comparison.baseline.durationSeconds, 3_600, "duration still compares")
    }

    func test_comparison_untrackedOutcomes_hideServeSplitButKeepPointsWon() {
        let untracked = F.points(10, won: 7, server: .me, outcome: .uncategorized)
        let comparison = MatchComparison(current: F.record(stats: untracked), baseline: F.record(stats: untracked))
        XCTAssertFalse(comparison.current.hasOutcomeTracking)
        XCTAssertEqual(comparison.current.outcomeCoverage, 0)
        XCTAssertNil(comparison.rows.first { $0.metric == .firstServeIn }?.current,
                     "isSecondServe on an untracked point is not evidence of a first serve")
        XCTAssertNil(comparison.rows.first { $0.metric == .winners }?.current)
        XCTAssertEqual(comparison.rows.first { $0.metric == .pointsWon }?.current,
                       TrendMetric.Ratio(numerator: 7, denominator: 10))
        XCTAssertEqual(comparison.rows.first { $0.metric == .pointsWon }?.direction, .flat)
    }

    func test_comparison_partialCurrentMatch_hasNoInferredResult() {
        let live = F.record(start: 1_000, end: nil, iWon: nil, stats: F.points(4, won: 3),
                            setScores: [SetScore(gamesMe: 6, gamesOpponent: 3), SetScore()])
        let comparison = MatchComparison(current: live, baseline: F.record(start: 0, iWon: false))
        XCTAssertTrue(comparison.current.isPartial)
        XCTAssertNil(comparison.current.result)
        XCTAssertEqual(comparison.current.setScoreLabels, ["6–3"], "the unstarted set in play is omitted")
        XCTAssertEqual(comparison.baseline.result, .loss)
        XCTAssertFalse(comparison.baseline.isPartial)
    }

    func test_comparison_reportsFormatAndTypeDifferences() {
        let a = F.record(format: .standard)
        let b = F.record(type: .doubles, format: .bestOf3FullFinalSet)
        let comparison = MatchComparison(current: a, baseline: b)
        XCTAssertTrue(comparison.formatsDiffer)
        XCTAssertTrue(comparison.matchTypesDiffer)
        XCTAssertFalse(MatchComparison(current: a, baseline: a).formatsDiffer)
    }

    func test_comparison_doubleFaultFallIsImproving() throws {
        let current = F.points(10, won: 10, server: .me, outcome: .winner)
        let baseline = F.points(8, won: 8, server: .me, outcome: .winner)
            + F.points(2, won: 0, server: .me, outcome: .doubleFault, secondServe: true)
        let row = try XCTUnwrap(MatchComparison(current: F.record(stats: current), baseline: F.record(stats: baseline))
                                    .rows.first { $0.metric == .doubleFaults })
        XCTAssertEqual(row.current, TrendMetric.Ratio(numerator: 0, denominator: 10))
        XCTAssertEqual(row.baseline, TrendMetric.Ratio(numerator: 2, denominator: 10))
        XCTAssertEqual(row.direction, .improving, "a falling double-fault rate is good news")
    }

    func test_comparison_metricsAreRatesFromTheTrendsCatalogue() {
        XCTAssertTrue(MatchComparison.metrics.allSatisfy { $0.unit == .percent })
        XCTAssertTrue(MatchComparison.metrics.contains(.doubleFaults))
        XCTAssertTrue(MatchComparison.metrics.contains(.unforcedErrors))
        XCTAssertTrue(MatchComparison.metrics.contains(.winners))
    }
}
