import SwiftUI
import DeuceMateCore

struct OpponentsView: View {
    @EnvironmentObject private var store: PhoneStatsStore
    @EnvironmentObject private var syncService: PhoneMatchSyncService
    @State private var searchText = ""

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private var opponents: [RosterEntry] {
        PlayerRoster.suggestions(
            searchText,
            in: OpponentDirectory.entries(from: store.history, forgotten: store.forgottenPlayers)
        )
    }

    var body: some View {
        List {
            if opponents.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView(
                        "No Opponents Yet",
                        systemImage: "person.2",
                        description: Text("Add opponent names in Match Info after a match, and they’ll appear here.")
                    )
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            } else {
                ForEach(opponents) { opponent in
                    NavigationLink {
                        OpponentDetailView(opponentID: opponent.id)
                            .environmentObject(syncService)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(opponent.name)
                                .foregroundStyle(.primary)
                            Text("\(PlayersSettingsView.matchCount(opponent.matchCount)) · last \(Self.dateFormatter.string(from: opponent.lastPlayed))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("opponent-row-\(opponent.id.uuidString)")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Opponents")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search opponents")
    }
}

private struct OpponentDetailView: View {
    let opponentID: UUID

    @EnvironmentObject private var store: PhoneStatsStore
    @EnvironmentObject private var syncService: PhoneMatchSyncService
    @State private var selectedMatch: MatchRecord?
    @State private var notesExpanded = false

    /// Condensed playing style: centred chips (display only) and notes (tap → expand).
    @ViewBuilder
    private func playingStyleSection(for opponent: RosterEntry) -> some View {
        let chips = [
            opponent.handedness?.displayLabel,
            opponent.backhand.map { "\($0.displayLabel) backhand" },
            opponent.playStyle?.displayLabel
        ].compactMap { $0 }
        let notes = opponent.playingNotes

        Section {
            if chips.isEmpty && notes == nil {
                NavigationLink {
                    PlayerManageView(playerID: opponentID)
                        .environmentObject(syncService)
                } label: {
                    Text("Add handedness, backhand, style or notes")
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("opponent-edit-playing-style")
            } else {
                if !chips.isEmpty {
                    // Display only: editing lives behind the toolbar gear
                    // (`opponent-manage-player`), so no row chevron here.
                    ChipFlowLayout(spacing: 6) {
                        ForEach(chips, id: \.self) { chip in
                            Text(chip)
                                .font(.subheadline)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("opponent-playing-style-chips")
                }
                if let notes {
                    Button {
                        withAnimation { notesExpanded.toggle() }
                    } label: {
                        Text(notes)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(notesExpanded ? nil : 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(notesExpanded ? "Collapses the notes" : "Expands the notes")
                    .accessibilityIdentifier("opponent-playing-notes")
                }
            }
        }
    }

    private var roster: [RosterEntry] {
        PlayerRoster.entries(from: store.history, forgotten: store.forgottenPlayers)
    }

    private var opponent: RosterEntry? {
        OpponentDirectory.entries(from: store.history, forgotten: store.forgottenPlayers)
            .first { $0.id == opponentID }
    }

    private var doublesMatchups: [Matchup] {
        OpponentDirectory.doublesMatchups(vs: opponentID, in: store.history)
    }

    /// Match history membership is based on the opposition tags only. A player
    /// appearing as the partner must not make a match an opponent result.
    private var opponentMatches: [MatchRecord] {
        store.history
            .filter { $0.tags?.opponents.contains(where: { $0.id == opponentID }) == true }
            .sorted {
                return MatchChronology.newestFirst($0, $1)
            }
    }

    private var pendingMatches: [MatchRecord] { opponentMatches.filter(\.isInProgress) }
    private var completedMatches: [MatchRecord] { opponentMatches.filter { !$0.isInProgress } }

    var body: some View {
        Group {
            if let opponent {
                List {
                    playingStyleSection(for: opponent)

                    Section("Head to Head · Singles") {
                        headToHeadRow(HeadToHead.record(vs: opponentID, in: store.history, excluding: nil, matchType: .singles))
                    }

                    if !doublesMatchups.isEmpty {
                        Section {
                            ForEach(doublesMatchups, id: \.self) { matchup in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(teamLabel(for: matchup))
                                        .font(.headline)
                                    headToHeadRow(HeadToHead.record(for: matchup, in: store.history, excluding: nil))
                                }
                                .padding(.vertical, 3)
                            }
                        } header: {
                            Text("Head to Head · Doubles")
                        } footer: {
                            Text("Each row uses the same partner and exact opponent pair. Matches with incomplete player tags are not grouped.")
                        }
                    }

                    if hasIncompleteDoublesTags {
                        Section {
                            Text("Some doubles matches are missing player tags, so they can’t be assigned to a specific team matchup.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        NavigationLink {
                            GamePlanView(opponentID: opponentID)
                                .environmentObject(store)
                        } label: {
                            Label("Prepare Game Plan", systemImage: "list.bullet.clipboard")
                        }
                        .accessibilityIdentifier("opponent-prepare-game-plan")
                    } footer: {
                        Text("Build an evidence pack from your singles matches against \(opponent.name) to ask an AI app for a pre-match plan.")
                    }

                    if !pendingMatches.isEmpty {
                        Section("Pending Matches") {
                            ForEach(pendingMatches) { record in matchRow(record) }
                        }
                    }

                    Section("Past Matches") {
                        if completedMatches.isEmpty {
                            Text("No completed matches yet")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(completedMatches) { record in matchRow(record) }
                        }
                    }
                }
                .accessibilityIdentifier("opponent-detail")
                .navigationTitle(opponent.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            PlayerManageView(playerID: opponentID)
                                .environmentObject(syncService)
                        } label: {
                            Image(systemName: "gear")
                        }
                        .accessibilityLabel("Rename or Manage Player")
                        .accessibilityIdentifier("opponent-manage-player")
                    }
                }
            } else {
                ContentUnavailableView("Opponent Removed", systemImage: "person.crop.circle.badge.xmark")
                    .accessibilityIdentifier("opponent-detail")
            }
        }
        // Keep the presenter mounted across opponent updates. A sheet attached
        // to the conditional List can disappear during a row tap/re-render.
        .sheet(item: $selectedMatch) { selected in
            NavigationStack {
                if let current = store.history.first(where: { $0.id == selected.id }) {
                    MatchDetailView(record: current)
                        .environmentObject(syncService)
                        .environmentObject(store)
                } else {
                    ContentUnavailableView("Match Removed", systemImage: "trash")
                }
            }
        }
        .onReceive(store.$history) { history in
            if let selectedMatch, !history.contains(where: { $0.id == selectedMatch.id }) {
                self.selectedMatch = nil
            }
        }
    }

    private func matchRow(_ record: MatchRecord) -> some View {
        Button { selectedMatch = record } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(MatchChronology.caption(record, formatter: Self.dateFormatter))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let score = scoreLabel(for: record) {
                        Text(score)
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                    HStack(spacing: 8) {
                        Text(record.isInProgress ? "In Progress" : resultLabel(for: record))
                            .font(.caption.weight(.semibold))
                        Text("\(record.matchType == .doubles ? "Doubles" : "Singles") · \(formatLabel(for: record))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("opponent-match-\(record.id.uuidString)")
    }

    private func scoreLabel(for record: MatchRecord) -> String? {
        guard !record.setScores.isEmpty else { return nil }
        var parts = record.setScores.enumerated().map { index, set in
            SetScoreLabel.string(for: set, setIndex: index, matchFormat: record.matchFormat)
        }
        if record.isInProgress,
           record.matchFormat.config.playRegularSets,
           record.setScores.last?.isTieBreak == false,
           let game = MatchRecord.gameScoreString(mePoints: record.currentPointsMe, oppPoints: record.currentPointsOpponent) {
            parts.append("(\(game))")
        }
        return parts.joined(separator: "  ")
    }

    private func resultLabel(for record: MatchRecord) -> String {
        guard let won = record.iWon else { return "Draw" }
        return won ? "Won" : "Lost"
    }

    private func formatLabel(for record: MatchRecord) -> String {
        return switch record.matchFormat {
        case .standard: "Best of 3"
        case .bestOf3FullFinalSet: "Best of 3 (Full Final Set)"
        case .superTiebreak: "Super Tiebreak"
        case .perpetualSuperTiebreak: "Perpetual Tiebreak"
        case .quick4Games: "Quick 4 Games"
        case .shortSets: "Short Sets"
        case .fast4: "FAST4"
        case .perpetualPoints: "Perpetual Points"
        }
    }

    private var hasIncompleteDoublesTags: Bool {
        store.history.contains { record in
            record.matchType == .doubles
                && (record.tags?.opponents.contains { $0.id == opponentID } ?? false)
                && Matchup(record: record) == nil
        }
    }

    private func teamLabel(for matchup: Matchup) -> String {
        let names = Dictionary(uniqueKeysWithValues: roster.map { ($0.id, $0.name) })
        let opposingNames = matchup.opponentIDs
            .sorted { $0.uuidString < $1.uuidString }
            .compactMap { names[$0] }
        let partner = matchup.partnerID.flatMap { names[$0] } ?? "Unknown partner"
        return "vs \(opposingNames.joined(separator: " & ")) · with \(partner)"
    }

    @ViewBuilder
    private func headToHeadRow(_ record: HeadToHeadRecord) -> some View {
        if record.played == 0 {
            Text("No completed matches yet")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(record.wins) \(record.wins == 1 ? "win" : "wins") · \(record.losses) \(record.losses == 1 ? "loss" : "losses") · \(record.draws) \(record.draws == 1 ? "draw" : "draws")")
                    .accessibilityLabel("Head to head, completed matches: \(record.wins) wins, \(record.losses) losses, \(record.draws) draws")
                Text(MatchComparisonFormat.headToHeadSummary(record))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let lastPlayed = record.lastPlayed {
                    Text("Last played \(Self.dateFormatter.string(from: lastPlayed))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

/// Wrapping row of small chips, each row centred; wraps onto extra lines at
/// large text sizes.
private struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(in: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(in: bounds.width, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func arrange(in width: CGFloat, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        // First pass: break subviews into rows.
        var rows: [[(index: Int, size: CGSize)]] = [[]]
        var x: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            // Cap each chip at the row width so an oversized label wraps its
            // text instead of overflowing (accessibility Dynamic Type sizes).
            let size = subview.sizeThatFits(ProposedViewSize(width: width.isFinite ? width : nil, height: nil))
            if x > 0, x + size.width > width {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append((index, size))
            x += size.width + spacing
        }

        // Second pass: centre each row within the available width.
        let rowWidths = rows.map { row in
            row.reduce(0) { $0 + $1.size.width } + spacing * CGFloat(max(row.count - 1, 0))
        }
        let maxRowWidth = rowWidths.max() ?? 0
        let containerWidth = width.isFinite ? width : maxRowWidth
        var frames = [CGRect](repeating: .zero, count: subviews.count)
        var y: CGFloat = 0
        for (row, rowWidth) in zip(rows, rowWidths) where !row.isEmpty {
            var rowX = max((containerWidth - rowWidth) / 2, 0)
            let rowHeight = row.map(\.size.height).max() ?? 0
            for item in row {
                frames[item.index] = CGRect(origin: CGPoint(x: rowX, y: y), size: item.size)
                rowX += item.size.width + spacing
            }
            y += rowHeight + spacing
        }
        let height = max(y - spacing, 0)
        return (frames, CGSize(width: containerWidth, height: height))
    }
}
