// GamePlanNotesReviewView.swift — review the exact private notes a game plan
// pack would quote, match by match, and leave any of them out. Mirrors
// `NotesExportReviewSheet`'s disclosure: notes may contain personal or health
// information, and may name people even with player names off. Nothing is
// included until "Include Notes"; Cancel changes nothing.
import SwiftUI
import DeuceMateCore

struct GamePlanNotesReviewView: View {
    struct Item: Identifiable {
        var id: UUID { matchID }
        let matchID: UUID
        let title: String
        let text: String
    }

    let notes: [Item]
    let includeNames: Bool
    /// Notes the player left out in an earlier review; they start left out.
    /// Every other note starts included, because the player is reviewing it now.
    let initiallyExcluded: Set<UUID>
    /// The approved notes, as reviewed, by match.
    let onConfirm: ([UUID: String]) -> Void
    let onCancel: () -> Void

    @State private var excluded: Set<UUID> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        Text(MatchExportDisclosure.notesPersonalDataLine)
                    } icon: {
                        Image(systemName: "exclamationmark.shield")
                            .foregroundStyle(.orange)
                    }
                    if !includeNames {
                        Label {
                            Text(MatchExportDisclosure.namesOffNotesWarning)
                        } icon: {
                            Image(systemName: "person.crop.circle.badge.questionmark")
                                .foregroundStyle(.orange)
                        }
                    }
                } footer: {
                    Text("Each included note is quoted exactly as shown below, labelled as your observation rather than recorded data.")
                }

                ForEach(notes) { note in
                    Section {
                        Toggle("Include this note", isOn: Binding(
                            get: { !excluded.contains(note.matchID) },
                            set: { isOn in
                                if isOn { excluded.remove(note.matchID) } else { excluded.insert(note.matchID) }
                            }
                        ))
                        .accessibilityIdentifier("game-plan-note-toggle-\(note.matchID.uuidString)")
                        Text(MatchExportDetails.quoted(note.text))
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .foregroundStyle(excluded.contains(note.matchID) ? .secondary : .primary)
                            .accessibilityLabel("Note: \(note.text)")
                    } header: {
                        Text(note.title)
                    }
                }
            }
            .navigationTitle("Review Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Include Notes") {
                        var approved: [UUID: String] = [:]
                        for note in notes where !excluded.contains(note.matchID) {
                            approved[note.matchID] = note.text
                        }
                        onConfirm(approved)
                    }
                    .accessibilityIdentifier("game-plan-confirm-notes")
                }
            }
            .onAppear {
                excluded = initiallyExcluded.intersection(notes.map(\.matchID))
            }
        }
        .presentationDetents([.large])
    }
}
