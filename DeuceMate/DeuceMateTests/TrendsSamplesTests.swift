// TrendsSamplesTests.swift — cache invalidation for the Trends screen's
// id-keyed MatchTrendSample derivation. Regression coverage for a bug
// caught in PR #120 review: an id-only cache signature doesn't change when
// a match transitions from in-progress to completed (same id, new
// endTime/iWon), so the newly-eligible match silently never appears.
import Foundation
import DeuceMateCore
import Testing
@testable import DeuceMate

@MainActor
struct TrendsSamplesTests {

    private func makePoints(count: Int) -> [PointStat] {
        (0..<count).map { i in
            PointStat(setIndex: 0, server: .me, winner: i % 2 == 0 ? .me : .opponent,
                      outcome: i % 2 == 0 ? .winner : .unforcedError)
        }
    }

    private func makeInProgress(id: UUID) -> MatchRecord {
        MatchRecord(id: id, startTime: Date(), endTime: nil,
                    setScores: [SetScore()], stats: makePoints(count: 25), iWon: nil)
    }

    private func makeCompleted(id: UUID, startTime: Date) -> MatchRecord {
        MatchRecord(id: id, startTime: startTime, endTime: Date(),
                    setScores: [SetScore(gamesMe: 6, gamesOpponent: 3)],
                    stats: makePoints(count: 25), iWon: true)
    }

    /// The bug: refresh(records:) is called once while a match is
    /// in-progress (excluded from samples, correctly), then again after the
    /// SAME match completes (same id, only endTime/iWon changed). An
    /// id-only cache signature sees no change in the id array and skips
    /// recomputation, leaving the newly-eligible match permanently absent
    /// from samples until an unrelated match changes the id set.
    @Test func refresh_picksUpMatchCompletingWithSameID() {
        let id = UUID()
        let cache = TrendsSamples()

        // excludingActiveMatchID held constant (nil) across both calls, so
        // the ONLY thing that changes between them is the record's own
        // endTime/iWon — isolating exactly the transition the bug missed.
        cache.refresh(records: [makeInProgress(id: id)], excludingActiveMatchID: nil)
        #expect(cache.samples.isEmpty)

        let completed = makeCompleted(id: id, startTime: Date().addingTimeInterval(-3600))
        cache.refresh(records: [completed], excludingActiveMatchID: nil)
        #expect(cache.samples.map(\.matchID) == [id])
    }

    /// A no-op refresh (identical records, identical activeMatchID) must not
    /// recompute — this is the whole point of the cache. Verified indirectly:
    /// samples stays stable in both identity and content across a redundant call.
    @Test func refresh_isNoOpWhenNothingChanged() {
        let id = UUID()
        let record = makeCompleted(id: id, startTime: Date().addingTimeInterval(-3600))
        let cache = TrendsSamples()

        cache.refresh(records: [record], excludingActiveMatchID: nil)
        let first = cache.samples
        cache.refresh(records: [record], excludingActiveMatchID: nil)
        #expect(cache.samples.map(\.matchID) == first.map(\.matchID))
        #expect(cache.samples.count == 1)
    }

    /// Adding a second match (id set changes) is picked up — the pre-existing
    /// id-based half of the signature still works.
    @Test func refresh_picksUpNewlyAddedMatch() {
        let idA = UUID()
        let idB = UUID()
        let cache = TrendsSamples()

        cache.refresh(records: [makeCompleted(id: idA, startTime: Date().addingTimeInterval(-7200))], excludingActiveMatchID: nil)
        #expect(cache.samples.count == 1)

        cache.refresh(records: [
            makeCompleted(id: idA, startTime: Date().addingTimeInterval(-7200)),
            makeCompleted(id: idB, startTime: Date().addingTimeInterval(-3600))
        ], excludingActiveMatchID: nil)
        #expect(Set(cache.samples.map(\.matchID)) == Set([idA, idB]))
    }

    /// A change to `excludingActiveMatchID` alone (no record content change)
    /// must also trigger recomputation, since it affects which record the
    /// derivation excludes.
    @Test func refresh_picksUpActiveMatchIDChange() {
        let idA = UUID()
        let idB = UUID()
        let recordA = makeCompleted(id: idA, startTime: Date().addingTimeInterval(-7200))
        let recordB = makeCompleted(id: idB, startTime: Date().addingTimeInterval(-3600))
        let cache = TrendsSamples()

        cache.refresh(records: [recordA, recordB], excludingActiveMatchID: idA)
        #expect(cache.samples.map(\.matchID) == [idB])

        cache.refresh(records: [recordA, recordB], excludingActiveMatchID: nil)
        #expect(Set(cache.samples.map(\.matchID)) == Set([idA, idB]))
    }
}
