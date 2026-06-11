// MatchSyncTransportTests.swift — exercises the reachability- and size-gated
// routing in MatchSyncTransport with a fake session.
//
// The transport's only branching logic — when to use sendMessage vs queue via
// userInfo vs spill to a file, and how each error/unreachable path falls back —
// is otherwise unreachable from package tests because the production transport
// talks to WCSession (unavailable on macOS). Injecting a `MatchSyncSessing`
// fake lets us assert exactly which path each call takes.
import XCTest
@testable import DeuceMateCore

/// In-memory stand-in for WCSession. Records every routed call and lets a test
/// dictate reachability/activation and whether a live send "fails".
private final class FakeSyncSession: MatchSyncSessing {
    var isActivated = true
    var isReachable = true
    /// When true, a `sendMessage` invoked while reachable invokes its
    /// errorHandler (simulating a delivery failure) instead of the replyHandler.
    var failLiveSend = false
    var liveSendError: Error = NSError(domain: "test.sync", code: 7)

    private(set) var sentMessages: [[String: Any]] = []
    private(set) var queuedUserInfos: [[String: Any]] = []
    private(set) var transferredFiles: [(url: URL, metadata: [String: Any]?)] = []

    func sendMessage(_ message: [String: Any],
                     replyHandler: (([String: Any]) -> Void)?,
                     errorHandler: ((Error) -> Void)?) {
        sentMessages.append(message)
        if failLiveSend {
            errorHandler?(liveSendError)
        } else {
            replyHandler?([:])
        }
    }

    func queueUserInfo(_ userInfo: [String: Any]) {
        queuedUserInfos.append(userInfo)
    }

    func transferFile(at url: URL, metadata: [String: Any]?) {
        transferredFiles.append((url, metadata))
    }
}

final class MatchSyncTransportTests: XCTestCase {

    private func makeRecord(id: UUID = UUID(), iWon: Bool? = nil) -> MatchRecord {
        MatchRecord(
            id: id,
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            setScores: [SetScore(gamesMe: 1, gamesOpponent: 0)],
            stats: [],
            iWon: iWon
        )
    }

    /// Builds a history large enough to cross `matchSyncUserInfoSizeLimit` so the
    /// file-transfer branch is exercised deterministically.
    private func makeOversizedHistory() throws -> [MatchRecord] {
        var records: [MatchRecord] = []
        var index = 0
        repeat {
            let stats = (0..<60).map { _ in
                PointStat(setIndex: 0, server: .me, winner: .me, outcome: .winner, isSecondServe: false)
            }
            records.append(makeRecord(id: UUID(), iWon: true))
            records[records.count - 1].stats = stats
            index += 1
        } while try MatchSyncMessage.encode(records).count <= matchSyncUserInfoSizeLimit && index < 200
        return records
    }

    // MARK: - sendRecord (live checkpoint)

    func test_sendRecord_reachable_sendsCheckpointMessage() {
        let fake = FakeSyncSession()
        let transport = MatchSyncTransport(session: fake)
        let record = makeRecord()

        transport.sendRecord(record, completedClearsActive: false, announcement: nil)

        XCTAssertEqual(fake.sentMessages.count, 1)
        XCTAssertNotNil(fake.sentMessages.first?[MatchSyncKey.singleMatch] as? Data)
        XCTAssertEqual(fake.sentMessages.first?[MatchSyncKey.activeMatchID] as? String, record.id.uuidString)
        XCTAssertTrue(fake.queuedUserInfos.isEmpty)
    }

    func test_sendRecord_reachableButSendFails_queuesAnnouncementOnly() {
        let fake = FakeSyncSession()
        fake.failLiveSend = true
        let transport = MatchSyncTransport(session: fake)

        transport.sendRecord(makeRecord(), completedClearsActive: false, announcement: "Deuce.")

        XCTAssertEqual(fake.sentMessages.count, 1)               // attempted live send
        XCTAssertEqual(fake.queuedUserInfos.count, 1)            // announcement fell back
        XCTAssertEqual(fake.queuedUserInfos.first?[MatchSyncKey.liveAnnouncement] as? String, "Deuce.")
    }

    func test_sendRecord_unreachable_queuesAnnouncementButDropsCheckpoint() {
        let fake = FakeSyncSession()
        fake.isReachable = false
        let transport = MatchSyncTransport(session: fake)

        transport.sendRecord(makeRecord(), completedClearsActive: false, announcement: "Game.")

        XCTAssertTrue(fake.sentMessages.isEmpty)                 // checkpoint silently dropped
        XCTAssertEqual(fake.queuedUserInfos.count, 1)
        XCTAssertEqual(fake.queuedUserInfos.first?[MatchSyncKey.liveAnnouncement] as? String, "Game.")
    }

