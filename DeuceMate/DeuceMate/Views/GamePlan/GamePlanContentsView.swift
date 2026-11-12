// GamePlanContentsView.swift — what the pack quotes beyond the match data,
// pushed from Prepare Game Plan's Includes row: player names, the opponent's
// Playing Style notes and the selected matches' private notes.
//
// All three start ON: the player prepares this pack for their own AI app and
// wrote the notes as scouting for exactly this. Any note can be left out with
// Choose Notes, and the Includes summary on the main screen states what is in
// before anything is copied or shared. Health data is never included.
import SwiftUI
import DeuceMateCore

struct GamePlanContentsView: View {
    @Binding var includeNames: Bool
    @Binding var includePlayingNotes: Bool
    @Binding var includeNotes: Bool
    /// Notes the player chose to leave out, by match.
    @Binding var notesLeftOut: Set<UUID>
    let hasPlayingNotes: Bool
    let notesUnreadable: Bool
    /// Private notes on the selected matches, newest match first.
    let notes: [GamePlanNotesReviewView.Item]

    @State private var showNotesReview = false

    private var includedNoteCount: Int { notes.filter { !notesLeftOut.contains($0.matchID) }.count }

    var body: some View {
        List {
            Section {
                Toggle("Player names", isOn: $includeNames)
                    .accessibilityIdentifier("game-plan-include-names")
                if hasPlayingNotes {
                    Toggle("Playing style notes", isOn: $includePlayingNotes)
                        .accessibilityIdentifier("game-plan-include-playing-notes")
                }
                if notesUnreadable {
                    Label("Private notes couldn’t be read, so none can be included. Your notes haven’t been changed.",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("game-plan-notes-unreadable")
                } else if !notes.isEmpty {
                    Toggle("Private notes", isOn: $includeNotes)
                        .accessibilityIdentifier("game-plan-include-notes")
                    if includeNotes {
                        Button {
                            showNotesReview = true
                        } label: {
                            LabeledContent("Choose Notes", value: "\(includedNoteCount) of \(notes.count)")
                        }
                        .accessibilityIdentifier("game-plan-choose-notes")
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(MatchExportDisclosure.namesCaption(isOn: includeNames, forAI: true))
                    if (includePlayingNotes && hasPlayingNotes) || (includeNotes && !notes.isEmpty && !notesUnreadable) {
                        Text("Notes are quoted exactly as written and may mention names or health.")
                    }
                    if includeNotes && !notes.isEmpty && !notesUnreadable && !includeNames {
                        Text(MatchExportDisclosure.namesOffNotesWarning)
                            .foregroundStyle(.orange)
                    }
                    Text("Heart rate, steps, calories and other Health data are never included.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Pack Contents")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showNotesReview) {
            GamePlanNotesReviewView(
                notes: notes,
                includeNames: includeNames,
                initiallyExcluded: notesLeftOut,
                onConfirm: { excluded in
                    // Keep choices for notes not on screen now (another selection).
                    notesLeftOut = notesLeftOut.subtracting(notes.map(\.matchID)).union(excluded)
                    showNotesReview = false
                },
                onCancel: { showNotesReview = false }
            )
        }
    }

    /// "Names · Style · 2 notes" — what the pack quotes, for the main screen.
    static func summary(includeNames: Bool, includePlayingNotes: Bool, hasPlayingNotes: Bool,
                        includeNotes: Bool, notesUnreadable: Bool, includedNoteCount: Int,
                        noteCount: Int) -> String {
        var parts = [includeNames ? "Names" : "No names"]
        if hasPlayingNotes { parts.append(includePlayingNotes ? "Style" : "No style") }
        if noteCount > 0 && !notesUnreadable {
            parts.append(includeNotes
                         ? GamePlanText.plural(includedNoteCount, "note")
                         : "No notes")
        }
        return parts.joined(separator: " · ")
    }
}
