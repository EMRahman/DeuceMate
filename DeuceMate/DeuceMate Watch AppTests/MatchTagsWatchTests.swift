//
//  MatchTagsWatchTests.swift
//  DeuceMate Watch AppTests
//
//  Match tags are phone-authored metadata the watch stores and shows but never
//  edits (MATCH_TAGS_PLAN.md PR 2). These tests pin the two halves of that:
//  `StatsStore.updateTags` obeys the "read failure != empty archive" rule, and
//  no watch write path that replaces a record by id can erase the tags
//  (§12.1 "Metadata independence").
//

import Foundation
import DeuceMateCore
import Testing
@testable import DeuceMate_Watch_App

struct MatchTagsWatchTests {

    // MARK: - Helpers

    private func makeTempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("matchtags-test-\(UUID().uuidString).json")
    }

    private func makeRecord(id: UUID = UUID(), tags: MatchTags? = nil) -> MatchRecord {
        MatchRecord(
            id: id,
            startTime: Date(timeIntervalSince1970: 1_000_000),
            setScores: [SetScore(gamesMe: 2, gamesOpponent: 1)],
            stats: [],
            currentServer: .me,
            tags: tags
        )
    }

    private func tags(_ opponent: String = "Alex",
                      type: CompetitionType? = .league,
                      at seconds: TimeInterval) -> MatchTags {
        MatchTags(opponents: [TaggedPlayer(name: opponent)],
                  competitionType: type,
                  updatedAt: Date(timeIntervalSince1970: seconds))
    }

    private final class SyncSpy: MatchSyncService {
        var sent: [MatchRecord] = []
        var histories: [[MatchRecord]] = []
        var lastSyncDate: Date? { nil }
        func start() {}
        func sendMatch(_ record: MatchRecord, announcement: String?) { sent.append(record) }
        func clearActiveMatch() {}
        func sendFullHistory(_ records: [MatchRecord]) { histories.append(records) }
    }

    // MARK: - updateTags

    @Test func updateTagsAppliesToStoredRecordAndPersists() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = StatsStore(fileURL: url)
        let record = makeRecord()
        store.saveHistory([record])
        let incoming = tags(at: 100)

        let saved = try #require(store.updateTags(id: record.id, tags: incoming))

        #expect(saved.tags == incoming)
        // Tag-only: the body is untouched.
        #expect(saved.setScores == record.setScores)
        #expect(saved.isInProgress == record.isInProgress)
        #expect(StatsStore(fileURL: url).loadHistoryOrNil()?.first?.tags == incoming)
    }

    @Test func updateTagsDoesNotOverwriteAnUnreadableArchive() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not valid json {{{".utf8).write(to: url)
        let before = try Data(contentsOf: url)
        let store = StatsStore(fileURL: url)

        #expect(store.updateTags(id: UUID(), tags: tags(at: 1)) == nil)
        #expect(try Data(contentsOf: url) == before)
    }

    @Test func updateTagsForMissingIDIsANoOpAndNeverCreatesARecord() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = StatsStore(fileURL: url)

        // Absent archive: nothing is created.
        #expect(store.updateTags(id: UUID(), tags: tags(at: 1)) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))

        // Existing archive without that ID: bytes unchanged.
        store.saveHistory([makeRecord()])
        let before = try Data(contentsOf: url)
        #expect(store.updateTags(id: UUID(), tags: tags(at: 1)) == nil)
        #expect(try Data(contentsOf: url) == before)
    }

    @Test func updateTagsReportsFailureWhenTheWriteFails() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let record = makeRecord()
        try JSONEncoder().encode([record]).write(to: url)
        let before = try Data(contentsOf: url)
        let store = StatsStore(fileURL: url, writeHistory: { _, _ in
            throw CocoaError(.fileWriteNoPermission)
        })

        #expect(store.updateTags(id: record.id, tags: tags(at: 5)) == nil)
        #expect(try Data(contentsOf: url) == before)
    }

    @Test func olderIncomingRevisionNeverOverwritesANewerStoredOne() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = StatsStore(fileURL: url)
        let newer = tags("Newer", at: 200)
        let record = makeRecord(tags: newer)
        store.saveHistory([record])

        let saved = try #require(store.updateTags(id: record.id, tags: tags("Older", at: 100)))

        #expect(saved.tags == newer)
        #expect(store.loadHistory().first?.tags == newer)
    }

    @Test func newerIncomingRevisionReplacesTheStoredOne() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = StatsStore(fileURL: url)
        let record = makeRecord(tags: tags("Older", at: 100))
        store.saveHistory([record])
        let newer = tags("Newer", at: 200)

        #expect(store.updateTags(id: record.id, tags: newer)?.tags == newer)
    }

    @Test func newerEmptyRevisionClearsTheTags() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = StatsStore(fileURL: url)
        let existing = tags(at: 100)
        let record = makeRecord(tags: existing)
        store.saveHistory([record])
        let cleared = MatchTags.cleared(after: existing, now: Date(timeIntervalSince1970: 50))

        let saved = try #require(store.updateTags(id: record.id, tags: cleared))

        let result = try #require(saved.tags)
        #expect(result.isEmpty)
        #expect(result.displayLine == nil)
        #expect(result.updatedAt > existing.updatedAt)
    }

    // MARK: - Metadata independence (write paths that replace by id)

    @Test func appendingAnUntaggedCheckpointKeepsTheStoredTags() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = StatsStore(fileURL: url)
        let stored = tags(at: 100)
        let record = makeRecord(tags: stored)
        store.saveHistory([record])

        var checkpoint = makeRecord(id: record.id)   // tag-less, like every live checkpoint
        checkpoint.currentPointsMe = 2
        store.appendMatch(checkpoint)

        let result = try #require(store.loadHistory().first)
        #expect(result.currentPointsMe == 2)          // the body did advance
        #expect(result.tags == stored)                // the tags survived
    }

    @Test func completingATaggedInProgressRecordKeepsItsTagsAndOnlyThenCompletes() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = StatsStore(fileURL: url)
        let stored = tags(at: 100)
        let record = makeRecord(tags: stored)
        store.saveHistory([record])

        // A tag-only update must never complete the match.
        let afterTag = try #require(store.updateTags(id: record.id, tags: tags("B", at: 150)))
        #expect(afterTag.isInProgress)

        let viewModel = ScoreViewModel(statsStore: store, stateFileURL: makeTempURL())
        let sync = SyncSpy()
        viewModel.syncService = sync
        #expect(viewModel.endStoredMatchAtCurrentScore(afterTag))

        let completed = try #require(store.loadHistory().first)
        #expect(!completed.isInProgress)
        #expect(completed.tags == afterTag.tags)
        #expect(sync.histories.last?.first?.tags == afterTag.tags)   // sent to the phone with tags
    }

    @MainActor
    @Test func tagsSurviveResumeScoreUndoParkAndCompletion() throws {
        let url = makeTempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = StatsStore(fileURL: url)
        let stored = tags(at: 100)
        let record = makeRecord(tags: stored)
        store.saveHistory([record])
        let viewModel = ScoreViewModel(statsStore: store, stateFileURL: makeTempURL())
        let sync = SyncSpy()
        viewModel.syncService = sync
        viewModel.statsTrackingEnabled = false

        // Resume removes the record from the store; the view model must keep the tags.
        viewModel.resumeMatch(record)
        #expect(viewModel.liveMatchTags == stored)

        // Score, then undo: every checkpoint sent to the phone carries the tags.
        viewModel.winPoint(player: .me)
        viewModel.undo()
        viewModel.winPoint(player: .opponent)
        #expect(!sync.sent.isEmpty)
        #expect(sync.sent.allSatisfy { $0.tags == stored })

        // Park it: the stored record is the live score AND still tagged.
        viewModel.resetMatch()
        let parked = try #require(store.loadHistory().first)
        #expect(parked.id == record.id)
        #expect(parked.isInProgress)
        #expect(parked.currentPointsOpponent == 1)
        #expect(parked.tags == stored)
        #expect(sync.sent.last?.tags == stored)

        // Resume again and let the phone complete it: still tagged.
        viewModel.resumeMatch(parked)
        viewModel.completeCurrentMatchIfMatching(parked.id)
        let completed = try #require(store.loadHistory().first)
        #expect(!completed.isInProgress)
        #expect(completed.tags == stored)
        #expect(viewModel.liveMatchTags == nil)
    }

    @MainActor
    @Test func resumingAStaleSnapshotKeepsTheNewerStoredTags() throws {
        let store = StatsStore(fileURL: makeTempURL())
        let stale = makeRecord(tags: tags("Old", at: 100))
        store.saveHistory([stale])
        // The phone's newer revision lands while the sheet still holds `stale`.
        let newer = tags("Newer", at: 200)
        _ = try #require(store.updateTags(id: stale.id, tags: newer))
        let viewModel = ScoreViewModel(statsStore: store, stateFileURL: makeTempURL())
        let sync = SyncSpy()
        viewModel.syncService = sync
        viewModel.statsTrackingEnabled = false

        viewModel.resumeMatch(stale)
        #expect(viewModel.liveMatchTags == newer)
        viewModel.winPoint(player: .me)
        #expect(sync.sent.last?.tags == newer)
        viewModel.resetMatch()
        #expect(store.loadHistory().first?.tags == newer)
    }

    @MainActor
    @Test func resumingAStaleSnapshotKeepsAnExplicitClear() throws {
        let store = StatsStore(fileURL: makeTempURL())
        let old = tags("Old", at: 100)
        let stale = makeRecord(tags: old)
        store.saveHistory([stale])
        let cleared = MatchTags.cleared(after: old, now: Date(timeIntervalSince1970: 200))
        _ = try #require(store.updateTags(id: stale.id, tags: cleared))
        let viewModel = ScoreViewModel(statsStore: store, stateFileURL: makeTempURL())
        let sync = SyncSpy()
        viewModel.syncService = sync
        viewModel.statsTrackingEnabled = false

        viewModel.resumeMatch(stale)
        #expect(viewModel.liveMatchTags == cleared)
        viewModel.winPoint(player: .me)
        #expect(sync.sent.last?.tags == cleared)
        viewModel.resetMatch()
        #expect(store.loadHistory().first?.tags == cleared)
    }

    @MainActor
    @Test func aTagUpdateForTheLiveMatchIsCarriedWithoutChangingTheScore() throws {
        let store = StatsStore(fileURL: makeTempURL())
        let record = makeRecord()
        store.saveHistory([record])
        let viewModel = ScoreViewModel(statsStore: store, stateFileURL: makeTempURL())
        viewModel.statsTrackingEnabled = false
        viewModel.resumeMatch(record)
        let incoming = tags(at: 300)
        let pointsBefore = viewModel.currentPointsMe

        // The live match is not in the store, so the store update is a no-op…
        #expect(store.updateTags(id: record.id, tags: incoming) == nil)
        // …and the view model picks it up instead (only for its own identity).
        viewModel.applyIncomingMatchTags(tags("Other", at: 400), matchID: UUID())
        #expect(viewModel.liveMatchTags == nil)
        viewModel.applyIncomingMatchTags(incoming, matchID: record.id)

        #expect(viewModel.liveMatchTags == incoming)
        #expect(viewModel.currentPointsMe == pointsBefore)
        #expect(viewModel.currentMatchID == record.id)

        viewModel.resetMatch()
        #expect(store.loadHistory().first?.tags == incoming)
    }

    @Test func aTaggedRecordSurvivesTheFullHistoryRoundTripThePhoneReads() throws {
        // The watch sends the stored JSON; the phone's merge must see the tags.
        let stored = tags(at: 100)
        let record = makeRecord(tags: stored)
        let decoded = try JSONDecoder().decode([MatchRecord].self,
                                               from: JSONEncoder().encode([record]))
        #expect(decoded.first?.tags == stored)
    }
}
