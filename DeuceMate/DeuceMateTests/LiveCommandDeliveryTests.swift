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
        service.updatePublishedWatchState(isPaired: true, isWatchAppInstalled: true, isReachable: false, pendingTransferCount: 0)
        #expect(!service.isLiveStateConfirmed)
        session.state = LiveMatchState(record: nil, inputEnabled: true)
        session.automaticallyReply = false
        service.updatePublishedWatchState(isPaired: true, isWatchAppInstalled: true, isReachable: true, pendingTransferCount: 0)
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
        service.updatePublishedWatchState(isPaired: true, isWatchAppInstalled: true, isReachable: false, pendingTransferCount: 0)
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
}
