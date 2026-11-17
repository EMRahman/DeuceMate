// CourtSideTrendsTests.swift — the deuce/ad side rule and the per-side Serve &
// Return trend metrics built on it.
import XCTest
@testable import DeuceMateCore

final class CourtSideTrendsTests: XCTestCase {

    // MARK: - Fixtures

    private func point(server: Player = .me, winner: Player = .me, outcome: PointOutcome = .winner,
                       secondServe: Bool = false, score: (Int, Int)?, tiebreak: Bool = false) -> PointStat {
        PointStat(
            setIndex: 0, server: server, winner: winner, outcome: outcome, isSecondServe: secondServe,
            gameScoreAtStart: score.map { GameScoreSnapshot(server: $0.0, returner: $0.1, isTiebreak: tiebreak) }
        )
    }

    private func record(_ points: [PointStat], format: MatchFormat = .standard, daysAgo: Int = 0) -> MatchRecord {
        let start = Date().addingTimeInterval(TimeInterval(-daysAgo * 86_400))
        return MatchRecord(
            id: UUID(), startTime: start, endTime: start.addingTimeInterval(3600),
            setScores: [SetScore()], stats: points, iWon: true,
            matchType: .singles, matchFormat: format
        )
    }

    /// 24 categorized points with known per-side serve and return results.
    ///
    /// Deuce side (even points played): I serve 8 — 6 first serves in (4 won),
    /// 2 second serves (1 won, 1 double fault); I return 4 first serves (win 1).
    /// Ad side (odd points played): I serve 8 — 4 first serves in (all won),
    /// 4 second serves (2 won); I return 4 first serves (win 3).
    private func sidedPoints() -> [PointStat] {
        var p: [PointStat] = []
        // Deuce serving.
        for i in 0..<4 { p.append(point(winner: .me, score: (i % 2 == 0 ? (0, 0) : (1, 1)))) }
        for _ in 0..<2 { p.append(point(winner: .opponent, outcome: .unforcedError, score: (2, 0))) }
        p.append(point(winner: .me, secondServe: true, score: (3, 3)))
        p.append(point(winner: .opponent, outcome: .doubleFault, secondServe: true, score: (0, 2)))
        // Ad serving.
        for _ in 0..<4 { p.append(point(winner: .me, score: (1, 0))) }
        p.append(point(winner: .me, secondServe: true, score: (4, 3)))
        p.append(point(winner: .me, secondServe: true, score: (0, 3)))
        p.append(point(winner: .opponent, outcome: .unforcedError, secondServe: true, score: (2, 1)))
        p.append(point(winner: .opponent, outcome: .doubleFault, secondServe: true, score: (3, 2)))
        // Deuce returning.
        p.append(point(server: .opponent, winner: .me, score: (0, 0)))
        for _ in 0..<3 { p.append(point(server: .opponent, winner: .opponent, score: (2, 2))) }
        // Ad returning.
        for _ in 0..<3 { p.append(point(server: .opponent, winner: .me, score: (1, 2))) }
        p.append(point(server: .opponent, winner: .opponent, score: (3, 0)))
        return p
    }

    // MARK: - CourtSide.of

    func test_side_evenPointsPlayedIsDeuce_oddIsAd() {
        XCTAssertEqual(CourtSide.of(point(score: (0, 0)), noAdScoring: false), .deuce)
        XCTAssertEqual(CourtSide.of(point(score: (1, 0)), noAdScoring: false), .ad)
        XCTAssertEqual(CourtSide.of(point(score: (2, 1)), noAdScoring: false), .ad)
        XCTAssertEqual(CourtSide.of(point(score: (1, 3)), noAdScoring: false), .deuce)
    }

    func test_side_followsDeuceAndAdvantage() {
        XCTAssertEqual(CourtSide.of(point(score: (3, 3)), noAdScoring: false), .deuce)
        XCTAssertEqual(CourtSide.of(point(score: (4, 3)), noAdScoring: false), .ad)
        XCTAssertEqual(CourtSide.of(point(score: (3, 4)), noAdScoring: false), .ad)
        XCTAssertEqual(CourtSide.of(point(score: (4, 4)), noAdScoring: false), .deuce)
    }

