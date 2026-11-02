// PlayerPickerView.swift — choose an opponent/partner from the roster derived
// from the archive, or add a new one (MATCH_TAGS_PLAN.md §5).
//
// Search runs Core's `PlayerRoster.suggestions`: an existing name that matches
// the typed text case-insensitively is offered FIRST, so picking it is the
// easy path and a duplicate "Alex" is never minted by accident. Typed names
// are capped at `MatchTags.maxNameLength` characters.
import SwiftUI
import DeuceMateCore

struct PlayerPickerView: View {
    let title: String
    /// Players already placed elsewhere in this match.
    let excludedIDs: Set<UUID>
    var onMerged: ((_ duplicateID: UUID, _ kept: TaggedPlayer) -> Void)? = nil
    let onPick: (TaggedPlayer) -> Void

    private struct ManagedPlayer: Identifiable, Hashable {
        let id: UUID
    }

    @EnvironmentObject private var store: PhoneStatsStore
    @EnvironmentObject private var syncService: PhoneMatchSyncService
    @State private var query = ""
    @State private var managedPlayer: ManagedPlayer?

    private static let lastPlayedFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private var roster: [RosterEntry] {
        PlayerRoster.entries(from: store.history, forgotten: store.forgottenPlayers)
            .filter { !excludedIDs.contains($0.id) }
    }

    private var sanitizedQuery: String { MatchTags.sanitizedName(query) }

    var body: some View {
        let entries = roster
        let suggestions = PlayerRoster.suggestions(query, in: entries)
        let existing = PlayerRoster.existingEntry(named: query, in: entries)
        List {
            if sanitizedQuery.isEmpty {
                if entries.isEmpty {
                    Section {
                        Text("Type a name above to add your first player.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Recent Players") {
                        ForEach(entries) { entry in rosterRow(entry) }
                    }
                }
            } else {
                if !suggestions.isEmpty {
                    Section(existing != nil ? "Existing Player" : "Matching Players") {
                        ForEach(suggestions) { entry in rosterRow(entry) }
                    }
                }
                Section {
                    Button {
                        onPick(TaggedPlayer(id: UUID(), name: sanitizedQuery))
                    } label: {
                        Label(
                            existing != nil
                                ? "Add another “\(sanitizedQuery)” as new player"
                                : "Add “\(sanitizedQuery)” as new player",
                            systemImage: "person.crop.circle.badge.plus"
                        )
                    }
                    .accessibilityIdentifier("add-new-player")
                } footer: {
                    if existing != nil {
                        Text("“\(existing?.name ?? "")” is already a player. Pick them above unless this is a different person.")
                    }
                }
            }
            Section {
            } footer: {
                Text("Tip: first names or nicknames are enough. Up to \(MatchTags.maxNameLength) characters.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Name, e.g. Alex"
        )
        .autocorrectionDisabled()
        .textInputAutocapitalization(.words)
        .onChange(of: query) { _, newValue in
            if newValue.count > MatchTags.maxNameLength {
                query = String(newValue.prefix(MatchTags.maxNameLength))
            }
        }
        .navigationDestination(item: $managedPlayer) { target in
            PlayerManageView(playerID: target.id, onMerged: onMerged)
                .environmentObject(syncService)
        }
    }

    private func rosterRow(_ entry: RosterEntry) -> some View {
        HStack(spacing: 12) {
            Button {
                onPick(entry.taggedPlayer)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .foregroundStyle(.primary)
                    Text("\(entry.matchCount == 1 ? "1 match" : "\(entry.matchCount) matches") · last \(Self.lastPlayedFormatter.string(from: entry.lastPlayed))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("roster-player-\(entry.name)")

            Button {
                managedPlayer = ManagedPlayer(id: entry.id)
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.tint)
                    .imageScale(.large)
                    .frame(minWidth: 36, minHeight: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Manage \(entry.name)")
            .accessibilityIdentifier("manage-player-\(entry.name)")
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                managedPlayer = ManagedPlayer(id: entry.id)
            } label: {
                Label("Manage", systemImage: "person.crop.circle")
            }
            .tint(.accentColor)
        }
    }
}
