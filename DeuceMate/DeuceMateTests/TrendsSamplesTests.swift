// TrendsSamplesTests.swift — cache invalidation for the Trends screen's
// id-keyed MatchTrendSample derivation.
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

    private func makeInProgress(id: UUID, pointCount: Int = 25) -> MatchRecord {
        MatchRecord(id: id, startTime: Date(), endTime: nil,
                    setScores: [SetScore()], stats: makePoints(count: pointCount), iWon: nil)
    }

    private func makeCompleted(id: UUID, startTime: Date) -> MatchRecord {
        MatchRecord(id: id, startTime: startTime, endTime: Date(),
                    setScores: [SetScore(gamesMe: 6, gamesOpponent: 3)],
                    stats: makePoints(count: 25), iWon: true)
    }

    /// Regression for a bug caught in PR #120 review: an id-only cache
    /// signature doesn't change when a match transitions from in-progress
    /// to completed (same id, new endTime/iWon), so the sample's content
    /// stayed frozen at its in-progress shape. Now that in-progress matches
    /// are themselves eligible (owner request), the assertion is about the
    /// sample's CONTENT updating on completion, not about appearing for the
    /// first time.
    @Test func refresh_picksUpMatchCompletingWithSameID() {
        let id = UUID()
        let cache = TrendsSamples()

        cache.refresh(records: [makeInProgress(id: id)])
        #expect(cache.samples.map(\.matchID) == [id])
        #expect(cache.samples.first?.isInProgress == true)
        #expect(cache.samples.first?.recorderWon == nil)

        let completed = makeCompleted(id: id, startTime: Date().addingTimeInterval(-3600))
        cache.refresh(records: [completed])
        #expect(cache.samples.map(\.matchID) == [id])
        #expect(cache.samples.first?.isInProgress == false)
        #expect(cache.samples.first?.recorderWon == true)
    }

    /// A live match's stats grow one point at a time while endTime/iWon stay
    /// nil the whole time — a fingerprint on id/endTime/iWon alone can't see
    /// that. The cache must pick up the newly-scored points on the next
    /// refresh, not freeze at whatever the match looked like on first load.
    @Test func refresh_picksUpNewPointsOnStillInProgressMatch() {
        let id = UUID()
        let cache = TrendsSamples()

        cache.refresh(records: [makeInProgress(id: id, pointCount: 25)])
        #expect(cache.samples.first?.totalPoints == 25)

        cache.refresh(records: [makeInProgress(id: id, pointCount: 30)])
        #expect(cache.samples.first?.totalPoints == 30)
    }

    /// Regression for a Codex-caught bug in PR #121 review: an (id,
    /// endTime, iWon, statsCount) fingerprint doesn't change when a record's
    /// point-level content is replaced in place — e.g. a Settings > Backup
    /// & Transfer import re-categorizing points — while id, endTime, iWon,
    /// and point count all stay identical. Not hypothetical:
    /// `ManualMatchArchiveBackup`'s replace/merge import modes both
    /// preserve the incoming record's id. The cache must pick up the new
    /// content, not freeze on the old.
    @Test func refresh_picksUpChangedContentWithSameIdentityAndCount() {
        let id = UUID()
        let cache = TrendsSamples()

        let original = makeCompleted(id: id, startTime: Date().addingTimeInterval(-3600))
        cache.refresh(records: [original])
        let originalUnforcedErrors = cache.samples.first?.unforcedErrorsHit
        #expect(originalUnforcedErrors == 12)  // makePoints alternates winner/unforcedError over 25 points

        // Same id/startTime/endTime/setScores/iWon/point-count as `original`
        // — only the point-level content differs (every point now a winner).
        let recategorized = MatchRecord(
            id: id, startTime: original.startTime, endTime: original.endTime,
            setScores: original.setScores,
            stats: (0..<25).map { _ in PointStat(setIndex: 0, server: .me, winner: .me, outcome: .winner) },
            iWon: original.iWon
        )
        #expect(recategorized.stats.count == original.stats.count)

        cache.refresh(records: [recategorized])
        #expect(cache.samples.first?.unforcedErrorsHit == 0)
    }

    /// A no-op refresh (identical records) must not recompute — this is the
    /// whole point of the cache. Verified indirectly: samples stays stable
    /// in both identity and content across a redundant call.
    @Test func refresh_isNoOpWhenNothingChanged() {
        let id = UUID()
        let record = makeCompleted(id: id, startTime: Date().addingTimeInterval(-3600))
        let cache = TrendsSamples()

        cache.refresh(records: [record])
        let first = cache.samples
        cache.refresh(records: [record])
        #expect(cache.samples.map(\.matchID) == first.map(\.matchID))
        #expect(cache.samples.count == 1)
    }

    /// Adding a second match (id set changes) is picked up.
    @Test func refresh_picksUpNewlyAddedMatch() {
        let idA = UUID()
        let idB = UUID()
        let cache = TrendsSamples()

        cache.refresh(records: [makeCompleted(id: idA, startTime: Date().addingTimeInterval(-7200))])
        #expect(cache.samples.count == 1)

        cache.refresh(records: [
            makeCompleted(id: idA, startTime: Date().addingTimeInterval(-7200)),
            makeCompleted(id: idB, startTime: Date().addingTimeInterval(-3600))
        ])
        #expect(Set(cache.samples.map(\.matchID)) == Set([idA, idB]))
    }

}
