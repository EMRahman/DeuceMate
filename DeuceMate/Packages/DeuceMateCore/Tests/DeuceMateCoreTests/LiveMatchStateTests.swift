import XCTest
@testable import DeuceMateCore

final class LiveMatchStateTests: XCTestCase {
    private final class Session: MatchSyncSessing {
        var isActivated = true
        var isReachable = true
        var reply: [String: Any] = [:]
        var error: Error?
        var sent = 0
        var queued = 0
        func sendMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)?,
                         errorHandler: ((Error) -> Void)?) {
            sent += 1
            if let error { errorHandler?(error) } else { replyHandler?(reply) }
        }
        func queueUserInfo(_ userInfo: [String: Any]) { queued += 1 }
        func transferFile(at url: URL, metadata: [String: Any]?) { queued += 1 }
    }

    func test_liveProjectionHasConstantSizeAndDoesNotCarryArchiveOrHealthData() throws {
        let point = PointStat(setIndex: 0, server: .me, winner: .me, outcome: .winner)
        let record = MatchRecord(startTime: Date(), setScores: [SetScore()],
            stats: Array(repeating: point, count: 2000), currentPointsMe: 2,
            currentServer: .opponent, totalSteps: 9000, totalCaloriesKcal: 700,
            recentPoints: Array(repeating: .me, count: 100))
        let state = LiveMatchState(record: record, inputEnabled: true)
        let reply = LiveMatchReply(state: state, sessionID: UUID(), sequence: 9)
        let payload = try MatchSyncPayloadBuilder.liveReply(reply)
        XCTAssertLessThan(try XCTUnwrap(payload[MatchSyncKey.liveReply] as? Data).count, 4000)
        XCTAssertEqual(state.record?.currentPointsMe, 2)
        XCTAssertEqual(state.record?.currentServer, .opponent)
        XCTAssertEqual(state.record?.recentPoints.count, 8)
        XCTAssertEqual(state.record?.stats, [])
        XCTAssertNil(state.record?.totalSteps)
        XCTAssertNil(state.record?.totalCaloriesKcal)
        XCTAssertEqual(record.stats.count, 2000)
        XCTAssertEqual(SyncIncomingPayload.decode(payload), [.liveState(reply)])
        XCTAssertNil(payload[MatchSyncKey.singleMatch], "a compact state must never enter archive merging")
    }

    func test_requestRoundTripsTheIntendedMatchAndPendingPhase() throws {
        let pending = PendingPointInfo(server: .me, winner: .opponent, setIndex: 1, isSecondServe: true)
        let request = LiveMatchRequest(action: MatchSyncKey.statActionCommitEndingShot, matchID: UUID(),
            endingShot: .rally, pendingPoint: pending, pendingOutcome: .unforcedError)
        let payload = try MatchSyncPayloadBuilder.liveRequest(request)
        let data = try XCTUnwrap(payload[MatchSyncKey.liveRequest] as? Data)
        XCTAssertEqual(try JSONDecoder().decode(LiveMatchRequest.self, from: data), request)
    }

    func test_idleAndUnreadableAreDifferentReplies() throws {
        let idle = LiveMatchReply(state: LiveMatchState(record: nil, inputEnabled: true))
        let unavailable = LiveMatchReply(state: nil, message: "Cannot read saved state")
        XCTAssertNotEqual(idle, unavailable)
        XCTAssertNotNil(idle.state)
        XCTAssertNil(idle.state?.record)
        XCTAssertNil(unavailable.state)
    }

    func test_transportRequiresAnApplicationReplyAndNeverQueuesOrRetries() throws {
        let session = Session(), transport = MatchSyncTransport(session: Session())
        var success = false
        transport.requestLiveState(LiveMatchRequest()) { result in
            if case .success = result { success = true }
        }
        XCTAssertFalse(success, "a blank transport acknowledgement cannot confirm the score")
        session.error = NSError(domain: "lost", code: 1)
        var failed = false
        MatchSyncTransport(session: session).requestLiveState(LiveMatchRequest(action: "winMe")) {
            if case .failure = $0 { failed = true }
        }
        XCTAssertTrue(failed)
        XCTAssertEqual(session.sent, 1)
        XCTAssertEqual(session.queued, 0)
        session.isReachable = false
        MatchSyncTransport(session: session).requestLiveState(LiveMatchRequest()) { _ in }
        XCTAssertEqual(session.sent, 1)
        XCTAssertEqual(session.queued, 0)
    }

    func test_transportReturnsAuthoritativeStateAndRejectsFutureReplyVersions() throws {
        let session = Session()
        let reply = LiveMatchReply(state: LiveMatchState(record: nil, inputEnabled: false), sessionID: UUID(), sequence: 4)
        session.reply = try MatchSyncPayloadBuilder.liveReply(reply)
        var received: LiveMatchReply?
        MatchSyncTransport(session: session).requestLiveState(LiveMatchRequest()) {
            if case .success(let value) = $0 { received = value }
        }
        XCTAssertEqual(received, reply)
        let data = try XCTUnwrap(session.reply[MatchSyncKey.liveReply] as? Data)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["version"] = 2
        session.reply[MatchSyncKey.liveReply] = try JSONSerialization.data(withJSONObject: json)
        var failed = false
        MatchSyncTransport(session: session).requestLiveState(LiveMatchRequest()) {
            if case .failure = $0 { failed = true }
        }
        XCTAssertTrue(failed)
        guard case .decodeError = SyncIncomingPayload.decode(session.reply).first else {
            return XCTFail("future pushes must not update the board")
        }
    }

    func test_readinessAndCommandWaitGateAllInput() {
        let syncing = LiveScoreboardStatus(isWatchReachable: true, isInputEnabled: true,
                                          isStateConfirmed: false, isRequestInFlight: true)
        XCTAssertEqual(syncing.badgeLabel, "SYNCING WITH WATCH")
        XCTAssertFalse(syncing.acceptsInput)
        XCTAssertFalse(syncing.showsSwipeHint)
        let sending = LiveScoreboardStatus(isWatchReachable: true, isInputEnabled: true, isRequestInFlight: true)
        XCTAssertEqual(sending.badgeLabel, "SENDING TO WATCH")
        XCTAssertFalse(sending.acceptsInput)
        let blocked = LiveScoreboardStatus(isWatchReachable: true, isInputEnabled: true, blockingReason: "Continue on Watch")
        XCTAssertFalse(blocked.acceptsInput)
        XCTAssertEqual(blocked.detail, "Continue on Watch")
    }

    // MARK: - Watch prompts

    func test_promptAnswers_matchTheWatchButtonsInOrder() {
        let changeover = LiveWatchPrompt.changeover(symbol: "🔁 🎾", reason: "Even games – balls change ends")
        XCTAssertEqual(changeover.kind, .changeover)
        XCTAssertEqual(changeover.title, "🔁 🎾")
        XCTAssertEqual(changeover.detail, "Even games – balls change ends")
        XCTAssertEqual(changeover.answers.map(\.label), ["OK"])
        XCTAssertEqual(changeover.answers.map(\.action), [MatchSyncKey.promptActionAcknowledgeChangeover])

        let doubles = LiveWatchPrompt.doublesServer
        XCTAssertEqual(doubles.kind, .doublesServer)
        XCTAssertEqual(doubles.title, "Who serves next?")
        XCTAssertEqual(doubles.answers.map(\.label), ["Me", "Partner"])
        XCTAssertEqual(doubles.answers.map(\.doublesServer), [.me, .partner])
        XCTAssertTrue(doubles.answers.allSatisfy { $0.action == MatchSyncKey.promptActionChooseDoublesServer })
    }

    func test_promptAnswerRequest_carriesThePromptItAnswers() throws {
        let id = UUID()
        let prompt = LiveWatchPrompt.doublesServer
        let partner = try XCTUnwrap(prompt.answers.last)
        let request = prompt.request(for: partner, matchID: id)
        XCTAssertEqual(request.action, MatchSyncKey.promptActionChooseDoublesServer)
        XCTAssertEqual(request.matchID, id)
        XCTAssertEqual(request.prompt, prompt)
        XCTAssertEqual(request.doublesServer, .partner)
        let payload = try MatchSyncPayloadBuilder.liveRequest(request)
        let data = try XCTUnwrap(payload[MatchSyncKey.liveRequest] as? Data)
        XCTAssertEqual(try JSONDecoder().decode(LiveMatchRequest.self, from: data), request)
    }

    func test_promptWireKeys_arePinned() {
        // A Watch and iPhone on different builds must agree on these strings.
        XCTAssertEqual(MatchSyncKey.promptActionAcknowledgeChangeover, "acknowledgeChangeover")
        XCTAssertEqual(MatchSyncKey.promptActionChooseDoublesServer, "chooseDoublesServer")
        XCTAssertEqual(LiveWatchPrompt.Kind.changeover.rawValue, "changeover")
        XCTAssertEqual(LiveWatchPrompt.Kind.doublesServer.rawValue, "doublesServer")
    }

    func test_promptRoundTripsInTheLiveReply() throws {
        let record = MatchRecord(startTime: Date(), setScores: [SetScore()], stats: [])
        let prompt = LiveWatchPrompt.changeover(symbol: "🔁 👥", reason: "Odd games – players change ends")
            .occurring(UUID())
        let reply = LiveMatchReply(state: LiveMatchState(record: record, inputEnabled: true,
            blockingReason: "Continue on the Watch before scoring.", prompt: prompt),
            sessionID: UUID(), sequence: 3)
        let payload = try MatchSyncPayloadBuilder.liveReply(reply)
        XCTAssertEqual(SyncIncomingPayload.decode(payload), [.liveState(reply)])
        XCTAssertEqual(reply.state?.prompt, prompt)
    }

    func test_idleStateNeverCarriesAPrompt() {
        let state = LiveMatchState(record: nil, inputEnabled: true, prompt: .doublesServer)
        XCTAssertNil(state.prompt)
    }

    func test_olderWatchStateWithoutPrompt_stillDecodes() throws {
        let record = MatchRecord(startTime: Date(), setScores: [SetScore()], stats: [])
        let state = LiveMatchState(record: record, inputEnabled: true,
                                   blockingReason: "Continue on the Watch before scoring.")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        json.removeValue(forKey: "prompt")
        let decoded = try JSONDecoder().decode(LiveMatchState.self,
                                               from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.prompt)
        XCTAssertEqual(decoded.blockingReason, "Continue on the Watch before scoring.")
    }

    func test_olderPhoneRequestWithoutPromptFields_stillDecodes() throws {
        let json = #"{"action":"winMe","matchID":"\#(UUID().uuidString)"}"#
        let request = try JSONDecoder().decode(LiveMatchRequest.self, from: Data(json.utf8))
        XCTAssertEqual(request.action, MatchSyncKey.scoreCommandWinMe)
        XCTAssertNil(request.prompt)
        XCTAssertNil(request.doublesServer)
    }

    func test_sameWordsOnADifferentAppearance_isADifferentPrompt() throws {
        let words = LiveWatchPrompt.changeover(symbol: "🔁 👥", reason: "Odd games – players change ends")
        let first = words.occurring(UUID()), later = words.occurring(UUID())
        XCTAssertNotEqual(first, later, "A late answer to the first must not match the later one")
        XCTAssertEqual(first.title, later.title)
        XCTAssertEqual(first.detail, later.detail)

        let request = first.request(for: first.answers[0], matchID: UUID())
        let decoded = try JSONDecoder().decode(LiveMatchRequest.self, from: JSONEncoder().encode(request))
        XCTAssertEqual(decoded.prompt?.occurrence, first.occurrence, "The answer names the appearance it saw")
        XCTAssertNotEqual(decoded.prompt, later)
    }

    func test_promptWithoutOccurrence_stillDecodes() throws {
        let json = #"{"kindRaw":"changeover","title":"🔁 🎾","detail":"Even games – balls change ends"}"#
        let prompt = try JSONDecoder().decode(LiveWatchPrompt.self, from: Data(json.utf8))
        XCTAssertNil(prompt.occurrence)
        XCTAssertEqual(prompt.kind, .changeover)
    }

    func test_newerPromptKind_decodesWithoutAnswers() throws {
        let json = #"{"kindRaw":"medicalTimeout","title":"Timeout"}"#
        let prompt = try JSONDecoder().decode(LiveWatchPrompt.self, from: Data(json.utf8))
        XCTAssertNil(prompt.kind)
        XCTAssertNil(prompt.detail)
        XCTAssertTrue(prompt.answers.isEmpty, "Never guess an answer to an unknown screen")
    }
}
