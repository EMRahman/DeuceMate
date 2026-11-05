// WatchHistoryPushTests.swift
import XCTest
@testable import DeuceMateCore

final class WatchHistoryPushTests: XCTestCase {

    private func inProgress(id: UUID = UUID()) -> MatchRecord {
        MatchRecord(id: id, startTime: Date(timeIntervalSince1970: 1_000), setScores: [SetScore()], stats: [])
    }

    private func completed(id: UUID = UUID()) -> MatchRecord {
        MatchRecord(id: id, startTime: Date(timeIntervalSince1970: 1_000),
                    endTime: Date(timeIntervalSince1970: 2_000), setScores: [SetScore()], stats: [], iWon: true)
    }

    func test_noLiveMatch_keepsEveryRecordInOrder() {
        let records = [inProgress(), completed(), inProgress()]
        XCTAssertEqual(WatchHistory.recordsForPush(records, liveMatchID: nil), records)
    }

    func test_dropsTheLiveMatchsInProgressCopy() {
        let live = inProgress(), other = inProgress(), finished = completed()
        XCTAssertEqual(
            WatchHistory.recordsForPush([other, live, finished], liveMatchID: live.id),
            [other, finished]
        )
    }

    func test_keepsACompletedCopyOfTheLiveMatch() {
        let copy = completed()
        XCTAssertEqual(WatchHistory.recordsForPush([copy], liveMatchID: copy.id), [copy])
    }

    func test_liveMatchNotStored_changesNothing() {
        let records = [inProgress(), completed()]
        XCTAssertEqual(WatchHistory.recordsForPush(records, liveMatchID: UUID()), records)
    }

    func test_liveMatchIsTheOnlyRecord_returnsEmpty() {
        let live = inProgress()
        XCTAssertTrue(WatchHistory.recordsForPush([live], liveMatchID: live.id).isEmpty)
    }

    /// Why the filter exists: without it, this merge is what reverts the phone.
    func test_theDroppedCopyWouldHaveOverwrittenANewerCheckpoint() {
        let id = UUID()
        var newer = inProgress(id: id)
        newer.currentPointsMe = 3
        let stale = inProgress(id: id)
        let merged = MatchMergePolicy.merge(incoming: [stale], into: [newer])
        XCTAssertEqual(merged.first?.currentPointsMe, 0)

        let filtered = WatchHistory.recordsForPush([stale], liveMatchID: id)
        XCTAssertEqual(MatchMergePolicy.merge(incoming: filtered, into: [newer]).first?.currentPointsMe, 3)
    }
}
