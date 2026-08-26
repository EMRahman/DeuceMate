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

    /// Full record equality, not a hand-picked field subset. An earlier
    /// (id, endTime, iWon, statsCount) fingerprint missed a real case: a
    /// Settings > Backup & Transfer import can replace a record's content —
    /// re-categorized points, corrected server data, edited start
    /// time/type/format — while its id, endTime, iWon, and point count all
    /// stay identical (`ManualMatchArchiveBackup`'s replace/merge modes
    /// both preserve the incoming record's `id`, so this isn't
    /// hypothetical). That left the Trends screen showing stale derived
    /// data until something else happened to change the signature, since
    /// dismissing the Settings sheet doesn't recreate this `@StateObject`
    /// (Codex review, PR #121). `MatchRecord`'s synthesized `==` compares
    /// every stored field, including `stats`, so nothing that could change
    /// a derived `MatchTrendSample` can silently miss invalidating the
    /// cache — and it stays correct automatically if a future field is
    /// added, with no field list to keep in sync.
    private var cachedRecords: [MatchRecord] = []

    /// The resolved max HR the cached samples were derived with. It is a live
    /// setting (`MaxHRSetting`) applied retroactively to archived matches, so
    /// editing a birth year in Settings changes every hard-zone counter without
    /// touching a single record — leaving the records-only check above unable
    /// to notice. Same composite-key reasoning as `MatchDetailView`'s
    /// `.task(id: "\(playerNTRP)-\(resolvedMaxHR)")`.
    private var cachedMaxHR: Int?

    /// Recomputes `samples` only if something that could change the result has
    /// actually changed since the last call — the records themselves, or the
    /// max-HR yardstick the zone counters are measured against.
    func refresh(records: [MatchRecord], maxHR: Int) {
        guard records != cachedRecords || maxHR != cachedMaxHR else { return }
        cachedRecords = records
        cachedMaxHR = maxHR
        samples = PerformanceTrends.samples(from: records, maxHR: maxHR)
    }
}
