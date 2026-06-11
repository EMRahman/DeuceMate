// SyncIncomingPayloadTests.swift — coverage for the inbound WC payload decoder.
import XCTest
@testable import DeuceMateCore

final class SyncIncomingPayloadTests: XCTestCase {

    private func makeRecord(id: UUID = UUID()) -> MatchRecord {
        MatchRecord(
            id: id,
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: nil,
            setScores: [SetScore(gamesMe: 1, gamesOpponent: 0)],
            stats: [],
            iWon: nil,
            matchType: .singles,
            matchFormat: .standard,
            matchElapsedSeconds: 60,
            setElapsedSeconds: [0: 60]
        )
    }

    // MARK: - Single-key payloads

    func test_decode_requestFullHistory() {
        let events = SyncIncomingPayload.decode([MatchSyncKey.requestFullHistory: true])
        XCTAssertEqual(events, [.requestFullHistory])
    }

    func test_decode_ping() {
        let events = SyncIncomingPayload.decode(["ping": true])
        XCTAssertEqual(events, [.ping])
    }

    func test_decode_announcement() {
        let events = SyncIncomingPayload.decode([MatchSyncKey.liveAnnouncement: "Deuce."])
        XCTAssertEqual(events, [.announcement("Deuce.")])
    }

    func test_decode_iPhoneInputEnabled() {
        let events = SyncIncomingPayload.decode([MatchSyncKey.iPhoneInputEnabled: true])
        XCTAssertEqual(events, [.iPhoneInputEnabled(true)])
    }

    func test_decode_playerName() {
        let events = SyncIncomingPayload.decode([MatchSyncKey.playerName: "Federer"])
        XCTAssertEqual(events, [.playerName("Federer")])
    }

    func test_decode_scoreCommand_withMatchID() {
        let id = UUID()
        let events = SyncIncomingPayload.decode([
            MatchSyncKey.scoreCommand: MatchSyncKey.scoreCommandWinMe,
            MatchSyncKey.scoreCommandMatchID: id.uuidString,
        ])
        XCTAssertEqual(events, [.scoreCommand(command: MatchSyncKey.scoreCommandWinMe, matchID: id)])
    }

    func test_decode_scoreCommand_withoutMatchID_isNil() {
        let events = SyncIncomingPayload.decode([
            MatchSyncKey.scoreCommand: MatchSyncKey.scoreCommandUndo,
        ])
        XCTAssertEqual(events, [.scoreCommand(command: MatchSyncKey.scoreCommandUndo, matchID: nil)])
    }

    func test_decode_scoreCommand_invalidMatchID_isNil() {
        let events = SyncIncomingPayload.decode([
            MatchSyncKey.scoreCommand: MatchSyncKey.scoreCommandWinOpp,
            MatchSyncKey.scoreCommandMatchID: "not-a-uuid",
        ])
        XCTAssertEqual(events, [.scoreCommand(command: MatchSyncKey.scoreCommandWinOpp, matchID: nil)])
    }

    func test_decode_clearActiveMatch() {
        let events = SyncIncomingPayload.decode([MatchSyncKey.clearActiveMatch: true])
        XCTAssertEqual(events, [.clearActiveMatch])
    }

    // MARK: - Watch manifest + delete-on-watch

    func test_decode_watchManifest() throws {
        let a = UUID(), b = UUID()
        let data = try JSONEncoder().encode([a.uuidString, b.uuidString])
        let events = SyncIncomingPayload.decode([MatchSyncKey.watchManifest: data])
        XCTAssertEqual(events, [.watchManifest([a, b])])
    }

    func test_decode_watchManifest_skipsInvalidUUIDs() throws {
        let a = UUID()
        let data = try JSONEncoder().encode([a.uuidString, "not-a-uuid"])
        let events = SyncIncomingPayload.decode([MatchSyncKey.watchManifest: data])
        XCTAssertEqual(events, [.watchManifest([a])])
    }

