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
    @State private var selectedMatchType: MatchType
    @State private var pickerSlot: Slot?
    @State private var managedTarget: ManagedTarget?
    @State private var saveError: String?
    @State private var showClearConfirmation = false
    @State private var showDiscardConfirmation = false
    @State private var originalTags: MatchTags?

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

    private enum ManagedTarget: Hashable, Identifiable {
        case roster(UUID)
        case draftSlot(Slot)

        var id: String {
            switch self {
            case .roster(let playerID): return "roster-\(playerID.uuidString)"
            case .draftSlot(let slot): return "draft-\(slot.id)"
            }
        }
    }

    init(record: MatchRecord) {
        self.record = record
        _selectedMatchType = State(initialValue: record.matchType)
        let tags = record.tags
        let opponentCount = record.matchType == .doubles ? 2 : 1
        let normalizedTags = tags?.sanitized()
        _originalTags = State(initialValue: normalizedTags.map {
            MatchTags(
                opponents: Array($0.opponents.prefix(opponentCount)),
                partner: record.matchType == .doubles ? $0.partner : nil,
                competitionTypeRaw: $0.competitionTypeRaw,
                updatedAt: $0.updatedAt
            )
        })
        _competition = State(initialValue: tags?.competitionType)
        _unknownCompetitionRaw = State(initialValue: tags?.competitionType == nil ? tags?.competitionTypeRaw : nil)
        var initial: [TaggedPlayer?] = [nil, nil]
        if let opps = tags?.opponents {
            for (index, player) in opps.prefix(2).enumerated() {
                initial[index] = player
            }
        }
        _opponents = State(initialValue: initial)
        _partner = State(initialValue: tags?.partner)
    }

    private var isDoubles: Bool { selectedMatchType == .doubles }

    /// The draft as tags (clock fields are stamped by the store on save).
    private var draft: MatchTags {
        MatchTags(
            opponents: Array(opponents.prefix(isDoubles ? 2 : 1)).compactMap { $0 },
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
        if !record.isInProgress && selectedMatchType != record.matchType {
            return true
        }
        let stored = originalTags ?? MatchTags(competitionTypeRaw: nil, updatedAt: .distantPast)
        let current = draft.sanitized()
        return current.opponents != stored.opponents
            || current.partner != stored.partner
            || current.competitionTypeRaw != stored.competitionTypeRaw
    }

    private var droppedDraftPlayers: [TaggedPlayer] {
        var dropped: [TaggedPlayer] = []
        if let partner {
            dropped.append(partner)
        }
        if opponents.count > 1, let secondOpponent = opponents[1] {
            dropped.append(secondOpponent)
        }
        return dropped
    }

    private var matchTypeFooterText: String {
        if selectedMatchType == .singles {
            let dropped = droppedDraftPlayers
            if !dropped.isEmpty {
                let names = dropped.map(\.name).joined(separator: " and ")
                return "Saving as Singles keeps all scores and stats, and removes \(names) from Match Info."
            }
        }
        return "Change between Singles and Doubles if the wrong match type was selected. Scores, point stats and health data are kept."
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
                    ForEach(0..<(isDoubles ? 2 : 1), id: \.self) { index in
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

                if !record.isInProgress {
                    Section {
                        Picker("Match Type", selection: $selectedMatchType) {
                            Text("Singles").tag(MatchType.singles)
                            Text("Doubles").tag(MatchType.doubles)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("match-type-picker")
                    } header: {
                        Text("Match Type")
                    } footer: {
                        Text(matchTypeFooterText)
                    }
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
                    Button("Cancel") { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveDraft() }
                        .disabled(!hasChanges)
                        .accessibilityIdentifier("save-match-info")
                }
            }
            .navigationDestination(item: $pickerSlot) { slot in
                PlayerPickerView(
                    title: pickerTitle(for: slot),
                    excludedIDs: excludedIDs(for: slot),
                    onMerged: handleMerge
                ) { picked in
                    assign(picked, to: slot)
                    pickerSlot = nil
                }
            }
            .navigationDestination(item: $managedTarget) { target in
                switch target {
                case .roster(let playerID):
                    PlayerManageView(playerID: playerID, onMerged: handleMerge)
                        .environmentObject(syncService)
                case .draftSlot(let slot):
                    DraftPlayerManageView(player: slotBinding(for: slot))
                }
            }
            .confirmationDialog(
                "Clear match details?",
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear Details", role: .destructive) {
                    clearDetails()
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
        .confirmationDialog(
            "Discard unsaved changes?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Keep Editing", role: .cancel) {}
            Button("Discard Changes", role: .destructive) { dismiss() }
        } message: {
            Text("Your changes to Match Info haven't been saved.")
        }
        .protectDraftDismissal(
            isDirty: Binding(get: { self.hasChanges }, set: { _ in }),
            isDiscardPromptPresented: $showDiscardConfirmation
        )
        .onReceive(store.$history) { history in
            reconcileWithStore(history: history, forgotten: store.forgottenPlayerLedger())
        }
        .onReceive(store.$forgottenPlayers) { forgotten in
            reconcileWithStore(history: store.history, forgotten: forgotten)
        }
    }

    // MARK: - Competition

    @ViewBuilder
    private var competitionSection: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading),
                                     count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
                ForEach(CompetitionType.allCases) { type in
                    Button {
                        competition = competition == type ? nil : type
                        unknownCompetitionRaw = nil
                    } label: {
                        HStack(spacing: 8) {
                            Text(type.displayLabel)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: competition == type ? "checkmark.circle.fill" : "circle")
                        }
                        .padding(.horizontal, 10)
                        .frame(minHeight: 44)
                        .padding(.vertical, 4)
                        .background(competition == type ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(competition == type ? Color.accentColor : Color.primary)
                    .accessibilityLabel(type.displayLabel)
                    .accessibilityAddTraits(competition == type ? .isSelected : [])
                    .accessibilityIdentifier("competition-\(type.rawValue)")
                }
            }
        } header: {
            Text("Competition Type")
        } footer: {
            if unknownCompetitionRaw != nil && competition == nil {
                Text("This match has a competition type from a newer version of DeuceMate. It's kept unless you choose another.")
            }
        }
    }

    // MARK: - Players

    @ViewBuilder
    private func playerRow(player: TaggedPlayer?, slot: Slot, addTitle: String) -> some View {
        if let player {
            HStack {
                Button {
                    manage(player, in: slot)
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.tint)
                        .imageScale(.large)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Manage \(player.name)")
                .accessibilityIdentifier("manage-slot-\(slot.id)")
                Text(player.name)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
            VStack(alignment: .leading, spacing: 10) {
                if isDoubles {
                    Text(pickerTitle(for: slot))
                        .font(.subheadline.weight(.semibold))
                }
                let recent = PlayerRoster.entries(from: store.history, forgotten: store.forgottenPlayers)
                    .filter { !excludedIDs(for: slot).contains($0.id) }
                    .prefix(4)
                if !recent.isEmpty {
                    Text("Recent players")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [dynamicTypeSize.isAccessibilitySize
                        ? GridItem(.flexible(), alignment: .leading)
                        : GridItem(.adaptive(minimum: 120), alignment: .leading)], spacing: 8) {
                        ForEach(Array(recent)) { entry in
                            Button {
                                assign(entry.taggedPlayer, to: slot)
                            } label: {
                                Text(entry.name)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tint)
                            .contextMenu {
                                Button {
                                    managedTarget = .roster(entry.id)
                                } label: {
                                    Label("Manage Player", systemImage: "person.crop.circle")
                                }
                            }
                            .accessibilityLabel("Use \(entry.name) as \(pickerTitle(for: slot).lowercased())")
                            .accessibilityIdentifier("recent-\(slot.id)-\(entry.name)")
                        }
                    }
                }
                Button {
                    pickerSlot = slot
                } label: {
                    Label("Search or add player…", systemImage: "magnifyingglass")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(pickerTitle(for: slot)), search or add player")
                .accessibilityIdentifier(addTitle)
            }
        }
    }

    private func pickerTitle(for slot: Slot) -> String {
        switch slot {
        case .partner: return "Partner"
        case .opponent(let index): return isDoubles ? "Opponent \(index + 1)" : "Opponent"
        }
    }

    /// Players already placed in another slot can't be picked twice.
    private func excludedIDs(for slot: Slot) -> Set<UUID> {
        if !isDoubles {
            // In singles, only opponent(0) is visible, so no other slot blocks it.
            return []
        }
        var ids = Set(opponents.prefix(2).compactMap { $0?.id })
        if let partner { ids.insert(partner.id) }
        switch slot {
        case .partner:
            if let partner { ids.remove(partner.id) }
        case .opponent(let index):
            if opponents.indices.contains(index), let current = opponents[index] {
                ids.remove(current.id)
            }
        }
        return ids
    }

    private func assign(_ player: TaggedPlayer?, to slot: Slot) {
        switch slot {
        case .partner:
            partner = player
        case .opponent(let index):
            if opponents.indices.contains(index) {
                opponents[index] = player
            }
            if !isDoubles, let playerID = player?.id {
                if partner?.id == playerID {
                    partner = nil
                }
                if opponents.count > 1, opponents[1]?.id == playerID {
                    opponents[1] = nil
                }
            }
        }
    }

    private func slotBinding(for slot: Slot) -> Binding<TaggedPlayer?> {
        Binding(
            get: {
                switch slot {
                case .partner: return partner
                case .opponent(let index): return opponents.indices.contains(index) ? opponents[index] : nil
                }
            },
            set: { assign($0, to: slot) }
        )
    }

    private func manage(_ player: TaggedPlayer, in slot: Slot) {
        let isRosterPlayer = PlayerRoster
            .entries(from: store.history, forgotten: store.forgottenPlayers)
            .contains { $0.id == player.id }
        managedTarget = isRosterPlayer ? .roster(player.id) : .draftSlot(slot)
    }

    private func handleMerge(_ duplicateID: UUID, _ kept: TaggedPlayer) {
        reconcileWithStore(
            history: store.loadHistory(),
            forgotten: store.forgottenPlayerLedger(),
            merged: (duplicateID, kept)
        )
    }

    private func reconcileWithStore(
        history: [MatchRecord],
        forgotten: ForgottenPlayerLedger,
        merged: (duplicateID: UUID, kept: TaggedPlayer)? = nil
    ) {
        let reconciledDraft = PlayerRoster.reconcilingEditorSlots(
            partner: partner,
            opponents: opponents,
            in: history,
            forgotten: forgotten,
            merged: merged
        )
        partner = reconciledDraft.partner
        var reconciledOpponents = reconciledDraft.opponents
        while reconciledOpponents.count < 2 {
            reconciledOpponents.append(nil)
        }
        opponents = Array(reconciledOpponents.prefix(2))

        if let original = originalTags {
            let reconciledOriginal = PlayerRoster.reconcilingEditorSlots(
                partner: original.partner,
                opponents: original.opponents.map { Optional($0) },
                in: history,
                forgotten: forgotten,
                merged: merged
            )
            originalTags = MatchTags(
                opponents: reconciledOriginal.opponents.compactMap { $0 },
                partner: record.matchType == .doubles ? reconciledOriginal.partner : nil,
                competitionTypeRaw: original.competitionTypeRaw,
                updatedAt: original.updatedAt,
                revisionID: original.revisionID
            ).sanitized()
        }
    }

    // MARK: - Save

    private func saveDraft() {
        let previousRecord = store.history.first(where: { $0.id == record.id }) ?? record
        let typeChange: MatchType? = (!record.isInProgress && selectedMatchType != previousRecord.matchType)
            ? selectedMatchType
            : nil
        do {
            let saved = try store.updateMatchDetails(
                id: record.id,
                matchType: typeChange,
                tags: draft
            )
            if saved.matchTypeRevision != previousRecord.matchTypeRevision {
                syncService.pushMatchTypeUpdates(forMatchIDs: [record.id])
            }
            if saved.tags != previousRecord.tags {
                syncService.pushTagUpdates(forMatchIDs: [record.id])
            }
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func clearDetails() {
        do {
            try store.updateTags(id: record.id, tags: MatchTags(competitionTypeRaw: nil, updatedAt: Date()))
            syncService.pushTagUpdates(forMatchIDs: [record.id])
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func cancel() {
        if hasChanges {
            showDiscardConfirmation = true
        } else {
            dismiss()
        }
    }
}

private struct DraftPlayerManageView: View {
    @Binding var player: TaggedPlayer?

    @State private var nameDraft = ""
    @State private var didInitialize = false

    var body: some View {
        Group {
            if let current = player {
                Form {
                    Section {
                        TextField("Name", text: $nameDraft)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("rename-player-field")
                            .onChange(of: nameDraft) { _, value in
                                if value.count > MatchTags.maxNameLength {
                                    nameDraft = String(value.prefix(MatchTags.maxNameLength))
                                }
                                let sanitized = MatchTags.sanitizedName(nameDraft)
                                if !sanitized.isEmpty {
                                    player?.name = sanitized
                                }
                            }
                    } header: {
                        Text("Name")
                    }

                    Section {
                        Picker("Handedness", selection: Binding(
                            get: { current.handednessRaw ?? "" },
                            set: { player?.handednessRaw = $0.isEmpty ? nil : $0 }
                        )) {
                            Text("Not specified").tag("")
                            ForEach(PlayerHandedness.allCases) { option in
                                Text(option.displayLabel).tag(option.rawValue)
                            }
                        }
                        .accessibilityIdentifier("player-handedness-picker")

                        Picker("Backhand", selection: Binding(
                            get: { current.backhandRaw ?? "" },
                            set: { player?.backhandRaw = $0.isEmpty ? nil : $0 }
                        )) {
                            Text("Not specified").tag("")
                            ForEach(PlayerBackhand.allCases) { option in
                                Text(option.displayLabel).tag(option.rawValue)
                            }
                        }
                        .accessibilityIdentifier("player-backhand-picker")

                        Picker("Play Style", selection: Binding(
                            get: { current.playStyleRaw ?? "" },
                            set: { player?.playStyleRaw = $0.isEmpty ? nil : $0 }
                        )) {
                            Text("Not specified").tag("")
                            ForEach(PlayerPlayStyle.allCases) { option in
                                Text(option.displayLabel).tag(option.rawValue)
                            }
                        }
                        .accessibilityIdentifier("player-play-style-picker")
                    } header: {
                        Text("Playing Style")
                    } footer: {
                        Text("Saved with this match when you tap Save in Match Info.")
                    }
                }
                .onAppear {
                    if !didInitialize {
                        nameDraft = current.name
                        didInitialize = true
                    }
                }
            } else {
                ContentUnavailableView("Player Removed", systemImage: "person.crop.circle.badge.xmark")
            }
        }
        .navigationTitle(player?.name ?? "Player")
        .navigationBarTitleDisplayMode(.inline)
    }
}
