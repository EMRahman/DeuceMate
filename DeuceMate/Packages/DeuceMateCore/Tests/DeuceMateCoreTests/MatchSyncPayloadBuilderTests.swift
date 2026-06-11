// MatchSyncPayloadBuilderTests.swift — asserts the exact wire-payload shapes.
//
// Complements MatchSyncRoundTripTests (which proves builder→decode symmetry) by
// pinning the dictionary contents directly, so a regression in key selection is
// caught even if the decoder changed in a compensating way.
import XCTest
@testable import DeuceMateCore

final class MatchSyncPayloadBuilderTests: XCTestCase {

    private func makeRecord(id: UUID = UUID(), iWon: Bool? = nil, endTime: Date? = nil) -> MatchRecord {
        MatchRecord(
            id: id,
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: endTime,
            setScores: [SetScore(gamesMe: 1, gamesOpponent: 0)],
            stats: [],
            iWon: iWon,
            matchType: .singles,
            matchFormat: .standard,
            matchElapsedSeconds: 60,
            setElapsedSeconds: [0: 60]
        )
    }

    // MARK: - Checkpoint

    func test_inProgressCheckpoint_carriesActiveMatchID_noClear() throws {
        let record = makeRecord(iWon: nil)
        let payload = try MatchSyncPayloadBuilder.checkpoint(
            record: record, completedClearsActive: false, announcement: nil
        )
        XCTAssertNotNil(payload[MatchSyncKey.singleMatch] as? Data)
        XCTAssertEqual(payload[MatchSyncKey.activeMatchID] as? String, record.id.uuidString)
        XCTAssertNil(payload[MatchSyncKey.clearActiveMatch])
        XCTAssertNil(payload[MatchSyncKey.liveAnnouncement])
    }

    func test_completedCheckpoint_carriesClear_noActiveMatchID() throws {
        let record = makeRecord(iWon: true, endTime: Date(timeIntervalSince1970: 1_700_003_600))
        let payload = try MatchSyncPayloadBuilder.checkpoint(
            record: record, completedClearsActive: true, announcement: nil
        )
        XCTAssertEqual(payload[MatchSyncKey.clearActiveMatch] as? Bool, true)
        XCTAssertNil(payload[MatchSyncKey.activeMatchID])
    }

    func test_checkpoint_includesAnnouncementOnlyWhenPresent() throws {
        let record = makeRecord(iWon: nil)
        let withAnn = try MatchSyncPayloadBuilder.checkpoint(
            record: record, completedClearsActive: false, announcement: "Deuce."
        )
        XCTAssertEqual(withAnn[MatchSyncKey.liveAnnouncement] as? String, "Deuce.")

        let withoutAnn = try MatchSyncPayloadBuilder.checkpoint(
            record: record, completedClearsActive: false, announcement: nil
        )
        XCTAssertNil(withoutAnn[MatchSyncKey.liveAnnouncement])
    }

    // MARK: - Manifest / delete / control

    func test_watchManifest_encodesIDStrings() throws {
        let a = UUID(), b = UUID()
        let payload = try MatchSyncPayloadBuilder.watchManifest([a, b])
        let data = try XCTUnwrap(payload[MatchSyncKey.watchManifest] as? Data)
        let decoded = try JSONDecoder().decode([String].self, from: data)
        XCTAssertEqual(decoded, [a.uuidString, b.uuidString])
    }

    func test_deleteMatchOnWatch_carriesBothKeys() {
        let id = UUID()
        let payload = MatchSyncPayloadBuilder.deleteMatchOnWatch(id)
        XCTAssertEqual(payload[MatchSyncKey.deleteMatchOnWatch] as? Bool, true)
        XCTAssertEqual(payload[MatchSyncKey.deleteMatchID] as? String, id.uuidString)
    }

    func test_requestFullHistory_payload() {
        let payload = MatchSyncPayloadBuilder.requestFullHistory()
        XCTAssertEqual(payload[MatchSyncKey.requestFullHistory] as? Bool, true)
    }

    func test_singleRecordPayload_andHistoryPayload_useExpectedKeys() throws {
        let record = makeRecord(iWon: true, endTime: Date(timeIntervalSince1970: 1_700_003_600))
        XCTAssertNotNil(try MatchSyncPayloadBuilder.singleRecord(record)[MatchSyncKey.singleMatch] as? Data)
        XCTAssertNotNil(try MatchSyncPayloadBuilder.history([record])[MatchSyncKey.matchHistory] as? Data)
    }
}