    func test_decode_watchManifest_corruptData_emitsDecodeError() {
        let events = SyncIncomingPayload.decode([MatchSyncKey.watchManifest: Data([0x00, 0x01])])
        XCTAssertEqual(events.count, 1)
        if case .decodeError(let key, _) = events[0] {
            XCTAssertEqual(key, MatchSyncKey.watchManifest)
        } else {
            XCTFail("expected decodeError, got \(events)")
        }
    }

    func test_decode_deleteMatchOnWatch() {
        let id = UUID()
        let events = SyncIncomingPayload.decode([
            MatchSyncKey.deleteMatchOnWatch: true,
            MatchSyncKey.deleteMatchID: id.uuidString
        ])
        XCTAssertEqual(events, [.deleteMatchOnWatch(id)])
    }

    func test_decode_deleteMatchOnWatch_missingID_isIgnored() {
        let events = SyncIncomingPayload.decode([MatchSyncKey.deleteMatchOnWatch: true])
        XCTAssertTrue(events.isEmpty)
    }

    func test_decode_deleteMatchOnWatch_invalidID_isIgnored() {
        let events = SyncIncomingPayload.decode([
            MatchSyncKey.deleteMatchOnWatch: true,
            MatchSyncKey.deleteMatchID: "not-a-uuid"
        ])
        XCTAssertTrue(events.isEmpty)
    }

    func test_decode_activeMatchID() {
        let id = UUID()
        let events = SyncIncomingPayload.decode([MatchSyncKey.activeMatchID: id.uuidString])
        XCTAssertEqual(events, [.activeMatchID(id)])
    }

    func test_decode_activeMatchID_invalidUUID_isIgnored() {
        let events = SyncIncomingPayload.decode([MatchSyncKey.activeMatchID: "not-a-uuid"])
        XCTAssertTrue(events.isEmpty)
    }

    func test_decode_clearActiveMatch_takesPrecedence_overActiveMatchID() {
        // Watch sends both keys when finalising a match (see MatchSyncTransport.sendRecord).
        // The clear should win so the phone removes its live pointer atomically.
        let events = SyncIncomingPayload.decode([
            MatchSyncKey.clearActiveMatch: true,
            MatchSyncKey.activeMatchID: UUID().uuidString
        ])
        XCTAssertEqual(events, [.clearActiveMatch])
    }

    // MARK: - Record payloads

    func test_decode_singleMatch() throws {
        let record = makeRecord()
        let data = try MatchSyncMessage.encode(record)
        let events = SyncIncomingPayload.decode([MatchSyncKey.singleMatch: data])
        XCTAssertEqual(events, [.singleMatch(record)])
    }

    func test_decode_history() throws {
        let records = [makeRecord(), makeRecord()]
        let data = try MatchSyncMessage.encode(records)
        let events = SyncIncomingPayload.decode([MatchSyncKey.matchHistory: data])
        XCTAssertEqual(events, [.history(records)])
    }

    func test_decode_history_takesPrecedenceOver_singleMatch() throws {
        // A defensive check: if a payload somehow contained both, the bulk
        // history wins so the phone doesn't merge a stale record on top.
        let history = [makeRecord()]
        let single = makeRecord()
        let events = SyncIncomingPayload.decode([
            MatchSyncKey.matchHistory: try MatchSyncMessage.encode(history),
            MatchSyncKey.singleMatch: try MatchSyncMessage.encode(single)
        ])
        XCTAssertEqual(events, [.history(history)])
    }

    func test_decode_corruptSingleMatch_emitsDecodeError() {
        let bogus = Data([0x00, 0x01, 0x02])
        let events = SyncIncomingPayload.decode([MatchSyncKey.singleMatch: bogus])
        XCTAssertEqual(events.count, 1)
        if case .decodeError(let key, _) = events[0] {
            XCTAssertEqual(key, MatchSyncKey.singleMatch)
        } else {
            XCTFail("expected decodeError, got \(events)")
        }
    }

    // MARK: - Combined payloads

