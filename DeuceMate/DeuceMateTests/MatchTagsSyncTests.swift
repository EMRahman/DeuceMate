// MatchTagsSyncTests.swift — PhoneMatchSyncService's tag pushes and §6.1
// reconciliation, with a real PhoneStatsStore and a fake WatchConnectivity
// session that records what would be sent to the watch.
import Dispatch
import Foundation
import DeuceMateCore
import Testing
@testable import DeuceMate

private final class RecordingSession: MatchSyncSessing {
    var isActivated = true
    var isReachable = true
    private(set) var sent: [[String: Any]] = []

    func sendMessage(_ message: [String: Any],
                     replyHandler: (([String: Any]) -> Void)?,
                     errorHandler: ((Error) -> Void)?) {
        sent.append(message)
        replyHandler?([:])
    }
    func queueUserInfo(_ userInfo: [String: Any]) { sent.append(userInfo) }
    func transferFile(at url: URL, metadata: [String: Any]?) {}

    /// Every `matchTagsUpdate` sent, decoded.
    var tagUpdates: [MatchTagsUpdate] {
        sent.flatMap { payload in
            SyncIncomingPayload.decode(payload).compactMap { event -> MatchTagsUpdate? in
                if case .matchTagsUpdate(let id, let tags) = event { return MatchTagsUpdate(matchID: id, tags: tags) }
                return nil
            }
        }
    }

    func reset() { sent.removeAll() }
}

@MainActor
struct MatchTagsSyncTests {
    @MainActor private struct Harness {
        let root: URL
        let store: PhoneStatsStore
        let session: RecordingSession
        let service: PhoneMatchSyncService

        init() {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("match-tags-sync-\(UUID().uuidString)", isDirectory: true)
            store = PhoneStatsStore(storageConfiguration: .init(
                canonicalDirectoryURL: root.appendingPathComponent("MatchArchive", isDirectory: true),
                legacyDocumentsDirectoryURL: root.appendingPathComponent("Documents", isDirectory: true),
                startsICloudSync: false
            ))
            session = RecordingSession()
            service = PhoneMatchSyncService(
                isSessionSupported: { true },
                activateSession: { _ in },
                scheduleAfter: { _, _ in },
                transport: MatchSyncTransport(session: session)
            )
            service.start(store: store)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }

        var canonical: URL { root.appendingPathComponent("MatchArchive", isDirectory: true) }
        var ledgerURL: URL { canonical.appendingPathComponent("forgottenPlayers.json") }

        /// A second process's view of the same files — what a relaunch loads.
        func relaunchedStore() -> PhoneStatsStore {
            PhoneStatsStore(storageConfiguration: .init(
                canonicalDirectoryURL: canonical,
                legacyDocumentsDirectoryURL: root.appendingPathComponent("Documents", isDirectory: true),
                startsICloudSync: false
            ))
        }

        func makeNotesStore() -> MatchNotesStore {
            MatchNotesStore(configuration: .init(directoryURL: root.appendingPathComponent("MatchNotes", isDirectory: true)))
        }

        /// Storage becomes unwritable mid-session: a non-empty directory at the
        /// ledger path (the first canonical file written) defeats every write.
        func blockCanonicalWrites() throws {
            try? FileManager.default.removeItem(at: ledgerURL) // the current ledger file
            try FileManager.default.createDirectory(at: ledgerURL, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: ledgerURL.appendingPathComponent("blocker"))
        }

        func unblockCanonicalWrites() throws {
            try FileManager.default.removeItem(at: ledgerURL)
        }
    }

    private func match(id: UUID = UUID()) -> MatchRecord {
        MatchRecord(
            id: id,
            startTime: Date(timeIntervalSince1970: 1_000),
            endTime: Date(timeIntervalSince1970: 4_000),
            setScores: [SetScore(gamesMe: 6, gamesOpponent: 3)],
            stats: [],
            iWon: true
        )
    }

    private func drainMain() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @Test func editTimePushGoesOnlyToMatchesTheWatchHolds() async throws {
        let h = Harness()
        defer { h.remove() }
        let onWatch = match(), phoneOnly = match()
        h.store.saveHistory([onWatch, phoneOnly])
        h.service.handle([.watchManifest([onWatch.id])])
        await drainMain()
        h.session.reset()

        try h.store.updateTags(id: onWatch.id, tags: MatchTags(competitionType: .league, updatedAt: Date()))
        try h.store.updateTags(id: phoneOnly.id, tags: MatchTags(competitionType: .league, updatedAt: Date()))
        h.service.pushTagUpdates(forMatchIDs: [onWatch.id, phoneOnly.id])

        #expect(h.session.tagUpdates.map(\.matchID) == [onWatch.id])
        #expect(h.session.tagUpdates.first?.tags.competitionType == .league)
        // Never as a whole record (that would hit the watch's completion path).
        #expect(h.session.sent.allSatisfy { $0[MatchSyncKey.singleMatch] == nil })
    }

