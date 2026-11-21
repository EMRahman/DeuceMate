// PhoneStatsStore.swift — StatsStoring implementation for the iPhone target.
// No historyCap — the phone is a durable archive that keeps everything.
//
// Storage model (canonical + backup):
//   • CANONICAL — device-local JSON (health-stripped history + tombstones) in
//     Application Support. Always readable at launch: no iCloud daemon, no
//     network, never evicted by storage optimisation, and protected only until
//     first unlock so background WatchConnectivity launches can read it. The
//     UI renders from this, unconditionally.
//   • HEALTH SIDECAR — a device-local, backup-excluded JSON projection holding
//     only the five HealthKit-derived fields. It is merged into history in memory.
//   • ICLOUD BACKUP — the same two files in the iCloud Drive ubiquity container,
//     pushed in the background (debounced) after local saves. iCloud is only
//     read during initial local-archive setup; once initialized, it never pulls
//     back into the phone archive. Its availability never gates the UI.
//
// Initial restore rules are pure and live in Core (`ArchiveBackupPolicy`).
// Tombstones are backed up alongside records, so a fresh-install restore does
// not resurrect deleted matches. A read or decode failure is never treated as
// an empty archive: the file stays in place, writes and iCloud pushes derived
// from it are suppressed so they can't clobber data, and `archiveProblem`
// tells the user (TECHNICAL_DEBT #18).
//
// Match tags (opponent / partner names, competition type — MATCH_TAGS_PLAN.md)
// ride on `MatchRecord` and therefore live in the canonical archive and its
// iCloud copy. Every path that replaces a record carries its stored tags
// forward by their own clock (`MatchRecord.mergingTags`). The forgotten-player
// ledger (`forgottenPlayers.json`, player ids only, never names) is persisted
// and backed up next to the tombstones, and every inbound path — watch merge,
// "Sync to iPhone", manual import (both modes) and the initial iCloud restore
// — scrubs forgotten players before anything is adopted. Private notes are NOT
// here: they live in the separate backup-excluded `MatchNotesStore`.
//
// `archiveInitialized.json` means the local archive and iCloud backup have
// been reconciled at least once. Only `syncICloudBackupOnQueue` writes it
// (after a successful `initialRestore`). `adoptOnQueue` never writes it, so
// a local write can never foreclose the initial restore.
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
    /// Non-nil when a canonical archive file (history, tombstones or the
    /// forgotten-player ledger) exists but could not be read or decoded at
    /// launch. Writes and iCloud pushes are then suspended for the process and
    /// the archive screen explains why the list looks empty (TECHNICAL_DEBT #18).
    @Published private(set) var archiveProblem: ArchiveLoadProblem? = nil
    /// How many matches the last backup push kept in the backup because they
    /// had left this iPhone with no tombstone or confirmed Replace to explain
    /// it (`BackupPushGuard`, TECHNICAL_DEBT #18); 0 when nothing is withheld.
    /// The archive screen then offers Bring Them Back / Remove from Backup.
    @Published private(set) var withheldBackupMatchCount = 0
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
    /// Set when a canonical file exists but could not be used at launch: an
    /// I/O or protection error (`.unreadable`), or bytes that do not decode
    /// (`.undecodable` — damaged, or written by a newer build). Neither is
    /// "missing". All disk writes and backup passes are then suppressed for the
    /// rest of the process so state derived from a failed read can never
    /// overwrite the real archive or its iCloud copy; the app keeps working in
    /// memory. The file stays in place, so the next launch either loads it or
    /// reaches the same diagnosis — never a silently empty archive.
    private var canonicalSuspension: ArchiveLoadProblem?
    private var canonicalWritesSuspended: Bool { canonicalSuspension != nil }
    /// The scheduled debounced backup push or restore download-retry, if any.
    private var pendingBackupSync: DispatchWorkItem?
    /// Last outgoing content a push handled (pushed, or withheld by the guard);
    /// nil before the first push. Used to skip redundant iCloud writes when
    /// nothing has changed.
    private var lastPushedSnapshot: ArchiveBackupPolicy.Snapshot?
    /// What this iPhone last pushed in full (`backupManifest.json`): the
    /// baseline `BackupPushGuard` checks every push against. nil when it has
    /// never been written or can't be read; the push then reads the ids
    /// already in the backup instead.
    private var backupManifest: BackupManifest?
    /// The matches the last push withheld, and the baseline it compared
    /// against; empty / nil when nothing is withheld. `withheldBackupMatchCount`
    /// mirrors the count on main.
    private var withheldMatchIDs: Set<UUID> = []
    private var withheldBaseline: BackupManifest?
    private var isBackupWithheldOnQueue: Bool { !withheldMatchIDs.isEmpty }
    /// The ubiquity identity token at the time of the last successful push.
    /// A different token means a different iCloud account — we must push even if content is unchanged.
    private var lastPushedIdentityToken: AnyHashable?
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
        /// Production asks for the ubiquity container (this may block briefly,
        /// so it is only called on the store queue). Tests pass a local folder
        /// so the real push path can run without iCloud.
        let backupContainerURL: () -> URL?

        init(
            canonicalDirectoryURL: URL,
            legacyDocumentsDirectoryURL: URL,
            startsICloudSync: Bool,
            backupExcluder: ((URL) throws -> Void)? = nil,
            backupContainerURL: (() -> URL?)? = nil
        ) {
            self.canonicalDirectoryURL = canonicalDirectoryURL
            self.legacyDocumentsDirectoryURL = legacyDocumentsDirectoryURL
            self.startsICloudSync = startsICloudSync
            self.backupExcluder = backupExcluder ?? { try PhoneStatsStore.excludeFromBackup($0) }
            self.backupContainerURL = backupContainerURL
                ?? { FileManager.default.url(forUbiquityContainerIdentifier: nil) }
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
            migrateLegacyDocumentsArchiveIfNeeded()
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
        queue.sync {
            var updated = records
            let prior = updated.first(where: { $0.id == record.id })
            updated.removeAll { $0.id == record.id }
            let merged = record
                .mergingResumeEvents(prior?.resumeEvents ?? [])
                .mergingTags(prior?.tags)
                .mergingMatchTypeRevision(prior?.matchTypeRevision)
            updated.append(forgotten.scrubbed(merged, now: Date()))
            adoptOnQueue(records: updated, tombstones: tombstones)
        }
    }

    /// Pull a watch-only match into the durable archive ("Sync to iPhone"). A
    /// permanently deleted match (tombstoned) is never resurrected: a stale
    /// watch-mirror row can surface it in the window before the queued watch
    /// delete lands, so we keep the tombstone and skip the add. A stale copy
    /// can also carry a forgotten player, so it is scrubbed first.
    func syncToPhone(_ record: MatchRecord) {
        queue.sync {
            guard !tombstones.contains(record.id),
                  !records.contains(where: { $0.id == record.id }) else { return }
            adoptOnQueue(records: records + [forgotten.scrubbed(record, now: Date())], tombstones: tombstones)
        }
    }

    /// Permanently delete a match from the iPhone: drop the record and tombstone
    /// the id so neither a later watch sync nor an iCloud restore can re-import
    /// it. Callers separately issue a watch-side delete when the match is also
    /// on the watch, so "permanent" means gone everywhere, and remove the
    /// match's private notes from `MatchNotesStore`.
    func deletePermanently(id: UUID) {
        queue.sync {
            var updatedTombstones = tombstones
            updatedTombstones.insert(id)
            adoptOnQueue(
                records: records.filter { $0.id != id },
                tombstones: updatedTombstones
            )
        }
    }

    /// `StatsStoring` conformance. On the phone the protocol's "remove" is a true,
    /// permanent deletion (matching the watch's destructive `removeMatch`). Freeing
    /// watch space without discarding the archive copy is a watch-side delete issued
    /// via `PhoneMatchSyncService.sendDeleteMatchOnWatch(_:)`, not a store operation.
    func removeMatch(id: UUID) { deletePermanently(id: id) }

    // MARK: - Match tags (MATCH_TAGS_PLAN.md §4–§6)

    /// Why a user edit of match details or the player roster did not happen.
    /// Shared by `updateTags`, the Players actions (rename, merge, forget) and
    /// manual archive import (`.notPersisted` only).
    enum TagEditError: LocalizedError, Equatable {
        case matchNotFound
        case matchInProgress
        /// The canonical archive (or the forgotten-player ledger) could not be
        /// written — storage failed, or writes are suspended after an
        /// unreadable or undecodable launch read (`archiveProblem`). The edit was rolled back in memory, so
        /// nothing changed and nothing may be pushed to the watch.
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
    /// copy arriving later is scrubbed. Returns the changed match ids (the
    /// caller pushes their tags to the watch) only once the ledger and the
    /// archive are both on disk; otherwise throws `TagEditError.notPersisted`
    /// with the in-memory archive and ledger unchanged, so the player still
    /// shows — exactly what a relaunch would load.
    @discardableResult
    func forgetPlayer(_ playerID: UUID, now: Date = Date()) throws -> Set<UUID> {
        try queue.sync {
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
            let mutation = mutate(records)
            guard !mutation.affectedMatchIDs.isEmpty else { return [] }
            try commitUserEditOnQueue(records: mutation.records)
            return mutation.affectedMatchIDs
        }
    }

    /// Adopts a user-initiated edit all-or-nothing. Background paths (watch
    /// merges, imports) keep their in-memory result when a write fails so the
    /// session stays usable; an edit the user is waiting on must instead
    /// report failure honestly. If the canonical files were not all written
    /// (storage error, or writes suspended after an unreadable launch read),
    /// the previous archive and ledger are restored and republished and
    /// `TagEditError.notPersisted` is thrown, so the UI shows exactly what a
    /// relaunch would load and the caller never pushes the edit to the watch.
    /// (`writeCanonicalOnQueue` writes the ledger first, so a `forget` that
    /// fails part-way may still take effect at the next launch — the safe
    /// direction — but success is never reported for one that isn't durable.)
    private func commitUserEditOnQueue(
        records newRecords: [MatchRecord],
        forgotten newForgotten: ForgottenPlayerLedger? = nil
    ) throws {
        let previousRecords = records
        let previousForgotten = forgotten
        guard adoptOnQueue(records: newRecords, tombstones: tombstones, forgotten: newForgotten) else {
            records = previousRecords
            forgotten = previousForgotten
            publishOnQueue()
            throw TagEditError.notPersisted
        }
    }

    // MARK: - Manual archive export/import

    /// Full-fidelity archive (names included) plus the forgotten-player ledger,
    /// so a restore elsewhere keeps deletion intent. Private notes are written
    /// ONLY when the caller passes `notes` (the user's separate, default-off
    /// "Include private notes" opt-in); `nil` omits the section entirely.
    func exportManualArchiveData(notes: [MatchNote]? = nil) throws -> Data {
        try queue.sync {
            try ManualMatchArchiveBackup.encode(
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

        // All-or-nothing, like a user edit: an import that only lived in memory
        // (writes suspended after an unusable launch read, or a failed write)
        // would vanish on relaunch, so it is rolled back and reported instead
        // of claimed as success — and the caller leaves private notes alone.
        try queue.sync {
            // A confirmed Replace is a way out of a suspended archive: the
            // preserved files are copied aside first, then replaced. A Merge
            // into an archive that couldn't be loaded would hide that the
            // damaged matches aren't in it, so it stays refused.
            let suspension = mode == .replace ? canonicalSuspension : nil
            if suspension != nil {
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
                tombstones: tombstones,
                mode: mode,
                currentForgottenPlayers: forgotten,
                importedForgottenPlayers: archive.forgottenPlayers
            )
            let previousRecords = records
            let previousTombstones = tombstones
            let previousForgotten = forgotten
            guard adoptOnQueue(
                records: snapshot.records,
                tombstones: snapshot.tombstones,
                forgotten: snapshot.forgottenPlayers
            ) else {
                records = previousRecords
                tombstones = previousTombstones
                forgotten = previousForgotten
                canonicalSuspension = suspension ?? canonicalSuspension
                publishOnQueue()
                throw TagEditError.notPersisted
            }
            if suspension != nil {
                publishArchiveProblemOnQueue()
            }
            if mode == .replace {
                // The user confirmed replacing the archive, so the backup may
                // now drop what the file didn't contain. Without this the push
                // guard would keep the replaced matches in the backup forever.
                recordBackupManifestOnQueue(BackupManifest(
                    recordIDs: Set(records.map(\.id)),
                    tombstones: tombstones
                ))
            }
        }
        return preview
    }

    // MARK: - Recovery (TECHNICAL_DEBT #18, stage 3)
    //
    // The ways out of a suspended archive and a withheld backup push. Each one
    // that replaces something copies it first: the preserved archive files go
    // to `MatchArchive/Recovered/<time>/`, and so does the backup's record file
    // before "Remove from Backup" lets matches leave it. Nothing is deleted.

    enum RecoveryError: Error, Equatable {
        /// The canonical files couldn't be written; nothing changed.
        case notPersisted
        /// iCloud is unavailable, still downloading, or the backup unreadable.
        case backupUnavailable
        /// None of the withheld matches could be read from the backup.
        case nothingReadable
    }

    /// Reads the canonical files again ("Try Again"). Anything that arrived
    /// while writes were suspended (Watch syncs, deletions) is kept on top of
    /// what loads. Returns the problem that remains, nil when the archive is
    /// back to normal and saving again.
    func retryArchiveLoad() async -> ArchiveLoadProblem? {
        await onQueue { self.retryArchiveLoadOnQueue() }
    }

    /// Copies the preserved archive files ("Save a Copy") into a fresh
    /// temporary folder for the share sheet. The originals stay in place.
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

    /// Restores a suspended archive from the iCloud backup, on top of whatever
    /// this iPhone holds in memory (`ArchiveBackupPolicy.initialRestore`), with
    /// Health values from the local sidecar put back. Returns how many matches
    /// the archive then holds.
    func restoreArchiveFromICloud() async throws -> Int {
        try await onQueueThrowing { () throws -> Int in
            guard case .loaded(let backup) = self.readFullBackupOnQueue(),
                  !backup.records.records.isEmpty else {
                throw RecoveryError.backupUnavailable
            }
            let snapshot = ArchiveBackupPolicy.initialRestore(
                localRecords: self.records,
                localTombstones: self.tombstones,
                backupRecords: backup.records.records,
                backupTombstones: backup.tombstones,
                localForgottenPlayers: self.forgotten,
                backupForgottenPlayers: backup.forgotten
            )
            let restored = HealthSidecarPolicy.merge(stripped: snapshot.records, health: self.localHealthSidecarOnQueue())
            try self.replaceSuspendedArchiveOnQueue(
                records: restored,
                tombstones: snapshot.tombstones,
                forgotten: snapshot.forgottenPlayers
            )
            self.markArchiveInitializedOnQueue()
            return self.records.count
        }
    }

    /// "Bring Them Back": copies the withheld matches from the backup into the
    /// archive and pushes again. Returns how many came back and how many this
    /// build couldn't read (those stay withheld, so the backup keeps them).
    func bringBackWithheldMatches() async throws -> (restored: Int, stillMissing: Int) {
        try await onQueueThrowing { () throws -> (restored: Int, stillMissing: Int) in
            let wanted = self.withheldMatchIDs
            guard !wanted.isEmpty else { return (0, 0) }
            guard let container = self.storageConfiguration.backupContainerURL() else {
                throw RecoveryError.backupUnavailable
            }
            let historyURL = container.appendingPathComponent(Self.historyFilename)
            let tombstoneURL = container.appendingPathComponent(Self.tombstoneFilename)
            guard case .loaded(let list) = self.decodeBackup(LenientRecordList.self, from: self.backupFileState(at: historyURL)) else {
                throw RecoveryError.backupUnavailable
            }
            let found = list.records.filter { wanted.contains($0.id) }
            guard !found.isEmpty else { throw RecoveryError.nothingReadable }
            let merged = MatchMergePolicy.merge(
                incoming: found,
                into: self.records,
                tombstones: self.tombstones,
                forgottenPlayers: self.forgotten
            )
            let previous = self.records
            guard self.adoptOnQueue(records: merged, tombstones: self.tombstones) else {
                self.records = previous
                self.publishOnQueue()
                throw RecoveryError.notPersisted
            }
            self.pushNowOnQueue(historyURL: historyURL, tombstoneURL: tombstoneURL)
            return (found.count, wanted.count - found.count)
        }
    }

    /// "Remove from Backup": the user accepts that the withheld matches leave
    /// the backup. The backup's record file is copied to this iPhone first,
    /// then only those ids stop being protected (`acceptingLoss`).
    func removeWithheldMatchesFromBackup() async throws {
        try await onQueueThrowing {
            let accepted = self.withheldMatchIDs
            guard !accepted.isEmpty, let baseline = self.withheldBaseline else { return }
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
            self.recordBackupManifestOnQueue(baseline.acceptingLoss(of: accepted))
            self.pushNowOnQueue(historyURL: historyURL, tombstoneURL: tombstoneURL)
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
        let heldRecords = records
        let heldTombstones = tombstones
        let heldForgotten = forgotten
        canonicalSuspension = nil
        records = []
        tombstones = []
        forgotten = ForgottenPlayerLedger()
        loadCanonicalOnQueue()

        tombstones.formUnion(heldTombstones)
        forgotten = forgotten.union(heldForgotten)
        let loaded = forgotten.scrubbed(records.filter { !tombstones.contains($0.id) }, now: Date())
        let combined = MatchMergePolicy.merge(
            incoming: heldRecords,
            into: loaded,
            tombstones: tombstones,
            forgottenPlayers: forgotten
        )
        if canonicalSuspension == nil {
            adoptOnQueue(records: combined, tombstones: tombstones)
        } else {
            records = Self.sortedNewestFirst(combined)
            publishOnQueue()
        }
        publishArchiveProblemOnQueue()
        return canonicalSuspension
    }

    /// Adopts a replacement for a suspended archive: copies the preserved
    /// files aside, lifts the suspension and writes. On any failure the
    /// suspension and the in-memory archive are put back.
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
        let previous = (records, tombstones, forgotten)
        canonicalSuspension = nil
        guard adoptOnQueue(records: newRecords, tombstones: newTombstones, forgotten: newForgotten) else {
            (records, tombstones, forgotten) = previous
            canonicalSuspension = suspension
            publishOnQueue()
            throw RecoveryError.notPersisted
        }
        publishArchiveProblemOnQueue()
    }

    private func publishArchiveProblemOnQueue() {
        let problem = canonicalSuspension
        DispatchQueue.main.async { self.archiveProblem = problem }
    }

    /// The score-bearing canonical files that exist (history, tombstones,
    /// forgotten-player ledger). The Health sidecar is never copied: it must
    /// stay backup-excluded, and recovery merges it back instead.
    private var preservedFileURLs: [URL] {
        [canonicalHistoryURL, canonicalTombstoneURL, canonicalForgottenPlayersURL]
            .filter { FileManager.default.fileExists(atPath: $0.path) }
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
        let records = decodeBackup(LenientRecordList.self, from: historyState)
        let tombstones = decodeBackup([UUID].self, from: tombstoneState)
        let ledger = decodeBackup(ForgottenPlayerLedger.self, from: ledgerState)
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
    private func pushNowOnQueue(historyURL: URL, tombstoneURL: URL) {
        pendingBackupSync?.cancel()
        pendingBackupSync = nil
        guard !canonicalWritesSuspended, !shouldAttemptInitialRestoreOnQueue else { return }
        lastPushedSnapshot = nil
        pushBackupOnQueue(historyURL: historyURL, tombstoneURL: tombstoneURL)
    }

    // MARK: - Merge incoming records from WatchConnectivity

    /// Merges watch records (tags by their own clock, forgotten players
    /// scrubbed) and returns the resulting archive, which the sync service
    /// feeds to §6.1 reconciliation (`MatchTags.pendingWatchUpdates`).
    @discardableResult
    func mergeIncoming(_ incoming: [MatchRecord]) -> [MatchRecord] {
        queue.sync {
            let merged = MatchMergePolicy.merge(
                incoming: incoming,
                into: records,
                tombstones: tombstones,
                forgottenPlayers: forgotten
            )
            adoptOnQueue(records: merged, tombstones: tombstones)
            return records
        }
    }

    @discardableResult
    func mergeIncoming(_ record: MatchRecord) -> [MatchRecord] {
        mergeIncoming([record])
    }

    // MARK: - Canonical store (device-local source of truth)

    /// Adopt new state as the canonical archive: persist it, publish it, and
    /// schedule a debounced iCloud backup sync. The single funnel for every
    /// mutation. `forgotten` nil keeps the current ledger (it only ever grows).
    /// Returns whether the canonical files were written.
    @discardableResult
    private func adoptOnQueue(
        records newRecords: [MatchRecord],
        tombstones newTombstones: Set<UUID>,
        forgotten newForgotten: ForgottenPlayerLedger? = nil
    ) -> Bool {
        records = Self.sortedNewestFirst(newRecords)
        tombstones = newTombstones
        if let newForgotten { forgotten = forgotten.union(newForgotten) }
        let didWrite = writeCanonicalOnQueue()
        publishOnQueue()
        guard didWrite else {
            // During the initial restore phase the pending item is a restore
            // retry (reading from iCloud, not pushing to it) — leave it running.
            // Only cancel in steady state, where the pending item would push
            // current in-memory state that never reached disk.
            if !shouldAttemptInitialRestoreOnQueue {
                pendingBackupSync?.cancel()
                pendingBackupSync = nil
            }
            return false
        }
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
    private func writeCanonicalOnQueue() -> Bool {
        guard !canonicalWritesSuspended else { return false }
        do {
            let split = HealthSidecarPolicy.split(records)
            try FileManager.default.createDirectory(
                at: canonicalDirectoryURL, withIntermediateDirectories: true
            )
            // Deletion intent first: if the process dies before the archive is
            // rewritten, the next launch still scrubs the forgotten player
            // from the older archive (see `loadCanonicalOnQueue`).
            try Self.write(forgotten, to: canonicalForgottenPlayersURL)
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

            // Sidecar first during the normal path: a process interruption can
            // leave an older stripped main paired with newer Health values. The
            // exclusion-failure path above deliberately prefers a durable,
            // stripped main even though its local Health projection is dropped.
            try Self.write(split.stripped, to: canonicalHistoryURL)
            try Self.write(Array(tombstones), to: canonicalTombstoneURL)
            return true
        } catch {
            phoneStoreLogger.error("Failed to write canonical archive: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Records why canonical writes stop, keeping the more persistent reason
    /// when several files fail.
    private func suspendCanonicalWrites(_ problem: ArchiveLoadProblem) {
        canonicalSuspension = problem.combined(with: canonicalSuspension)
    }

    private func loadCanonicalOnQueue() {
        // Score-bearing files fail closed: a file that exists but can't be used
        // is preserved in place and suspends writes. Deleting or moving it here
        // would make the next launch see "missing" and write an empty archive
        // over the iCloud backup (TECHNICAL_DEBT #18).
        switch Self.readCanonicalFile([UUID].self, at: canonicalTombstoneURL, whenUndecodable: .preserveInPlace) {
        case .loaded(let ids):
            tombstones = Set(ids)
        case .missing:
            break
        case .unreadable:
            suspendCanonicalWrites(.unreadable)
        case .undecodable, .corrupt:
            // Losing tombstones would resurrect deleted matches.
            suspendCanonicalWrites(.undecodable)
        }
        switch Self.readCanonicalFile(ForgottenPlayerLedger.self, at: canonicalForgottenPlayersURL, whenUndecodable: .preserveInPlace) {
        case .loaded(let ledger):
            forgotten = ledger
        case .missing:
            break // pre-tags archive; the archive itself was scrubbed when each forget ran
        case .unreadable:
            suspendCanonicalWrites(.unreadable)
        case .undecodable, .corrupt:
            // Losing the ledger would drop the user's deletion intent.
            suspendCanonicalWrites(.undecodable)
        }
        let loadedRecords: [MatchRecord]
        switch Self.readCanonicalFile([MatchRecord].self, at: canonicalHistoryURL, whenUndecodable: .preserveInPlace) {
        case .loaded(let loaded):
            loadedRecords = loaded
        case .missing:
            loadedRecords = []
        case .unreadable:
            suspendCanonicalWrites(.unreadable)
            loadedRecords = []
        case .undecodable, .corrupt:
            suspendCanonicalWrites(.undecodable)
            loadedRecords = []
        }

        // Reassert the file flag before a corrupt sidecar can be moved to a
        // recovery file. The moved quarantine copy still contains Health data.
        if FileManager.default.fileExists(atPath: healthSidecarURL.path) {
            do {
                try storageConfiguration.backupExcluder(healthSidecarURL)
            } catch {
                phoneStoreLogger.error("Failed to reapply Health sidecar backup exclusion: \(error.localizedDescription, privacy: .public)")
            }
        }
        // The Health sidecar is a reconstructable projection, not score-bearing
        // data: a damaged one is moved aside and the archive keeps working.
        let health: [MatchHealthData]
        switch Self.readCanonicalFile([MatchHealthData].self, at: healthSidecarURL, whenUndecodable: .moveAside) {
        case .loaded(let loaded):
            health = loaded
        case .missing, .corrupt, .undecodable, .unreadable:
            health = []
        }

        let loadedHadHealth = !HealthSidecarPolicy.split(loadedRecords).health.isEmpty
        let merged = HealthSidecarPolicy.merge(stripped: loadedRecords, health: health)
        // The ledger is written before the archive, so an interrupted forget
        // can leave an older archive still naming the player; finish it here.
        let scrubbed = forgotten.scrubbed(merged, now: Date())
        let neededScrub = scrubbed != merged
        records = Self.sortedNewestFirst(scrubbed)

        // The pre-sidecar canonical file was full-fidelity. Content detection is
        // the migration marker: once rewritten successfully, the main file has
        // no Health fields and this path never runs again.
        if (loadedHadHealth || neededScrub) && !canonicalWritesSuspended {
            if writeCanonicalOnQueue() {
                phoneStoreLogger.notice("Migrated canonical archive to the backup-excluded Health sidecar")
            }
        }
        // A missing or unreadable manifest only means the next push reads its
        // baseline from the backup itself — never a reason to suspend.
        if case .loaded(let manifest) = Self.readCanonicalFile(
            BackupManifest.self, at: backupManifestURL, whenUndecodable: .moveAside
        ) {
            backupManifest = manifest
        }
        if let canonicalSuspension {
            phoneStoreLogger.error("Canonical archive \(canonicalSuspension.rawValue, privacy: .public); file preserved, running in-memory with writes and iCloud backup suspended")
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
        /// (`.moveAside` — the reconstructable Health sidecar only).
        case corrupt
        /// Bytes were readable but not decodable, and the file was left where
        /// it is (`.preserveInPlace` — score-bearing files). Never `missing`.
        case undecodable
        /// The file exists but could not be read (I/O / protection error). Must
        /// never be conflated with `missing` — see `canonicalWritesSuspended`.
        case unreadable
    }

    private enum UndecodableHandling {
        /// Leave the bytes in place so every launch reaches the same diagnosis.
        case preserveInPlace
        /// Move the file to `<name>.corrupt` so the store can start that file clean.
        case moveAside
    }

    private static func readCanonicalFile<T: Decodable>(
        _ type: T.Type,
        at url: URL,
        whenUndecodable handling: UndecodableHandling
    ) -> CanonicalRead<T> {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            phoneStoreLogger.error("Failed to read \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .unreadable
        }
        do {
            return .loaded(try JSONDecoder().decode(T.self, from: data))
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

    // MARK: - Legacy migration (pre-canonical layout)

    /// Earlier builds could leave a fallback archive in local Documents. Decode
    /// and rewrite it through the new canonical writer — never move it as-is —
    /// so upgraded users get the new until-first-unlock protection class instead
    /// of inheriting the old complete-protection metadata.
    private func migrateLegacyDocumentsArchiveIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: canonicalHistoryURL.path) else { return }
        let documents = storageConfiguration.legacyDocumentsDirectoryURL
        let legacyHistory = documents.appendingPathComponent(Self.historyFilename)
        let legacyTombstoneURL = documents.appendingPathComponent(Self.tombstoneFilename)
        guard fm.fileExists(atPath: legacyHistory.path) || fm.fileExists(atPath: legacyTombstoneURL.path) else {
            return
        }
        do {
            let legacyRecords = try Self.readLegacyFile([MatchRecord].self, at: legacyHistory) ?? []
            let legacyTombstones = try Self.readLegacyFile([UUID].self, at: legacyTombstoneURL) ?? []
            try fm.createDirectory(at: canonicalDirectoryURL, withIntermediateDirectories: true)
            try Self.write(Self.sortedNewestFirst(legacyRecords), to: canonicalHistoryURL)
            try Self.write(legacyTombstones, to: canonicalTombstoneURL)
            try? fm.removeItem(at: legacyHistory)
            try? fm.removeItem(at: legacyTombstoneURL)
            phoneStoreLogger.notice("Migrated legacy Documents archive into the canonical store")
        } catch {
            phoneStoreLogger.error("Legacy archive migration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func readLegacyFile<T: Decodable>(_ type: T.Type, at url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
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
            pushBackupOnQueue(
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

        let decodedRecords = decodeBackup([MatchRecord].self, from: historyState)
        let decodedTombstones = decodeBackup([UUID].self, from: tombstoneState)
        let decodedLedger = decodeBackup(ForgottenPlayerLedger.self, from: ledgerState)
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
        let previousRecords = records
        let previousTombstones = tombstones
        let previousForgotten = forgotten
        records = snapshot.records
        tombstones = snapshot.tombstones
        forgotten = snapshot.forgottenPlayers
        guard writeCanonicalOnQueue(), markArchiveInitializedOnQueue() else {
            records = previousRecords
            tombstones = previousTombstones
            forgotten = previousForgotten
            finishRestoreIndicator()
            return
        }
        DispatchQueue.main.async { self.pendingRestorePreview = nil }
        publishOnQueue()
        pushBackupOnQueue(historyURL: historyURL, tombstoneURL: tombstoneURL)
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
    /// and the user can re-open the prompt by tapping it. The marker stays absent
    /// so backup pushes remain paused and the old backup is never overwritten.
    /// SwiftUI's alert already dismisses the alert UI by flipping `isPresented`;
    /// nothing needs to change in the store.
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

    /// Pushes the archive through `BackupPushGuard`: a match may leave the
    /// backup only with a tombstone or a confirmed Replace (TECHNICAL_DEBT #18).
    private func pushBackupOnQueue(historyURL: URL, tombstoneURL: URL, retriesRemaining: Int = 0) {
        let currentToken = FileManager.default.ubiquityIdentityToken as? AnyHashable
        let outgoing = backupSnapshotOnQueue()
        guard outgoing != lastPushedSnapshot || currentToken != lastPushedIdentityToken else {
            // Content unchanged — still read the upload status so the indicator
            // stays current (the daemon may have finished uploading since last check).
            if !isBackupWithheldOnQueue {
                readUploadStatusOnQueue(historyURL: historyURL, tombstoneURL: tombstoneURL)
            }
            return
        }

        let baseline: BackupManifest?
        if let backupManifest {
            baseline = backupManifest
        } else {
            switch backupBaselineOnQueue(historyURL: historyURL, tombstoneURL: tombstoneURL) {
            case .ready(let manifest):
                baseline = manifest
            case .downloading:
                // Never push over a backup we haven't been able to compare against.
                guard retriesRemaining > 0 else {
                    phoneStoreLogger.notice("iCloud backup still downloading; deferring the push to the next trigger")
                    return
                }
                let delay = Self.backupRetryDelays[Self.backupRetryDelays.count - retriesRemaining]
                scheduleICloudBackupSyncOnQueue(after: delay, retriesRemaining: retriesRemaining - 1)
                return
            }
        }

        do {
            switch BackupPushGuard.decision(outgoing: outgoing, baseline: baseline) {
            case .push(let snapshot):
                // Deletion intent first, so a partially pushed backup never pairs
                // the newer archive with an older ledger.
                try coordinatedWriteBackup(snapshot.forgottenPlayers, to: Self.backupLedgerURL(besides: historyURL))
                try coordinatedWriteBackup(snapshot.records, to: historyURL)
                try coordinatedWriteBackup(Array(snapshot.tombstones), to: tombstoneURL)
                recordBackupManifestOnQueue(BackupManifest(pushed: snapshot))
                setBackupWithheldOnQueue([], baseline: nil)
                readUploadStatusOnQueue(historyURL: historyURL, tombstoneURL: tombstoneURL)
            case .withholdRecords(let snapshot, let unexplained):
                // Tombstones and the ledger only ever make the backup safer.
                try coordinatedWriteBackup(snapshot.forgottenPlayers, to: Self.backupLedgerURL(besides: historyURL))
                try coordinatedWriteBackup(Array(snapshot.tombstones), to: tombstoneURL)
                phoneStoreLogger.fault("iCloud backup kept: \(unexplained.count, privacy: .public) match(es) would leave it with no deletion or Replace to explain it")
                setBackupWithheldOnQueue(unexplained, baseline: baseline)
            }
            lastPushedSnapshot = outgoing
            lastPushedIdentityToken = currentToken
        } catch {
            // Push failures are recoverable: the canonical archive is safe
            // on-device and the next trigger retries the same content.
            phoneStoreLogger.error("iCloud backup push failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private enum BackupBaseline {
        /// nil = no backup has been written yet, so there is nothing to protect.
        case ready(BackupManifest?)
        case downloading
    }

    /// The ids already in the backup, read only when this iPhone has no
    /// manifest (first push after updating, or after a restore). Records are
    /// decoded as ids only, so a backup whose full records this build can't
    /// read — a newer format — is still protected.
    private func backupBaselineOnQueue(historyURL: URL, tombstoneURL: URL) -> BackupBaseline {
        let historyState = backupFileState(at: historyURL)
        let tombstoneState = backupFileState(at: tombstoneURL)
        if historyState.isDownloading || tombstoneState.isDownloading { return .downloading }
        let ids = decodeBackup([BackupRecordID].self, from: historyState).value
        let tombstones = decodeBackup([UUID].self, from: tombstoneState).value
        // A missing or unreadable-as-ids history has nothing this guard could protect.
        guard ids != nil || tombstones != nil else { return .ready(nil) }
        return .ready(BackupManifest(
            recordIDs: Set((ids ?? []).map(\.id)),
            tombstones: Set(tombstones ?? [])
        ))
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

    private func decodeBackup<T: Decodable>(_ type: T.Type, from state: BackupFileState) -> DecodedBackup<T> {
        guard case .ready(let data) = state else { return .missing }
        do {
            return .loaded(try JSONDecoder().decode(T.self, from: data))
        } catch {
            phoneStoreLogger.error("iCloud backup decode failed: \(error.localizedDescription, privacy: .public)")
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
