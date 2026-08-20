// ArchiveBackupPolicyTests.swift — one-way iCloud backup rules.
import XCTest
@testable import DeuceMateCore

final class ArchiveBackupPolicyTests: XCTestCase {

    private func makeRecord(
        id: UUID = UUID(),
        startTime: Date = Date(),
        endTime: Date? = nil,
        iWon: Bool? = nil,
        statCount: Int = 0
    ) -> MatchRecord {
        MatchRecord(
            id: id,
            startTime: startTime,
            endTime: endTime,
            setScores: [],
            stats: (0..<statCount).map { _ in
                PointStat(
                    setIndex: 0,
                    server: .me,
                    winner: .me,
                    outcome: .winner,
                    isSecondServe: false
                )
            },
            iWon: iWon
        )
    }

    private func makeRecordWithHealth(
        id: UUID = UUID(),
        startTime: Date = Date(timeIntervalSince1970: 1_700_000_000),
        endTime: Date? = Date(timeIntervalSince1970: 1_700_003_600),
        iWon: Bool? = true,
        pointID: UUID = UUID()
    ) -> MatchRecord {
        MatchRecord(
            id: id,
            startTime: startTime,
            endTime: endTime,
            setScores: [],
            stats: [
                PointStat(
                    id: pointID,
                    setIndex: 0,
                    server: .me,
                    winner: .me,
                    outcome: .winner,
                    heartRateBPM: 156,
                    stepsCumulative: 42
                )
            ],
            iWon: iWon,
            totalSteps: 1_234,
            totalDistanceMeters: 3_210,
            totalCaloriesKcal: 456
        )
    }

    // MARK: - Outbound backup

    func test_backupSnapshot_filtersTombstonedRecords() {
        let deleted = makeRecord(endTime: Date(), iWon: true)
        let kept = makeRecord(endTime: Date(), iWon: false)

        let snapshot = ArchiveBackupPolicy.backupSnapshot(
            records: [deleted, kept],
            tombstones: [deleted.id]
        )

        XCTAssertEqual(snapshot.records.map(\.id), [kept.id])
        XCTAssertEqual(snapshot.tombstones, [deleted.id])
    }

    func test_backupSnapshot_sortsNewestFirst() {
        let oldest = makeRecord(startTime: Date(timeIntervalSince1970: 100), endTime: Date(), iWon: true)
        let newest = makeRecord(startTime: Date(timeIntervalSince1970: 200), endTime: Date(), iWon: false)

        let snapshot = ArchiveBackupPolicy.backupSnapshot(records: [oldest, newest], tombstones: [])

        XCTAssertEqual(snapshot.records.map(\.id), [newest.id, oldest.id])
    }

    // MARK: - Initial restore

    func test_initialRestore_importsBackupOnlyRecord() {
        let backup = makeRecord(endTime: Date(), iWon: true)

        let snapshot = ArchiveBackupPolicy.initialRestore(
            localRecords: [], localTombstones: [],
            backupRecords: [backup], backupTombstones: []
        )

        XCTAssertEqual(snapshot.records.map(\.id), [backup.id])
    }

    func test_initialRestore_unionsTombstonesAndBlocksResurrection() {
        let backup = makeRecord(endTime: Date(), iWon: true)

        let snapshot = ArchiveBackupPolicy.initialRestore(
            localRecords: [], localTombstones: [backup.id],
            backupRecords: [backup], backupTombstones: []
        )

        XCTAssertTrue(snapshot.records.isEmpty)
        XCTAssertEqual(snapshot.tombstones, [backup.id])
    }

    func test_initialRestore_backupTombstoneDeletesLocalRecord() {
        let local = makeRecord(endTime: Date(), iWon: true)

        let snapshot = ArchiveBackupPolicy.initialRestore(
            localRecords: [local], localTombstones: [],
            backupRecords: [], backupTombstones: [local.id]
        )

        XCTAssertTrue(snapshot.records.isEmpty)
        XCTAssertEqual(snapshot.tombstones, [local.id])
    }

    func test_initialRestore_completedBackupFinalizesLocalCheckpoint() {
        let id = UUID()
        let start = Date(timeIntervalSince1970: 1_000)
        let localCheckpoint = makeRecord(id: id, startTime: start, statCount: 3)
        let completedBackup = makeRecord(id: id, startTime: start, endTime: Date(), iWon: true, statCount: 4)

        let snapshot = ArchiveBackupPolicy.initialRestore(
            localRecords: [localCheckpoint], localTombstones: [],
            backupRecords: [completedBackup], backupTombstones: []
        )

        XCTAssertEqual(snapshot.records.first?.iWon, true)
        XCTAssertEqual(snapshot.records.first?.stats.count, 4)
    }

