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
        let a = record()
        let baseline = BackupManifest(recordIDs: [a.id], tombstones: [])
        XCTAssertEqual(
            BackupPushGuard.decision(outgoing: snapshot([], tombstones: [a.id]), baseline: baseline),
            .push(snapshot([], tombstones: [a.id]))
        )
    }

    func test_unexplainedLoss_withholdsRecordsButStillPushesTombstones() {
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

    func test_tombstonesAreUnionedWithBaselineAndRemoteTombstones() {
        let a = record(), oldDeletion = UUID(), remoteDeletion = UUID(), newDeletion = UUID()
        let baseline = BackupManifest(recordIDs: [a.id], tombstones: [oldDeletion])
        XCTAssertEqual(
            BackupPushGuard.decision(
                outgoing: snapshot([a], tombstones: [newDeletion]),
                baseline: baseline,
                remoteTombstones: [remoteDeletion]
            ),
            .push(snapshot([a], tombstones: [oldDeletion, remoteDeletion, newDeletion]))
        )
    }

    func test_reimportedMatch_isNotHiddenByBaselineOrRemoteTombstoneWhenPushAllowed() {
        let restored = record(), otherRemoteDeletion = UUID()
        let baseline = BackupManifest(recordIDs: [], tombstones: [restored.id])
        XCTAssertEqual(
            BackupPushGuard.decision(
                outgoing: snapshot([restored]),
                baseline: baseline,
                remoteTombstones: [restored.id, otherRemoteDeletion]
            ),
            .push(snapshot([restored], tombstones: [otherRemoteDeletion]))
        )
    }

    func test_withheldPush_keepsRemoteTombstonesStrictlyAdditive() {
        // When the history write is withheld (lost is missing), do NOT subtract
        // restored.id from remote tombstones yet because restored isn't written yet.
        let lost = record(), restored = record(), otherRemoteDeletion = UUID()
        let baseline = BackupManifest(recordIDs: [lost.id], tombstones: [])
        let decision = BackupPushGuard.decision(
            outgoing: snapshot([restored]),
            baseline: baseline,
            remoteTombstones: [restored.id, otherRemoteDeletion]
        )
        XCTAssertEqual(
            decision,
            .withholdRecords(
                ArchiveBackupPolicy.Snapshot(
                    records: snapshot([restored]).records,
                    tombstones: [restored.id, otherRemoteDeletion],
                    forgottenPlayers: ForgottenPlayerLedger()
                ),
                unexplained: [lost.id]
            )
        )
    }

    func test_replaceImport_manifestExplainsTheReplacedMatches() {
        let old = record(), replacement = record()
        let afterReplace = BackupManifest(recordIDs: [replacement.id], tombstones: [])
        XCTAssertEqual(
            BackupPushGuard.decision(outgoing: snapshot([replacement]), baseline: afterReplace),
            .push(snapshot([replacement]))
        )
        let stale = BackupManifest(recordIDs: [old.id], tombstones: [])
        XCTAssertEqual(
            BackupPushGuard.decision(outgoing: snapshot([replacement]), baseline: stale),
            .withholdRecords(snapshot([replacement]), unexplained: [old.id])
        )
    }

    func test_acceptingALoss_letsOnlyThoseMatchesLeaveAndPreservesIdentity() {
        let a = record(), b = record(), c = record(), kept = record(), deleted = UUID()
        let baseline = BackupManifest(recordIDs: [a.id, b.id, c.id, kept.id], tombstones: [deleted], identityKey: "acct-a")
        let accepted = baseline.acceptingLoss(of: [a.id, b.id])
        XCTAssertEqual(accepted, BackupManifest(recordIDs: [c.id, kept.id], tombstones: [deleted], identityKey: "acct-a"))
        XCTAssertTrue(accepted.matchesIdentity("acct-a"))
        XCTAssertFalse(accepted.matchesIdentity("acct-b"))
        XCTAssertEqual(
            BackupPushGuard.decision(outgoing: snapshot([kept, c]), baseline: accepted),
            .push(snapshot([kept, c], tombstones: [deleted]))
        )
        XCTAssertEqual(
            BackupPushGuard.decision(outgoing: snapshot([kept]), baseline: accepted),
            .withholdRecords(snapshot([kept], tombstones: [deleted]), unexplained: [c.id])
        )
    }

    func test_manifest_roundTripsWithAndWithoutIdentityKey() throws {
        let a = record(), deleted = UUID()
        let manifest = BackupManifest(pushed: snapshot([a], tombstones: [deleted]), identityKey: "token-1")
        let decoded = try JSONDecoder().decode(BackupManifest.self, from: JSONEncoder().encode(manifest))
        XCTAssertEqual(decoded, manifest)

        // Legacy manifest JSON without `identityKey` decodes cleanly with nil.
        let legacyJSON = #"{"recordIDs":["\#(a.id.uuidString)"],"tombstones":["\#(deleted.uuidString)"]}"#
        let legacyDecoded = try JSONDecoder().decode(BackupManifest.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(legacyDecoded, BackupManifest(recordIDs: [a.id], tombstones: [deleted], identityKey: nil))
    }

    func test_recordIDs_decodeFromABackupThisBuildCannotFullyRead() throws {
        let json = String(decoding: try JSONEncoder().encode([record()]), as: UTF8.self)
        let newer = Data(json.replacingOccurrences(of: "\"stats\":[]", with: "\"stats\":[{\"outcome\":\"smash\"}]").utf8)
        XCTAssertNil(try? JSONDecoder().decode([MatchRecord].self, from: newer))
        XCTAssertEqual(try JSONDecoder().decode([BackupRecordID].self, from: newer).count, 1)
    }
}
