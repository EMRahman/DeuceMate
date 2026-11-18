// Live commands wait for Watch state; failures never replay scoring intent.
import Dispatch
import Foundation
import DeuceMateCore
import Testing
@testable import DeuceMate

private final class LiveCommandSession: MatchSyncSessing {
    var isActivated = true
    var isReachable = true
    var failLiveSend = false
    var automaticallyReply = true
    var blankReply = false
    var state = LiveMatchState(record: MatchRecord(startTime: Date(), setScores: [SetScore()], stats: []), inputEnabled: true)
    let sessionID = UUID()
    var sequence: UInt64 = 0
    var message: String?
    private(set) var requests: [LiveMatchRequest] = []
    private(set) var queued: [[String: Any]] = []
    var pendingReplies: [([String: Any]) -> Void] = []

    func sendMessage(_ message: [String: Any],
                     replyHandler: (([String: Any]) -> Void)?,
                     errorHandler: ((Error) -> Void)?) {
        guard let data = message[MatchSyncKey.liveRequest] as? Data,
              let request = try? JSONDecoder().decode(LiveMatchRequest.self, from: data) else { return }
        requests.append(request)
        if failLiveSend { errorHandler?(NSError(domain: "test.live", code: 1)); return }
        guard let replyHandler else { return }
        if automaticallyReply { replyHandler(reply()) } else { pendingReplies.append(replyHandler) }
    }
    func reply() -> [String: Any] {
        if blankReply { return [:] }
        sequence += 1
        return (try? MatchSyncPayloadBuilder.liveReply(LiveMatchReply(state: state, message: message,
            sessionID: sessionID, sequence: sequence))) ?? [:]
    }
    func queueUserInfo(_ userInfo: [String: Any]) { queued.append(userInfo) }
    func transferFile(at url: URL, metadata: [String: Any]?) {}
    func resetRequests() { requests = [] }
}

/// Records scheduled work so tests can run request timeouts (10 s) and
/// countdown ticks (1 s) on demand.
private final class ManualScheduler {
    private var items: [(delay: TimeInterval, work: DispatchWorkItem)] = []
    func schedule(_ delay: TimeInterval, _ work: DispatchWorkItem) { items.append((delay, work)) }
    var pendingTicks: Int { items.filter { $0.delay == 1 }.count }
    func runLatest(delay: TimeInterval) {
        guard let index = items.lastIndex(where: { $0.delay == delay }) else { return }
        items.remove(at: index).work.perform()
    }
}

@MainActor
struct LiveCommandDeliveryTests {
    private func makeService(_ session: LiveCommandSession,
                             schedule: @escaping (TimeInterval, DispatchWorkItem) -> Void = { _, _ in }) -> PhoneMatchSyncService {
        PhoneMatchSyncService(isSessionSupported: { false }, activateSession: { _ in },
            scheduleAfter: schedule, transport: MatchSyncTransport(session: session))
    }
    private func drainMainQueue() async {
        // A failed command schedules one read-only recovery request and its reply.
        for _ in 0..<3 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }
    private func ready(_ service: PhoneMatchSyncService, _ session: LiveCommandSession) async {
        service.requestLiveState()
        await drainMainQueue()
        #expect(service.isLiveStateConfirmed)
        session.resetRequests()
    }
    private func sendEveryLiveCommand(through service: PhoneMatchSyncService) async {
        service.sendScoreCommand(MatchSyncKey.scoreCommandWinMe, matchID: service.activeMatchID)
        await drainMainQueue()
        service.sendSelectOutcome(.winner)
        await drainMainQueue()
        service.sendCommitEndingShot(.rally)
        await drainMainQueue()
        service.sendCancelOutcomeSelection()
        await drainMainQueue()
        service.sendUndoPoint()
        await drainMainQueue()
    }

    @Test func deliveredCommandsReportNoFailure() async {
        let session = LiveCommandSession()
        // Keep the transport and observed Watch state from the same peer.
        let connected = makeService(session)
        await ready(connected, session)
        await sendEveryLiveCommand(through: connected)
        #expect(session.requests.count == 5)
        #expect(connected.liveCommandFailureCount == 0)
        #expect(!connected.isLiveRequestInFlight)
    }