    func test_initialRestore_staleInProgressBackupDoesNotOverwriteLocalCheckpoint() {
        let id = UUID()
        let start = Date(timeIntervalSince1970: 1_000)
        let localCheckpoint = makeRecord(id: id, startTime: start, statCount: 5)
        let staleBackup = makeRecord(id: id, startTime: start, statCount: 3)

        let snapshot = ArchiveBackupPolicy.initialRestore(
            localRecords: [localCheckpoint], localTombstones: [],
            backupRecords: [staleBackup], backupTombstones: []
        )

        XCTAssertEqual(snapshot.records.first?.stats.count, 5)
    }

    func test_initialRestore_bothCompletedLaterEndTimeWins() {
        let id = UUID()
        let start = Date(timeIntervalSince1970: 1_000)
        let olderLocal = makeRecord(id: id, startTime: start, endTime: Date(timeIntervalSince1970: 1_100), iWon: false)
        let newerBackup = makeRecord(id: id, startTime: start, endTime: Date(timeIntervalSince1970: 1_200), iWon: true)

        let snapshot = ArchiveBackupPolicy.initialRestore(
            localRecords: [olderLocal], localTombstones: [],
            backupRecords: [newerBackup], backupTombstones: []
        )

        XCTAssertEqual(snapshot.records.first?.iWon, true)
    }

    func test_sameContents_ignoresOrdering() {
        let a = makeRecord(endTime: Date(), iWon: true)
        let b = makeRecord(endTime: Date(), iWon: false)

        XCTAssertTrue(ArchiveBackupPolicy.sameContents([a, b], [b, a]))
    }

    // MARK: - Health-data stripping (PR A)

    func test_backupSnapshot_stripsAllFiveHealthKeysFromJSONTree() throws {
        let record = makeRecordWithHealth()
        let snapshot = ArchiveBackupPolicy.backupSnapshot(records: [record], tombstones: [])

        let data = try JSONEncoder().encode(snapshot.records)
        let json = String(decoding: data, as: UTF8.self)

        for key in ["totalSteps", "totalDistanceMeters", "totalCaloriesKcal", "heartRateBPM", "stepsCumulative"] {
            XCTAssertFalse(json.contains("\"" + key + "\""), "\(key) leaked into iCloud backup JSON")
        }
    }

    func test_strippingHealthData_nilsExactlyFiveFieldsAndPreservesRest() {
        let pointID = UUID()
        let full = makeRecordWithHealth(pointID: pointID)
        let stripped = full.strippingHealthData()

        XCTAssertNil(stripped.totalSteps)
        XCTAssertNil(stripped.totalDistanceMeters)
        XCTAssertNil(stripped.totalCaloriesKcal)
        XCTAssertNil(stripped.stats.first?.heartRateBPM)
        XCTAssertNil(stripped.stats.first?.stepsCumulative)

        // Idempotent
        XCTAssertEqual(stripped, stripped.strippingHealthData())

        // All non-health fields preserved
        var expected = full
        expected.totalSteps = nil
        expected.totalDistanceMeters = nil
        expected.totalCaloriesKcal = nil
        expected.stats = full.stats.map { $0.strippingHealthData() }
        XCTAssertEqual(stripped, expected)
    }

    func test_watchHeal_fullCompletedRecordWinsOverStrippedRestoredCopy() {
        let id = UUID()
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 2_000)
        let pointID = UUID()

        let restoredStripped = makeRecordWithHealth(id: id, startTime: start, endTime: end, iWon: true, pointID: pointID)
            .strippingHealthData()
        let fullFromWatch = makeRecordWithHealth(id: id, startTime: start, endTime: end, iWon: true, pointID: pointID)

        // incomingEnd >= existingEnd → full watch copy wins
        let resolved = MatchMergePolicy.resolve(incoming: fullFromWatch, existing: restoredStripped)

