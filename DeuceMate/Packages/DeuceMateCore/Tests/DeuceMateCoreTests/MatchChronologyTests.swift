import XCTest
@testable import DeuceMateCore

final class MatchChronologyTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private func record(_ start: Double, _ end: Double?, id: UUID = UUID(), point: Double? = nil,
                        won: Bool? = true) -> MatchRecord {
        MatchRecord(id: id, startTime: base.addingTimeInterval(start),
                    endTime: end.map { base.addingTimeInterval($0) }, setScores: [],
                    stats: (0..<20).map { _ in PointStat(timestamp: base.addingTimeInterval(point ?? start),
                        setIndex: 0, server: .me, winner: .me, outcome: .winner) }, iWon: won)
    }

    func testFinishOrderDrivesHistoryTrendsWindowsBaselineAndBackup() throws {
        let a = record(0, 900), b = record(200, 300), c = record(400, 500)
        let archive = MatchMergePolicy.merge(incoming: [b, a, c], into: [])
        XCTAssertEqual(archive.map(\.id), [a.id, c.id, b.id])
        XCTAssertEqual(WatchMirror.merged(existing: [], incoming: archive, manifest: []).map(\.id), archive.map(\.id))
        let samples = PerformanceTrends.samples(from: archive)
        XCTAssertEqual(samples.map(\.matchID), [b.id, c.id, a.id])
        XCTAssertEqual(samples.last?.startTime, a.startTime)
        XCTAssertEqual(samples.last?.date, a.endTime)
        let scoped = PerformanceTrends.scoped(samples, filter: TrendFilter(), window: .last(2))
        XCTAssertEqual(scoped.map(\.matchID), [c.id, a.id])
        XCTAssertEqual(PerformanceTrends.series(for: .pointsWon, in: scoped)?.points.map(\.date), [c.endTime, a.endTime].compactMap { $0 })
        XCTAssertEqual(PreviousMatchBaseline.select(for: a, in: archive).baseline?.id, c.id)
        XCTAssertEqual(ArchiveBackupPolicy.BackupPreview.from(records: archive).newestMatchDate, a.endTime)
    }

    func testProvisionalActivityAndLegacyFallbackNeverUseAdministrativeFinishForPlay() throws {
        let live = record(0, nil, point: 500, won: nil)
        XCTAssertEqual(MatchChronology.date(live), base.addingTimeInterval(500))
        let completed = live.endingAtCurrentScore(at: base.addingTimeInterval(900))
        XCTAssertEqual(MatchChronology.activityDate(completed), base.addingTimeInterval(500))
        XCTAssertEqual(MatchChronology.date(completed), base.addingTimeInterval(900))
        XCTAssertEqual(PerformanceTrends.samples(from: [completed]).map(\.matchID), [live.id])
        let legacy = record(10, nil)
        XCTAssertEqual(MatchChronology.date(legacy), legacy.startTime)
        XCTAssertEqual(MatchChronology.label(legacy), "Played")
        let noPoints = MatchRecord(startTime: base, setScores: [], stats: [])
        XCTAssertEqual(MatchChronology.activityDate(noPoints), base)
    }

    func testTiesAreDeterministicAndMultiDayPresentationPreservesStart() throws {
        let low = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let high = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let a = record(0, 200_000, id: low), b = record(20, 200_000, id: high)
        XCTAssertEqual([b, a].sorted(by: MatchChronology.newestFirst).map(\.id), [low, high])
        XCTAssertEqual([b, a].sorted(by: MatchChronology.oldestFirst).map(\.id), [low, high])
        let f = DateFormatter(); f.dateStyle = .medium; f.timeZone = TimeZone(secondsFromGMT: 0)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let description = MatchChronology.description(a, formatter: f, calendar: calendar)
        XCTAssertTrue(description.contains("Started " + f.string(from: a.startTime)))
        XCTAssertTrue(description.contains("Finished " + f.string(from: try XCTUnwrap(a.endTime))))
        let vm = MatchWebViewModel.make(from: a)
        XCTAssertTrue(vm.meta.dateDisplay.contains("Started"))
        XCTAssertTrue(vm.meta.dateDisplay.contains("Finished"))
    }
}
