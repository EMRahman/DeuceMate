// PlayersSettingsView.swift — Settings → Players: the roster derived from the
// archive, with Rename, Merge duplicates and Forget player (MATCH_TAGS_PLAN.md
// §5, §6.2). Each action is one serialized `PhoneStatsStore` mutation followed
// by tag pushes for the affected matches the watch holds (§6.1 reconciliation
// catches any it misses). Forgetting also writes the forgotten-player ledger,
// so stale watch copies, backups and archives can't bring the name back.
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

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var syncService: PhoneMatchSyncService
    @ObservedObject private var store: PhoneStatsStore = .shared
    @ObservedObject private var notesStore: MatchNotesStore = .shared

    @State private var newName = ""
    @State private var showMergePicker = false
    @State private var pendingMerge: RosterEntry?
    @State private var showForgetConfirmation = false
    @State private var errorMessage: String?

    private var entries: [RosterEntry] {
        PlayerRoster.entries(from: store.history, forgotten: store.forgottenPlayers)
    }

    private var entry: RosterEntry? { entries.first { $0.id == playerID } }

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
    }

    @ViewBuilder
    private func form(for entry: RosterEntry) -> some View {
        let sanitized = MatchTags.sanitizedName(newName)
        Form {
            Section {
                TextField("Name", text: $newName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("rename-player-field")
                    .onChange(of: newName) { _, value in
                        if value.count > MatchTags.maxNameLength {
                            newName = String(value.prefix(MatchTags.maxNameLength))
                        }
                    }
                Button("Rename") { rename(to: sanitized) }
                    .disabled(sanitized.isEmpty || sanitized == entry.name)
                    .accessibilityIdentifier("rename-player")
            } header: {
                Text("Name")
            } footer: {
                Text("Renaming updates all \(PlayersSettingsView.matchCount(entry.matchCount)) with this player.")
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
        .onAppear { if newName.isEmpty { newName = entry.name } }
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
        .alert(
            "Something Went Wrong",
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
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

    private func rename(to name: String) {
        let affected = store.renamePlayer(playerID, to: name)
        syncService.pushTagUpdates(forMatchIDs: affected)
    }

    private func merge(into kept: RosterEntry) {
        let affected = store.mergePlayers(playerID, into: kept.id)
        syncService.pushTagUpdates(forMatchIDs: affected)
        pendingMerge = nil
        dismiss()
    }

    private func forget(deletingNotes: Bool) {
        let noteIDs = affectedNoteIDs
        let affected = store.forgetPlayer(playerID)
        syncService.pushTagUpdates(forMatchIDs: affected)
        // Publication of the new ledger is asynchronous; re-scrub the mirror
        // once it has landed on the main queue.
        DispatchQueue.main.async { syncService.rescrubMirror() }
        if deletingNotes {
            do {
                try notesStore.removeNotes(for: noteIDs)
            } catch {
                errorMessage = "The player was forgotten, but their matches' private notes couldn't be deleted: \(error.localizedDescription)"
                return
            }
        }
        dismiss()
    }
}
