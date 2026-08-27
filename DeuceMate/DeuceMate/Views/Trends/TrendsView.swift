// TrendsView.swift — the full Trends screen, pushed from TrendsSection onto
// PastMatchesView's existing NavigationStack (not a sheet — Trends is a
// sibling destination the user drills into and back out of, unlike the
// per-match MatchDetailView leaf). Window / type / format filters, a
// Rate/Count toggle, then one grouped chart per TrendMetricGroup.
// See docs/features/PERFORMANCE_TRENDS_PLAN.md §6.2.
import SwiftUI
import DeuceMateCore

struct TrendsView: View {
    /// Already-eligible samples for the whole archive (computed once by
    /// TrendsSection's TrendsSamples cache) — this view only filters/windows.
    let samples: [MatchTrendSample]

    // Phone-local UI state, not synced (no MatchSyncKey, no wire key — see
    // CLAUDE.md §0's settings-key exception list, which these four keys
    // are added to in the same PR as this file).
    @AppStorage("trendsWindow") private var windowRaw: String = "last10"
    @AppStorage("trendsMatchType") private var matchTypeRaw: String = "all"
    @AppStorage("trendsMatchFormat") private var matchFormatRaw: String = "all"
    /// Off by default — completed matches only. On blends the in-progress
    /// match's data into every chart alongside completed ones (an
    /// inclusion switch, not a dataset swap — see TrendFilter.includeInProgress).
    @AppStorage("trendsIncludeInProgress") private var includeInProgress: Bool = false

    @State private var displayMode: TrendDisplayMode = .rate


    private var window: TrendWindow {
        if windowRaw == "all" { return .all }
        if windowRaw.hasPrefix("last"), let n = Int(windowRaw.dropFirst(4)) { return .last(n) }
        return .last(10)
    }

    /// `nil` decodes as "all" for both — `MatchType(rawValue: "all")` and
    /// `MatchFormat(rawValue: "all")` both naturally return nil since
    /// neither enum has an "all" case.
    private var matchType: MatchType? { MatchType(rawValue: matchTypeRaw) }
    private var matchFormat: MatchFormat? { MatchFormat(rawValue: matchFormatRaw) }

    /// `.perpetualPoints` is omitted from the format menu (below) since it
    /// can never contribute a sample (§3.5) — offering it would be a filter
    /// that always empties the screen.
    private let selectableFormats: [MatchFormat] = [
        .standard, .bestOf3FullFinalSet, .superTiebreak, .perpetualSuperTiebreak, .quick4Games
    ]

    /// Display order for the grouped sections — a presentation preference
    /// distinct from `TrendMetricGroup`'s own declaration order (which
    /// `TrendMetric.metrics(in:)` and every other Core consumer are
    /// indifferent to). Errors first, then Serve & Return, Attack, Rally
    /// Depth (whole-match, then split by serving side), Pressure, Fatigue.
    private let groupDisplayOrder: [TrendMetricGroup] = [
        .errors, .serveReturn, .attack, .rallyDepth, .rallyDepthByService, .pressure,
        .fatigue
    ]

    private var scopedSamples: [MatchTrendSample] {
        PerformanceTrends.scoped(
            samples,
            filter: TrendFilter(matchType: matchType, matchFormat: matchFormat, includeInProgress: includeInProgress),
            window: window
        )
    }

    /// Matches in the current scoped window whose outcome tracking was off
    /// for part of the match (`trackingCoverage < 1.0`) — surfaced so a
    /// low-coverage window isn't silently averaged in as if every point had
    /// been seen (OQ-5, docs/features/PERFORMANCE_TRENDS_PLAN.md §3.6).
    private var partiallyTrackedCount: Int {
        scopedSamples.filter { $0.trackingCoverage < 1.0 }.count
    }

    /// index -> match date for EVERY scoped sample, independent of whether
    /// any metric in any group actually has a plottable value there.
    /// `TrendChart` deriving dates only from its own (already-sparse)
    /// `series` left an index with zero data for the whole group — every
    /// Rally Depth metric gapped on a match with no ending-shot data, say —
    /// invisible to both its axis label and its selection readout, even
    /// though `chartXDomain` still spans that index (Codex review, PR
    /// #121). `scopedSamples` is oldest-first, matching `TrendPoint.index`.
    private var dateByIndex: [Int: Date] {
        Dictionary(uniqueKeysWithValues: scopedSamples.enumerated().map { ($0.offset, $0.element.startTime) })
    }