        XCTAssertEqual(resolved.totalSteps, 1_234)
        XCTAssertEqual(resolved.totalDistanceMeters, 3_210)
        XCTAssertEqual(resolved.totalCaloriesKcal, 456)
        XCTAssertEqual(resolved.stats.first?.heartRateBPM, 156)
        XCTAssertEqual(resolved.stats.first?.stepsCumulative, 42)
    }

    func test_e2e_disasterDrill_restoreStripsThenManualImportRestoresHealth() throws {
        let pointID = UUID()
        let record = makeRecordWithHealth(pointID: pointID)

        // iCloud backup snapshot (health stripped)
        let snapshot = ArchiveBackupPolicy.backupSnapshot(records: [record], tombstones: [])

        // Fresh install: restore from iCloud into empty local archive
        let restored = ArchiveBackupPolicy.initialRestore(
            localRecords: [], localTombstones: [],
            backupRecords: snapshot.records, backupTombstones: snapshot.tombstones
        )

        let restoredRecord = try XCTUnwrap(restored.records.first)
        XCTAssertNil(restoredRecord.totalSteps)
        XCTAssertNil(restoredRecord.stats.first?.heartRateBPM)
        // Tennis data intact
        XCTAssertEqual(restoredRecord.id, record.id)
        XCTAssertEqual(restoredRecord.iWon, record.iWon)

        // Manual import (merge) with the original full-fidelity archive
        let healed = ManualMatchArchiveBackup.importSnapshot(
            importing: [record],
            into: restored.records,
            tombstones: restored.tombstones,
            mode: .merge
        )

        let healedRecord = try XCTUnwrap(healed.records.first)
        XCTAssertEqual(healedRecord.totalSteps, 1_234)
        XCTAssertEqual(healedRecord.totalDistanceMeters, 3_210)
        XCTAssertEqual(healedRecord.totalCaloriesKcal, 456)
        XCTAssertEqual(healedRecord.stats.first?.heartRateBPM, 156)
        XCTAssertEqual(healedRecord.stats.first?.stepsCumulative, 42)
    }

    func test_resolveBackup_completedStrippedBackupBackfillsHealthFromLocalCheckpoint() throws {
        let id = UUID()
        let start = Date(timeIntervalSince1970: 1_000)
        let pointID = UUID()

        // In-progress local checkpoint with health data
        let localCheckpoint = makeRecordWithHealth(id: id, startTime: start, endTime: nil, iWon: nil, pointID: pointID)
        // Completed backup with health stripped (post-PR-A state)
        let strippedBackup = makeRecordWithHealth(
            id: id, startTime: start, endTime: Date(timeIntervalSince1970: 2_000), iWon: true, pointID: pointID
        ).strippingHealthData()

        let snapshot = ArchiveBackupPolicy.initialRestore(
            localRecords: [localCheckpoint], localTombstones: [],
            backupRecords: [strippedBackup], backupTombstones: []
        )

        let result = try XCTUnwrap(snapshot.records.first)
        // Completed backup wins (tennis outcome preserved)
        XCTAssertEqual(result.iWon, true)
        // Health fields backfilled from local checkpoint
        XCTAssertEqual(result.totalSteps, 1_234)
        XCTAssertEqual(result.totalDistanceMeters, 3_210)
        XCTAssertEqual(result.totalCaloriesKcal, 456)
        XCTAssertEqual(result.stats.first?.heartRateBPM, 156)
        XCTAssertEqual(result.stats.first?.stepsCumulative, 42)
    }

    // MARK: - Restore prompt preview

    func test_backupPreview_reportsCountAndNewestMatchDate() {
        let newest = Date(timeIntervalSince1970: 3_000)
        let preview = ArchiveBackupPolicy.BackupPreview.from(records: [
            makeRecord(startTime: Date(timeIntervalSince1970: 1_000)),
            makeRecord(startTime: newest),
            makeRecord(startTime: Date(timeIntervalSince1970: 2_000))
        ])

        XCTAssertEqual(preview.recordCount, 3)
        XCTAssertEqual(preview.newestMatchDate, newest)
    }

    func test_backupPreview_ofEmptyBackupHasNoDate() {
        let preview = ArchiveBackupPolicy.BackupPreview.from(records: [])
        XCTAssertEqual(preview.recordCount, 0)
        XCTAssertNil(preview.newestMatchDate)
    }

    func test_sortedNewestFirst_isStableForIdenticalStartTimes() {
        // Ties fall back to a deterministic order so the archive list (and the
        // preview's newest date) can't flip between reads.
        let start = Date(timeIntervalSince1970: 5_000)
        let records = (0..<4).map { _ in makeRecord(startTime: start) }

        let first = ArchiveBackupPolicy.sortedNewestFirst(records)
        let second = ArchiveBackupPolicy.sortedNewestFirst(records.reversed())

        XCTAssertEqual(Set(first.map(\.id)), Set(records.map(\.id)))
        XCTAssertEqual(first.map(\.id), second.map(\.id))
    }
}