    /// §6.1 rule 1: an untagged watch copy (old build, or a missed push) gets
    /// the phone's tags back after the merge keeps them.
    @Test func historyFromABehindWatchTriggersAResend() async throws {
        let h = Harness()
        defer { h.remove() }
        let record = match()
        h.store.saveHistory([record])
        let saved = try h.store.updateTags(id: record.id, tags: MatchTags(
            opponents: [TaggedPlayer(name: "Alex")], updatedAt: Date()))
        h.session.reset()

        h.service.handle([.history([record])]) // the watch's copy has no tags

        #expect(h.store.loadHistory().first?.tags == saved)
        #expect(h.session.tagUpdates == [MatchTagsUpdate(matchID: record.id, tags: saved)])

        // A watch that is already current gets nothing.
        h.session.reset()
        var current = record
        current.tags = saved
        h.service.handle([.history([current])])
        #expect(h.session.tagUpdates.isEmpty)
    }

    /// §6.1 rule 2: ids newly in the manifest get non-nil tags — including an
    /// empty clear — and an unchanged manifest causes no resend storm.
    @Test func newlyHeldManifestIDsReceiveTagsIncludingClears() async throws {
        let h = Harness()
        defer { h.remove() }
        let record = match()
        h.store.saveHistory([record])
        try h.store.updateTags(id: record.id, tags: MatchTags(competitionType: .league, updatedAt: Date()))
        let cleared = try h.store.updateTags(id: record.id, tags: MatchTags(competitionTypeRaw: nil, updatedAt: Date()))
        #expect(cleared.isEmpty)
        h.service.handle([.watchManifest([])])
        await drainMain()
        h.session.reset()

        h.service.handle([.watchManifest([record.id])])
        await drainMain()
        #expect(h.session.tagUpdates == [MatchTagsUpdate(matchID: record.id, tags: cleared)])

        h.session.reset()
        h.service.handle([.watchManifest([record.id])])
        await drainMain()
        #expect(h.session.tagUpdates.isEmpty)
    }

    /// A stale watch copy naming a forgotten player is scrubbed on arrival, and
    /// the cleaned revision is sent back so the watch converges.
    @Test func staleWatchCopyOfAForgottenPlayerIsScrubbedAndCorrected() async throws {
        let h = Harness()
        defer { h.remove() }
        let alex = TaggedPlayer(name: "Alex")
        let record = match()
        h.store.saveHistory([record])
        let tagged = try h.store.updateTags(id: record.id, tags: MatchTags(opponents: [alex], updatedAt: Date()))
        try h.store.forgetPlayer(alex.id)
        h.session.reset()

        var stale = record
        stale.tags = tagged
        h.service.handle([.history([stale])])

        let stored = try #require(h.store.loadHistory().first?.tags)
        #expect(stored.playerIDs.contains(alex.id) == false)
        #expect(h.session.tagUpdates.first?.tags.playerIDs.contains(alex.id) == false)
        #expect(h.session.tagUpdates.map(\.matchID) == [record.id])
    }

    @Test func incomingTagUpdateIsMergedAndAnOlderOneIsAnsweredWithThePhonesCopy() async throws {
        let h = Harness()
        defer { h.remove() }
        let record = match()
        h.store.saveHistory([record])
        let phone = try h.store.updateTags(id: record.id, tags: MatchTags(competitionType: .tournament, updatedAt: Date()))
        h.session.reset()

        let older = MatchTags(competitionType: .friendly, updatedAt: phone.updatedAt.addingTimeInterval(-120))
        h.service.handle([.matchTagsUpdate(matchID: record.id, tags: older)])

        #expect(h.store.loadHistory().first?.tags?.competitionType == .tournament)
        #expect(h.session.tagUpdates == [MatchTagsUpdate(matchID: record.id, tags: phone)])
        #expect(h.store.loadHistory().first?.isInProgress == false)
    }

    // MARK: - Players actions when storage can't be written (the user's view)

    /// Settings → Players → Forget with unwritable storage: the action fails
    /// with the user-facing message, nothing reaches the watch, the private
    /// note the user asked to delete is kept, and the player is still listed —
    /// now and after a relaunch.
    @Test func forgetWithUnwritableStorageShowsAnErrorAndPushesNothing() async throws {
        let h = Harness()
        defer { h.remove() }
        let alex = TaggedPlayer(name: "Alex")
        let record = match()
        h.store.saveHistory([record])
        try h.store.updateTags(id: record.id, tags: MatchTags(opponents: [alex], updatedAt: Date()))
        h.service.handle([.watchManifest([record.id])]) // the watch holds it
        await drainMain()
        let notes = h.makeNotesStore()
        try notes.save(text: "Alex's backhand", for: record.id)
        let actions = PlayerRosterActions(store: h.store, notesStore: notes, syncService: h.service)
        try h.blockCanonicalWrites()
        h.session.reset()

        var thrown: Error?
        do { try actions.forget(alex.id, deletingNotesFor: [record.id]) } catch { thrown = error }

        #expect(thrown as? PhoneStatsStore.TagEditError == .notPersisted)
        #expect(thrown?.localizedDescription.contains("nothing was changed") == true)
        await drainMain()
        #expect(h.session.tagUpdates.isEmpty)
        #expect(notes.note(for: record.id)?.text == "Alex's backhand")
        #expect(PlayerRoster.entries(from: h.store.history, forgotten: h.store.forgottenPlayers).map(\.name) == ["Alex"])
        try h.unblockCanonicalWrites()
        #expect(h.relaunchedStore().rosterEntries().map(\.name) == ["Alex"])
    }

