// GamePlanEvidenceView.swift — which matches against the opponent a game
// plan draws on, pushed from Prepare Game Plan's Matches row: the Last 5 /
// Last 10 / Count / All presets, individual selection, date and competition
// filters, the unfinished-matches opt-in, and what the selection covers.
// Selection rules live in Core (`GamePlanSelection`, `GamePlanEligibility`).
import SwiftUI
import DeuceMateCore

/// Everything the player chooses about the evidence. One value, so the main
/// screen hands a single binding to this screen.
struct GamePlanEvidenceChoices: Equatable {
    var selection = GamePlanSelection()
    var customCount = 3
    /// The Count preset is on, so 5 or 10 chosen with the stepper stays a count.
    var usesCustomCount = false
    /// On by default: a saved checkpoint is partial evidence, never a result.
    var includeInProgress = true
    var useFromDate = false
    var fromDate = Date()
    var useThroughDate = false
    var throughDate = Date()
    var competitionFilter: Set<GamePlanCompetition>?

    var filter: GamePlanFilter {
        GamePlanFilter(from: useFromDate ? fromDate : nil,
                       through: useThroughDate ? throughDate : nil,
                       competitions: competitionFilter)
    }
}

struct GamePlanEvidenceView: View {
    @Binding var choices: GamePlanEvidenceChoices
    let candidates: GamePlanCandidates
    let opponentName: String
    /// Selected matches that carry a private note.
    let noteMatchIDs: Set<UUID>
    /// The unfinished match being finished: always selected.
    let pinnedMatchID: UUID?

    private var pool: [MatchRecord] { choices.selection.filtered(candidates) }
    private var selected: [MatchRecord] { choices.selection.resolve(candidates, pinning: pinnedMatchID) }

    /// Competition contexts present among eligible matches, for the filter.
    private var availableCompetitions: [GamePlanCompetition] {
        Set(candidates.eligible.map(GamePlanCompetition.init(record:)))
            .sorted { GamePlanCompetition.ordered($0, $1) }
    }

