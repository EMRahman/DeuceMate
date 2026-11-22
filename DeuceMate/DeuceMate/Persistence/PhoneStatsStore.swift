// PhoneStatsStore.swift — StatsStoring implementation for the iPhone target.
// No historyCap — the phone is a durable archive that keeps everything.
//
// Storage model (canonical + backup):
//   • CANONICAL — device-local JSON (health-stripped history + tombstones +
//     forgotten-player ledger) in Application Support. Always readable at
//     launch: no iCloud daemon, no network, never evicted by storage
//     optimisation, and protected only until first unlock so background
//     WatchConnectivity launches can read it. The UI renders from this,
//     unconditionally.
//   • HEALTH SIDECAR — a device-local, backup-excluded JSON projection holding
//     only the five HealthKit-derived fields. It is merged into history in memory.
//   • ICLOUD BACKUP — the same files in the iCloud Drive ubiquity container,
//     pushed in the background (debounced) after local saves. iCloud is only
//     read during initial local-archive setup; once initialized, it never pulls
//     back into the phone archive. Its availability never gates the UI.
//
// Safety invariants (TECHNICAL_DEBT #18):
//   • FAIL CLOSED ON READ — a history, tombstone, or forgotten-player file that
//     exists but cannot be read or decoded (or a legacy orphaned `.corrupt`
//     quarantine, or missing history/tombstones when `archiveInitialized.json`
//     is present) is left in place byte-for-byte. Writes, Watch archive merges,
//     exports, and iCloud pushes are suspended, and `archiveProblem` explains
//     the state on the archive screen. Only the reconstructable Health sidecar
//     degrades independently.
//   • DURABLE WRITES ONLY — `adoptOnQueue` writes to disk BEFORE mutating
//     in-memory state or publishing, writing deletion intent (`forgottenPlayers`
//     and `deletedMatchIDs`) before `matchHistory.json`. Transient Watch write
//     failures retain unscrubbed copies in `pendingWatchRecords` for retry.
//   • ICLOUD BACKUP FLOOR (`BackupPushGuard`) — a match may leave iCloud only
//     with a tombstone or a confirmed Replace import; otherwise history is
//     withheld while additive tombstones and forgotten players still push.
//     `BackupManifest` is scoped to the active iCloud identity token; switching
//     accounts or lacking a manifest inspects the destination container
//     directly (via `BackupRecordID`) and never overwrites an unreadable remote
//     backup. Remote `forgottenPlayers.json` and `deletedMatchIDs.json` are
//     always inspected and unioned (or preserved untouched if uninspectable).
//   • EXPLICIT RECOVERY — Try Again, Restore from iCloud (lenient per-match
//     decode, clearing `backupManifest` so newer-format matches stay protected),
//     Save a Copy, confirmed Replace import, Bring Them Back, and Remove from
//     Backup. Any replacement copies originals into `MatchArchive/Recovered/`
//     first (never the Health sidecar) and aborts if copying fails.
//
// `archiveInitialized.json` means the local archive and iCloud backup have
// been reconciled at least once. Only `performRestoreOnQueue` /
// `restoreArchiveFromICloud` writes it. `adoptOnQueue` never writes it, so a
// local write can never foreclose the initial restore.
import Foundation
import Combine
import os
import DeuceMateCore

private let phoneStoreLogger = Logger(subsystem: "com.deucemate.persistence", category: "PhoneStatsStore")

final class PhoneStatsStore: ObservableObject, StatsStoring {
    static let shared = PhoneStatsStore()

    @Published private(set) var history: [MatchRecord] = []
    /// Main-thread published mirror of `tombstones` so the list can hide a stale
    /// watch-mirror row for a match that was just permanently deleted (the watch
    /// delete may still be queued and the cached mirror not yet pruned).
    @Published private(set) var tombstoneIDs: Set<UUID> = []
    /// Main-thread mirror of the forgotten-player ledger, so the roster and
    /// watch-mirror rows can exclude forgotten players before display.
    @Published private(set) var forgottenPlayers = ForgottenPlayerLedger()
    /// True while the first local setup is still pulling the archive out of the
    /// iCloud backup. Drives the "Restoring from iCloud…"
    /// status line; the list may be momentarily incomplete only in this state.
    @Published private(set) var isRestoringFromICloud: Bool = false
    /// Non-nil when the store detected a non-empty iCloud backup on a fresh
    /// install and is waiting for the user to confirm or decline the restore.
    /// Backup pushes stay paused (the marker stays absent) while this is set,
    /// so the old backup is never overwritten while the question is open.
    @Published private(set) var pendingRestorePreview: ArchiveBackupPolicy.BackupPreview? = nil
    /// Whether the last-pushed backup files are confirmed uploaded to iCloud.
    /// `nil` = nothing has been pushed yet (never claim backed up in that state);
    /// `false` = pushed to the local replica, daemon upload in progress;
    /// `true` = both files confirmed uploaded.
    @Published private(set) var isBackupUploaded: Bool? = nil
    /// Non-nil when a canonical archive file (history, tombstones, or the
    /// forgotten-player ledger) could not be read or decoded at launch. Writes
    /// and iCloud pushes are suspended and the archive screen explains why.
    @Published private(set) var archiveProblem: ArchiveLoadProblem? = nil
    /// Convenience check for views gating archive mutations and exports.
    var isArchiveBlocked: Bool { archiveProblem != nil }
    /// True when one or more Watch deliveries arrived after a healthy load but
    /// failed to persist to disk; cleared once a retry commits cleanly.
    @Published private(set) var watchArchiveSaveFailed: Bool = false
    /// How many matches the last backup push kept in the backup because they
    /// had left this iPhone with no tombstone or confirmed Replace to explain
    /// it (`BackupPushGuard`, TECHNICAL_DEBT #18); 0 when nothing is withheld.
    @Published private(set) var withheldBackupMatchCount: Int = 0
    /// The indicator reads "iCloud backup paused" instead of claiming an upload.
    var isBackupWithheld: Bool { withheldBackupMatchCount > 0 }
    /// Whether the user's iCloud account/container is currently usable. When
    /// false the archive still works in full (it is device-local); backup
    /// pushes and initial restore pause until iCloud returns.
    var isICloudAvailable: Bool { FileManager.default.ubiquityIdentityToken != nil }

    /// Serial queue confining all store state and file I/O.
    private let queue = DispatchQueue(label: "com.deucemate.phone.statsstore", qos: .utility)

    // MARK: - Queue-confined state

    /// In-memory working copy of the canonical archive, newest-first.
    private var records: [MatchRecord] = []
    /// IDs the user permanently deleted. Prevents re-import of deleted records
    /// during watch syncs and iCloud restores. `tombstoneIDs` mirrors it on main.
    private var tombstones: Set<UUID> = []
    /// Forgotten player ids (MATCH_TAGS_PLAN.md §6.2). Persisted and backed up
    /// with the tombstones; unioned, never shrunk, by every inbound path.
    private var forgotten = ForgottenPlayerLedger()
    /// Queue-confined authority for write/backup suspension. Recomputed on
    /// launch and explicit recovery.
    private var canonicalSuspension: ArchiveLoadProblem?
    private var canonicalWritesSuspended: Bool { canonicalSuspension != nil }
    /// Readable local tombstones and forgotten-player ledger retained privately
    /// while the archive is suspended (e.g., `matchHistory.json` undecodable
    /// while deletion ledgers loaded cleanly). Never published while suspended,
    /// and unioned into explicit recovery so intact local deletion intent is
    /// never erased by an older backup or Replace import.
    private var suspendedLocalTombstones: Set<UUID> = []
    private var suspendedLocalForgotten = ForgottenPlayerLedger()
    /// Watch bodies that arrived after a healthy load but failed to commit.
    /// Retained unscrubbed so retry compares their original revisions against
    /// the committed archive before scrubbing the winner.
    private var pendingWatchRecords: [MatchRecord] = [] {
        didSet {
            let failed = !pendingWatchRecords.isEmpty
            if oldValue.isEmpty != pendingWatchRecords.isEmpty {
                DispatchQueue.main.async { self.watchArchiveSaveFailed = failed }
            }
        }
    }
    /// The scheduled debounced backup push or restore download-retry, if any.
    private var pendingBackupSync: DispatchWorkItem?
    /// Last outgoing content a push handled (pushed, or withheld by the guard);
    /// nil before the first push. Used to skip redundant iCloud writes.
    private var lastPushedSnapshot: ArchiveBackupPolicy.Snapshot?
    /// The iCloud identity key at the time of the last handled push.
    /// A different key means a different iCloud account — re-inspect remote.
    private var lastPushedIdentityKey: String?
    /// What this iPhone last pushed in full (`backupManifest.json`): the
    /// baseline `BackupPushGuard` checks pushes against when its `identityKey`
    /// matches the active iCloud account.
    private var backupManifest: BackupManifest?
    /// The matches the last push withheld, and the baseline it compared
    /// against; empty / nil when nothing is withheld.
    private var withheldMatchIDs: Set<UUID> = []
    private var withheldBaseline: BackupManifest?
    private var isBackupWithheldOnQueue: Bool { !withheldMatchIDs.isEmpty }
    /// Decoded backup data waiting for the user to confirm or decline a restore.
    /// Non-nil only between when the prompt is shown and when the user responds.
    private var pendingRestoreDecoded: (records: [MatchRecord], tombstones: [UUID], forgotten: ForgottenPlayerLedger?)?

    private var ubiquityObserver: NSObjectProtocol?

    // MARK: - File locations

    /// One filename pair shared by the canonical store and the iCloud backup.
    /// Backup names intentionally match the pre-canonical layout, so the
    /// archive an earlier build kept in the ubiquity container can be adopted
    /// with no iCloud-side migration.
    private static let historyFilename = "matchHistory.json"
    private static let tombstoneFilename = "deletedMatchIDs.json"
    private static let initializedFilename = "archiveInitialized.json"
    private static let healthFilename = "healthData.json"
    private static let forgottenPlayersFilename = "forgottenPlayers.json"
    private static let backupManifestFilename = "backupManifest.json"
    /// Copies kept by recovery before it replaces anything: the preserved
    /// archive files, or the backup's record file (TECHNICAL_DEBT #18).
    private static let recoveredDirectoryName = "Recovered"

    struct StorageConfiguration {
        let canonicalDirectoryURL: URL
        let legacyDocumentsDirectoryURL: URL
        let startsICloudSync: Bool
        let backupExcluder: (URL) throws -> Void
        /// Where the iCloud backup files live; nil = iCloud unavailable.
        /// Production asks for the ubiquity container (only called on `queue`).
        /// Tests pass a local folder so the real push path runs without iCloud.
        let backupContainerURL: () -> URL?
        /// Opaque fingerprint for the signed-in iCloud account so switching
        /// accounts invalidates cached manifests/baselines and re-inspects the
        /// destination container.
        let backupIdentityKey: () -> String?

        init(
            canonicalDirectoryURL: URL,
            legacyDocumentsDirectoryURL: URL,
            startsICloudSync: Bool,
            backupExcluder: ((URL) throws -> Void)? = nil,
            backupContainerURL: (() -> URL?)? = nil,
            backupIdentityKey: (() -> String?)? = nil
        ) {
            self.canonicalDirectoryURL = canonicalDirectoryURL
            self.legacyDocumentsDirectoryURL = legacyDocumentsDirectoryURL
            self.startsICloudSync = startsICloudSync
            self.backupExcluder = backupExcluder ?? { try PhoneStatsStore.excludeFromBackup($0) }
            self.backupContainerURL = backupContainerURL
                ?? { FileManager.default.url(forUbiquityContainerIdentifier: nil) }
            self.backupIdentityKey = backupIdentityKey
                ?? { PhoneStatsStore.currentICloudIdentityKey() }
        }

