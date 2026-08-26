// TrendsSamples.swift — caches the id-keyed derivation of MatchTrendSamples
// from the phone archive so MatchStatsSummary's ~30-filter-pass init runs
// once per match, not once per render. See
// docs/features/PERFORMANCE_TRENDS_PLAN.md §6.6.
import Foundation
import Combine
import DeuceMateCore

@MainActor
final class TrendsSamples: ObservableObject {
    /// Oldest-first, eligible matches only (PerformanceTrends.samples owns
    /// both the ordering and the eligibility rule).
    @Published private(set) var samples: [MatchTrendSample] = []

    /// The subset of each record's fields that changes eligibility or
    /// derivation: `id` for add/remove, `endTime`/`iWon` for the
    /// in-progress -> completed transition. The phone archive is otherwise
    /// read-only once a match completes (CLAUDE.md's "phone never authors
    /// results" invariant), so those three fields are sufficient — a full
    /// `stats` comparison would also catch it but at the cost of walking
    /// every point in the archive on every check.
    private struct Fingerprint: Equatable {
        let id: UUID
        let endTime: Date?
        let iWon: Bool?
    }

    private var cachedFingerprints: [Fingerprint] = []
    private var cachedActiveMatchID: UUID?

    /// Recomputes `samples` from `records` only if something that could
    /// change the result has actually changed since the last call.
    ///
    /// An id-only signature is not enough: the live match's id is already
    /// present in `store.history` while in-progress (excluded from
    /// `samples` by `MatchTrendSample.init?`'s `isInProgress` check, not by
    /// being absent from `records`), so when it completes — same id, new
    /// `endTime`/`iWon` — an id-only comparison sees no change and the
    /// newly-eligible match stays missing from every trend until some
    /// unrelated match changes the id set. (Caught in PR #120 review.)
    func refresh(records: [MatchRecord], excludingActiveMatchID activeMatchID: UUID?) {
        let fingerprints = records.map { Fingerprint(id: $0.id, endTime: $0.endTime, iWon: $0.iWon) }
        guard fingerprints != cachedFingerprints || activeMatchID != cachedActiveMatchID else { return }
        cachedFingerprints = fingerprints
        cachedActiveMatchID = activeMatchID
        samples = PerformanceTrends.samples(from: records, excluding: activeMatchID)
    }
}
