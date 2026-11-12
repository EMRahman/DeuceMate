// GamePlanUpcomingView.swift — the next match against this opponent, pushed
// from Prepare Game Plan's first row: a new match (competition, format, date)
// or finishing one of the unfinished matches from its saved score.
//
// Everything arrives pre-filled from the previous match against the opponent
// (`GamePlanUpcomingMatch(prefilledFrom:)`); an unfinished previous match is
// the match to finish. The summary on the main screen keeps the statement
// visible, so a wrong guess is never hidden.
import SwiftUI
import DeuceMateCore

struct GamePlanUpcomingView: View {
    @Binding var upcoming: GamePlanUpcomingMatch
    @Binding var hasDate: Bool
    @Binding var date: Date
    /// Start time of the match the values were pre-filled from, if any.
    let prefilledFrom: Date?
    /// Unfinished matches against this opponent, newest first.
    let unfinished: [MatchRecord]

    private var finishing: MatchRecord? {
        unfinished.first { $0.id == upcoming.finishingMatchID }
    }

    var body: some View {
        List {
            if !unfinished.isEmpty {
                Section {
                    Picker("Next match", selection: Binding(
                        get: { finishing?.id },
                        set: { id in choose(id) }
                    )) {
                        Text("New match").tag(UUID?.none)
                        ForEach(unfinished) { record in
                            Text("Finish \(Self.shortDay(record.startTime)) · \(GamePlanEvidence.checkpointScoreLabel(record))")
                                .tag(Optional(record.id))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .accessibilityIdentifier("game-plan-next-match")
                } header: {
                    Text("Next Match")
                } footer: {
                    Text(finishing == nil
                         ? "Or pick an unfinished match to get a plan for finishing it from its saved score."
                         : "The plan reads the saved score, what went well and what hurt so far, and how to close the match out. That match is always included as evidence.")
                }
            }

            Section {
                if let finishing {
                    LabeledContent("Competition", value: GamePlanCompetition(record: finishing).label)
                    LabeledContent("Format", value: GamePlanText.formatLabel(finishing.matchFormat))
                } else {
                    Picker("Competition", selection: $upcoming.competition) {
                        Text("Not set").tag(CompetitionType?.none)
                        ForEach(CompetitionType.allCases) { type in
                            Text(type.displayLabel).tag(Optional(type))
                        }
                    }
                    .accessibilityIdentifier("game-plan-competition")
                    Picker("Format", selection: $upcoming.format) {
                        Text("Not set").tag(MatchFormat?.none)
                        ForEach(GamePlanText.selectableFormats, id: \.self) { format in
                            Text(GamePlanText.formatLabel(format)).tag(Optional(format))
                        }
                    }
                    .accessibilityIdentifier("game-plan-format")
                }
                Toggle(finishing == nil ? "Set a date" : "Set a resume date", isOn: $hasDate)
                if hasDate {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if finishing != nil {
                        Text("Competition and format are the unfinished match’s own.")
                    } else {
                        if let prefilledFrom {
                            Text("Filled in from your previous match against this opponent (\(GamePlanView.dayFormatter.string(from: prefilledFrom))). Change anything that’s different this time.")
                        }
                        Text("Your own statements, not tracked data. The plan leads with matches of the same competition type.")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Upcoming Match")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Switching to an unfinished match states that match's own competition
    /// and format; switching back to a new match keeps them as a starting point.
    private func choose(_ id: UUID?) {
        upcoming.finishingMatchID = id
        guard let record = unfinished.first(where: { $0.id == id }) else { return }
        let prefill = GamePlanUpcomingMatch(prefilledFrom: record)
        upcoming.competition = prefill.competition
        upcoming.format = prefill.format
    }

    private static let shortDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f
    }()

    static func shortDay(_ date: Date) -> String { shortDayFormatter.string(from: date) }

    /// "Finish 3 Nov · 6–4 2–3", "League · Best of 3 · 14 Nov 2026", or "Not set".
    static func summary(_ upcoming: GamePlanUpcomingMatch, date: Date?, finishing: MatchRecord?) -> String {
        if let finishing {
            return "Finish \(shortDay(finishing.startTime)) · \(GamePlanEvidence.checkpointScoreLabel(finishing))"
        }
        if upcoming.competition == nil && upcoming.format == nil && date == nil { return "Not set" }
        var parts = [
            upcoming.competition?.displayLabel ?? "Competition not set",
            upcoming.format.map(GamePlanText.formatLabel) ?? "Format not set",
        ]
        if let date { parts.append(GamePlanView.dayFormatter.string(from: date)) }
        return parts.joined(separator: " · ")
    }
}
