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

    /// The match IDs, in order, that produced the current `samples` —
    /// recomputing only when this changes avoids re-deriving on every
    /// unrelated re-render of the archive screen.
    private var cachedSignature: [UUID] = []

    /// Recomputes `samples` from `records` only if the record set has
    /// actually changed since the last call. `records` may be in any order
    /// (`PerformanceTrends.samples` normalizes to oldest-first internally).
    func refresh(records: [MatchRecord], excludingActiveMatchID activeMatchID: UUID?) {
        let signature = records.map(\.id)
        guard signature != cachedSignature else { return }
        cachedSignature = signature
        samples = PerformanceTrends.samples(from: records, excluding: activeMatchID)
    }
}