    func test_decode_combinedAnnouncementAndCheckpoint_returnsBothInOrder() throws {
        // Watch's checkpoint payload bundles the record, an active-match-id, and
        // an optional announcement. The phone must speak the announcement *and*
        // merge the record.
        let record = makeRecord()
        let payload: [String: Any] = [
            MatchSyncKey.singleMatch: try MatchSyncMessage.encode(record),
            MatchSyncKey.activeMatchID: record.id.uuidString,
            MatchSyncKey.liveAnnouncement: "Game point."
        ]
        let events = SyncIncomingPayload.decode(payload)
        XCTAssertEqual(events, [
            .announcement("Game point."),
            .activeMatchID(record.id),
            .singleMatch(record)
        ])
    }

    func test_decode_emptyPayload_returnsNoEvents() {
        XCTAssertTrue(SyncIncomingPayload.decode([:]).isEmpty)
    }

    // MARK: - File payloads

    func test_decodeFile_history() throws {
        let records = [makeRecord(), makeRecord()]
        let data = try MatchSyncMessage.encode(records)
        let event = SyncIncomingPayload.decodeFile(data: data, key: MatchSyncKey.matchHistory)
        XCTAssertEqual(event, .history(records))
    }

    func test_decodeFile_singleMatch() throws {
        let record = makeRecord()
        let data = try MatchSyncMessage.encode(record)
        let event = SyncIncomingPayload.decodeFile(data: data, key: MatchSyncKey.singleMatch)
        XCTAssertEqual(event, .singleMatch(record))
    }

    func test_decodeFile_unknownKey_returnsDecodeError() {
        let event = SyncIncomingPayload.decodeFile(data: Data(), key: "unknown")
        if case .decodeError(let key, _) = event {
            XCTAssertEqual(key, "unknown")
        } else {
            XCTFail("expected decodeError, got \(event)")
        }
    }

    func test_decodeFile_corruptData_returnsDecodeError() {
        let bogus = Data([0xff, 0xee, 0xdd])
        let event = SyncIncomingPayload.decodeFile(data: bogus, key: MatchSyncKey.matchHistory)
        if case .decodeError(let key, _) = event {
            XCTAssertEqual(key, MatchSyncKey.matchHistory)
        } else {
            XCTFail("expected decodeError, got \(event)")
        }
    }

    // MARK: - Pulse Coach settings

    func test_decode_pulseCoachMaxHR() {
        let events = SyncIncomingPayload.decode([MatchSyncKey.pulseCoachMaxHR: 184])
        XCTAssertEqual(events, [.pulseCoachMaxHR(184)])
    }

    func test_decode_pulseCoachSettingsTogether() {
        let events = SyncIncomingPayload.decode([
            MatchSyncKey.pulseCoachMaxHR: 175
        ])
        XCTAssertTrue(events.contains(.pulseCoachMaxHR(175)))
    }

    func test_decode_userBirthYear() {
        let events = SyncIncomingPayload.decode([MatchSyncKey.userBirthYear: 1985])
        XCTAssertEqual(events, [.userBirthYear(1985)])
    }

    func test_decode_userBirthYearFromHealth() {
        let events = SyncIncomingPayload.decode([MatchSyncKey.userBirthYearFromHealth: true])
        XCTAssertEqual(events, [.userBirthYearFromHealth(true)])
    }

    func test_decode_userBirthYearFromHealth_withYear() {
        let events = SyncIncomingPayload.decode([
            MatchSyncKey.userBirthYear: 1985,
            MatchSyncKey.userBirthYearFromHealth: true
        ])
        XCTAssertTrue(events.contains(.userBirthYear(1985)))
        XCTAssertTrue(events.contains(.userBirthYearFromHealth(true)))
    }

    func test_decode_userMaxHROverride() {
        let events = SyncIncomingPayload.decode([MatchSyncKey.userMaxHROverride: 192])
        XCTAssertEqual(events, [.userMaxHROverride(192)])
    }

