// LiveCommandDeliveryTests.swift — Live score and category commands fail fast and
// report anything undelivered, so the scoreboard can say so.
import Dispatch
import Foundation
import DeuceMateCore
import Testing
@testable import DeuceMate

private final class LiveCommandSession: MatchSyncSessing {
    var isActivated = true
    var isReachable = true
    var failLiveSend = false
    private(set) var sent: [[String: Any]] = []
    private(set) var queued: [[String: Any]] = []

    func sendMessage(_ message: [String: Any],
                     replyHandler: (([String: Any]) -> Void)?,
                     errorHandler: ((Error) -> Void)?) {
        sent.append(message)
        if failLiveSend {
            errorHandler?(NSError(domain: "test.live", code: 1))
        } else {
            replyHandler?([:])
        }
    }
    func queueUserInfo(_ userInfo: [String: Any]) { queued.append(userInfo) }
    func transferFile(at url: URL, metadata: [String: Any]?) {}
}

@MainActor
struct LiveCommandDeliveryTests {
    private func makeService(_ session: LiveCommandSession) -> PhoneMatchSyncService {
        PhoneMatchSyncService(
            isSessionSupported: { false },
            activateSession: { _ in },
            scheduleAfter: { _, _ in },
            transport: MatchSyncTransport(session: session)
        )
    }

    /// Lets the failure counter's main-queue hop run.
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    /// Every live command the scoreboard can send.
    private func sendEveryLiveCommand(through service: PhoneMatchSyncService) {
        service.sendScoreCommand(MatchSyncKey.scoreCommandWinMe, matchID: UUID())
        service.sendSelectOutcome(.winner)
        service.sendCommitEndingShot(.rally)
        service.sendCancelOutcomeSelection()
        service.sendUndoPoint()
    }

    @Test func deliveredCommandsReportNoFailure() async {
        let session = LiveCommandSession()
        let service = makeService(session)

        sendEveryLiveCommand(through: service)
        await drainMainQueue()

        #expect(session.sent.count == 5)
        #expect(service.liveCommandFailureCount == 0)
    }

    @Test func unreachableCommandsAreDroppedAndReported() async {
        let session = LiveCommandSession()
        session.isReachable = false
        let service = makeService(session)

        sendEveryLiveCommand(through: service)
        await drainMainQueue()

        #expect(session.sent.isEmpty)
        #expect(session.queued.isEmpty, "a stale queued command could apply to a later point")
        #expect(service.liveCommandFailureCount == 5)
    }

    @Test func connectionLostDuringSendIsReportedWithoutRetrying() async {
        let session = LiveCommandSession()
        session.failLiveSend = true
        let service = makeService(session)

        service.sendScoreCommand(MatchSyncKey.scoreCommandWinMe, matchID: UUID())
        await drainMainQueue()

        #expect(session.sent.count == 1, "retrying an ambiguous failure could score twice")
        #expect(session.queued.isEmpty)
        #expect(service.liveCommandFailureCount == 1)
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
}
