// PlayersSettingsView.swift — Settings → Players: the roster derived from the
// archive, with Rename, Merge duplicates and Forget player (MATCH_TAGS_PLAN.md
// §5, §6.2). Each action (`PlayerRosterActions`) is one serialized
// `PhoneStatsStore` mutation followed — only once it is on disk — by tag
// pushes for the affected matches the watch holds (§6.1 reconciliation
// catches any it misses). Forgetting also writes the forgotten-player ledger,
// so stale watch copies, backups and archives can't bring the name back. A
// failed save changes nothing: the screen stays open and shows an alert.
import SwiftUI
import DeuceMateCore

struct PlayersSettingsView: View {
    @EnvironmentObject private var syncService: PhoneMatchSyncService
    @ObservedObject private var store: PhoneStatsStore = .shared

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        let entries = PlayerRoster.entries(from: store.history, forgotten: store.forgottenPlayers)
        List {
            if entries.isEmpty {
                Section {
                    Text("No players yet. Add an opponent or partner from a match's Match Info, and they'll appear here.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(entries) { entry in
                        NavigationLink {
                            PlayerManageView(playerID: entry.id)
                                .environmentObject(syncService)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name)
                                Text("\(Self.matchCount(entry.matchCount)) · last \(Self.dateFormatter.string(from: entry.lastPlayed))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("player-row-\(entry.name)")
                    }
                } footer: {
                    Text("Players come from your matches. Renaming or merging updates every match; forgetting removes a player from every match.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Players")
        .navigationBarTitleDisplayMode(.inline)
    }

    static func matchCount(_ count: Int) -> String {
        count == 1 ? "1 match" : "\(count) matches"
    }
}

// MARK: - One player

struct PlayerManageView: View {
    let playerID: UUID
    var onMerged: ((_ duplicateID: UUID, _ kept: TaggedPlayer) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var syncService: PhoneMatchSyncService
    @ObservedObject private var store: PhoneStatsStore = .shared
    @ObservedObject private var notesStore: MatchNotesStore = .shared

    @FocusState private var isNameFocused: Bool
    @State private var newName = ""
    @State private var handednessDraft = ""
    @State private var backhandDraft = ""
    @State private var playStyleDraft = ""
    @State private var notesDraft = ""
    @FocusState private var isNotesFocused: Bool
    @State private var didInitializeDetailsDraft = false
    @State private var showMergePicker = false
    @State private var pendingMerge: RosterEntry?
    @State private var showForgetConfirmation = false
    @State private var errorMessage: String?
    @State private var nameSaveFailure: String?
    @State private var showNotesLeaveConfirmation = false
    @State private var showClearNotesConfirmation = false

    private var entries: [RosterEntry] {
        PlayerRoster.entries(from: store.history, forgotten: store.forgottenPlayers)
    }

    private var entry: RosterEntry? { entries.first { $0.id == playerID } }

    private var hasUnsavedName: Bool {
        guard let entry else { return false }
        let sanitized = MatchTags.sanitizedName(newName)
        return !sanitized.isEmpty && sanitized != entry.name
    }

    private var hasUnsavedNotes: Bool {
        guard didInitializeDetailsDraft, let entry else { return false }
        return TaggedPlayer.sanitizedPlayingNotes(notesDraft) != entry.playingNotes
    }

    /// Saving now would delete notes that exist, so it is confirmed first.
    private var notesDraftClearsSavedNotes: Bool {
        guard let entry else { return false }
        return entry.playingNotes != nil && TaggedPlayer.sanitizedPlayingNotes(notesDraft) == nil
    }

    /// Typed text that hasn't reached the archive yet (name or playing notes).
    private var hasUnsavedText: Bool { hasUnsavedName || hasUnsavedNotes }

    /// Matches mentioning this player that carry a private note — notes can
    /// mention the person in prose, which forgetting cannot reliably remove.
    private var affectedNoteIDs: Set<UUID> {
        let mentioning = Set(store.history.filter { $0.tags?.playerIDs.contains(playerID) ?? false }.map(\.id))
        return Set(notesStore.notes.values.filter { !$0.isCleared && mentioning.contains($0.matchID) }.map(\.matchID))
    }

    var body: some View {
        Group {
            if let entry {
                form(for: entry)
            } else {
                ContentUnavailableView("Player Removed", systemImage: "person.crop.circle.badge.xmark")
            }
        }
        .navigationTitle(entry?.name ?? "Player")
        .navigationBarTitleDisplayMode(.inline)
        // On the Group, not the form: after a forget whose note deletion
        // failed the form is already replaced by "Player Removed".
        .alert(
            "Something Went Wrong",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        // While a typed name is unsaved, this Back replaces the system one (which
        // also turns off swipe-back) so a failed save can keep the screen open.
        .navigationBarBackButtonHidden(hasUnsavedText)
        .toolbar {
            if hasUnsavedText {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        if hasUnsavedNotes {
                            showNotesLeaveConfirmation = true
                        } else {
                            saveAndLeave()
                        }
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .accessibilityLabel("Back")
                    .accessibilityIdentifier("player-manage-back")
                }
            }
        }
        .alert(
            "Couldn't Save Changes",
            isPresented: Binding(get: { nameSaveFailure != nil }, set: { if !$0 { nameSaveFailure = nil } })
        ) {
            Button("Keep Editing", role: .cancel) {}
            Button("Discard Change", role: .destructive) {
                if let entry {
                    newName = entry.name
                    notesDraft = entry.playingNotes ?? ""
                }
                dismiss()
            }
        } message: {
            Text(nameSaveFailure ?? "")
        }
        .confirmationDialog(
            notesDraftClearsSavedNotes ? "Delete these notes?" : "Save changes to notes?",
            isPresented: $showNotesLeaveConfirmation,
            titleVisibility: .visible
        ) {
            if notesDraftClearsSavedNotes {
                Button("Delete Notes", role: .destructive) { leaveSavingNotes() }
            } else {
                Button("Save Notes") { leaveSavingNotes() }
            }
            Button(notesDraftClearsSavedNotes ? "Keep Saved Notes" : "Discard Changes",
                   role: notesDraftClearsSavedNotes ? nil : .destructive) {
                leaveDiscardingNotes()
            }
            // Not `role: .cancel`: iOS 26+ hides a cancel button when this dialog
            // shows as a popover, leaving the destructive choices on their own.
            Button("Keep Editing") {}
        } message: {
            Text(notesDraftClearsSavedNotes
                 ? "The notes field is empty. Deleting removes this player's saved notes and can't be undone."
                 : "Your changes to this player's notes haven't been saved.")
        }
        .confirmationDialog(
            "Delete these notes?",
            isPresented: $showClearNotesConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Notes", role: .destructive) { saveNotes() }
            Button("Keep Notes") {}
        } message: {
            Text("This removes this player's saved notes and can't be undone.")
        }
        // A sheet holding this screen can't be swiped away with unsaved notes;
        // Back asks instead.
        .interactiveDismissDisabled(hasUnsavedNotes)
        // The fallback when a parent closes this screen, such as its sheet being
        // dismissed. The store ignores a player already merged away or forgotten.
        .onDisappear { saveNameIfChanged() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveNameIfChanged() }
        }
    }

    @ViewBuilder
    private func form(for entry: RosterEntry) -> some View {
        Form {
            Section {
                TextField("Name", text: $newName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("rename-player-field")
                    .submitLabel(.done)
                    .focused($isNameFocused)
                    .onSubmit { saveNameIfChanged() }
                    .onChange(of: isNameFocused) { _, focused in
                        if !focused { saveNameIfChanged() }
                    }
                    .onChange(of: newName) { _, value in
                        if value.count > MatchTags.maxNameLength {
                            newName = String(value.prefix(MatchTags.maxNameLength))
                        }
                    }
            } header: {
                Text("Name")
            } footer: {
                Text("Saves automatically and updates all \(PlayersSettingsView.matchCount(entry.matchCount)) with this player.")
            }

            Section {
                Picker("Handedness", selection: $handednessDraft) {
                    Text("Not specified").tag("")
                    ForEach(PlayerHandedness.allCases) { option in
                        Text(option.displayLabel).tag(option.rawValue)
                    }
                    if let raw = entry.handednessRaw, PlayerHandedness(rawValue: raw) == nil {
                        Text("Other (\(raw))").tag(raw)
                    }
                }
                .accessibilityIdentifier("player-handedness-picker")

                Picker("Backhand", selection: $backhandDraft) {
                    Text("Not specified").tag("")
                    ForEach(PlayerBackhand.allCases) { option in
                        Text(option.displayLabel).tag(option.rawValue)
                    }
                    if let raw = entry.backhandRaw, PlayerBackhand(rawValue: raw) == nil {
                        Text("Other (\(raw))").tag(raw)
                    }
                }
                .accessibilityIdentifier("player-backhand-picker")

                Picker("Play Style", selection: $playStyleDraft) {
                    Text("Not specified").tag("")
                    ForEach(PlayerPlayStyle.allCases) { option in
                        Text(option.displayLabel).tag(option.rawValue)
                    }
                    if let raw = entry.playStyleRaw, PlayerPlayStyle(rawValue: raw) == nil {
                        Text("Other (\(raw))").tag(raw)
                    }
                }
                .accessibilityIdentifier("player-play-style-picker")

                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField(
                        "e.g. strong first serve; a lot of pace",
                        text: $notesDraft,
                        axis: .vertical
                    )
                    .lineLimit(2...6)
                    .focused($isNotesFocused)
                    .accessibilityIdentifier("player-playing-notes-field")
                    .onChange(of: notesDraft) { _, value in
                        if value.count > TaggedPlayer.maxPlayingNotesLength {
                            notesDraft = String(value.prefix(TaggedPlayer.maxPlayingNotesLength))
                        }
                    }
                    // Notes are saved only by Save Notes, so a cleared field
                    // can never delete them just by losing focus.
                    if hasUnsavedNotes {
                        HStack {
                            Button("Revert") { revertNotes() }
                                .accessibilityIdentifier("player-notes-revert")
                            Spacer()
                            Button(notesDraftClearsSavedNotes ? "Delete Notes" : "Save Notes") {
                                if notesDraftClearsSavedNotes {
                                    showClearNotesConfirmation = true
                                } else {
                                    saveNotes()
                                }
                            }
                            .fontWeight(.semibold)
                            .foregroundStyle(notesDraftClearsSavedNotes ? Color.red : Color.accentColor)
                            .accessibilityIdentifier("player-notes-save")
                        }
                        // Two buttons in one Form row: each must take only its own taps.
                        .buttonStyle(.borderless)
                        .padding(.top, 4)
                    }
                }
            } header: {
                Text("Playing Style")
            } footer: {
                Text("Handedness, backhand and play style save automatically; notes save when you tap Save Notes. Optional tennis profile and notes are shown on the opponent detail screen. The profile is included in AI Coach match context. Notes are used only in an Opponent Game Plan, and you can turn them off there.")
            }

            Section {
                Button("Merge Duplicate Into…") { showMergePicker = true }
                    .disabled(entries.count < 2)
                    .accessibilityIdentifier("merge-player")
            } footer: {
                Text("If the same person was added twice, merge this entry into the other one. Every match then uses that player.")
            }

            Section {
                Button("Forget Player", role: .destructive) { showForgetConfirmation = true }
                    .accessibilityIdentifier("forget-player")
            } footer: {
                Text("Removes \(entry.name) from every match on this iPhone and, when it holds those matches, your Apple Watch. Scores are kept.")
            }
        }
        .onAppear {
            if newName.isEmpty { newName = entry.name }
            if !didInitializeDetailsDraft {
                loadDetailsDraft(from: entry)
                didInitializeDetailsDraft = true
            }
        }
        .onChange(of: handednessDraft) { saveDetailsIfChanged() }
        .onChange(of: backhandDraft) { saveDetailsIfChanged() }
        .onChange(of: playStyleDraft) { saveDetailsIfChanged() }
        .onDisappear {
            // Best-effort fallback for the pickers when a parent closes this
            // screen. Unsaved notes are never written here: they only save on
            // Save Notes, and Back and swipe-down ask while they're unsaved.
            try? persistDetails(includingNotes: false)
        }
        .sheet(isPresented: $showMergePicker) {
            mergePicker(for: entry)
        }
        .confirmationDialog(
            pendingMerge.map { "Merge “\(entry.name)” into “\($0.name)”?" } ?? "",
            isPresented: Binding(get: { pendingMerge != nil }, set: { if !$0 { pendingMerge = nil } }),
            titleVisibility: .visible,
            presenting: pendingMerge
        ) { kept in
            Button("Merge") { merge(into: kept) }
            Button("Cancel", role: .cancel) {}
        } message: { kept in
            Text("Every match with “\(entry.name)” will use “\(kept.name)” instead. This can't be undone.")
        }
        .confirmationDialog(
            "Forget \(entry.name)?",
            isPresented: $showForgetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Forget Player", role: .destructive) { forget(deletingNotes: false) }
            let noteCount = affectedNoteIDs.count
            if noteCount > 0 {
                Button("Forget and Delete \(noteCount == 1 ? "1 Private Note" : "\(noteCount) Private Notes")", role: .destructive) {
                    forget(deletingNotes: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(forgetMessage(for: entry))
        }
    }

    private func forgetMessage(for entry: RosterEntry) -> String {
        var parts = [
            "\(entry.name) will be removed from \(PlayersSettingsView.matchCount(entry.matchCount)) on this iPhone, from your Apple Watch when it next syncs, and from the iCloud backup copy on its next successful upload. DeuceMate remembers only an anonymous ID so old copies can't bring the name back.",
            "Reports you already shared, earlier device backups, and match archive files exported before now can't be changed."
        ]
        let noteCount = affectedNoteIDs.count
        if noteCount > 0 {
            parts.append("\(noteCount == 1 ? "1 match with this player has" : "\(noteCount) matches with this player have") a private note that may mention them. Notes are kept unless you also delete them.")
        }
        return parts.joined(separator: "\n\n")
    }

    private func mergePicker(for entry: RosterEntry) -> some View {
        NavigationStack {
            List {
                Section {
                    ForEach(entries.filter { $0.id != entry.id }) { other in
                        Button {
                            showMergePicker = false
                            // Present the confirmation once the sheet has gone.
                            DispatchQueue.main.async { pendingMerge = other }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(other.name).foregroundStyle(.primary)
                                Text(PlayersSettingsView.matchCount(other.matchCount))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("merge-target-\(other.name)")
                    }
                } header: {
                    Text("Keep which player?")
                } footer: {
                    Text("“\(entry.name)” will be merged into the player you choose.")
                }
            }
            .navigationTitle("Merge Into")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showMergePicker = false }
                }
            }
        }
    }

    // MARK: - Actions

    private var actions: PlayerRosterActions {
        PlayerRosterActions(store: store, notesStore: notesStore, syncService: syncService)
    }

    private func loadDetailsDraft(from entry: RosterEntry) {
        handednessDraft = entry.handednessRaw ?? ""
        backhandDraft = entry.backhandRaw ?? ""
        playStyleDraft = entry.playStyleRaw ?? ""
        notesDraft = entry.playingNotes ?? ""
    }

    /// Autosaves a picked value. A failed save puts the pickers back to what is
    /// stored, so the screen never shows a value that wasn't saved.
    private func saveDetailsIfChanged() {
        do {
            try persistDetails(includingNotes: false)
        } catch {
            errorMessage = error.localizedDescription
            // Put the pickers back to what is stored; typed notes stay so the
            // player can retry.
            if let entry {
                handednessDraft = entry.handednessRaw ?? ""
                backhandDraft = entry.backhandRaw ?? ""
                playStyleDraft = entry.playStyleRaw ?? ""
            }
        }
    }

    /// Saves the picked profile. The notes draft is written only when
    /// `includingNotes` (Save Notes); otherwise the stored notes are kept as-is,
    /// so a picker change can't save half-typed or cleared notes.
    private func persistDetails(includingNotes: Bool) throws {
        guard didInitializeDetailsDraft, let entry else { return }
        let handedness = handednessDraft.isEmpty ? nil : handednessDraft
        let backhand = backhandDraft.isEmpty ? nil : backhandDraft
        let playStyle = playStyleDraft.isEmpty ? nil : playStyleDraft
        let notes = includingNotes ? TaggedPlayer.sanitizedPlayingNotes(notesDraft) : entry.playingNotes
        guard handedness != entry.handednessRaw
                || backhand != entry.backhandRaw
                || playStyle != entry.playStyleRaw
                || notes != entry.playingNotes else { return }
        try actions.updateDetails(
            playerID,
            handednessRaw: handedness,
            backhandRaw: backhand,
            playStyleRaw: playStyle,
            playingNotes: notes
        )
    }

    /// Save Notes. A failed save keeps the typed text so the player can retry.
    private func saveNotes() {
        let saved = TaggedPlayer.sanitizedPlayingNotes(notesDraft)
        do {
            try persistDetails(includingNotes: true)
            notesDraft = saved ?? ""
            isNotesFocused = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func revertNotes() {
        notesDraft = entry?.playingNotes ?? ""
        isNotesFocused = false
    }

    /// Autosaves the name when editing ends rather than on each keystroke,
    /// because a rename rewrites every match with this player and notifies the
    /// watch. A failed save keeps the typed text and retries when editing next ends.
    private func saveNameIfChanged() {
        do {
            try persistName()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Saves the name (and any picker change); Back only completes when that is
    /// durable, otherwise the screen stays open with the typed text. Unsaved
    /// notes never reach here: Back asks about them first.
    private func saveAndLeave() {
        do {
            try persistName()
            try persistDetails(includingNotes: false)
            dismiss()
        } catch {
            nameSaveFailure = error.localizedDescription
        }
    }

    /// Back → Save Notes (or Delete Notes): saves the name and the notes, and
    /// leaves only when both are durable.
    private func leaveSavingNotes() {
        do {
            try persistName()
            try persistDetails(includingNotes: true)
            dismiss()
        } catch {
            nameSaveFailure = error.localizedDescription
        }
    }

    /// Back → Discard Changes / Keep Saved Notes: drops the notes draft, then
    /// leaves as Back normally does (the name still autosaves).
    private func leaveDiscardingNotes() {
        revertNotes()
        saveAndLeave()
    }

    /// A blank name isn't a rename, so the field returns to the current one.
    private func persistName() throws {
        guard let entry else { return }
        let sanitized = MatchTags.sanitizedName(newName)
        guard !sanitized.isEmpty else {
            newName = entry.name
            return
        }
        guard sanitized != entry.name else { return }
        try actions.rename(playerID, to: sanitized)
        newName = sanitized
    }

    private func merge(into kept: RosterEntry) {
        pendingMerge = nil
        do {
            try actions.merge(playerID, into: kept.id)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        onMerged?(playerID, kept.taggedPlayer)
        dismiss()
    }

    private func forget(deletingNotes: Bool) {
        do {
            try actions.forget(playerID, deletingNotesFor: deletingNotes ? affectedNoteIDs : [])
        } catch {
            // Not saved ⇒ nothing changed and the player is still listed; a
            // notes failure ⇒ the player is gone ("Player Removed" shows
            // behind the alert). Either way, stay and say so.
            errorMessage = error.localizedDescription
            return
        }
        dismiss()
    }
}
