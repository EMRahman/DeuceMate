// MatchMergePolicyTests.swift
import XCTest
@testable import DeuceMateCore

final class MatchMergePolicyTests: XCTestCase {

    // MARK: - Helpers

    private func makeRecord(
        id: UUID = UUID(),
        startTime: Date = Date(),
        endTime: Date? = nil,
        iWon: Bool? = nil,
        statCount: Int = 0
    ) -> MatchRecord {
        MatchRecord(
            id: id,
            startTime: startTime,
            endTime: endTime,
            setScores: [],
            stats: (0..<statCount).map { _ in
                PointStat(
                    setIndex: 0,
                    server: .me,
                    winner: .me,
                    outcome: .winner,
                    isSecondServe: false
                )
            },
            iWon: iWon
        )
    }

    // MARK: - resolve tests

    func test_newId_insertsRecord() {
        let incoming = makeRecord()
        let result = MatchMergePolicy.resolve(incoming: incoming, existing: nil)
        XCTAssertEqual(result.id, incoming.id)
    }

    func test_inProgressToCompleted_replacesRecord() {
        let id = UUID()
        let existing = makeRecord(id: id, iWon: nil)
        let incoming = makeRecord(id: id, endTime: Date(), iWon: true)
        let result = MatchMergePolicy.resolve(incoming: incoming, existing: existing)
        XCTAssertEqual(result.iWon, true)
    }

    func test_bothCompleted_incomingNewer_replacesRecord() {
        let id = UUID()
        let old = Date(timeIntervalSinceNow: -100)
        let new = Date()
        let existing = makeRecord(id: id, endTime: old, iWon: false)
        let incoming = makeRecord(id: id, endTime: new, iWon: true)
        let result = MatchMergePolicy.resolve(incoming: incoming, existing: existing)
        XCTAssertEqual(result.iWon, true)
    }

    func test_bothCompleted_incomingOlder_keepsExisting() {
        let id = UUID()
        let old = Date(timeIntervalSinceNow: -100)
        let new = Date()
        let existing = makeRecord(id: id, endTime: new, iWon: false)
        let incoming = makeRecord(id: id, endTime: old, iWon: true)
        let result = MatchMergePolicy.resolve(incoming: incoming, existing: existing)
        XCTAssertEqual(result.iWon, false)
    }

    func test_completedExisting_inProgressIncoming_keepsExisting() {
        let id = UUID()
        let existing = makeRecord(id: id, endTime: Date(), iWon: true)
        let incoming  = makeRecord(id: id, iWon: nil)
        let result = MatchMergePolicy.resolve(incoming: incoming, existing: existing)
        XCTAssertEqual(result.iWon, true)
    }

    func test_completedExisting_inProgressIncomingWithMorePoints_keepsExisting() {
        // A late-arriving in-progress checkpoint with more points than the completed
        // record must NOT downgrade the completed match. Completed is always final.
        let id = UUID()
        let existing = makeRecord(id: id, endTime: Date(), iWon: false, statCount: 5)
        let incoming  = makeRecord(id: id, iWon: nil, statCount: 100)
        let result = MatchMergePolicy.resolve(incoming: incoming, existing: existing)
        XCTAssertEqual(result.iWon, false)
        XCTAssertEqual(result.stats.count, 5)
    }

    func test_bothInProgress_incomingAlwaysWins() {
        // Watch is source of truth; sendMessage delivers in order.
        let id = UUID()
        let existing = makeRecord(id: id, iWon: nil, statCount: 10)
        let incoming  = makeRecord(id: id, iWon: nil, statCount: 5)
        let result = MatchMergePolicy.resolve(incoming: incoming, existing: existing)
        XCTAssertEqual(result.stats.count, 5)
    }

    func test_bothInProgress_undo_incomingFewerStatsThanExisting_incomingWins() {
        // Regression: after an undo the checkpoint has fewer stats. The old
        // "more stats wins" heuristic would discard the reverted state; the
        // phone scoreboard would then not update until the next scored point.
        let id = UUID()
        let existing = makeRecord(id: id, iWon: nil, statCount: 3)
        let incoming  = makeRecord(id: id, iWon: nil, statCount: 2) // after undo
        let result = MatchMergePolicy.resolve(incoming: incoming, existing: existing)
        XCTAssertEqual(result.stats.count, 2)
    }

    // MARK: - merge tests

    func test_merge_tombstone_preventsReimport() {
        let id = UUID()
        let current: [MatchRecord] = []
        let incoming = [makeRecord(id: id, endTime: Date(), iWon: true)]
        let result = MatchMergePolicy.merge(incoming: incoming, into: current, tombstones: [id])
        XCTAssertTrue(result.isEmpty)
    }