    @Test func unreachableCommandsAreDroppedAndReported() async {
        let session = LiveCommandSession()
        session.isReachable = false
        let service = makeService(session)
        await sendEveryLiveCommand(through: service)
        #expect(session.requests.isEmpty)
        #expect(session.queued.isEmpty)
        #expect(service.liveCommandFailureCount == 5)
    }

    @Test func connectionLostDuringSendRefreshesWithoutRetryingTheCommand() async {
        let session = LiveCommandSession()
        let connected = makeService(session)
        await ready(connected, session)
        session.failLiveSend = true
        connected.sendScoreCommand(MatchSyncKey.scoreCommandWinMe, matchID: connected.activeMatchID)
        await drainMainQueue()
        #expect(session.requests.filter { $0.action != nil }.count == 1)
        #expect(session.requests.filter { $0.action == nil }.count == 1)
        #expect(session.queued.isEmpty)
        #expect(connected.liveCommandFailureCount > 0)
        #expect(!connected.isLiveStateConfirmed)
    }

    @Test func settingsPushesStayQueuedAndAreNotLiveFailures() async {
        let session = LiveCommandSession()
        session.isReachable = false
        let service = makeService(session)
        service.pushIPhoneInputEnabled(true)
        await drainMainQueue()
        #expect(session.queued.count == 1)
        #expect(service.liveCommandFailureCount == 0)
    }

    @Test func watchAcknowledgementPushUnlocksInputWithoutARefresh() async throws {
        let session = LiveCommandSession()
        let record = try #require(session.state.record)
        session.state = LiveMatchState(record: record, inputEnabled: true,
            blockingReason: "Continue on the Watch before scoring.")
        let service = makeService(session)
        await ready(service, session)
        service.sendScoreCommand(MatchSyncKey.scoreCommandWinMe, matchID: record.id)
        #expect(session.requests.isEmpty)

        session.state = LiveMatchState(record: record, inputEnabled: true)
        let data = try #require(session.reply()[MatchSyncKey.liveReply] as? Data)
        service.handle([.liveState(try JSONDecoder().decode(LiveMatchReply.self, from: data))])
        await drainMainQueue()
        #expect(service.isLiveStateConfirmed)
        #expect(service.liveState?.blockingReason == nil)
        #expect(service.liveState?.record == record, "Acknowledgement does not score another point")
        #expect(session.requests.isEmpty, "A push must release the existing confirmation without a refresh")

        service.sendScoreCommand(MatchSyncKey.scoreCommandWinMe, matchID: record.id)
        await drainMainQueue()
        #expect(session.requests.map(\.action) == [MatchSyncKey.scoreCommandWinMe])
    }

    @Test func scoreDoesNotChangeLocallyAndOnlyOneRequestCanBeInFlight() async throws {
        let session = LiveCommandSession()
        let connected = makeService(session)
        await ready(connected, session)
        session.automaticallyReply = false
        let before = connected.liveState
        connected.sendScoreCommand(MatchSyncKey.scoreCommandWinMe, matchID: connected.activeMatchID)
        connected.sendScoreCommand(MatchSyncKey.scoreCommandWinMe, matchID: connected.activeMatchID)
        #expect(connected.isLiveRequestInFlight)
        #expect(session.requests.count == 1)
        #expect(connected.liveState == before)
        var record = try #require(session.state.record)
        record.currentPointsMe = 1
        session.state = LiveMatchState(record: record, inputEnabled: true)
        session.pendingReplies[0](session.reply())
        await drainMainQueue()
        #expect(connected.liveState?.record?.currentPointsMe == 1)
        #expect(!connected.isLiveRequestInFlight)
    }

    @Test func reconnectRequiresFreshStateAndMissedIdleClearsPendingPoint() async {
        let session = LiveCommandSession()
        let service = makeService(session)
        session.state = LiveMatchState(record: session.state.record,
            pendingPoint: PendingPointInfo(server: .me, winner: .me, setIndex: 0, isSecondServe: false),
            pendingOutcome: .winner, inputEnabled: true)
        await ready(service, session)
        service.updatePublishedWatchState(isPaired: true, isWatchAppInstalled: true, isReachable: false, transfers: (userInfo: 0, files: 0))
        #expect(!service.isLiveStateConfirmed)
        session.state = LiveMatchState(record: nil, inputEnabled: true)
        session.automaticallyReply = false
        service.updatePublishedWatchState(isPaired: true, isWatchAppInstalled: true, isReachable: true, transfers: (userInfo: 0, files: 0))
        #expect(!service.isLiveStateConfirmed, "reachability alone cannot unlock input")
        service.requestLiveState()
        session.pendingReplies[0](session.reply())
        await drainMainQueue()
        #expect(service.isLiveStateConfirmed)
        #expect(service.activeMatchID == nil)
        #expect(service.pendingPoint == nil)
        #expect(service.pendingPointOutcome == nil)
    }

