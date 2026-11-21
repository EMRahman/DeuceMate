// BackupPushGuard.swift — the iCloud backup push floor (TECHNICAL_DEBT #18).
//
// The iCloud copy is a one-way backup of the phone archive, so whatever the
// phone pushes replaces it. If the phone's in-memory archive ever loses matches
// without the user deleting them (a damaged file, a bug in a new code path),
// the next push would make that loss permanent in the backup too.
//
// The rule: a match that was in the backup may leave it only when the loss is
// explained.
//   • A tombstone explains it — the user permanently deleted the match.
//   • A confirmed Replace import explains it — the store rewrites the manifest
//     to the replacement archive's ids and its current tombstones, so the
//     replaced matches are no longer part of the promise.
// Anything else is unexplained: the record file is withheld and the existing
// backup kept. Tombstones and the forgotten-player ledger are still pushed,
// because they only ever make the backup safer.
//
// Tombstones are pushed as a union with the baseline's, so losing the local
// tombstone file can never shrink the backup's record of deletions — except for
// a match that is in the outgoing records (a Replace or Merge import can bring
// a deleted match back on purpose; the backup must not then hide it).
//
// The baseline is the manifest of what this iPhone last pushed, persisted next
// to the canonical archive. When it is missing (first push after updating, or
// a fresh restore) the store reads the ids already in the backup instead.
import Foundation

/// The ids an iPhone last pushed to its iCloud backup: the baseline the next
/// push is checked against. Ids only — never names or match data.
public struct BackupManifest: Codable, Equatable, Sendable {
    public let recordIDs: Set<UUID>
    public let tombstones: Set<UUID>

    public init(recordIDs: Set<UUID>, tombstones: Set<UUID>) {
        self.recordIDs = recordIDs
        self.tombstones = tombstones
    }

    /// The manifest of a snapshot that was just pushed in full.
    public init(pushed snapshot: ArchiveBackupPolicy.Snapshot) {
        self.init(recordIDs: Set(snapshot.records.map(\.id)), tombstones: snapshot.tombstones)
    }
}

public enum BackupPushDecision: Equatable, Sendable {
    /// Push everything in this snapshot (tombstones already unioned with the baseline's).
    case push(ArchiveBackupPolicy.Snapshot)
    /// Push the snapshot's tombstones and ledger, but keep the backup's records:
    /// these ids would leave the backup with no tombstone or confirmed Replace.
    case withholdRecords(ArchiveBackupPolicy.Snapshot, unexplained: Set<UUID>)
}

public enum BackupPushGuard {

    /// Decides what may be pushed. `baseline` nil means there is nothing to
    /// protect (no backup has been written yet).
    public static func decision(
        outgoing: ArchiveBackupPolicy.Snapshot,
        baseline: BackupManifest?
    ) -> BackupPushDecision {
        guard let baseline else { return .push(outgoing) }
        let outgoingIDs = Set(outgoing.records.map(\.id))
        let tombstones = outgoing.tombstones.union(baseline.tombstones.subtracting(outgoingIDs))
        let guarded = ArchiveBackupPolicy.Snapshot(
            records: outgoing.records,
            tombstones: tombstones,
            forgottenPlayers: outgoing.forgottenPlayers
        )
        let unexplained = baseline.recordIDs
            .subtracting(outgoingIDs)
            .subtracting(tombstones)
        return unexplained.isEmpty ? .push(guarded) : .withholdRecords(guarded, unexplained: unexplained)
    }
}

/// Decodes only a backup record's id, so the baseline can be read from a
/// backup whose full records this build can't decode (a newer format, or an
/// unknown enum value) — the very case the guard exists for.
public struct BackupRecordID: Decodable, Sendable {
    public let id: UUID
}
