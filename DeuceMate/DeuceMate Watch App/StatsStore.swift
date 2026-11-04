// StatsStore.swift
import Foundation
import os
import DeuceMateCore

private let statsStoreLogger = Logger(subsystem: "com.deucemate.persistence", category: "WatchStatsStore")

/// Watch-only persistence capability for an explicit history completion. Unlike
/// the legacy append API, success means the existing record was actually saved.
protocol WatchStatsStoring: StatsStoring {
    func loadHistoryOrNil() -> [MatchRecord]?
    @discardableResult func appendMatchDurably(_ record: MatchRecord) -> Bool
    /// Read, update and save on the store's serial queue. Returns the saved
    /// history, or nil for an unreadable archive, missing/completed ID or failed
    /// write. Never recreates a record from a stale history-sheet snapshot.
    func completeStoredMatch(id: UUID, at date: Date) -> [MatchRecord]?

    /// Merge a tag update into an already-stored record on the store's serial
    /// queue. Returns the saved record, or nil for an unreadable archive, a
    /// missing ID (never creates a record) or a failed write.
    func updateTags(id: UUID, tags: MatchTags) -> MatchRecord?

    /// Convert an already-completed stored match between singles and doubles on
    /// the store's serial queue. Returns the saved history, or nil for an
    /// unreadable archive, missing/in-progress ID, unchanged type, or failed write.
    func convertStoredMatchType(id: UUID, to matchType: MatchType, at date: Date) -> [MatchRecord]?

    /// Merge a peer match-type revision into an already-stored completed record
    /// on the store's serial queue. Metadata-only: never creates a record and
    /// ignores in-progress records. Returns the saved record, or nil on failure/no-op.
    func updateMatchType(id: UUID, revision: MatchTypeRevision) -> MatchRecord?

    /// Remove a stored record and return the tags it holds at that moment, read
    /// and removed on one serial-queue hop. Resuming a match uses this so a tag
    /// revision saved after the history sheet captured its snapshot is not lost.
    /// Returns nil (and removes nothing) for an unreadable archive, a missing ID
    /// or an untagged record; a read failure is never treated as "no tags".
    func removeMatchReturningTags(id: UUID) -> MatchTags?
}

/// JSON-backed `StatsStoring` implementation for the watch target. Persists to
/// `matchHistory.json` in the app's Documents directory. All file I/O is
/// funnelled through a serial queue to prevent read/write races.
final class StatsStore: WatchStatsStoring {
    static let shared = StatsStore()

    /// Maximum number of matches retained on the watch. Older matches are
    /// trimmed on append; the phone keeps everything it ever received. The value
    /// lives in `DeuceMateCore` (`WatchHistory.cap`) so the phone UI can reference
    /// the same number without it drifting.
    static let historyCap = WatchHistory.cap

    private let queue = DispatchQueue(label: "com.deucemate.statsstore", qos: .utility)

    private let fileURL: URL
    private let writeHistory: ([MatchRecord], URL) throws -> Void

    /// Production initializer — persists to `matchHistory.json` in the app's
    /// Documents directory.
    convenience init() {
        self.init(fileURL: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("matchHistory.json"))
    }

    /// Test-only initializer that points the store at an explicit file, so the
    /// decode-failure and write-guard behaviour can be exercised without
    /// touching (or clobbering) the real Documents archive. The writer seam makes
    /// save failures deterministic in tests without relying on file permissions.
    init(
        fileURL: URL,
        writeHistory: @escaping ([MatchRecord], URL) throws -> Void = {
            try BackupExcludedFileWriter.write($0, to: $1)
        }
    ) {
        self.fileURL = fileURL
        self.writeHistory = writeHistory
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

    func completeStoredMatch(id: UUID, at date: Date) -> [MatchRecord]? {
        queue.sync {
            guard var records = _loadHistoryUnsafe(),
                  let index = records.firstIndex(where: { $0.id == id }),
                  records[index].isInProgress else { return nil }
            records[index] = records[index].endingAtCurrentScore(at: date)
            records.sort(by: MatchChronology.newestFirst)
            guard _writeUnsafe(records) else { return nil }
            return records
        }
    }

    func updateTags(id: UUID, tags: MatchTags) -> MatchRecord? {
        queue.sync {
            guard var records = _loadHistoryUnsafe(),
                  let index = records.firstIndex(where: { $0.id == id }) else { return nil }
            let updated = records[index].mergingTags(tags)
            records[index] = updated
            guard _writeUnsafe(records) else { return nil }
            return updated
        }
    }

    func convertStoredMatchType(id: UUID, to matchType: MatchType, at date: Date) -> [MatchRecord]? {
        queue.sync {
            guard var records = _loadHistoryUnsafe(),
                  let index = records.firstIndex(where: { $0.id == id }),
                  !records[index].isInProgress,
                  records[index].matchType != matchType else { return nil }
            records[index] = records[index].convertingMatchType(to: matchType, at: date)
            guard _writeUnsafe(records) else { return nil }
            return records
        }
    }

    func updateMatchType(id: UUID, revision: MatchTypeRevision) -> MatchRecord? {
        queue.sync {
            guard var records = _loadHistoryUnsafe(),
                  let index = records.firstIndex(where: { $0.id == id }),
                  !records[index].isInProgress else { return nil }
            let updated = records[index].mergingMatchTypeRevision(revision)
            records[index] = updated
            guard _writeUnsafe(records) else { return nil }
            return updated
        }
    }

    func removeMatchReturningTags(id: UUID) -> MatchTags? {
        queue.sync {
            guard var records = _loadHistoryUnsafe() else {
                statsStoreLogger.error("removeMatchReturningTags skipped: match history unreadable; refusing to overwrite")
                return nil
            }
            guard let index = records.firstIndex(where: { $0.id == id }) else { return nil }
            let tags = records[index].tags
            records.remove(at: index)
            _writeUnsafe(records)
            return tags
        }
    }

    func appendMatch(_ record: MatchRecord) {
        _ = appendMatchDurably(record)
    }

    @discardableResult
    func appendMatchDurably(_ record: MatchRecord) -> Bool {
        queue.sync {
            guard var records = _loadHistoryUnsafe() else {
                statsStoreLogger.error("appendMatch skipped: match history unreadable; refusing to overwrite")
                return false
            }
            // Tags and matchTypeRevision are metadata that live checkpoints never carry.
            // Merge the stored copy's tags and revision forward so replacing a record
            // by id can't erase them (MATCH_TAGS_PLAN.md §3).
            var record = record
            if let stored = records.first(where: { $0.id == record.id }) {
                record = record
                    .mergingResumeEvents(stored.resumeEvents)
                    .mergingTags(stored.tags)
                    .mergingMatchTypeRevision(stored.matchTypeRevision)
            }
            records.removeAll { $0.id == record.id }
            records.append(record)
            records.sort(by: MatchChronology.newestFirst)
            if records.count > StatsStore.historyCap {
                records = Array(records.prefix(StatsStore.historyCap))
            }
            return _writeUnsafe(records)
        }
    }

    func removeMatch(id: UUID) {
        queue.sync {
            guard var records = _loadHistoryUnsafe() else {
                statsStoreLogger.error("removeMatch skipped: match history unreadable; refusing to overwrite")
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
            return try JSONDecoder().decode([MatchRecord].self, from: data)
                .sorted(by: MatchChronology.newestFirst)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        } catch {
            statsStoreLogger.error("Failed to read or decode match history: \(error.localizedDescription, privacy: .public)")
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
            try writeHistory(records, fileURL)
            return true
        } catch {
            statsStoreLogger.error("Failed to write match history: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
