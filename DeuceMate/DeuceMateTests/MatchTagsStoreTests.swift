// MatchTagsStoreTests.swift — PhoneStatsStore's match-tag editing, the
// forgotten-player ledger and the tag-preserving replacement paths, against
// the real canonical archive files (MATCH_TAGS_PLAN.md §3–§6.2).
import Foundation
import DeuceMateCore
import Testing
@testable import DeuceMate

struct MatchTagsStoreTests {
    private struct Fixture {
        let root: URL
        let canonical: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("match-tags-store-\(UUID().uuidString)", isDirectory: true)
            canonical = root.appendingPathComponent("MatchArchive", isDirectory: true)
            try FileManager.default.createDirectory(at: canonical, withIntermediateDirectories: true)
        }

        var historyURL: URL { canonical.appendingPathComponent("matchHistory.json") }
        var ledgerURL: URL { canonical.appendingPathComponent("forgottenPlayers.json") }
        var tombstoneURL: URL { canonical.appendingPathComponent("deletedMatchIDs.json") }

        /// Makes the ledger unwritable mid-session: a non-empty directory at
        /// its path, which an atomic file write cannot replace. The ledger is
        /// the first canonical file written, so every write then fails.
        func blockCanonicalWrites() throws {
            try? FileManager.default.removeItem(at: ledgerURL) // the current ledger file
            try FileManager.default.createDirectory(at: ledgerURL, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: ledgerURL.appendingPathComponent("blocker"))
        }

        func unblockCanonicalWrites() throws {
            try FileManager.default.removeItem(at: ledgerURL)
        }

        func makeStore() -> PhoneStatsStore {
            PhoneStatsStore(storageConfiguration: .init(
                canonicalDirectoryURL: canonical,
                legacyDocumentsDirectoryURL: root.appendingPathComponent("Documents", isDirectory: true),
                startsICloudSync: false
            ))
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    private static let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func completed(id: UUID = UUID(), start: TimeInterval = 0, tags: MatchTags? = nil,
                           type: MatchType = .singles) -> MatchRecord {
        MatchRecord(
            id: id,
            startTime: Self.base.addingTimeInterval(start),
            endTime: Self.base.addingTimeInterval(start + 3_600),
            setScores: [SetScore(gamesMe: 6, gamesOpponent: 4)],
            stats: [],
            iWon: true,
            matchType: type,
            tags: tags
        )
    }

    private func inProgress(id: UUID = UUID()) -> MatchRecord {
        MatchRecord(
            id: id,
            startTime: Self.base,
            endTime: nil,
            setScores: [SetScore(gamesMe: 3, gamesOpponent: 2)],
            stats: [],
            iWon: nil,
            currentPointsMe: 2,
            currentPointsOpponent: 1
        )
    }

    private func draft(opponents: [TaggedPlayer] = [], partner: TaggedPlayer? = nil,
                       competition: CompetitionType? = nil) -> MatchTags {
        MatchTags(opponents: opponents, partner: partner, competitionType: competition, updatedAt: Date())
    }

    // MARK: - updateTags

    @Test func updateTagsSavesStampsAndSurvivesRelaunch() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let match = completed()
        let store = fixture.makeStore()
        store.saveHistory([match])
        let alex = TaggedPlayer(name: "Alex")

        let saved = try store.updateTags(id: match.id, tags: draft(opponents: [alex], competition: .league))

        #expect(saved.displayLine == "vs Alex · League")
        #expect(saved.revisionID != MatchTags.legacyRevisionID)
        let reloaded = fixture.makeStore().loadHistory().first
        #expect(reloaded?.tags?.displayLine == "vs Alex · League")
        #expect(reloaded?.tags?.opponents.first?.id == alex.id)
        // Body untouched.
        #expect(reloaded?.setScores == match.setScores)
        #expect(reloaded?.endTime == match.endTime)
    }

    @Test func editingAnInProgressMatchNeverCompletesItOrChangesTheScore() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let live = inProgress()
        let store = fixture.makeStore()
        store.saveHistory([live])

        try store.updateTags(id: live.id, tags: draft(opponents: [TaggedPlayer(name: "Jo")], competition: .friendly))

