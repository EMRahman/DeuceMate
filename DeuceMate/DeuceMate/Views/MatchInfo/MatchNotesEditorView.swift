// MatchNotesEditorView.swift — private notes for one match (MATCH_TAGS_PLAN.md
// §4.1). Multiline, up to `MatchNotesPolicy.maxLength` characters, paragraph
// breaks kept. Typing autosaves after a short pause, and any remaining text is
// saved on Done and when the app leaves the foreground. The sheet can't be
// swiped away while any text is unsaved, and if a save fails Done asks whether
// to keep editing or discard. Notes are stored only on this iPhone, excluded from device and
// iCloud backups, and persist independently of match details (tags).
import SwiftUI
import DeuceMateCore

struct MatchNotesEditorView: View {
    let matchID: UUID

    /// The pause in typing before a save, and so also how long swipe-down
    /// stays blocked after the last keystroke. Done saves straight away.
    private static let autosaveDelay: Duration = .milliseconds(500)

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var notesStore: MatchNotesStore = .shared
    @State private var draft: String
    @State private var saveError: String?
    @State private var showDeleteConfirmation = false
    @State private var showSaveFailedConfirmation = false
    @State private var showStorageInfo = false
    @State private var isDiscarding = false
    @FocusState private var isEditorFocused: Bool

    init(matchID: UUID) {
        self.matchID = matchID
        _draft = State(initialValue: MatchNotesStore.shared.note(for: matchID)?.text ?? "")
    }

    private var savedText: String { notesStore.note(for: matchID)?.text ?? "" }
    private var isUnavailable: Bool { notesStore.loadFailure != nil }
    private var hasUnsavedText: Bool { MatchNotesPolicy.sanitizedText(draft) != savedText }

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
                        } else if !isUnavailable {
                            Text("Changes save automatically.")
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
                    dismissKeyboardAndSave()
                }

                Button {
                    dismissKeyboardAndSave()
                    showStorageInfo = true
                } label: {
                    Label("Privacy and storage", systemImage: "info.circle")
                        .font(.footnote)
                }
                .accessibilityIdentifier("private-note-storage")

                if !savedText.isEmpty && !isUnavailable {
                    Button(role: .destructive) {
                        dismissKeyboardAndSave()
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
                        dismissKeyboardAndSave()
                    }
            )
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
        // A save that first runs in onDisappear can't keep the sheet open if it
        // fails, so swipe-down waits for the text to be saved. Done is always
        // available, and it stays open with choices if its save fails.
        .interactiveDismissDisabled(hasUnsavedText)
    }

    private func dismissKeyboardAndSave() {
        if isEditorFocused {
            isEditorFocused = false
        }
        saveIfNeeded()
    }

    /// Writes the draft if it differs from the stored note (empty text clears
    /// it). Returns `false` only when a needed write failed; the draft stays on
    /// screen and the footer shows why.
    @discardableResult
    private func saveIfNeeded() -> Bool {
        guard !isDiscarding, !isUnavailable else { return true }
        guard hasUnsavedText else {
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
