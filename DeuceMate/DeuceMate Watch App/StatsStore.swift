// StatsStore.swift
import Foundation
import os
import DeuceMateCore

private let statsStoreLogger = Logger(subsystem: "com.deucemate.persistence", category: "WatchStatsStore")

/// JSON-backed `StatsStoring` implementation for the watch target. Persists to
/// `matchHistory.json` in the app's Documents directory. All file I/O is
/// funnelled through a serial queue to prevent read/write races.
final class StatsStore: StatsStoring {
    static let shared = StatsStore()

    /// Maximum number of matches retained on the watch. Older matches are
    /// trimmed on append; the phone keeps everything it ever received. The value
    /// lives in `DeuceMateCore` (`WatchHistory.cap`) so the phone UI can reference
    /// the same number without it drifting.
    static let historyCap = WatchHistory.cap

    private let queue = DispatchQueue(label: "com.deucemate.statsstore", qos: .utility)

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("matchHistory.json")
    }

    init() {}

    func loadHistory() -> [MatchRecord] {
        queue.sync { _loadHistoryUnsafe() }
    }

    func saveHistory(_ records: [MatchRecord]) {
        queue.sync { _writeUnsafe(records) }
    }

    func appendMatch(_ record: MatchRecord) {
        queue.sync {
            var records = _loadHistoryUnsafe()
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
            var records = _loadHistoryUnsafe()
            records.removeAll { $0.id == id }
            _writeUnsafe(records)
        }
    }

    // MARK: - Private

    private func _loadHistoryUnsafe() -> [MatchRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        do {
            return try JSONDecoder().decode([MatchRecord].self, from: data)
        } catch {
            statsStoreLogger.error("Failed to decode match history: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func _writeUnsafe(_ records: [MatchRecord]) {
        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            statsStoreLogger.error("Failed to write match history: \(error.localizedDescription, privacy: .public)")
        }
    }
}
