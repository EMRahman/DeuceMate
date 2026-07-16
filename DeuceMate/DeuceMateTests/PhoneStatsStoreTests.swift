// PhoneStatsStoreTests.swift — real canonical archive and Health sidecar I/O.
import Foundation
import DeuceMateCore
import Testing
@testable import DeuceMate

struct PhoneStatsStoreTests {
    private struct Fixture {
        let root: URL
        let canonical: URL
        let legacyDocuments: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("phone-stats-store-\(UUID().uuidString)", isDirectory: true)
            canonical = root.appendingPathComponent("MatchArchive", isDirectory: true)
            legacyDocuments = root.appendingPathComponent("Documents", isDirectory: true)
            try FileManager.default.createDirectory(at: canonical, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: legacyDocuments, withIntermediateDirectories: true)
        }

        var historyURL: URL { canonical.appendingPathComponent("matchHistory.json") }
        var tombstoneURL: URL { canonical.appendingPathComponent("deletedMatchIDs.json") }
        var healthURL: URL { canonical.appendingPathComponent("healthData.json") }

        func makeStore() -> PhoneStatsStore {
            PhoneStatsStore(storageConfiguration: .init(
                canonicalDirectoryURL: canonical,
                legacyDocumentsDirectoryURL: legacyDocuments,
                startsICloudSync: false
            ))
        }

