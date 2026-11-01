import Foundation
import DeuceMateCore
import Testing
@testable import DeuceMate

struct PlayerDetailsStoreTests {
    @Test func detailsUpdateIsPersistedAcrossEveryRoleAndKeepsUnknownRawValues() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("player-details-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("Archive", isDirectory: true)
        let docs = root.appendingPathComponent("Documents", isDirectory: true)
        let store = PhoneStatsStore(storageConfiguration: .init(
            canonicalDirectoryURL: archive,
            legacyDocumentsDirectoryURL: docs,
            startsICloudSync: false
        ))

        let player = TaggedPlayer(name: "Alex")
        var first = MatchRecord(startTime: Date(timeIntervalSince1970: 1), endTime: Date(timeIntervalSince1970: 2), setScores: [], stats: [], iWon: true)
        first.tags = MatchTags(opponents: [player], updatedAt: Date(timeIntervalSince1970: 1))
        var second = MatchRecord(startTime: Date(timeIntervalSince1970: 3), endTime: Date(timeIntervalSince1970: 4), setScores: [], stats: [], iWon: true)
        second.tags = MatchTags(partner: player, updatedAt: Date(timeIntervalSince1970: 3))
        store.saveHistory([first, second])

        let changed = try store.updatePlayerDetails(
            player.id,
            handednessRaw: PlayerHandedness.leftHanded.rawValue,
            backhandRaw: PlayerBackhand.oneHanded.rawValue,
            playStyleRaw: "future-style"
        )

        #expect(changed == [first.id, second.id])
        let relaunched = PhoneStatsStore(storageConfiguration: .init(
            canonicalDirectoryURL: archive,
            legacyDocumentsDirectoryURL: docs,
            startsICloudSync: false
        ))
        let records = relaunched.loadHistory()
        let snapshots = records.compactMap { record -> TaggedPlayer? in
            record.tags?.allPlayers.first { $0.id == player.id }
        }
        #expect(snapshots.count == 2)
        #expect(snapshots.allSatisfy {
            $0.handedness == .leftHanded
                && $0.backhand == .oneHanded
                && $0.playStyleRaw == "future-style"
        })
    }

    @Test func clearingDetailsIsPersisted() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("player-details-clear-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("Archive", isDirectory: true)
        let docs = root.appendingPathComponent("Documents", isDirectory: true)
        let player = TaggedPlayer(
            name: "Alex",
            handednessRaw: PlayerHandedness.rightHanded.rawValue,
            backhandRaw: PlayerBackhand.twoHanded.rawValue,
            playStyleRaw: PlayerPlayStyle.allCourt.rawValue
        )
        var record = MatchRecord(startTime: Date(timeIntervalSince1970: 1), endTime: Date(timeIntervalSince1970: 2), setScores: [], stats: [], iWon: true)
        record.tags = MatchTags(opponents: [player], updatedAt: Date(timeIntervalSince1970: 1))
        let store = PhoneStatsStore(storageConfiguration: .init(canonicalDirectoryURL: archive, legacyDocumentsDirectoryURL: docs, startsICloudSync: false))
        store.saveHistory([record])

        try store.updatePlayerDetails(player.id, handednessRaw: nil, backhandRaw: nil, playStyleRaw: nil)

        let reloaded = PhoneStatsStore(storageConfiguration: .init(canonicalDirectoryURL: archive, legacyDocumentsDirectoryURL: docs, startsICloudSync: false))
        let savedPlayer = reloaded.loadHistory().first?.tags?.opponents.first
        #expect(savedPlayer?.handednessRaw == nil)
        #expect(savedPlayer?.backhandRaw == nil)
        #expect(savedPlayer?.playStyleRaw == nil)
    }

    @Test func failedDetailsWriteLeavesArchiveUntouched() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("player-details-failure-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = root.appendingPathComponent("Archive", isDirectory: true)
        let docs = root.appendingPathComponent("Documents", isDirectory: true)
        let player = TaggedPlayer(name: "Alex")
        var record = MatchRecord(startTime: Date(timeIntervalSince1970: 1), endTime: Date(timeIntervalSince1970: 2), setScores: [], stats: [], iWon: true)
        record.tags = MatchTags(opponents: [player], updatedAt: Date(timeIntervalSince1970: 1))
        let store = PhoneStatsStore(storageConfiguration: .init(canonicalDirectoryURL: archive, legacyDocumentsDirectoryURL: docs, startsICloudSync: false))
        store.saveHistory([record])

        let ledger = archive.appendingPathComponent("forgottenPlayers.json")
        try? FileManager.default.removeItem(at: ledger)
        try FileManager.default.createDirectory(at: ledger, withIntermediateDirectories: true)
        try Data("block".utf8).write(to: ledger.appendingPathComponent("blocker"))

        #expect(throws: PhoneStatsStore.TagEditError.notPersisted) {
            try store.updatePlayerDetails(
                player.id,
                handednessRaw: PlayerHandedness.leftHanded.rawValue,
                backhandRaw: PlayerBackhand.oneHanded.rawValue,
                playStyleRaw: PlayerPlayStyle.counterpuncher.rawValue
            )
        }
        #expect(store.loadHistory() == [record])
    }
}
