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

    @Test func initializerExcludesAnExistingArchiveDuringUpgrade() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try JSONEncoder().encode([makeRecord()]).write(to: url)
        #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup != true)

        _ = StatsStore(fileURL: url)

        #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    // MARK: - Confirmed history completion

    @Test func completionPersistsDrawAndReturnsExactlyTheSavedHistory() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = StatsStore(fileURL: url)
        let record = makeRecord()
        let other = makeRecord()
        store.saveHistory([record, other])
        let end = Date(timeIntervalSince1970: 2_000_000)

        let saved = try #require(store.completeStoredMatch(id: record.id, at: end))

        #expect(saved == [record.endingAtCurrentScore(at: end), other])
        #expect(saved[0].endTime == end)
        #expect(saved[0].iWon == nil)
        #expect(!saved[0].isInProgress)
        #expect(StatsStore(fileURL: url).loadHistoryOrNil() == saved)
        #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func completionDoesNotCreateAnAbsentArchive() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = StatsStore(fileURL: url)

        #expect(store.completeStoredMatch(id: UUID(), at: Date()) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func completionDoesNotRewriteAnAlreadyCompletedRecord() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = StatsStore(fileURL: url)
        let completed = makeRecord().endingAtCurrentScore(at: Date(timeIntervalSince1970: 2_000_000))
        store.saveHistory([completed])
        let before = try Data(contentsOf: url)

        #expect(store.completeStoredMatch(id: completed.id, at: Date()) == nil)
        #expect(try Data(contentsOf: url) == before)
    }

    enum CompletionFailure: CaseIterable {
        case unreadableArchive, missingRecord, failedWrite
    }

    @MainActor
    @Test(arguments: CompletionFailure.allCases)
    func completionFailureDoesNotDismissOrSync(_ failure: CompletionFailure) throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let sheetSnapshot = makeRecord()
        let other = makeRecord()
        try JSONEncoder().encode([sheetSnapshot, other]).write(to: url)
        var writeAttempts = 0
        let store = StatsStore(fileURL: url, writeHistory: { records, fileURL in
            writeAttempts += 1
            if failure == .failedWrite { throw CocoaError(.fileWriteNoPermission) }
            try BackupExcludedFileWriter.write(records, to: fileURL)
        })
        let viewModel = ScoreViewModel(statsStore: store, stateFileURL: makeTempURL())
        let sync = CompletionSyncSpy()
        viewModel.syncService = sync

        // Simulate the archive changing after the history sheet captured its record.
        switch failure {
        case .unreadableArchive:
            try writeCorrupt(to: url)
        case .missingRecord:
            store.removeMatch(id: sheetSnapshot.id)
        case .failedWrite:
            break
        }
        writeAttempts = 0
        let before = try Data(contentsOf: url)

        // MatchStatsView uses this Bool to gate dismissal; false shows its error.
        #expect(!viewModel.endStoredMatchAtCurrentScore(sheetSnapshot))
        #expect(sync.calls.isEmpty)
        #expect(try Data(contentsOf: url) == before)
        #expect(writeAttempts == (failure == .failedWrite ? 1 : 0))
        #expect(viewModel.currentMatchID == nil)
    }

    @MainActor
    @Test func successfulCompletionUsesLatestStoredScoreAndSyncsSavedSnapshot() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = StatsStore(fileURL: url)
        let sheetSnapshot = makeRecord()
        var latest = sheetSnapshot
        latest.setScores = [SetScore(gamesMe: 0, gamesOpponent: 0)]
        latest.currentPointsOpponent = 2
        let other = makeRecord()
        store.saveHistory([latest, other])
        let viewModel = ScoreViewModel(statsStore: store, stateFileURL: makeTempURL())
        let sync = CompletionSyncSpy()
        viewModel.syncService = sync

        #expect(viewModel.endStoredMatchAtCurrentScore(sheetSnapshot))

        let saved = try #require(store.loadHistoryOrNil())
        #expect(saved.count == 2)
        #expect(saved[0].id == sheetSnapshot.id)
        #expect(saved[0].currentPointsOpponent == 2)
        #expect(saved[0].iWon == false)
        #expect(!saved[0].isInProgress)
        #expect(saved[1] == other)
        #expect(sync.calls == ["fullHistory"])
        #expect(sync.histories == [saved])
        #expect(viewModel.currentMatchID == nil)
    }

    private final class CompletionSyncSpy: MatchSyncService {
        var calls: [String] = []
        var histories: [[MatchRecord]] = []
        var lastSyncDate: Date? { nil }
        func start() { calls.append("start") }
        func sendMatch(_ record: MatchRecord, announcement: String?) { calls.append("match") }
        func clearActiveMatch() { calls.append("clearActiveMatch") }
        func sendFullHistory(_ records: [MatchRecord]) {
            calls.append("fullHistory")
            histories.append(records)
        }
    }
}
