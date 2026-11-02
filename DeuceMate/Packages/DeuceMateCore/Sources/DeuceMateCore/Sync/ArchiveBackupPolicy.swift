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
        /// Forgotten player ids to store alongside the records
        /// (MATCH_TAGS_PLAN.md §6.2). Backed up with the archive; unioned on restore.
        public let forgottenPlayers: ForgottenPlayerLedger

        public init(
            records: [MatchRecord],
            tombstones: Set<UUID>,
            forgottenPlayers: ForgottenPlayerLedger = ForgottenPlayerLedger()
        ) {
            self.records = records
            self.tombstones = tombstones
            self.forgottenPlayers = forgottenPlayers
        }
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
    /// App Store Review Guideline 5.1.3(ii). Tags (names, competition) are not
    /// health data and stay in the private backup; private notes are never on
    /// `MatchRecord`, so they cannot reach it. The forgotten-player ledger is
    /// carried through unchanged so deletion intent is backed up too.
    public static func backupSnapshot(
        records: [MatchRecord],
        tombstones: Set<UUID>,
        forgottenPlayers: ForgottenPlayerLedger = ForgottenPlayerLedger()
    ) -> Snapshot {
        Snapshot(
            records: sortedNewestFirst(
                records
                    .filter { !tombstones.contains($0.id) }
                    .map { $0.strippingHealthData() }
            ),
            tombstones: tombstones,
            forgottenPlayers: forgottenPlayers
        )
    }

    /// Restore an iCloud backup only during local archive initialization.
    ///
    /// This is deliberately not the WatchConnectivity merge policy. The watch is
    /// authoritative for live checkpoints; iCloud is only a backup and may be
    /// stale. Backup-only records are imported, tombstones union, completed
    /// bodies can finalize local in-progress records, but a backup in-progress
    /// body never overwrites a local in-progress body. Tags merge by their own
    /// clock on every path (`resolveBackup`). Forgotten-player ledgers union
    /// (a backup without one, `nil`, cannot erase local deletion intent), and
    /// every resulting record is scrubbed of forgotten players regardless of
    /// timestamps, so a stale backup cannot resurrect a forgotten name.
    public static func initialRestore(
        localRecords: [MatchRecord],
        localTombstones: Set<UUID>,
        backupRecords: [MatchRecord],
        backupTombstones: Set<UUID>,
        localForgottenPlayers: ForgottenPlayerLedger = ForgottenPlayerLedger(),
        backupForgottenPlayers: ForgottenPlayerLedger? = nil,
        now: Date = Date()
    ) -> Snapshot {
        let tombstones = localTombstones.union(backupTombstones)
        let forgotten = localForgottenPlayers.union(backupForgottenPlayers)
        var byID = Dictionary(
            uniqueKeysWithValues: localRecords
                .filter { !tombstones.contains($0.id) }
                .map { ($0.id, $0) }
        )

        for backup in backupRecords where !tombstones.contains(backup.id) {
            byID[backup.id] = resolveBackup(backup: backup, local: byID[backup.id])
        }

        return Snapshot(
            records: sortedNewestFirst(forgotten.scrubbed(Array(byID.values), now: now)),
            tombstones: tombstones,
            forgottenPlayers: forgotten
        )
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

    /// Chooses the body by the restore rules below, then merges tags by their
    /// own clock whichever body won (MATCH_TAGS_PLAN.md §3) — a stale backup
    /// body must neither drop newer local tags nor lose newer backup tags.
    /// Tags merge FIRST, then `mergingMatchTypeRevision` runs SECOND so converted
    /// matches deterministically normalize any merged tags.
    static func resolveBackup(backup: MatchRecord, local: MatchRecord?) -> MatchRecord {
        guard let local else { return backup.mergingMatchTypeRevision(backup.matchTypeRevision) }
        var winner = resolveBackupBody(backup: backup, local: local)
        winner.tags = MatchTags.merged(local.tags, backup.tags)
        winner = winner.mergingMatchTypeRevision(
            MatchTypeRevision.merged(local.matchTypeRevision, backup.matchTypeRevision)
        )
        return winner
    }

    private static func resolveBackupBody(backup: MatchRecord, local: MatchRecord) -> MatchRecord {
        let backupIsCompleted = !backup.isInProgress
        let localIsCompleted = !local.isInProgress

        if backupIsCompleted && !localIsCompleted {
            // Completed backup wins; backfill health fields the local checkpoint may have captured.
            return backup.fillingMissingHealthData(from: local)
        }
        if !backupIsCompleted && localIsCompleted {
            return local
        }
        if backupIsCompleted && localIsCompleted {
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