        static var production: StorageConfiguration {
            StorageConfiguration(
                canonicalDirectoryURL: FileManager.default
                    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("MatchArchive", isDirectory: true),
                legacyDocumentsDirectoryURL: FileManager.default
                    .urls(for: .documentDirectory, in: .userDomainMask)[0],
                startsICloudSync: true
            )
        }
    }

    private let storageConfiguration: StorageConfiguration

    private var canonicalDirectoryURL: URL { storageConfiguration.canonicalDirectoryURL }
    private var canonicalHistoryURL: URL {
        canonicalDirectoryURL.appendingPathComponent(Self.historyFilename)
    }
    private var canonicalTombstoneURL: URL {
        canonicalDirectoryURL.appendingPathComponent(Self.tombstoneFilename)
    }
    private var canonicalInitializedURL: URL {
        canonicalDirectoryURL.appendingPathComponent(Self.initializedFilename)
    }
    private var healthSidecarURL: URL {
        canonicalDirectoryURL.appendingPathComponent(Self.healthFilename)
    }
    private var canonicalForgottenPlayersURL: URL {
        canonicalDirectoryURL.appendingPathComponent(Self.forgottenPlayersFilename)
    }
    private var backupManifestURL: URL {
        canonicalDirectoryURL.appendingPathComponent(Self.backupManifestFilename)
    }

    // MARK: - Init

    convenience init() {
        self.init(storageConfiguration: .production)
    }

    init(storageConfiguration: StorageConfiguration) {
        self.storageConfiguration = storageConfiguration
        let initial = queue.sync { () -> ([MatchRecord], Set<UUID>, Bool, ForgottenPlayerLedger, ArchiveLoadProblem?) in
            loadCanonicalOnQueue()
            return (records, tombstones, shouldAttemptInitialRestoreOnQueue, forgotten, canonicalSuspension)
        }
        history = initial.0
        tombstoneIDs = initial.1
        forgottenPlayers = initial.3
        archiveProblem = initial.4
        // Fresh local archive setup with iCloud signed in: show "Restoring from
        // iCloud…" until the first restore attempt settles, so an initially
        // short list reads as in-progress rather than data loss.
        if storageConfiguration.startsICloudSync
                && initial.2 && initial.0.isEmpty && isICloudAvailable {
            isRestoringFromICloud = true
        }
        if storageConfiguration.startsICloudSync {
            ubiquityObserver = NotificationCenter.default.addObserver(
                forName: .NSUbiquityIdentityDidChange, object: nil, queue: nil
            ) { [weak self] _ in
                self?.syncICloudBackup()
            }
            syncICloudBackup()
        }
    }

    deinit {
        if let ubiquityObserver {
            NotificationCenter.default.removeObserver(ubiquityObserver)
        }
    }

    // MARK: - StatsStoring

    /// True when the canonical archive is loaded and no Watch deliveries are
    /// waiting on a failed local write. Used by `PhoneMatchSyncService` to avoid
    /// claiming sync success while data failed to commit.
    var archiveAvailableForSync: Bool {
        queue.sync { !canonicalWritesSuspended && pendingWatchRecords.isEmpty }
    }

    func loadHistory() -> [MatchRecord] {
        queue.sync { records }
    }

    /// Replaces the archive. Stored tags and match-type revisions for any id
    /// present on both sides are carried forward by their own clocks, so a
    /// caller holding a stale copy can never erase a newer edit; forgotten
    /// players are scrubbed.
    func saveHistory(_ newRecords: [MatchRecord]) {
        queue.sync {
            let existingByID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let now = Date()
            let carried = newRecords.map { record -> MatchRecord in
                let prior = existingByID[record.id]
                let merged = record
                    .mergingResumeEvents(prior?.resumeEvents ?? [])
                    .mergingTags(prior?.tags)
                    .mergingMatchTypeRevision(prior?.matchTypeRevision)
                return forgotten.scrubbed(merged, now: now)
            }
            adoptOnQueue(records: carried, tombstones: tombstones)
        }
    }

    /// Inserts or replaces one record by id (manual entry, End at Current
    /// Score). Replacement keeps stored tags and match-type revision by their
    /// own clocks — the caller's copy may predate an edit made while it was open.
    func appendMatch(_ record: MatchRecord) {
        appendMatchDurably(record)
    }

    @discardableResult
    func appendMatchDurably(_ record: MatchRecord) -> Bool {
        queue.sync {
            var updated = records
            let prior = updated.first(where: { $0.id == record.id })
            updated.removeAll { $0.id == record.id }
            let merged = record
                .mergingResumeEvents(prior?.resumeEvents ?? [])
                .mergingTags(prior?.tags)
                .mergingMatchTypeRevision(prior?.matchTypeRevision)
            updated.append(forgotten.scrubbed(merged, now: Date()))
            return adoptOnQueue(records: updated, tombstones: tombstones)
        }
    }

    /// Pull a watch-only match into the durable archive ("Sync to iPhone"). A
    /// permanently deleted match (tombstoned) is never resurrected: a stale
    /// watch-mirror row can surface it in the window before the queued watch
    /// delete lands, so we keep the tombstone and skip the add. A stale copy
    /// can also carry a forgotten player, so it is scrubbed first.
    @discardableResult
    func syncToPhone(_ record: MatchRecord) -> Bool {
        queue.sync {
            guard !canonicalWritesSuspended else { return false }
            guard !tombstones.contains(record.id),
                  !records.contains(where: { $0.id == record.id }) else { return true }
            return adoptOnQueue(records: records + [forgotten.scrubbed(record, now: Date())], tombstones: tombstones)
        }
    }

    /// Permanently delete a match from the iPhone: drop the record and tombstone
    /// the id so neither a later watch sync nor an iCloud restore can re-import
    /// it. Returns whether the deletion committed to disk; callers must check
    /// durability before deleting from Watch or removing private notes.
    @discardableResult
    func deletePermanently(id: UUID) -> Bool {
        queue.sync {
            var updatedTombstones = tombstones
            updatedTombstones.insert(id)
            return adoptOnQueue(
                records: records.filter { $0.id != id },
                tombstones: updatedTombstones
            )
        }
    }

    /// `StatsStoring` conformance. On the phone the protocol's "remove" is a true,
    /// permanent deletion (matching the watch's destructive `removeMatch`). Freeing
    /// watch space without discarding the archive copy is a watch-side delete issued
    /// via `PhoneMatchSyncService.sendDeleteMatchOnWatch(_:)`, not a store operation.
    func removeMatch(id: UUID) { _ = deletePermanently(id: id) }

    // MARK: - Match tags (MATCH_TAGS_PLAN.md §4–§6)

    /// Why a user edit of match details, the player roster, or manual archive
    /// transfer did not happen.
    enum TagEditError: LocalizedError, Equatable {
        case matchNotFound
        case matchInProgress
        /// The canonical archive (or the forgotten-player ledger) could not be
        /// written — storage failed, or writes are suspended after an
        /// unreadable or undecodable launch read (`archiveProblem`). Nothing
        /// changed and nothing may be pushed to the watch.
        case notPersisted

        var errorDescription: String? {
            switch self {
            case .matchNotFound:
                return "This match is no longer in the iPhone archive."
            case .matchInProgress:
                return "Only completed matches can be changed between Singles and Doubles."
            case .notPersisted:
                return "Your change couldn't be saved to this iPhone's storage, so nothing was changed. Try again, or restart DeuceMate if this keeps happening."
            }
        }
    }

    /// Converts a completed match between Singles and Doubles (`Doubles ↔ Singles`),
    /// normalizing incompatible doubles tags if converting to Singles and scrubbing
    /// forgotten players. All-or-nothing via `commitUserEditOnQueue`.
    @discardableResult
    func convertMatchType(id: UUID, to newType: MatchType, now: Date = Date()) throws -> MatchRecord {
        try queue.sync {
            guard !canonicalWritesSuspended else { throw TagEditError.notPersisted }
            guard let index = records.firstIndex(where: { $0.id == id }) else {
                throw TagEditError.matchNotFound
            }
            guard !records[index].isInProgress else {
                throw TagEditError.matchInProgress
            }
            guard records[index].matchType != newType else {
                return records[index]
            }
            let converted = forgotten.scrubbed(
                records[index],
                now: now
            ).convertingMatchType(to: newType, at: now)
            var updated = records
            updated[index] = converted
            try commitUserEditOnQueue(records: updated)
            return converted
        }
    }

    /// Atomically updates a match's optional `matchType` (completed matches only)
    /// and its `MatchTags` draft in a single `commitUserEditOnQueue` write.
    /// Avoids writing a phantom empty `MatchTags` when an untagged match only
    /// changes `matchType`.
    @discardableResult
    func updateMatchDetails(
        id: UUID,
        matchType newMatchType: MatchType?,
        tags draft: MatchTags,
        now: Date = Date()
    ) throws -> MatchRecord {
        try queue.sync {
            guard !canonicalWritesSuspended else { throw TagEditError.notPersisted }
            guard let index = records.firstIndex(where: { $0.id == id }) else {
                throw TagEditError.matchNotFound
            }
            var current = records[index]
            if let newMatchType, newMatchType != current.matchType {
                guard !current.isInProgress else {
                    throw TagEditError.matchInProgress
                }
                current = current.convertingMatchType(to: newMatchType, at: now)
            }
            var normalizedDraft = draft.sanitized()
            if current.matchType == .singles {
                normalizedDraft.partner = nil
                normalizedDraft.opponents = Array(normalizedDraft.opponents.prefix(1))
            }
            let existingClean = current.tags?.sanitized()
            let tagsContentChanged: Bool = {
                guard let existingClean else { return !normalizedDraft.isEmpty }
                return existingClean.opponents != normalizedDraft.opponents
                    || existingClean.partner != normalizedDraft.partner
                    || existingClean.competitionTypeRaw != normalizedDraft.competitionTypeRaw
            }()
            if tagsContentChanged {
                let stamped = normalizedDraft.isEmpty
                    ? MatchTags.cleared(after: current.tags, now: now)
                    : normalizedDraft.revised(after: current.tags, now: now)
                let scrubbedRevision = forgotten.scrubbed(stamped, now: now)
                current = current.mergingTags(scrubbedRevision)
            } else {
                current = forgotten.scrubbed(current, now: now)
            }
            guard current != records[index] else { return current }
            var updated = records
            updated[index] = current
            try commitUserEditOnQueue(records: updated)
            return current
        }
    }

    /// Applies a post-completion match-type update (`matchTypeUpdate`) from a peer.
    /// Ignored for unknown IDs and in-progress records.
    @discardableResult
    func applyIncomingMatchType(_ update: MatchTypeUpdate, now: Date = Date()) -> [MatchRecord] {
        queue.sync {
            guard !canonicalWritesSuspended else { return records }
            guard let index = records.firstIndex(where: { $0.id == update.matchID }),
                  !records[index].isInProgress else { return records }
            let merged = forgotten.scrubbed(
                records[index],
                now: now
            ).mergingMatchTypeRevision(update.revision)
            guard merged != records[index] else { return records }
            var updated = records
            updated[index] = merged
            adoptOnQueue(records: updated, tombstones: tombstones)
            return records
        }
    }

