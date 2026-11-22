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
        var ledgerURL: URL { canonical.appendingPathComponent("forgottenPlayers.json") }
        var initializedURL: URL { canonical.appendingPathComponent("archiveInitialized.json") }
        var manifestURL: URL { canonical.appendingPathComponent("backupManifest.json") }

        var backup: URL { root.appendingPathComponent("Backup", isDirectory: true) }
        var backupHistoryURL: URL { backup.appendingPathComponent("matchHistory.json") }
        var backupTombstoneURL: URL { backup.appendingPathComponent("deletedMatchIDs.json") }
        var backupLedgerURL: URL { backup.appendingPathComponent("forgottenPlayers.json") }

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

        /// A store past its one-time initial restore that pushes to `container`
        /// (defaults to `backup`) under `identityKey`.
        func makeBackingUpStore(
            container: (() -> URL?)? = nil,
            identityKey: (() -> String?)? = nil,
            startsICloudSync: Bool = true
        ) throws -> PhoneStatsStore {
            try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
            try JSONEncoder().encode(true).write(to: initializedURL)
            let defaultBackup = backup
            return PhoneStatsStore(storageConfiguration: .init(
                canonicalDirectoryURL: canonical,
                legacyDocumentsDirectoryURL: legacyDocuments,
                startsICloudSync: startsICloudSync,
                backupContainerURL: container ?? { defaultBackup },
                backupIdentityKey: identityKey ?? { "account-a" }
            ))
        }

        /// Makes every canonical write fail while reads still succeed: the
        /// first file written (the forgotten-player ledger) becomes a
        /// non-empty folder. Call only after the store has loaded.
        func blockCanonicalWrites() throws {
            try? FileManager.default.removeItem(at: ledgerURL)
            try FileManager.default.createDirectory(at: ledgerURL, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: ledgerURL.appendingPathComponent("blocker"))
        }

        func unblockCanonicalWrites() throws {
            try FileManager.default.removeItem(at: ledgerURL)
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
        #expect(store.archiveProblem == .unreadable)
        #expect(store.loadHistory().isEmpty)
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

        #expect(store.archiveProblem == .unreadable)
        #expect(store.loadHistory().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.historyURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.healthURL.path))
    }

    // MARK: - Fail-closed canonical reads (TECHNICAL_DEBT #18)

    private func archiveFromNewerBuild() throws -> Data {
        let json = String(decoding: try JSONEncoder().encode([record(health: false)]), as: UTF8.self)
        let newer = json.replacingOccurrences(of: "\"outcome\":\"winner\"", with: "\"outcome\":\"smash\"")
        #expect(newer != json)
        #expect((try? JSONDecoder().decode([MatchRecord].self, from: Data(newer.utf8))) == nil)
        return Data(newer.utf8)
    }

    private func pushNow(_ store: PhoneStatsStore) async -> Bool {
        store.syncICloudBackup()
        _ = store.loadHistory()
        return await MainActor.run { store.isBackupWithheld }
    }

    private func backupIDs(_ fixture: Fixture, in container: URL? = nil) throws -> Set<UUID> {
        let url = (container ?? fixture.backup).appendingPathComponent("matchHistory.json")
        return Set(try JSONDecoder().decode([MatchRecord].self, from: Data(contentsOf: url)).map(\.id))
    }

    private func recoveredFiles(_ fixture: Fixture) throws -> [URL] {
        let root = fixture.canonical.appendingPathComponent("Recovered", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .flatMap { try FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil) }
    }

    @Test func cleanLoadReportsNoArchiveProblem() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try encode([record().strippingHealthData()], to: fixture.historyURL)

        #expect(fixture.makeStore().archiveProblem == nil)
    }

    @Test func undecodableMainIsPreservedInPlaceAndSuspendsWritesExportsAndBackupAcrossRelaunch() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let backupRecord = record().strippingHealthData()
        try FileManager.default.createDirectory(at: fixture.backup, withIntermediateDirectories: true)
        let backupBytes = try JSONEncoder().encode([backupRecord])
        try backupBytes.write(to: fixture.backupHistoryURL)
        try encode([UUID](), to: fixture.backupTombstoneURL)

        let original = try archiveFromNewerBuild()
        try original.write(to: fixture.historyURL)
        try encode([UUID](), to: fixture.tombstoneURL)

        for _ in 0..<2 {
            let store = try fixture.makeBackingUpStore()
            #expect(store.archiveProblem == .undecodable)
            #expect(!store.appendMatchDurably(record()))
            #expect(!store.deletePermanently(id: backupRecord.id))
            #expect(store.mergeIncoming([record()]) == nil)
            #expect(throws: PhoneStatsStore.TagEditError.notPersisted) {
                try store.exportManualArchiveData()
            }
            #expect(throws: PhoneStatsStore.TagEditError.notPersisted) {
                try store.importManualArchive(data: ManualMatchArchiveBackup.encode(records: [record()]), mode: .merge)
            }
            _ = await pushNow(store)
            #expect(store.loadHistory().isEmpty)
            #expect(try Data(contentsOf: fixture.historyURL) == original)
            #expect(!FileManager.default.fileExists(atPath: fixture.historyURL.appendingPathExtension("corrupt").path))
            #expect(try Data(contentsOf: fixture.backupHistoryURL) == backupBytes)
        }
    }

    @Test func undecodableTombstonesSuspendWritesAndPreserveBytes() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let damaged = Data("[\"not-a-uuid\"]".utf8)
        try damaged.write(to: fixture.tombstoneURL)

        let store = fixture.makeStore()
        #expect(store.archiveProblem == .undecodable)
        #expect(!store.appendMatchDurably(record()))
        #expect(!FileManager.default.fileExists(atPath: fixture.historyURL.path))
        #expect(try Data(contentsOf: fixture.tombstoneURL) == damaged)
    }

    @Test(arguments: [
        "not json {{{",
        "{}",
        #"{"playerIDs":null}"#,
        #"{"schemaVersion":0,"playerIDs":[]}"#,
        #"{"schemaVersion":1,"playerIDs":42}"#,
        #"{"schemaVersion":1,"playerIDs":["00000000-0000-0000-0000-000000000001","bad-id"]}"#
    ])
    func malformedForgottenPlayerLedgerSuspendsWrites(json: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let existing = record().strippingHealthData()
        try encode([existing], to: fixture.historyURL)
        try encode([UUID](), to: fixture.tombstoneURL)
        let damaged = Data(json.utf8)
        try damaged.write(to: fixture.ledgerURL)

        let store = fixture.makeStore()
        #expect(store.archiveProblem == .undecodable)
        #expect(store.loadHistory().isEmpty)
        #expect(!store.appendMatchDurably(record()))
        #expect(try Data(contentsOf: fixture.ledgerURL) == damaged)
        #expect(try JSONDecoder().decode([MatchRecord].self, from: Data(contentsOf: fixture.historyURL)) == [existing])
    }

    @Test(arguments: [
        #"{"schemaVersion":2,"playerIDs":[]}"#,
        #"{"schemaVersion":2,"playerIDs":[{"id":"reshaped-in-v2"}]}"#
    ])
    func newerForgottenPlayerLedgerDiagnosesNewerVersionAndPreservesBytes(json: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let existing = record().strippingHealthData()
        try encode([existing], to: fixture.historyURL)
        try encode([UUID](), to: fixture.tombstoneURL)
        let future = Data(json.utf8)
        try future.write(to: fixture.ledgerURL)

        let store = fixture.makeStore()
        #expect(store.archiveProblem == .newerVersion)
        #expect(store.loadHistory().isEmpty)
        #expect(!store.appendMatchDurably(record()))
        #expect(try Data(contentsOf: fixture.ledgerURL) == future)
    }

    @Test func initialRestoreWaitsForAnIntactForgottenPlayerLedger() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.backup, withIntermediateDirectories: true)
        try encode([MatchRecord](), to: fixture.backupHistoryURL)
        try encode([UUID](), to: fixture.backupTombstoneURL)
        let damaged = Data(#"{"playerIDs":["bad-id"]}"#.utf8)
        try damaged.write(to: fixture.backupLedgerURL)

        let store = PhoneStatsStore(storageConfiguration: .init(
            canonicalDirectoryURL: fixture.canonical,
            legacyDocumentsDirectoryURL: fixture.legacyDocuments,
            startsICloudSync: false,
            backupContainerURL: { fixture.backup }
        ))
        store.syncICloudBackup()
        _ = store.loadHistory()
        #expect(!FileManager.default.fileExists(atPath: fixture.initializedURL.path))
        #expect(try Data(contentsOf: fixture.backupLedgerURL) == damaged)

        let forgotten = ForgottenPlayerLedger(playerIDs: [UUID()])
        try encode(forgotten, to: fixture.backupLedgerURL)
        store.syncICloudBackup()
        _ = store.loadHistory()
        #expect(store.forgottenPlayerLedger() == forgotten)
        #expect(FileManager.default.fileExists(atPath: fixture.initializedURL.path))
    }

    @Test func initializedArchivePredatingForgottenPlayerLedgerStillLoads() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let saved = record(health: false)
        try encode([saved], to: fixture.historyURL)
        try encode([UUID](), to: fixture.tombstoneURL)
        try encode(true, to: fixture.initializedURL)
        let store = fixture.makeStore()
        #expect(store.archiveProblem == nil)
        #expect(store.loadHistory() == [saved])
    }

    @Test(arguments: ["matchHistory.json", "deletedMatchIDs.json"])
    func initializedArchiveRequiresHistoryAndTombstones(filename: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        fixture.makeStore().appendMatch(record())
        try encode(true, to: fixture.initializedURL)
        try FileManager.default.removeItem(at: fixture.canonical.appendingPathComponent(filename))
        #expect(fixture.makeStore().archiveProblem == .undecodable)
    }

    @Test func oldQuarantineBlocksLegacyMigrationAndRecoversCleanlyOnReplace() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let quarantine = fixture.historyURL.appendingPathExtension("corrupt")
        let legacyHistory = fixture.legacyDocuments.appendingPathComponent("matchHistory.json")
        let evidence = Data("preserved archive".utf8)
        try evidence.write(to: quarantine)
        try encode([record()], to: legacyHistory)

        let store = fixture.makeStore()
        #expect(store.archiveProblem == .undecodable)
        #expect(!store.appendMatchDurably(record()))
        #expect(try Data(contentsOf: quarantine) == evidence)
        #expect(FileManager.default.fileExists(atPath: legacyHistory.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.historyURL.path))

        // Confirmed Replace copies the legacy quarantine into Recovered/ and clears it.
        let replacement = record()
        try store.importManualArchive(data: ManualMatchArchiveBackup.encode(records: [replacement]), mode: .replace)
        #expect(await MainActor.run { store.archiveProblem } == nil)
        #expect(!FileManager.default.fileExists(atPath: quarantine.path))
        let copiedNames = Set(try recoveredFiles(fixture).map(\.lastPathComponent))
        #expect(copiedNames.contains("matchHistory.json.corrupt"))
        #expect(fixture.makeStore().archiveProblem == nil)
    }

    @Test func undecodableOutranksUnreadableWhenBothFail() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.tombstoneURL, withIntermediateDirectories: true)
        try archiveFromNewerBuild().write(to: fixture.historyURL)

        #expect(fixture.makeStore().archiveProblem == .undecodable)
    }

    // MARK: - iCloud backup push guard (TECHNICAL_DEBT #18)

    @Test func pushWritesTheBackupAndRemembersIdentityScopedManifest() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let match = record()
        try encode([match.strippingHealthData()], to: fixture.historyURL)
        try encode([UUID](), to: fixture.tombstoneURL)
        let store = try fixture.makeBackingUpStore()

        #expect(await pushNow(store) == false)
        #expect(try backupIDs(fixture) == [match.id])
        let manifest = try JSONDecoder().decode(BackupManifest.self, from: Data(contentsOf: fixture.manifestURL))
        #expect(manifest.recordIDs == [match.id])
        #expect(manifest.identityKey == "account-a")
    }

    @Test func deletingTheOnlyMatchStillEmptiesTheBackup() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let match = record()
        try encode([match.strippingHealthData()], to: fixture.historyURL)
        try encode([UUID](), to: fixture.tombstoneURL)
        let store = try fixture.makeBackingUpStore()
        _ = await pushNow(store)

        #expect(store.deletePermanently(id: match.id))

        #expect(await pushNow(store) == false)
        #expect(try backupIDs(fixture).isEmpty)
        #expect(try JSONDecoder().decode([UUID].self, from: Data(contentsOf: fixture.backupTombstoneURL)) == [match.id])
    }

    @Test func unexplainedLossKeepsTheBackupsRecords() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let kept = record(), lost = record()
        try encode([kept.strippingHealthData()], to: fixture.historyURL)
        try encode([UUID](), to: fixture.tombstoneURL)
        try encode(BackupManifest(recordIDs: [kept.id, lost.id], tombstones: [], identityKey: "account-a"), to: fixture.manifestURL)
        try FileManager.default.createDirectory(at: fixture.backup, withIntermediateDirectories: true)
        let backupBytes = try JSONEncoder().encode([kept.strippingHealthData(), lost.strippingHealthData()])
        try backupBytes.write(to: fixture.backupHistoryURL)
        let store = try fixture.makeBackingUpStore()

        #expect(await pushNow(store) == true)
        #expect(try Data(contentsOf: fixture.backupHistoryURL) == backupBytes)
        #expect(FileManager.default.fileExists(atPath: fixture.backupTombstoneURL.path))
    }

    @Test func withoutAManifestTheBaselineIsReadFromANewerFormatBackup() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let kept = record()
        try encode([kept.strippingHealthData()], to: fixture.historyURL)
        try encode([UUID](), to: fixture.tombstoneURL)
        try FileManager.default.createDirectory(at: fixture.backup, withIntermediateDirectories: true)
        let newerID = UUID()
        let backupBytes = Data("""
        [\(String(decoding: try JSONEncoder().encode(kept.strippingHealthData()), as: UTF8.self)),
         {"id":"\(newerID.uuidString)","stats":[{"outcome":"smash"}]}]
        """.utf8)
        try backupBytes.write(to: fixture.backupHistoryURL)
        let store = try fixture.makeBackingUpStore()

        #expect(await pushNow(store) == true)
        #expect(try Data(contentsOf: fixture.backupHistoryURL) == backupBytes)
    }

    @Test func corruptOrFutureEnvelopeRemoteBackupIsNeverOverwritten() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let local = record()
        try encode([local.strippingHealthData()], to: fixture.historyURL)
        try encode([UUID](), to: fixture.tombstoneURL)
        try FileManager.default.createDirectory(at: fixture.backup, withIntermediateDirectories: true)
        let futureEnvelope = Data(#"{"format":"deucemate.matchHistory","schemaVersion":2,"items":[]}"#.utf8)
        try futureEnvelope.write(to: fixture.backupHistoryURL)
        try encode([UUID](), to: fixture.backupTombstoneURL)
        let store = try fixture.makeBackingUpStore()

        _ = await pushNow(store)

        #expect(try Data(contentsOf: fixture.backupHistoryURL) == futureEnvelope)
    }

    @Test func switchingICloudAccountInspectsDestinationAndUnionsRemoteLedgers() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let accountA = fixture.root.appendingPathComponent("iCloudA", isDirectory: true)
        let accountB = fixture.root.appendingPathComponent("iCloudB", isDirectory: true)
        try FileManager.default.createDirectory(at: accountA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: accountB, withIntermediateDirectories: true)

        let matchA = record(), matchB = record()
        let localDeleted = UUID(), remoteDeleted = UUID()
        let localForgotten = UUID(), remoteForgotten = UUID()

        try encode([matchA.strippingHealthData()], to: fixture.historyURL)
        try encode([localDeleted], to: fixture.tombstoneURL)
        try encode(ForgottenPlayerLedger(playerIDs: [localForgotten]), to: fixture.ledgerURL)

        var activeContainer = accountA
        var activeIdentity = "account-a"
        let store = try fixture.makeBackingUpStore(
            container: { activeContainer },
            identityKey: { activeIdentity },
            startsICloudSync: false
        )
        #expect(await pushNow(store) == false)
        #expect(try backupIDs(fixture, in: accountA) == [matchA.id])

        // Populate Account B with an extra match plus its own deletion ledgers.
        let accountBHistoryBytes = try JSONEncoder().encode([matchA.strippingHealthData(), matchB.strippingHealthData()])
        try accountBHistoryBytes.write(to: accountB.appendingPathComponent("matchHistory.json"))
        try encode([remoteDeleted], to: accountB.appendingPathComponent("deletedMatchIDs.json"))
        try encode(ForgottenPlayerLedger(playerIDs: [remoteForgotten]), to: accountB.appendingPathComponent("forgottenPlayers.json"))

        // Switch to Account B: Account A's local manifest must NOT authorize overwriting Account B.
        activeContainer = accountB
        activeIdentity = "account-b"
        #expect(await pushNow(store) == true)
        #expect(try Data(contentsOf: accountB.appendingPathComponent("matchHistory.json")) == accountBHistoryBytes)
        let mergedTombstones = try JSONDecoder().decode([UUID].self, from: Data(contentsOf: accountB.appendingPathComponent("deletedMatchIDs.json")))
        #expect(Set(mergedTombstones) == Set([localDeleted, remoteDeleted]))
        let mergedLedger = try JSONDecoder().decode(ForgottenPlayerLedger.self, from: Data(contentsOf: accountB.appendingPathComponent("forgottenPlayers.json")))
        #expect(mergedLedger == ForgottenPlayerLedger(playerIDs: [localForgotten, remoteForgotten]))
    }

    @Test func confirmedReplaceImportShrinksBackupWhilePreservingRemoteTombstones() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let old = record(), replacement = record(), remoteDeleted = UUID()
        try encode([old.strippingHealthData()], to: fixture.historyURL)
        try encode([UUID](), to: fixture.tombstoneURL)
        let store = try fixture.makeBackingUpStore()
        _ = await pushNow(store)
        try encode([remoteDeleted], to: fixture.backupTombstoneURL)

        try store.importManualArchive(data: ManualMatchArchiveBackup.encode(records: [replacement]), mode: .replace)

        #expect(await pushNow(store) == false)
        #expect(try backupIDs(fixture) == [replacement.id])
        let tombstones = try JSONDecoder().decode([UUID].self, from: Data(contentsOf: fixture.backupTombstoneURL))
        #expect(Set(tombstones) == [remoteDeleted])
    }

    @Test func mergeImportLiftsRemoteTombstoneForRestoredMatchWhileKeepingOthers() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let restored = record(), stillDeleted = record()
        try encode([restored.strippingHealthData(), stillDeleted.strippingHealthData()], to: fixture.historyURL)
        try encode([UUID](), to: fixture.tombstoneURL)
        let store = try fixture.makeBackingUpStore()
        _ = await pushNow(store)

        #expect(store.deletePermanently(id: restored.id))
        #expect(store.deletePermanently(id: stillDeleted.id))
        #expect(await pushNow(store) == false)

        try store.importManualArchive(data: ManualMatchArchiveBackup.encode(records: [restored]), mode: .merge)
        #expect(await pushNow(store) == false)
        #expect(try backupIDs(fixture) == [restored.id])
        let tombstones = try JSONDecoder().decode([UUID].self, from: Data(contentsOf: fixture.backupTombstoneURL))
        #expect(Set(tombstones) == [stillDeleted.id])
    }

    // MARK: - Explicit recovery (TECHNICAL_DEBT #18)

    @Test func tryAgainLoadsTheArchiveOnceReadable() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.historyURL, withIntermediateDirectories: true)
        let store = fixture.makeStore()
        #expect(store.archiveProblem == .unreadable)

        let saved = record()
        try FileManager.default.removeItem(at: fixture.historyURL)
        try encode([saved.strippingHealthData()], to: fixture.historyURL)

        #expect(await store.retryArchiveLoad() == nil)
        #expect(await MainActor.run { store.archiveProblem } == nil)
        #expect(store.loadHistory().map(\.id) == [saved.id])
    }

    @Test func saveACopySharesThePreservedFilesWithoutHealthSidecar() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try archiveFromNewerBuild()
        try original.write(to: fixture.historyURL)
        try encode([UUID()], to: fixture.tombstoneURL)
        try encode(HealthSidecarPolicy.split([record()]).health, to: fixture.healthURL)
        let store = fixture.makeStore()

        let copies = try store.copyPreservedArchiveForSharing()
        defer { copies.forEach { try? FileManager.default.removeItem(at: $0.deletingLastPathComponent()) } }

        #expect(Set(copies.map(\.lastPathComponent)) == ["matchHistory.json", "deletedMatchIDs.json"])
        let historyCopy = try #require(copies.first { $0.lastPathComponent == "matchHistory.json" })
        #expect(try Data(contentsOf: historyCopy) == original)
        #expect(try Data(contentsOf: fixture.historyURL) == original)
        #expect(store.archiveProblem == .undecodable)
    }

    @Test func restoreFromICloudReplacesUndecodableArchiveKeepsCopyAndProtectsNewerBackupMatches() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try archiveFromNewerBuild()
        try original.write(to: fixture.historyURL)
        try encode([UUID](), to: fixture.tombstoneURL)
        // Stale local manifest that does NOT know about newerID in iCloud.
        let backedUp = record()
        try encode(BackupManifest(recordIDs: [backedUp.id], tombstones: [], identityKey: "account-a"), to: fixture.manifestURL)
        try encode(HealthSidecarPolicy.split([backedUp]).health, to: fixture.healthURL)

        try FileManager.default.createDirectory(at: fixture.backup, withIntermediateDirectories: true)
        let newerID = UUID()
        let backupBytes = Data("""
        [\(String(decoding: try JSONEncoder().encode(backedUp.strippingHealthData()), as: UTF8.self)),
         {"id":"\(newerID.uuidString)","stats":[{"outcome":"smash"}]}]
        """.utf8)
        try backupBytes.write(to: fixture.backupHistoryURL)
        try encode([UUID](), to: fixture.backupTombstoneURL)
        let store = try fixture.makeBackingUpStore(startsICloudSync: false)
        #expect(store.archiveProblem == .undecodable)

        guard case .available(let preview, let newer) = await store.iCloudRestoreOffer() else {
            Issue.record("expected the backup to be offered")
            return
        }
        #expect(preview.recordCount == 1)
        #expect(newer == 1)

        #expect(try await store.restoreArchiveFromICloud() == 1)
        #expect(await MainActor.run { store.archiveProblem } == nil)
        #expect(store.loadHistory().first?.totalSteps == 1_234)
        let kept = try recoveredFiles(fixture)
        #expect(try Data(contentsOf: #require(kept.first { $0.lastPathComponent == "matchHistory.json" })) == original)

        // Next push must NOT overwrite the newer-format match in iCloud despite the old stale manifest.
        #expect(await pushNow(store) == true)
        #expect(try Data(contentsOf: fixture.backupHistoryURL) == backupBytes)
    }

    private func withheldSetup(_ fixture: Fixture) async throws -> (PhoneStatsStore, kept: MatchRecord, lost: MatchRecord, backupBytes: Data) {
        let kept = record(), lost = record()
        try encode([kept.strippingHealthData()], to: fixture.historyURL)
        try encode([UUID](), to: fixture.tombstoneURL)
        try encode(BackupManifest(recordIDs: [kept.id, lost.id], tombstones: [], identityKey: "account-a"), to: fixture.manifestURL)
        try FileManager.default.createDirectory(at: fixture.backup, withIntermediateDirectories: true)
        let backupBytes = try JSONEncoder().encode([kept.strippingHealthData(), lost.strippingHealthData()])
        try backupBytes.write(to: fixture.backupHistoryURL)
        try encode([UUID](), to: fixture.backupTombstoneURL)
        let store = try fixture.makeBackingUpStore(startsICloudSync: false)
        #expect(await pushNow(store) == true)
        #expect(await MainActor.run { store.withheldBackupMatchCount } == 1)
        return (store, kept, lost, backupBytes)
    }

    @Test func bringBackRestoresWithheldMatchesAndResumesBackup() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let (store, kept, lost, _) = try await withheldSetup(fixture)

        let result = try await store.bringBackWithheldMatches()

        #expect(result.restored == 1 && result.stillMissing == 0)
        #expect(Set(store.loadHistory().map(\.id)) == [kept.id, lost.id])
        #expect(await MainActor.run { store.isBackupWithheld } == false)
        #expect(try backupIDs(fixture) == [kept.id, lost.id])
    }

    @Test func removeFromBackupKeepsCopyAndReportsFailureIfRemoteWriteFails() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let (store, kept, _, backupBytes) = try await withheldSetup(fixture)

        try await store.removeWithheldMatchesFromBackup(confirmed: store.withheldBackupMatchIDs())

        #expect(await MainActor.run { store.isBackupWithheld } == false)
        #expect(try backupIDs(fixture) == [kept.id])
        let copy = try #require(try recoveredFiles(fixture).first)
        #expect(copy.lastPathComponent == "iCloud-matchHistory.json")
        #expect(try Data(contentsOf: copy) == backupBytes)
        #expect(store.loadHistory().map(\.id) == [kept.id])
    }

    @Test func removeFromBackupThrowsWhenBackupWriteFails() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let (store, _, _, _) = try await withheldSetup(fixture)
        // Make backup tombstone path a directory so coordinatedWriteBackup fails.
        try FileManager.default.removeItem(at: fixture.backupTombstoneURL)
        try FileManager.default.createDirectory(at: fixture.backupTombstoneURL, withIntermediateDirectories: true)

        await #expect(throws: PhoneStatsStore.RecoveryError.backupUnavailable) {
            try await store.removeWithheldMatchesFromBackup(confirmed: store.withheldBackupMatchIDs())
        }
        #expect(await MainActor.run { store.isBackupWithheld } == true)
    }

    @Test func restoreFromICloudPreservesReadableLocalDeletionLedgersWhenHistoryUndecodable() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let kept = record(health: false)
        let deleted = record(health: false)
        let forgottenPlayer = TaggedPlayer(name: "Alex")
        let taggedKept = kept.mergingTags(MatchTags(opponents: [forgottenPlayer], updatedAt: Date(timeIntervalSince1970: 3_000)))

        // Local history is undecodable, but local tombstones and forgotten-player ledger are intact.
        try archiveFromNewerBuild().write(to: fixture.historyURL)
        try encode([deleted.id], to: fixture.tombstoneURL)
        try encode(ForgottenPlayerLedger(playerIDs: [forgottenPlayer.id]), to: fixture.ledgerURL)

        // Older iCloud backup predates both the permanent delete and the forget.
        try FileManager.default.createDirectory(at: fixture.backup, withIntermediateDirectories: true)
        try encode([taggedKept, deleted], to: fixture.backupHistoryURL)
        try encode([UUID](), to: fixture.backupTombstoneURL)

        let store = try fixture.makeBackingUpStore(startsICloudSync: false)
        #expect(store.archiveProblem == .undecodable)

        let restoredCount = try await store.restoreArchiveFromICloud()
        #expect(restoredCount == 1)
        #expect(store.loadHistory().map(\.id) == [kept.id])
        #expect(store.loadHistory().first?.tags?.opponents.isEmpty == true)
        #expect(store.forgottenPlayerLedger().contains(forgottenPlayer.id))
        let persistedTombstones = try JSONDecoder().decode([UUID].self, from: Data(contentsOf: fixture.tombstoneURL))
        #expect(Set(persistedTombstones) == [deleted.id])
    }

    @Test func bringBackWithheldMatchesAdoptsRemoteDeletionLedgersAndRefusesCorruptLedgers() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let kept = record(health: false)
        let forgottenPlayer = TaggedPlayer(name: "Sam")
        let withheld = record(health: false).mergingTags(
            MatchTags(opponents: [forgottenPlayer], updatedAt: Date(timeIntervalSince1970: 3_000))
        )
        try encode([kept], to: fixture.historyURL)
        try encode([UUID](), to: fixture.tombstoneURL)
        try encode(BackupManifest(recordIDs: [kept.id, withheld.id], tombstones: [], identityKey: "account-a"), to: fixture.manifestURL)
        try FileManager.default.createDirectory(at: fixture.backup, withIntermediateDirectories: true)
        try encode([kept, withheld], to: fixture.backupHistoryURL)
        try encode([UUID](), to: fixture.backupTombstoneURL)

        let store = try fixture.makeBackingUpStore(startsICloudSync: false)
        #expect(await pushNow(store) == true)

        // Corrupt remote ledger must refuse bring-back instead of bypassing deletion intent.
        try Data(#"{"playerIDs":["bad-id"]}"#.utf8).write(to: fixture.backupLedgerURL)
        await #expect(throws: PhoneStatsStore.RecoveryError.backupUnavailable) {
            try await store.bringBackWithheldMatches()
        }

        // Valid remote ledger is unioned locally and scrubs the restored match.
        try encode(ForgottenPlayerLedger(playerIDs: [forgottenPlayer.id]), to: fixture.backupLedgerURL)
        let result = try await store.bringBackWithheldMatches()
        #expect(result.restored == 1 && result.stillMissing == 0)
        #expect(store.forgottenPlayerLedger().contains(forgottenPlayer.id))
        let restoredMatch = try #require(store.loadHistory().first { $0.id == withheld.id })
        #expect(restoredMatch.tags?.opponents.isEmpty == true)
    }

    @Test func removeFromBackupRejectsStaleAccountBaselineAfterAccountSwitch() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let accountA = fixture.root.appendingPathComponent("iCloudA", isDirectory: true)
        let accountB = fixture.root.appendingPathComponent("iCloudB", isDirectory: true)
        try FileManager.default.createDirectory(at: accountA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: accountB, withIntermediateDirectories: true)

        let kept = record(health: false), lostA = record(health: false), matchB = record(health: false)
        try encode([kept], to: fixture.historyURL)
        try encode([UUID](), to: fixture.tombstoneURL)
        try encode(BackupManifest(recordIDs: [kept.id, lostA.id], tombstones: [], identityKey: "account-a"), to: fixture.manifestURL)
        try encode([kept, lostA], to: accountA.appendingPathComponent("matchHistory.json"))
        try encode([UUID](), to: accountA.appendingPathComponent("deletedMatchIDs.json"))

        let accountBBytes = try JSONEncoder().encode([kept, matchB])
        try accountBBytes.write(to: accountB.appendingPathComponent("matchHistory.json"))
        try encode([UUID](), to: accountB.appendingPathComponent("deletedMatchIDs.json"))

        var activeContainer = accountA
        var activeIdentity = "account-a"
        let store = try fixture.makeBackingUpStore(
            container: { activeContainer },
            identityKey: { activeIdentity },
            startsICloudSync: false
        )
        #expect(await pushNow(store) == true)
        #expect(await MainActor.run { store.withheldBackupMatchCount } == 1)

        // User switches to Account B before tapping Remove from Backup: stale
        // Account A baseline must be rejected and Account B left untouched.
        activeContainer = accountB
        activeIdentity = "account-b"
        await #expect(throws: PhoneStatsStore.RecoveryError.backupUnavailable) {
            try await store.removeWithheldMatchesFromBackup(confirmed: store.withheldBackupMatchIDs())
        }
        #expect(try Data(contentsOf: accountB.appendingPathComponent("matchHistory.json")) == accountBBytes)
        #expect(await MainActor.run { store.isBackupWithheld } == false)
    }

    @Test func interruptedDeleteReplaysPersistedTombstonesOnRelaunch() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let kept = record(health: false)
        let deleted = record(health: false)
        // Simulate a crash after writing deletedMatchIDs.json but before rewriting matchHistory.json.
        try encode([kept, deleted], to: fixture.historyURL)
        try encode([deleted.id], to: fixture.tombstoneURL)

        let store = fixture.makeStore()
        #expect(store.archiveProblem == nil)
        #expect(store.loadHistory().map(\.id) == [kept.id])
        let persisted = try JSONDecoder().decode([MatchRecord].self, from: Data(contentsOf: fixture.historyURL))
        #expect(persisted.map(\.id) == [kept.id])
    }

    @Test func bringBackWithheldMatchesFiltersExistingLocalRecordsMatchingRemoteTombstones() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let kept = record(health: false)
        let deletedRemotely = record(health: false)
        let withheld = record(health: false)

        try encode([kept, deletedRemotely], to: fixture.historyURL)
        try encode([UUID](), to: fixture.tombstoneURL)
        try encode(
            BackupManifest(recordIDs: [kept.id, deletedRemotely.id, withheld.id], tombstones: [], identityKey: "account-a"),
            to: fixture.manifestURL
        )
        try FileManager.default.createDirectory(at: fixture.backup, withIntermediateDirectories: true)
        try encode([kept, withheld], to: fixture.backupHistoryURL)
        try encode([deletedRemotely.id], to: fixture.backupTombstoneURL)

        let store = try fixture.makeBackingUpStore(startsICloudSync: false)
        #expect(await pushNow(store) == true)

        let result = try await store.bringBackWithheldMatches()
        #expect(result.restored == 1 && result.stillMissing == 0)
        #expect(Set(store.loadHistory().map(\.id)) == [kept.id, withheld.id])
        let persistedTombstones = try JSONDecoder().decode([UUID].self, from: Data(contentsOf: fixture.tombstoneURL))
        #expect(Set(persistedTombstones) == [deletedRemotely.id])
    }

    // MARK: - Versioned archive readers (TECHNICAL_DEBT #19)

    @Test func version1EnvelopesLoadCleanlyAndWritersStayBareArrayCompatible() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let saved = record(health: false)
        let deletedID = UUID()
        try PersistedArchiveCodec.encodeEnvelope([saved], format: PersistedArchiveCodec.historyFormat)
            .write(to: fixture.historyURL)
        try PersistedArchiveCodec.encodeEnvelope([deletedID], format: PersistedArchiveCodec.tombstonesFormat)
            .write(to: fixture.tombstoneURL)

        let store = fixture.makeStore()
        #expect(store.archiveProblem == nil)
        #expect(store.loadHistory() == [saved])
        #expect(store.tombstoneIDs == [deletedID])

        // Step-1 rollout: writers keep emitting bare JSON arrays for older builds.
        let added = record(health: false)
        #expect(store.appendMatchDurably(added))
        #expect(try Data(contentsOf: fixture.historyURL).first == UInt8(ascii: "["))
        #expect(try Data(contentsOf: fixture.tombstoneURL).first == UInt8(ascii: "["))
    }

    @Test func futureEnvelopeInHistoryOrTombstonesDiagnosesNewerVersionAndSuspendsWrites() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let futureHistory = Data("""
        {"format":"deucemate.matchHistory","schemaVersion":2,"items":[{"id":"not-a-uuid","outcome":"smash"}]}
        """.utf8)
        try futureHistory.write(to: fixture.historyURL)
        try encode([UUID](), to: fixture.tombstoneURL)

        let historyStore = fixture.makeStore()
        #expect(historyStore.archiveProblem == .newerVersion)
        #expect(!historyStore.appendMatchDurably(record()))
        #expect(try Data(contentsOf: fixture.historyURL) == futureHistory)

        // Newer version outranks unreadable when both fail.
        try FileManager.default.removeItem(at: fixture.tombstoneURL)
        try FileManager.default.createDirectory(at: fixture.tombstoneURL, withIntermediateDirectories: true)
        #expect(fixture.makeStore().archiveProblem == .newerVersion)

        // Future tombstone envelope with healthy history also diagnoses `.newerVersion`.
        let fixture2 = try Fixture()
        defer { fixture2.remove() }
        let existing = record(health: false)
        let futureTombstones = Data(#"{"format":"deucemate.deletedMatchIDs","schemaVersion":2,"items":[{"bad":1}]}"#.utf8)
        try encode([existing], to: fixture2.historyURL)
        try futureTombstones.write(to: fixture2.tombstoneURL)

        let tombstoneStore = fixture2.makeStore()
        #expect(tombstoneStore.archiveProblem == .newerVersion)
        #expect(tombstoneStore.loadHistory().isEmpty)
        #expect(try Data(contentsOf: fixture2.tombstoneURL) == futureTombstones)
    }

    @Test func remoteVersion1EnvelopeSupportsBackupBaselineAndRestore() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let local = record(health: false), remoteOnly = record(health: false), deletedID = UUID()
        try encode([local], to: fixture.historyURL)
        try encode([UUID](), to: fixture.tombstoneURL)
        try FileManager.default.createDirectory(at: fixture.backup, withIntermediateDirectories: true)
        let remoteEnvelope = try PersistedArchiveCodec.encodeEnvelope(
            [local, remoteOnly],
            format: PersistedArchiveCodec.historyFormat
        )
        try remoteEnvelope.write(to: fixture.backupHistoryURL)
        try PersistedArchiveCodec.encodeEnvelope(
            [deletedID],
            format: PersistedArchiveCodec.tombstonesFormat
        ).write(to: fixture.backupTombstoneURL)

        // Push without a manifest inspects the v1 remote envelope via BackupRecordID and withholds.
        let store = try fixture.makeBackingUpStore(startsICloudSync: false)
        #expect(await pushNow(store) == true)
        #expect(try Data(contentsOf: fixture.backupHistoryURL) == remoteEnvelope)

        // Restore from iCloud also decodes v1 remote envelopes cleanly.
        try archiveFromNewerBuild().write(to: fixture.historyURL)
        let brokenStore = try fixture.makeBackingUpStore(startsICloudSync: false)
        #expect(brokenStore.archiveProblem == .undecodable)
        let restored = try await brokenStore.restoreArchiveFromICloud()
        #expect(restored == 2)
        #expect(Set(brokenStore.loadHistory().map(\.id)) == [local.id, remoteOnly.id])
    }

    // MARK: - Carried over from the stacked #18 PRs (#224–#227)

    @Test func unreadableMainReportsUnreadableProblem() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.historyURL, withIntermediateDirectories: true)

        #expect(fixture.makeStore().archiveProblem == .unreadable)
    }

    @Test func manualMergeWhileSuspendedFailsInsteadOfClaimingSuccess() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try archiveFromNewerBuild()
        try original.write(to: fixture.historyURL)
        let store = fixture.makeStore()
        let archive = try ManualMatchArchiveBackup.encode(records: [record()])

        // A Merge into an archive that couldn't be loaded would hide that the
        // damaged matches aren't in it, so it stays refused.
        #expect(throws: (any Error).self) {
            try store.importManualArchive(data: archive, mode: .merge)
        }
        #expect(store.loadHistory().isEmpty)
        #expect(try Data(contentsOf: fixture.historyURL) == original)
    }

    @Test func mergeImportPushesWithoutWithholding() async throws {
        // Merge never drops matches, so the guard has nothing to withhold.
        let fixture = try Fixture()
        defer { fixture.remove() }
        let existing = record(), added = record()
        try encode([existing.strippingHealthData()], to: fixture.historyURL)
        try encode([UUID](), to: fixture.tombstoneURL)
        let store = try fixture.makeBackingUpStore()
        _ = await pushNow(store)

        try store.importManualArchive(data: ManualMatchArchiveBackup.encode(records: [added]), mode: .merge)

        #expect(await pushNow(store) == false)
        #expect(try backupIDs(fixture) == [existing.id, added.id])
    }

    @Test func confirmedReplaceImportRecoversASuspendedArchiveAndKeepsACopy() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try archiveFromNewerBuild()
        try original.write(to: fixture.historyURL)
        let store = fixture.makeStore()
        let replacement = record()

        try store.importManualArchive(data: ManualMatchArchiveBackup.encode(records: [replacement]), mode: .replace)

        #expect(await MainActor.run { store.archiveProblem } == nil)
        #expect(store.loadHistory().map(\.id) == [replacement.id])
        #expect(try JSONDecoder().decode([MatchRecord].self, from: Data(contentsOf: fixture.historyURL)).map(\.id) == [replacement.id])
        let kept = try recoveredFiles(fixture).filter { $0.lastPathComponent == "matchHistory.json" }
        #expect(kept.count == 1)
        #expect(try kept.first.map { try Data(contentsOf: $0) } == original)
    }

    @Test func tryAgainThatStillFailsChangesNothing() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try archiveFromNewerBuild()
        try original.write(to: fixture.historyURL)
        let store = fixture.makeStore()
        let arrived = record()
        // Refused while paused: the Watch keeps its copy and resends later.
        #expect(store.appendMatchDurably(arrived) == false)

        #expect(await store.retryArchiveLoad() == .undecodable)
        #expect(await MainActor.run { store.archiveProblem } == .undecodable)
        #expect(store.loadHistory().isEmpty)
        #expect(try Data(contentsOf: fixture.historyURL) == original)
    }

    @Test func restoreOfferExplainsAMissingBackupAndChangesNothing() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try archiveFromNewerBuild()
        try original.write(to: fixture.historyURL)
        let store = try fixture.makeBackingUpStore()

        #expect(await store.iCloudRestoreOffer() == .noBackup)
        await #expect(throws: PhoneStatsStore.RecoveryError.backupUnavailable) {
            try await store.restoreArchiveFromICloud()
        }
        #expect(try Data(contentsOf: fixture.historyURL) == original)
        #expect(try recoveredFiles(fixture).isEmpty)
    }

    @Test func savedMatchThatCannotBeWrittenChangesNothingAndSavesOnceWritable() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.makeStore()
        let existing = record()
        #expect(store.appendMatchDurably(existing))
        try fixture.blockCanonicalWrites()

        let manual = record()
        #expect(store.appendMatchDurably(manual) == false)
        #expect(store.loadHistory().map(\.id) == [existing.id])

        try fixture.unblockCanonicalWrites()
        #expect(fixture.makeStore().loadHistory().map(\.id) == [existing.id])
        #expect(store.appendMatchDurably(manual))
        #expect(Set(fixture.makeStore().loadHistory().map(\.id)) == [existing.id, manual.id])
    }

    @Test func permanentDeletionThatCannotBeWrittenKeepsTheMatch() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.makeStore()
        let match = record()
        #expect(store.appendMatchDurably(match))
        try fixture.blockCanonicalWrites()

        #expect(store.deletePermanently(id: match.id) == false)

        // Still listed, and no tombstone in memory or on disk: the caller keeps
        // the note and doesn't delete it on the Watch.
        #expect(store.loadHistory().map(\.id) == [match.id])
        #expect(try JSONDecoder().decode([UUID].self, from: Data(contentsOf: fixture.tombstoneURL)).isEmpty)
        try fixture.unblockCanonicalWrites()
        #expect(fixture.makeStore().loadHistory().map(\.id) == [match.id])

        #expect(store.deletePermanently(id: match.id))
        #expect(fixture.makeStore().loadHistory().isEmpty)
        #expect(try JSONDecoder().decode([UUID].self, from: Data(contentsOf: fixture.tombstoneURL)) == [match.id])
    }

    @Test func saveAndDeleteWhilePausedAreRefusedAndChangeNothing() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try archiveFromNewerBuild()
        try original.write(to: fixture.historyURL)
        let store = fixture.makeStore()

        #expect(store.appendMatchDurably(record()) == false)
        #expect(store.deletePermanently(id: UUID()) == false)
        #expect(store.loadHistory().isEmpty)
        #expect(try Data(contentsOf: fixture.historyURL) == original)
        #expect(FileManager.default.fileExists(atPath: fixture.tombstoneURL.path) == false)
    }

    // MARK: - A write that fails after the deletion intent (TECHNICAL_DEBT #18)

    /// Lets the deletion-intent files be written, then fails the Health
    /// sidecar write that follows them.
    private func failWritesAfterDeletionIntent(_ fixture: Fixture) throws {
        try? FileManager.default.removeItem(at: fixture.healthURL)
        try FileManager.default.createDirectory(at: fixture.healthURL, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: fixture.healthURL.appendingPathComponent("blocker"))
    }

    @Test func deleteThatFailsAfterItsTombstoneIsWrittenLeavesNoTombstoneBehind() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.makeStore()
        let match = record()
        #expect(store.appendMatchDurably(match))
        let tombstonesBefore = try Data(contentsOf: fixture.tombstoneURL)
        try failWritesAfterDeletionIntent(fixture)

        #expect(store.deletePermanently(id: match.id) == false)

        // The caller says the match wasn't deleted, keeps its note and leaves
        // the Watch alone, so a relaunch must still show it.
        #expect(try Data(contentsOf: fixture.tombstoneURL) == tombstonesBefore)
        try FileManager.default.removeItem(at: fixture.healthURL)
        #expect(fixture.makeStore().loadHistory().map(\.id) == [match.id])
    }

    @Test func forgetThatFailsAfterTheLedgerIsWrittenLeavesTheLedgerAsItWas() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.makeStore()
        #expect(store.appendMatchDurably(record()))
        let ledgerBefore = try Data(contentsOf: fixture.ledgerURL)
        try failWritesAfterDeletionIntent(fixture)

        #expect(throws: PhoneStatsStore.TagEditError.notPersisted) {
            _ = try store.forgetPlayer(UUID())
        }

        #expect(try Data(contentsOf: fixture.ledgerURL) == ledgerBefore)
    }

    // MARK: - Recovery review fixes (TECHNICAL_DEBT #18)

    /// A backup history holding `kept` plus one record only a newer build reads.
    private func backupBytesWithNewerRecord(_ kept: MatchRecord) throws -> Data {
        Data("""
        [\(String(decoding: try JSONEncoder().encode(kept.strippingHealthData()), as: UTF8.self)),
         {"id":"\(UUID().uuidString)","stats":[{"outcome":"smash"}]}]
        """.utf8)
    }

    @Test func confirmedReplaceKeepsACopyOfTheICloudBackupIncludingUndecodableMatches() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let old = record(), replacement = record()
        try encode([old.strippingHealthData()], to: fixture.historyURL)
        try encode([UUID](), to: fixture.tombstoneURL)
        try encode(BackupManifest(recordIDs: [old.id], tombstones: [], identityKey: "account-a"), to: fixture.manifestURL)
        try FileManager.default.createDirectory(at: fixture.backup, withIntermediateDirectories: true)
        let backupBytes = try backupBytesWithNewerRecord(old)
        try backupBytes.write(to: fixture.backupHistoryURL)
        try encode([UUID](), to: fixture.backupTombstoneURL)
        let store = try fixture.makeBackingUpStore(startsICloudSync: false)

        try store.importManualArchive(data: ManualMatchArchiveBackup.encode(records: [replacement]), mode: .replace)

        let copy = try #require(try recoveredFiles(fixture).first { $0.lastPathComponent == "iCloud-matchHistory.json" })
        #expect(try Data(contentsOf: copy) == backupBytes)
        // The Replace then goes through and the backup matches the archive.
        _ = await pushNow(store)
        #expect(try backupIDs(fixture) == [replacement.id])
    }

    @Test func replaceDoesNotOverwriteTheBackupWhenItsCopyCannotBeKept() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let old = record(), replacement = record()
        try encode([old.strippingHealthData()], to: fixture.historyURL)
        try encode([UUID](), to: fixture.tombstoneURL)
        try encode(BackupManifest(recordIDs: [old.id], tombstones: [], identityKey: "account-a"), to: fixture.manifestURL)
        try FileManager.default.createDirectory(at: fixture.backup, withIntermediateDirectories: true)
        let backupBytes = try backupBytesWithNewerRecord(old)
        try backupBytes.write(to: fixture.backupHistoryURL)
        try encode([UUID](), to: fixture.backupTombstoneURL)
        let store = try fixture.makeBackingUpStore(startsICloudSync: false)
        // A file where the Recovered folder must go: the copy cannot be made.
        let recovered = fixture.canonical.appendingPathComponent("Recovered")
        try Data("x".utf8).write(to: recovered)

        try store.importManualArchive(data: ManualMatchArchiveBackup.encode(records: [replacement]), mode: .replace)
        _ = await pushNow(store)
        #expect(try Data(contentsOf: fixture.backupHistoryURL) == backupBytes)

        // Once the copy can be made, the Replace goes through.
        try FileManager.default.removeItem(at: recovered)
        _ = await pushNow(store)
        #expect(try backupIDs(fixture) == [replacement.id])
        #expect(try recoveredFiles(fixture).contains { $0.lastPathComponent == "iCloud-matchHistory.json" })
    }

    @Test func replaceWhileSignedOutDoesNotClaimThePreviousAccountsPush() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try encode([record().strippingHealthData()], to: fixture.historyURL)
        try encode([UUID](), to: fixture.tombstoneURL)
        try encode(BackupManifest(recordIDs: [], tombstones: [], identityKey: "account-a"), to: fixture.manifestURL)
        let store = try fixture.makeBackingUpStore(container: { nil }, identityKey: { nil }, startsICloudSync: false)
        let replacement = record()

        try store.importManualArchive(data: ManualMatchArchiveBackup.encode(records: [replacement]), mode: .replace)

        let manifest = try JSONDecoder().decode(BackupManifest.self, from: Data(contentsOf: fixture.manifestURL))
        #expect(manifest.identityKey == nil)
        #expect(manifest.recordIDs == [replacement.id])
    }

    @Test func freshInstallWithANewerFormatBackupOffersReadableMatchesAndKeepsTheRest() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let readable = record(health: false)
        try FileManager.default.createDirectory(at: fixture.backup, withIntermediateDirectories: true)
        let backupBytes = try backupBytesWithNewerRecord(readable)
        try backupBytes.write(to: fixture.backupHistoryURL)
        try encode([UUID](), to: fixture.backupTombstoneURL)
        let backup = fixture.backup
        // No archiveInitialized marker: this is the one-time initial restore.
        let store = PhoneStatsStore(storageConfiguration: .init(
            canonicalDirectoryURL: fixture.canonical,
            legacyDocumentsDirectoryURL: fixture.legacyDocuments,
            startsICloudSync: false,
            backupContainerURL: { backup },
            backupIdentityKey: { "account-a" }
        ))

        store.syncICloudBackup()
        _ = store.loadHistory()
        var preview: ArchiveBackupPolicy.BackupPreview?
        for _ in 0..<40 where preview == nil {
            preview = await MainActor.run { store.pendingRestorePreview }
            if preview == nil { try await Task.sleep(for: .milliseconds(50)) }
        }
        #expect(preview?.recordCount == 1)
        #expect(preview?.newerFormatCount == 1)

        store.confirmRestore()
        _ = store.loadHistory()
        #expect(store.loadHistory().map(\.id) == [readable.id])
        // The newer-format match is still in iCloud and protected.
        _ = await pushNow(store)
        #expect(try Data(contentsOf: fixture.backupHistoryURL) == backupBytes)
        #expect(await MainActor.run { store.withheldBackupMatchCount } == 1)
    }

    @Test func removeFromBackupRefusesWhenMoreIsWithheldThanWasConfirmed() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let (store, _, lost, backupBytes) = try await withheldSetup(fixture)
        let confirmed = store.withheldBackupMatchIDs()
        #expect(confirmed == [lost.id])

        // A different match than the one the user saw.
        await #expect(throws: PhoneStatsStore.RecoveryError.withheldSetChanged) {
            try await store.removeWithheldMatchesFromBackup(confirmed: [UUID()])
        }
        #expect(try Data(contentsOf: fixture.backupHistoryURL) == backupBytes)
        #expect(await MainActor.run { store.isBackupWithheld } == true)
        #expect(try recoveredFiles(fixture).isEmpty)

        try await store.removeWithheldMatchesFromBackup(confirmed: confirmed)
        #expect(await MainActor.run { store.isBackupWithheld } == false)
    }

    @Test func bringBackThatAdoptsMatchesButCannotPushReportsSuccessNotFailure() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let (store, kept, lost, backupBytes) = try await withheldSetup(fixture)
        // A read-only backup folder: reads work, the push write fails.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: fixture.backup.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.backup.path) }

        let result = try await store.bringBackWithheldMatches()

        #expect(result.restored == 1)
        #expect(result.backupUpdated == false)
        #expect(Set(store.loadHistory().map(\.id)) == [kept.id, lost.id])
        #expect(try Data(contentsOf: fixture.backupHistoryURL) == backupBytes)
    }

    @Test func saveACopyKeepsFilesAfterwardsAndSweepsOnlyStaleEarlierCopies() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try archiveFromNewerBuild().write(to: fixture.historyURL)
        let store = fixture.makeStore()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeuceMate Archive Copies", isDirectory: true)
        let stale = root.appendingPathComponent("stale-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stale, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.creationDate: Date(timeIntervalSinceNow: -3 * 24 * 60 * 60)], ofItemAtPath: stale.path
        )
        let first = try store.copyPreservedArchiveForSharing()
        let second = try store.copyPreservedArchiveForSharing()
        defer { try? FileManager.default.removeItem(at: first[0].deletingLastPathComponent()) }
        defer { try? FileManager.default.removeItem(at: second[0].deletingLastPathComponent()) }

        #expect(!FileManager.default.fileExists(atPath: stale.path))
        // A recent copy (an AirDrop may still be reading it) survives the next one.
        #expect(FileManager.default.fileExists(atPath: first[0].path))
        #expect(FileManager.default.fileExists(atPath: second[0].path))
    }

    @Test func restoreFromICloudReportsWhenBackupCouldNotBeSwitchedBackOn() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let kept = record(health: false)
        try archiveFromNewerBuild().write(to: fixture.historyURL)
        try FileManager.default.createDirectory(at: fixture.backup, withIntermediateDirectories: true)
        try encode([kept], to: fixture.backupHistoryURL)
        try encode([UUID](), to: fixture.backupTombstoneURL)
        let store = try fixture.makeBackingUpStore(startsICloudSync: false)
        // The marker can't be written: a non-empty folder sits where it goes.
        try FileManager.default.removeItem(at: fixture.initializedURL)
        try FileManager.default.createDirectory(at: fixture.initializedURL, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: fixture.initializedURL.appendingPathComponent("blocker"))

        await #expect(throws: PhoneStatsStore.RecoveryError.restoredButBackupNotResumed) {
            try await store.restoreArchiveFromICloud()
        }
        #expect(store.loadHistory().map(\.id) == [kept.id])
        #expect(await MainActor.run { store.archiveProblem } == nil)
    }
}
