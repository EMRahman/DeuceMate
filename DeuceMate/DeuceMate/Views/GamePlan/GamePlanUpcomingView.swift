// GamePlanUpcomingView.swift — the upcoming match's competition, format and
// date, pushed from Prepare Game Plan's first row. Competition and format
// arrive pre-filled from the previous match against the opponent
// (`GamePlanUpcomingMatch(prefilledFrom:)`); the summary on the main screen
// keeps that statement visible, so a wrong guess is never hidden.
import SwiftUI
import DeuceMateCore

struct GamePlanUpcomingView: View {
    @Binding var upcoming: GamePlanUpcomingMatch
    @Binding var hasDate: Bool
    @Binding var date: Date
    /// Start time of the match the values were pre-filled from, if any.
    let prefilledFrom: Date?

    var body: some View {
        List {
            Section {
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
                Toggle("Set a date", isOn: $hasDate)
                if hasDate {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let prefilledFrom {
                        Text("Filled in from your previous match against this opponent (\(GamePlanView.dayFormatter.string(from: prefilledFrom))). Change anything that’s different this time.")
                    }
                    Text("Your own statements, not tracked data. The plan leads with matches of the same competition type.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Upcoming Match")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// "League · Best of 3 · 14 Nov 2026", or "Not set".
    static func summary(_ upcoming: GamePlanUpcomingMatch, date: Date?) -> String {
        if upcoming.competition == nil && upcoming.format == nil && date == nil { return "Not set" }
        var parts = [
            upcoming.competition?.displayLabel ?? "Competition not set",
            upcoming.format.map(GamePlanText.formatLabel) ?? "Format not set",
        ]
        if let date { parts.append(GamePlanView.dayFormatter.string(from: date)) }
        return parts.joined(separator: " · ")
    }
}
