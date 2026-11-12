// MatchNotesEditorView.swift — private notes for one match (MATCH_TAGS_PLAN.md
// §4.1). Multiline, up to `MatchNotesPolicy.maxLength` characters, paragraph
// breaks kept. Nothing is written until Save: a stray edit or an emptied
// field can't silently replace or delete a note. Cancel and swipe-down ask
// before discarding unsaved changes, and saving an emptied note asks first
// (it deletes the note). Notes are stored only on this iPhone, excluded from
// device and iCloud backups, and persist independently of match details (tags).
import SwiftUI
import DeuceMateCore

struct MatchNotesEditorView: View {
    let matchID: UUID

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var notesStore: MatchNotesStore = .shared
    @State private var draft: String
    @State private var saveError: String?
    @State private var showDeleteConfirmation = false
    @State private var showDiscardConfirmation = false
    @State private var showStorageInfo = false
    @FocusState private var isEditorFocused: Bool

    init(matchID: UUID) {
        self.matchID = matchID
        _draft = State(initialValue: MatchNotesStore.shared.note(for: matchID)?.text ?? "")
    }

    private var savedText: String { notesStore.note(for: matchID)?.text ?? "" }
    private var isUnavailable: Bool { notesStore.loadFailure != nil }
    private var hasUnsavedText: Bool { MatchNotesPolicy.sanitizedText(draft) != savedText }
    /// Saving now would delete the stored note, so Save asks first.
    private var draftClearsSavedNote: Bool {
        !savedText.isEmpty && MatchNotesPolicy.sanitizedText(draft).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if let failure = notesStore.loadFailure {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }

                // The editor takes the remaining height and shrinks above the
                // keyboard, keeping the counter and bottom actions visible.
                TextEditor(text: $draft)
                    .focused($isEditorFocused)
                    .disabled(isUnavailable)
                    .accessibilityIdentifier("match-notes-editor")
                    .accessibilityLabel("Private note")
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.visible)
                    .scrollDismissesKeyboard(.interactively)
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(isEditorFocused ? Color.accentColor : Color(uiColor: .separator), lineWidth: isEditorFocused ? 1.5 : 1)
                            .allowsHitTesting(false)
                    )
                    .overlay(alignment: .topLeading) {
                        if draft.isEmpty {
                            Text("Tactics, how you felt, what to try next time…")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 16)
                                .padding(.horizontal, 13)
                                .allowsHitTesting(false)
                        }
                    }

                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        if let saveError {
                            Label(saveError, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .accessibilityIdentifier("match-note-save-error")
                        } else if hasUnsavedText && !isUnavailable {
                            Text("Unsaved changes. Tap Save to keep them.")
                                .accessibilityIdentifier("match-note-unsaved")
                        }
                    }
                    Spacer(minLength: 8)
                    Text("\(draft.count) / \(MatchNotesPolicy.maxLength.formatted())")
                        .monospacedDigit()
                        .fixedSize()
                        .accessibilityIdentifier("match-note-character-count")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissKeyboard()
                }

                Button {
                    dismissKeyboard()
                    showStorageInfo = true
                } label: {
                    Label("Privacy and storage", systemImage: "info.circle")
                        .font(.footnote)
                }
                .accessibilityIdentifier("private-note-storage")

                if !savedText.isEmpty && !isUnavailable {
                    Button(role: .destructive) {
                        dismissKeyboard()
                        showDeleteConfirmation = true
                    } label: {
                        Text("Delete Note")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .padding(.vertical, 4)
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("delete-match-note")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                Color(uiColor: .systemGroupedBackground)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissKeyboard()
                    }
            )
            .navigationTitle("Private Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancel() }
                        .accessibilityIdentifier("cancel-match-note")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!hasUnsavedText || isUnavailable)
                        .accessibilityIdentifier("save-match-note")
                }
            }
            .onChange(of: draft) { _, newValue in
                if newValue.count > MatchNotesPolicy.maxLength {
                    draft = String(newValue.prefix(MatchNotesPolicy.maxLength))
                }
            }
            .alert("Privacy and storage", isPresented: $showStorageInfo) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Stored on this iPhone. Not backed up automatically.\n\nPrivate notes aren't synced to Apple Watch and aren't in the iCloud or device backup. They are never added to a shared report, AI Coach prompt or exported archive unless you choose Include Private Note when sharing. If you delete the app or move to a new iPhone, they don't come back.")
            }
            .confirmationDialog(
                "Delete this note?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Note", role: .destructive) { deleteNote() }
                // Not `role: .cancel`, which iOS 26+ hides in popover dialogs.
                Button("Keep Note") {}
            } message: {
                Text("The note is removed from this iPhone. This can't be undone.")
            }
            .onAppear {
                if savedText.isEmpty && !isUnavailable { isEditorFocused = true }
            }
        }
        .confirmationDialog(
            "Discard changes to this note?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            // Not `role: .cancel`: iOS 26+ hides a cancel button when this dialog
            // shows as a popover, leaving Discard as the only visible choice.
            Button("Keep Editing") {}
            Button("Discard Changes", role: .destructive) { dismiss() }
        } message: {
            Text("Your changes haven't been saved.")
        }
        // Swipe-down can never discard unsaved text: the system block is what
        // guarantees it (the delegate hook alone didn't hold on iOS 27), and
        // where the hook is installed the attempt also asks, like Cancel.
        .interactiveDismissDisabled(hasUnsavedText && !isUnavailable)
        .protectDraftDismissal(
            isDirty: Binding(get: { self.hasUnsavedText && !self.isUnavailable }, set: { _ in }),
            isDiscardPromptPresented: $showDiscardConfirmation
        )
    }

    private func dismissKeyboard() {
        if isEditorFocused {
            isEditorFocused = false
        }
    }

    private func cancel() {
        if hasUnsavedText && !isUnavailable {
            dismissKeyboard()
            showDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    /// Writes the draft and closes. An emptied note is a deletion, so it is
    /// confirmed first. A failed write keeps the sheet open with the draft and
    /// shows why in the footer.
    private func save() {
        guard hasUnsavedText, !isUnavailable else { return }
        if draftClearsSavedNote {
            dismissKeyboard()
            showDeleteConfirmation = true
            return
        }
        do {
            try notesStore.save(text: draft, for: matchID)
            saveError = nil
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func deleteNote() {
        do {
            try notesStore.save(text: "", for: matchID)
            draft = ""
            saveError = nil
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
