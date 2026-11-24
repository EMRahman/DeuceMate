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
        /// Stands in for the iCloud container (see `makeICloudStore`).
        let iCloud: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("phone-stats-store-\(UUID().uuidString)", isDirectory: true)
            canonical = root.appendingPathComponent("MatchArchive", isDirectory: true)
            legacyDocuments = root.appendingPathComponent("Documents", isDirectory: true)
            iCloud = root.appendingPathComponent("iCloud", isDirectory: true)
            try FileManager.default.createDirectory(at: canonical, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: legacyDocuments, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: iCloud, withIntermediateDirectories: true)
        }

        var historyURL: URL { canonical.appendingPathComponent("matchHistory.json") }
        var tombstoneURL: URL { canonical.appendingPathComponent("deletedMatchIDs.json") }
        var healthURL: URL { canonical.appendingPathComponent("healthData.json") }
        var initializedURL: URL { canonical.appendingPathComponent("archiveInitialized.json") }
        var iCloudHistoryURL: URL { iCloud.appendingPathComponent("matchHistory.json") }

        /// Dated damaged copies (`<file>.corrupt-<stamp>`) of `url`, oldest first.
        func damagedCopies(of url: URL) throws -> [URL] {
            try FileManager.default.contentsOfDirectory(atPath: canonical.path)
                .filter { $0.hasPrefix(url.lastPathComponent + ".corrupt-") }
                .sorted()
                .map { canonical.appendingPathComponent($0) }
        }

        /// A store whose backup passes write to `iCloud`. Sync stays manual:
        /// call `syncICloudBackup()`, then any synchronous call to drain the queue.
        func makeICloudStore() -> PhoneStatsStore {
            PhoneStatsStore(storageConfiguration: .init(
                canonicalDirectoryURL: canonical,
                legacyDocumentsDirectoryURL: legacyDocuments,
                startsICloudSync: false,
                iCloudContainerURL: { iCloud }
            ))
        }

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
        // The damaged sidecar is kept as a dated, backup-excluded copy, and a
        // damaged sidecar never pauses iCloud (ARCHIVE_DERISK_PLAN.md §3.2).
        let sidecarCopy = try #require(try fixture.damagedCopies(of: fixture.healthURL).first)
        #expect(try sidecarCopy
            .resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #expect(!store.isPausedForDamagedArchive)
    }

    // MARK: - Damaged copies and the iCloud pause (ARCHIVE_DERISK_PLAN.md §3)

    @Test func decodeFailureKeepsDatedCopyAndLeavesEarlierCopies() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let earlierDated = fixture.canonical.appendingPathComponent("matchHistory.json.corrupt-20260101T000000")
        let legacy = fixture.canonical.appendingPathComponent("matchHistory.json.corrupt")
        try Data("earlier".utf8).write(to: earlierDated)
        try Data("legacy".utf8).write(to: legacy)
        try Data("not json {{{".utf8).write(to: fixture.historyURL)

        let store = fixture.makeStore()

        #expect(store.loadHistory().isEmpty)
        #expect(store.isPausedForDamagedArchive)
        let copies = try fixture.damagedCopies(of: fixture.historyURL)
        #expect(copies.count == 2)
        #expect(try Data(contentsOf: earlierDated) == Data("earlier".utf8))
        #expect(try Data(contentsOf: legacy) == Data("legacy".utf8))
        let newCopy = try #require(copies.first { $0 != earlierDated })
        #expect(newCopy.lastPathComponent.wholeMatch(of: #/matchHistory\.json\.corrupt-\d{8}T\d{6}/#) != nil)
        #expect(try Data(contentsOf: newCopy) == Data("not json {{{".utf8))
        #expect(try newCopy.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)

        // The app stays usable: new matches still save on the iPhone.
        let incoming = record()
        store.appendMatch(incoming)
        #expect(fixture.makeStore().loadHistory().map(\.id) == [incoming.id])
    }

    @Test(arguments: ["matchHistory.json", "deletedMatchIDs.json", "forgottenPlayers.json"])
    func damagedCopyPausesICloudOnThisAndNextLaunch(damagedFile: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        // An initialized archive, so a normal pass would push (the 1.4.0 overwrite).
        try encode([record(health: false)], to: fixture.historyURL)
        try encode([UUID](), to: fixture.tombstoneURL)
        try encode(true, to: fixture.initializedURL)
        try Data("not json {{{".utf8).write(to: fixture.canonical.appendingPathComponent(damagedFile))
        try encode([record(health: false), record(health: false)], to: fixture.iCloudHistoryURL)
        let iCloudBefore = try Data(contentsOf: fixture.iCloudHistoryURL)
        let iCloudFilesBefore = Set(try FileManager.default.contentsOfDirectory(atPath: fixture.iCloud.path))

        let store = fixture.makeICloudStore()
        #expect(store.isPausedForDamagedArchive)
        store.syncICloudBackup()
        store.appendMatch(record())
        store.syncICloudBackup()
        _ = store.loadHistory()

        let relaunched = fixture.makeICloudStore()
        #expect(relaunched.isPausedForDamagedArchive)
        relaunched.syncICloudBackup()
        _ = relaunched.loadHistory()

        #expect(try Data(contentsOf: fixture.iCloudHistoryURL) == iCloudBefore)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: fixture.iCloud.path)) == iCloudFilesBefore)
        #expect(try fixture.damagedCopies(of: fixture.canonical.appendingPathComponent(damagedFile)).count == 1)
    }

    /// Controls for the pause: copies that must not pause iCloud still push.
    @Test(arguments: [
        "matchHistory.json.corrupt",                  // legacy 1.4.0 copy, undated
        "healthData.json.corrupt-20261123T101500"     // damaged Health sidecar
    ])
    func copiesThatMustNotPauseICloudStillPush(copyName: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let kept = record(health: false)
        try encode([kept], to: fixture.historyURL)
        try encode([UUID](), to: fixture.tombstoneURL)
        try encode(true, to: fixture.initializedURL)
        try Data("not json {{{".utf8).write(to: fixture.canonical.appendingPathComponent(copyName))
        try encode([record(health: false)], to: fixture.iCloudHistoryURL)

        let store = fixture.makeICloudStore()
        #expect(!store.isPausedForDamagedArchive)
        store.syncICloudBackup()
        _ = store.loadHistory()

        let pushed = try JSONDecoder().decode([MatchRecord].self, from: Data(contentsOf: fixture.iCloudHistoryURL))
        #expect(pushed.map(\.id) == [kept.id])
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