    /// Tiebreak: the opening point is deuce, then every server serves ad then
    /// deuce — exactly the parity of tiebreak points already played.
    func test_side_inTiebreak() {
        XCTAssertEqual(CourtSide.of(point(score: (0, 0), tiebreak: true), noAdScoring: false), .deuce)
        XCTAssertEqual(CourtSide.of(point(score: (0, 1), tiebreak: true), noAdScoring: false), .ad)
        XCTAssertEqual(CourtSide.of(point(score: (1, 1), tiebreak: true), noAdScoring: false), .deuce)
        XCTAssertEqual(CourtSide.of(point(score: (6, 5), tiebreak: true), noAdScoring: false), .ad)
    }

    func test_side_unknownWithoutSavedScore() {
        XCTAssertNil(CourtSide.of(point(score: nil), noAdScoring: false))
    }

    /// No-ad deciding point: the receiver picks the side, so it's unknown —
    /// but the same 3–3 in a no-ad TIEBREAK is an ordinary deuce-side point.
    func test_side_noAdDecidingPointIsUnknown() {
        XCTAssertNil(CourtSide.of(point(score: (3, 3)), noAdScoring: true))
        XCTAssertEqual(CourtSide.of(point(score: (3, 2)), noAdScoring: true), .ad)
        XCTAssertEqual(CourtSide.of(point(score: (3, 3), tiebreak: true), noAdScoring: true), .deuce)
    }

    // MARK: - MatchTrendSample split

    func test_sample_splitsServeAndReturnCountersBySide() throws {
        let sample = try XCTUnwrap(MatchTrendSample(record: record(sidedPoints())))
        let deuce = try XCTUnwrap(sample.serveReturn(on: .deuce))
        let ad = try XCTUnwrap(sample.serveReturn(on: .ad))

        XCTAssertEqual(deuce.servicePoints, 8)
        XCTAssertEqual(deuce.firstServesIn, 6)
        XCTAssertEqual(deuce.firstServeWins, 4)
        XCTAssertEqual(deuce.secondServePoints, 2)
        XCTAssertEqual(deuce.secondServesIn, 1)
        XCTAssertEqual(deuce.secondServeWins, 1)
        XCTAssertEqual(deuce.returnPointsOnFirst, 4)
        XCTAssertEqual(deuce.returnWinsOnFirst, 1)

        XCTAssertEqual(ad.servicePoints, 8)
        XCTAssertEqual(ad.firstServesIn, 4)
        XCTAssertEqual(ad.firstServeWins, 4)
        XCTAssertEqual(ad.secondServePoints, 4)
        XCTAssertEqual(ad.secondServesIn, 3)
        XCTAssertEqual(ad.secondServeWins, 2)
        XCTAssertEqual(ad.returnPointsOnFirst, 4)
        XCTAssertEqual(ad.returnWinsOnFirst, 3)
    }

    /// The two sides partition the whole match when every point has a side.
    func test_sample_sidesSumToWholeMatch() throws {
        let sample = try XCTUnwrap(MatchTrendSample(record: record(sidedPoints())))
        let deuce = try XCTUnwrap(sample.serveReturn(on: .deuce))
        let ad = try XCTUnwrap(sample.serveReturn(on: .ad))
        let whole = sample.serveReturn
        XCTAssertEqual(deuce.servicePoints + ad.servicePoints, whole.servicePoints)
        XCTAssertEqual(deuce.firstServesIn + ad.firstServesIn, whole.firstServesIn)
        XCTAssertEqual(deuce.secondServeWins + ad.secondServeWins, whole.secondServeWins)
        XCTAssertEqual(deuce.returnWinsOnFirst + ad.returnWinsOnFirst, whole.returnWinsOnFirst)
        XCTAssertEqual(sample.serveReturn(on: nil), whole)
    }

    /// Matches recorded before per-point score capture have no side at all —
    /// absent, not zero, so a side chart shows a gap.
    func test_sample_legacyMatchHasNoSideData() throws {
        let legacy = sidedPoints().map {
            PointStat(setIndex: $0.setIndex, server: $0.server, winner: $0.winner, outcome: $0.outcome,
                      isSecondServe: $0.isSecondServe)
        }
        let sample = try XCTUnwrap(MatchTrendSample(record: record(legacy)))
        XCTAssertTrue(sample.serveReturnBySide.isEmpty)
        XCTAssertNil(TrendMetric.firstServeIn.ratio(in: sample, courtSide: .deuce))
        XCTAssertNotNil(TrendMetric.firstServeIn.ratio(in: sample, courtSide: nil))
    }

