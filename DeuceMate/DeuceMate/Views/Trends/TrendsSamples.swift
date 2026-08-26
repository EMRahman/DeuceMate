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
    /// both the ordering and the eligibility rule) — including the live
    /// match, once it clears the categorized-points threshold.
    @Published private(set) var samples: [MatchTrendSample] = []

    /// The subset of each record's fields that changes eligibility or
    /// derivation: `id` for add/remove, `endTime`/`iWon` for the
    /// in-progress -> completed transition, and `statsCount` for a still-
    /// live match's points arriving one by one — its `endTime`/`iWon` never
    /// change while in progress, so without a stats-shaped signal a live
    /// match's trend line would freeze at whatever it looked like on the
    /// first refresh and never pick up a newly-scored point. The phone
    /// archive is otherwise read-only once a match completes (CLAUDE.md's
    /// "phone never authors results" invariant), so a full `stats` value
    /// comparison isn't needed for completed matches — just the count.
    private struct Fingerprint: Equatable {
        let id: UUID
        let endTime: Date?
        let iWon: Bool?
        let statsCount: Int
    }

    private var cachedFingerprints: [Fingerprint] = []

    /// Recomputes `samples` from `records` only if something that could
    /// change the result has actually changed since the last call.
    func refresh(records: [MatchRecord]) {
        let fingerprints = records.map { Fingerprint(id: $0.id, endTime: $0.endTime, iWon: $0.iWon, statsCount: $0.stats.count) }
        guard fingerprints != cachedFingerprints else { return }
        cachedFingerprints = fingerprints
        samples = PerformanceTrends.samples(from: records)
    }
}
