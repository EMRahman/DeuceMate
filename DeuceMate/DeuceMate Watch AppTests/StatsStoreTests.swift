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

    @Test func validHistoryRoundTrips() {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = StatsStore(fileURL: url)
        let records = [makeRecord(), makeRecord()]

        store.saveHistory(records)

        #expect(store.loadHistoryOrNil() == records)
        #expect(store.loadHistory() == records)
    }
}
