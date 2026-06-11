// WatchMirrorTests.swift
import XCTest
@testable import DeuceMateCore

final class WatchMirrorTests: XCTestCase {

    // MARK: - Helpers

    private func makeRecord(
        id: UUID = UUID(),
        startTime: Date = Date(),
        endTime: Date? = Date(),
        iWon: Bool? = true,
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

    /// An in-progress (live) record: no result yet and no end time.
    private func makeInProgress(id: UUID = UUID(), startTime: Date = Date()) -> MatchRecord {
        makeRecord(id: id, startTime: startTime, endTime: nil, iWon: nil)
    }

    // MARK: - merged

    func test_merged_insertsIncomingRecord() {
        let rec = makeRecord()
        let result = WatchMirror.merged(existing: [], incoming: [rec], manifest: [rec.id])
        XCTAssertEqual(result.map(\.id), [rec.id])
    }

    func test_merged_upsertsByID_newerBodyReplaces() {
        let id = UUID()
        let old = makeRecord(id: id, statCount: 2)
        let new = makeRecord(id: id, statCount: 7)
        let result = WatchMirror.merged(existing: [old], incoming: [new], manifest: [id])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.stats.count, 7)
    }

    func test_merged_retainsIncomingIDEvenWhenAbsentFromManifest() {
        // The watch sends the manifest as a *separate* message from the record, so
        // at the instant a record arrives the manifest is often the previous (and
        // therefore stale) one. A record we just received must never be dropped.
        let rec = makeRecord()
        let result = WatchMirror.merged(existing: [], incoming: [rec], manifest: [])
        XCTAssertEqual(result.map(\.id), [rec.id])
    }

    func test_merged_dropsExistingRecordNotInManifestNorIncoming() {
        let stale = makeRecord()
        let fresh = makeRecord()
        let result = WatchMirror.merged(
            existing: [stale],
            incoming: [fresh],
            manifest: [fresh.id]
        )
        XCTAssertEqual(result.map(\.id), [fresh.id])
    }

    func test_merged_ignoresInProgressIncoming() {
        let live = makeInProgress()
        let result = WatchMirror.merged(existing: [], incoming: [live], manifest: [live.id])
        XCTAssertTrue(result.isEmpty, "live checkpoints are shown from the archive, never mirrored")
    }

    func test_merged_keepsCompletedDraw() {
        // A completed draw has iWon == nil but a non-nil endTime, so it is NOT
        // in-progress and must be mirrored.
        let draw = makeRecord(endTime: Date(), iWon: nil)
        let result = WatchMirror.merged(existing: [], incoming: [draw], manifest: [draw.id])
        XCTAssertEqual(result.map(\.id), [draw.id])
    }

    func test_merged_sortsNewestFirst() {
        let now = Date()
        let older = makeRecord(startTime: now.addingTimeInterval(-100))
        let newer = makeRecord(startTime: now)
        let result = WatchMirror.merged(
            existing: [older],
            incoming: [newer],
            manifest: [older.id, newer.id]
        )
        XCTAssertEqual(result.map(\.id), [newer.id, older.id])
    }

    func test_merged_equalStartTime_tiebreaksByIDAscending() {
        let when = Date(timeIntervalSince1970: 1_000)
        let ids = [UUID(), UUID()].sorted { $0.uuidString < $1.uuidString }
        let a = makeRecord(id: ids[0], startTime: when)
        let b = makeRecord(id: ids[1], startTime: when)
        // Feed them in the "wrong" order to prove the sort, not input order, decides.
        let result = WatchMirror.merged(
            existing: [],
            incoming: [b, a],
            manifest: [a.id, b.id]
        )
        XCTAssertEqual(result.map(\.id), [ids[0], ids[1]])
    }

    // MARK: - pruned

    func test_pruned_keepsOnlyManifestIDs() {
        let keep = makeRecord()
        let drop = makeRecord()
        let result = WatchMirror.pruned([keep, drop], manifest: [keep.id])
        XCTAssertEqual(result.map(\.id), [keep.id])
    }

    func test_pruned_emptyManifest_emptiesMirror() {
        let result = WatchMirror.pruned([makeRecord(), makeRecord()], manifest: [])
        XCTAssertTrue(result.isEmpty)
    }

    func test_pruned_sortsNewestFirst() {
        let now = Date()
        let older = makeRecord(startTime: now.addingTimeInterval(-100))
        let newer = makeRecord(startTime: now)
        let result = WatchMirror.pruned([older, newer], manifest: [older.id, newer.id])
        XCTAssertEqual(result.map(\.id), [newer.id, older.id])
    }
}
