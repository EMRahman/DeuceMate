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

    /// Completed matches only — the archive-screen headline has no room for
    /// its own filter controls, so it silently takes the feature's default
    /// (TrendFilter()'s includeInProgress: false), matching the full Trends
    /// screen's own default. The in-progress match can still be seen by
    /// opening the full screen and switching "Include In-Progress Matches" on.
    private var completedOnly: [MatchTrendSample] {
        PerformanceTrends.scoped(samplesCache.samples, filter: TrendFilter(), window: .all)
    }

    private var headline: [TrendSeries] {
        PerformanceTrends.headline(in: completedOnly)
    }

    /// "Double Faults 7%, Unforced Errors 24%, ..." — one VoiceOver
    /// announcement standing in for the four TrendSparkline rows once
    /// they're combined into a single accessibility element (see body).
    private var headlineAccessibilitySummary: String {
        let parts = headline.map { series in
            "\(series.metric.displayLabel) \(series.metric.format(series.pooled))"
        }
        return (["Trends"] + parts).joined(separator: ", ")
    }

    private var matchesNeeded: Int? {
        // Counts completedOnly, not samplesCache.samples — otherwise this
        // gate could pass on total match count while the headline it gates
        // (computed from the completed-only subset) still has too few.
        let have = completedOnly.count
        guard have < PerformanceTrends.minimumMatches else { return nil }
        return PerformanceTrends.minimumMatches - have
    }

    /// Whether opening the full Trends screen and switching on "Include
    /// In-Progress Matches" would itself clear `minimumMatches`, even
    /// though the completed-only count (`matchesNeeded`) doesn't. That
    /// toggle lives ONLY inside `TrendsView`, so without this the thin-data
    /// state was a dead end: too few completed matches to unlock the
    /// NavigationLink, with no way to reach the one control that could fix
    /// that (Codex review, PR #121).
    private var reachableViaInProgress: Bool {
        matchesNeeded != nil && samplesCache.samples.count >= PerformanceTrends.minimumMatches
    }

    private func thinDataLabel(needed: Int) -> some View {
        Label(
            reachableViaInProgress
                ? "Track \(needed) more completed match\(needed == 1 ? "" : "es") — or open Trends and include your in-progress match."
                : "Track \(needed) more tracked match\(needed == 1 ? "" : "es") to see performance trends.",
            systemImage: "lock"
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.vertical, 2)
    }

    var body: some View {
        Section {
            if let needed = matchesNeeded {
                if reachableViaInProgress {
                    NavigationLink {
                        TrendsView(samples: samplesCache.samples)
                    } label: {
                        thinDataLabel(needed: needed)
                    }
                    .accessibilityHint(Text("Opens Trends"))
                } else {
                    thinDataLabel(needed: needed)
                }
            } else {
                // The whole card is the navigation target — not just a
                // separate "See all trends" row — so any tap on a sparkline
                // opens the full screen. The system supplies the chevron
                // disclosure hint automatically for a NavigationLink row in
                // a List, the same one the old text-only row already had.
                NavigationLink {
                    TrendsView(samples: samplesCache.samples)
                } label: {
                    VStack(spacing: 6) {
                        ForEach(headline) { series in
                            TrendSparkline(series: series, displayMode: .rate, color: theme.colors.me, sampleCount: completedOnly.count)
                        }
                    }
                    .padding(.vertical, 2)
                }
                // Each TrendSparkline already ignores its own children for
                // accessibility and states its own label; wrapping four of
                // them in one NavigationLink would otherwise concatenate
                // all four into one run-on VoiceOver announcement. Replace
                // it with one concise summary plus an explicit hint that
                // this opens something.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(headlineAccessibilitySummary))
                .accessibilityHint(Text("Opens Trends"))
            }
        } header: {
            Text("Trends")
        }
        .onAppear {
            samplesCache.refresh(records: records)
        }
        // `records` (a `[MatchRecord]`) is directly Equatable — comparing
        // it here, rather than a hand-picked field subset, is what makes
        // TrendsSamples.refresh's own full-record equality check (see that
        // file) actually get invoked whenever anything relevant changes,
        // including a live match's stats growing point-by-point (endTime/
        // iWon never change while in progress, so watching only those
        // wouldn't retrigger) or a Backup & Transfer import replacing a
        // record's content in place (Codex review, PR #121).
        .onChange(of: records) { _, _ in
            samplesCache.refresh(records: records)
        }
    }
}
