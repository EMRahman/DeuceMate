// MatchTrendSampleTests.swift — eligibility, field mapping, and the
// recorder-framed renaming that PERFORMANCE_TRENDS_PLAN.md §10 flags as the
// highest-risk line in the whole feature.
import XCTest
@testable import DeuceMateCore

final class MatchTrendSampleTests: XCTestCase {

    // MARK: - Fixtures

    /// 20 categorized points, evenly mixed, so every counter this test
    /// touches is non-trivial: focal serves half, wins half, hits some
    /// winners/UE/DF, is forced into an error, forces one, and has one
    /// break point each way plus one big (tiebreak) point.
    private func makeEligiblePoints() -> [PointStat] {
        var points: [PointStat] = []
        // Focal serves 10 points: 6 first-serve winners, 2 second-serve
        // points (1 win, 1 double fault), 2 unforced errors.
        points.append(PointStat(setIndex: 0, server: .me, winner: .me, outcome: .winner, isSecondServe: false, endingShot: .serve))
        points.append(PointStat(setIndex: 0, server: .me, winner: .me, outcome: .winner, isSecondServe: false, endingShot: .serve))
        points.append(PointStat(setIndex: 0, server: .me, winner: .me, outcome: .winner, isSecondServe: false, endingShot: .serve))
        points.append(PointStat(setIndex: 0, server: .me, winner: .opponent, outcome: .unforcedError, isSecondServe: false, endingShot: .rally))
        points.append(PointStat(setIndex: 0, server: .me, winner: .opponent, outcome: .unforcedError, isSecondServe: false, endingShot: .rally))
        points.append(PointStat(setIndex: 0, server: .me, winner: .me, outcome: .winner, isSecondServe: false, endingShot: .serve))
        points.append(PointStat(setIndex: 0, server: .me, winner: .me, outcome: .winner, isSecondServe: false, endingShot: .serve))
        // Break point — focal serves, loses it.
        points.append(PointStat(setIndex: 0, server: .me, winner: .opponent, outcome: .winner, isSecondServe: false, isBreakPoint: true, endingShot: .rally))
        points.append(PointStat(setIndex: 0, server: .me, winner: .me, outcome: .winner, isSecondServe: true, endingShot: .servePlusOne))
        points.append(PointStat(setIndex: 0, server: .me, winner: .opponent, outcome: .doubleFault, isSecondServe: true, endingShot: .serve))
        // Opponent serves 10 points: focal returns and wins 4, loses 4 to
        // opponent winners, opponent double-faults once (focal wins it),
        // opponent is forced into an error once (focal wins it), plus one
        // break point (focal as returner, wins it) and one tiebreak point.
        points.append(PointStat(setIndex: 0, server: .opponent, winner: .me, outcome: .winner, isSecondServe: false, endingShot: .return))
        points.append(PointStat(setIndex: 0, server: .opponent, winner: .me, outcome: .winner, isSecondServe: false, endingShot: .return))
        points.append(PointStat(setIndex: 0, server: .opponent, winner: .opponent, outcome: .winner, isSecondServe: false, endingShot: .serve))
        points.append(PointStat(setIndex: 0, server: .opponent, winner: .opponent, outcome: .winner, isSecondServe: false, endingShot: .serve))
        points.append(PointStat(setIndex: 0, server: .opponent, winner: .opponent, outcome: .winner, isSecondServe: false, endingShot: .serve))
        points.append(PointStat(setIndex: 0, server: .opponent, winner: .opponent, outcome: .winner, isSecondServe: false, endingShot: .serve))
        points.append(PointStat(setIndex: 0, server: .opponent, winner: .me, outcome: .doubleFault, isSecondServe: true, endingShot: .serve))
        points.append(PointStat(setIndex: 0, server: .opponent, winner: .me, outcome: .forcedError, isSecondServe: false, endingShot: .servePlusOne))
        // Break point — focal as returner, wins it.
        points.append(PointStat(setIndex: 0, server: .opponent, winner: .me, outcome: .winner, isSecondServe: false, isBreakPoint: true, endingShot: .return))
        // Tiebreak point (big point via gameScoreAtStart.isTiebreak).
        points.append(PointStat(setIndex: 0, server: .opponent, winner: .me, outcome: .winner, isSecondServe: false, endingShot: .rally,
                                gameScoreAtStart: GameScoreSnapshot(server: 4, returner: 4, isTiebreak: true)))
        return points
    }