    @Test func reconnectCatchesUpWithoutAnotherPointAndPushDoesNotCompleteARequest() async throws {
        let session = LiveCommandSession()
        let service = makeService(session)
        await ready(service, session)
        service.updatePublishedWatchState(isPaired: true, isWatchAppInstalled: true, isReachable: false, transfers: (userInfo: 0, files: 0))
        var record = try #require(session.state.record)
        record.currentPointsMe = 3
        session.state = LiveMatchState(record: record, inputEnabled: true)
        session.automaticallyReply = false
        service.requestLiveState()
        let earlierReply = session.reply()
        record.currentPointsMe = 2 // Watch undo arrives after the snapshot was built.
        session.state = LiveMatchState(record: record, inputEnabled: true)
        let newerReply = try #require(session.reply()[MatchSyncKey.liveReply] as? Data)
        service.handle([.liveState(try JSONDecoder().decode(LiveMatchReply.self, from: newerReply))])
        await drainMainQueue()
        #expect(!service.isLiveStateConfirmed)
        #expect(service.isLiveRequestInFlight)
        session.pendingReplies[0](earlierReply)
        await drainMainQueue()
        #expect(service.isLiveStateConfirmed)
        #expect(service.liveState?.record?.currentPointsMe == 2, "an older response cannot overwrite the newer Watch undo")
        #expect(session.requests.filter { $0.action != nil }.isEmpty)
    }

    @Test func timeoutReconcilesAndIgnoresTheLateCommandReply() async {
        let session = LiveCommandSession()
        var timeouts: [DispatchWorkItem] = []
        let service = makeService(session, schedule: { _, work in timeouts.append(work) })
        await ready(service, session)
        session.automaticallyReply = false
        service.sendScoreCommand(MatchSyncKey.scoreCommandWinMe, matchID: service.activeMatchID)
        let lateCommandReply = session.pendingReplies[0]
        timeouts.last?.perform()
        #expect(session.requests.map(\.action) == [MatchSyncKey.scoreCommandWinMe, nil])
        #expect(service.isLiveRequestInFlight, "the read-only recovery is now pending")
        lateCommandReply(session.reply())
        await drainMainQueue()
        #expect(!service.isLiveStateConfirmed)
        #expect(service.isLiveRequestInFlight)
        session.pendingReplies[1](session.reply())
        await drainMainQueue()
        #expect(service.isLiveStateConfirmed)
        #expect(!service.isLiveRequestInFlight)
        #expect(session.queued.isEmpty)
    }

    @Test func blankLegacyReplyNeverConfirmsReadiness() async {
        let session = LiveCommandSession()
        session.blankReply = true
        let service = makeService(session)
        service.requestLiveState()
        await drainMainQueue()
        #expect(!service.isLiveStateConfirmed)
        service.sendScoreCommand(MatchSyncKey.scoreCommandWinMe, matchID: UUID())
        #expect(session.requests.count == 1, "no score command before a supported state response")
    }

    @Test func rejectionShowsWatchReasonAndDelayedHistoryCannotReplaceLiveState() async throws {
        let session = LiveCommandSession()
        let service = makeService(session)
        await ready(service, session)
        session.message = "Continue on the Watch before scoring."
        service.sendScoreCommand(MatchSyncKey.scoreCommandWinMe, matchID: service.activeMatchID)
        await drainMainQueue()
        #expect(service.liveCommandMessage == session.message)
        #expect(service.liveCommandFailureCount == 1)
        let current = try #require(service.liveState?.record)
        var stale = current
        stale.currentPointsMe = 99
        service.handle([.history([stale]), .clearActiveMatch])
        await drainMainQueue()
        #expect(service.liveState?.record == current)
        #expect(service.activeMatchID == current.id)
    }

    // MARK: - Watch prompts

