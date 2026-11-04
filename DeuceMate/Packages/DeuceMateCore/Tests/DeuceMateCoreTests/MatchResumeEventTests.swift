import XCTest
@testable import DeuceMateCore

final class MatchResumeEventTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private func point(_ offset: Double, id: UUID = UUID()) -> PointStat {
        PointStat(id: id, timestamp: start.addingTimeInterval(offset), setIndex: 0,
                  server: .me, winner: .me, outcome: .winner, heartRateBPM: 140, stepsCumulative: 10)
    }
    private func record() -> MatchRecord {
        MatchRecord(startTime: start, setScores: [SetScore()], stats: [point(10)], totalSteps: 100,
                    totalDistanceMeters: 120, totalCaloriesKcal: 30,
                    resumeEvents: [MatchResumeEvent(resumedAt: start.addingTimeInterval(100), pausedAt: start.addingTimeInterval(20))],
                    parkedAt: start.addingTimeInterval(150))
    }

    func testAdditiveCodingAndOldReaderCompatibility() throws {
        let original = record()
        let encoded = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(MatchRecord.self, from: encoded), original)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json.removeValue(forKey: "resumeEvents"); json.removeValue(forKey: "parkedAt")
        let legacy = try JSONDecoder().decode(MatchRecord.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(legacy.resumeEvents.isEmpty)
        XCTAssertNil(legacy.parkedAt)
        struct OldReader: Decodable { let id: UUID; let startTime: Date }
        XCTAssertEqual(try JSONDecoder().decode(OldReader.self, from: encoded).id, original.id)
    }

    func testEventsUnionIndependentlyOfBodyAndParkFollowsWinner() throws {
        let newer = record()
        var oldPeer = newer
        oldPeer.resumeEvents = []
        oldPeer.parkedAt = nil
        oldPeer.currentPointsMe = 2
        let merged = MatchMergePolicy.resolve(incoming: oldPeer, existing: newer)
        XCTAssertEqual(merged.resumeEvents, newer.resumeEvents)
        XCTAssertNil(merged.parkedAt)
        XCTAssertEqual(merged.currentPointsMe, 2)
        let completed = oldPeer.endingAtCurrentScore(at: start.addingTimeInterval(300))
        XCTAssertNil(completed.parkedAt)
        let final = MatchMergePolicy.resolve(incoming: newer, existing: completed)
        XCTAssertFalse(final.isInProgress)
        XCTAssertEqual(final.resumeEvents, newer.resumeEvents)
        XCTAssertNil(final.parkedAt)
        XCTAssertTrue(MatchMergePolicy.merge(incoming: [newer], into: [], tombstones: [newer.id]).isEmpty)
        let restored = ArchiveBackupPolicy.initialRestore(localRecords: [oldPeer], localTombstones: [], backupRecords: [newer], backupTombstones: [])
        XCTAssertEqual(restored.records.first?.resumeEvents, newer.resumeEvents)
        XCTAssertEqual(restored.records.first?.currentPointsMe, 2)
    }

    func testDuplicateIDResolutionIsCommutativeAssociativeAndIdempotent() {
        let id = UUID()
        let a = MatchResumeEvent(id: id, resumedAt: start)
        let b = MatchResumeEvent(id: id, resumedAt: start, pausedAt: start.addingTimeInterval(-50))
        let c = MatchResumeEvent(resumedAt: start.addingTimeInterval(20))
        XCTAssertEqual(MatchResumeEvent.merged([a,c], [b]), MatchResumeEvent.merged([b], [c,a]))
        XCTAssertEqual(MatchResumeEvent.merged(MatchResumeEvent.merged([a], [b]), [c]), MatchResumeEvent.merged([a], MatchResumeEvent.merged([b], [c])))
        XCTAssertEqual(MatchResumeEvent.merged([b], [b]), [b])
    }

    func testHealthPoliciesPreserveSessionMetadataAndRemoveMeasurements() throws {
        let original = record()
        let split = HealthSidecarPolicy.split([original])
        XCTAssertEqual(split.stripped.first?.resumeEvents, original.resumeEvents)
        XCTAssertEqual(split.stripped.first?.parkedAt, original.parkedAt)
        XCTAssertNil(split.stripped.first?.totalSteps)
        XCTAssertNil(split.stripped.first?.stats.first?.heartRateBPM)
        XCTAssertEqual(HealthSidecarPolicy.merge(stripped: split.stripped, health: split.health), [original])
        let backup = ArchiveBackupPolicy.backupSnapshot(records: [original], tombstones: [])
        XCTAssertEqual(backup.records, split.stripped)
        XCTAssertEqual(MatchChronology.activityDate(original), original.parkedAt)
    }

    func testFullFidelityManualArchiveTransferPreservesSessionIDsAndHealth() throws {
        let original = record()
        let bytes = try ManualMatchArchiveBackup.encode(records: [original], exportedAt: start)
        let archive = try ManualMatchArchiveBackup.decode(bytes)
        XCTAssertEqual(archive.records, [original])
        let imported = ManualMatchArchiveBackup.importSnapshot(importing: archive.records,
            into: [], tombstones: [original.id], mode: .merge)
        XCTAssertEqual(imported.records.first?.resumeEvents, original.resumeEvents)
        XCTAssertEqual(imported.records.first?.totalSteps, original.totalSteps)
        XCTAssertFalse(imported.tombstones.contains(original.id))
    }

    func testAnchorsSurviveEqualTimestampsClockChangesAndKeepFullCoordinates() {
        let points = [point(200), point(100), point(200)]
        let anchored = MatchResumeEvent(resumedAt: start.addingTimeInterval(150), precedingPointID: points[0].id)
        let coincident = MatchResumeEvent(resumedAt: start.addingTimeInterval(160), precedingPointID: points[0].id)
        XCTAssertEqual(ResumeMarkers.derive(events: [anchored, coincident], points: points).map(\.beforePointIndex), [1,1])
        XCTAssertEqual(ResumeMarkers.sessionIndices(events: [anchored,coincident], points: points), [0,2,2])
        let fallback = MatchResumeEvent(resumedAt: start.addingTimeInterval(200))
        XCTAssertEqual(ResumeMarkers.derive(events: [fallback], points: points).first?.beforePointIndex, 0)
        let missing = MatchResumeEvent(resumedAt: start, precedingPointID: UUID())
        XCTAssertNil(ResumeMarkers.derive(events: [missing], points: points).first?.beforePointIndex)
        XCTAssertEqual(ResumeMarkers.sessionIndices(events: [missing], points: points), [0,1,2])
        // Suffix-only history must not guess a boundary from the timestamp.
        XCTAssertNil(ResumeMarkers.derive(events: [anchored], points: Array(points.dropFirst())).first?.beforePointIndex)
    }

    func testTrailingNoPointsAndUnknownDurations() {
        let event = MatchResumeEvent(resumedAt: start.addingTimeInterval(20))
        XCTAssertEqual(ResumeMarkers.derive(events: [event], points: []).first?.beforePointIndex, 0)
        XCTAssertEqual(ResumeMarkers.derive(events: [event], points: [point(10)]).first?.beforePointIndex, 1)
        XCTAssertNil(event.breakDuration)
        XCTAssertNil(MatchResumeEvent(resumedAt: start, pausedAt: start.addingTimeInterval(1)).breakDuration)
        XCTAssertEqual(MatchResumeEvent(resumedAt: start, pausedAt: start).breakDuration, 0)
    }

    func testWorkoutBaselinesRetainOldTotalsAndSnapshotsDoNotAccumulateRepeatedly() {
        let previous = MatchActivityTotals(steps: 100, distanceMeters: 200, caloriesKcal: 20)
        let current = MatchActivityTotals(steps: 12, distanceMeters: 20, caloriesKcal: 2)
        let snapshot = previous.adding(current)
        XCTAssertEqual(snapshot.steps, 112)
        XCTAssertEqual(previous.adding(current), snapshot)
        XCTAssertEqual(snapshot.adding(MatchActivityTotals()), snapshot)
        XCTAssertEqual(snapshot.adding(MatchActivityTotals(steps: 3)).steps, 115)
        XCTAssertNil(MatchActivityTotals().adding(MatchActivityTotals()).steps)
    }
}