        let after = try #require(store.loadHistory().first)
        #expect(after.isInProgress)
        #expect(after.iWon == nil)
        #expect(after.endTime == nil)
        #expect(after.setScores == live.setScores)
        #expect(after.currentPointsMe == 2)
        #expect(after.currentPointsOpponent == 1)
        #expect(after.tags?.displayLine == "vs Jo · Friendly")
    }

    @Test func clockIsStrictlyMonotonicEvenWhenTheDeviceClockGoesBackwards() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let match = completed()
        let store = fixture.makeStore()
        store.saveHistory([match])
        let now = Self.base.addingTimeInterval(10_000)

        let first = try store.updateTags(id: match.id, tags: draft(competition: .league), now: now)
        let second = try store.updateTags(id: match.id, tags: draft(competition: .tournament),
                                          now: now.addingTimeInterval(-500))

        #expect(second.updatedAt > first.updatedAt)
        #expect(second.supersedes(first))
        #expect(store.loadHistory().first?.tags?.competitionType == .tournament)
    }

    @Test func clearingSavesAnEmptyNewerRevisionThatBeatsAnOlderTaggedCopy() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let match = completed()
        let store = fixture.makeStore()
        store.saveHistory([match])
        let tagged = try store.updateTags(id: match.id, tags: draft(opponents: [TaggedPlayer(name: "Alex")]))

        let cleared = try store.updateTags(id: match.id, tags: draft())
        #expect(cleared.isEmpty)
        #expect(cleared.supersedes(tagged))

        // A stale watch copy still carrying the old tags must not resurrect them.
        var stale = match
        stale.tags = tagged
        store.mergeIncoming([stale])
        #expect(store.loadHistory().first?.tags?.isEmpty == true)
    }

    @Test func updateTagsForAnUnknownMatchThrows() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = fixture.makeStore()
        #expect(throws: PhoneStatsStore.TagEditError.matchNotFound) {
            try store.updateTags(id: UUID(), tags: draft(competition: .league))
        }
    }

    // MARK: - Replacement paths keep tags

    /// The §3 regression end-to-end: the watch re-sends its untagged copy of a
    /// finished match with the same endTime on every Sync Now.
    @Test func watchHistoryWithAnUntaggedEqualEndTimeCopyKeepsTags() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let match = completed()
        let store = fixture.makeStore()
        store.saveHistory([match])
        try store.updateTags(id: match.id, tags: draft(opponents: [TaggedPlayer(name: "Alex")], competition: .league))

        store.mergeIncoming([match]) // watch copy, tags == nil

        #expect(store.loadHistory().first?.tags?.displayLine == "vs Alex · League")
        #expect(fixture.makeStore().loadHistory().first?.tags?.displayLine == "vs Alex · League")
    }

    /// End at Current Score builds the completed record from a copy that may
    /// predate a tag edit made while the sheet was open; appendMatch must keep
    /// the stored tags.
    @Test func appendMatchCarriesStoredTagsForward() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let live = inProgress()
        let store = fixture.makeStore()
        store.saveHistory([live])
        try store.updateTags(id: live.id, tags: draft(opponents: [TaggedPlayer(name: "Sam")]))

        store.appendMatch(live.endingAtCurrentScore()) // stale copy without tags

        let after = try #require(store.loadHistory().first)
        #expect(after.isInProgress == false)
        #expect(after.tags?.displayLine == "vs Sam")
    }

    @Test func saveHistoryCarriesStoredTagsForward() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let match = completed()
        let store = fixture.makeStore()
        store.saveHistory([match])
        try store.updateTags(id: match.id, tags: draft(competition: .practice))

        store.saveHistory([match])

        #expect(store.loadHistory().first?.tags?.competitionType == .practice)
    }

    @Test func incomingTagUpdateMergesByClockAndIgnoresUnknownMatches() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let match = completed()
        let store = fixture.makeStore()
        store.saveHistory([match])
        let newer = try store.updateTags(id: match.id, tags: draft(competition: .league))

        // Older incoming revision loses.
        let older = MatchTags(competitionType: .friendly, updatedAt: newer.updatedAt.addingTimeInterval(-60))
        store.applyIncomingTags(MatchTagsUpdate(matchID: match.id, tags: older))
        #expect(store.loadHistory().first?.tags?.competitionType == .league)

        // Newer incoming revision wins; body untouched.
        let later = MatchTags(competitionType: .tournament, updatedAt: newer.updatedAt.addingTimeInterval(60))
        store.applyIncomingTags(MatchTagsUpdate(matchID: match.id, tags: later))
        #expect(store.loadHistory().first?.tags?.competitionType == .tournament)
        #expect(store.loadHistory().first?.setScores == match.setScores)

        // Tags never create a match.
        store.applyIncomingTags(MatchTagsUpdate(matchID: UUID(), tags: later))
        #expect(store.loadHistory().count == 1)
    }

    // MARK: - Roster mutations

    @Test func renameAndMergeRewriteEveryMatch() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let alex = TaggedPlayer(name: "Alex")
        let alexDuplicate = TaggedPlayer(name: "alex")
        let a = completed(start: 0)
        let b = completed(start: 10_000)
        let c = completed(start: 20_000)
        let store = fixture.makeStore()
        store.saveHistory([a, b, c])
        try store.updateTags(id: a.id, tags: draft(opponents: [alex]))
        try store.updateTags(id: b.id, tags: draft(opponents: [alex]))
        try store.updateTags(id: c.id, tags: draft(opponents: [alexDuplicate]))

        let renamed = try store.renamePlayer(alex.id, to: "Alexandra")
        #expect(renamed == [a.id, b.id])
        let merged = try store.mergePlayers(alexDuplicate.id, into: alex.id)
        #expect(merged == [c.id])

        let roster = store.rosterEntries()
        #expect(roster.count == 1)
        #expect(roster.first?.name == "Alexandra")
        #expect(roster.first?.matchCount == 3)
        #expect(fixture.makeStore().loadHistory().allSatisfy { $0.tags?.displayLine == "vs Alexandra" })
    }

    @Test func forgetRemovesThePlayerEverywhereAndPersistsAnIDOnlyLedger() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let alex = TaggedPlayer(name: "Alex Forgettable")
        let sam = TaggedPlayer(name: "Sam")
        let a = completed(start: 0)
        let b = completed(start: 10_000, type: .doubles)
        let store = fixture.makeStore()
        store.saveHistory([a, b])
        try store.updateTags(id: a.id, tags: draft(opponents: [alex], competition: .league))
        try store.updateTags(id: b.id, tags: draft(opponents: [sam, TaggedPlayer(name: "Jo")], partner: alex))

        let affected = try store.forgetPlayer(alex.id)

        #expect(affected == [a.id, b.id])
        #expect(store.rosterEntries().map(\.name).contains("Alex Forgettable") == false)
        let history = store.loadHistory()
        #expect(history.allSatisfy { !($0.tags?.playerIDs.contains(alex.id) ?? false) })
        #expect(history.first { $0.id == a.id }?.tags?.displayLine == "League")
        // The ledger is persisted with ids only — never the name.
        let ledgerData = try Data(contentsOf: fixture.ledgerURL)
        let ledgerText = String(decoding: ledgerData, as: UTF8.self)
        #expect(ledgerText.contains(alex.id.uuidString))
        #expect(ledgerText.contains("Alex") == false)
        // Neither the archive nor a relaunch brings the name back.
        let historyText = String(decoding: try Data(contentsOf: fixture.historyURL), as: UTF8.self)
        #expect(historyText.contains("Alex Forgettable") == false)
        let reloaded = fixture.makeStore()
        #expect(reloaded.forgottenPlayers.contains(alex.id))
    }

    // MARK: - Failed writes (nothing is reported as saved unless it is on disk)

    /// The review scenario: the launch read failed, so canonical writes are
    /// suspended. Forget must fail visibly, leave the player in the roster
    /// (in memory AND after a relaunch), and write no ledger.
    @Test func forgetWithSuspendedWritesThrowsAndThePlayerSurvivesRelaunch() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let alex = TaggedPlayer(name: "Alex")
        let match = completed(tags: MatchTags(opponents: [alex], updatedAt: Self.base))
        try JSONEncoder().encode([match]).write(to: fixture.historyURL)
        // A directory at the tombstone URL is an unreadable (not missing) file.
        try FileManager.default.createDirectory(at: fixture.tombstoneURL, withIntermediateDirectories: true)
        let store = fixture.makeStore()
        #expect(store.rosterEntries().map(\.name) == ["Alex"])

        #expect(throws: PhoneStatsStore.TagEditError.notPersisted) {
            try store.forgetPlayer(alex.id)
        }

        #expect(store.rosterEntries().map(\.name) == ["Alex"])
        #expect(store.forgottenPlayerLedger().contains(alex.id) == false)
        #expect(store.loadHistory().first?.tags?.playerIDs.contains(alex.id) == true)
        #expect(FileManager.default.fileExists(atPath: fixture.ledgerURL.path) == false)
        // Relaunch: the name is still there (what the user was told).
        #expect(fixture.makeStore().rosterEntries().map(\.name) == ["Alex"])
    }

    @Test func forgetThatCannotBeWrittenRollsBackInMemoryAndOnDisk() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let alex = TaggedPlayer(name: "Alex")
        let match = completed()
        let store = fixture.makeStore()
        store.saveHistory([match])
        try store.updateTags(id: match.id, tags: draft(opponents: [alex]))
        try fixture.blockCanonicalWrites()

        #expect(throws: PhoneStatsStore.TagEditError.notPersisted) {
            try store.forgetPlayer(alex.id)
        }

        #expect(store.forgottenPlayerLedger().isEmpty)
        #expect(store.rosterEntries().map(\.name) == ["Alex"])
        try fixture.unblockCanonicalWrites()
        let reloaded = fixture.makeStore()
        #expect(reloaded.forgottenPlayerLedger().isEmpty)
        #expect(reloaded.rosterEntries().map(\.name) == ["Alex"])
        // Retrying once storage is writable works.
        #expect(try store.forgetPlayer(alex.id) == [match.id])
        #expect(fixture.makeStore().forgottenPlayerLedger().contains(alex.id))
    }

    @Test func renameAndMergeThatCannotBeWrittenThrowAndChangeNothing() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let alex = TaggedPlayer(name: "Alex")
        let alexDuplicate = TaggedPlayer(name: "alex")
        let a = completed(start: 0), b = completed(start: 10_000)
        let store = fixture.makeStore()
        store.saveHistory([a, b])
        try store.updateTags(id: a.id, tags: draft(opponents: [alex]))
        try store.updateTags(id: b.id, tags: draft(opponents: [alexDuplicate]))
        let before = store.loadHistory()
        try fixture.blockCanonicalWrites()

        #expect(throws: PhoneStatsStore.TagEditError.notPersisted) {
            try store.renamePlayer(alex.id, to: "Alexandra")
        }
        #expect(throws: PhoneStatsStore.TagEditError.notPersisted) {
            try store.mergePlayers(alexDuplicate.id, into: alex.id)
        }

        #expect(store.loadHistory() == before)
        try fixture.unblockCanonicalWrites()
        #expect(fixture.makeStore().loadHistory() == before)
    }

    @Test func updateTagsThatCannotBeWrittenThrowsAndKeepsTheStoredTags() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let match = completed()
        let store = fixture.makeStore()
        store.saveHistory([match])
        let saved = try store.updateTags(id: match.id, tags: draft(competition: .league))
        try fixture.blockCanonicalWrites()

        #expect(throws: PhoneStatsStore.TagEditError.notPersisted) {
            try store.updateTags(id: match.id, tags: draft(competition: .tournament))
        }

        #expect(store.loadHistory().first?.tags == saved)
    }

    @Test func forgottenPlayerCannotReturnThroughAnyInboundPath() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let alex = TaggedPlayer(name: "Alex")
        let match = completed()
        let store = fixture.makeStore()
        store.saveHistory([match])
        let tagged = try store.updateTags(id: match.id, tags: draft(opponents: [alex]))
        // Snapshot of a stale copy taken BEFORE the forget.
        var stale = match
        stale.tags = tagged
        let otherStale = completed(start: 50_000, tags: tagged) // a match the phone never held
        let oldArchive = try ManualMatchArchiveBackup.encode(records: [stale, otherStale])
        try store.forgetPlayer(alex.id)

        // 1. Stale watch history (newer-looking clock even).
        let futureTags = MatchTags(opponents: [alex], updatedAt: Date().addingTimeInterval(86_400))
        var futureStale = stale
        futureStale.tags = futureTags
        store.mergeIncoming([futureStale])
        // 2. "Sync to iPhone" of a stale watch-only row.
        store.syncToPhone(otherStale)
        #expect(store.loadHistory().allSatisfy { !($0.tags?.playerIDs.contains(alex.id) ?? false) })
        // 3. Incoming tag update.
        store.applyIncomingTags(MatchTagsUpdate(matchID: match.id, tags: futureTags))
        #expect(store.loadHistory().allSatisfy { !($0.tags?.playerIDs.contains(alex.id) ?? false) })
        // 4. Manual import, merge and replace, of an old archive without a ledger.
        try store.importManualArchive(data: oldArchive, mode: .merge)
        #expect(store.loadHistory().allSatisfy { !($0.tags?.playerIDs.contains(alex.id) ?? false) })
        try store.importManualArchive(data: oldArchive, mode: .replace)
        #expect(store.loadHistory().allSatisfy { !($0.tags?.playerIDs.contains(alex.id) ?? false) })
        // The ledger survived the replace.
        #expect(fixture.makeStore().forgottenPlayers.contains(alex.id))
    }

    @Test func manualExportCarriesTheLedgerAndImportUnionsIt() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let alex = TaggedPlayer(name: "Alex")
        let match = completed()
        let store = fixture.makeStore()
        store.saveHistory([match])
        try store.updateTags(id: match.id, tags: draft(opponents: [alex]))
        try store.forgetPlayer(alex.id)

        let exported = try ManualMatchArchiveBackup.decode(store.exportManualArchiveData())
        #expect(exported.forgottenPlayers?.contains(alex.id) == true)

        // A fresh install importing that archive inherits the deletion intent.
        let other = try Fixture()
        defer { other.remove() }
        let fresh = other.makeStore()
        try fresh.importManualArchive(data: store.exportManualArchiveData(), mode: .merge)
        #expect(fresh.forgottenPlayerLedger().contains(alex.id))
    }

    // MARK: - iCloud backup snapshot

    @Test func backupSnapshotKeepsNamesAndLedgerButNeverNoteText() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let notesDir = fixture.root.appendingPathComponent("MatchNotes", isDirectory: true)
        let notes = MatchNotesStore(configuration: .init(directoryURL: notesDir))
        let match = completed()
        let store = fixture.makeStore()
        store.saveHistory([match])
        try store.updateTags(id: match.id, tags: draft(opponents: [TaggedPlayer(name: "Alex")], competition: .league))
        let forgotten = TaggedPlayer(name: "Gone")
        try store.forgetPlayer(forgotten.id)
        let secret = "knee felt sore — secret-note-marker-81723"
        try notes.save(text: secret, for: match.id)

        let snapshot = store.currentBackupSnapshot()
        let recordsJSON = String(decoding: try JSONEncoder().encode(snapshot.records), as: UTF8.self)
        let ledgerJSON = String(decoding: try JSONEncoder().encode(snapshot.forgottenPlayers), as: UTF8.self)

        #expect(recordsJSON.contains("Alex"))
        #expect(recordsJSON.contains("league"))
        #expect(recordsJSON.contains("secret-note-marker") == false)
        #expect(ledgerJSON.contains(forgotten.id.uuidString))
        #expect(ledgerJSON.contains("secret-note-marker") == false)
        // …and the canonical archive files on disk hold no note text either.
        for file in try FileManager.default.contentsOfDirectory(at: fixture.canonical, includingPropertiesForKeys: nil) {
            let text = String(decoding: try Data(contentsOf: file), as: UTF8.self)
            #expect(text.contains("secret-note-marker") == false, "\(file.lastPathComponent) must not hold note text")
        }
    }
}
