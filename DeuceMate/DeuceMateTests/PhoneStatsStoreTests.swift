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

        /// A local folder standing in for the iCloud container, so the real
        /// push path (and its guard) runs without iCloud.
        var backup: URL { root.appendingPathComponent("Backup", isDirectory: true) }
        var backupHistoryURL: URL { backup.appendingPathComponent("matchHistory.json") }
        var backupTombstoneURL: URL { backup.appendingPathComponent("deletedMatchIDs.json") }
        var manifestURL: URL { canonical.appendingPathComponent("backupManifest.json") }

        /// A store past its one-time initial restore that pushes to `backup`.
        func makeBackingUpStore() throws -> PhoneStatsStore {
            try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
            try JSONEncoder().encode(true)
                .write(to: canonical.appendingPathComponent("archiveInitialized.json"))
            let backupURL = backup
            return PhoneStatsStore(storageConfiguration: .init(
                canonicalDirectoryURL: canonical,
                legacyDocumentsDirectoryURL: legacyDocuments,
                startsICloudSync: true,
                backupContainerURL: { backupURL }
            ))
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }

        /// A non-empty folder where the Health sidecar goes. The sidecar is
        /// optional, so the archive still loads, but every canonical write
        /// fails (the sidecar is written before the history).
        func blockCanonicalWrites() throws {
            try? FileManager.default.removeItem(at: healthURL)
            try FileManager.default.createDirectory(at: healthURL, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: healthURL.appendingPathComponent("blocker"))
        }

        func unblockCanonicalWrites() throws {
            try FileManager.default.removeItem(at: healthURL)
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

    // MARK: - Undecodable canonical files fail closed (TECHNICAL_DEBT #18)

    /// A real archive written by a build that knows an outcome this one
    /// doesn't: valid JSON whose single unknown enum value fails the whole
    /// `[MatchRecord]` decode — the archive-wide amplifier #18 describes.
    private func archiveFromNewerBuild() throws -> Data {
        let json = String(decoding: try JSONEncoder().encode([record(health: false)]), as: UTF8.self)
        let newer = json.replacingOccurrences(of: "\"outcome\":\"winner\"", with: "\"outcome\":\"smash\"")
        #expect(newer != json)
        #expect((try? JSONDecoder().decode([MatchRecord].self, from: Data(newer.utf8))) == nil)
        return Data(newer.utf8)
    }

    @Test func cleanLoadReportsNoArchiveProblem() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try encode([record().strippingHealthData()], to: fixture.historyURL)

        #expect(fixture.makeStore().archiveProblem == nil)
    }

    @Test func undecodableMainIsPreservedInPlaceAndSuspendsWritesAcrossRelaunch() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try archiveFromNewerBuild()
        try original.write(to: fixture.historyURL)

        let store = fixture.makeStore()
        #expect(store.archiveProblem == .undecodable)
        store.appendMatch(record())
        store.deletePermanently(id: UUID())

        // In memory only: the file is byte-for-byte untouched and never moved
        // aside, so the next launch cannot mistake it for a missing archive.
        #expect(store.loadHistory().count == 1)
        #expect(try Data(contentsOf: fixture.historyURL) == original)
        #expect(!FileManager.default.fileExists(atPath: fixture.historyURL.appendingPathExtension("corrupt").path))
        #expect(!FileManager.default.fileExists(atPath: fixture.tombstoneURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.healthURL.path))

        // The regression this guards: before #18 the file was moved aside, so
        // a relaunch saw "missing", resumed writes and pushed an empty archive.
        let relaunched = fixture.makeStore()
        #expect(relaunched.archiveProblem == .undecodable)
        relaunched.appendMatch(record())
        #expect(try Data(contentsOf: fixture.historyURL) == original)
    }

    @Test func undecodableTombstonesSuspendWrites() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let damaged = Data("[\"not-a-uuid\"]".utf8)
        try damaged.write(to: fixture.tombstoneURL)

        let store = fixture.makeStore()
        store.appendMatch(record())

        // Losing tombstones would let a later sync or restore resurrect deletions.
        #expect(store.archiveProblem == .undecodable)
        #expect(!FileManager.default.fileExists(atPath: fixture.historyURL.path))
        #expect(try Data(contentsOf: fixture.tombstoneURL) == damaged)
    }

    @Test func undecodableForgottenPlayerLedgerSuspendsWrites() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let existing = record().strippingHealthData()
        try encode([existing], to: fixture.historyURL)
        let damaged = Data("not json {{{".utf8)
        try damaged.write(to: fixture.ledgerURL)

        let store = fixture.makeStore()
        store.appendMatch(record())

        // Dropping the ledger would forget which players the user asked to forget.
        #expect(store.archiveProblem == .undecodable)
        #expect(try Data(contentsOf: fixture.ledgerURL) == damaged)
        #expect(try JSONDecoder().decode([MatchRecord].self, from: Data(contentsOf: fixture.historyURL)) == [existing])
    }

    @Test func unreadableMainReportsUnreadableProblem() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.historyURL, withIntermediateDirectories: true)

        #expect(fixture.makeStore().archiveProblem == .unreadable)
    }

    @Test func undecodableOutranksUnreadableWhenBothFail() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.tombstoneURL, withIntermediateDirectories: true)
        try archiveFromNewerBuild().write(to: fixture.historyURL)

        #expect(fixture.makeStore().archiveProblem == .undecodable)
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
        #expect(throws: PhoneStatsStore.TagEditError.notPersisted) {
            try store.importManualArchive(data: archive, mode: .merge)
        }
        #expect(store.loadHistory().isEmpty)
        #expect(try Data(contentsOf: fixture.historyURL) == original)
    }

    // MARK: - iCloud backup push guard (TECHNICAL_DEBT #18)

    /// Runs a push now (cancelling the debounced one) and waits for it:
    /// `loadHistory()` is a barrier on the store's serial queue, and the main
    /// queue hop publishes `isBackupWithheld`.
    private func pushNow(_ store: PhoneStatsStore) async -> Bool {
        store.syncICloudBackup()
        _ = store.loadHistory()
        return await MainActor.run { store.isBackupWithheld }
    }

    private func backupIDs(_ fixture: Fixture) throws -> Set<UUID> {
        Set(try JSONDecoder().decode([MatchRecord].self, from: Data(contentsOf: fixture.backupHistoryURL)).map(\.id))
    }

    @Test func pushWritesTheBackupAndRemembersWhatItPushed() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let match = record()
        try encode([match.strippingHealthData()], to: fixture.historyURL)
        let store = try fixture.makeBackingUpStore()

        #expect(await pushNow(store) == false)
        #expect(try backupIDs(fixture) == [match.id])
        let manifest = try JSONDecoder().decode(BackupManifest.self, from: Data(contentsOf: fixture.manifestURL))
        #expect(manifest.recordIDs == [match.id])
    }

    @Test func deletingTheOnlyMatchStillEmptiesTheBackup() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let match = record()
        try encode([match.strippingHealthData()], to: fixture.historyURL)
        let store = try fixture.makeBackingUpStore()
        _ = await pushNow(store)

        store.deletePermanently(id: match.id)

        #expect(await pushNow(store) == false)
        #expect(try backupIDs(fixture).isEmpty)
        #expect(try JSONDecoder().decode([UUID].self, from: Data(contentsOf: fixture.backupTombstoneURL)) == [match.id])
    }

    @Test func unexplainedLossKeepsTheBackupsRecords() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        // The archive lists one match, but this iPhone last backed up two and
        // nothing records deleting the second: the loss is unexplained.
        let kept = record(), lost = record()
        try encode([kept.strippingHealthData()], to: fixture.historyURL)
        try encode(BackupManifest(recordIDs: [kept.id, lost.id], tombstones: []), to: fixture.manifestURL)
        try FileManager.default.createDirectory(at: fixture.backup, withIntermediateDirectories: true)
        let backupBytes = try JSONEncoder().encode([kept.strippingHealthData(), lost.strippingHealthData()])
        try backupBytes.write(to: fixture.backupHistoryURL)
        let store = try fixture.makeBackingUpStore()

        #expect(await pushNow(store) == true)
        #expect(try Data(contentsOf: fixture.backupHistoryURL) == backupBytes)
        // Tombstones are still pushed: they only make the backup safer.
        #expect(FileManager.default.fileExists(atPath: fixture.backupTombstoneURL.path))
    }

    @Test func withoutAManifestTheBaselineIsReadFromTheBackup() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        // First push after updating: no manifest yet, so the ids already in
        // the backup are the baseline — including a record from a newer build
        // that this build can't fully decode.
        let kept = record()
        try encode([kept.strippingHealthData()], to: fixture.historyURL)
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

    @Test func confirmedReplaceImportMayShrinkTheBackup() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let old = record(), replacement = record()
        try encode([old.strippingHealthData()], to: fixture.historyURL)
        let store = try fixture.makeBackingUpStore()
        _ = await pushNow(store)

        try store.importManualArchive(
            data: ManualMatchArchiveBackup.encode(records: [replacement]),
            mode: .replace
        )

        #expect(await pushNow(store) == false)
        #expect(try backupIDs(fixture) == [replacement.id])
    }

    @Test func mergeImportPushesWithoutWithholding() async throws {
        // Merge never drops matches, so the guard has nothing to withhold.
        let fixture = try Fixture()
        defer { fixture.remove() }
        let existing = record(), added = record()
        try encode([existing.strippingHealthData()], to: fixture.historyURL)
        let store = try fixture.makeBackingUpStore()
        _ = await pushNow(store)

        try store.importManualArchive(data: ManualMatchArchiveBackup.encode(records: [added]), mode: .merge)

        #expect(await pushNow(store) == false)
        #expect(try backupIDs(fixture) == [existing.id, added.id])
    }

    // MARK: - Recovery (TECHNICAL_DEBT #18, stage 3)

    /// Every file recovery kept under `MatchArchive/Recovered/<time>/`.
    private func recoveredFiles(_ fixture: Fixture) throws -> [URL] {
        let root = fixture.canonical.appendingPathComponent("Recovered", isDirectory: true)
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .flatMap { try FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil) }
    }

    @Test func confirmedReplaceImportRecoversASuspendedArchiveAndKeepsACopy() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try archiveFromNewerBuild()
        try original.write(to: fixture.historyURL)
        let store = fixture.makeStore()
        let replacement = record()

        // Stage 1 refused this; a confirmed Replace is now a way out.
        try store.importManualArchive(data: ManualMatchArchiveBackup.encode(records: [replacement]), mode: .replace)

        #expect(await MainActor.run { store.archiveProblem } == nil)
        #expect(store.loadHistory().map(\.id) == [replacement.id])
        #expect(try JSONDecoder().decode([MatchRecord].self, from: Data(contentsOf: fixture.historyURL)).map(\.id) == [replacement.id])
        let kept = try recoveredFiles(fixture)
        #expect(kept.map(\.lastPathComponent) == ["matchHistory.json"])
        #expect(try Data(contentsOf: kept[0]) == original)
    }

    @Test func tryAgainLoadsTheArchiveOnceReadableAndKeepsWhatArrivedMeanwhile() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.historyURL, withIntermediateDirectories: true)
        let store = fixture.makeStore()
        #expect(store.archiveProblem == .unreadable)
        let arrived = record()
        store.appendMatch(arrived) // in memory only while suspended

        // The temporary problem clears: the real archive is readable again.
        let saved = record()
        try FileManager.default.removeItem(at: fixture.historyURL)
        try encode([saved.strippingHealthData()], to: fixture.historyURL)

        #expect(await store.retryArchiveLoad() == nil)
        #expect(await MainActor.run { store.archiveProblem } == nil)
        #expect(Set(store.loadHistory().map(\.id)) == [saved.id, arrived.id])
        let onDisk = try JSONDecoder().decode([MatchRecord].self, from: Data(contentsOf: fixture.historyURL))
        #expect(Set(onDisk.map(\.id)) == [saved.id, arrived.id])
    }

    @Test func tryAgainThatStillFailsChangesNothing() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try archiveFromNewerBuild()
        try original.write(to: fixture.historyURL)
        let store = fixture.makeStore()
        let arrived = record()
        store.appendMatch(arrived)

        #expect(await store.retryArchiveLoad() == .undecodable)
        #expect(await MainActor.run { store.archiveProblem } == .undecodable)
        #expect(store.loadHistory().map(\.id) == [arrived.id])
        #expect(try Data(contentsOf: fixture.historyURL) == original)
    }

    @Test func tryAgainStaysPausedWhenWhatArrivedMeanwhileCannotBeSaved() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.historyURL, withIntermediateDirectories: true)
        let store = fixture.makeStore()
        #expect(store.archiveProblem == .unreadable)
        let arrived = record()
        store.appendMatch(arrived) // in memory only while suspended

        // The archive becomes readable, but storage still refuses writes.
        let saved = record()
        try FileManager.default.removeItem(at: fixture.historyURL)
        let savedBytes = try JSONEncoder().encode([saved.strippingHealthData()])
        try savedBytes.write(to: fixture.historyURL)
        try fixture.blockCanonicalWrites()

        // Not reported as recovered: nothing it holds is on disk yet.
        #expect(await store.retryArchiveLoad() == .unreadable)
        #expect(await MainActor.run { store.archiveProblem } == .unreadable)
        #expect(Set(store.loadHistory().map(\.id)) == [saved.id, arrived.id])
        #expect(try Data(contentsOf: fixture.historyURL) == savedBytes)

        // Once storage works, the next Try Again saves both.
        try fixture.unblockCanonicalWrites()
        #expect(await store.retryArchiveLoad() == nil)
        let onDisk = try JSONDecoder().decode([MatchRecord].self, from: Data(contentsOf: fixture.historyURL))
        #expect(Set(onDisk.map(\.id)) == [saved.id, arrived.id])
    }

    // MARK: User saves and deletes are all-or-nothing

    @Test func commitMatchWhileSuspendedThrowsAndChangesNothing() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try archiveFromNewerBuild()
        try original.write(to: fixture.historyURL)
        let store = fixture.makeStore()
        #expect(store.archiveProblem == .undecodable)

        #expect(throws: PhoneStatsStore.TagEditError.notPersisted) {
            try store.commitMatch(record())
        }

        // A manual entry the user was told failed is not shown as saved.
        #expect(store.loadHistory().isEmpty)
        #expect(try Data(contentsOf: fixture.historyURL) == original)
    }

    @Test func commitMatchThatCannotBeWrittenRollsBackAndSucceedsOnceWritable() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.makeStore()
        let existing = record()
        try store.commitMatch(existing)
        try fixture.blockCanonicalWrites()

        let manual = record()
        #expect(throws: PhoneStatsStore.TagEditError.notPersisted) {
            try store.commitMatch(manual)
        }
        #expect(store.loadHistory().map(\.id) == [existing.id])

        try fixture.unblockCanonicalWrites()
        #expect(fixture.makeStore().loadHistory().map(\.id) == [existing.id])
        try store.commitMatch(manual)
        #expect(Set(fixture.makeStore().loadHistory().map(\.id)) == [existing.id, manual.id])
    }

    @Test func commitPermanentDeletionThatCannotBeWrittenKeepsTheMatch() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.makeStore()
        let match = record()
        try store.commitMatch(match)
        try fixture.blockCanonicalWrites()

        #expect(throws: PhoneStatsStore.TagEditError.notPersisted) {
            try store.commitPermanentDeletion(id: match.id)
        }

        // Still listed, and no tombstone in memory or on disk: the caller keeps
        // the note and doesn't delete it on the Watch.
        #expect(store.loadHistory().map(\.id) == [match.id])
        #expect(try JSONDecoder().decode([UUID].self, from: Data(contentsOf: fixture.tombstoneURL)).isEmpty)
        try fixture.unblockCanonicalWrites()
        #expect(fixture.makeStore().loadHistory().map(\.id) == [match.id])

        try store.commitPermanentDeletion(id: match.id)
        #expect(fixture.makeStore().loadHistory().isEmpty)
        #expect(try JSONDecoder().decode([UUID].self, from: Data(contentsOf: fixture.tombstoneURL)) == [match.id])
    }

    @Test func commitPermanentDeletionWhileSuspendedThrowsAndKeepsTheMatch() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let existing = record().strippingHealthData()
        try encode([existing], to: fixture.historyURL)
        let damaged = Data("[\"not-a-uuid\"]".utf8)
        try damaged.write(to: fixture.tombstoneURL)
        let store = fixture.makeStore()
        #expect(store.archiveProblem == .undecodable)

        #expect(throws: PhoneStatsStore.TagEditError.notPersisted) {
            try store.commitPermanentDeletion(id: existing.id)
        }

        #expect(store.loadHistory().map(\.id) == [existing.id])
        #expect(try Data(contentsOf: fixture.tombstoneURL) == damaged)
    }

    @Test func saveACopySharesThePreservedFilesAndLeavesThemInPlace() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try archiveFromNewerBuild()
        try original.write(to: fixture.historyURL)
        try encode([UUID()], to: fixture.tombstoneURL)
        let store = fixture.makeStore()

        let copies = try store.copyPreservedArchiveForSharing()
        defer { copies.forEach { try? FileManager.default.removeItem(at: $0.deletingLastPathComponent()) } }

        #expect(Set(copies.map(\.lastPathComponent)) == ["matchHistory.json", "deletedMatchIDs.json"])
        let historyCopy = try #require(copies.first { $0.lastPathComponent == "matchHistory.json" })
        #expect(try Data(contentsOf: historyCopy) == original)
        #expect(try Data(contentsOf: fixture.historyURL) == original)
        #expect(store.archiveProblem == .undecodable)
    }

    @Test func restoreFromICloudReplacesAnUndecodableArchiveAndKeepsACopy() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try archiveFromNewerBuild()
        try original.write(to: fixture.historyURL)
        // The backup is health-stripped; the local sidecar still has the values.
        let backedUp = record()
        try encode(HealthSidecarPolicy.split([backedUp]).health, to: fixture.healthURL)
        try FileManager.default.createDirectory(at: fixture.backup, withIntermediateDirectories: true)
        try encode([backedUp.strippingHealthData()], to: fixture.backupHistoryURL)
        try encode([UUID](), to: fixture.backupTombstoneURL)
        let store = try fixture.makeBackingUpStore()
        #expect(store.archiveProblem == .undecodable)
        let arrived = record()
        store.appendMatch(arrived)

        guard case .available(let preview, let newer) = await store.iCloudRestoreOffer() else {
            Issue.record("expected the backup to be offered")
            return
        }
        #expect(preview.recordCount == 1)
        #expect(newer == 0)

        #expect(try await store.restoreArchiveFromICloud() == 2)
        #expect(await MainActor.run { store.archiveProblem } == nil)
        let restored = store.loadHistory()
        #expect(Set(restored.map(\.id)) == [backedUp.id, arrived.id])
        #expect(restored.first { $0.id == backedUp.id }?.totalSteps == 1_234)
        let kept = try recoveredFiles(fixture)
        #expect(try Data(contentsOf: #require(kept.first { $0.lastPathComponent == "matchHistory.json" })) == original)
        // Saving and backing up resume.
        #expect(await pushNow(store) == false)
        #expect(try backupIDs(fixture) == [backedUp.id, arrived.id])
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

    /// The `unexplainedLossKeepsTheBackupsRecords` setup: the backup holds
    /// `kept` and `lost`, the archive only `kept`, and nothing explains it.
    private func withheldSetup(_ fixture: Fixture) async throws -> (PhoneStatsStore, kept: MatchRecord, lost: MatchRecord, backupBytes: Data) {
        let kept = record(), lost = record()
        try encode([kept.strippingHealthData()], to: fixture.historyURL)
        try encode(BackupManifest(recordIDs: [kept.id, lost.id], tombstones: []), to: fixture.manifestURL)
        try FileManager.default.createDirectory(at: fixture.backup, withIntermediateDirectories: true)
        let backupBytes = try JSONEncoder().encode([kept.strippingHealthData(), lost.strippingHealthData()])
        try backupBytes.write(to: fixture.backupHistoryURL)
        let store = try fixture.makeBackingUpStore()
        #expect(await pushNow(store) == true)
        #expect(await MainActor.run { store.withheldBackupMatchCount } == 1)
        return (store, kept, lost, backupBytes)
    }

    @Test func bringBackRestoresTheWithheldMatchesAndResumesTheBackup() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let (store, kept, lost, _) = try await withheldSetup(fixture)

        let result = try await store.bringBackWithheldMatches()

        #expect(result.restored == 1 && result.stillMissing == 0)
        #expect(Set(store.loadHistory().map(\.id)) == [kept.id, lost.id])
        #expect(await MainActor.run { store.isBackupWithheld } == false)
        #expect(try backupIDs(fixture) == [kept.id, lost.id])
    }

    @Test func removeFromBackupLetsOnlyTheWithheldMatchesGoAndKeepsACopy() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let (store, kept, _, backupBytes) = try await withheldSetup(fixture)

        try await store.removeWithheldMatchesFromBackup()

        #expect(await MainActor.run { store.isBackupWithheld } == false)
        #expect(try backupIDs(fixture) == [kept.id])
        let copy = try #require(try recoveredFiles(fixture).first)
        #expect(copy.lastPathComponent == "iCloud-matchHistory.json")
        #expect(try Data(contentsOf: copy) == backupBytes)
        // The archive itself is untouched: removing from the backup is not a delete.
        #expect(store.loadHistory().map(\.id) == [kept.id])
    }
}
