// MatchNotesEditorView.swift — private notes for one match (MATCH_TAGS_PLAN.md
// §4.1). Multiline, up to `MatchNotesPolicy.maxLength` characters, paragraph
// breaks kept. Typing autosaves after a short pause, and any remaining text is
// saved on Done, on swipe-down and when the app leaves the foreground. While
// saves are failing the sheet can't be swiped away, and Done asks whether to
// keep editing or discard. Notes are stored only on this iPhone, excluded from device and
// iCloud backups, and persist independently of match details (tags).
import SwiftUI
import DeuceMateCore

struct MatchNotesEditorView: View {
    let matchID: UUID

    /// The pause in typing before a save. Every way out of the editor saves
    /// straight away, so this only limits how often the file is rewritten.
    private static let autosaveDelay: Duration = .seconds(1)

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var notesStore: MatchNotesStore = .shared
    @State private var draft: String
    @State private var saveError: String?
    @State private var showDeleteConfirmation = false
    @State private var showSaveFailedConfirmation = false
    @State private var isDiscarding = false
    @FocusState private var isEditorFocused: Bool

    init(matchID: UUID) {
        self.matchID = matchID
        _draft = State(initialValue: MatchNotesStore.shared.note(for: matchID)?.text ?? "")
    }

    private var savedText: String { notesStore.note(for: matchID)?.text ?? "" }
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
                        if let saveError {
                            Label(saveError, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .accessibilityIdentifier("match-note-save-error")
                        } else if !isUnavailable {
                            Text("Changes save automatically.")
                        }
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { finish() }
                        .accessibilityIdentifier("done-match-note")
                }
            }
            .onChange(of: draft) { _, newValue in
                if newValue.count > MatchNotesPolicy.maxLength {
                    draft = String(newValue.prefix(MatchNotesPolicy.maxLength))
                }
            }
            // Restarts on each change, so it saves once typing pauses.
            .task(id: draft) {
                try? await Task.sleep(for: Self.autosaveDelay)
                guard !Task.isCancelled else { return }
                saveIfNeeded()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { saveIfNeeded() }
            }
            .onDisappear { saveIfNeeded() }
            .confirmationDialog(
                "Delete this note?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Note", role: .destructive) { deleteNote() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The note is removed from this iPhone. This can't be undone.")
            }
            .onAppear {
                if savedText.isEmpty && !isUnavailable { isEditorFocused = true }
            }
        }
        .confirmationDialog(
            "Couldn't save your note",
            isPresented: $showSaveFailedConfirmation,
            titleVisibility: .visible
        ) {
            // Not `role: .cancel`: iOS 26+ hides a cancel button when this dialog
            // shows as a popover, leaving Discard as the only visible choice.
            Button("Keep Editing") {}
            Button("Discard Changes", role: .destructive) {
                isDiscarding = true
                dismiss()
            }
        } message: {
            Text(saveError ?? "Your latest changes haven't been saved.")
        }
        // Swipe-down saves through onDisappear. While saves are failing it is
        // blocked, so the unsaved text can't be lost; Done offers the way out.
        .interactiveDismissDisabled(saveError != nil)
    }

    /// Writes the draft if it differs from the stored note (empty text clears
    /// it). Returns `false` only when a needed write failed; the draft stays on
    /// screen and the footer shows why.
    @discardableResult
    private func saveIfNeeded() -> Bool {
        guard !isDiscarding, !isUnavailable else { return true }
        guard MatchNotesPolicy.sanitizedText(draft) != savedText else {
            saveError = nil
            return true
        }
        do {
            try notesStore.save(text: draft, for: matchID)
            saveError = nil
            return true
        } catch {
            saveError = error.localizedDescription
            return false
        }
    }

    private func finish() {
        if saveIfNeeded() {
            dismiss()
        } else {
            showSaveFailedConfirmation = true
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