    func test_decode_pulseCoachAllSettingsTogether() {
        let events = SyncIncomingPayload.decode([
            MatchSyncKey.pulseCoachMaxHR: 188,
            MatchSyncKey.userBirthYear: 1990,
            MatchSyncKey.userMaxHROverride: 0
        ])
        XCTAssertTrue(events.contains(.pulseCoachMaxHR(188)))
        XCTAssertTrue(events.contains(.userBirthYear(1990)))
        XCTAssertTrue(events.contains(.userMaxHROverride(0)))
    }

    // MARK: - Pending-point mirror + stat actions

    private func samplePendingInfo() -> PendingPointInfo {
        PendingPointInfo(
            server: .me,
            winner: .opponent,
            setIndex: 0,
            isSecondServe: true,
            isBreakPoint: false,
            gameScoreAtStart: GameScoreSnapshot(server: 1, returner: 2, isTiebreak: false)
        )
    }

    func test_decode_pendingPoint_withOutcome() throws {
        let info = samplePendingInfo()
        let data = try JSONEncoder().encode(info)
        let events = SyncIncomingPayload.decode([
            MatchSyncKey.pendingPoint: data,
            MatchSyncKey.pendingPointOutcome: PointOutcome.winner.rawValue
        ])
        XCTAssertTrue(events.contains(.pendingPoint(info)))
        XCTAssertTrue(events.contains(.pendingPointOutcome(.winner)))
    }

    func test_decode_pendingPoint_emptyOutcomeMeansPhaseOne() throws {
        let info = samplePendingInfo()
        let data = try JSONEncoder().encode(info)
        let events = SyncIncomingPayload.decode([
            MatchSyncKey.pendingPoint: data,
            MatchSyncKey.pendingPointOutcome: ""
        ])
        XCTAssertTrue(events.contains(.pendingPoint(info)))
        XCTAssertTrue(events.contains(.pendingPointOutcome(nil)))
    }

    func test_decode_clearPendingPoint_takesPrecedence_overPendingPoint() throws {
        let info = samplePendingInfo()
        let data = try JSONEncoder().encode(info)
        let events = SyncIncomingPayload.decode([
            MatchSyncKey.pendingPoint: data,
            MatchSyncKey.clearPendingPoint: true
        ])
        XCTAssertTrue(events.contains(.clearPendingPoint))
        XCTAssertFalse(events.contains(.pendingPoint(info)))
    }

    func test_decode_statAction_selectOutcome() {
        let events = SyncIncomingPayload.decode([
            MatchSyncKey.statAction: MatchSyncKey.statActionSelectOutcome,
            MatchSyncKey.statActionOutcome: PointOutcome.unforcedError.rawValue
        ])
        XCTAssertEqual(events, [.statAction(
            action: MatchSyncKey.statActionSelectOutcome,
            outcome: .unforcedError,
            endingShot: nil
        )])
    }

    func test_decode_statAction_commitEndingShot() {
        let events = SyncIncomingPayload.decode([
            MatchSyncKey.statAction: MatchSyncKey.statActionCommitEndingShot,
            MatchSyncKey.statActionEndingShot: EndingShot.rally.rawValue
        ])
        XCTAssertEqual(events, [.statAction(
            action: MatchSyncKey.statActionCommitEndingShot,
            outcome: nil,
            endingShot: .rally
        )])
    }

    func test_decode_statAction_cancelOutcomeSelection() {
        let events = SyncIncomingPayload.decode([
            MatchSyncKey.statAction: MatchSyncKey.statActionCancelOutcomeSelection
        ])
        XCTAssertEqual(events, [.statAction(
            action: MatchSyncKey.statActionCancelOutcomeSelection,
            outcome: nil,
            endingShot: nil
        )])
    }

    func test_decode_statAction_undoPoint() {
        let events = SyncIncomingPayload.decode([
            MatchSyncKey.statAction: MatchSyncKey.statActionUndoPoint
        ])
        XCTAssertEqual(events, [.statAction(
            action: MatchSyncKey.statActionUndoPoint,
            outcome: nil,
            endingShot: nil
        )])
    }
}
