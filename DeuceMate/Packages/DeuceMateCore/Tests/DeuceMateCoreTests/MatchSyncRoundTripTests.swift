// MatchSyncRoundTripTests.swift — end-to-end watch↔phone wire-flow coverage.
//
// Exercises the real construction code (`MatchSyncPayloadBuilder`, used by both the
// transport and the delegates) through the decode side (`SyncIncomingPayload`), the
// phone merge (`MatchMergePolicy`), and the storage badge (`MatchStorageResolver`).
// This models the actual flow a match takes across the wire rather than asserting
// any single layer in isolation.
import XCTest
@testable import DeuceMateCore

final class MatchSyncRoundTripTests: XCTestCase {

    // MARK: - Helpers

    private func makeRecord(
        id: UUID = UUID(),
        startTime: Date = Date(timeIntervalSince1970: 1_700_000_000),
        endTime: Date? = nil,
        iWon: Bool? = nil,
        statCount: Int = 0
    ) -> MatchRecord {
        MatchRecord(
            id: id,
            startTime: startTime,
            endTime: endTime,
            setScores: [SetScore(gamesMe: 1, gamesOpponent: 0)],
            stats: (0..<statCount).map { _ in
                PointStat(setIndex: 0, server: .me, winner: .me, outcome: .winner, isSecondServe: false)
            },
            iWon: iWon,
            matchType: .singles,
            matchFormat: .standard,
            matchElapsedSeconds: 60,
            setElapsedSeconds: [0: 60]
        )
    }

    private func singleMatch(in events: [SyncIncomingEvent]) -> MatchRecord? {
        for case .singleMatch(let r) in events { return r }
        return nil
    }

    private func history(in events: [SyncIncomingEvent]) -> [MatchRecord]? {
        for case .history(let r) in events { return r }
        return nil
    }

    private func manifest(in events: [SyncIncomingEvent]) -> Set<UUID>? {
        for case .watchManifest(let s) in events { return s }
        return nil
    }

    // MARK: - Checkpoint flow (watch → phone)

    func test_inProgressCheckpoint_decodesAndMergesOntoPhone() throws {
        let record = makeRecord(iWon: nil, statCount: 3)
        let payload = try MatchSyncPayloadBuilder.checkpoint(
            record: record,
            completedClearsActive: false,
            announcement: "Game point."
        )

        // Decode: announcement, then the active-match pointer, then the record.
        let events = SyncIncomingPayload.decode(payload)
        XCTAssertEqual(events, [
            .announcement("Game point."),
            .activeMatchID(record.id),
            .singleMatch(record)
        ])

        // The record that crossed the wire merges onto an empty phone history.
        let decoded = try XCTUnwrap(singleMatch(in: events))
        let phone = MatchMergePolicy.merge(incoming: [decoded], into: [])
        XCTAssertEqual(phone.map(\.id), [record.id])
        XCTAssertNil(phone.first?.iWon)
    }

    func test_completionCheckpoint_replacesInProgressOnPhone() throws {
        let id = UUID()
        // Phone already holds the in-progress checkpoint.
        let inProgress = makeRecord(id: id, iWon: nil, statCount: 3)
        var phone = MatchMergePolicy.merge(incoming: [inProgress], into: [])

        // Watch finalises the match → completion checkpoint clears the active pointer.
        let completed = makeRecord(id: id, endTime: Date(timeIntervalSince1970: 1_700_003_600), iWon: true, statCount: 4)
        let payload = try MatchSyncPayloadBuilder.checkpoint(
            record: completed,
            completedClearsActive: true,
            announcement: nil
        )
        let events = SyncIncomingPayload.decode(payload)
        XCTAssertEqual(events, [.clearActiveMatch, .singleMatch(completed)])

        let decoded = try XCTUnwrap(singleMatch(in: events))
        phone = MatchMergePolicy.merge(incoming: [decoded], into: phone)
        XCTAssertEqual(phone.count, 1)
        XCTAssertEqual(phone.first?.iWon, true, "completed checkpoint must replace the in-progress one")
    }

    // MARK: - Full-history sync

    func test_fullHistorySync_decodesAndMergesDeduped() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let a = makeRecord(startTime: now.addingTimeInterval(-100), endTime: now, iWon: true)
        let b = makeRecord(startTime: now, endTime: now.addingTimeInterval(60), iWon: false)
        let payload = try MatchSyncPayloadBuilder.history([a, b])

        let events = SyncIncomingPayload.decode(payload)
        XCTAssertEqual(events, [.history([a, b])])

        let decoded = try XCTUnwrap(history(in: events))
        // Merge over an existing copy of `a` — dedupes by id and sorts newest-first.
        let merged = MatchMergePolicy.merge(incoming: decoded, into: [a])
        XCTAssertEqual(merged.map(\.id), [b.id, a.id])
    }

    // MARK: - Manifest → badge

    func test_manifest_roundTrips_andDrivesStorageLocation() throws {
        let onWatch = makeRecord(endTime: Date(timeIntervalSince1970: 1_700_000_100), iWon: true)
        let phoneOnly = makeRecord(endTime: Date(timeIntervalSince1970: 1_700_000_200), iWon: false)

        let payload = try MatchSyncPayloadBuilder.watchManifest([onWatch.id])
        let events = SyncIncomingPayload.decode(payload)
        XCTAssertEqual(events, [.watchManifest([onWatch.id])])

        let watchIDs = try XCTUnwrap(manifest(in: events))
        XCTAssertEqual(
            MatchStorageResolver.location(matchID: onWatch.id, onPhone: true, watchIDs: watchIDs),
            .both
        )
        XCTAssertEqual(
            MatchStorageResolver.location(matchID: phoneOnly.id, onPhone: true, watchIDs: watchIDs),
            .phoneOnly
        )
    }

    func test_deleteOnWatch_thenManifest_flipsBadgeToPhoneOnly() throws {
        let a = makeRecord(endTime: Date(timeIntervalSince1970: 1_700_000_100), iWon: true)
        let b = makeRecord(endTime: Date(timeIntervalSince1970: 1_700_000_200), iWon: false)

        // Phone issues the delete command.
        let deletePayload = MatchSyncPayloadBuilder.deleteMatchOnWatch(a.id)
        XCTAssertEqual(SyncIncomingPayload.decode(deletePayload), [.deleteMatchOnWatch(a.id)])

        // Both still on watch → `a` reads as "both".
        let before = try XCTUnwrap(manifest(in: SyncIncomingPayload.decode(
            try MatchSyncPayloadBuilder.watchManifest([a.id, b.id])
        )))
        XCTAssertEqual(MatchStorageResolver.location(matchID: a.id, onPhone: true, watchIDs: before), .both)

        // Watch removed `a` and re-published its manifest → badge flips to phone-only.
        let after = try XCTUnwrap(manifest(in: SyncIncomingPayload.decode(
            try MatchSyncPayloadBuilder.watchManifest([b.id])
        )))
        XCTAssertEqual(MatchStorageResolver.location(matchID: a.id, onPhone: true, watchIDs: after), .phoneOnly)
    }

    // MARK: - Control

    func test_requestFullHistory_roundTrips() {
        let events = SyncIncomingPayload.decode(MatchSyncPayloadBuilder.requestFullHistory())
        XCTAssertEqual(events, [.requestFullHistory])
    }
}