    /// A no-ad deciding point counts in the whole match but on neither side.
    func test_sample_noAdDecidingPointCountsOnNeitherSide() throws {
        var points = sidedPoints()
        points.append(point(winner: .me, score: (3, 3)))
        let sample = try XCTUnwrap(MatchTrendSample(record: record(points, format: .fast4)))
        let deuce = try XCTUnwrap(sample.serveReturn(on: .deuce))
        let ad = try XCTUnwrap(sample.serveReturn(on: .ad))
        // The fixture's 3–3 and 4–3 serves also read as deciding-point scores
        // under no-ad, so all three drop out of both sides.
        XCTAssertEqual(deuce.servicePoints + ad.servicePoints, sample.servicePoints - 3)
    }

    // MARK: - TrendMetric

    func test_metric_readsSideCounters() throws {
        let sample = try XCTUnwrap(MatchTrendSample(record: record(sidedPoints())))
        XCTAssertEqual(TrendMetric.firstServeIn.ratio(in: sample, courtSide: .deuce),
                       TrendMetric.Ratio(numerator: 6, denominator: 8))
        XCTAssertEqual(TrendMetric.firstServeIn.ratio(in: sample, courtSide: .ad),
                       TrendMetric.Ratio(numerator: 4, denominator: 8))
        XCTAssertEqual(TrendMetric.firstServeWin.ratio(in: sample, courtSide: .ad),
                       TrendMetric.Ratio(numerator: 4, denominator: 4))
        XCTAssertEqual(TrendMetric.returnWinFirst.ratio(in: sample, courtSide: .deuce),
                       TrendMetric.Ratio(numerator: 1, denominator: 4))
        XCTAssertEqual(TrendMetric.returnWinFirst.ratio(in: sample, courtSide: .ad),
                       TrendMetric.Ratio(numerator: 3, denominator: 4))
        // No opponent second serves in the fixture: gap, not 0%.
        XCTAssertNil(TrendMetric.returnWinSecond.ratio(in: sample, courtSide: .deuce))
    }

    /// The side-free reading is unchanged by the refactor.
    func test_metric_nilSideMatchesWholeMatchReading() throws {
        let sample = try XCTUnwrap(MatchTrendSample(record: record(sidedPoints())))
        for metric in TrendMetric.allCases {
            let a = metric.rawPair(in: sample)
            let b = metric.rawPair(in: sample, courtSide: nil)
            XCTAssertEqual(a?.numerator, b?.numerator, "\(metric)")
            XCTAssertEqual(a?.denominator, b?.denominator, "\(metric)")
        }
    }

    func test_metric_onlyServeReturnSupportsSide() throws {
        let sample = try XCTUnwrap(MatchTrendSample(record: record(sidedPoints())))
        for metric in TrendMetric.allCases {
            XCTAssertEqual(metric.supportsCourtSide, metric.group == .serveReturn, "\(metric)")
            if !metric.supportsCourtSide {
                XCTAssertNil(metric.rawPair(in: sample, courtSide: .deuce), "\(metric)")
            }
        }
    }

    // MARK: - PerformanceTrends

    func test_series_poolsPerSideAcrossMatches() throws {
        let samples = PerformanceTrends.samples(from: [
            record(sidedPoints(), daysAgo: 3), record(sidedPoints(), daysAgo: 2), record(sidedPoints(), daysAgo: 1)
        ])
        let deuce = try XCTUnwrap(PerformanceTrends.series(for: .firstServeIn, in: samples, courtSide: .deuce))
        let ad = try XCTUnwrap(PerformanceTrends.series(for: .firstServeIn, in: samples, courtSide: .ad))
        XCTAssertEqual(deuce.points.count, 3)
        XCTAssertEqual(deuce.pooled, TrendMetric.Ratio(numerator: 18, denominator: 24))
        XCTAssertEqual(ad.pooled, TrendMetric.Ratio(numerator: 12, denominator: 24))
    }

    func test_groupSeries_withSideCoversEveryServeReturnMetric() {
        let samples = PerformanceTrends.samples(from: [record(sidedPoints())])
        let series = PerformanceTrends.series(for: .serveReturn, in: samples, courtSide: .ad)
        XCTAssertEqual(series.map(\.metric), TrendMetric.metrics(in: .serveReturn))
    }
}
