// MatchInfoEditorView.swift — the "Match Info" editor sheet: Competition Type,
// then opponent(s) and, for doubles, a partner picked from the roster.
//
// Saving goes through `PhoneStatsStore.updateTags`, which stamps the draft
// against the stored revision and merges it with `mergingTags` — the score and
// completion state are never touched, so an in-progress match stays in
// progress. A successful save is pushed to the watch when it holds the match.
import SwiftUI
import DeuceMateCore

struct MatchInfoEditorView: View {
    let record: MatchRecord

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var store: PhoneStatsStore
    @EnvironmentObject private var syncService: PhoneMatchSyncService

    @State private var competition: CompetitionType?
    /// Keeps an unknown future competition raw value when the user leaves it alone.
    @State private var unknownCompetitionRaw: String?
    @State private var partner: TaggedPlayer?
    @State private var opponents: [TaggedPlayer?]
    @State private var pickerSlot: Slot?
    @State private var saveError: String?
    @State private var showClearConfirmation = false

    /// Which player position the roster picker is filling.
    enum Slot: Hashable, Identifiable {
        case partner
        case opponent(Int)
        var id: String {
            switch self {
            case .partner: return "partner"
            case .opponent(let i): return "opponent-\(i)"
            }
        }
    }

    init(record: MatchRecord) {
        self.record = record
        let tags = record.tags
        _competition = State(initialValue: tags?.competitionType)
        _unknownCompetitionRaw = State(initialValue: tags?.competitionType == nil ? tags?.competitionTypeRaw : nil)
        let slots = record.matchType == .doubles ? 2 : 1
        var initial: [TaggedPlayer?] = Array(repeating: nil, count: slots)
        for (index, player) in (tags?.opponents ?? []).prefix(slots).enumerated() {
            initial[index] = player
        }
        _opponents = State(initialValue: initial)
        _partner = State(initialValue: record.matchType == .doubles ? tags?.partner : nil)
    }

    private var isDoubles: Bool { record.matchType == .doubles }

    /// The draft as tags (clock fields are stamped by the store on save).
    private var draft: MatchTags {
        MatchTags(
            opponents: opponents.compactMap { $0 },
            partner: isDoubles ? partner : nil,
            competitionTypeRaw: competition?.rawValue ?? unknownCompetitionRaw,
            updatedAt: Date()
        )
    }

    private var storedTags: MatchTags? {
        store.history.first(where: { $0.id == record.id })?.tags ?? record.tags
    }

    private var hasStoredDetails: Bool { !(storedTags?.isEmpty ?? true) }

    private var hasChanges: Bool {
        let stored = storedTags ?? MatchTags(competitionTypeRaw: nil, updatedAt: .distantPast)
        let current = draft.sanitized()
        return current.opponents != stored.opponents
            || current.partner != stored.partner
            || current.competitionTypeRaw != stored.competitionTypeRaw
    }

