//
//  MatchTypeWatchTests.swift
//  DeuceMate Watch AppTests
//

import Foundation
import DeuceMateCore
import Testing
@testable import DeuceMate_Watch_App

struct MatchTypeWatchTests {

    typealias MockStatsStore = DeuceMate_Watch_AppTests.MockStatsStore

    // MARK: - Helpers

    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("matchtype-test-\(UUID().uuidString).json")
    }

    private func makeRecord(
        id: UUID = UUID(),
        matchType: MatchType = .singles,
        isInProgress: Bool = false,
        matchTypeRevision: MatchTypeRevision? = nil,
        tags: MatchTags? = nil
    ) -> MatchRecord {
        MatchRecord(
            id: id,
            startTime: Date(timeIntervalSince1970: 1_000_000),
            endTime: isInProgress ? nil : Date(timeIntervalSince1970: 1_003_600),
            setScores: [SetScore(gamesMe: 6, gamesOpponent: 4)],
            stats: [],
            iWon: isInProgress ? nil : true,
            currentServer: .me,
            matchType: matchType,
            tags: tags,
            matchTypeRevision: matchTypeRevision
        )
    }

    private final class SyncSpy: MatchSyncService {
        var sent: [MatchRecord] = []
        var histories: [[MatchRecord]] = []
        var lastSyncDate: Date? { nil }
        func start() {}
        func sendMatch(_ record: MatchRecord, announcement: String?) { sent.append(record) }
        func clearActiveMatch() {}
        func sendFullHistory(_ records: [MatchRecord]) { histories.append(records) }
        func sendPendingPointState(_ pending: PendingPointInfo?, outcome: PointOutcome?) {}
    }

    private final class FailingStatsStore: WatchStatsStoring {
        private var records: [MatchRecord] = []
        func loadHistory() -> [MatchRecord] { records }
        func saveHistory(_ records: [MatchRecord]) { self.records = records }
        func completeStoredMatch(id: UUID, at date: Date) -> [MatchRecord]? { nil }
        func updateTags(id: UUID, tags: MatchTags) -> MatchRecord? { nil }
        func convertStoredMatchType(id: UUID, to matchType: MatchType, at date: Date) -> [MatchRecord]? { nil }
        func updateMatchType(id: UUID, revision: MatchTypeRevision) -> MatchRecord? { nil }
        func appendMatch(_ record: MatchRecord) { records.append(record) }
        func removeMatch(id: UUID) { records.removeAll { $0.id == id } }
        func removeMatchReturningTags(id: UUID) -> MatchTags? { nil }
    }

    // MARK: - 1. convertStoredMatchType: converts and persists

    @Test func convertStoredMatchTypeConvertsBetweenDoublesAndSinglesAndPersists() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = StatsStore(fileURL: url)

        let matchID = UUID()
        let tags = MatchTags(
            opponents: [TaggedPlayer(name: "Opponent 1"), TaggedPlayer(name: "Opponent 2")],
            partner: TaggedPlayer(name: "Partner"),
            competitionType: .league,
            updatedAt: Date(timeIntervalSince1970: 1_000_000)
        )
        let doublesRecord = makeRecord(
            id: matchID,
            matchType: .doubles,
            tags: tags
        )
        store.saveHistory([doublesRecord])

        let convertTime = Date(timeIntervalSince1970: 1_002_000)
        let converted = try #require(store.convertStoredMatchType(id: matchID, to: .singles, at: convertTime))
        #expect(converted.count == 1)
        let singlesRecord = converted[0]
        #expect(singlesRecord.matchType == .singles)
        #expect(singlesRecord.matchTypeRevision?.matchType == .singles)
        #expect(singlesRecord.matchTypeRevision?.updatedAt == convertTime)
        // Partner dropped, only first opponent kept
        #expect(singlesRecord.tags?.partner == nil)
        #expect(singlesRecord.tags?.opponents.count == 1)
        #expect(singlesRecord.tags?.opponents.first?.name == "Opponent 1")

        // Persists across fresh StatsStore load
        let freshStore = StatsStore(fileURL: url)
        let loaded = try #require(freshStore.loadHistoryOrNil())
        #expect(loaded.count == 1)
        #expect(loaded[0].matchType == .singles)
        #expect(loaded[0].matchTypeRevision == singlesRecord.matchTypeRevision)
        #expect(loaded[0].tags == singlesRecord.tags)

        // Convert back from singles to doubles
        let convertBackTime = Date(timeIntervalSince1970: 1_004_000)
        let convertedAgain = try #require(freshStore.convertStoredMatchType(id: matchID, to: .doubles, at: convertBackTime))
        #expect(convertedAgain.count == 1)
        let doublesAgain = convertedAgain[0]
        #expect(doublesAgain.matchType == .doubles)
        #expect(doublesAgain.matchTypeRevision?.matchType == .doubles)
        #expect(doublesAgain.matchTypeRevision?.updatedAt == convertBackTime)

        let reloaded = try #require(StatsStore(fileURL: url).loadHistoryOrNil())
        #expect(reloaded.count == 1)
        #expect(reloaded[0].matchType == .doubles)
        #expect(reloaded[0].matchTypeRevision == doublesAgain.matchTypeRevision)
    }

    // MARK: - 2. convertStoredMatchType: error handling and invariants

    @Test func convertStoredMatchTypeRefusesInvalidConditions() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = StatsStore(fileURL: url)

        // 1. Refuses in-progress match (nil)
        let inProgress = makeRecord(matchType: .doubles, isInProgress: true)
        store.saveHistory([inProgress])
        #expect(store.convertStoredMatchType(id: inProgress.id, to: .singles, at: Date()) == nil)
        #expect(store.loadHistoryOrNil()?.first?.matchType == .doubles)

        // 2. Refuses missing ID (nil)
        #expect(store.convertStoredMatchType(id: UUID(), to: .singles, at: Date()) == nil)

        // 3. Refuses unchanged type (nil)
        let completedDoubles = makeRecord(matchType: .doubles, isInProgress: false)
        store.saveHistory([completedDoubles])
        #expect(store.convertStoredMatchType(id: completedDoubles.id, to: .doubles, at: Date()) == nil)

        // 4. Refuses unreadable/corrupt archive (nil, preserves exact bytes on disk)
        let corruptURL = makeTempURL()
        defer { try? FileManager.default.removeItem(at: corruptURL) }
        try Data("corrupt json {{{".utf8).write(to: corruptURL)
        let beforeBytes = try Data(contentsOf: corruptURL)
        let corruptStore = StatsStore(fileURL: corruptURL)
        #expect(corruptStore.convertStoredMatchType(id: UUID(), to: .singles, at: Date()) == nil)
        let afterBytes = try Data(contentsOf: corruptURL)
        #expect(afterBytes == beforeBytes)

        // 5. Refuses failed write (nil)
        let failingURL = makeTempURL()
        defer { try? FileManager.default.removeItem(at: failingURL) }
        let failingStore = StatsStore(fileURL: failingURL, writeHistory: { _, _ in
            throw CocoaError(.fileWriteNoPermission)
        })
        try BackupExcludedFileWriter.write([completedDoubles], to: failingURL)
        #expect(failingStore.convertStoredMatchType(id: completedDoubles.id, to: .singles, at: Date()) == nil)
        let onDisk = try #require(StatsStore(fileURL: failingURL).loadHistoryOrNil())
        #expect(onDisk.first?.matchType == .doubles)
    }

    // MARK: - 3. updateMatchType: merges revision and rejects invalid cases

    @Test func updateMatchTypeAppliesRevisionAndRefusesInvalidCases() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = StatsStore(fileURL: url)

        let completed = makeRecord(matchType: .doubles, isInProgress: false)
        store.saveHistory([completed])

        let revTime = Date(timeIntervalSince1970: 1_005_000)
        let revID = UUID()
        let incomingRevision = MatchTypeRevision(
            matchType: .singles,
            updatedAt: revTime,
            revisionID: revID
        )

        // 1. Applies incoming MatchTypeRevision to completed match
        let updated = try #require(store.updateMatchType(id: completed.id, revision: incomingRevision))
        #expect(updated.matchType == .singles)
        #expect(updated.matchTypeRevision == incomingRevision)
        #expect(StatsStore(fileURL: url).loadHistoryOrNil()?.first?.matchType == .singles)

        // 2. Ignores missing ID (never creates record)
        let missingID = UUID()
        #expect(store.updateMatchType(id: missingID, revision: incomingRevision) == nil)
        let countAfterMissing = store.loadHistoryOrNil()?.count
        #expect(countAfterMissing == 1)

        // 3. Ignores in-progress match
        let inProgress = makeRecord(matchType: .doubles, isInProgress: true)
        store.saveHistory([inProgress])
        #expect(store.updateMatchType(id: inProgress.id, revision: incomingRevision) == nil)
        let inProgressAfter = store.loadHistoryOrNil()?.first(where: { $0.id == inProgress.id })
        #expect(inProgressAfter?.matchType == .doubles)
        #expect(inProgressAfter?.matchTypeRevision == nil)

        // 4. Refuses unreadable archive
        let corruptURL = makeTempURL()
        defer { try? FileManager.default.removeItem(at: corruptURL) }
        try Data("corrupt bytes {{{".utf8).write(to: corruptURL)
        let before = try Data(contentsOf: corruptURL)
        let corruptStore = StatsStore(fileURL: corruptURL)
        #expect(corruptStore.updateMatchType(id: completed.id, revision: incomingRevision) == nil)
        #expect(try Data(contentsOf: corruptURL) == before)
    }

    // MARK: - 4. appendMatch: preserves stored matchTypeRevision

    @Test func appendMatchPreservesStoredMatchTypeRevision() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = StatsStore(fileURL: url)

        let id = UUID()
        let rev = MatchTypeRevision(
            matchType: .doubles,
            updatedAt: Date(timeIntervalSince1970: 1_005_000),
            revisionID: UUID()
        )
        let stored = makeRecord(id: id, matchType: .doubles, isInProgress: false, matchTypeRevision: rev)
        store.saveHistory([stored])

        // An un-revised record replacing by ID
        let replacement = makeRecord(id: id, matchType: .singles, isInProgress: false, matchTypeRevision: nil)
        store.appendMatch(replacement)

        let loaded = try #require(store.loadHistoryOrNil())
        #expect(loaded.count == 1)
        #expect(loaded[0].matchTypeRevision == rev)
        #expect(loaded[0].matchType == .doubles)
    }

    // MARK: - 5. ScoreViewModel.convertStoredMatchType

    @MainActor
    @Test func scoreViewModelConvertStoredMatchType() throws {
        let store = MockStatsStore()
        let sync = SyncSpy()
        let stateURL = makeTempURL()
        defer { try? FileManager.default.removeItem(at: stateURL) }
        let viewModel = ScoreViewModel(statsStore: store, stateFileURL: stateURL)
        viewModel.syncService = sync

        // 1. Succeeds on completed stored match and pushes sendFullHistory with converted record
        let doublesRecord = makeRecord(matchType: .doubles, isInProgress: false)
        store.saveHistory([doublesRecord])

        let success = viewModel.convertStoredMatchType(doublesRecord, to: .singles)
        #expect(success == true)
        #expect(sync.histories.count == 1)
        #expect(sync.histories.first?.first?.matchType == .singles)
        #expect(store.loadHistory().first?.matchType == .singles)

        // 2. Returns false and does NOT sync when match is in-progress
        sync.histories.removeAll()
        let inProg = makeRecord(matchType: .doubles, isInProgress: true)
        store.saveHistory([inProg])
        #expect(viewModel.convertStoredMatchType(inProg, to: .singles) == false)
        #expect(sync.histories.isEmpty)

        // 3. Returns false and does NOT sync when match matches currentMatchID
        sync.histories.removeAll()
        let liveRecord = makeRecord(matchType: .doubles, isInProgress: false)
        store.saveHistory([liveRecord])
        viewModel.resumeMatch(liveRecord)
        #expect(viewModel.currentMatchID == liveRecord.id)
        #expect(viewModel.convertStoredMatchType(liveRecord, to: .singles) == false)
        #expect(sync.histories.isEmpty)
        viewModel.resetMatch()

        // 4. Returns false and does NOT sync when target matchType equals current record matchType
        sync.histories.removeAll()
        let singlesRecord = makeRecord(matchType: .singles, isInProgress: false)
        store.saveHistory([singlesRecord])
        #expect(viewModel.convertStoredMatchType(singlesRecord, to: .singles) == false)
        #expect(sync.histories.isEmpty)

        // 5. Returns false and does NOT sync when store returns nil (write failure)
        sync.histories.removeAll()
        let failingStore = FailingStatsStore()
        let stateURL2 = makeTempURL()
        defer { try? FileManager.default.removeItem(at: stateURL2) }
        let vmFailing = ScoreViewModel(statsStore: failingStore, stateFileURL: stateURL2)
        vmFailing.syncService = sync
        let targetRecord = makeRecord(matchType: .doubles, isInProgress: false)
        failingStore.saveHistory([targetRecord])
        #expect(vmFailing.convertStoredMatchType(targetRecord, to: .singles) == false)
        #expect(sync.histories.isEmpty)
    }
}