    var body: some View {
        List {
            Section {
                if candidates.eligible.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No singles matches against \(opponentName) yet")
                            .font(.subheadline.weight(.semibold))
                        Text("Tag them as the opponent in Match Info on a past singles match to use it here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    presetPicker
                    if preset == .count {
                        Stepper(value: Binding(
                            get: { choices.customCount },
                            set: { value in
                                choices.customCount = GamePlanSelection.clampedCount(value, available: pool.count)
                                choices.selection.mode = .latest(choices.customCount)
                            }
                        ), in: 1...max(1, pool.count)) {
                            Text("Latest \(choices.customCount) \(choices.customCount == 1 ? "match" : "matches")")
                        }
                        .accessibilityIdentifier("game-plan-custom-count")
                    }
                    if case .custom = choices.selection.mode {
                        HStack {
                            Text("Custom selection")
                            Spacer()
                            Button("Reset to Last 5") {
                                choices.usesCustomCount = false
                                choices.selection.mode = .latest(GamePlanSelection.defaultCount)
                            }
                            .font(.footnote)
                        }
                    }
                    NavigationLink {
                        GamePlanMatchPickerView(
                            pool: pool,
                            selectedIDs: Set(selected.map(\.id)),
                            notesMatchIDs: noteMatchIDs,
                            pinned: selected.first { $0.id == pinnedMatchID },
                            toggle: { id in choices.selection.toggle(id, candidates: candidates) }
                        )
                    } label: {
                        LabeledContent("Matches", value: "\(selected.count) of \(max(pool.count, selected.count)) selected")
                    }
                    .accessibilityIdentifier("game-plan-choose-matches")
                    selectionSummary
                }
            } footer: {
                Text(pinnedMatchID == nil
                     ? "Only the selected matches are used."
                     : "Only the selected matches are used. The match you’re finishing is always included.")
            }

            if !candidates.eligible.isEmpty {
                Section {
                    filters
                } header: {
                    Text("Filters")
                } footer: {
                    Text("Filters apply before the count, so Last 5 means the latest five that match.")
                }
            }

            Section {
                Toggle("Include unfinished matches", isOn: $choices.includeInProgress)
                    .accessibilityIdentifier("game-plan-include-in-progress")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unfinished matches are saved checkpoints: partial evidence, never results.")
                    if let exclusions = Self.exclusionsText(candidates) { Text(exclusions) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Matches")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("game-plan-evidence-screen")
    }

    // MARK: - Presets

    private enum Preset: Hashable { case last5, last10, count, all, custom }

    private var preset: Preset {
        switch choices.selection.mode {
        case .latest where choices.usesCustomCount: return .count
        case .latest(5):  return .last5
        case .latest(10): return .last10
        case .latest:     return .count
        case .all:        return .all
        case .custom:     return .custom
        }
    }

    private var presetPicker: some View {
        Picker("Selection", selection: Binding(
            get: { preset },
            set: { newValue in
                choices.usesCustomCount = newValue == .count
                switch newValue {
                case .last5:  choices.selection.mode = .latest(5)
                case .last10: choices.selection.mode = .latest(10)
                case .count:
                    choices.customCount = GamePlanSelection.clampedCount(choices.customCount, available: pool.count)
                    choices.selection.mode = .latest(choices.customCount)
                case .all:    choices.selection.mode = .all
                case .custom: break
                }
            }
        )) {
            Text("Last 5").tag(Preset.last5)
            Text("Last 10").tag(Preset.last10)
            Text("Count").tag(Preset.count)
            Text("All").tag(Preset.all)
            if preset == .custom { Text("Custom").tag(Preset.custom) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("game-plan-preset")
    }

    // MARK: - Summary

    private var selectionSummary: some View {
        let points = selected.reduce(0) { $0 + $1.stats.count }
        let withOutcome = selected.reduce(0) { $0 + $1.stats.filter { $0.outcome != .uncategorized }.count }
        let starts = selected.map(\.startTime)
        let range: String = {
            guard let first = starts.min(), let last = starts.max() else { return "—" }
            let a = GamePlanView.dayFormatter.string(from: first), b = GamePlanView.dayFormatter.string(from: last)
            return a == b ? a : "\(a) – \(b)"
        }()
        let competitions = Dictionary(grouping: selected, by: GamePlanCompetition.init(record:))
            .sorted { GamePlanCompetition.ordered($0.key, $1.key) }
            .map { "\($0.key.label) \($0.value.count)" }
            .joined(separator: " · ")
        let scoreOnly = selected.filter { $0.stats.isEmpty }.count
        let partial = selected.filter { record in
            let tracked = record.stats.filter { $0.outcome != .uncategorized }.count
            return tracked > 0 && tracked < record.stats.count
        }.count
        return VStack(alignment: .leading, spacing: 3) {
            Text("Dates: \(range)")
            Text("Points: \(points) saved · outcomes on \(GamePlanText.percent(withOutcome, of: points))")
            if !competitions.isEmpty { Text("Competition: \(competitions)") }
            Text("Notes: \(noteMatchIDs.count) on selected matches")
            if scoreOnly > 0 || partial > 0 {
                Text("Coverage: \(scoreOnly) score only · \(partial) partially tracked")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("game-plan-selection-summary")
    }

    // MARK: - Filters

    @ViewBuilder
    private var filters: some View {
        Toggle("From", isOn: $choices.useFromDate)
        if choices.useFromDate {
            DatePicker("From date", selection: $choices.fromDate, displayedComponents: .date)
        }
        Toggle("Through", isOn: $choices.useThroughDate)
        if choices.useThroughDate {
            DatePicker("Through date", selection: $choices.throughDate, displayedComponents: .date)
        }
        ForEach(availableCompetitions) { competition in
            Toggle(competition.label, isOn: Binding(
                get: { choices.competitionFilter?.contains(competition) ?? true },
                set: { isOn in
                    var set = choices.competitionFilter ?? Set(availableCompetitions)
                    if isOn { set.insert(competition) } else { set.remove(competition) }
                    choices.competitionFilter = set == Set(availableCompetitions) ? nil : set
                }
            ))
        }
    }

    // MARK: - Exclusions

    /// The full disclosure of what was left out and why.
    static func exclusionsText(_ c: GamePlanCandidates) -> String? {
        var parts: [String] = []
        if !c.excludedDoubles.isEmpty {
            parts.append("\(GamePlanText.plural(c.excludedDoubles.count, "doubles match", "doubles matches")) left out: this version prepares singles, and team points can’t show one opponent’s pattern.")
        }
        if !c.excludedInProgress.isEmpty {
            parts.append("\(GamePlanText.plural(c.excludedInProgress.count, "unfinished match", "unfinished matches")) left out.")
        }
        if c.untaggedSinglesCount > 0 {
            parts.append("\(GamePlanText.plural(c.untaggedSinglesCount, "singles match", "singles matches")) in your archive have no opponent tagged and can’t be used until tagged in Match Info.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// One line for the main screen: "Left out: 2 doubles · 1 unfinished."
    /// Untagged archive matches aren't about this opponent, so they're only
    /// explained on the Matches screen.
    static func shortExclusionsText(_ c: GamePlanCandidates) -> String? {
        var parts: [String] = []
        if !c.excludedDoubles.isEmpty { parts.append("\(c.excludedDoubles.count) doubles") }
        if !c.excludedInProgress.isEmpty { parts.append("\(c.excludedInProgress.count) unfinished") }
        return parts.isEmpty ? nil : "Left out: \(parts.joined(separator: " · "))."
    }
}