    @Test func promptAnswerIsTheOneCommandAllowedWhileTheWatchIsBlocked() async throws {
        let session = LiveCommandSession()
        let record = try #require(session.state.record)
        let prompt = LiveWatchPrompt.changeover(symbol: "🔁 🎾", reason: "Even games – balls change ends")
        session.state = LiveMatchState(record: record, inputEnabled: true,
            blockingReason: "Continue on the Watch before scoring.", prompt: prompt)
        let service = makeService(session)
        await ready(service, session)
        session.resetRequests()

        service.sendScoreCommand(MatchSyncKey.scoreCommandWinMe, matchID: record.id)
        #expect(session.requests.isEmpty, "Points still wait for the prompt")
        let failuresBefore = service.liveCommandFailureCount

        session.state = LiveMatchState(record: record, inputEnabled: true)
        service.sendWatchPromptAnswer(try #require(prompt.answers.first))
        await drainMainQueue()
        let sent = try #require(session.requests.last)
        #expect(session.requests.count == 1)
        #expect(sent.action == MatchSyncKey.promptActionAcknowledgeChangeover)
        #expect(sent.prompt == prompt, "The Watch checks the prompt it is answering")
        #expect(sent.matchID == record.id)
        #expect(service.liveState?.prompt == nil, "Only the Watch reply clears the prompt")
        #expect(service.liveCommandFailureCount == failuresBefore, "The answer itself is not a failure")
    }

    @Test func doublesAnswerCarriesTheChosenPlayer() async throws {
        let session = LiveCommandSession()
        let record = try #require(session.state.record)
        session.state = LiveMatchState(record: record, inputEnabled: true,
            blockingReason: "Continue on the Watch before scoring.", prompt: .doublesServer)
        let service = makeService(session)
        await ready(service, session)
        session.resetRequests()

        service.sendWatchPromptAnswer(try #require(LiveWatchPrompt.doublesServer.answers.last))
        await drainMainQueue()
        #expect(session.requests.map(\.doublesServer) == [.partner])
        #expect(session.requests.map(\.action) == [MatchSyncKey.promptActionChooseDoublesServer])
    }

    @Test func answerForAPromptThatIsNotShownIsNeverSent() async throws {
        let session = LiveCommandSession()
        let record = try #require(session.state.record)
        session.state = LiveMatchState(record: record, inputEnabled: true)
        let service = makeService(session)
        await ready(service, session)
        session.resetRequests()

        let stale = LiveWatchPrompt.changeover(symbol: "🔁 🎾", reason: "Already answered on the Watch")
        service.sendWatchPromptAnswer(try #require(stale.answers.first))
        await drainMainQueue()
        #expect(session.requests.isEmpty)
        #expect(service.liveCommandFailureCount == 1)
    }

    @Test func promptAnswerNeedsIPhoneInputAndAReachableWatch() async throws {
        let session = LiveCommandSession()
        let record = try #require(session.state.record)
        session.state = LiveMatchState(record: record, inputEnabled: false,
            blockingReason: "Continue on the Watch before scoring.", prompt: .doublesServer)
        let service = makeService(session)
        await ready(service, session)
        session.resetRequests()
        service.sendWatchPromptAnswer(try #require(LiveWatchPrompt.doublesServer.answers.first))
        await drainMainQueue()
        #expect(session.requests.isEmpty)

        session.state = LiveMatchState(record: record, inputEnabled: true,
            blockingReason: "Continue on the Watch before scoring.", prompt: .doublesServer)
        await ready(service, session)
        session.resetRequests()
        session.isReachable = false
        service.sendWatchPromptAnswer(try #require(LiveWatchPrompt.doublesServer.answers.first))
        await drainMainQueue()
        #expect(session.requests.isEmpty)
    }

    // MARK: - Automatic refresh retry

    private func makeService(_ session: LiveCommandSession, scheduler: ManualScheduler) -> PhoneMatchSyncService {
        makeService(session, schedule: { scheduler.schedule($0, $1) })
    }

    /// Runs the countdown one tick at a time, recording what it showed, and
    /// lets the refresh it ends with finish.
    @discardableResult
    private func runCountdown(_ service: PhoneMatchSyncService, _ scheduler: ManualScheduler) async -> [Int] {
        var shown: [Int] = []
        while let seconds = service.liveRetryCountdown, shown.count < 60 {
            shown.append(seconds)
            scheduler.runLatest(delay: 1)
        }
        await drainMainQueue()
        return shown
    }

    @Test func failedRefreshCountsDownAndAsksAgain() async {
        let session = LiveCommandSession()
        session.failLiveSend = true
        let scheduler = ManualScheduler()
        let service = makeService(session, scheduler: scheduler)
        service.requestLiveState()
        await drainMainQueue()
        #expect(service.liveRetryCountdown == 3)
        #expect(service.liveCommandFailureCount == 0,
                "the countdown explains a failed refresh; the command-failure message would hide it")
        #expect(!service.isLiveStateConfirmed)

        session.failLiveSend = false
        let shown = await runCountdown(service, scheduler)
        #expect(shown == [3, 2, 1])
        #expect(session.requests.map(\.action) == [nil, nil])
        #expect(service.isLiveStateConfirmed)
        #expect(service.liveRetryCountdown == nil)
        #expect(scheduler.pendingTicks == 0)
    }

    @Test func retriesBackOffAndStopAtTheRefreshButton() async {
        let session = LiveCommandSession()
        session.failLiveSend = true
        let scheduler = ManualScheduler()
        let service = makeService(session, scheduler: scheduler)
        service.requestLiveState()
        await drainMainQueue()
        var starts: [Int] = []
        while let seconds = service.liveRetryCountdown, starts.count < 10 {
            starts.append(seconds)
            await runCountdown(service, scheduler)
        }
        #expect(starts == LiveRefreshRetry.delays)
        #expect(session.requests.count == LiveRefreshRetry.delays.count + 1)
        #expect(service.liveRetryCountdown == nil)
        #expect(!service.isLiveStateConfirmed)
        #expect(LiveScoreboardStatus(isWatchReachable: true, isInputEnabled: true, isStateConfirmed: false,
                                     retryCountdown: service.liveRetryCountdown).detail
                == "Current score not confirmed. Refresh to reconnect.")
    }

    @Test func newWatchPointRestoresCategoryInputAfterReconnectRetriesExpire() async throws {
        let session = LiveCommandSession()
        let scheduler = ManualScheduler()
        let service = makeService(session, scheduler: scheduler)
        await ready(service, session)
        var record = try #require(session.state.record)
        let pending = PendingPointInfo(server: .me, winner: .me, setIndex: 0, isSecondServe: false)

        session.failLiveSend = true
        service.requestLiveState()
        await drainMainQueue()
        record.currentPointsMe = 1
        session.state = LiveMatchState(record: record, pendingPoint: pending, inputEnabled: true)
        service.handle(SyncIncomingPayload.decode(session.reply()))
        await drainMainQueue()
        #expect(service.liveRetryCountdown == 3)
        #expect(session.requests.count == 1, "A point during backoff uses the scheduled retry")
        for _ in LiveRefreshRetry.delays { await runCountdown(service, scheduler) }
        #expect(service.liveRetryCountdown == nil)
        session.resetRequests()

        service.handle(SyncIncomingPayload.decode(session.reply()))
        await drainMainQueue()
        #expect(session.requests.isEmpty, "A new wire sequence for the same score cannot restart retries")

        session.failLiveSend = false
        session.automaticallyReply = false
        record.currentPointsMe = 2
        record.checkpointRevision += 1
        session.state = LiveMatchState(record: record, pendingPoint: pending, inputEnabled: true)
        let point = SyncIncomingPayload.decode(session.reply())
        service.handle(point)
        service.handle(point) // Message and application context can carry the same point.
        await drainMainQueue()
        #expect(service.pendingPoint == pending)
        #expect(service.liveState?.record?.currentPointsMe == 2)
        #expect(!service.isLiveStateConfirmed)
        service.sendSelectOutcome(.winner)
        #expect(session.requests.map(\.action) == [nil])
        let confirm = try #require(session.pendingReplies.first)
        confirm(session.reply())
        await drainMainQueue()
        #expect(service.isLiveStateConfirmed)
        #expect(service.isWatchReachable)
        #expect(!service.isLiveRequestInFlight)
        #expect(service.pendingPoint == pending)
        service.sendSelectOutcome(.winner)
        #expect(session.requests.map(\.action) == [nil, MatchSyncKey.statActionSelectOutcome])
        #expect(session.requests.last?.pendingPoint == pending)
    }

    @Test func offlineAndBackgroundWatchPointsOnlyUpdateTheDisplay() async throws {
        let session = LiveCommandSession()
        let service = makeService(session)
        await ready(service, session)
        var record = try #require(session.state.record)
        session.isReachable = false
        service.updatePublishedWatchState(isPaired: true, isWatchAppInstalled: true,
            isReachable: false, transfers: (0, 0))
        record.currentPointsMe = 1
        session.state = LiveMatchState(record: record, inputEnabled: true)
        service.handle(SyncIncomingPayload.decode(session.reply()))
        await drainMainQueue()
        #expect(session.requests.isEmpty)
        #expect(!service.isLiveStateConfirmed)
        #expect(service.liveState?.record?.currentPointsMe == 1)

        service.pauseLiveState()
        session.isReachable = true
        record.currentPointsMe = 2
        session.state = LiveMatchState(record: record, inputEnabled: true)
        service.handle(SyncIncomingPayload.decode(session.reply()))
        await drainMainQueue()
        #expect(session.requests.isEmpty)
        #expect(!service.isLiveStateConfirmed)
        #expect(service.liveState?.record?.currentPointsMe == 2)
        service.resumeLiveState()
        await drainMainQueue()
        #expect(session.requests.map(\.action) == [nil])
        #expect(service.isLiveStateConfirmed)
    }

    @Test func pointCanRecoverInputBeforeTheReachabilityCallback() async throws {
        let session = LiveCommandSession()
        let service = makeService(session)
        await ready(service, session)
        session.isReachable = false
        service.updatePublishedWatchState(isPaired: true, isWatchAppInstalled: true,
            isReachable: false, transfers: (0, 0))

        session.isReachable = true // Bluetooth returns before a new delegate notification.
        var record = try #require(session.state.record)
        record.currentPointsOpponent = 1
        session.state = LiveMatchState(record: record, inputEnabled: true)
        service.handle(SyncIncomingPayload.decode(session.reply()))
        await drainMainQueue()
        #expect(session.requests.map(\.action) == [nil])
        #expect(service.isWatchReachable)
        #expect(service.isLiveStateConfirmed)
        service.sendScoreCommand(MatchSyncKey.scoreCommandWinMe, matchID: record.id)
        #expect(session.requests.map(\.action) == [nil, MatchSyncKey.scoreCommandWinMe])
    }

    @Test func freshRequestRestartsTheRetryBudget() async {
        let session = LiveCommandSession()
        session.failLiveSend = true
        let scheduler = ManualScheduler()
        let service = makeService(session, scheduler: scheduler)
        service.requestLiveState()
        await drainMainQueue()
        await runCountdown(service, scheduler)
        #expect(service.liveRetryCountdown == 5)
        service.requestLiveState() // Retry Now / reopening the scoreboard
        await drainMainQueue()
        #expect(service.liveRetryCountdown == 3)
    }

    @Test func losingTheWatchCancelsTheCountdown() async {
        let session = LiveCommandSession()
        session.failLiveSend = true
        let scheduler = ManualScheduler()
        let service = makeService(session, scheduler: scheduler)
        service.requestLiveState()
        await drainMainQueue()
        #expect(service.liveRetryCountdown == 3)
        session.isReachable = false
        service.updatePublishedWatchState(isPaired: true, isWatchAppInstalled: true, isReachable: false, transfers: (userInfo: 0, files: 0))
        #expect(service.liveRetryCountdown == nil)
        scheduler.runLatest(delay: 1) // a tick already scheduled must do nothing
        await drainMainQueue()
        #expect(service.liveRetryCountdown == nil)
        #expect(session.requests.count == 1)
    }

    @Test func automaticRetriesNeverReplayAScoreCommand() async {
        let session = LiveCommandSession()
        let scheduler = ManualScheduler()
        let service = makeService(session, scheduler: scheduler)
        service.requestLiveState()
        await drainMainQueue()
        #expect(service.isLiveStateConfirmed)
        session.resetRequests()
        session.failLiveSend = true
        service.sendScoreCommand(MatchSyncKey.scoreCommandWinMe, matchID: service.activeMatchID)
        await drainMainQueue()
        #expect(service.liveCommandFailureCount == 1, "a failed command still says so")
        await runCountdown(service, scheduler)
        await runCountdown(service, scheduler)
        #expect(session.requests.filter { $0.action != nil }.count == 1)
        #expect(session.requests.filter { $0.action == nil }.count == 3)
        #expect(session.queued.isEmpty)
    }

    @Test func lateRefreshReplyShowsTheNewerScoreWithoutConfirming() async throws {
        let session = LiveCommandSession()
        let scheduler = ManualScheduler()
        let service = makeService(session, scheduler: scheduler)
        service.requestLiveState()
        await drainMainQueue()
        session.automaticallyReply = false
        service.requestLiveState()
        scheduler.runLatest(delay: 10) // the reply misses the timeout
        await drainMainQueue()
        #expect(service.liveRetryCountdown == 3)

        var record = try #require(session.state.record)
        record.currentPointsMe = 3
        session.state = LiveMatchState(record: record, inputEnabled: true)
        session.pendingReplies[0](session.reply())
        await drainMainQueue()
        #expect(service.liveState?.record?.currentPointsMe == 3, "the late reply is still the Watch's score")
        #expect(!service.isLiveStateConfirmed, "only the current request can unlock input")
        #expect(service.liveRetryCountdown == 3, "the retry still confirms readiness")
    }

    @Test func lateReplyFromAnotherWatchSessionIsIgnored() async throws {
        let session = LiveCommandSession()
        let scheduler = ManualScheduler()
        let service = makeService(session, scheduler: scheduler)
        service.requestLiveState()
        await drainMainQueue()
        let before = service.liveState
        session.automaticallyReply = false
        service.requestLiveState()
        scheduler.runLatest(delay: 10)
        await drainMainQueue()

        var record = try #require(session.state.record)
        record.currentPointsMe = 3
        let other = LiveMatchReply(state: LiveMatchState(record: record, inputEnabled: true),
                                   message: nil, sessionID: UUID(), sequence: 99)
        session.pendingReplies[0]((try? MatchSyncPayloadBuilder.liveReply(other)) ?? [:])
        await drainMainQueue()
        #expect(service.liveState == before)
    }

    @Test func pushFromNewWatchSessionAppliesNewScoreWhileReconfirming() async throws {
        let session = LiveCommandSession()
        let service = makeService(session)
        await ready(service, session)
        session.resetRequests()

        session.isReachable = false
        service.updatePublishedWatchState(isPaired: true, isWatchAppInstalled: true, isReachable: false, transfers: (userInfo: 0, files: 0))
        var record = try #require(session.state.record)
        record.currentPointsMe = 2
        let restartedReply = LiveMatchReply(
            state: LiveMatchState(record: record, inputEnabled: true),
            message: nil,
            sessionID: UUID(),
            sequence: 1
        )
        // Even while the Watch remains unreachable for RPC confirmation, a push
        // (e.g. via applicationContext) from a restarted Watch session updates the score.
        service.handle([.liveState(restartedReply)])
        await drainMainQueue()
        #expect(service.liveState?.record?.currentPointsMe == 2)
        #expect(!service.isLiveStateConfirmed, "new Watch session still waits for confirmation")
        #expect(session.requests.isEmpty)
    }

    @Test func coldStartLateReplyShowsScoreWithoutConfirming() async throws {
        let session = LiveCommandSession()
        session.automaticallyReply = false
        let scheduler = ManualScheduler()
        let service = makeService(session, scheduler: scheduler)
        service.requestLiveState()
        scheduler.runLatest(delay: 10)
        await drainMainQueue()
        #expect(service.liveState == nil)

        var record = try #require(session.state.record)
        record.currentPointsOpponent = 2
        session.state = LiveMatchState(record: record, inputEnabled: true)
        session.pendingReplies[0](session.reply())
        await drainMainQueue()
        #expect(service.liveState?.record?.currentPointsOpponent == 2)
        #expect(!service.isLiveStateConfirmed)
    }

    @Test func delayedPushFromSupersededWatchSessionIsIgnored() async throws {
        let session = LiveCommandSession()
        let service = makeService(session)
        await ready(service, session)
        let sessionAID = session.sessionID

        var recordB = try #require(session.state.record)
        recordB.currentPointsMe = 3
        let sessionBID = UUID()
        let sessionBReply = LiveMatchReply(
            state: LiveMatchState(record: recordB, inputEnabled: true),
            message: nil,
            sessionID: sessionBID,
            sequence: 1
        )
        session.isReachable = false
        service.updatePublishedWatchState(isPaired: true, isWatchAppInstalled: true, isReachable: false, transfers: (userInfo: 0, files: 0))
        service.handle([.liveState(sessionBReply)])
        await drainMainQueue()
        #expect(service.liveState?.record?.currentPointsMe == 3)

        var staleRecordA = try #require(session.state.record)
        staleRecordA.currentPointsMe = 1
        let delayedAReply = LiveMatchReply(
            state: LiveMatchState(record: staleRecordA, inputEnabled: true),
            message: nil,
            sessionID: sessionAID,
            sequence: 99
        )
        service.handle([.liveState(delayedAReply)])
        await drainMainQueue()
        #expect(service.liveState?.record?.currentPointsMe == 3,
                "a delayed push from retired session A must not replace session B")
    }

    @Test func currentRequestRecoversAfterAnUnseenOldContext() async throws {
        let session = LiveCommandSession()
        let service = makeService(session)
        var current = try #require(session.state.record)
        current.currentPointsMe = 3
        session.state = LiveMatchState(record: current, inputEnabled: true)
        await ready(service, session)

        // The app first heard from the running Watch via RPC. Simulate a
        // previously unseen context belonging to its previous process.
        var old = current
        old.currentPointsMe = 1
        service.handle([.liveState(LiveMatchReply(
            state: LiveMatchState(record: old, inputEnabled: true), sessionID: UUID(), sequence: 1))])
        await drainMainQueue()
        #expect(session.requests.count == 1, "a mismatched session triggered one confirming refresh")
        #expect(service.isLiveStateConfirmed)
        #expect(service.liveState?.record?.currentPointsMe == 3)
    }

    @Test func olderCheckpointFromAnUnseenSessionCannotRegressOfflineScore() async throws {
        let session = LiveCommandSession()
        var record = try #require(session.state.record)
        record.currentPointsMe = 3
        record.checkpointRevision = 5
        session.state = LiveMatchState(record: record, inputEnabled: true)
        let service = makeService(session)
        await ready(service, session)
        session.isReachable = false
        service.updatePublishedWatchState(isPaired: true, isWatchAppInstalled: true,
            isReachable: false, transfers: (0, 0))
        record.currentPointsMe = 1
        record.checkpointRevision = 2
        service.handle([.liveState(LiveMatchReply(state: LiveMatchState(record: record, inputEnabled: true),
            sessionID: UUID(), sequence: 99))])
        await drainMainQueue()
        #expect(service.liveState?.record?.currentPointsMe == 3)
        #expect(!service.isLiveStateConfirmed)
    }

    @Test func queuedArchiveCheckpointCannotRollBackANewerPoint() throws {
        var before = MatchRecord(startTime: Date(), setScores: [SetScore()], stats: [])
        before.currentPointsMe = 1
        before.checkpointRevision = 1
        let session = LiveCommandSession()
        session.isReachable = false
        MatchSyncTransport(session: session).sendRecordReliable(before)
        var after = before
        after.currentPointsMe = 2
        after.checkpointRevision = 2
        let queued = try #require(session.queued.first)
        guard case .singleMatch(let old) = SyncIncomingPayload.decode(queued).first else {
            Issue.record("Expected a queued Watch record")
            return
        }
        let merged = MatchMergePolicy.merge(incoming: [old], into: [after])
        #expect(merged.first?.currentPointsMe == 2)
    }

    @Test func cachedPermissionPreservesThePhonesOfflineSetting() async throws {
        let defaults = UserDefaults.standard
        let key = MatchSyncKey.iPhoneInputEnabled
        let previous = defaults.object(forKey: key)
        defer { defaults.set(previous, forKey: key) }
        defaults.set(false, forKey: key)

        let session = LiveCommandSession()
        session.isReachable = false
        let service = makeService(session)
        let data = try #require(session.reply()[MatchSyncKey.liveReply] as? Data)
        service.handle(SyncIncomingPayload.decode([MatchSyncKey.liveReply: data]))
        await drainMainQueue()
        #expect(service.liveState?.inputEnabled == true)
        #expect(!service.isLiveStateConfirmed)
        #expect(!defaults.bool(forKey: key))
    }

    @Test func firstLiveScoreOpensMatchesBeforeTheArchiveArrives() async {
        let session = LiveCommandSession()
        let service = makeService(session)
        #expect(PastMatchesView.showsEmptyArchive(hasHistory: false, hasLiveMatch: false, hasWatchRows: false))
        service.handle(SyncIncomingPayload.decode(session.reply()))
        await drainMainQueue()
        #expect(!PastMatchesView.showsEmptyArchive(hasHistory: false,
            hasLiveMatch: service.liveState?.record != nil, hasWatchRows: false))
    }

}
