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
// not resurrect deleted matches. A read failure is never treated as an empty
// archive: writes derived from a failed read are suppressed so they can't
// clobber data.
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
    /// Set when a canonical file exists but could not be read at launch (I/O or
    /// protection error — distinct from "missing"). All disk writes and backup
    /// passes are then suppressed for the rest of the process so state derived
    /// from a failed read can never overwrite the real archive; the app keeps
    /// working in memory and the next clean launch reloads everything.
    private var canonicalWritesSuspended = false
    /// The scheduled debounced backup push or restore download-retry, if any.
    private var pendingBackupSync: DispatchWorkItem?
    /// Last content successfully pushed to the ubiquity container; nil before the first push.
    /// Used to skip redundant iCloud writes when nothing has changed.
    private var lastPushedSnapshot: ArchiveBackupPolicy.Snapshot?
    /// The ubiquity identity token at the time of the last successful push.
    /// A different token means a different iCloud account — we must push even if content is unchanged.
    private var lastPushedIdentityToken: AnyHashable?
    /// Decoded backup data waiting for the user to confirm or decline a restore.
    /// Non-nil only between when the prompt is shown and when the user responds.
    private var pendingRestoreDecoded: (records: [MatchRecord], tombstones: [UUID])?

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

    struct StorageConfiguration {
        let canonicalDirectoryURL: URL
        let legacyDocumentsDirectoryURL: URL
        let startsICloudSync: Bool

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

    // MARK: - Init

    convenience init() {
        self.init(storageConfiguration: .production)
    }

    init(storageConfiguration: StorageConfiguration) {
        self.storageConfiguration = storageConfiguration
        let initial = queue.sync { () -> ([MatchRecord], Set<UUID>, Bool) in
            migrateLegacyDocumentsArchiveIfNeeded()
            loadCanonicalOnQueue()
            return (records, tombstones, shouldAttemptInitialRestoreOnQueue)
        }
        history = initial.0
        tombstoneIDs = initial.1
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

    func saveHistory(_ newRecords: [MatchRecord]) {
        queue.sync {
            adoptOnQueue(records: newRecords, tombstones: tombstones)
        }
    }

    func appendMatch(_ record: MatchRecord) {
        queue.sync {
            var updated = records
            updated.removeAll { $0.id == record.id }
            updated.append(record)
            adoptOnQueue(records: updated, tombstones: tombstones)
        }
    }

    /// Pull a watch-only match into the durable archive ("Sync to iPhone"). A
    /// permanently deleted match (tombstoned) is never resurrected: a stale
    /// watch-mirror row can surface it in the window before the queued watch
    /// delete lands, so we keep the tombstone and skip the add.
    func syncToPhone(_ record: MatchRecord) {
        queue.sync {
            guard !tombstones.contains(record.id),
                  !records.contains(where: { $0.id == record.id }) else { return }
            adoptOnQueue(records: records + [record], tombstones: tombstones)
        }
    }

    /// Permanently delete a match from the iPhone: drop the record and tombstone
    /// the id so neither a later watch sync nor an iCloud restore can re-import
    /// it. Callers separately issue a watch-side delete when the match is also
    /// on the watch, so "permanent" means gone everywhere.
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

    // MARK: - Manual archive export/import

    func exportManualArchiveData() throws -> Data {
        try queue.sync {
            try ManualMatchArchiveBackup.encode(records: records)
        }
    }

    func previewManualArchiveImport(data: Data) throws -> ManualMatchArchiveBackup.ImportPreview {
        try ManualMatchArchiveBackup.preview(data)
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
            exportedAt: archive.exportedAt
        )

        queue.sync {
            let snapshot = ManualMatchArchiveBackup.importSnapshot(
                importing: archive.records,
                into: records,
                tombstones: tombstones,
                mode: mode
            )
            adoptOnQueue(records: snapshot.records, tombstones: snapshot.tombstones)
        }
        return preview
    }

    // MARK: - Merge incoming records from WatchConnectivity

    func mergeIncoming(_ incoming: [MatchRecord]) {
        queue.sync {
            let merged = MatchMergePolicy.merge(
                incoming: incoming,
                into: records,
                tombstones: tombstones
            )
            adoptOnQueue(records: merged, tombstones: tombstones)
        }
    }

    func mergeIncoming(_ record: MatchRecord) {
        mergeIncoming([record])
    }

    // MARK: - Canonical store (device-local source of truth)

    /// Adopt new state as the canonical archive: persist it, publish it, and
    /// schedule a debounced iCloud backup sync. The single funnel for every mutation.
    private func adoptOnQueue(records newRecords: [MatchRecord], tombstones newTombstones: Set<UUID>) {
        records = Self.sortedNewestFirst(newRecords)
        tombstones = newTombstones
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
            return
        }
        if storageConfiguration.startsICloudSync {
            scheduleICloudBackupSyncOnQueue(after: Self.backupPushDebounce, retriesRemaining: Self.backupRetryDelays.count)
        }
    }

    private func publishOnQueue() {
        let recordsSnapshot = records
        let tombstoneSnapshot = tombstones
        DispatchQueue.main.async {
            self.history = recordsSnapshot
            self.tombstoneIDs = tombstoneSnapshot
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
            try Self.write(split.health, to: healthSidecarURL)
            // Atomic writes replace the destination inode, so the exclusion
            // resource value must be reapplied after every sidecar write.
            try Self.excludeFromBackup(healthSidecarURL)

            // Sidecar first: a process interruption can leave an older stripped
            // main paired with newer Health values, but cannot strip the latest
            // main before its Health projection is durable.
            try Self.write(split.stripped, to: canonicalHistoryURL)
            try Self.write(Array(tombstones), to: canonicalTombstoneURL)
            return true
        } catch {
            phoneStoreLogger.error("Failed to write canonical archive: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func loadCanonicalOnQueue() {
        switch Self.readCanonicalFile([UUID].self, at: canonicalTombstoneURL) {
        case .loaded(let ids):
            tombstones = Set(ids)
        case .missing, .corrupt:
            break // corrupt file was moved aside; initial restore may refill what it can
        case .unreadable:
            canonicalWritesSuspended = true
        }
        let loadedRecords: [MatchRecord]
        switch Self.readCanonicalFile([MatchRecord].self, at: canonicalHistoryURL) {
        case .loaded(let loaded):
            loadedRecords = loaded
        case .missing, .corrupt:
            loadedRecords = [] // corrupt file was moved aside; initial restore may refill what it can
        case .unreadable:
            canonicalWritesSuspended = true
            loadedRecords = []
        }

        // Reassert the file flag before a corrupt sidecar can be moved to a
        // recovery file. The moved quarantine copy still contains Health data.
        if FileManager.default.fileExists(atPath: healthSidecarURL.path) {
            do {
                try Self.excludeFromBackup(healthSidecarURL)
            } catch {
                phoneStoreLogger.error("Failed to reapply Health sidecar backup exclusion: \(error.localizedDescription, privacy: .public)")
            }
        }
        let health: [MatchHealthData]
        switch Self.readCanonicalFile([MatchHealthData].self, at: healthSidecarURL) {
        case .loaded(let loaded):
            health = loaded
        case .missing, .corrupt, .unreadable:
            health = []
        }

        let loadedHadHealth = !HealthSidecarPolicy.split(loadedRecords).health.isEmpty
        records = Self.sortedNewestFirst(
            HealthSidecarPolicy.merge(stripped: loadedRecords, health: health)
        )

        // The pre-sidecar canonical file was full-fidelity. Content detection is
        // the migration marker: once rewritten successfully, the main file has
        // no Health fields and this path never runs again.
        if loadedHadHealth && !canonicalWritesSuspended {
            if writeCanonicalOnQueue() {
                phoneStoreLogger.notice("Migrated canonical archive to the backup-excluded Health sidecar")
            }
        }
        if canonicalWritesSuspended {
            phoneStoreLogger.error("Canonical archive unreadable; running in-memory with writes suspended")
        }
    }

    private var shouldAttemptInitialRestoreOnQueue: Bool {
        !canonicalWritesSuspended
            && !FileManager.default.fileExists(atPath: canonicalInitializedURL.path)
    }

    private enum CanonicalRead<T> {
        case loaded(T)
        case missing
        /// Bytes were readable but not decodable. The file was moved aside (kept
        /// for recovery) so the store can start clean without destroying it.
        case corrupt
        /// The file exists but could not be read (I/O / protection error). Must
        /// never be conflated with `missing` — see `canonicalWritesSuspended`.
        case unreadable
    }

    private static func readCanonicalFile<T: Decodable>(_ type: T.Type, at url: URL) -> CanonicalRead<T> {
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
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
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
            pushBackupOnQueue(historyURL: backupHistoryURL, tombstoneURL: backupTombstoneURL)
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
        // Restore only when BOTH files are settled: folding records in while
        // their tombstones are still downloading could resurrect a deleted match.
        if historyState.isDownloading || tombstoneState.isDownloading {
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
        guard decodedRecords.isUsable, decodedTombstones.isUsable else {
            phoneStoreLogger.error("Initial iCloud restore skipped because backup data is corrupt")
            finishRestoreIndicator()
            return
        }

        let backupRecords = decodedRecords.value ?? []
        let backupTombstones = decodedTombstones.value ?? []

        if backupRecords.isEmpty {
            // Nothing to restore — reconcile silently and start pushing.
            performRestoreOnQueue(
                backupRecords: backupRecords,
                backupTombstones: backupTombstones,
                historyURL: historyURL,
                tombstoneURL: tombstoneURL
            )
            return
        }

        // Non-empty backup: show the restore prompt. Backup pushes stay paused
        // (marker absent) until the user responds so the old backup is preserved.
        pendingRestoreDecoded = (backupRecords, backupTombstones)
        let preview = ArchiveBackupPolicy.BackupPreview.from(records: backupRecords)
        DispatchQueue.main.async {
            self.pendingRestorePreview = preview
        }
        finishRestoreIndicator()
    }

    private func performRestoreOnQueue(
        backupRecords: [MatchRecord],
        backupTombstones: [UUID],
        historyURL: URL,
        tombstoneURL: URL
    ) {
        let snapshot = ArchiveBackupPolicy.initialRestore(
            localRecords: records,
            localTombstones: tombstones,
            backupRecords: backupRecords,
            backupTombstones: Set(backupTombstones)
        )
        let previousRecords = records
        let previousTombstones = tombstones
        records = snapshot.records
        tombstones = snapshot.tombstones
        guard writeCanonicalOnQueue(), markArchiveInitializedOnQueue() else {
            records = previousRecords
            tombstones = previousTombstones
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
            guard let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
                return
            }
            let historyURL = container.appendingPathComponent(Self.historyFilename)
            let tombstoneURL = container.appendingPathComponent(Self.tombstoneFilename)
            performRestoreOnQueue(
                backupRecords: decoded.records,
                backupTombstones: decoded.tombstones,
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

    private func pushBackupOnQueue(historyURL: URL, tombstoneURL: URL) {
        let currentToken = FileManager.default.ubiquityIdentityToken as? AnyHashable
        let snapshot = ArchiveBackupPolicy.backupSnapshot(records: records, tombstones: tombstones)
        guard snapshot != lastPushedSnapshot || currentToken != lastPushedIdentityToken else {
            // Content unchanged — still read the upload status so the indicator
            // stays current (the daemon may have finished uploading since last check).
            readUploadStatusOnQueue(historyURL: historyURL, tombstoneURL: tombstoneURL)
            return
        }
        do {
            try coordinatedWriteBackup(snapshot.records, to: historyURL)
            try coordinatedWriteBackup(Array(snapshot.tombstones), to: tombstoneURL)
            lastPushedSnapshot = snapshot
            lastPushedIdentityToken = currentToken
            readUploadStatusOnQueue(historyURL: historyURL, tombstoneURL: tombstoneURL)
        } catch {
            // Push failures are recoverable: the canonical archive is safe
            // on-device and the next trigger retries the same content.
            phoneStoreLogger.error("iCloud backup push failed: \(error.localizedDescription, privacy: .public)")
        }
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