    func test_sendRecord_unreachableWithoutAnnouncement_isSilentDrop() {
        let fake = FakeSyncSession()
        fake.isReachable = false
        let transport = MatchSyncTransport(session: fake)

        transport.sendRecord(makeRecord(), completedClearsActive: false, announcement: nil)

        XCTAssertTrue(fake.sentMessages.isEmpty)
        XCTAssertTrue(fake.queuedUserInfos.isEmpty)
    }

    func test_sendRecord_notActivated_doesNothing() {
        let fake = FakeSyncSession()
        fake.isActivated = false
        let transport = MatchSyncTransport(session: fake)

        transport.sendRecord(makeRecord(), completedClearsActive: false, announcement: "x")

        XCTAssertTrue(fake.sentMessages.isEmpty)
        XCTAssertTrue(fake.queuedUserInfos.isEmpty)
    }

    // MARK: - sendRecordReliable (size-gated)

    func test_sendRecordReliable_reachable_sendsMessage() {
        let fake = FakeSyncSession()
        let transport = MatchSyncTransport(session: fake)

        transport.sendRecordReliable(makeRecord())

        XCTAssertEqual(fake.sentMessages.count, 1)
        XCTAssertTrue(fake.queuedUserInfos.isEmpty)
        XCTAssertTrue(fake.transferredFiles.isEmpty)
    }

    func test_sendRecordReliable_unreachableSmall_queuesUserInfo() {
        let fake = FakeSyncSession()
        fake.isReachable = false
        let transport = MatchSyncTransport(session: fake)

        transport.sendRecordReliable(makeRecord())

        XCTAssertTrue(fake.sentMessages.isEmpty)
        XCTAssertEqual(fake.queuedUserInfos.count, 1)
        XCTAssertNotNil(fake.queuedUserInfos.first?[MatchSyncKey.singleMatch] as? Data)
        XCTAssertTrue(fake.transferredFiles.isEmpty)
    }

    func test_sendRecordReliable_reachableButFails_fallsBackToUserInfo() {
        let fake = FakeSyncSession()
        fake.failLiveSend = true
        let transport = MatchSyncTransport(session: fake)

        transport.sendRecordReliable(makeRecord())

        XCTAssertEqual(fake.sentMessages.count, 1)
        XCTAssertEqual(fake.queuedUserInfos.count, 1)
    }

    // MARK: - sendHistory (size-gated)

    func test_sendHistory_empty_doesNothing() {
        let fake = FakeSyncSession()
        let transport = MatchSyncTransport(session: fake)

        transport.sendHistory([])

        XCTAssertTrue(fake.sentMessages.isEmpty)
        XCTAssertTrue(fake.queuedUserInfos.isEmpty)
        XCTAssertTrue(fake.transferredFiles.isEmpty)
    }

    func test_sendHistory_small_queuesUserInfo() {
        let fake = FakeSyncSession()
        let transport = MatchSyncTransport(session: fake)

        transport.sendHistory([makeRecord(iWon: true)])

        XCTAssertEqual(fake.queuedUserInfos.count, 1)
        XCTAssertNotNil(fake.queuedUserInfos.first?[MatchSyncKey.matchHistory] as? Data)
        XCTAssertTrue(fake.transferredFiles.isEmpty)
    }

    func test_sendHistory_oversized_spillsToFileTransfer() throws {
        let fake = FakeSyncSession()
        let transport = MatchSyncTransport(session: fake)
        let history = try makeOversizedHistory()

        transport.sendHistory(history)

        XCTAssertTrue(fake.queuedUserInfos.isEmpty)
        XCTAssertEqual(fake.transferredFiles.count, 1)
        XCTAssertEqual(fake.transferredFiles.first?.metadata?["key"] as? String, MatchSyncKey.matchHistory)
    }

    // MARK: - sendControl

    func test_sendControl_reachable_sendsMessage() {
        let fake = FakeSyncSession()
        let transport = MatchSyncTransport(session: fake)

        transport.sendControl(MatchSyncPayloadBuilder.requestFullHistory(), queueOnFailure: true)

        XCTAssertEqual(fake.sentMessages.count, 1)
        XCTAssertTrue(fake.queuedUserInfos.isEmpty)
    }

