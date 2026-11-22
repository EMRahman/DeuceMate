// BackupPushGuard.swift — the iCloud backup push floor (TECHNICAL_DEBT #18).
//
// The iCloud copy is a one-way backup of the phone archive, so whatever the
// phone pushes replaces it. If the phone's in-memory archive ever loses matches
// without the user deleting them (a damaged file, a bug in a new code path, or
// switching to an iCloud account that already holds other matches), the next
// push would make that loss permanent in the backup too.
//
// The rule: a match that was in the backup may leave it only when the loss is
// explained.
//   • A tombstone explains it — the user permanently deleted the match.
//   • A confirmed Replace import explains it — the store rewrites the manifest
//     (scoped to the active iCloud identity) to the replacement archive's ids,
//     so the replaced matches are no longer part of the promise.
// Anything else is unexplained: the record file is withheld and the existing
// backup kept. Additive tombstones and the forgotten-player ledger are still
// pushed, because they only ever make the backup safer.
//
// Tombstones are unioned with both the manifest's and the live remote backup's
// tombstones. When the record push is ALLOWED, any id being pushed in
// `outgoing.records` is subtracted from the inherited tombstones (so a manual
// Merge or Replace import can deliberately bring a previously deleted match
// back). When the record push is WITHHELD, tombstones remain strictly additive
// — nothing is subtracted until the restored record is actually written.
//
// `BackupManifest` carries an optional `identityKey` tying it to the iCloud
// account it was pushed to. If the account changes (or the manifest is missing),
// the store ignores the stale manifest and reads the destination backup's ids
// directly via `BackupRecordID`.
import Foundation

/// The ids an iPhone last pushed to its iCloud backup: the baseline the next
/// push is checked against. Ids only — never names or match data.
public struct BackupManifest: Codable, Equatable, Sendable {
    public let recordIDs: Set<UUID>
    public let tombstones: Set<UUID>
    /// Opaque fingerprint of the iCloud account (`ubiquityIdentityToken`) that
    /// this manifest describes. `nil` when written without an active token or
    /// decoded from an older manifest; a mismatching token invalidates this
    /// manifest so the destination container is inspected directly.
    public let identityKey: String?

    public init(
        recordIDs: Set<UUID>,
        tombstones: Set<UUID>,
        identityKey: String? = nil
    ) {
        self.recordIDs = recordIDs
        self.tombstones = tombstones
        self.identityKey = identityKey
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recordIDs = try c.decode(Set<UUID>.self, forKey: .recordIDs)
        tombstones = try c.decode(Set<UUID>.self, forKey: .tombstones)
        identityKey = try c.decodeIfPresent(String.self, forKey: .identityKey)
    }

    /// The manifest of a snapshot that was just pushed in full.
    public init(pushed snapshot: ArchiveBackupPolicy.Snapshot, identityKey: String? = nil) {
        self.init(
            recordIDs: Set(snapshot.records.map(\.id)),
            tombstones: snapshot.tombstones,
            identityKey: identityKey
        )
    }

    /// Whether this manifest was recorded for `currentIdentityKey`.
    public func matchesIdentity(_ currentIdentityKey: String?) -> Bool {
        identityKey == currentIdentityKey
    }

    /// The user confirmed these matches may leave the backup ("Remove from
    /// Backup"). Only these ids stop being protected: a loss that appears
    /// later is still withheld, and the backup's deletions are kept.
    public func acceptingLoss(of ids: Set<UUID>) -> BackupManifest {
        BackupManifest(
            recordIDs: recordIDs.subtracting(ids),
            tombstones: tombstones,
            identityKey: identityKey
        )
    }
}

public enum BackupPushDecision: Equatable, Sendable {
    /// Push everything in this snapshot (tombstones already unioned with the
    /// baseline and remote tombstones, minus any id being pushed).
    case push(ArchiveBackupPolicy.Snapshot)
    /// Push the snapshot's additive tombstones and ledger, but keep the
    /// backup's records: these ids would leave the backup with no tombstone or
    /// confirmed Replace. Remote/baseline tombstones are NOT subtracted here.
    case withholdRecords(ArchiveBackupPolicy.Snapshot, unexplained: Set<UUID>)
}

public enum BackupPushGuard {

    /// Decides what may be pushed. `baseline` nil means there is no baseline
    /// record set to protect (no backup has been written yet). `remoteTombstones`
    /// carries any live deletions already present in the destination container
    /// so a local loss or Replace recovery can never erase remote deletions.
    public static func decision(
        outgoing: ArchiveBackupPolicy.Snapshot,
        baseline: BackupManifest?,
        remoteTombstones: Set<UUID> = []
    ) -> BackupPushDecision {
        let outgoingIDs = Set(outgoing.records.map(\.id))
        let inheritedTombstones = (baseline?.tombstones ?? []).union(remoteTombstones)
        let unexplained = (baseline?.recordIDs ?? [])
            .subtracting(outgoingIDs)
            .subtracting(outgoing.tombstones)
            .subtracting(inheritedTombstones)

        if unexplained.isEmpty {
            let mergedTombstones = outgoing.tombstones.union(inheritedTombstones.subtracting(outgoingIDs))
            let guarded = ArchiveBackupPolicy.Snapshot(
                records: outgoing.records,
                tombstones: mergedTombstones,
                forgottenPlayers: outgoing.forgottenPlayers
            )
            return .push(guarded)
        } else {
            // History write is withheld: keep tombstones strictly additive so
            // nothing is un-tombstoned before its restored record actually lands.
            let additiveTombstones = outgoing.tombstones.union(inheritedTombstones)
            let guarded = ArchiveBackupPolicy.Snapshot(
                records: outgoing.records,
                tombstones: additiveTombstones,
                forgottenPlayers: outgoing.forgottenPlayers
            )
            return .withholdRecords(guarded, unexplained: unexplained)
        }
    }
}

/// Decodes only a backup record's id, so the baseline can be read from a
/// backup whose full records this build can't decode (a newer format, or an
/// unknown enum value) — the very case the guard exists for.
public struct BackupRecordID: Decodable, Sendable {
    public let id: UUID
}
