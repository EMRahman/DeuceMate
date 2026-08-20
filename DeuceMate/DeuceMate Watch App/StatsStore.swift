// StatsStore.swift
import Foundation
import os
import DeuceMateCore

private let statsStoreLogger = Logger(subsystem: "com.deucemate.persistence", category: "WatchStatsStore")

/// JSON-backed `StatsStoring` implementation for the watch target. Persists to
/// `matchHistory.json` in the app's Documents directory. All file I/O is
/// funnelled through a serial queue to prevent read/write races.
final class StatsStore: StatsStoring, PersistenceOutcomeReporting {
    static let shared = StatsStore()

    /// Installed by `ScoreViewModel` so a failed write or an unreadable archive
    /// reaches the screen instead of only the unified log — for a scoring app a
    /// dropped write is lost match data. Called on the main queue.
    var onPersistenceOutcome: ((PersistenceOutcome) -> Void)?

    /// Maximum number of matches retained on the watch. Older matches are
    /// trimmed on append; the phone keeps everything it ever received. The value
    /// lives in `DeuceMateCore` (`WatchHistory.cap`) so the phone UI can reference
    /// the same number without it drifting.
    static let historyCap = WatchHistory.cap

    private let queue = DispatchQueue(label: "com.deucemate.statsstore", qos: .utility)

    private let fileURL: URL

    /// Production initializer — persists to `matchHistory.json` in the app's
    /// Documents directory.
    init() {
        fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("matchHistory.json")
        excludeExistingArchiveFromBackup()
    }

    /// Test-only initializer that points the store at an explicit file, so the
    /// decode-failure and write-guard behaviour can be exercised without
    /// touching (or clobbering) the real Documents archive.
    init(fileURL: URL) {
        self.fileURL = fileURL
        excludeExistingArchiveFromBackup()
    }

    func loadHistory() -> [MatchRecord] {
        queue.sync { _loadHistoryUnsafe() ?? [] }
    }

    /// `nil` when the file exists but could not be read or decoded — as opposed
    /// to `[]`, which means the archive is genuinely empty. Callers that write a
    /// derived history back (or broadcast it to the phone) MUST use this and bail
    /// on `nil`, so a transient read/decode failure can't be persisted as an
    /// empty archive or prune the phone's watch mirror. Mirrors `PhoneStatsStore`'s
    /// "a read failure is never treated as an empty archive" invariant.
    func loadHistoryOrNil() -> [MatchRecord]? {
        queue.sync { _loadHistoryUnsafe() }
    }

    func saveHistory(_ records: [MatchRecord]) {
        _ = queue.sync { _writeUnsafe(records) }
    }

    func appendMatch(_ record: MatchRecord) {
        queue.sync {
            guard var records = _loadHistoryUnsafe() else {
                statsStoreLogger.error("appendMatch skipped: match history unreadable; refusing to overwrite")
                // The archive is intact but this finished match did not join it,
                // which is the same consequence as a failed write.
                report(.failed(PersistenceFailure(
                    operation: .saveMatchHistory,
                    detail: "appendMatch skipped: match history unreadable"
                )))
                return
            }
            records.removeAll { $0.id == record.id }
            records.append(record)
            records.sort { $0.startTime > $1.startTime }
            if records.count > StatsStore.historyCap {
                records = Array(records.prefix(StatsStore.historyCap))
            }
            _writeUnsafe(records)
        }
    }

    func removeMatch(id: UUID) {
        queue.sync {
            guard var records = _loadHistoryUnsafe() else {
                statsStoreLogger.error("removeMatch skipped: match history unreadable; refusing to overwrite")
                report(.failed(PersistenceFailure(
                    operation: .saveMatchHistory,
                    detail: "removeMatch skipped: match history unreadable"
                )))
                return
            }
            records.removeAll { $0.id == id }
            _writeUnsafe(records)
        }
    }

    // MARK: - Private

    private func excludeExistingArchiveFromBackup() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            try BackupExcludedFileWriter.excludeFromBackup(at: fileURL)
        } catch {
            statsStoreLogger.error("Failed to exclude existing match history from backup: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Returns `[]` only when the file is genuinely absent (no history yet), and
    /// `nil` when the file exists but can't be read or decoded. The distinction
    /// matters: callers that write a derived history back must never treat an
    /// unreadable archive as empty (see `loadHistoryOrNil`). Reading directly and
    /// keying "absent" off `CocoaError.fileReadNoSuchFile` (rather than a separate
    /// `fileExists` probe) avoids a check-then-read race and the deprecated
    /// `URL.path`; a locked/unreadable file throws a different error → `nil`.
    private func _loadHistoryUnsafe() -> [MatchRecord]? {
        do {
            let data = try Data(contentsOf: fileURL)
            let records = try JSONDecoder().decode([MatchRecord].self, from: data)
            report(.succeeded(.readMatchHistory))
            return records
        } catch CocoaError.fileReadNoSuchFile {
            // No history yet is the normal first-run state, not a failure.
            report(.succeeded(.readMatchHistory))
            return []
        } catch {
            statsStoreLogger.error("Failed to read or decode match history: \(error.localizedDescription, privacy: .public)")
            report(.failed(PersistenceFailure(
                operation: .readMatchHistory,
                detail: error.localizedDescription
            )))
            return nil
        }
    }

    @discardableResult
    private func _writeUnsafe(_ records: [MatchRecord]) -> Bool {
        do {
            // Class B protection (until-first-unlock): background WatchConnectivity
            // deliveries can run this while the watch is locked/off-wrist, and the
            // archive must stay writable there — Class A would silently drop the
            // write. Health-bearing watch history is also excluded from device
            // backup after every atomic replacement.
            try BackupExcludedFileWriter.write(records, to: fileURL)
            report(.succeeded(.saveMatchHistory))
            return true
        } catch {
            statsStoreLogger.error("Failed to write match history: \(error.localizedDescription, privacy: .public)")
            report(.failed(PersistenceFailure(
                operation: .saveMatchHistory,
                detail: error.localizedDescription
            )))
            return false
        }
    }

    /// Hop to main before handing an outcome to the UI: every call site above
    /// runs on the store's serial I/O queue.
    private func report(_ outcome: PersistenceOutcome) {
        guard let onPersistenceOutcome else { return }
        DispatchQueue.main.async { onPersistenceOutcome(outcome) }
    }
}
