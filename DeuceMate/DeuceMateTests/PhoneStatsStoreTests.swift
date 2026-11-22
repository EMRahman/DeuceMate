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
        #"{"schemaVersion":1,"playerIDs":42}"#,
        #"{"schemaVersion":1,"playerIDs":["00000000-0000-0000-0000-000000000001","bad-id"]}"#,
        #"{"schemaVersion":2,"playerIDs":[]}"#
    ])
    func malformedOrNewerForgottenPlayerLedgerSuspendsWrites(json: String) throws {
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

        try await store.removeWithheldMatchesFromBackup()

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
            try await store.removeWithheldMatchesFromBackup()
        }
        #expect(await MainActor.run { store.isBackupWithheld } == true)
    }
}
