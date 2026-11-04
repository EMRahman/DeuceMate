import XCTest
@testable import DeuceMateCore

final class MatchSessionsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private func date(_ offset: Double) -> Date { start.addingTimeInterval(offset) }
    private func point(_ offset: Double, steps: Int = 0) -> PointStat {
        PointStat(timestamp: date(offset), setIndex: 0, server: .me, winner: .me,
                  outcome: .winner, heartRateBPM: 130, stepsCumulative: steps)
    }
    func testKnownBreakExcludesParkedSamplesAndResumesBucketAtObservedResume() throws {
        let points = [point(10), point(20), point(100010), point(100020)]
        let record = MatchRecord(startTime: start, endTime: date(100030), setScores: [], stats: points,
            resumeEvents: [MatchResumeEvent(resumedAt: date(100000), pausedAt: date(30), precedingPointID: points[1].id)])
        let windows = MatchSessions.heartRateWindows(record)
        XCTAssertEqual(windows[2], DateInterval(start: date(100000), end: date(100010)))
        let values = MatchSessions.bucketHeartRate(samples: [(date(5),120),(date(15),130),(date(50000),220),(date(100005),150),(date(100015),160)], record: record)
        XCTAssertEqual(values.map(\.bpm), [120,130,150,160])
        XCTAssertEqual(values.map(\.pointIndex), [0,1,2,3])
    }
    func testUnknownParkUsesOldSnapshotsAndNeverQueriesAnUnboundedBreak() {
        let points = [point(10), point(100010)]
        let record = MatchRecord(startTime: start, endTime: date(100020), setScores: [], stats: points,
            resumeEvents: [MatchResumeEvent(resumedAt: date(100000), precedingPointID: points[0].id)])
        XCTAssertNil(MatchSessions.heartRateWindows(record)[0])
        XCTAssertEqual(MatchSessions.bucketHeartRate(samples: [(date(5),220),(date(50000),220),(date(100005),150)], record: record).map(\.bpm), [130,150])
        XCTAssertNil(MatchDurations.matchElapsedSeconds(record))
        XCTAssertNil(MatchDurations.setElapsedSeconds(record, setIndex: 0))
    }
    func testMultipleResumesAtOneBoundaryAndClockChangesAreConservative() {
        let points = [point(10), point(100010)]
        let events = [MatchResumeEvent(resumedAt: date(80000), pausedAt: date(20), precedingPointID: points[0].id),
                      MatchResumeEvent(resumedAt: date(100000), pausedAt: date(90000), precedingPointID: points[0].id)]
        let record = MatchRecord(startTime: start, endTime: date(100020), setScores: [], stats: points, resumeEvents: events)
        XCTAssertEqual(MatchSessions.heartRateWindows(record)[1], DateInterval(start: date(100000), end: date(100010)))
        var invalid = record
        invalid.resumeEvents = [MatchResumeEvent(resumedAt: date(100000), pausedAt: date(100001), precedingPointID: points[0].id)]
        XCTAssertNil(MatchSessions.heartRateWindows(invalid)[0])
    }
    func testMovementResetsLoadAtEachSessionAndFilteredSummaryRetainsFullHistoryCoordinates() {
        let points = [point(10,steps:100), point(20,steps:110),point(100010,steps:200),point(100020,steps:206)]
        let event = MatchResumeEvent(resumedAt: date(100000), pausedAt: date(30), precedingPointID: points[1].id)
        XCTAssertEqual(StepsSeries.make(stats: points, totalSteps: 206, resumeEvents: [event]).map(\.perPoint), [0,10,0,6])
        let full = MatchStatsSummary(stats: points, focal: .me, resumeEvents: [event])
        XCTAssertEqual(full.stepsTimeline.map(\.perPointSteps), [0,10,0,6])
        let scoped = MatchStatsSummary(stats: Array(points.suffix(2)), focal: .me, resumeEvents: [event], sessionPoints: points)
        XCTAssertEqual(scoped.stepsTimeline.map(\.perPointSteps), [0,6])
        XCTAssertTrue(full.autoInsights.isEmpty)
        XCTAssertTrue(full.stepsInsights.isEmpty)
        let unmeasured = points.map { $0.strippingHealthData() }
        XCTAssertTrue(StepsSeries.make(stats: unmeasured, totalSteps: 206, resumeEvents: [event]).isEmpty)
    }

    func testHTMLContractAndBothRenderersCarryPerspectiveNeutralSessionsWithoutHealth() throws {
        let points = [point(10,steps:100), point(100010,steps:200)]
        let event = MatchResumeEvent(resumedAt: date(100000), precedingPointID: points[0].id)
        let record = MatchRecord(startTime: start, endTime: date(100030), setScores: [SetScore()],
            stats: points, matchElapsedSeconds: 600, resumeEvents: [event])
        let recorder = MatchWebViewModel.make(from: record)
        let opponent = MatchWebViewModel.make(from: record, perspective: .opponent)
        XCTAssertEqual(recorder.schemaVersion, 14)
        XCTAssertEqual(recorder.points.map(\.sessionIndex), [0,1])
        XCTAssertEqual(recorder.steps?.timeline.map(\.perPoint), [0,0])
        XCTAssertEqual(recorder.resumeEvents.first?.beforePointIndex, 1)
        XCTAssertNil(recorder.resumeEvents.first?.breakSeconds)
        XCTAssertEqual(recorder.sessionSummary, opponent.sessionSummary)
        XCTAssertEqual(recorder.resumeEvents.first?.label, opponent.resumeEvents.first?.label)
        let stripped = MatchWebViewModel.make(from: record.strippingHealthData())
        XCTAssertNil(stripped.hr); XCTAssertNil(stripped.steps)
        XCTAssertEqual(stripped.resumeEvents.first?.id, event.id.uuidString)
        XCTAssertEqual(stripped.resumeEvents.first?.setIndex, 0)
        let html = MatchHTMLExporter.html(for: record)
        XCTAssertTrue(html.contains("Play sessions"))
        XCTAssertTrue(html.contains("Break duration unknown"))
        XCTAssertTrue(html.contains("stroke-dasharray=\"1 5\""))
        XCTAssertTrue(html.contains("sessionIndex === arr[i-1].sessionIndex"))
    }
}
