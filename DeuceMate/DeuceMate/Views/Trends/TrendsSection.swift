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
    /// no `stats` at all (§6.1).
    let records: [MatchRecord]
    let activeMatchID: UUID?

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
            samplesCache.refresh(records: records, excludingActiveMatchID: activeMatchID)
        }
        .onChange(of: records.map(\.id)) { _, _ in
            samplesCache.refresh(records: records, excludingActiveMatchID: activeMatchID)
        }
    }
}