    var body: some View {
        NavigationStack {
            Form {
                competitionSection
                if isDoubles {
                    Section {
                        playerRow(player: partner, slot: .partner, addTitle: "Add partner")
                    } header: {
                        Text("Partner")
                    }
                }
                Section {
                    ForEach(opponents.indices, id: \.self) { index in
                        playerRow(
                            player: opponents[index],
                            slot: .opponent(index),
                            addTitle: isDoubles ? "Add opponent \(index + 1)" : "Add opponent"
                        )
                    }
                } header: {
                    Text(isDoubles ? "Opponents" : "Opponent")
                } footer: {
                    Text("First names or nicknames are enough — e.g. Alex. Names are saved with this match in your archive and its iCloud backup, and appear on your Apple Watch.")
                }

                if hasStoredDetails {
                    Section {
                        Button("Clear Match Details", role: .destructive) {
                            showClearConfirmation = true
                        }
                        .accessibilityIdentifier("clear-match-details")
                    } footer: {
                        Text("Removes the opponent, partner and competition type from this match only. The score and any private note are kept.")
                    }
                }
            }
            .navigationTitle("Match Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(draft) }
                        .disabled(!hasChanges)
                        .accessibilityIdentifier("save-match-info")
                }
            }
            .navigationDestination(item: $pickerSlot) { slot in
                PlayerPickerView(
                    title: pickerTitle(for: slot),
                    excludedIDs: excludedIDs(for: slot)
                ) { picked in
                    assign(picked, to: slot)
                    pickerSlot = nil
                }
            }
            .confirmationDialog(
                "Clear match details?",
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear Details", role: .destructive) {
                    save(MatchTags(competitionTypeRaw: nil, updatedAt: Date()))
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The opponent, partner and competition type are removed from this match on iPhone and, when it holds the match, Apple Watch.")
            }
            .alert(
                "Couldn't Save",
                isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    // MARK: - Competition

    @ViewBuilder
    private var competitionSection: some View {
        Section {
            // The four labels fit as segments at standard text sizes ("Not
            // set" is no segment selected, cleared from the header); the menu
            // keeps every choice readable at larger sizes.
            if dynamicTypeSize >= .xLarge {
                Picker("Competition Type", selection: $competition) {
                    Text("Not set").tag(CompetitionType?.none)
                    competitionOptions
                }
                .pickerStyle(.menu)
                .labelsHidden() // the section header already says it
                .accessibilityIdentifier("competition-type-picker")
            } else {
                Picker("Competition Type", selection: $competition) {
                    competitionOptions
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("competition-type-picker")
            }
        } header: {
            HStack {
                Text("Competition Type")
                Spacer()
                if competition != nil && dynamicTypeSize < .xLarge {
                    Button("Not Set") { competition = nil }
                        .font(.footnote)
                        .textCase(nil)
                        .accessibilityLabel("Set competition type to not set")
                        .accessibilityIdentifier("competition-not-set")
                }
            }
        } footer: {
            if unknownCompetitionRaw != nil && competition == nil {
                Text("This match has a competition type from a newer version of DeuceMate. It's kept unless you choose another.")
            }
        }
    }

    @ViewBuilder
    private var competitionOptions: some View {
        ForEach(CompetitionType.allCases) { type in
            Text(type.displayLabel).tag(CompetitionType?.some(type))
        }
    }

    // MARK: - Players

    @ViewBuilder
    private func playerRow(player: TaggedPlayer?, slot: Slot, addTitle: String) -> some View {
        if let player {
            HStack {
                Button {
                    pickerSlot = slot
                } label: {
                    // At accessibility sizes the name gets its own line rather
                    // than wrapping beside the icon and "Change".
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                        : AnyLayout(HStackLayout())
                    layout {
                        Text(player.name)
                            .foregroundStyle(.primary)
                        if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                        Text("Change")
                            .font(.subheadline)
                            .foregroundStyle(.tint)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(player.name), change")
                Button {
                    assign(nil, to: slot)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.large)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove \(player.name)")
            }
        } else {
            Button {
                pickerSlot = slot
            } label: {
                Label(addTitle, systemImage: "plus.circle.fill")
            }
        }
    }

    private func pickerTitle(for slot: Slot) -> String {
        switch slot {
        case .partner: return "Partner"
        case .opponent: return isDoubles ? "Opponent" : "Opponent"
        }
    }

    /// Players already placed in another slot can't be picked twice.
    private func excludedIDs(for slot: Slot) -> Set<UUID> {
        var ids = Set(opponents.compactMap { $0?.id })
        if let partner { ids.insert(partner.id) }
        switch slot {
        case .partner:
            if let partner { ids.remove(partner.id) }
        case .opponent(let index):
            if let current = opponents[index] { ids.remove(current.id) }
        }
        return ids
    }

    private func assign(_ player: TaggedPlayer?, to slot: Slot) {
        switch slot {
        case .partner: partner = player
        case .opponent(let index): opponents[index] = player
        }
    }

    // MARK: - Save

    private func save(_ tags: MatchTags) {
        do {
            try store.updateTags(id: record.id, tags: tags)
            syncService.pushTagUpdates(forMatchIDs: [record.id])
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
