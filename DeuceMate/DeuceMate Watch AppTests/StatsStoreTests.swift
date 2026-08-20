//
//  StatsStoreTests.swift
//  DeuceMate Watch AppTests
//
//  Exercises the real `StatsStore` (not the in-memory mock) against a temp file,
//  covering the invariant that a failed/corrupt read is never treated as an
//  empty archive and never overwrites stored matches (mirrors PhoneStatsStore).
//

import Foundation
import DeuceMateCore
import Testing
@testable import DeuceMate_Watch_App

struct StatsStoreTests {

    // MARK: - Helpers

    /// A unique temp file URL that does not yet exist on disk.
    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("statsstore-test-\(UUID().uuidString).json")
    }

    private func writeCorrupt(to url: URL) throws {
        try Data("not valid json {{{".utf8).write(to: url)
    }

    /// Each call gets a distinct `id` from `MatchRecord`'s default `UUID()`.
    private func makeRecord() -> MatchRecord {
        MatchRecord(
            startTime: Date(timeIntervalSince1970: 1_000_000),
            setScores: [],
            stats: []
        )
    }

    // MARK: - Absent file == genuinely empty

    @Test func absentFileLoadsAsEmpty() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = StatsStore(fileURL: url)

        #expect(store.loadHistoryOrNil() == [])   // [] means "no history yet"…
        #expect(store.loadHistory() == [])
    }

    @Test func appendWritesWhenArchiveIsGenuinelyEmpty() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = StatsStore(fileURL: url)
        let record = makeRecord()

        // A fresh install (absent file → []) must still allow the first append —
        // the guard only blocks unreadable archives, not empty ones.
        store.appendMatch(record)
        #expect(store.loadHistory() == [record])
    }

    // MARK: - Corrupt file == unreadable (nil), never empty

    @Test func corruptFileLoadsAsNil() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeCorrupt(to: url)
        let store = StatsStore(fileURL: url)

        #expect(store.loadHistoryOrNil() == nil)   // …nil means "exists but unreadable"
        #expect(store.loadHistory() == [])         // UI read paths still degrade to []
    }

    @Test func appendDoesNotOverwriteCorruptFile() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeCorrupt(to: url)
        let before = try Data(contentsOf: url)
        let store = StatsStore(fileURL: url)

        store.appendMatch(makeRecord())

        // The corrupt bytes must be untouched — a transient read failure must not
        // clobber the archive with a single-record (or empty) history.
        let after = try Data(contentsOf: url)
        #expect(after == before)
        #expect(store.loadHistoryOrNil() == nil)
    }

    @Test func removeDoesNotOverwriteCorruptFile() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeCorrupt(to: url)
        let before = try Data(contentsOf: url)
        let store = StatsStore(fileURL: url)

        store.removeMatch(id: UUID())

        let after = try Data(contentsOf: url)
        #expect(after == before)
        #expect(store.loadHistoryOrNil() == nil)
    }

    // MARK: - Valid data round-trips

    @Test func validHistoryRoundTrips() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = StatsStore(fileURL: url)
        let records = [makeRecord(), makeRecord()]

        store.saveHistory(records)

        #expect(store.loadHistoryOrNil() == records)
        #expect(store.loadHistory() == records)
        #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func repeatedWritesReapplyBackupExclusion() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = StatsStore(fileURL: url)

        store.saveHistory([makeRecord()])
        var values = URLResourceValues()
        values.isExcludedFromBackup = false
        var mutableURL = url
        try mutableURL.setResourceValues(values)
        #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == false)

        store.saveHistory([makeRecord(), makeRecord()])
        #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    // MARK: - Persistence outcome reporting

    /// Thread-safe sink for outcomes, which are delivered on the main queue.
    private final class OutcomeSink: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [PersistenceOutcome] = []

        func append(_ outcome: PersistenceOutcome) {
            lock.lock(); storage.append(outcome); lock.unlock()
        }

        var outcomes: [PersistenceOutcome] {
            lock.lock(); defer { lock.unlock() }
            return storage
        }
    }

    /// Runs `body` with a sink installed, then lets the store's main-queue
    /// callbacks drain before returning what was reported.
    private func reportedOutcomes(
        of store: StatsStore,
        during body: () -> Void
    ) async -> [PersistenceOutcome] {
        let sink = OutcomeSink()
        store.onPersistenceOutcome = { sink.append($0) }
        body()
        // Callbacks were already enqueued on main, which is FIFO, so this hop
        // runs after all of them.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        store.onPersistenceOutcome = nil
        return sink.outcomes
    }

    @Test func successfulWriteReportsSuccess() async {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = StatsStore(fileURL: url)

        let outcomes = await reportedOutcomes(of: store) {
            store.saveHistory([makeRecord()])
        }

        #expect(outcomes == [.succeeded(.saveMatchHistory)])
    }

    @Test func absentArchiveReportsSuccessNotFailure() async {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = StatsStore(fileURL: url)

        let outcomes = await reportedOutcomes(of: store) {
            _ = store.loadHistoryOrNil()
        }

        // A fresh install is not a failure — "missing" must never raise a warning.
        #expect(outcomes == [.succeeded(.readMatchHistory)])
    }

    @Test func corruptArchiveReportsReadFailure() async throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeCorrupt(to: url)
        let store = StatsStore(fileURL: url)

        let outcomes = await reportedOutcomes(of: store) {
            _ = store.loadHistoryOrNil()
        }

        #expect(outcomes.count == 1)
        guard case .failed(let failure) = outcomes.first else {
            Issue.record("expected a read failure, got \(outcomes)")
            return
        }
        #expect(failure.operation == .readMatchHistory)
    }

    @Test func appendOnUnreadableArchiveReportsSaveFailure() async throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try writeCorrupt(to: url)
        let store = StatsStore(fileURL: url)

        let outcomes = await reportedOutcomes(of: store) {
            store.appendMatch(makeRecord())
        }

        // Refusing to overwrite the archive protects it, but the finished match
        // did not reach disk — that must surface as a save failure, not silence.
        let failures: [PersistenceOperation] = outcomes.compactMap {
            guard case .failed(let failure) = $0 else { return nil }
            return failure.operation
        }
        #expect(failures.contains(.saveMatchHistory))
    }

    @Test func initializerExcludesAnExistingArchiveDuringUpgrade() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try JSONEncoder().encode([makeRecord()]).write(to: url)
        #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup != true)

        _ = StatsStore(fileURL: url)

        #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }
}
