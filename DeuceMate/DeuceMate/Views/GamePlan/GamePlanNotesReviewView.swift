// GamePlanNotesReviewView.swift — read the exact private notes a game plan
// pack quotes, match by match, and leave any of them out. Notes are included
// by default; this sheet is where the player excludes one. Mirrors
// `NotesExportReviewSheet`'s disclosure: notes may contain personal or health
// information, and may name people even with player names off. Done applies
// the choices; Cancel changes nothing.
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
    /// Notes the player left out earlier; they start left out.
    let initiallyExcluded: Set<UUID>
    /// The notes now left out, by match.
    let onConfirm: (Set<UUID>) -> Void
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
            .navigationTitle("Choose Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onConfirm(excluded) }
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