    /// The user's edit of one match's details. `draft` is the editor's value;
    /// the store stamps it on its queue against the CURRENT stored revision
    /// (`revised(after:)`, or `cleared(after:)` when empty), so the clock is
    /// strictly monotonic even if the device clock moved backwards, then
    /// applies it with `mergingTags` — never touching score or completion.
    /// Returns the saved revision for the watch push.
    @discardableResult
    func updateTags(id: UUID, tags draft: MatchTags, now: Date = Date()) throws -> MatchTags {
        try queue.sync {
            guard !canonicalWritesSuspended else { throw TagEditError.notPersisted }
            guard let index = records.firstIndex(where: { $0.id == id }) else {
                throw TagEditError.matchNotFound
            }
            let previous = records[index].tags
            let stamped = draft.sanitized().isEmpty
                ? MatchTags.cleared(after: previous, now: now)
                : draft.revised(after: previous, now: now)
            // A player forgotten while the editor was open must not come back.
            let revision = forgotten.scrubbed(stamped, now: now)
            var updated = records
            updated[index] = updated[index].mergingTags(revision)
            let saved = updated[index].tags ?? revision
            try commitUserEditOnQueue(records: updated)
            return saved
        }
    }

    /// Applies tags that arrived from a peer (`matchTagsUpdate`). Merged by the
    /// tag clock and scrubbed of forgotten players; a record the phone does not
    /// hold is ignored (tags never create a match). Returns the resulting
    /// archive so the caller can reconcile the watch.
    @discardableResult
    func applyIncomingTags(_ update: MatchTagsUpdate, now: Date = Date()) -> [MatchRecord] {
        queue.sync {
            guard !canonicalWritesSuspended else { return records }
            guard let index = records.firstIndex(where: { $0.id == update.matchID }) else { return records }
            let merged = forgotten.scrubbed(records[index].mergingTags(update.tags), now: now)
            guard merged != records[index] else { return records }
            var updated = records
            updated[index] = merged
            adoptOnQueue(records: updated, tombstones: tombstones)
            return records
        }
    }

    /// Queue-consistent read of the ledger (the published `forgottenPlayers`
    /// mirror updates on the next main-queue turn).
    func forgottenPlayerLedger() -> ForgottenPlayerLedger {
        queue.sync { forgotten }
    }

    /// Selectable players derived from the archive, most recent first,
    /// excluding forgotten ids.
    func rosterEntries() -> [RosterEntry] {
        queue.sync { PlayerRoster.entries(from: records, forgotten: forgotten) }
    }

    /// Renames `playerID` in every match. Returns the ids of changed matches.
    /// Throws `TagEditError.notPersisted` (with nothing changed) when the
    /// archive could not be written — the caller must not push to the watch.
    @discardableResult
    func renamePlayer(_ playerID: UUID, to newName: String, now: Date = Date()) throws -> Set<UUID> {
        try applyRosterMutation { PlayerRoster.renaming(playerID, to: newName, in: $0, now: now) }
    }

    /// Updates a player's optional tennis playing profile in every match.
    @discardableResult
    func updatePlayerDetails(
        _ playerID: UUID,
        handednessRaw: String?,
        backhandRaw: String?,
        playStyleRaw: String?,
        playingNotes: String? = nil,
        now: Date = Date()
    ) throws -> Set<UUID> {
        try applyRosterMutation {
            PlayerRoster.updatingDetails(
                playerID,
                handednessRaw: handednessRaw,
                backhandRaw: backhandRaw,
                playStyleRaw: playStyleRaw,
                playingNotes: playingNotes,
                in: $0,
                now: now
            )
        }
    }

    /// Merges duplicate `duplicateID` into `keptID` in every match. Throws
    /// like `renamePlayer`.
    @discardableResult
    func mergePlayers(_ duplicateID: UUID, into keptID: UUID, now: Date = Date()) throws -> Set<UUID> {
        try applyRosterMutation { PlayerRoster.merging(duplicateID, into: keptID, in: $0, now: now) }
    }

    /// "Forget player": records the id in the ledger AND removes the player
    /// from every role in every match, in one serialized mutation, so a stale
    /// copy arriving later is scrubbed. Returns the changed match ids only once
    /// the ledger and the archive are both on disk; otherwise throws
    /// `TagEditError.notPersisted` with in-memory state unchanged.
    @discardableResult
    func forgetPlayer(_ playerID: UUID, now: Date = Date()) throws -> Set<UUID> {
        try queue.sync {
            guard !canonicalWritesSuspended else { throw TagEditError.notPersisted }
            let mutation = PlayerRoster.forgetting(playerID, in: records, now: now)
            try commitUserEditOnQueue(
                records: mutation.records,
                forgotten: forgotten.forgetting(playerID)
            )
            return mutation.affectedMatchIDs
        }
    }

    /// Match ids whose tags mention `playerID` in any role.
    func matchIDs(mentioning playerID: UUID) -> Set<UUID> {
        queue.sync {
            Set(records.filter { $0.tags?.playerIDs.contains(playerID) ?? false }.map(\.id))
        }
    }

    private func applyRosterMutation(_ mutate: ([MatchRecord]) -> RosterMutation) throws -> Set<UUID> {
        try queue.sync {
            guard !canonicalWritesSuspended else { throw TagEditError.notPersisted }
            let mutation = mutate(records)
            guard !mutation.affectedMatchIDs.isEmpty else { return [] }
            try commitUserEditOnQueue(records: mutation.records)
            return mutation.affectedMatchIDs
        }
    }

    private func commitUserEditOnQueue(
        records newRecords: [MatchRecord],
        forgotten newForgotten: ForgottenPlayerLedger? = nil
    ) throws {
        guard adoptOnQueue(records: newRecords, tombstones: tombstones, forgotten: newForgotten) else {
            throw TagEditError.notPersisted
        }
    }

    // MARK: - Manual archive export/import

    /// Full-fidelity archive (names included) plus the forgotten-player ledger,
    /// so a restore elsewhere keeps deletion intent. Refused when writes are
    /// suspended so an unreadable archive can never be exported as empty.
    func exportManualArchiveData(notes: [MatchNote]? = nil) throws -> Data {
        try queue.sync {
            guard !canonicalWritesSuspended else { throw TagEditError.notPersisted }
            return try ManualMatchArchiveBackup.encode(
                records: records,
                forgottenPlayers: forgotten.isEmpty ? nil : forgotten,
                notes: notes
            )
        }
    }

    func previewManualArchiveImport(data: Data) throws -> ManualMatchArchiveBackup.ImportPreview {
        try ManualMatchArchiveBackup.preview(data)
    }

    /// Ids of the records a manual archive file holds — used to plan what a
    /// Replace would do to private notes before the user confirms.
    func manualArchiveRecordIDs(data: Data) throws -> Set<UUID> {
        Set(try ManualMatchArchiveBackup.decode(data).records.map(\.id))
    }

    @discardableResult
    func importManualArchive(
        data: Data,
        mode: ManualMatchArchiveBackup.ImportMode
    ) throws -> ManualMatchArchiveBackup.ImportPreview {
        let archive = try ManualMatchArchiveBackup.decode(data)
        let preview = ManualMatchArchiveBackup.ImportPreview(
            recordCount: archive.records.count,
            includesHealthData: archive.includesHealthData,
            exportedAt: archive.exportedAt,
            noteCount: archive.notes?.filter { !$0.isCleared }.count ?? 0
        )

        // All-or-nothing: an import that cannot be persisted is refused and
        // leaves private notes untouched. A confirmed Replace is an explicit
        // way out of a suspended archive (preserved files are copied aside
        // first); Merge stays refused while suspended because it would hide
        // that the unreadable matches aren't included.
        try queue.sync {
            let suspension = canonicalSuspension
            if suspension != nil {
                guard mode == .replace else { throw TagEditError.notPersisted }
                do {
                    _ = try copyPreservedFilesAsideOnQueue()
                } catch {
                    throw TagEditError.notPersisted
                }
                canonicalSuspension = nil
            }
            let snapshot = ManualMatchArchiveBackup.importSnapshot(
                importing: archive.records,
                into: records,
                tombstones: tombstones.union(suspendedLocalTombstones),
                mode: mode,
                currentForgottenPlayers: forgotten.union(suspendedLocalForgotten),
                importedForgottenPlayers: archive.forgottenPlayers
            )
            guard adoptOnQueue(
                records: snapshot.records,
                tombstones: snapshot.tombstones,
                forgotten: snapshot.forgottenPlayers
            ) else {
                canonicalSuspension = suspension
                throw TagEditError.notPersisted
            }
            if suspension != nil {
                suspendedLocalTombstones = []
                suspendedLocalForgotten = ForgottenPlayerLedger()
                removeLegacyQuarantineFilesOnQueue()
                publishArchiveProblemOnQueue()
            }
            if mode == .replace {
                pendingWatchRecords = []
                // The user confirmed replacing the archive, so the backup may
                // now drop what the file didn't contain on this iCloud account.
                // Remote tombstones and forgotten players are still unioned
                // when the push runs so a Replace recovery from damaged local
                // deletion ledgers never erases remote deletion intent.
                let identityKey = storageConfiguration.backupIdentityKey() ?? backupManifest?.identityKey
                recordBackupManifestOnQueue(BackupManifest(
                    recordIDs: Set(records.map(\.id)),
                    tombstones: tombstones,
                    identityKey: identityKey
                ))
            }
        }
        return preview
    }

    // MARK: - Recovery (TECHNICAL_DEBT #18)
    //
    // Explicit ways out of a suspended archive or a withheld backup push. Each
    // replacement copies originals to `MatchArchive/Recovered/<time>/` first
    // (copy, never move: an unreadable file aborts recovery before overwriting
    // anything). The Health sidecar is never copied there.

    enum RecoveryError: Error, Equatable {
        /// The canonical files couldn't be copied or written; nothing changed.
        case notPersisted
        /// iCloud is unavailable, still downloading, or the backup unreadable/unwritable.
        case backupUnavailable
        /// None of the withheld matches could be read from the backup.
        case nothingReadable
    }

    /// Reads the canonical files again ("Try Again"). Returns the remaining
    /// problem, or `nil` when the archive is back to normal and saving again.
    func retryArchiveLoad() async -> ArchiveLoadProblem? {
        await onQueue { self.retryArchiveLoadOnQueue() }
    }

    /// Copies the preserved archive files ("Save a Copy") into a fresh
    /// temporary folder for the share sheet. Originals stay in place.
    func copyPreservedArchiveForSharing() throws -> [URL] {
        try queue.sync {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("DeuceMate Archive Copy \(UUID().uuidString)", isDirectory: true)
            return try copyPreservedFilesOnQueue(to: folder)
        }
    }

    /// What "Restore from iCloud" would restore, read fresh from the backup.
    func iCloudRestoreOffer() async -> ICloudArchiveRestore {
        await onQueue {
            switch self.readFullBackupOnQueue() {
            case .loaded(let backup):
                guard !backup.records.records.isEmpty else { return .noBackup }
                return .available(
                    .from(records: backup.records.records),
                    newerFormatCount: backup.records.undecodableCount
                )
            case .unavailable(let offer):
                return offer
            }
        }
    }

    /// Restores a suspended archive from the iCloud backup, re-merging Health
    /// values from the local backup-excluded sidecar. Clears any stale local
    /// `backupManifest` so newer-format matches still in iCloud remain
    /// protected on subsequent pushes. Returns how many matches were restored.
    func restoreArchiveFromICloud() async throws -> Int {
        try await onQueueThrowing { () throws -> Int in
            guard case .loaded(let backup) = self.readFullBackupOnQueue(),
                  !backup.records.records.isEmpty else {
                throw RecoveryError.backupUnavailable
            }
            let snapshot = ArchiveBackupPolicy.initialRestore(
                localRecords: self.records,
                localTombstones: self.tombstones.union(self.suspendedLocalTombstones),
                backupRecords: backup.records.records,
                backupTombstones: backup.tombstones,
                localForgottenPlayers: self.forgotten.union(self.suspendedLocalForgotten),
                backupForgottenPlayers: backup.forgotten
            )
            let restored = HealthSidecarPolicy.merge(
                stripped: snapshot.records,
                health: self.localHealthSidecarOnQueue()
            )
            try self.replaceSuspendedArchiveOnQueue(
                records: restored,
                tombstones: snapshot.tombstones,
                forgotten: snapshot.forgottenPlayers
            )
            // Clear any stale local manifest so the next push inspects the real
            // remote backup via `BackupRecordID` and never drops matches that
            // required a newer build (`undecodableCount > 0`).
            self.clearBackupManifestOnQueue()
            self.markArchiveInitializedOnQueue()
            return self.records.count
        }
    }