        func makeStore(backupExcluder: @escaping (URL) throws -> Void) -> PhoneStatsStore {
            PhoneStatsStore(storageConfiguration: .init(
                canonicalDirectoryURL: canonical,
                legacyDocumentsDirectoryURL: legacyDocuments,
                startsICloudSync: false,
                backupExcluder: backupExcluder
            ))
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func record(id: UUID = UUID(), health: Bool = true) -> MatchRecord {
        MatchRecord(
            id: id,
            startTime: Date(timeIntervalSince1970: 1_000),
            endTime: Date(timeIntervalSince1970: 2_000),
            setScores: [SetScore(gamesMe: 6, gamesOpponent: 4)],
            stats: [PointStat(
                id: UUID(),
                timestamp: Date(timeIntervalSince1970: 1_100),
                setIndex: 0,
                server: .me,
                winner: .me,
                outcome: .winner,
                heartRateBPM: health ? 156 : nil,
                stepsCumulative: health ? 42 : nil
            )],
            iWon: true,
            totalSteps: health ? 1_234 : nil,
            totalDistanceMeters: health ? 3_210 : nil,
            totalCaloriesKcal: health ? 456 : nil
        )
    }

    private func encode<T: Encodable>(_ value: T, to url: URL) throws {
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }

    @Test func legacyFullFidelityMainMigratesAndLoadsFullRecord() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = record()
        try encode([original], to: fixture.historyURL)
        try encode([UUID](), to: fixture.tombstoneURL)

        let store = fixture.makeStore()

        #expect(store.loadHistory() == [original])
        let persistedMain = try JSONDecoder().decode(
            [MatchRecord].self,
            from: Data(contentsOf: fixture.historyURL)
        )
        #expect(persistedMain.first?.totalSteps == nil)
        #expect(persistedMain.first?.totalDistanceMeters == nil)
        #expect(persistedMain.first?.totalCaloriesKcal == nil)
        #expect(persistedMain.first?.stats.first?.heartRateBPM == nil)
        #expect(persistedMain.first?.stats.first?.stepsCumulative == nil)
        #expect(try JSONDecoder().decode(
            [MatchHealthData].self,
            from: Data(contentsOf: fixture.healthURL)
        ).count == 1)
        #expect(try fixture.healthURL
            .resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #expect(try fixture.historyURL
            .resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup != true)
    }

    @Test func corruptSidecarDegradesAndDoesNotSuspendLaterWrites() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let stripped = record().strippingHealthData()
        try encode([stripped], to: fixture.historyURL)
        try encode([UUID](), to: fixture.tombstoneURL)
        try Data("not json {{{".utf8).write(to: fixture.healthURL)

        let store = fixture.makeStore()
        #expect(store.loadHistory() == [stripped])

        let incoming = record()
        store.appendMatch(incoming)
        #expect(Set(store.loadHistory().map(\.id)) == Set([stripped.id, incoming.id]))
        #expect(FileManager.default.fileExists(atPath: fixture.healthURL.path))
        #expect(FileManager.default.fileExists(atPath: fixture.healthURL.appendingPathExtension("corrupt").path))
        #expect(try fixture.healthURL.appendingPathExtension("corrupt")
            .resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func unreadableMainSuspendsWritesInsteadOfReplacingArchive() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        // A directory at the file URL exists but cannot be decoded as file data,
        // reliably exercising the I/O/unreadable path without permission tricks.
        try FileManager.default.createDirectory(at: fixture.historyURL, withIntermediateDirectories: true)
        let store = fixture.makeStore()

        store.appendMatch(record())

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: fixture.historyURL.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(store.loadHistory().count == 1) // in-memory operation still succeeds
        #expect(!FileManager.default.fileExists(atPath: fixture.healthURL.path))
    }

    @Test func manualImportBackfillsMissingSidecarAndExportStaysFullFidelity() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = record()
        try encode([original.strippingHealthData()], to: fixture.historyURL)
        try encode([UUID](), to: fixture.tombstoneURL)
        let store = fixture.makeStore()
        let archive = try ManualMatchArchiveBackup.encode(records: [original])

        try store.importManualArchive(data: archive, mode: .merge)

        #expect(store.loadHistory() == [original])
        let exported = try ManualMatchArchiveBackup.decode(store.exportManualArchiveData())
        #expect(exported.records == [original])
        #expect(try JSONDecoder().decode(
            [MatchHealthData].self,
            from: Data(contentsOf: fixture.healthURL)
        ).count == 1)
    }

    @Test func repeatedWritesReapplySidecarExclusion() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.makeStore()
        store.saveHistory([record()])

        var values = URLResourceValues()
        values.isExcludedFromBackup = false
        var mutableHealthURL = fixture.healthURL
        try mutableHealthURL.setResourceValues(values)

        store.saveHistory([record(), record()])

        #expect(try fixture.healthURL
            .resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func exclusionFailureDiscardsHealthButStillPersistsStrippedArchive() throws {
        struct ExclusionFailure: Error {}

        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = record()
        let store = fixture.makeStore { _ in throw ExclusionFailure() }

        store.saveHistory([original])

        #expect(store.loadHistory() == [original]) // current process remains full-fidelity
        #expect(!FileManager.default.fileExists(atPath: fixture.healthURL.path))
        let persistedMain = try JSONDecoder().decode(
            [MatchRecord].self,
            from: Data(contentsOf: fixture.historyURL)
        )
        #expect(persistedMain == [original.strippingHealthData()])
        #expect(try JSONDecoder().decode(
            [UUID].self,
            from: Data(contentsOf: fixture.tombstoneURL)
        ).isEmpty)

        let reloaded = fixture.makeStore()
        #expect(reloaded.loadHistory() == [original.strippingHealthData()])
    }

    @Test func deletePermanentlyTombstonesAndBlocksResurrectionAcrossReload() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let kept = record()
        let deleted = record()
        let store = fixture.makeStore()
        store.saveHistory([kept, deleted])

        store.deletePermanently(id: deleted.id)

        #expect(store.loadHistory().map(\.id) == [kept.id])
        // The tombstone is persisted so a later sync or restore can't resurrect it.
        let persistedTombstones = try JSONDecoder().decode(
            [UUID].self,
            from: Data(contentsOf: fixture.tombstoneURL)
        )
        #expect(persistedTombstones == [deleted.id])

        // A fresh store on the same directory reloads the tombstone, and neither a
        // watch "Sync to iPhone" nor a WatchConnectivity merge brings it back.
        let reloaded = fixture.makeStore()
        #expect(reloaded.loadHistory().map(\.id) == [kept.id])
        reloaded.syncToPhone(deleted)
        #expect(reloaded.loadHistory().map(\.id) == [kept.id])
        reloaded.mergeIncoming([deleted])
        #expect(reloaded.loadHistory().map(\.id) == [kept.id])
    }

    @Test func legacyDocumentsArchiveMigratesIntoBackupExcludedCanonicalStore() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = record()
        // Pre-canonical builds left a full-fidelity archive in local Documents.
        let legacyHistory = fixture.legacyDocuments.appendingPathComponent("matchHistory.json")
        let legacyTombstones = fixture.legacyDocuments.appendingPathComponent("deletedMatchIDs.json")
        try encode([original], to: legacyHistory)
        try encode([UUID](), to: legacyTombstones)

        let store = fixture.makeStore()

        // The full record is available in memory (Health merged back from the sidecar)...
        #expect(store.loadHistory() == [original])
        // ...the legacy Documents files are consumed...
        #expect(!FileManager.default.fileExists(atPath: legacyHistory.path))
        #expect(!FileManager.default.fileExists(atPath: legacyTombstones.path))
        // ...the canonical history is health-stripped...
        let persistedMain = try JSONDecoder().decode(
            [MatchRecord].self,
            from: Data(contentsOf: fixture.historyURL)
        )
        #expect(persistedMain == [original.strippingHealthData()])
        // ...and the Health projection lives in the backup-excluded sidecar.
        #expect(try JSONDecoder().decode(
            [MatchHealthData].self,
            from: Data(contentsOf: fixture.healthURL)
        ).count == 1)
        #expect(try fixture.healthURL
            .resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func appendMatchReplacesRecordWithSameID() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.makeStore()
        let id = UUID()
        var first = record(id: id)
        first.setScores = [SetScore(gamesMe: 6, gamesOpponent: 4)]
        store.appendMatch(first)

        var updated = record(id: id)
        updated.setScores = [
            SetScore(gamesMe: 7, gamesOpponent: 6),
            SetScore(gamesMe: 6, gamesOpponent: 3)
        ]
        store.appendMatch(updated)

        let history = store.loadHistory()
        #expect(history.count == 1)
        #expect(history.first?.id == id)
        #expect(history.first?.setScores == updated.setScores)
    }

    @Test func manualImportReplaceModeReplacesEntireArchive() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let existing = record()
        let store = fixture.makeStore()
        store.saveHistory([existing])

        let replacement = record()
        let archive = try ManualMatchArchiveBackup.encode(records: [replacement])
        try store.importManualArchive(data: archive, mode: .replace)

        #expect(store.loadHistory() == [replacement])
    }

    @Test func unreadableTombstoneFileSuspendsWrites() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        // A directory at the tombstone URL exists but cannot be decoded as file
        // data, exercising the .unreadable branch for the tombstone file. A read
        // failure must never be treated as an empty archive.
        try FileManager.default.createDirectory(at: fixture.tombstoneURL, withIntermediateDirectories: true)
        let store = fixture.makeStore()

        store.appendMatch(record())

        // The in-memory operation still succeeds, but nothing is persisted, so a
        // failed read can never overwrite the real archive with a partial one.
        #expect(store.loadHistory().count == 1)
        #expect(!FileManager.default.fileExists(atPath: fixture.historyURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.healthURL.path))
    }
}
