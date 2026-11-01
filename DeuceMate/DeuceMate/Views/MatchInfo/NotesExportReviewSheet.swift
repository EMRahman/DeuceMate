// NotesExportReviewSheet.swift — the reviewable step before a private note is
// allowed into a report, an AI Coach prompt or a manual archive
// (MATCH_TAGS_PLAN.md §4.1, §8.1). It shows the EXACT text that will be
// included, states that it may hold personal or health information, and warns
// when player names are off but the note prose may still contain names. The
// opt-in only takes effect on "Include Note"; Cancel leaves it off.
import SwiftUI
import DeuceMateCore

struct NotesExportReviewSheet: View {
    let noteText: String
    /// Whether player names are currently included in the same export.
    let includeNames: Bool
    /// Where the note will go, in a phrase: "this report", "AI prompts".
    let destination: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(MatchExportDetails.quoted(noteText))
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .accessibilityIdentifier("notes-export-preview")
                        .accessibilityLabel("Note text that will be included: \(noteText)")
                } header: {
                    Text("This exact text will be included")
                } footer: {
                    Text("Shown as it will appear in \(destination). Paragraph breaks are kept.")
                }

                Section {
                    Label {
                        Text(MatchExportDisclosure.notesPersonalDataLine)
                    } icon: {
                        Image(systemName: "exclamationmark.shield")
                            .foregroundStyle(.orange)
                    }
                    .accessibilityIdentifier("notes-export-disclosure")

                    if !includeNames {
                        Label {
                            Text(MatchExportDisclosure.namesOffNotesWarning)
                        } icon: {
                            Image(systemName: "person.crop.circle.badge.questionmark")
                                .foregroundStyle(.orange)
                        }
                        .accessibilityIdentifier("notes-export-names-warning")
                    }
                } footer: {
                    Text("DeuceMate has no server and never receives it. The note stays on this iPhone; only the copy you share leaves.")
                }
            }
            .navigationTitle("Private Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .accessibilityIdentifier("cancel-include-note")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Include Note", action: onConfirm)
                        .accessibilityIdentifier("confirm-include-note")
                }
            }
        }
        .presentationDetents([.large])
    }
}
