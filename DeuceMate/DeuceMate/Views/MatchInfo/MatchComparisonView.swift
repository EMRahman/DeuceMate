// MatchComparisonView.swift — "Compare with previous match" (MATCH_TAGS_PLAN.md
// §7.1). Both records are resolved by UUID from the live store on every
// render, so tag edits, watch syncs, imports and deletions update the screen.
//
// Baseline: Core's `PreviousMatchBaseline` — a rematch against the same
// opponent(s) when the identity is complete, otherwise the most recent earlier
// completed match of the same singles/doubles type. Rates come from Core's
// `MatchComparison` (existing Trends denominators, no second counting pass);
// a missing rate is "Not recorded", never zero, and an in-progress side is
// labelled partial with no inferred result.
import SwiftUI
import DeuceMateCore

struct MatchComparisonView: View {
    let currentID: UUID

    @EnvironmentObject private var store: PhoneStatsStore
    @Environment(\.appTheme) private var theme
    /// A baseline the user picked; `nil` = the automatic choice.
    @State private var chosenBaselineID: UUID?
    @State private var showPicker = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        let history = store.history
        Group {
            if let current = history.first(where: { $0.id == currentID }) {
                content(current: current, history: history)
            } else {
                ContentUnavailableView(
                    "Match Not Available",
                    systemImage: "tray",
                    description: Text("This match is no longer in the iPhone archive.")
                )
            }
        }
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPicker) {
            if let current = history.first(where: { $0.id == currentID }) {
                BaselinePickerView(current: current, selectedID: chosenBaselineID) { picked in
                    chosenBaselineID = picked
                    showPicker = false
                }
                .environmentObject(store)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(current: MatchRecord, history: [MatchRecord]) -> some View {
        let selection = PreviousMatchBaseline.select(for: current, in: history)
        // A chosen baseline that was deleted falls back to the automatic one.
        let chosen = chosenBaselineID.flatMap { id in history.first { $0.id == id && id != currentID } }
        let baseline = chosen ?? selection.baseline
        List {
            Section {
                baselineExplanation(selection: selection, isManual: chosen != nil, current: current)
                Button {
                    showPicker = true
                } label: {
                    Label("Choose Another Match", systemImage: "list.bullet")
                }
                .accessibilityIdentifier("choose-another-match")
            }

            if let baseline {
                let comparison = MatchComparison(current: current, baseline: baseline)
                overviewSection(comparison, baselineRecord: baseline)
                notesSection(comparison)
                metricsSection(comparison)
            }

            headToHeadSection(current: current, history: history)
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private func baselineExplanation(
        selection: PreviousMatchBaseline.Selection,
        isManual: Bool,
        current: MatchRecord
    ) -> some View {
        let typeLabel = current.matchType == .doubles ? "doubles" : "singles"
        VStack(alignment: .leading, spacing: 6) {
            if isManual {
                Text("Comparing with a match you chose")
                    .font(.headline)
            } else {
                switch selection {
                case .rematch(_, let matchup):
                    Text("Previous match against \(opponentNames(current))")
                        .font(.headline)
                    if matchup.matchType == .doubles {
                        Text("Doubles compares matches with the same partner against the same two opponents, in either order.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                case .noRematch:
                    Text("No previous match against this opponent")
                        .font(.headline)
                        .accessibilityIdentifier("no-rematch-message")
                    Text("Choose another \(typeLabel) match to compare with.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .sameType:
                    Text("Most recent earlier \(typeLabel) match")
                        .font(.headline)
                    Text("Add an opponent in Match Info to compare against the same player.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .noHistory:
                    Text("No earlier completed \(typeLabel) match")
                        .font(.headline)
                    Text("Once you finish another \(typeLabel) match it can be compared here. You can still choose an in-progress match.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Overview

    @ViewBuilder
    private func overviewSection(_ comparison: MatchComparison, baselineRecord: MatchRecord) -> some View {
        Section {
            columnHeader(comparison)
            valueRow("Result",
                     MatchComparisonFormat.result(comparison.current),
                     MatchComparisonFormat.result(comparison.baseline))
            valueRow("Score",
                     scoreText(comparison.current),
                     scoreText(comparison.baseline))
            valueRow("Duration",
                     MatchComparisonFormat.duration(comparison.current.durationSeconds),
                     MatchComparisonFormat.duration(comparison.baseline.durationSeconds))
            valueRow("Points tracked",
                     MatchComparisonFormat.coverage(comparison.current),
                     MatchComparisonFormat.coverage(comparison.baseline))
            if let line = baselineRecord.tags?.displayLine {
                LabeledContent("Previous match", value: line)
                    .font(.footnote)
            }
        } header: {
            Text("Overview")
        }
    }

    @ViewBuilder
    private func notesSection(_ comparison: MatchComparison) -> some View {
        let notes = comparisonNotes(comparison)
        if !notes.isEmpty {
            Section {
                ForEach(notes, id: \.self) { note in
                    Label(note, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func comparisonNotes(_ comparison: MatchComparison) -> [String] {
        var notes: [String] = []
        if comparison.current.isPartial || comparison.baseline.isPartial {
            notes.append("In-progress matches show partial stats; no result is assumed until they finish.")
        }
        if comparison.formatsDiffer {
            notes.append("These matches were played to different formats (\(formatLabel(comparison.current.matchFormat)) vs \(formatLabel(comparison.baseline.matchFormat))), so scores and durations aren't like-for-like. Rates still compare.")
        }
        if comparison.matchTypesDiffer {
            notes.append("One match is singles and the other doubles.")
        }
        if !comparison.current.hasOutcomeTracking || !comparison.baseline.hasOutcomeTracking {
            notes.append("Serve, return, winner and error rates need point outcomes. A match without them shows “Not recorded”.")
        }
        return notes
    }

    // MARK: - Metrics

    @ViewBuilder
    private func metricsSection(_ comparison: MatchComparison) -> some View {
        Section {
            columnHeader(comparison)
            ForEach(comparison.rows) { row in
                metricRow(row)
            }
        } header: {
            Text("Rates")
        } footer: {
            Text("Percentages show points won or made out of the points they could apply to. Changes are in percentage points.")
        }
    }

    private func metricRow(_ row: MatchComparison.Row) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.metric.displayLabel)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                if let change = MatchComparisonFormat.change(row.percentagePointChange) {
                    Text(change)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(color(for: row.direction))
                        .accessibilityLabel(changeAccessibility(change, direction: row.direction))
                }
            }
            Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 2) {
                GridRow {
                    Text(MatchComparisonFormat.ratio(row.current))
                        .foregroundStyle(row.current == nil ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(MatchComparisonFormat.ratio(row.baseline))
                        .foregroundStyle(row.baseline == nil ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.subheadline.monospacedDigit())
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Head-to-head

    @ViewBuilder
    private func headToHeadSection(current: MatchRecord, history: [MatchRecord]) -> some View {
        if let record = HeadToHead.record(for: current, in: history) {
            Section {
                Text(MatchComparisonFormat.headToHeadSummary(record))
                    .accessibilityIdentifier("head-to-head-summary")
            } header: {
                Text("Head-to-Head")
            } footer: {
                Text("Completed matches only, not counting this one. \(current.matchType == .doubles ? "Doubles counts the same partner against the same pair; singles and doubles are kept separate." : "Singles and doubles are kept separate.")")
            }
        }
    }

    // MARK: - Pieces

    private func columnHeader(_ comparison: MatchComparison) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 2) {
            GridRow {
                sideHeader("This match", side: comparison.current)
                sideHeader("Compared with", side: comparison.baseline)
            }
        }
    }

    private func sideHeader(_ title: String, side: MatchComparison.Side) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text("\(side.dateLabel) \(Self.dateFormatter.string(from: side.date))")
                .font(.subheadline.weight(.semibold))
            if side.isPartial {
                Text("In Progress — partial stats")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }

    private func valueRow(_ label: String, _ current: String, _ baseline: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 2) {
                GridRow {
                    Text(current)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(baseline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.subheadline.monospacedDigit())
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func scoreText(_ side: MatchComparison.Side) -> String {
        side.setScoreLabels.isEmpty ? "—" : side.setScoreLabels.joined(separator: "  ")
    }

    private func opponentNames(_ record: MatchRecord) -> String {
        let names = record.tags?.opponents.map(\.name) ?? []
        return names.isEmpty ? "this opponent" : names.joined(separator: " & ")
    }

    private func color(for direction: TrendDelta.Direction?) -> Color {
        switch direction {
        case .improving?: return theme.colors.me
        case .declining?: return theme.colors.opponent
        default: return .secondary
        }
    }

    private func changeAccessibility(_ change: String, direction: TrendDelta.Direction?) -> String {
        switch direction {
        case .improving?: return "\(change), better"
        case .declining?: return "\(change), worse"
        default: return change
        }
    }

    private func formatLabel(_ format: MatchFormat) -> String {
        switch format {
        case .standard:               return "Best of 3"
        case .bestOf3FullFinalSet:    return "Best of 3, full final set"
        case .superTiebreak:          return "Super Tiebreak"
        case .perpetualSuperTiebreak: return "Perpetual Tiebreak"
        case .quick4Games:            return "Quick 4 Games"
        case .perpetualPoints:        return "Perpetual Points"
        }
    }
}

// MARK: - Baseline picker

/// "Choose another match": every other match of the same singles/doubles type,
/// newest first. Completed only by default, with an explicit toggle to include
/// in-progress matches (each labelled partial).
struct BaselinePickerView: View {
    let current: MatchRecord
    let selectedID: UUID?
    /// `nil` = go back to the automatic baseline.
    let onPick: (UUID?) -> Void

    @EnvironmentObject private var store: PhoneStatsStore
    @Environment(\.dismiss) private var dismiss
    @State private var includeInProgress = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        let candidates = PreviousMatchBaseline.pickerCandidates(
            for: current, in: store.history, includeInProgress: includeInProgress
        )
        NavigationStack {
            List {
                Section {
                    Toggle("Include in-progress matches", isOn: $includeInProgress)
                        .accessibilityIdentifier("include-in-progress-toggle")
                } footer: {
                    Text("In-progress matches compare partial stats.")
                }
                Section {
                    Button {
                        onPick(nil)
                    } label: {
                        HStack {
                            Text("Automatic (recommended)")
                            Spacer()
                            if selectedID == nil { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                    }
                }
                Section(current.matchType == .doubles ? "Doubles Matches" : "Singles Matches") {
                    if candidates.isEmpty {
                        Text("No other \(current.matchType == .doubles ? "doubles" : "singles") matches yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(candidates) { record in
                        Button {
                            onPick(record.id)
                        } label: {
                            candidateRow(record)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("baseline-candidate-\(record.id.uuidString)")
                    }
                }
            }
            .navigationTitle("Choose a Match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func candidateRow(_ record: MatchRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(MatchChronology.caption(record, formatter: Self.dateFormatter))
                    .font(.subheadline.weight(.semibold))
                let score = record.setScores.enumerated().map { index, set in
                    SetScoreLabel.string(for: set, setIndex: index, matchFormat: record.matchFormat)
                }.joined(separator: "  ")
                if !score.isEmpty {
                    Text(score).font(.subheadline.monospacedDigit())
                }
                if let line = record.tags?.displayLine {
                    Text(line).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
                if record.isInProgress {
                    Text("In Progress — partial stats")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            if record.id == selectedID {
                Image(systemName: "checkmark").foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
    }
}