    private func makeRecord(
        points: [PointStat],
        id: UUID = UUID(),
        startTime: Date = Date(),
        endTime: Date? = Date(),
        iWon: Bool? = true,
        matchType: MatchType = .singles,
        matchFormat: MatchFormat = .standard
    ) -> MatchRecord {
        MatchRecord(
            id: id, startTime: startTime, endTime: endTime,
            setScores: [SetScore()], stats: points, iWon: iWon,
            matchType: matchType, matchFormat: matchFormat
        )
    }

    // MARK: - Eligibility

    func test_eligibility_rejectsInProgressMatch() {
        let record = makeRecord(points: makeEligiblePoints(), endTime: nil, iWon: nil)
        XCTAssertNil(MatchTrendSample(record: record))
    }

    func test_eligibility_rejectsPerpetualPoints() {
        // .perpetualPoints sets disablesPointTracking: true (ScoreTypes.swift:135) —
        // it never presents the categorisation sheet, so it can never clear
        // the categorized-points threshold either way; this asserts the
        // format is excluded directly, not merely starved of data.
        let points = (0..<30).map { _ in
            PointStat(setIndex: 0, server: .me, winner: .me, outcome: .winner)
        }
        let record = makeRecord(points: points, matchFormat: .perpetualPoints)
        XCTAssertNil(MatchTrendSample(record: record))
    }

    func test_eligibility_rejectsTooFewCategorizedPoints() {
        let points = (0..<19).map { _ in
            PointStat(setIndex: 0, server: .me, winner: .me, outcome: .winner)
        }
        let record = makeRecord(points: points)
        XCTAssertNil(MatchTrendSample(record: record))
    }

    func test_eligibility_acceptsExactlyTheThreshold() {
        let points = (0..<20).map { _ in
            PointStat(setIndex: 0, server: .me, winner: .me, outcome: .winner)
        }
        let record = makeRecord(points: points)
        XCTAssertNotNil(MatchTrendSample(record: record))
    }

    /// The threshold counts CATEGORIZED points, not raw point count — a
    /// match with 19 categorized points plus 50 uncategorized ones must
    /// still be rejected.
    func test_eligibility_countsCategorizedOnly_notTotalPoints() {
        let categorized = (0..<19).map { _ in
            PointStat(setIndex: 0, server: .me, winner: .me, outcome: .winner)
        }
        let uncategorized = (0..<50).map { _ in
            PointStat(setIndex: 0, server: .me, winner: .me, outcome: .uncategorized)
        }
        let record = makeRecord(points: categorized + uncategorized)
        XCTAssertNil(MatchTrendSample(record: record))
    }

    func test_eligibility_acceptsDraw() {
        // iWon == nil with a non-nil endTime is a completed draw, not
        // in-progress (MatchRecord.isInProgress, MatchRecord.swift:176).
        let record = makeRecord(points: makeEligiblePoints(), iWon: nil)
        let sample = MatchTrendSample(record: record)
        XCTAssertNotNil(sample)
        XCTAssertNil(sample?.recorderWon)
    }

    // MARK: - Field mapping against a hand-built match

    func test_counters_matchHandBuiltExpectations() {
        let record = makeRecord(points: makeEligiblePoints())
        guard let s = MatchTrendSample(record: record) else {
            return XCTFail("expected an eligible sample")
        }
        XCTAssertEqual(s.totalPoints, 20)
        XCTAssertEqual(s.categorizedPoints, 20)
        XCTAssertEqual(s.trackingCoverage, 1.0)
        XCTAssertEqual(s.doubleFaults, 1)
        XCTAssertEqual(s.opponentDoubleFaults, 1)
        XCTAssertEqual(s.breakPointOpps, 1)
        XCTAssertEqual(s.breakPointWins, 1)
        XCTAssertEqual(s.breakPointsFaced, 1)
        XCTAssertEqual(s.breakPointsLost, 1)
        XCTAssertEqual(s.bigPointTotal, 3)   // 2 break points + 1 tiebreak point
        XCTAssertEqual(s.opponentServicePoints, s.returnPointsOnFirst + s.returnPointsOnSecond)
    }