    /// "Bring Them Back": reads and validates the full backup (history,
    /// tombstones, and forgotten-player ledger), unions remote deletion intent,
    /// merges the withheld matches into the archive, and pushes immediately.
    /// Rejects stale-account recovery state if the iCloud identity changed.
    /// Returns how many came back and how many this build couldn't read (those
    /// stay withheld and protected in iCloud).
    func bringBackWithheldMatches() async throws -> (restored: Int, stillMissing: Int) {
        try await onQueueThrowing { () throws -> (restored: Int, stillMissing: Int) in
            let wanted = self.withheldMatchIDs
            guard !wanted.isEmpty else { return (0, 0) }
            let currentIdentityKey = self.storageConfiguration.backupIdentityKey()
            guard let baseline = self.withheldBaseline, baseline.matchesIdentity(currentIdentityKey) else {
                self.setBackupWithheldOnQueue([], baseline: nil)
                throw RecoveryError.backupUnavailable
            }
            guard case .loaded(let backup) = self.readFullBackupOnQueue() else {
                throw RecoveryError.backupUnavailable
            }
            guard let container = self.storageConfiguration.backupContainerURL() else {
                throw RecoveryError.backupUnavailable
            }
            let historyURL = container.appendingPathComponent(Self.historyFilename)
            let tombstoneURL = container.appendingPathComponent(Self.tombstoneFilename)
            let mergedTombstones = self.tombstones.union(backup.tombstones)
            let mergedForgotten = self.forgotten.union(backup.forgotten)
            let found = backup.records.records.filter { wanted.contains($0.id) && !mergedTombstones.contains($0.id) }
            guard !found.isEmpty else { throw RecoveryError.nothingReadable }
            let merged = mergedForgotten.scrubbed(
                MatchMergePolicy.merge(
                    incoming: found,
                    into: self.records.filter { !mergedTombstones.contains($0.id) },
                    tombstones: mergedTombstones,
                    forgottenPlayers: mergedForgotten
                ),
                now: Date()
            )
            guard self.adoptOnQueue(records: merged, tombstones: mergedTombstones, forgotten: mergedForgotten) else {
                throw RecoveryError.notPersisted
            }
            let remaining = wanted.subtracting(mergedTombstones).subtracting(Set(found.map(\.id))).count
            let outcome = self.pushNowOnQueue(historyURL: historyURL, tombstoneURL: tombstoneURL)
            switch outcome {
            case .pushed, .withheld:
                return (found.count, remaining)
            case .deferred, .unreadableRemote, .failed:
                throw RecoveryError.backupUnavailable
            }
        }
    }

    /// "Remove from Backup": the user accepts that the withheld matches leave
    /// the backup. Rejects stale-account recovery state if the iCloud account
    /// changed since the push was withheld. The backup's record file is copied
    /// to this iPhone first, then only those confirmed ids stop being protected
    /// (`acceptingLoss`). Throws `RecoveryError.backupUnavailable` if the
    /// remote write fails, without falsely clearing the withheld state.
    func removeWithheldMatchesFromBackup() async throws {
        try await onQueueThrowing {
            let accepted = self.withheldMatchIDs
            guard !accepted.isEmpty, let baseline = self.withheldBaseline else { return }
            let currentIdentityKey = self.storageConfiguration.backupIdentityKey()
            guard baseline.matchesIdentity(currentIdentityKey) else {
                self.setBackupWithheldOnQueue([], baseline: nil)
                throw RecoveryError.backupUnavailable
            }
            guard let container = self.storageConfiguration.backupContainerURL() else {
                throw RecoveryError.backupUnavailable
            }
            let historyURL = container.appendingPathComponent(Self.historyFilename)
            let tombstoneURL = container.appendingPathComponent(Self.tombstoneFilename)
            switch self.backupFileState(at: historyURL) {
            case .ready(let data):
                let folder = try self.newRecoveredFolderOnQueue()
                try data.write(to: folder.appendingPathComponent("iCloud-" + Self.historyFilename), options: .atomic)
            case .missing:
                break // nothing in the backup to keep a copy of
            case .downloading:
                throw RecoveryError.backupUnavailable
            }
            let updatedBaseline = baseline.acceptingLoss(of: accepted)
            let outcome = self.pushNowOnQueue(
                historyURL: historyURL,
                tombstoneURL: tombstoneURL,
                overrideBaseline: updatedBaseline
            )
            switch outcome {
            case .pushed:
                return
            case .withheld:
                // Accepted matches are no longer blocked, but another unexplained
                // loss still remains; record the reduced baseline and surface error.
                self.recordBackupManifestOnQueue(updatedBaseline)
                throw RecoveryError.backupUnavailable
            case .deferred, .unreadableRemote, .failed:
                throw RecoveryError.backupUnavailable
            }
        }
    }

    // MARK: Recovery helpers

