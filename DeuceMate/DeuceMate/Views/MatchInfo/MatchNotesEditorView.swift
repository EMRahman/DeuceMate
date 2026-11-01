// MatchNotesEditorView.swift — private notes for one match (MATCH_TAGS_PLAN.md
// §4.1). Multiline, up to `MatchNotesPolicy.maxLength` characters, paragraph
// breaks kept. Save and Cancel; a failed save keeps the draft open. Notes are
// stored only on this iPhone, excluded from device and iCloud backups, and
// persist independently of match details (tags).
import SwiftUI
import DeuceMateCore

struct MatchNotesEditorView: View {
    let matchID: UUID

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var notesStore: MatchNotesStore = .shared
    @State private var draft: String
    @State private var saveError: String?
    @State private var showDeleteConfirmation = false
    @FocusState private var isEditorFocused: Bool

    init(matchID: UUID) {
        self.matchID = matchID
        _draft = State(initialValue: MatchNotesStore.shared.note(for: matchID)?.text ?? "")
    }

    private var savedText: String { notesStore.note(for: matchID)?.text ?? "" }
    private var hasChanges: Bool { MatchNotesPolicy.sanitizedText(draft) != savedText }
    private var isUnavailable: Bool { notesStore.loadFailure != nil }

    var body: some View {
        NavigationStack {
            Form {
                if let failure = notesStore.loadFailure {
                    Section {
                        Label(failure, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                Section {
                    TextEditor(text: $draft)
                        .frame(minHeight: 180)
                        .focused($isEditorFocused)
                        .disabled(isUnavailable)
                        .accessibilityIdentifier("match-notes-editor")
                        .accessibilityLabel("Private note")
                        .overlay(alignment: .topLeading) {
                            if draft.isEmpty {
                                Text("Tactics, how you felt, what to try next time…")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Stored on this iPhone. Not backed up automatically.")
                            .fontWeight(.semibold)
                        Text("Private notes aren't synced to Apple Watch and aren't in the iCloud or device backup. They are never added to a shared report, AI Coach prompt or exported archive unless you choose Include Private Note when sharing. If you delete the app or move to a new iPhone, they don't come back.")
                        Text("\(draft.count) / \(MatchNotesPolicy.maxLength)")
                            .monospacedDigit()
                    }
                }

                if !savedText.isEmpty && !isUnavailable {
                    Section {
                        Button("Delete Note", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                        .accessibilityIdentifier("delete-match-note")
                    }
                }
            }
            .navigationTitle("Private Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(draft) }
                        .disabled(!hasChanges || isUnavailable)
                        .accessibilityIdentifier("save-match-note")
                }
            }
            .onChange(of: draft) { _, newValue in
                if newValue.count > MatchNotesPolicy.maxLength {
                    draft = String(newValue.prefix(MatchNotesPolicy.maxLength))
                }
            }
            .confirmationDialog(
                "Delete this note?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Note", role: .destructive) { save("") }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The note is removed from this iPhone. This can't be undone.")
            }
            .alert(
                "Couldn't Save Note",
                isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
            .onAppear {
                if savedText.isEmpty && !isUnavailable { isEditorFocused = true }
            }
        }
    }

    private func save(_ text: String) {
        do {
            try notesStore.save(text: text, for: matchID)
            dismiss()
        } catch {
            // Keep the draft open so nothing typed is lost.
            saveError = error.localizedDescription
        }
    }
}
