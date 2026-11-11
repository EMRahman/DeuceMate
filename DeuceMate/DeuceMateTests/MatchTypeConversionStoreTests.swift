// MatchTypeConversionStoreTests.swift — PhoneStatsStore match-type conversion,
// atomic editor save, tag normalization, and PhoneMatchSyncService peer sync.
import Dispatch
import Foundation
import DeuceMateCore
import Testing
@testable import DeuceMate

// MARK: - Test Harnesses

private struct StoreFixture {
    let root: URL
    let canonical: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("match-type-store-\(UUID().uuidString)", isDirectory: true)
        canonical = root.appendingPathComponent("MatchArchive", isDirectory: true)
        try FileManager.default.createDirectory(at: canonical, withIntermediateDirectories: true)
    }

    var historyURL: URL { canonical.appendingPathComponent("matchHistory.json") }
    var ledgerURL: URL { canonical.appendingPathComponent("forgottenPlayers.json") }
    var sidecarURL: URL { canonical.appendingPathComponent("healthSidecar.json") }

    func blockCanonicalWrites() throws {
        try? FileManager.default.removeItem(at: ledgerURL)
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

private final class RecordingSession: MatchSyncSessing {
    var isActivated = true
    var isReachable = true
    private(set) var sent: [[String: Any]] = []

    func sendMessage(
        _ message: [String: Any],
        replyHandler: (([String: Any]) -> Void)?,
        errorHandler: ((Error) -> Void)?
    ) {
        sent.append(message)
        replyHandler?([:])
    }

    func queueUserInfo(_ userInfo: [String: Any]) { sent.append(userInfo) }
    func transferFile(at url: URL, metadata: [String: Any]?) {}

    var matchTypeUpdates: [MatchTypeUpdate] {
        sent.flatMap { payload in
            SyncIncomingPayload.decode(payload).compactMap { event -> MatchTypeUpdate? in
                if case .matchTypeUpdate(let id, let rev) = event { return MatchTypeUpdate(matchID: id, revision: rev) }
                return nil
            }
        }
    }

    var tagUpdates: [MatchTagsUpdate] {
        sent.flatMap { payload in
            SyncIncomingPayload.decode(payload).compactMap { event -> MatchTagsUpdate? in
                if case .matchTagsUpdate(let id, let tags) = event { return MatchTagsUpdate(matchID: id, tags: tags) }
                return nil
            }
        }
    }

    var sentSingleMatches: [MatchRecord] {
        sent.flatMap { payload in
            SyncIncomingPayload.decode(payload).compactMap { event -> MatchRecord? in
                if case .singleMatch(let record) = event { return record }
                return nil
            }
        }
    }

    func reset() { sent.removeAll() }
}

@MainActor
private struct SyncHarness {
    let root: URL
    let store: PhoneStatsStore
    let session: RecordingSession
    let service: PhoneMatchSyncService

    init() {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("match-type-sync-\(UUID().uuidString)", isDirectory: true)
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

// MARK: - Test Helpers

private let testBaseDate = Date(timeIntervalSince1970: 1_700_000_000)

private func drainMain() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
}

private func makeCompletedMatch(
    id: UUID = UUID(),
    start: TimeInterval = 0,
    tags: MatchTags? = nil,
    type: MatchType = .singles,
    revision: MatchTypeRevision? = nil,
    totalSteps: Int? = 1250,
    totalCalories: Double? = 340.5
) -> MatchRecord {
    MatchRecord(
        id: id,
        startTime: testBaseDate.addingTimeInterval(start),
        endTime: testBaseDate.addingTimeInterval(start + 3_600),
        setScores: [SetScore(gamesMe: 6, gamesOpponent: 4)],
        stats: [
            PointStat(
                timestamp: testBaseDate.addingTimeInterval(start + 60),
                setIndex: 0,
                server: .me,
                winner: .me,
                outcome: .winner,
                endingShot: .serve,
                heartRateBPM: 145,
                stepsCumulative: 20
            )
        ],
        iWon: true,
        matchType: type,
        totalSteps: totalSteps,
        totalCaloriesKcal: totalCalories,
        tags: tags,
        matchTypeRevision: revision
    )
}

private func makeInProgressMatch(id: UUID = UUID()) -> MatchRecord {
    MatchRecord(
        id: id,
        startTime: testBaseDate,
        endTime: nil,
        setScores: [SetScore(gamesMe: 3, gamesOpponent: 2)],
        stats: [],
        iWon: nil,
        currentPointsMe: 2,
        currentPointsOpponent: 1
    )
}

// MARK: - Tests

@MainActor
struct MatchTypeConversionStoreTests {

    // MARK: 1. PhoneStatsStore.convertMatchType

    @Test func convertCompletedDoublesToSinglesNormalizesTagsAndPreservesHealthData() throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }

        let store = fixture.makeStore()
        let alex = TaggedPlayer(name: "Alex")
        let jo = TaggedPlayer(name: "Jo")
        let sam = TaggedPlayer(name: "Sam")
        let initialTags = MatchTags(opponents: [alex, jo], partner: sam, competitionType: .league, updatedAt: Date())
        let match = makeCompletedMatch(tags: initialTags, type: .doubles)
        store.saveHistory([match])

        let converted = try store.convertMatchType(id: match.id, to: .singles)

        #expect(converted.matchType == .singles)
        #expect(converted.matchTypeRevision?.matchType == .singles)
        #expect(converted.tags?.partner == nil)
        #expect(converted.tags?.opponents.count == 1)
        #expect(converted.tags?.opponents.first?.name == "Alex")
        #expect(converted.tags?.competitionType == .league)
        #expect(converted.totalSteps == 1250)
        #expect(converted.totalCaloriesKcal == 340.5)
        #expect(converted.stats.count == 1)

        // Across store relaunch
        let relaunched = fixture.makeStore().loadHistory().first
        #expect(relaunched?.matchType == .singles)
        #expect(relaunched?.matchTypeRevision?.matchType == .singles)
        #expect(relaunched?.tags?.partner == nil)
        #expect(relaunched?.tags?.opponents.count == 1)
        #expect(relaunched?.tags?.opponents.first?.name == "Alex")
        #expect(relaunched?.tags?.competitionType == .league)
        #expect(relaunched?.totalSteps == 1250)
        #expect(relaunched?.totalCaloriesKcal == 340.5)
        #expect(relaunched?.stats.count == 1)
    }

    @Test func convertCompletedSinglesToDoublesPreservesExistingOpponentAndHealthData() throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }

        let store = fixture.makeStore()
        let alex = TaggedPlayer(name: "Alex")
        let initialTags = MatchTags(opponents: [alex], partner: nil, competitionType: .friendly, updatedAt: Date())
        let match = makeCompletedMatch(tags: initialTags, type: .singles)
        store.saveHistory([match])

        let converted = try store.convertMatchType(id: match.id, to: .doubles)

        #expect(converted.matchType == .doubles)
        #expect(converted.matchTypeRevision?.matchType == .doubles)
        #expect(converted.tags?.partner == nil)
        #expect(converted.tags?.opponents.count == 1)
        #expect(converted.tags?.opponents.first?.name == "Alex")
        #expect(converted.tags?.competitionType == .friendly)
        #expect(converted.totalSteps == 1250)
        #expect(converted.totalCaloriesKcal == 340.5)

        // Across store relaunch
        let relaunched = fixture.makeStore().loadHistory().first
        #expect(relaunched?.matchType == .doubles)
        #expect(relaunched?.matchTypeRevision?.matchType == .doubles)
        #expect(relaunched?.tags?.opponents.count == 1)
        #expect(relaunched?.tags?.opponents.first?.name == "Alex")
        #expect(relaunched?.totalSteps == 1250)
        #expect(relaunched?.totalCaloriesKcal == 340.5)
    }

    @Test func convertMatchTypeThrowsMatchNotFoundAndMatchInProgress() throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }

        let store = fixture.makeStore()
        let inProgress = makeInProgressMatch()
        store.saveHistory([inProgress])

        #expect(throws: PhoneStatsStore.TagEditError.matchNotFound) {
            try store.convertMatchType(id: UUID(), to: .doubles)
        }

        #expect(throws: PhoneStatsStore.TagEditError.matchInProgress) {
            try store.convertMatchType(id: inProgress.id, to: .doubles)
        }
    }

    @Test func convertMatchTypeRollsBackWhenCanonicalWritesBlocked() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }

        let store = fixture.makeStore()
        let match = makeCompletedMatch(type: .doubles)
        store.saveHistory([match])

        try fixture.blockCanonicalWrites()

        #expect(throws: PhoneStatsStore.TagEditError.notPersisted) {
            try store.convertMatchType(id: match.id, to: .singles)
        }

        #expect(store.loadHistory().first?.matchType == .doubles)
        await drainMain()
        #expect(store.history.first?.matchType == .doubles)
    }

    // MARK: 2. PhoneStatsStore.updateMatchDetails

    @Test func updateMatchDetailsAtomicallyConvertsSinglesToDoublesWithTags() throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }

        let store = fixture.makeStore()
        let match = makeCompletedMatch(type: .singles)
        store.saveHistory([match])

        let alex = TaggedPlayer(name: "Alex")
        let jo = TaggedPlayer(name: "Jo")
        let sam = TaggedPlayer(name: "Sam")
        let draft = MatchTags(opponents: [alex, jo], partner: sam, competitionType: .league, updatedAt: Date())

        let saved = try store.updateMatchDetails(id: match.id, matchType: .doubles, tags: draft)

        #expect(saved.matchType == .doubles)
        #expect(saved.matchTypeRevision?.matchType == .doubles)
        #expect(saved.tags?.partner?.name == "Sam")
        #expect(saved.tags?.opponents.count == 2)
        #expect(saved.tags?.competitionType == .league)

        let reloaded = fixture.makeStore().loadHistory().first
        #expect(reloaded?.matchType == .doubles)
        #expect(reloaded?.tags?.partner?.name == "Sam")
        #expect(reloaded?.tags?.opponents.count == 2)
    }

    @Test func updateMatchDetailsAtomicallyConvertsDoublesToSinglesWithChosenOpponent() throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }

        let store = fixture.makeStore()
        let alex = TaggedPlayer(name: "Alex")
        let jo = TaggedPlayer(name: "Jo")
        let sam = TaggedPlayer(name: "Sam")
        let match = makeCompletedMatch(
            tags: MatchTags(opponents: [alex, jo], partner: sam, competitionType: .league, updatedAt: Date()),
            type: .doubles
        )
        store.saveHistory([match])

        let draft = MatchTags(opponents: [jo], partner: nil, competitionType: .friendly, updatedAt: Date())
        let saved = try store.updateMatchDetails(id: match.id, matchType: .singles, tags: draft)

        #expect(saved.matchType == .singles)
        #expect(saved.matchTypeRevision?.matchType == .singles)
        #expect(saved.tags?.partner == nil)
        #expect(saved.tags?.opponents.count == 1)
        #expect(saved.tags?.opponents.first?.name == "Jo")
        #expect(saved.tags?.competitionType == .friendly)
    }

    @Test func updateMatchDetailsLeavesTagsNilForUntaggedMatchConvertedType() throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }

        let store = fixture.makeStore()
        let match = makeCompletedMatch(tags: nil, type: .singles)
        store.saveHistory([match])

        let emptyDraft = MatchTags(opponents: [], partner: nil, competitionTypeRaw: nil, updatedAt: Date())
        let saved = try store.updateMatchDetails(id: match.id, matchType: .doubles, tags: emptyDraft)

        #expect(saved.matchType == .doubles)
        #expect(saved.matchTypeRevision?.matchType == .doubles)
        #expect(saved.tags == nil)

        let reloaded = fixture.makeStore().loadHistory().first
        #expect(reloaded?.matchType == .doubles)
        #expect(reloaded?.tags == nil)
    }

    @Test func updateMatchDetailsRollsBackBothTypeAndTagsWhenCanonicalWritesFail() async throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }

        let store = fixture.makeStore()
        let match = makeCompletedMatch(tags: nil, type: .singles)
        store.saveHistory([match])

        try fixture.blockCanonicalWrites()

        let alex = TaggedPlayer(name: "Alex")
        let draft = MatchTags(opponents: [alex], partner: nil, competitionType: .friendly, updatedAt: Date())

        #expect(throws: PhoneStatsStore.TagEditError.notPersisted) {
            try store.updateMatchDetails(id: match.id, matchType: .doubles, tags: draft)
        }

        #expect(store.loadHistory().first?.matchType == .singles)
        #expect(store.loadHistory().first?.tags == nil)
        await drainMain()
        #expect(store.history.first?.matchType == .singles)
        #expect(store.history.first?.tags == nil)
    }

    // MARK: 3. PhoneStatsStore.saveHistory & appendMatch carry revision forward

    @Test func saveHistoryAndAppendMatchCarryStoredRevisionForward() throws {
        let fixture = try StoreFixture()
        defer { fixture.remove() }

        let store = fixture.makeStore()
        let match = makeCompletedMatch(type: .singles)
        store.saveHistory([match])

        let converted = try store.convertMatchType(id: match.id, to: .doubles)
        let revision = converted.matchTypeRevision
        #expect(revision != nil)

        // 1. saveHistory with older unconverted copy
        let olderCopy = makeCompletedMatch(id: match.id, type: .singles, revision: nil)
        store.saveHistory([olderCopy])

        let fromSaveHistory = store.loadHistory().first
        #expect(fromSaveHistory?.matchType == .doubles)
        #expect(fromSaveHistory?.matchTypeRevision == revision)

        // 2. appendMatch with older unconverted copy
        store.appendMatch(olderCopy)

        let fromAppendMatch = store.loadHistory().first
        #expect(fromAppendMatch?.matchType == .doubles)
        #expect(fromAppendMatch?.matchTypeRevision == revision)
    }

    // MARK: 4. PhoneMatchSyncService tests

    @Test @MainActor func pushMatchTypeUpdatesSendsOnlyForOnWatchIDsAndNeverSingleMatch() async throws {
        let harness = SyncHarness()
        defer { harness.remove() }

        let onWatchMatch = makeCompletedMatch(type: .singles)
        let phoneOnlyMatch = makeCompletedMatch(type: .singles)
        harness.store.saveHistory([onWatchMatch, phoneOnlyMatch])

        try harness.store.convertMatchType(id: onWatchMatch.id, to: .doubles)
        try harness.store.convertMatchType(id: phoneOnlyMatch.id, to: .doubles)

        harness.service.handle([.watchManifest([onWatchMatch.id])])
        await drainMain()
        harness.session.reset()

        harness.service.pushMatchTypeUpdates(forMatchIDs: [onWatchMatch.id, phoneOnlyMatch.id])
        await drainMain()

        #expect(harness.session.sentSingleMatches.isEmpty)
        #expect(harness.session.matchTypeUpdates.count == 1)
        #expect(harness.session.matchTypeUpdates.first?.matchID == onWatchMatch.id)
        #expect(harness.session.matchTypeUpdates.first?.revision.matchType == .doubles)
    }

    @Test @MainActor func watchHistoryPushWithUnconvertedCopyDoesNotRevertPhoneAndReconcilesBoth() async throws {
        let harness = SyncHarness()
        defer { harness.remove() }

        let alex = TaggedPlayer(name: "Alex")
        let jo = TaggedPlayer(name: "Jo")
        let sam = TaggedPlayer(name: "Sam")
        let tags = MatchTags(opponents: [alex, jo], partner: sam, competitionType: .league, updatedAt: Date())
        let match = makeCompletedMatch(tags: tags, type: .doubles)
        harness.store.saveHistory([match])

        // User converted doubles -> singles on phone (normalizing tags to alex only)
        let converted = try harness.store.convertMatchType(id: match.id, to: .singles)
        #expect(converted.tags?.partner == nil)
        #expect(converted.tags?.opponents.count == 1)

        // Mark as held on watch
        harness.service.handle([.watchManifest([match.id])])
        await drainMain()
        harness.session.reset()

        // Watch pushes older unconverted copy with equal endTime
        let watchCopy = makeCompletedMatch(
            id: match.id,
            start: 0,
            tags: tags,
            type: .doubles,
            revision: nil
        )
        harness.service.handle([.history([watchCopy])])
        await drainMain()

        // Phone keeps singles
        let currentRecord = harness.store.loadHistory().first(where: { $0.id == match.id })
        #expect(currentRecord?.matchType == .singles)
        #expect(currentRecord?.tags?.partner == nil)
        #expect(currentRecord?.tags?.opponents.count == 1)

        // Reconcile resent both matchTypeUpdate and matchTagsUpdate
        #expect(harness.session.matchTypeUpdates.contains { $0.matchID == match.id && $0.revision.matchType == .singles })
        #expect(harness.session.tagUpdates.contains { $0.matchID == match.id && $0.tags.partner == nil && $0.tags.opponents.count == 1 })
    }

    @Test @MainActor func watchManifestWithNewlyHeldIDSendsPendingMatchTypeUpdate() async throws {
        let harness = SyncHarness()
        defer { harness.remove() }

        let match = makeCompletedMatch(type: .singles)
        harness.store.saveHistory([match])
        try harness.store.convertMatchType(id: match.id, to: .doubles)

        harness.session.reset()

        // Watch manifest newly reports match.id
        harness.service.handle([.watchManifest([match.id])])
        await drainMain()

        #expect(harness.session.matchTypeUpdates.contains { $0.matchID == match.id && $0.revision.matchType == .doubles })
    }

    @Test @MainActor func incomingMatchTypeUpdateAppliesOrAnswersBackWhenSuperseded() async throws {
        let harness = SyncHarness()
        defer { harness.remove() }

        let match = makeCompletedMatch(type: .singles)
        harness.store.saveHistory([match])
        harness.service.handle([.watchManifest([match.id])])
        await drainMain()

        // 1. Incoming revision to doubles updates phone
        let rev1 = MatchTypeRevision(
            matchType: .doubles,
            updatedAt: Date(timeIntervalSince1970: 2_000_000_000),
            revisionID: UUID()
        )
        harness.service.handle([.matchTypeUpdate(matchID: match.id, revision: rev1)])
        await drainMain()

        let updated = harness.store.loadHistory().first(where: { $0.id == match.id })
        #expect(updated?.matchType == .doubles)
        #expect(updated?.matchTypeRevision == rev1)

        // 2. Phone converts to singles with a newer clock
        let newerRev = MatchTypeRevision.revised(to: .singles, after: rev1, now: Date(timeIntervalSince1970: 2_000_000_050))
        let converted = try harness.store.convertMatchType(id: match.id, to: .singles, now: newerRev.updatedAt)
        #expect(converted.matchType == .singles)

        harness.session.reset()

        // Watch echoes an older update (rev1)
        harness.service.handle([.matchTypeUpdate(matchID: match.id, revision: rev1)])
        await drainMain()

        // Phone keeps singles and answers back with its newer revision
        let stillSingles = harness.store.loadHistory().first(where: { $0.id == match.id })
        #expect(stillSingles?.matchType == .singles)
        #expect(harness.session.matchTypeUpdates.contains { $0.matchID == match.id && $0.revision.matchType == .singles })
    }

    @Test @MainActor func watchHistoryPushConvertedFromStaleDoublesCopyPreservesNewerPhoneTagEdit() async throws {
        let harness = SyncHarness()
        defer { harness.remove() }

        let alex = TaggedPlayer(name: "Alex")
        let jo = TaggedPlayer(name: "Jo")
        let sam = TaggedPlayer(name: "Sam")
        let matchID = UUID()

        // Both devices started with doubles tags at t=100 (friendly)
        let initialTags = MatchTags(
            opponents: [alex, jo],
            partner: sam,
            competitionType: .friendly,
            updatedAt: Date(timeIntervalSince1970: 100),
            revisionID: UUID()
        )
        let match = makeCompletedMatch(id: matchID, start: 0, tags: initialTags, type: .doubles)
        harness.store.saveHistory([match])

        // 1. Phone edits tags at t=200 to .league
        let phoneTagsAt200 = MatchTags(
            opponents: [alex, jo],
            partner: sam,
            competitionType: .league,
            updatedAt: Date(timeIntervalSince1970: 200),
            revisionID: UUID()
        )
        try harness.store.updateTags(id: matchID, tags: phoneTagsAt200, now: Date(timeIntervalSince1970: 200))

        // Mark as held on watch
        harness.service.handle([.watchManifest([matchID])])
        await drainMain()
        harness.session.reset()

        // 2. Watch converts its stale t=100 doubles copy to .singles at t=300
        let watchSinglesRev = MatchTypeRevision(
            matchType: .singles,
            updatedAt: Date(timeIntervalSince1970: 300),
            revisionID: UUID()
        )
        let watchCopy = makeCompletedMatch(
            id: matchID,
            start: 0,
            tags: initialTags.normalizedForSingles(),
            type: .singles,
            revision: watchSinglesRev
        )
        harness.service.handle([.history([watchCopy])])
        await drainMain()

        // Phone archive becomes .singles with .league + [Alex] + partner == nil
        let currentRecord = harness.store.loadHistory().first(where: { $0.id == matchID })
        #expect(currentRecord?.matchType == .singles)
        #expect(currentRecord?.tags?.competitionType == .league)
        #expect(currentRecord?.tags?.partner == nil)
        #expect(currentRecord?.tags?.opponents.count == 1)
        #expect(currentRecord?.tags?.opponents.first?.name == "Alex")
        #expect(currentRecord?.tags?.updatedAt == Date(timeIntervalSince1970: 200))

        // And sends the normalized .league matchTagsUpdate back to the watch
        #expect(harness.session.tagUpdates.contains {
            $0.matchID == matchID &&
            $0.tags.competitionType == .league &&
            $0.tags.partner == nil &&
            $0.tags.opponents.count == 1 &&
            $0.tags.opponents.first?.name == "Alex"
        })
    }
}