    /// How many scoped matches can actually support the Fatigue comparison.
    ///
    /// Health data is device-local and does NOT survive an iCloud restore: the
    /// canonical archive is health-stripped and the Health sidecar is excluded
    /// from backup, so after a fresh-install restore the tennis metrics come
    /// back and these do not. A partly-covered health chart is therefore a
    /// normal state that has to be explained rather than left mysterious —
    /// the same reasoning as the partial-tracking caption above.
    private func coverageNote(for group: TrendMetricGroup) -> String? {
        let total = scopedSamples.count
        guard total > 0 else { return nil }

        let covered: Int
        let subject: String
        switch group {
        case .fatigue:
            covered = scopedSamples.filter { !$0.setSlices.isEmpty }.count
            subject = "two or more completed sets"
        case .errors, .attack, .rallyDepth, .rallyDepthByService, .serveReturn, .pressure:
            return nil
        }

        return "\(covered) of \(total) match\(total == 1 ? "" : "es") in this window "
            + "\(covered == 1 ? "has" : "have") \(subject)."
    }

    var body: some View {
        List {
            Section {
                windowPicker
                HStack {
                    typePicker
                    Spacer()
                    formatMenu
                }
                Toggle("Include In-Progress Matches", isOn: $includeInProgress)
                Picker("Display", selection: $displayMode) {
                    ForEach(TrendDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Re-enforces PerformanceTrends.minimumMatches AFTER filtering —
            // the archive screen's TrendsSection only gates on the unfiltered
            // total, so a filter combination that leaves 1-2 matches must be
            // caught here or a single match would render as a "trend"
            // (Codex review, PR #121).
            if scopedSamples.count < PerformanceTrends.minimumMatches {
                Section {
                    ContentUnavailableView(
                        "Not Enough Matches",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text(scopedSamples.isEmpty
                            ? "No tracked matches match these filters."
                            : "Only \(scopedSamples.count) tracked match\(scopedSamples.count == 1 ? "" : "es") found for these filters — Trends needs at least \(PerformanceTrends.minimumMatches).")
                    )
                }
            } else {
                if partiallyTrackedCount > 0 {
                    Section {
                        Label(
                            "\(partiallyTrackedCount) match\(partiallyTrackedCount == 1 ? "" : "es") in this window had tracking off for part of the match — outcome rates below reflect only the tracked points.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                ForEach(groupDisplayOrder) { group in
                    let groupSeries = PerformanceTrends.series(for: group, in: scopedSamples)
                    // `!groupSeries.isEmpty` is not the right test: a group
                    // whose metrics all exist but carry no plottable point —
                    // every health group on an archive recorded without Health
                    // access — still returns a full series array. Ask whether
                    // any of them has a point before drawing a section of
                    // empty charts.
                    if groupSeries.contains(where: { !$0.points.isEmpty }) {
                        Section {
                            TrendChart(group: group, series: groupSeries, displayMode: displayMode, sampleCount: scopedSamples.count, dateByIndex: dateByIndex)
                        } header: {
                            Text(group.displayLabel)
                        } footer: {
                            if let note = coverageNote(for: group) {
                                Text(note)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var windowPicker: some View {
        Picker("Window", selection: $windowRaw) {
            ForEach(TrendWindow.presets, id: \.self) { w in
                Text(w.label).tag(windowRawValue(w))
            }
        }
        .pickerStyle(.segmented)
    }

    private func windowRawValue(_ w: TrendWindow) -> String {
        switch w {
        case .all: return "all"
        case .last(let n): return "last\(n)"
        }
    }

    private var typePicker: some View {
        Picker("Match Type", selection: $matchTypeRaw) {
            Text("All").tag("all")
            Text("Singles").tag(MatchType.singles.rawValue)
            Text("Doubles").tag(MatchType.doubles.rawValue)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 220)
    }

    private var formatMenu: some View {
        Menu {
            Button("All Formats") { matchFormatRaw = "all" }
            ForEach(selectableFormats, id: \.self) { format in
                Button(formatDisplayName(format)) { matchFormatRaw = format.rawValue }
            }
        } label: {
            Label(matchFormat.map(formatDisplayName) ?? "All Formats", systemImage: "line.3.horizontal.decrease.circle")
                .font(.subheadline)
        }
    }

    private func formatDisplayName(_ format: MatchFormat) -> String {
        switch format {
        case .standard:               return "Best of 3"
        case .bestOf3FullFinalSet:    return "Best of 3 (Full Final Set)"
        case .superTiebreak:          return "Super Tiebreak"
        case .perpetualSuperTiebreak: return "Perpetual Tiebreak"
        case .quick4Games:            return "Quick 4 Games"
        case .perpetualPoints:        return "Perpetual Points"
        }
    }
}