    /// The single highest-risk line in the plan (§10): MatchStatsSummary's
    /// my*/opponent* prefixes are relative to `focal`, not the recorder.
    /// `forcedErrorsCaused` MUST read summary.opponentForcedErrors (points
    /// the RECORDER forced errors out of the opponent on), never
    /// summary.myForcedErrors (errors the recorder was forced into).
    func test_recorderFramedNaming_forcedErrorsCausedVsConceded() {
        let record = makeRecord(points: makeEligiblePoints())
        guard let s = MatchTrendSample(record: record) else {
            return XCTFail("expected an eligible sample")
        }
        let summary = MatchStatsSummary(stats: makeEligiblePoints(), focal: .me)
        // forcedErrorsCaused: the recorder forced the OPPONENT into an error.
        // In the fixture that's the single opponent-serve forcedError point
        // the recorder won (summary.opponentForcedErrors).
        XCTAssertEqual(s.forcedErrorsCaused, summary.opponentForcedErrors)
        XCTAssertEqual(s.forcedErrorsCaused, 1)
        // forcedErrorsConceded: the recorder was forced into an error by the
        // opponent (summary.myForcedErrors). The fixture has none.
        XCTAssertEqual(s.forcedErrorsConceded, summary.myForcedErrors)
        XCTAssertEqual(s.forcedErrorsConceded, 0)
        // Same check for winners and unforced errors.
        XCTAssertEqual(s.winnersHit, summary.myWinners)
        XCTAssertEqual(s.winnersConceded, summary.opponentWinners)
        XCTAssertEqual(s.unforcedErrorsHit, summary.myUnforcedErrors)
        XCTAssertEqual(s.unforcedErrorsDrawn, summary.opponentUnforcedErrors)
    }

    // MARK: - Rally depth

    func test_rallyDepth_keyedCorrectly_missingBucketsAbsent() {
        // Only .serve and .rally ending shots in this small fixture — .return
        // and .servePlusOne must be ABSENT from the dictionary, not present
        // with a zero count (MatchStatsSummary.rallyDepth omits empty
        // buckets via compactMap; a keyed dictionary must mirror that).
        // 20 points to clear MatchTrendSample.minimumCategorizedPoints.
        let points = (0..<20).map { i in
            PointStat(setIndex: 0, server: .me, winner: i % 2 == 0 ? .me : .opponent,
                      outcome: i % 2 == 0 ? .winner : .unforcedError,
                      endingShot: i % 3 == 0 ? .serve : .rally)
        }
        let record = makeRecord(points: points)
        guard let s = MatchTrendSample(record: record) else {
            return XCTFail("expected an eligible sample")
        }
        XCTAssertNotNil(s.rallyDepth[.serve])
        XCTAssertNotNil(s.rallyDepth[.rally])
        XCTAssertNil(s.rallyDepth[.return])
        XCTAssertNil(s.rallyDepth[.servePlusOne])
        XCTAssertEqual(s.pointsWithEndingShot, 20)
    }

    func test_rallyDepth_emptyWhenNoEndingShotData() {
        // Matches archived before ending-shot capture have endingShot == nil
        // on every point (PointStat.swift:158-159's decodeIfPresent).
        let points = (0..<20).map { _ in
            PointStat(setIndex: 0, server: .me, winner: .me, outcome: .winner, endingShot: nil)
        }
        let record = makeRecord(points: points)
        guard let s = MatchTrendSample(record: record) else {
            return XCTFail("expected an eligible sample")
        }
        XCTAssertTrue(s.rallyDepth.isEmpty)
        XCTAssertEqual(s.pointsWithEndingShot, 0)
    }
}