    func test_sendControl_failWithQueueOnFailure_queues() {
        let fake = FakeSyncSession()
        fake.failLiveSend = true
        let transport = MatchSyncTransport(session: fake)

        transport.sendControl(MatchSyncPayloadBuilder.requestFullHistory(), queueOnFailure: true)

        XCTAssertEqual(fake.queuedUserInfos.count, 1)
    }

    func test_sendControl_failWithoutQueueOnFailure_doesNotQueue() {
        let fake = FakeSyncSession()
        fake.failLiveSend = true
        let transport = MatchSyncTransport(session: fake)

        transport.sendControl(MatchSyncPayloadBuilder.requestFullHistory(), queueOnFailure: false)

        XCTAssertTrue(fake.queuedUserInfos.isEmpty)
    }

    func test_sendControl_unreachableWithQueueOnFailure_queues() {
        let fake = FakeSyncSession()
        fake.isReachable = false
        let transport = MatchSyncTransport(session: fake)

        transport.sendControl(MatchSyncPayloadBuilder.requestFullHistory(), queueOnFailure: true)

        XCTAssertTrue(fake.sentMessages.isEmpty)
        XCTAssertEqual(fake.queuedUserInfos.count, 1)
    }

    // MARK: - sendAnnouncement

    func test_sendAnnouncement_reachable_reportsAcknowledged() {
        let fake = FakeSyncSession()
        let transport = MatchSyncTransport(session: fake)
        var ack: Bool?

        transport.sendAnnouncement("Ad in.") { ack = $0 }

        XCTAssertEqual(ack, true)
        XCTAssertEqual(fake.sentMessages.count, 1)
        XCTAssertTrue(fake.queuedUserInfos.isEmpty)
    }

    func test_sendAnnouncement_reachableButFails_queuesAndReportsFalse() {
        let fake = FakeSyncSession()
        fake.failLiveSend = true
        let transport = MatchSyncTransport(session: fake)
        var ack: Bool?

        transport.sendAnnouncement("Ad in.") { ack = $0 }

        XCTAssertEqual(ack, false)
        XCTAssertEqual(fake.queuedUserInfos.count, 1)
        XCTAssertEqual(fake.queuedUserInfos.first?[MatchSyncKey.liveAnnouncement] as? String, "Ad in.")
    }

    func test_sendAnnouncement_unreachable_queuesAndReportsFalse() {
        let fake = FakeSyncSession()
        fake.isReachable = false
        let transport = MatchSyncTransport(session: fake)
        var ack: Bool?

        transport.sendAnnouncement("Game.") { ack = $0 }

        XCTAssertEqual(ack, false)
        XCTAssertTrue(fake.sentMessages.isEmpty)
        XCTAssertEqual(fake.queuedUserInfos.count, 1)
    }

    func test_sendAnnouncement_notActivated_reportsFalseAndDoesNothing() {
        let fake = FakeSyncSession()
        fake.isActivated = false
        let transport = MatchSyncTransport(session: fake)
        var ack: Bool?

        transport.sendAnnouncement("Game.") { ack = $0 }

        XCTAssertEqual(ack, false)
        XCTAssertTrue(fake.sentMessages.isEmpty)
        XCTAssertTrue(fake.queuedUserInfos.isEmpty)
    }

    // MARK: - ping

    func test_ping_notActivated() {
        let fake = FakeSyncSession()
        fake.isActivated = false
        let transport = MatchSyncTransport(session: fake)
        var result: (Bool, String)?

        transport.ping { result = ($0, $1) }

        XCTAssertEqual(result?.0, false)
        XCTAssertEqual(result?.1, "Session not activated")
    }

    func test_ping_unreachable() {
        let fake = FakeSyncSession()
        fake.isReachable = false
        let transport = MatchSyncTransport(session: fake)
        var result: (Bool, String)?

        transport.ping { result = ($0, $1) }

        XCTAssertEqual(result?.0, false)
        XCTAssertEqual(result?.1, "Peer not reachable")
    }

    func test_ping_reachable_replies() {
        let fake = FakeSyncSession()
        let transport = MatchSyncTransport(session: fake)
        var result: (Bool, String)?

        transport.ping { result = ($0, $1) }

        XCTAssertEqual(result?.0, true)
        XCTAssertEqual(result?.1, "Peer replied")
    }

    func test_ping_reachableButErrors() {
        let fake = FakeSyncSession()
        fake.failLiveSend = true
        let transport = MatchSyncTransport(session: fake)
        var result: (Bool, String)?

        transport.ping { result = ($0, $1) }

        XCTAssertEqual(result?.0, false)
        XCTAssertTrue(result?.1.hasPrefix("Error:") ?? false)
    }
}
