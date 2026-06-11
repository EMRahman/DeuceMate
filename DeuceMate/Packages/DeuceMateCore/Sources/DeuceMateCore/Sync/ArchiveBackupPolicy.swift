// ArchiveBackupPolicy.swift — one-way phone archive backup policy.
//
// The iPhone's durable archive is a device-local file pair. iCloud Drive holds
// a background backup copy used for fresh-install restore, not a peer copy
// that continuously merges back into the phone after initialization.
import Foundation

/// Pure rules for turning the phone archive into an iCloud backup snapshot, and
/// for the one-time initial restore before the local archive has been initialized.
public enum ArchiveBackupPolicy {

    public struct Snapshot: Equatable, Sendable {
        /// Records to store, newest-first.
        public let records: [MatchRecord]
        /// Permanently deleted match IDs to store alongside the records.
        public let tombstones: Set<UUID>
    }

    /// Summary of a pending restore prompt: record count and newest match date,
    /// derived from the raw backup arrays. Shown to the user before they decide
    /// whether to import the backup.
    public struct BackupPreview: Equatable, Sendable {
        public let recordCount: Int
        public let newestMatchDate: Date?

        public static func from(records: [MatchRecord]) -> BackupPreview {
            BackupPreview(
                recordCount: records.count,
                newestMatchDate: records.max(by: { $0.startTime < $1.startTime })?.startTime
            )
        }
    }

    /// Build the outbound backup snapshot from the local canonical archive.
    /// HealthKit-derived fields are stripped before storage to comply with
    /// App Store Review Guideline 5.1.3(ii).
    public static func backupSnapshot(
        records: [MatchRecord],
        tombstones: Set<UUID>
    ) -> Snapshot {
        Snapshot(
            records: sortedNewestFirst(
                records
                    .filter { !tombstones.contains($0.id) }
                    .map { $0.strippingHealthData() }
            ),
            tombstones: tombstones
        )
    }

    /// Restore an iCloud backup only during local archive initialization.
    ///
    /// This is deliberately not the WatchConnectivity merge policy. The watch is
    /// authoritative for live checkpoints; iCloud is only a backup and may be
    /// stale. Backup-only records are imported, tombstones union, completed
    /// bodies can finalize local in-progress records, but a backup in-progress
    /// body never overwrites a local in-progress body.
    public static func initialRestore(
        localRecords: [MatchRecord],
        localTombstones: Set<UUID>,
        backupRecords: [MatchRecord],
        backupTombstones: Set<UUID>
    ) -> Snapshot {
        let tombstones = localTombstones.union(backupTombstones)
        var byID = Dictionary(
            uniqueKeysWithValues: localRecords
                .filter { !tombstones.contains($0.id) }
                .map { ($0.id, $0) }
        )

        for backup in backupRecords where !tombstones.contains(backup.id) {
            byID[backup.id] = resolveBackup(backup: backup, local: byID[backup.id])
        }

        return Snapshot(records: sortedNewestFirst(Array(byID.values)), tombstones: tombstones)
    }

    public static func sameContents(_ a: [MatchRecord], _ b: [MatchRecord]) -> Bool {
        guard a.count == b.count else { return false }
        let byID = Dictionary(a.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return b.allSatisfy { byID[$0.id] == $0 }
    }

    public static func sortedNewestFirst(_ records: [MatchRecord]) -> [MatchRecord] {
        records.sorted {
            $0.startTime != $1.startTime
                ? $0.startTime > $1.startTime
                : $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func resolveBackup(backup: MatchRecord, local: MatchRecord?) -> MatchRecord {
        guard let local else { return backup }

        if backup.iWon != nil && local.iWon == nil {
            // Completed backup wins; backfill health fields the local checkpoint may have captured.
            return backup.fillingMissingHealthData(from: local)
        }
        if backup.iWon == nil && local.iWon != nil {
            return local
        }
        if backup.iWon != nil && local.iWon != nil {
            let backupEnd = backup.endTime ?? backup.startTime
            let localEnd = local.endTime ?? local.startTime
            return backupEnd > localEnd ? backup : local
        }

        // Both are in-progress. The backup is not authoritative for live
        // checkpoints, so keep the local body and let the next outbound backup
        // update iCloud.
        return local
    }
}
