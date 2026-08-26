// TrendsSection.swift — the "Trends" section on the archive screen
// (PastMatchesView), above Live Match / Past Matches. Four headline
// sparklines plus a NavigationLink into the full TrendsView. Mirrors
// RecCoachSection's shape: a self-contained struct that emits its own
// Section, with a "needs N more" line instead of vanishing on thin data —
// a deliberate departure from the hide-when-empty idiom, since hiding here
// would mean a new user never discovers the feature (OQ-3).
// See docs/features/PERFORMANCE_TRENDS_PLAN.md §6.1, §6.6.
import SwiftUI
import DeuceMateCore

struct TrendsSection: View {
    /// The full phone archive (store.history) — NOT PastMatchesView's
    /// `pastRecords`, which unions in watch-mirror summaries that may carry
    /// no `stats` at all (§6.1). Includes the live match, if any — it now
    /// contributes to trends once it clears the categorized-points
    /// threshold (owner request), not just completed matches.
    let records: [MatchRecord]

    @Environment(\.appTheme) private var theme
    @StateObject private var samplesCache = TrendsSamples()

    private var headline: [TrendSeries] {
        PerformanceTrends.headline(in: samplesCache.samples)
    }

    private var matchesNeeded: Int? {
        let have = samplesCache.samples.count
        guard have < PerformanceTrends.minimumMatches else { return nil }
        return PerformanceTrends.minimumMatches - have
    }

    /// A cheap per-render signature covering everything TrendsSamples'
    /// cache cares about (id, endTime, iWon, stats.count) — used only to
    /// decide whether to CALL refresh at all; TrendsSamples' own internal
    /// fingerprint is the precise check. Needed because a live match's
    /// stats grow one point at a time without its id ever changing, so
    /// watching `records.map(\.id)` alone would never re-trigger while a
    /// match is still being scored.
    private var recordsSignature: String {
        records.map {
            "\($0.id.uuidString)|\($0.stats.count)|\($0.endTime?.timeIntervalSince1970 ?? -1)|\($0.iWon.map(String.init) ?? "?")"
        }.joined(separator: ";")
    }

    var body: some View {
        Section {
            if let needed = matchesNeeded {
                Label(
                    "Track \(needed) more tracked match\(needed == 1 ? "" : "es") to see performance trends.",
                    systemImage: "lock"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 2)
            } else {
                VStack(spacing: 6) {
                    ForEach(headline) { series in
                        TrendSparkline(series: series, displayMode: .rate, color: theme.colors.me)
                    }
                }
                .padding(.vertical, 2)
                NavigationLink {
                    TrendsView(samples: samplesCache.samples)
                } label: {
                    Text("See all trends")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(theme.colors.me)
                }
            }
        } header: {
            Text("Trends")
        }
        .onAppear {
            samplesCache.refresh(records: records)
        }
        .onChange(of: recordsSignature) { _, _ in
            samplesCache.refresh(records: records)
        }
    }
}