    private func onQueue<T>(_ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    private func onQueueThrowing<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try work() }) }
        }
    }

    private func retryArchiveLoadOnQueue() -> ArchiveLoadProblem? {
        guard canonicalSuspension != nil else { return nil }
        canonicalSuspension = nil
        records = []
        tombstones = []
        forgotten = ForgottenPlayerLedger()
        suspendedLocalTombstones = []
        suspendedLocalForgotten = ForgottenPlayerLedger()
        loadCanonicalOnQueue()
        publishOnQueue()
        publishArchiveProblemOnQueue()
        if canonicalSuspension == nil && storageConfiguration.startsICloudSync {
            scheduleICloudBackupSyncOnQueue(after: 0, retriesRemaining: Self.backupRetryDelays.count)
        }
        return canonicalSuspension
    }

    /// Adopts a replacement for a suspended archive: copies the preserved
    /// files aside, lifts the suspension, writes, and clears legacy `.corrupt`
    /// files only after commit succeeds.
    private func replaceSuspendedArchiveOnQueue(
        records newRecords: [MatchRecord],
        tombstones newTombstones: Set<UUID>,
        forgotten newForgotten: ForgottenPlayerLedger
    ) throws {
        let suspension = canonicalSuspension
        if suspension != nil {
            do {
                _ = try copyPreservedFilesAsideOnQueue()
            } catch {
                throw RecoveryError.notPersisted
            }
        }
        canonicalSuspension = nil
        guard adoptOnQueue(records: newRecords, tombstones: newTombstones, forgotten: newForgotten) else {
            canonicalSuspension = suspension
            throw RecoveryError.notPersisted
        }
        suspendedLocalTombstones = []
        suspendedLocalForgotten = ForgottenPlayerLedger()
        removeLegacyQuarantineFilesOnQueue()
        publishArchiveProblemOnQueue()
    }

    private func publishArchiveProblemOnQueue() {
        let problem = canonicalSuspension
        DispatchQueue.main.async { self.archiveProblem = problem }
    }

    private var legacyQuarantineURLs: [URL] {
        [canonicalHistoryURL, canonicalTombstoneURL, canonicalForgottenPlayersURL]
            .map { $0.appendingPathExtension("corrupt") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The score-bearing canonical files that exist (history, tombstones,
    /// forgotten-player ledger, plus any orphaned legacy `.corrupt` files).
    /// The Health sidecar is never copied: it must stay backup-excluded, and
    /// recovery merges it back instead.
    private var preservedFileURLs: [URL] {
        let active = [canonicalHistoryURL, canonicalTombstoneURL, canonicalForgottenPlayersURL]
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        return active + legacyQuarantineURLs
    }

    private func removeLegacyQuarantineFilesOnQueue() {
        for url in legacyQuarantineURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Copies (never moves) the preserved files into `folder`. Copying first
    /// means a file that can't even be read stops the recovery before
    /// anything is overwritten.
    private func copyPreservedFilesOnQueue(to folder: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return try preservedFileURLs.map { url in
            let copy = folder.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: copy)
            return copy
        }
    }

    @discardableResult
    private func copyPreservedFilesAsideOnQueue() throws -> [URL] {
        try copyPreservedFilesOnQueue(to: newRecoveredFolderOnQueue())
    }

    private func newRecoveredFolderOnQueue() throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let folder = canonicalDirectoryURL
            .appendingPathComponent(Self.recoveredDirectoryName, isDirectory: true)
            .appendingPathComponent("\(stamp) \(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func localHealthSidecarOnQueue() -> [MatchHealthData] {
        // Reassert backup exclusion before a corrupt sidecar could be moved aside.
        if FileManager.default.fileExists(atPath: healthSidecarURL.path) {
            do {
                try storageConfiguration.backupExcluder(healthSidecarURL)
            } catch {
                phoneStoreLogger.error("Failed to reapply Health sidecar backup exclusion: \(error.localizedDescription, privacy: .public)")
            }
        }
        if case .loaded(let health) = Self.readCanonicalFile(
            [MatchHealthData].self, at: healthSidecarURL, whenUndecodable: .moveAside
        ) {
            return health
        }
        return []
    }

    private struct FullBackup {
        let records: LenientRecordList
        let tombstones: Set<UUID>
        let forgotten: ForgottenPlayerLedger?
    }

    /// The whole backup for "Restore from iCloud". Records are read one at a
    /// time; tombstones and the ledger must read cleanly, or the restore could
    /// bring back what the user deleted or forgot.
    private enum FullBackupRead {
        case loaded(FullBackup)
        case unavailable(ICloudArchiveRestore)
    }

    private func readFullBackupOnQueue() -> FullBackupRead {
        guard let container = storageConfiguration.backupContainerURL() else {
            return .unavailable(.iCloudUnavailable)
        }
        let historyState = backupFileState(at: container.appendingPathComponent(Self.historyFilename))
        let tombstoneState = backupFileState(at: container.appendingPathComponent(Self.tombstoneFilename))
        let ledgerState = backupFileState(at: container.appendingPathComponent(Self.forgottenPlayersFilename))
        if historyState.isDownloading || tombstoneState.isDownloading || ledgerState.isDownloading {
            return .unavailable(.downloading)
        }
        let records = decodeBackup(
            LenientRecordList.self,
            from: historyState,
            expectedFormat: PersistedArchiveCodec.historyFormat
        )
        let tombstones = decodeBackup(
            [UUID].self,
            from: tombstoneState,
            expectedFormat: PersistedArchiveCodec.tombstonesFormat
        )
        let ledger = decodeStrictBackupLedger(from: ledgerState)
        guard records.isUsable, tombstones.isUsable, ledger.isUsable else { return .unavailable(.unreadable) }
        guard let list = records.value else { return .unavailable(.noBackup) }
        return .loaded(FullBackup(
            records: list,
            tombstones: Set(tombstones.value ?? []),
            forgotten: ledger.value
        ))
    }

    /// Pushes now instead of after the debounce, so the indicator and the
    /// withheld notice update as soon as a recovery action finishes.
    @discardableResult
    private func pushNowOnQueue(
        historyURL: URL,
        tombstoneURL: URL,
        overrideBaseline: BackupManifest? = nil
    ) -> PushOutcome {
        pendingBackupSync?.cancel()
        pendingBackupSync = nil
        guard !canonicalWritesSuspended, !shouldAttemptInitialRestoreOnQueue else {
            return .deferred
        }
        lastPushedSnapshot = nil
        return pushBackupOnQueue(
            historyURL: historyURL,
            tombstoneURL: tombstoneURL,
            overrideBaseline: overrideBaseline
        )
    }

    // MARK: - Merge incoming records from WatchConnectivity

    /// Merges watch records (tags by their own clock, forgotten players
    /// scrubbed) and returns the committed archive plus any retried IDs whose
    /// tags/match-type revisions should be reconciled back to the watch.
    /// Returns `nil` when writes are suspended or disk persistence fails
    /// (retaining unscrubbed copies in `pendingWatchRecords` for retry).
    @discardableResult
    func mergeIncoming(_ incoming: [MatchRecord]) -> (archive: [MatchRecord], retriedIDs: Set<UUID>)? {
        queue.sync {
            guard !canonicalWritesSuspended else { return nil }
            if incoming.isEmpty && pendingWatchRecords.isEmpty { return (records, []) }
            // Resolve competing Watch deliveries by their original revisions.
            // A scrub advances the tag clock, so apply it only after comparing
            // the Watch and phone copies in the archive merge below.
            let copies = pendingWatchRecords.isEmpty ? incoming : MatchMergePolicy.merge(
                incoming: incoming, into: pendingWatchRecords, tombstones: tombstones
            )
            let merged = MatchMergePolicy.merge(
                incoming: copies, into: records, tombstones: tombstones, forgottenPlayers: forgotten
            )
            guard merged == records || adoptOnQueue(records: merged, tombstones: tombstones) else {
                pendingWatchRecords = MatchMergePolicy.merge(incoming: copies, into: [], tombstones: tombstones)
                return nil
            }
            let retriedIDs = Set(pendingWatchRecords.map(\.id))
            pendingWatchRecords = []
            return (records, retriedIDs)
        }
    }

    @discardableResult
    func mergeIncoming(_ record: MatchRecord) -> (archive: [MatchRecord], retriedIDs: Set<UUID>)? {
        mergeIncoming([record])
    }

    // MARK: - Canonical store (device-local source of truth)

    /// Adopt new state as the canonical archive: persist it FIRST, then update
    /// memory, publish it, and schedule a debounced iCloud backup sync.
    /// `forgotten` nil keeps the current ledger (it only ever grows).
    /// Returns whether the canonical files were written.
    @discardableResult
    private func adoptOnQueue(
        records newRecords: [MatchRecord],
        tombstones newTombstones: Set<UUID>,
        forgotten newForgotten: ForgottenPlayerLedger? = nil
    ) -> Bool {
        guard !canonicalWritesSuspended else { return false }
        let sorted = Self.sortedNewestFirst(newRecords)
        let ledger = newForgotten.map { forgotten.union($0) } ?? forgotten
        guard writeCanonicalOnQueue(records: sorted, tombstones: newTombstones, forgotten: ledger) else {
            return false
        }
        records = sorted
        tombstones = newTombstones
        forgotten = ledger
        publishOnQueue()
        if storageConfiguration.startsICloudSync {
            scheduleICloudBackupSyncOnQueue(after: Self.backupPushDebounce, retriesRemaining: Self.backupRetryDelays.count)
        }
        return true
    }

    private func publishOnQueue() {
        let recordsSnapshot = records
        let tombstoneSnapshot = tombstones
        let forgottenSnapshot = forgotten
        DispatchQueue.main.async {
            self.history = recordsSnapshot
            self.tombstoneIDs = tombstoneSnapshot
            if self.forgottenPlayers != forgottenSnapshot {
                self.forgottenPlayers = forgottenSnapshot
            }
        }
    }

    @discardableResult
    private func writeCanonicalOnQueue(
        records: [MatchRecord],
        tombstones: Set<UUID>,
        forgotten: ForgottenPlayerLedger
    ) -> Bool {
        guard !canonicalWritesSuspended else { return false }
        // What the deletion-intent files held before this attempt, so a write
        // that fails after them can put them back (see the catch below).
        let priorIntent = [canonicalForgottenPlayersURL, canonicalTombstoneURL].map(Self.priorContents)
        var wroteIntent = false
        do {
            let split = HealthSidecarPolicy.split(records)
            try FileManager.default.createDirectory(
                at: canonicalDirectoryURL, withIntermediateDirectories: true
            )
            // Deletion intent FIRST (`forgottenPlayers` and `deletedMatchIDs`):
            // if the process dies before `matchHistory.json` finishes, a
            // relaunch never loses a deletion or resurrects a forgotten
            // player — and `deletePermanently` can never drop a record from
            // history without its tombstone already on disk.
            wroteIntent = true
            try Self.write(forgotten, to: canonicalForgottenPlayersURL)
            try Self.write(Array(tombstones), to: canonicalTombstoneURL)
            try Self.write(split.health, to: healthSidecarURL)
            // Atomic writes replace the destination inode, so the exclusion
            // resource value must be reapplied after every sidecar write. If
            // that fails, discard the unsafe projection but continue saving
            // the stripped main archive: scores must remain durable without
            // ever leaving Health data eligible for device backup.
            do {
                try storageConfiguration.backupExcluder(healthSidecarURL)
            } catch {
                phoneStoreLogger.error("Failed to exclude Health sidecar from backup; discarding its Health projection: \(error.localizedDescription, privacy: .public)")
                Self.discardUnsafeHealthSidecar(at: healthSidecarURL)
            }

            try Self.write(split.stripped, to: canonicalHistoryURL)
            return true
        } catch {
            phoneStoreLogger.error("Failed to write canonical archive: \(error.localizedDescription, privacy: .public)")
            // A write that fails (rather than a crash) is reported to the
            // caller as "nothing changed": the user is told the delete or
            // forget didn't happen, the note is kept and the Watch isn't told.
            // Deletion intent left on disk would make it happen anyway at the
            // next launch, so put those files back as they were.
            if wroteIntent { Self.restoreFiles(priorIntent) }
            return false
        }
    }

    /// A file's contents before a write, so a failed write can put them back.
    private enum PriorContents {
        case missing
        case bytes(Data)
        /// Present but not readable as a file: left alone, never removed.
        case unknown
    }

    private static func priorContents(of url: URL) -> (url: URL, prior: PriorContents) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return (url, .missing)
        }
        guard !isDirectory.boolValue, let data = try? Data(contentsOf: url) else { return (url, .unknown) }
        return (url, .bytes(data))
    }

    /// Best-effort: rewrites each file's earlier bytes, or removes a file that
    /// didn't exist before. A failure is logged; nothing more can be done.
    private static func restoreFiles(_ files: [(url: URL, prior: PriorContents)]) {
        for file in files {
            do {
                switch file.prior {
                case .bytes(let bytes):
                    try bytes.write(to: file.url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                case .missing:
                    var isDirectory: ObjCBool = false
                    if FileManager.default.fileExists(atPath: file.url.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                        try FileManager.default.removeItem(at: file.url)
                    }
                case .unknown:
                    break
                }
            } catch {
                phoneStoreLogger.error("Failed to restore \(file.url.lastPathComponent, privacy: .public) after a failed write: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Records why canonical writes stop, keeping the more persistent reason
    /// when several files fail.
    private func suspendCanonicalWrites(_ problem: ArchiveLoadProblem) {
        canonicalSuspension = problem.combined(with: canonicalSuspension)
    }

    /// Strict decoder for persisted/backed-up `forgottenPlayers.json`: checks
    /// `schemaVersion` BEFORE decoding `playerIDs` so a newer schema version
    /// diagnoses as `.newerVersion` even if its body shape changed, and
    /// requires a complete UUID set for supported versions.
    /// (`ForgottenPlayerLedger.init(from:)` intentionally tolerates malformed
    /// fields for external manual imports.)
    private struct StoredForgottenPlayers: Decodable {
        let playerIDs: Set<UUID>
        let schemaVersion: Int?

        private enum CodingKeys: String, CodingKey {
            case playerIDs
            case schemaVersion
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let version = try c.decodeIfPresent(Int.self, forKey: .schemaVersion)
            if let version {
                if version > ForgottenPlayerLedger.currentSchemaVersion {
                    throw PersistedArchiveCodec.CodecError.newerSchemaVersion(
                        version: version,
                        maxSupported: ForgottenPlayerLedger.currentSchemaVersion
                    )
                }
                guard version >= 1 else {
                    throw PersistedArchiveCodec.CodecError.unsupportedSchemaVersion(version)
                }
            }
            schemaVersion = version
            playerIDs = try c.decode(Set<UUID>.self, forKey: .playerIDs)
        }

        var ledger: ForgottenPlayerLedger {
            var result = ForgottenPlayerLedger(playerIDs: playerIDs)
            if let schemaVersion { result.schemaVersion = schemaVersion }
            return result
        }
    }

    private func loadCanonicalOnQueue() {
        // Reassert the file flag before a corrupt sidecar can be moved to a
        // recovery file. The moved quarantine copy still contains Health data.
        if FileManager.default.fileExists(atPath: healthSidecarURL.path) {
            do {
                try storageConfiguration.backupExcluder(healthSidecarURL)
            } catch {
                phoneStoreLogger.error("Failed to reapply Health sidecar backup exclusion: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Validate all three score-bearing files before migration, publication,
        // or any write. Unknown deletion intent makes even a readable history
        // unsafe to publish or mutate.
        let tombstoneRead = Self.readCanonicalFile(
            [UUID].self,
            at: canonicalTombstoneURL,
            expectedFormat: PersistedArchiveCodec.tombstonesFormat,
            whenUndecodable: .preserveInPlace
        )
        let ledgerRead = Self.readCanonicalFile(
            StoredForgottenPlayers.self,
            at: canonicalForgottenPlayersURL,
            whenUndecodable: .preserveInPlace
        )
        let historyRead = Self.readCanonicalFile(
            [MatchRecord].self,
            at: canonicalHistoryURL,
            expectedFormat: PersistedArchiveCodec.historyFormat,
            whenUndecodable: .preserveInPlace
        )

        var loadedTombstones: [UUID]?
        switch tombstoneRead {
        case .loaded(let ids): loadedTombstones = ids
        case .missing: break
        case .unreadable: suspendCanonicalWrites(.unreadable)
        case .undecodable, .corrupt: suspendCanonicalWrites(.undecodable)
        case .newerVersion: suspendCanonicalWrites(.newerVersion)
        }

        var loadedLedger: ForgottenPlayerLedger?
        switch ledgerRead {
        case .loaded(let stored):
            loadedLedger = stored.ledger
        case .missing:
            break // pre-tags archive; optional when genuinely absent
        case .unreadable:
            suspendCanonicalWrites(.unreadable)
        case .undecodable, .corrupt:
            suspendCanonicalWrites(.undecodable)
        case .newerVersion:
            suspendCanonicalWrites(.newerVersion)
        }

        var loadedHistory: [MatchRecord]?
        switch historyRead {
        case .loaded(let loaded): loadedHistory = loaded
        case .missing: break
        case .unreadable: suspendCanonicalWrites(.unreadable)
        case .undecodable, .corrupt: suspendCanonicalWrites(.undecodable)
        case .newerVersion: suspendCanonicalWrites(.newerVersion)
        }

        // Both history and tombstones precede `archiveInitialized.json`, even
        // for an empty archive. Missing either when initialized means the local
        // archive is incomplete and must not look like a fresh install.
        if loadedHistory == nil || loadedTombstones == nil {
            switch Self.readCanonicalFile(Bool.self, at: canonicalInitializedURL, whenUndecodable: .preserveInPlace) {
            case .loaded(true), .undecodable, .corrupt, .newerVersion:
                suspendCanonicalWrites(.undecodable)
            case .unreadable:
                suspendCanonicalWrites(.unreadable)
            case .loaded(false), .missing:
                break
            }
        }

        if let canonicalSuspension {
            records = []
            tombstones = []
            forgotten = ForgottenPlayerLedger()
            suspendedLocalTombstones = Set(loadedTombstones ?? [])
            suspendedLocalForgotten = loadedLedger ?? ForgottenPlayerLedger()
            phoneStoreLogger.error("Canonical archive \(canonicalSuspension.rawValue, privacy: .public); files preserved, archive operations and iCloud backup suspended")
            return
        }

        let loadedRecords: [MatchRecord]
        if let loadedHistory {
            loadedRecords = loadedHistory
            tombstones = Set(loadedTombstones ?? [])
        } else {
            switch migrateLegacyDocumentsArchiveIfNeeded(deleted: loadedTombstones ?? []) {
            case .loaded(let migrated):
                loadedRecords = migrated.records
                tombstones = migrated.tombstones
            case .failed(let problem):
                suspendCanonicalWrites(problem)
                records = []
                tombstones = []
                forgotten = ForgottenPlayerLedger()
                suspendedLocalTombstones = Set(loadedTombstones ?? [])
                suspendedLocalForgotten = loadedLedger ?? ForgottenPlayerLedger()
                phoneStoreLogger.error("Legacy archive migration blocked (\(problem.rawValue, privacy: .public))")
                return
            }
        }
        suspendedLocalTombstones = []
        suspendedLocalForgotten = ForgottenPlayerLedger()
        forgotten = loadedLedger ?? ForgottenPlayerLedger()

        // The Health sidecar is a reconstructable projection, not score-bearing
        // data: a damaged one is moved aside and the archive keeps working.
        let health: [MatchHealthData]
        switch Self.readCanonicalFile([MatchHealthData].self, at: healthSidecarURL, whenUndecodable: .moveAside) {
        case .loaded(let loaded):
            health = loaded
        case .missing, .corrupt, .undecodable, .unreadable, .newerVersion:
            health = []
        }

        let loadedHadHealth = !HealthSidecarPolicy.split(loadedRecords).health.isEmpty
        let merged = HealthSidecarPolicy.merge(stripped: loadedRecords, health: health)
        // Deletion intent (`forgottenPlayers` and `deletedMatchIDs`) is written
        // BEFORE `matchHistory.json`, so an interrupted delete or forget can
        // leave an older `matchHistory.json` still containing a tombstoned
        // match or forgotten player; replay both here before publishing.
        let withoutDeleted = merged.filter { !tombstones.contains($0.id) }
        let neededTombstoneReplay = withoutDeleted.count != merged.count
        let scrubbed = forgotten.scrubbed(withoutDeleted, now: Date())
        let neededScrub = scrubbed != withoutDeleted
        records = Self.sortedNewestFirst(scrubbed)

        // The pre-sidecar canonical file was full-fidelity. Content detection is
        // the migration marker: once rewritten successfully, the main file has
        // no Health fields and this path never runs again.
        if loadedHadHealth || neededTombstoneReplay || neededScrub {
            if writeCanonicalOnQueue(records: records, tombstones: tombstones, forgotten: forgotten) {
                phoneStoreLogger.notice("Reconciled canonical archive with Health sidecar and deletion ledgers")
            }
        }

        // A missing or unreadable manifest only means the next push reads its
        // baseline from the backup itself — never a reason to suspend.
        if case .loaded(let manifest) = Self.readCanonicalFile(
            BackupManifest.self, at: backupManifestURL, whenUndecodable: .moveAside
        ) {
            backupManifest = manifest
        }
    }

    private var shouldAttemptInitialRestoreOnQueue: Bool {
        !canonicalWritesSuspended
            && !FileManager.default.fileExists(atPath: canonicalInitializedURL.path)
    }

    private enum CanonicalRead<T> {
        case loaded(T)
        case missing
        /// Bytes were readable but not decodable, and the file was moved aside
        /// (`.moveAside` — Health sidecar and backup manifest only).
        case corrupt
        /// Bytes were readable but not decodable (or an orphaned legacy
        /// `.corrupt` file exists), and files were left in place. Never `missing`.
        case undecodable
        /// The file declared a schema version higher than this build supports.
        /// Bytes are always left in place.
        case newerVersion(Int)
        /// The file exists but could not be read (I/O / protection error).
        case unreadable
    }

    private enum UndecodableHandling {
        /// Leave bytes in place so every launch reaches the same diagnosis.
        /// Also treats a lone legacy `<name>.corrupt` quarantine as `.undecodable`.
        case preserveInPlace
        /// Move the file to `<name>.corrupt` so the store can start that file clean.
        case moveAside
    }

    private static func readCanonicalFile<T: Decodable>(
        _ type: T.Type,
        at url: URL,
        expectedFormat: String? = nil,
        whenUndecodable handling: UndecodableHandling
    ) -> CanonicalRead<T> {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            guard handling == .preserveInPlace else { return .missing }
            do {
                _ = try FileManager.default.attributesOfItem(atPath: url.appendingPathExtension("corrupt").path)
                return .undecodable
            } catch let attrError as CocoaError where attrError.code == .fileReadNoSuchFile {
                return .missing
            } catch {
                phoneStoreLogger.error("Failed to inspect quarantine for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return .unreadable
            }
        } catch {
            phoneStoreLogger.error("Failed to read \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .unreadable
        }
        do {
            if let expectedFormat {
                return .loaded(try PersistedArchiveCodec.decode(T.self, from: data, expectedFormat: expectedFormat))
            }
            return .loaded(try JSONDecoder().decode(T.self, from: data))
        } catch let error as PersistedArchiveCodec.CodecError {
            if case .newerSchemaVersion(let version, _) = error {
                phoneStoreLogger.error("File \(url.lastPathComponent, privacy: .public) uses newer schema version \(version, privacy: .public); preserving in place")
                return .newerVersion(version)
            }
            phoneStoreLogger.error("Failed to decode \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            guard handling == .moveAside else { return .undecodable }
            let aside = url.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: url, to: aside)
            return .corrupt
        } catch {
            phoneStoreLogger.error("Failed to decode \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            guard handling == .moveAside else { return .undecodable }
            let aside = url.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: url, to: aside)
            return .corrupt
        }
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        // Until-first-unlock (not complete) protection: WatchConnectivity can
        // launch this app in the background while the phone is locked, and the
        // archive must stay readable there or incoming merges would see an
        // empty store.
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static func excludeFromBackup(_ originalURL: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = originalURL
        try url.setResourceValues(values)
        let applied = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
            .isExcludedFromBackup == true
        guard applied else {
            throw CocoaError(.fileWriteUnknown, userInfo: [
                NSURLErrorKey: originalURL,
                NSLocalizedDescriptionKey: "Backup exclusion was not applied"
            ])
        }
    }

    /// Best-effort privacy fallback after an exclusion failure. Removing the
    /// file is preferred; if that fails, atomically replace it with an empty
    /// projection so no Health values remain eligible for backup.
    private static func discardUnsafeHealthSidecar(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            phoneStoreLogger.fault("Failed to remove unsafe Health sidecar; replacing it with an empty projection: \(error.localizedDescription, privacy: .public)")
            do {
                try write([MatchHealthData](), to: url)
            } catch {
                phoneStoreLogger.fault("Failed to clear unsafe Health sidecar: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    @discardableResult
    private func markArchiveInitializedOnQueue() -> Bool {
        guard !canonicalWritesSuspended else { return false }
        do {
            try FileManager.default.createDirectory(
                at: canonicalDirectoryURL, withIntermediateDirectories: true
            )
            try Self.write(true, to: canonicalInitializedURL)
            return true
        } catch {
            phoneStoreLogger.error("Failed to mark archive initialized: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Newest first with a stable id tiebreak so equal start times never reorder
    /// rows between saves (mirrors `WatchMirror.sortedByRecency`).
    private static func sortedNewestFirst(_ records: [MatchRecord]) -> [MatchRecord] {
        ArchiveBackupPolicy.sortedNewestFirst(records)
    }

    private static func currentICloudIdentityKey() -> String? {
        guard let token = FileManager.default.ubiquityIdentityToken else { return nil }
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            return data.base64EncodedString()
        }
        return String(describing: token)
    }

    // MARK: - Legacy migration (pre-canonical layout)

    private enum LegacyMigrationResult {
        case loaded((records: [MatchRecord], tombstones: Set<UUID>))
        case failed(ArchiveLoadProblem)
    }

    /// Earlier builds could leave a fallback archive in local Documents. Decode
    /// and rewrite it through the new canonical writer — never move it as-is —
    /// so upgraded users get the new until-first-unlock protection class instead
    /// of inheriting the old complete-protection metadata.
    private func migrateLegacyDocumentsArchiveIfNeeded(deleted: [UUID]) -> LegacyMigrationResult {
        let documents = storageConfiguration.legacyDocumentsDirectoryURL
        let legacyHistory = documents.appendingPathComponent(Self.historyFilename)
        let legacyDeletes = documents.appendingPathComponent(Self.tombstoneFilename)
        let historyRead = Self.readCanonicalFile(
            [MatchRecord].self,
            at: legacyHistory,
            expectedFormat: PersistedArchiveCodec.historyFormat,
            whenUndecodable: .preserveInPlace
        )
        let deleteRead = Self.readCanonicalFile(
            [UUID].self,
            at: legacyDeletes,
            expectedFormat: PersistedArchiveCodec.tombstonesFormat,
            whenUndecodable: .preserveInPlace
        )

        var problem: ArchiveLoadProblem?
        let history: [MatchRecord]?
        switch historyRead {
        case .loaded(let value): history = value
        case .missing: history = nil
        case .unreadable: history = nil; problem = ArchiveLoadProblem.unreadable.combined(with: problem)
        case .undecodable, .corrupt: history = nil; problem = ArchiveLoadProblem.undecodable.combined(with: problem)
        case .newerVersion: history = nil; problem = ArchiveLoadProblem.newerVersion.combined(with: problem)
        }
        let legacyIDs: [UUID]?
        switch deleteRead {
        case .loaded(let value): legacyIDs = value
        case .missing: legacyIDs = nil
        case .unreadable: legacyIDs = nil; problem = ArchiveLoadProblem.unreadable.combined(with: problem)
        case .undecodable, .corrupt: legacyIDs = nil; problem = ArchiveLoadProblem.undecodable.combined(with: problem)
        case .newerVersion: legacyIDs = nil; problem = ArchiveLoadProblem.newerVersion.combined(with: problem)
        }
        if let problem { return .failed(problem) }

        let mergedTombstones = Set(deleted).union(legacyIDs ?? [])
        guard history != nil || legacyIDs != nil else {
            return .loaded(([], mergedTombstones))
        }
        let records = Self.sortedNewestFirst((history ?? []).filter { !mergedTombstones.contains($0.id) })
        do {
            try FileManager.default.createDirectory(at: canonicalDirectoryURL, withIntermediateDirectories: true)
            try Self.write(Array(mergedTombstones), to: canonicalTombstoneURL)
            try Self.write(records, to: canonicalHistoryURL)
            try? FileManager.default.removeItem(at: legacyHistory)
            try? FileManager.default.removeItem(at: legacyDeletes)
            phoneStoreLogger.notice("Migrated legacy Documents archive into the canonical store")
            return .loaded((records, mergedTombstones))
        } catch {
            phoneStoreLogger.error("Legacy archive migration write failed: \(error.localizedDescription, privacy: .public)")
            return .failed(.unreadable)
        }
    }

    // MARK: - iCloud backup (push + initial restore)

    private static let backupPushDebounce: TimeInterval = 2
    /// Backoff for "backup exists but iCloud hasn't materialised it locally
    /// yet" (fresh install, or the file was evicted).
    private static let backupRetryDelays: [TimeInterval] = [2, 4, 8, 16]

    /// Sync the iCloud backup. Before the local archive is initialized, this may
    /// restore from iCloud once. After initialization, it only pushes the local
    /// canonical archive outward.
    func syncICloudBackup() {
        queue.async {
            self.pendingBackupSync?.cancel()
            self.pendingBackupSync = nil
            self.syncICloudBackupOnQueue(retriesRemaining: Self.backupRetryDelays.count)
        }
    }

    private func scheduleICloudBackupSyncOnQueue(after delay: TimeInterval, retriesRemaining: Int) {
        pendingBackupSync?.cancel()
        let pass = DispatchWorkItem { [weak self] in
            self?.syncICloudBackupOnQueue(retriesRemaining: retriesRemaining)
        }
        pendingBackupSync = pass
        queue.asyncAfter(deadline: .now() + delay, execute: pass)
    }

    private func syncICloudBackupOnQueue(retriesRemaining: Int) {
        guard !canonicalWritesSuspended else {
            finishRestoreIndicator()
            return
        }
        // May block briefly while the daemon sets the container up — we are on
        // the store's utility queue, never the main thread. nil = signed out /
        // iCloud Drive off; the archive keeps working locally.
        guard let container = storageConfiguration.backupContainerURL() else {
            // Container absent (signed out or iCloud Drive off). Leave the marker absent
            // so the NSUbiquityIdentityDidChange notification triggers a reconcile before
            // the first push when iCloud becomes available.
            finishRestoreIndicator()
            return
        }
        let backupHistoryURL = container.appendingPathComponent(Self.historyFilename)
        let backupTombstoneURL = container.appendingPathComponent(Self.tombstoneFilename)

        if shouldAttemptInitialRestoreOnQueue {
            restoreInitialBackupOnQueue(
                historyURL: backupHistoryURL,
                tombstoneURL: backupTombstoneURL,
                retriesRemaining: retriesRemaining
            )
        } else {
            _ = pushBackupOnQueue(
                historyURL: backupHistoryURL,
                tombstoneURL: backupTombstoneURL,
                retriesRemaining: retriesRemaining
            )
            finishRestoreIndicator()
        }
    }

    private func restoreInitialBackupOnQueue(
        historyURL: URL,
        tombstoneURL: URL,
        retriesRemaining: Int
    ) {
        // If the user has already been shown the restore prompt, don't re-derive.
        guard pendingRestoreDecoded == nil else { return }

        let historyState = backupFileState(at: historyURL)
        let tombstoneState = backupFileState(at: tombstoneURL)
        let ledgerState = backupFileState(at: Self.backupLedgerURL(besides: historyURL))
        // Restore only when ALL files are settled: folding records in while
        // their tombstones (or the forgotten-player ledger) are still
        // downloading could resurrect a deleted match or a forgotten name.
        if historyState.isDownloading || tombstoneState.isDownloading || ledgerState.isDownloading {
            guard retriesRemaining > 0 else {
                phoneStoreLogger.notice("iCloud backup still downloading; deferring to the next trigger")
                finishRestoreIndicator()
                return
            }
            let delay = Self.backupRetryDelays[Self.backupRetryDelays.count - retriesRemaining]
            scheduleICloudBackupSyncOnQueue(after: delay, retriesRemaining: retriesRemaining - 1)
            return
        }

        let decodedRecords = decodeBackup(
            [MatchRecord].self,
            from: historyState,
            expectedFormat: PersistedArchiveCodec.historyFormat
        )
        let decodedTombstones = decodeBackup(
            [UUID].self,
            from: tombstoneState,
            expectedFormat: PersistedArchiveCodec.tombstonesFormat
        )
        let decodedLedger = decodeStrictBackupLedger(from: ledgerState)
        guard decodedRecords.isUsable, decodedTombstones.isUsable, decodedLedger.isUsable else {
            phoneStoreLogger.error("Initial iCloud restore skipped because backup data is corrupt")
            finishRestoreIndicator()
            return
        }

        let backupRecords = decodedRecords.value ?? []
        let backupTombstones = decodedTombstones.value ?? []
        // Missing (an older build's backup) is `nil`: it can never erase the
        // local ledger — `initialRestore` unions it.
        let backupLedger = decodedLedger.value

        if backupRecords.isEmpty {
            // Nothing to restore — reconcile silently and start pushing.
            performRestoreOnQueue(
                backupRecords: backupRecords,
                backupTombstones: backupTombstones,
                backupLedger: backupLedger,
                historyURL: historyURL,
                tombstoneURL: tombstoneURL
            )
            return
        }

        // Non-empty backup: show the restore prompt. Backup pushes stay paused
        // (marker absent) until the user responds so the old backup is preserved.
        pendingRestoreDecoded = (backupRecords, backupTombstones, backupLedger)
        let preview = ArchiveBackupPolicy.BackupPreview.from(records: backupRecords)
        DispatchQueue.main.async {
            self.pendingRestorePreview = preview
        }
        finishRestoreIndicator()
    }

    private func performRestoreOnQueue(
        backupRecords: [MatchRecord],
        backupTombstones: [UUID],
        backupLedger: ForgottenPlayerLedger?,
        historyURL: URL,
        tombstoneURL: URL
    ) {
        let snapshot = ArchiveBackupPolicy.initialRestore(
            localRecords: records,
            localTombstones: tombstones,
            backupRecords: backupRecords,
            backupTombstones: Set(backupTombstones),
            localForgottenPlayers: forgotten,
            backupForgottenPlayers: backupLedger
        )
        guard writeCanonicalOnQueue(
            records: snapshot.records,
            tombstones: snapshot.tombstones,
            forgotten: snapshot.forgottenPlayers
        ), markArchiveInitializedOnQueue() else {
            finishRestoreIndicator()
            return
        }
        records = snapshot.records
        tombstones = snapshot.tombstones
        forgotten = snapshot.forgottenPlayers
        DispatchQueue.main.async { self.pendingRestorePreview = nil }
        publishOnQueue()
        _ = pushBackupOnQueue(historyURL: historyURL, tombstoneURL: tombstoneURL)
        finishRestoreIndicator()
    }

    /// User confirmed the restore prompt: run the restore, mark initialized, push.
    /// `pendingRestorePreview` is cleared only after the write succeeds, inside
    /// `performRestoreOnQueue` — so if the container becomes unavailable mid-flight
    /// the status line stays at "restore pending" rather than dropping to a false
    /// "pending upload".
    func confirmRestore() {
        queue.async { [weak self] in
            guard let self, let decoded = pendingRestoreDecoded else { return }
            pendingRestoreDecoded = nil
            guard let container = storageConfiguration.backupContainerURL() else {
                return
            }
            let historyURL = container.appendingPathComponent(Self.historyFilename)
            let tombstoneURL = container.appendingPathComponent(Self.tombstoneFilename)
            performRestoreOnQueue(
                backupRecords: decoded.records,
                backupTombstones: decoded.tombstones,
                backupLedger: decoded.forgotten,
                historyURL: historyURL,
                tombstoneURL: tombstoneURL
            )
        }
    }

    /// User dismissed the restore prompt ("Not now"): keep all pending state so
    /// the status line continues to show "iCloud backup found — restore pending"
    /// and the user can re-open the prompt by tapping it.
    func declineRestore() {}

    /// The forgotten-player ledger's backup file sits next to the history file
    /// in the ubiquity container (ids only, never names).
    private static func backupLedgerURL(besides historyURL: URL) -> URL {
        historyURL.deletingLastPathComponent().appendingPathComponent(forgottenPlayersFilename)
    }

    /// The exact content the next iCloud push writes: Health stripped, tags
    /// (names, competition) kept, the forgotten-player ledger alongside.
    /// Private notes are not part of `MatchRecord`, so they cannot be here.
    func currentBackupSnapshot() -> ArchiveBackupPolicy.Snapshot {
        queue.sync { backupSnapshotOnQueue() }
    }

    private func backupSnapshotOnQueue() -> ArchiveBackupPolicy.Snapshot {
        ArchiveBackupPolicy.backupSnapshot(records: records, tombstones: tombstones, forgottenPlayers: forgotten)
    }

    private enum PushOutcome {
        case pushed
        case withheld
        case deferred
        case unreadableRemote
        case failed
    }

    private enum RemoteLedgerInspection {
        case write(ForgottenPlayerLedger, needsWrite: Bool)
        case downloading
        case preserveExisting

        var isDownloading: Bool {
            if case .downloading = self { return true }
            return false
        }

        var isPreservingExisting: Bool {
            if case .preserveExisting = self { return true }
            return false
        }
    }

    private enum RemoteTombstoneInspection {
        case ready(existing: Set<UUID>, isMissing: Bool)
        case downloading
        case preserveExisting

        var isDownloading: Bool {
            if case .downloading = self { return true }
            return false
        }

        var isPreservingExisting: Bool {
            if case .preserveExisting = self { return true }
            return false
        }
    }

    private enum BackupBaseline {
        /// nil = no backup has been written yet, so there is nothing to protect.
        case ready(BackupManifest?)
        case downloading
        /// Remote history exists but could not be decoded even as IDs (corrupt
        /// or a future non-array schema). Never treat as empty.
        case unreadableRemote
    }

    /// Pushes the archive through `BackupPushGuard`: a match may leave the
    /// backup only with a tombstone or a confirmed Replace (TECHNICAL_DEBT #18).
    /// Always inspects remote deletion ledgers (`forgottenPlayers.json` and
    /// `deletedMatchIDs.json`) so they are unioned or preserved untouched, and
    /// scopes cached manifests/snapshots to the active iCloud identity key.
    @discardableResult
    private func pushBackupOnQueue(
        historyURL: URL,
        tombstoneURL: URL,
        retriesRemaining: Int = 0,
        overrideBaseline: BackupManifest? = nil
    ) -> PushOutcome {
        let currentIdentityKey = storageConfiguration.backupIdentityKey()
        let outgoing = backupSnapshotOnQueue()
        if overrideBaseline == nil,
           outgoing == lastPushedSnapshot,
           currentIdentityKey == lastPushedIdentityKey {
            if !isBackupWithheldOnQueue {
                readUploadStatusOnQueue(historyURL: historyURL, tombstoneURL: tombstoneURL)
            }
            return isBackupWithheldOnQueue ? .withheld : .pushed
        }
        if currentIdentityKey != lastPushedIdentityKey {
            lastPushedSnapshot = nil
            lastPushedIdentityKey = nil
            if let wb = withheldBaseline, !wb.matchesIdentity(currentIdentityKey) {
                setBackupWithheldOnQueue([], baseline: nil)
            }
        }

        let ledgerURL = Self.backupLedgerURL(besides: historyURL)
        let ledgerInspection = inspectRemoteLedgerOnQueue(merging: outgoing.forgottenPlayers, at: ledgerURL)
        let tombstoneInspection = inspectRemoteTombstonesOnQueue(at: tombstoneURL)

        let baselineResult: BackupBaseline
        if let overrideBaseline, overrideBaseline.matchesIdentity(currentIdentityKey) {
            baselineResult = .ready(overrideBaseline)
        } else if let manifest = backupManifest, manifest.matchesIdentity(currentIdentityKey) {
            baselineResult = .ready(manifest)
        } else {
            let remoteTombstones: Set<UUID>? = {
                if case .ready(let existing, _) = tombstoneInspection { return existing }
                return nil
            }()
            baselineResult = backupBaselineOnQueue(
                historyURL: historyURL,
                remoteTombstones: remoteTombstones,
                tombstoneInspection: tombstoneInspection,
                identityKey: currentIdentityKey
            )
        }

        // Write any readable additive deletion ledgers first, even if history
        // will be deferred or withheld (never overwriting an uninspectable one).
        do {
            if case .write(let mergedLedger, let needsWrite) = ledgerInspection, needsWrite {
                try coordinatedWriteBackup(mergedLedger, to: ledgerURL)
            }
        } catch {
            phoneStoreLogger.error("iCloud backup ledger push failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }

        if ledgerInspection.isDownloading
            || tombstoneInspection.isDownloading
            || { if case .downloading = baselineResult { return true }; return false }() {
            if storageConfiguration.startsICloudSync && retriesRemaining > 0 {
                let delay = Self.backupRetryDelays[Self.backupRetryDelays.count - retriesRemaining]
                scheduleICloudBackupSyncOnQueue(after: delay, retriesRemaining: retriesRemaining - 1)
            }
            phoneStoreLogger.notice("iCloud backup still downloading; deferring the push to the next trigger")
            return .deferred
        }

        if ledgerInspection.isPreservingExisting
            || tombstoneInspection.isPreservingExisting
            || { if case .unreadableRemote = baselineResult { return true }; return false }() {
            // Still push additive tombstones if tombstones themselves are readable.
            if case .ready(let existingTombstones, let isMissing) = tombstoneInspection {
                let mergedTombstones = outgoing.tombstones.union(existingTombstones)
                if isMissing || mergedTombstones != existingTombstones {
                    try? coordinatedWriteBackup(Array(mergedTombstones), to: tombstoneURL)
                }
            }
            phoneStoreLogger.error("Withheld iCloud backup history write: remote backup files could not be inspected cleanly")
            return .unreadableRemote
        }

        guard case .ready(let baseline) = baselineResult,
              case .ready(let remoteTombstones, let tombstonesMissing) = tombstoneInspection else {
            return .unreadableRemote
        }

        do {
            switch BackupPushGuard.decision(
                outgoing: outgoing,
                baseline: baseline,
                remoteTombstones: remoteTombstones
            ) {
            case .push(let snapshot):
                // Tombstones before history: safe for both deletions and
                // re-imports if a crash occurs between the two writes.
                if tombstonesMissing || snapshot.tombstones != remoteTombstones {
                    try coordinatedWriteBackup(Array(snapshot.tombstones), to: tombstoneURL)
                }
                try coordinatedWriteBackup(snapshot.records, to: historyURL)
                recordBackupManifestOnQueue(BackupManifest(pushed: snapshot, identityKey: currentIdentityKey))
                setBackupWithheldOnQueue([], baseline: nil)
                lastPushedSnapshot = outgoing
                lastPushedIdentityKey = currentIdentityKey
                readUploadStatusOnQueue(historyURL: historyURL, tombstoneURL: tombstoneURL)
                return .pushed
            case .withholdRecords(let snapshot, let unexplained):
                if tombstonesMissing || snapshot.tombstones != remoteTombstones {
                    try coordinatedWriteBackup(Array(snapshot.tombstones), to: tombstoneURL)
                }
                phoneStoreLogger.fault("iCloud backup kept: \(unexplained.count, privacy: .public) match(es) would leave it with no deletion or Replace to explain it")
                setBackupWithheldOnQueue(unexplained, baseline: baseline)
                lastPushedSnapshot = outgoing
                lastPushedIdentityKey = currentIdentityKey
                return .withheld
            }
        } catch {
            // Push failures are recoverable: the canonical archive is safe
            // on-device and the next trigger retries the same content.
            phoneStoreLogger.error("iCloud backup push failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    private func inspectRemoteLedgerOnQueue(
        merging local: ForgottenPlayerLedger,
        at url: URL
    ) -> RemoteLedgerInspection {
        switch backupFileState(at: url) {
        case .missing:
            return .write(local, needsWrite: true)
        case .downloading:
            return .downloading
        case .ready(let data):
            guard case .loaded(let existing) = decodeStrictBackupLedger(from: .ready(data)) else {
                phoneStoreLogger.error("Preserving iCloud backup forgotten-player ledger: remote file is unreadable or unsupported")
                return .preserveExisting
            }
            let merged = local.union(existing)
            return .write(merged, needsWrite: merged != existing)
        }
    }

    private func inspectRemoteTombstonesOnQueue(at url: URL) -> RemoteTombstoneInspection {
        switch backupFileState(at: url) {
        case .missing:
            return .ready(existing: [], isMissing: true)
        case .downloading:
            return .downloading
        case .ready(let data):
            switch decodeBackup([UUID].self, from: .ready(data), expectedFormat: PersistedArchiveCodec.tombstonesFormat) {
            case .loaded(let existing):
                return .ready(existing: Set(existing), isMissing: false)
            case .missing:
                return .ready(existing: [], isMissing: true)
            case .corrupt:
                phoneStoreLogger.error("Preserving iCloud backup tombstones: remote file could not be decoded")
                return .preserveExisting
            }
        }
    }

    /// Reads the ids already in the backup when this iPhone has no matching
    /// manifest (first push after updating, after recovery, or after switching
    /// iCloud accounts). Records decode as ids only (`BackupRecordID`), so a
    /// backup with unknown enum cases is still protected; a corrupt or
    /// non-array/future-envelope remote history fails closed (`.unreadableRemote`)
    /// rather than masquerading as empty.
    private func backupBaselineOnQueue(
        historyURL: URL,
        remoteTombstones: Set<UUID>?,
        tombstoneInspection: RemoteTombstoneInspection,
        identityKey: String?
    ) -> BackupBaseline {
        if tombstoneInspection.isDownloading { return .downloading }
        let historyState = backupFileState(at: historyURL)
        switch historyState {
        case .downloading:
            return .downloading
        case .missing:
            if let remoteTombstones, !remoteTombstones.isEmpty {
                return .ready(BackupManifest(recordIDs: [], tombstones: remoteTombstones, identityKey: identityKey))
            }
            return .ready(nil)
        case .ready:
            switch decodeBackup([BackupRecordID].self, from: historyState, expectedFormat: PersistedArchiveCodec.historyFormat) {
            case .loaded(let ids):
                return .ready(BackupManifest(
                    recordIDs: Set(ids.map(\.id)),
                    tombstones: remoteTombstones ?? [],
                    identityKey: identityKey
                ))
            case .missing:
                return .ready(nil)
            case .corrupt:
                return .unreadableRemote
            }
        }
    }

    /// Remembers the new baseline in memory and on disk. A failed write only
    /// means the next launch reads the baseline from the backup instead.
    private func recordBackupManifestOnQueue(_ manifest: BackupManifest) {
        backupManifest = manifest
        do {
            try FileManager.default.createDirectory(at: canonicalDirectoryURL, withIntermediateDirectories: true)
            try Self.write(manifest, to: backupManifestURL)
        } catch {
            phoneStoreLogger.error("Failed to save the backup manifest: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func clearBackupManifestOnQueue() {
        backupManifest = nil
        try? FileManager.default.removeItem(at: backupManifestURL)
    }

    private func setBackupWithheldOnQueue(_ ids: Set<UUID>, baseline: BackupManifest?) {
        withheldBaseline = ids.isEmpty ? nil : baseline
        guard ids != withheldMatchIDs else { return }
        withheldMatchIDs = ids
        let count = ids.count
        DispatchQueue.main.async { self.withheldBackupMatchCount = count }
    }

    /// Reads `.ubiquitousItemIsUploadedKey` on both backup files and publishes the
    /// result. `true` only when both files confirm uploaded; `false` when either is
    /// still uploading; `nil` is never written here (it stays nil until the first
    /// successful push, at which point the read returns true or false).
    private func readUploadStatusOnQueue(historyURL: URL, tombstoneURL: URL) {
        let keys: Set<URLResourceKey> = [.ubiquitousItemIsUploadedKey]
        let historyUploaded = (try? historyURL.resourceValues(forKeys: keys))?.ubiquitousItemIsUploaded ?? false
        let tombstoneUploaded = (try? tombstoneURL.resourceValues(forKeys: keys))?.ubiquitousItemIsUploaded ?? false
        let uploaded = historyUploaded && tombstoneUploaded
        DispatchQueue.main.async {
            self.isBackupUploaded = uploaded
        }
    }

    private enum DecodedBackup<T> {
        case loaded(T)
        case missing
        case corrupt

        var value: T? {
            if case .loaded(let value) = self { return value }
            return nil
        }

        var isUsable: Bool {
            if case .corrupt = self { return false }
            return true
        }
    }

    private func decodeBackup<T: Decodable>(
        _ type: T.Type,
        from state: BackupFileState,
        expectedFormat: String? = nil
    ) -> DecodedBackup<T> {
        guard case .ready(let data) = state else { return .missing }
        do {
            if let expectedFormat {
                return .loaded(try PersistedArchiveCodec.decode(T.self, from: data, expectedFormat: expectedFormat))
            }
            return .loaded(try JSONDecoder().decode(T.self, from: data))
        } catch {
            phoneStoreLogger.error("iCloud backup decode failed: \(error.localizedDescription, privacy: .public)")
            return .corrupt
        }
    }

    private func decodeStrictBackupLedger(from state: BackupFileState) -> DecodedBackup<ForgottenPlayerLedger> {
        guard case .ready(let data) = state else { return .missing }
        do {
            let stored = try JSONDecoder().decode(StoredForgottenPlayers.self, from: data)
            return .loaded(stored.ledger)
        } catch {
            phoneStoreLogger.error("iCloud backup ledger decode failed: \(error.localizedDescription, privacy: .public)")
            return .corrupt
        }
    }

    private enum BackupFileState {
        case ready(Data)
        case missing
        case downloading

        var isDownloading: Bool {
            if case .downloading = self { return true }
            return false
        }
    }

    /// Reads a backup file without ever conflating "not materialised yet" with
    /// "empty": a file that exists logically but is not on disk (placeholder /
    /// evicted) starts downloading and reports `.downloading` so callers retry
    /// instead of restoring against nothing.
    private func backupFileState(at url: URL) -> BackupFileState {
        if FileManager.default.fileExists(atPath: url.path) {
            if let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
               let status = values.ubiquitousItemDownloadingStatus,
               status != .current {
                do {
                    try FileManager.default.startDownloadingUbiquitousItem(at: url)
                } catch {
                    phoneStoreLogger.error("Failed to start iCloud backup download for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
                return .downloading
            }
            do {
                return .ready(try coordinatedRead(at: url))
            } catch {
                phoneStoreLogger.error("iCloud backup read failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                return .downloading // transient; retry path handles it
            }
        }
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            return .downloading
        } catch {
            // Nothing to download — the backup has never been written.
            return .missing
        }
    }

    // NSFileCoordinator keeps reads/writes consistent with the iCloud daemon's
    // own access to the container. Only invoked for files that exist locally
    // (see `backupFileState`), so coordination cannot block on a download.

    private func coordinatedRead(at url: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: url, options: [], error: &coordinationError
        ) { actualURL in
            result = Result { try Data(contentsOf: actualURL) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    private func coordinatedWriteBackup<T: Encodable>(_ value: T, to url: URL) throws {
        var coordinationError: NSError?
        var writeResult: Result<Void, Error> = .success(())
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: url, options: .forReplacing, error: &coordinationError
        ) { actualURL in
            writeResult = Result { try Self.write(value, to: actualURL) }
        }
        if let coordinationError { throw coordinationError }
        try writeResult.get()
    }

    private func finishRestoreIndicator() {
        DispatchQueue.main.async {
            if self.isRestoringFromICloud {
                self.isRestoringFromICloud = false
            }
        }
    }
}