    @Test func renameAndMergeWithUnwritableStoragePushNothing() async throws {
        let h = Harness()
        defer { h.remove() }
        let alex = TaggedPlayer(name: "Alex"), duplicate = TaggedPlayer(name: "alex")
        let a = match(), b = match()
        h.store.saveHistory([a, b])
        try h.store.updateTags(id: a.id, tags: MatchTags(opponents: [alex], updatedAt: Date()))
        try h.store.updateTags(id: b.id, tags: MatchTags(opponents: [duplicate], updatedAt: Date()))
        h.service.handle([.watchManifest([a.id, b.id])])
        await drainMain()
        let actions = PlayerRosterActions(store: h.store, notesStore: h.makeNotesStore(), syncService: h.service)
        try h.blockCanonicalWrites()
        h.session.reset()

        #expect(throws: PhoneStatsStore.TagEditError.notPersisted) {
            try actions.rename(alex.id, to: "Alexandra")
        }
        #expect(throws: PhoneStatsStore.TagEditError.notPersisted) {
            try actions.merge(duplicate.id, into: alex.id)
        }

        #expect(h.session.tagUpdates.isEmpty)
        #expect(Set(h.store.rosterEntries().map(\.name)) == ["Alex", "alex"])
    }

    /// The same action with working storage does push, so the failure tests
    /// above prove the guard rather than an inert path.
    @Test func forgetWithWritableStoragePushesTheScrubbedTags() async throws {
        let h = Harness()
        defer { h.remove() }
        let alex = TaggedPlayer(name: "Alex")
        let record = match()
        h.store.saveHistory([record])
        try h.store.updateTags(id: record.id, tags: MatchTags(opponents: [alex], updatedAt: Date()))
        h.service.handle([.watchManifest([record.id])])
        await drainMain()
        let actions = PlayerRosterActions(store: h.store, notesStore: h.makeNotesStore(), syncService: h.service)
        h.session.reset()

        try actions.forget(alex.id)

        #expect(h.session.tagUpdates.map(\.matchID) == [record.id])
        #expect(h.session.tagUpdates.first?.tags.playerIDs.contains(alex.id) == false)
        #expect(h.relaunchedStore().forgottenPlayerLedger().contains(alex.id))
    }

    @Test func watchMirrorRowsNeverShowAForgottenPlayer() async throws {
        let h = Harness()
        defer { h.remove() }
        let alex = TaggedPlayer(name: "Alex")
        let watchOnly = match()
        var stale = watchOnly
        stale.tags = MatchTags(opponents: [alex], updatedAt: Date())
        try h.store.forgetPlayer(alex.id)
        await drainMain()

        h.service.handle([.watchManifest([watchOnly.id])])
        await drainMain()
        h.service.handle([.history([stale])])
        await drainMain()

        #expect(h.service.watchMirror.allSatisfy { !($0.tags?.playerIDs.contains(alex.id) ?? false) })
    }

    @Test func importedForgottenPlayerIsScrubbedFromTheCachedWatchMirror() async throws {
        let h = Harness()
        defer { h.remove() }
        let alex = TaggedPlayer(name: "Alex")
        var watchOnly = match()
        watchOnly.tags = MatchTags(opponents: [alex], updatedAt: Date())
        h.service.handle([.watchManifest([watchOnly.id])])
        await drainMain()
        h.service.handle([.history([watchOnly])])
        await drainMain()
        #expect(h.service.watchMirror.contains { $0.tags?.playerIDs.contains(alex.id) ?? false })

        // Replace the archive with a file that forgot Alex and excludes the
        // cached watch-only match. No watch payload follows (unreachable).
        let archive = try ManualMatchArchiveBackup.encode(
            records: [match()],
            forgottenPlayers: ForgottenPlayerLedger(playerIDs: [alex.id])
        )
        try h.store.importManualArchive(data: archive, mode: .replace)
        await drainMain() // the store publishes the new ledger
        await drainMain() // the mirror observation re-scrubs

        #expect(h.store.forgottenPlayers.contains(alex.id))
        #expect(h.service.watchMirror.allSatisfy { !($0.tags?.playerIDs.contains(alex.id) ?? false) })
    }
}
