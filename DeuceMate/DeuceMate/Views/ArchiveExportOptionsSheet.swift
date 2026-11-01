// ArchiveExportOptionsSheet.swift — the review step before Settings > Backup &
// Transfer > Export Match Archive writes a file. It carries the existing
// "this archive is full-fidelity" disclosure and the separate, default-OFF
// "Include private notes" opt-in with an exact preview of every note that
// would be written (MATCH_TAGS_PLAN.md §4.1, §8.1).
import SwiftUI
import DeuceMateCore

struct ArchiveExportOptionsSheet: View {
    struct NoteLine: Identifiable {
        let note: MatchNote
        let matchDate: Date
        var id: UUID { note.matchID }
    }

    /// The existing archive disclosure (health fields when present).
    let baseMessage: String
    /// Every non-empty note that belongs to a match in the archive.
    let notes: [NoteLine]
    let onExport: (_ includeNotes: Bool) -> Void
    let onCancel: () -> Void

    @State private var includeNotes = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(baseMessage)
                        .accessibilityIdentifier("archive-export-message")
                } footer: {
                    Text("Archive files include the player names you added.")
                }

                Section {
                    if notes.isEmpty {
                        Text("You have no private notes on archived matches.")
                            .foregroundStyle(.secondary)
                    } else {
                        Toggle("Include private notes", isOn: $includeNotes)
                            .accessibilityIdentifier("archive-include-notes")
                    }
                } header: {
                    Text("Private Notes")
                } footer: {
                    if !notes.isEmpty {
                        Text(includeNotes
                             ? "Notes are written to the file in a separate section. Importing the file on another iPhone restores them to that iPhone's private notes."
                             : "Off by default. Private notes stay on this iPhone unless you include them.")
                    }
                }

                if includeNotes && !notes.isEmpty {
                    Section {
                        Label {
                            Text(MatchExportDisclosure.notesPersonalDataLine)
                        } icon: {
                            Image(systemName: "exclamationmark.shield").foregroundStyle(.orange)
                        }
                        .accessibilityIdentifier("archive-notes-disclosure")
                    }
                    Section {
                        ForEach(notes) { line in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Self.dateFormatter.string(from: line.matchDate))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(MatchExportDetails.quoted(line.note.text))
                                    .font(.footnote.monospaced())
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text("These \(notes.count == 1 ? "note" : "\(notes.count) notes") will be included")
                    }
                }
            }
            .navigationTitle("Export Match Archive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") { onExport(includeNotes && !notes.isEmpty) }
                        .accessibilityIdentifier("archive-export-confirm")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
