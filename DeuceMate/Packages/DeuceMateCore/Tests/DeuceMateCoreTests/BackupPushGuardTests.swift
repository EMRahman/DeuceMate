// BackupPushGuardTests.swift — the iCloud backup push floor (TECHNICAL_DEBT #18):
// a match may leave the backup only with a tombstone or a confirmed Replace.
import XCTest
@testable import DeuceMateCore

final class BackupPushGuardTests: XCTestCase {

    private func record(_ id: UUID = UUID()) -> MatchRecord {
        MatchRecord(
            id: id,
            startTime: Date(timeIntervalSince1970: 1_000),
            endTime: Date(timeIntervalSince1970: 2_000),
            setScores: [SetScore(gamesMe: 6, gamesOpponent: 4)],
            stats: [],
            iWon: true
        )
    }

    private func snapshot(_ records: [MatchRecord], tombstones: Set<UUID> = []) -> ArchiveBackupPolicy.Snapshot {
        ArchiveBackupPolicy.backupSnapshot(records: records, tombstones: tombstones)
    }

    func test_noBaseline_pushesUnchanged() {
        let outgoing = snapshot([])
        XCTAssertEqual(BackupPushGuard.decision(outgoing: outgoing, baseline: nil), .push(outgoing))
    }

    func test_growingArchive_pushes() {
        let a = record(), b = record()
        let baseline = BackupManifest(recordIDs: [a.id], tombstones: [])
        XCTAssertEqual(
            BackupPushGuard.decision(outgoing: snapshot([a, b]), baseline: baseline),
            .push(snapshot([a, b]))
        )
    }

    func test_deletingTheOnlyMatch_pushesAnEmptyArchive() {
        // The legitimate shrink a naive "never push smaller" floor would block.
        let a = record()
        let baseline = BackupManifest(recordIDs: [a.id], tombstones: [])
        XCTAssertEqual(
            BackupPushGuard.decision(outgoing: snapshot([], tombstones: [a.id]), baseline: baseline),
            .push(snapshot([], tombstones: [a.id]))
        )
    }

    func test_unexplainedLoss_withholdsRecordsButStillPushesTombstones() {
        // The #18 scenario: the local archive lost matches nobody deleted.
        let a = record(), b = record(), deleted = UUID()
        let baseline = BackupManifest(recordIDs: [a.id, b.id], tombstones: [deleted])
        let decision = BackupPushGuard.decision(outgoing: snapshot([]), baseline: baseline)
        XCTAssertEqual(decision, .withholdRecords(snapshot([], tombstones: [deleted]), unexplained: [a.id, b.id]))
    }

    func test_partialLoss_withholdsOnlyTheUnexplainedIDs() {
        let kept = record(), deleted = record(), lost = record()
        let baseline = BackupManifest(recordIDs: [kept.id, deleted.id, lost.id], tombstones: [])
        let decision = BackupPushGuard.decision(
            outgoing: snapshot([kept], tombstones: [deleted.id]),
            baseline: baseline
        )
        guard case .withholdRecords(_, let unexplained) = decision else {
            return XCTFail("expected the records to be withheld, got \(decision)")
        }
        XCTAssertEqual(unexplained, [lost.id])
    }

    func test_tombstonesAreUnionedWithTheBaseline() {
        // A lost local tombstone file must not shrink the backup's deletions,
        // or a fresh-install restore would bring deleted matches back.
        let a = record(), oldDeletion = UUID(), newDeletion = UUID()
        let baseline = BackupManifest(recordIDs: [a.id], tombstones: [oldDeletion])
        XCTAssertEqual(
            BackupPushGuard.decision(outgoing: snapshot([a], tombstones: [newDeletion]), baseline: baseline),
            .push(snapshot([a], tombstones: [oldDeletion, newDeletion]))
        )
    }

    func test_reimportedMatch_isNotHiddenByTheBaselineTombstone() {
        // A Replace or Merge import lifts the tombstone of a match it brings
        // back; the union must not re-tombstone a record that is being pushed.
        let restored = record()
        let baseline = BackupManifest(recordIDs: [], tombstones: [restored.id])
        XCTAssertEqual(
            BackupPushGuard.decision(outgoing: snapshot([restored]), baseline: baseline),
            .push(snapshot([restored]))
        )
    }

    func test_replaceImport_manifestExplainsTheReplacedMatches() {
        // After a confirmed Replace the store writes the replacement's ids as
        // the new baseline, so the old matches may leave the backup.
        let old = record(), replacement = record()
        let afterReplace = BackupManifest(recordIDs: [replacement.id], tombstones: [])
        XCTAssertEqual(
            BackupPushGuard.decision(outgoing: snapshot([replacement]), baseline: afterReplace),
            .push(snapshot([replacement]))
        )
        // Without that rewrite the same push would be withheld.
        let stale = BackupManifest(recordIDs: [old.id], tombstones: [])
        XCTAssertEqual(
            BackupPushGuard.decision(outgoing: snapshot([replacement]), baseline: stale),
            .withholdRecords(snapshot([replacement]), unexplained: [old.id])
        )
    }

    func test_manifestOfAPushedSnapshot_recordsItsIDsAndTombstones() throws {
        let a = record(), deleted = UUID()
        let manifest = BackupManifest(pushed: snapshot([a], tombstones: [deleted]))
        XCTAssertEqual(manifest, BackupManifest(recordIDs: [a.id], tombstones: [deleted]))
        let decoded = try JSONDecoder().decode(BackupManifest.self, from: JSONEncoder().encode(manifest))
        XCTAssertEqual(decoded, manifest)
    }

    func test_recordIDs_decodeFromABackupThisBuildCannotFullyRead() throws {
        // The baseline must be readable even when full records are not —
        // e.g. a point outcome added by a newer build.
        let json = String(decoding: try JSONEncoder().encode([record()]), as: UTF8.self)
        let newer = Data(json.replacingOccurrences(of: "\"stats\":[]", with: "\"stats\":[{\"outcome\":\"smash\"}]").utf8)
        XCTAssertNil(try? JSONDecoder().decode([MatchRecord].self, from: newer))
        XCTAssertEqual(try JSONDecoder().decode([BackupRecordID].self, from: newer).count, 1)
    }
}