    func test_merge_sortsByStartTimeDescending() {
        let now = Date()
        let r1 = makeRecord(startTime: now.addingTimeInterval(-200), endTime: now.addingTimeInterval(-100), iWon: true)
        let r2 = makeRecord(startTime: now.addingTimeInterval(-50),  endTime: now,                          iWon: false)
        let result = MatchMergePolicy.merge(incoming: [r1, r2], into: [])
        XCTAssertEqual(result.first?.id, r2.id)
    }

    func test_merge_backfillsHealthWhenExistingCompletedRecordWins() throws {
        let id = UUID()
        let pointID = UUID()
        let newerEnd = Date(timeIntervalSince1970: 2_000)
        let existing = MatchRecord(
            id: id,
            startTime: Date(timeIntervalSince1970: 1_000),
            endTime: newerEnd,
            setScores: [],
            stats: [PointStat(
                id: pointID,
                setIndex: 0,
                server: .me,
                winner: .me,
                outcome: .winner
            )],
            iWon: true
        )
        let incoming = MatchRecord(
            id: id,
            startTime: existing.startTime,
            endTime: newerEnd.addingTimeInterval(-100),
            setScores: [],
            stats: [PointStat(
                id: pointID,
                setIndex: 0,
                server: .me,
                winner: .me,
                outcome: .winner,
                heartRateBPM: 155,
                stepsCumulative: 42
            )],
            iWon: true,
            totalSteps: 1_234,
            totalDistanceMeters: 3_210,
            totalCaloriesKcal: 456
        )

        let result = try XCTUnwrap(MatchMergePolicy.merge(incoming: [incoming], into: [existing]).first)
        XCTAssertEqual(result.endTime, newerEnd)
        XCTAssertEqual(result.totalSteps, 1_234)
        XCTAssertEqual(result.totalDistanceMeters, 3_210)
        XCTAssertEqual(result.totalCaloriesKcal, 456)
        XCTAssertEqual(result.stats.first?.heartRateBPM, 155)
        XCTAssertEqual(result.stats.first?.stepsCumulative, 42)
    }

    // MARK: - merge edge cases

    func test_merge_emptyIncoming_returnsCurrentUnchanged() {
        let now = Date()
        let a = makeRecord(startTime: now.addingTimeInterval(-100), endTime: now, iWon: true)
        let b = makeRecord(startTime: now.addingTimeInterval(-50),  endTime: now, iWon: false)
        let result = MatchMergePolicy.merge(incoming: [], into: [a, b])
        XCTAssertEqual(Set(result.map(\.id)), Set([a.id, b.id]))
    }

    func test_merge_emptyCurrent_dedupesIncomingById() {
        // Two checkpoints of the same in-progress match; the later one wins.
        let id = UUID()
        let first  = makeRecord(id: id, iWon: nil, statCount: 2)
        let second = makeRecord(id: id, iWon: nil, statCount: 3)
        let result = MatchMergePolicy.merge(incoming: [first, second], into: [])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.stats.count, 3)
    }

    // MARK: - resolve edge cases

    func test_bothInProgress_equalStats_incomingWins() {
        let id = UUID()
        let existing = makeRecord(id: id, iWon: nil, statCount: 4)
        let incoming = makeRecord(id: id, startTime: Date(timeIntervalSince1970: 42), iWon: nil, statCount: 4)
        let result = MatchMergePolicy.resolve(incoming: incoming, existing: existing)
        XCTAssertEqual(result.startTime, incoming.startTime)
    }

    func test_bothCompleted_nilEndTime_fallsBackToStartTime() {
        let id = UUID()
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        // Both completed, both with endTime == nil → comparison falls back to startTime.
        let existing = makeRecord(id: id, startTime: newer, endTime: nil, iWon: false)
        let incoming = makeRecord(id: id, startTime: older, endTime: nil, iWon: true)
        let result = MatchMergePolicy.resolve(incoming: incoming, existing: existing)
        XCTAssertEqual(result.iWon, false, "older-startTime incoming must not replace the newer existing")

        let result2 = MatchMergePolicy.resolve(incoming: existing, existing: incoming)
        XCTAssertEqual(result2.iWon, false, "newer-startTime incoming wins")
    }

    // MARK: - merge ordering

    func test_merge_equalStartTimes_deterministicOrder() {
        let sharedStart = Date(timeIntervalSince1970: 1_000)
        let a = makeRecord(startTime: sharedStart, endTime: Date(), iWon: true)
        let b = makeRecord(startTime: sharedStart, endTime: Date(), iWon: false)

        let firstPass = MatchMergePolicy.merge(incoming: [a, b], into: [])
        let secondPass = MatchMergePolicy.merge(incoming: [b, a], into: [])
        XCTAssertEqual(
            firstPass.map(\.id), secondPass.map(\.id),
            "equal start times must sort identically regardless of input order"
        )
        XCTAssertEqual(
            firstPass.map(\.id),
            firstPass.map(\.id).sorted { $0.uuidString < $1.uuidString },
            "id is the documented tiebreak"
        )
    }
}
