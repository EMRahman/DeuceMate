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

    func test_completedDraw_replacesInProgressRecord() {
        let id = UUID()
        let existing = makeRecord(id: id, iWon: nil)
        let draw = makeRecord(id: id, endTime: Date(), iWon: nil)

        let result = MatchMergePolicy.resolve(incoming: draw, existing: existing)

        XCTAssertFalse(result.isInProgress)
        XCTAssertNil(result.iWon)
        XCTAssertEqual(result.endTime, draw.endTime)
    }

    func test_inProgressCheckpoint_cannotOverwriteCompletedDraw() {
        let id = UUID()
        let draw = makeRecord(id: id, endTime: Date(), iWon: nil, statCount: 2)
        let checkpoint = makeRecord(id: id, iWon: nil, statCount: 3)

        let result = MatchMergePolicy.resolve(incoming: checkpoint, existing: draw)

        XCTAssertFalse(result.isInProgress)
        XCTAssertEqual(result.stats.count, 2)
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

    func test_merge_equalCompletionTimes_deterministicOrder() {
        let sharedStart = Date(timeIntervalSince1970: 1_000)
        let finish = sharedStart.addingTimeInterval(60)
        let a = makeRecord(startTime: sharedStart, endTime: finish, iWon: true)
        let b = makeRecord(startTime: sharedStart, endTime: finish, iWon: false)

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

// MARK: - Tags merge independently of the body (MATCH_TAGS_PLAN.md §3)

extension MatchMergePolicyTests {

    private typealias F = TagFixtures

    /// THE regression this feature must never reintroduce: the user tags a
    /// finished match on the phone → the watch re-sends its history (Sync Now,
    /// requestFullHistory, ping) with its untagged copy of the SAME match,
    /// which has the same `endTime` → case 4's `>=` picks the incoming body →
    /// the tag must survive.
    func test_regression_equalEndTime_untaggedIncoming_keepsPhoneTags() {
        let id = UUID()
        let tags = F.tags(opponents: [F.player("Alex")], competition: .league, at: 10)
        let phoneCopy = F.record(id: id, iWon: true, tags: tags)
        let watchCopy = F.record(id: id, iWon: true, tags: nil)
        XCTAssertEqual(phoneCopy.endTime, watchCopy.endTime)

        let resolved = MatchMergePolicy.resolve(incoming: watchCopy, existing: phoneCopy)
        XCTAssertEqual(resolved.tags, tags)

        let merged = MatchMergePolicy.merge(incoming: [watchCopy], into: [phoneCopy])
        XCTAssertEqual(merged.first?.tags, tags, "full-history merge path keeps tags too")
    }

    func test_tags_mergeOnEveryReturnPath() {
        let id = UUID()
        let older = F.tags(opponents: [F.player("Alex")], at: 10)
        let newer = F.tags(opponents: [F.player("Jo")], at: 20)
        let live = { (tags: MatchTags?, points: Int) in
            F.record(id: id, end: nil, iWon: nil, tags: tags, stats: F.points(points, won: points))
        }
        let done = { (tags: MatchTags?, end: TimeInterval) in F.record(id: id, end: end, iWon: true, tags: tags) }

        // Case 2: in-progress → completed. Completion body wins; newer local tags survive.
        var r = MatchMergePolicy.resolve(incoming: done(older, 3_600), existing: live(newer, 3))
        XCTAssertFalse(r.isInProgress)
        XCTAssertEqual(r.tags, newer)
        // Case 3: late checkpoint vs completed. Completed body kept; newer incoming tags adopted.
        r = MatchMergePolicy.resolve(incoming: live(newer, 5), existing: done(older, 3_600))
        XCTAssertFalse(r.isInProgress)
        XCTAssertEqual(r.tags, newer)
        // Case 4: both completed, existing body newer; incoming tags newer.
        r = MatchMergePolicy.resolve(incoming: done(newer, 100), existing: done(older, 3_600))
        XCTAssertEqual(r.endTime, F.base.addingTimeInterval(3_600))
        XCTAssertEqual(r.tags, newer)
        // Case 5: both in progress (an undo checkpoint with fewer points).
        r = MatchMergePolicy.resolve(incoming: live(nil, 2), existing: live(newer, 3))
        XCTAssertEqual(r.stats.count, 2, "undo checkpoint still accepted")
        XCTAssertEqual(r.tags, newer, "the live checkpoint's missing tags don't wipe the archive's")
    }

    /// §12.1 "Metadata independence": tag a live checkpoint; score, undo and
    /// completion updates arrive; metadata survives every one.
    func test_scenario_taggedLiveMatch_survivesScoreUndoAndCompletion() {
        let id = UUID()
        let tags = F.tags(opponents: [F.player("Alex")], competition: .friendly, at: 10)
        var phone = F.record(id: id, end: nil, iWon: nil, stats: F.points(3, won: 2)).mergingTags(tags)

        for points in [4, 5, 4] {   // point, point, undo
            let checkpoint = F.record(id: id, end: nil, iWon: nil, stats: F.points(points, won: 2))
            phone = MatchMergePolicy.resolve(incoming: checkpoint, existing: phone)
            XCTAssertEqual(phone.stats.count, points)
            XCTAssertEqual(phone.tags, tags)
        }
        let completion = F.record(id: id, iWon: false, stats: F.points(6, won: 2))
        phone = MatchMergePolicy.resolve(incoming: completion, existing: phone)
        XCTAssertEqual(phone.iWon, false)
        XCTAssertEqual(phone.tags, tags)
    }

    /// The watch's `.singleMatch` handler resolves through the same function:
    /// a phone "Sync to Watch" of a tagged record lands with its tags, and an
    /// older-tag phone push cannot regress the watch's newer tags.
    func test_watchSingleMatchPath_usesTagClock() {
        let id = UUID()
        let newer = F.tags(competition: .league, at: 20)
        let watchHeld = F.record(id: id, tags: newer)
        let pushed = F.record(id: id, tags: F.tags(competition: .practice, at: 5))
        XCTAssertEqual(MatchMergePolicy.resolve(incoming: pushed, existing: watchHeld).tags, newer)
        XCTAssertEqual(MatchMergePolicy.resolve(incoming: watchHeld, existing: nil).tags, newer)
    }

    func test_tags_equalClockConflict_convergesInEitherArrivalOrder() {
        let id = UUID()
        let a = F.record(id: id, tags: F.tags(opponents: [F.player("Alex")], at: 5, revision: F.uuid(1)))
        let b = F.record(id: id, tags: F.tags(opponents: [F.player("Jo")], at: 5, revision: F.uuid(2)))
        XCTAssertEqual(MatchMergePolicy.resolve(incoming: a, existing: b).tags,
                       MatchMergePolicy.resolve(incoming: b, existing: a).tags)
    }

    func test_tags_emptyClear_beatsOlderTagsFromWatch() {
        let id = UUID()
        let original = F.tags(opponents: [F.player("Alex")], at: 10)
        let cleared = MatchTags.cleared(after: original, now: F.base.addingTimeInterval(20))
        let phone = F.record(id: id, tags: cleared)
        let staleWatch = F.record(id: id, tags: original)
        XCTAssertEqual(MatchMergePolicy.resolve(incoming: staleWatch, existing: phone).tags, cleared)
    }
}
