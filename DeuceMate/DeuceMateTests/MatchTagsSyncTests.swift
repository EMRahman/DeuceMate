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
    private struct Harness {
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
        h.store.forgetPlayer(alex.id)
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

    @Test func watchMirrorRowsNeverShowAForgottenPlayer() async throws {
        let h = Harness()
        defer { h.remove() }
        let alex = TaggedPlayer(name: "Alex")
        let watchOnly = match()
        var stale = watchOnly
        stale.tags = MatchTags(opponents: [alex], updatedAt: Date())
        h.store.forgetPlayer(alex.id)
        await drainMain()

        h.service.handle([.watchManifest([watchOnly.id])])
        await drainMain()
        h.service.handle([.history([stale])])
        await drainMain()

        #expect(h.service.watchMirror.allSatisfy { !($0.tags?.playerIDs.contains(alex.id) ?? false) })
    }
}
