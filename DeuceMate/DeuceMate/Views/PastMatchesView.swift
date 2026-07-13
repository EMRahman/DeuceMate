// PastMatchesView.swift — iPhone equivalent of the watch's MatchHistoryView.
import SwiftUI
import DeuceMateCore

/// Renders a score string with the tiebreak parenthetical (e.g. "(7-2)") as superscript.
/// The tiebreak paren is identified by being directly preceded by a digit, which
/// distinguishes it from a game-score paren like "(30-0)" that follows whitespace.
func styledScore(_ score: String, superSize: CGFloat) -> AttributedString {
    var result = AttributedString(score)
    var searchStart = result.startIndex
    while searchStart < result.endIndex,
          let openParen = result[searchStart...].range(of: "(") {
        let prevIdx = openParen.lowerBound
        if prevIdx > result.startIndex &&
           result.characters[result.characters.index(before: prevIdx)].isNumber {
            guard let closeParen = result[openParen.upperBound...].range(of: ")") else { break }
            let tbRange = openParen.lowerBound..<closeParen.upperBound
            result[tbRange].swiftUI.font = .system(size: superSize, weight: .bold).monospacedDigit()
            result[tbRange].swiftUI.baselineOffset = superSize * 0.45
            searchStart = closeParen.upperBound
        } else {
            searchStart = openParen.upperBound
        }
    }
    return result
}

struct PastMatchesView: View {
    @EnvironmentObject private var store: PhoneStatsStore
    @EnvironmentObject private var syncService: PhoneMatchSyncService
    @Environment(\.appTheme) private var theme
    @Environment(\.openURL) private var openURL

    @State private var selected: MatchRecord?
    @State private var showSettings = false
    @State private var showScoreboard = false
    @State private var showManualEntry = false
    @State private var showICloudGuide = false
    @State private var showRestorePrompt = false
    @State private var pendingDelete: PendingDelete?

    /// A match awaiting permanent-deletion confirmation. Permanent deletion is the
    /// one destructive action: it drops the phone's retained copy and, when the
    /// match is also on the watch, issues a watch-side delete — so it's gone
    /// everywhere. The everyday "Remove from Watch" only frees watch space (the
    /// iPhone keeps its copy) and is never routed here.
    private struct PendingDelete: Identifiable {
        let record: MatchRecord
        let onWatch: Bool
        var id: UUID { record.id }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            Group {
                if hasNoRows {
                    ScrollView {
                        emptyStateView
                            .padding(.top, 60)
                    }
                    .refreshable {
                        syncService.requestFullHistorySync()
                    }
                } else {
                    List {
                        // Compute archive data once at the top so both sections can
                        // reference pastRecords (e.g. the live-match footer needs it).
                        let archiveIDs = Set(store.history.map(\.id))
                        let activeID = syncService.activeMatchID
                        // Exclude permanently-deleted (tombstoned) ids: a queued watch
                        // delete may not have pruned the cached mirror yet, and a stale
                        // "On Apple Watch only" row must not let "Sync to iPhone" undo a
                        // permanent delete.
                        let watchOnly = syncService.isPaired
                            ? syncService.watchMirror.filter {
                                !archiveIDs.contains($0.id) && !store.tombstoneIDs.contains($0.id)
                              }
                            : []
                        // store.history is already newest-first; only combine and
                        // re-sort when there are watch-only rows (rare; ≤10), so the
                        // common path skips re-sorting the whole archive each render.
                        let pastRecords: [MatchRecord] = watchOnly.isEmpty
                            ? store.history.filter { $0.id != activeID }
                            : (store.history + watchOnly)
                                .filter { $0.id != activeID }
                                .sorted { $0.startTime > $1.startTime }

                        // Live Match section
                        if let liveRecord = store.history.first(where: { $0.id == activeID }) {
                            Section {
                                Button { selected = liveRecord } label: {
                                    rowView(for: liveRecord, location: rowLocation(for: liveRecord, inHistory: true))
                                }
                                .buttonStyle(.plain)
                                Button {
                                    showScoreboard = true
                                } label: {
                                    Label("Live Scoreboard", systemImage: "tv.fill")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(theme.colors.server)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 2)
                                }
                                .buttonStyle(.plain)
                            } header: {
                                Text("Live Match")
                            } footer: {
                                // Show iCloud status here only when there are no past
                                // records; otherwise it appears in the Past Matches footer.
                                if pastRecords.isEmpty {
                                    iCloudStatusLabel
                                        .font(.footnote)
                                }
                            }
                        }

                        // Past Matches — the phone archive plus matches still on the
                        // watch but removed from the phone (rendered from the watch
                        // mirror, badged "On Apple Watch only"). Mirror rows are
                        // hidden when no watch is paired.
                        if !pastRecords.isEmpty {
                            Section {
                                ForEach(pastRecords) { record in
                                    pastMatchRow(record, archiveIDs: archiveIDs)
                                }
                            } header: {
                                Text("Past Matches")
                            } footer: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(archiveFooterText)
                                    iCloudStatusLabel
                                }
                                .font(.footnote)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        syncService.requestFullHistorySync()
                    }
                }
            }
            .navigationTitle("Matches")
            .navigationBarTitleDisplayMode(.inline)
            .tint(theme.colors.me)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showManualEntry = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("Manual match entry")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(item: $selected) { record in
                NavigationStack {
                    MatchDetailView(record: record)
                        .environmentObject(syncService)
                        .environmentObject(store)
                }
            }
            .fullScreenCover(isPresented: $showScoreboard) {
                LiveScoreboardView()
                    .environmentObject(store)
                    .environmentObject(syncService)
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView()
                        .environmentObject(syncService)
                }
            }
            .sheet(isPresented: $showManualEntry) {
                ManualMatchEntryView()
                    .environmentObject(store)
                    .environmentObject(syncService)
            }
            .sheet(isPresented: $showICloudGuide) {
                iCloudGuideSheet
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .alert(
                "iCloud Backup Found",
                isPresented: $showRestorePrompt,
                presenting: store.pendingRestorePreview
            ) { preview in
                Button("Restore") { store.confirmRestore() }
                Button("Not Now", role: .cancel) { store.declineRestore() }
            } message: { preview in
                let dateStr: String = {
                    guard let date = preview.newestMatchDate else { return "" }
                    return ", latest \(Self.dateFormatter.string(from: date))"
                }()
                Text("Found a backup with \(preview.recordCount) match\(preview.recordCount == 1 ? "" : "es")\(dateStr). Restore it to this iPhone?")
            }
            .onChange(of: store.pendingRestorePreview) { _, preview in
                if preview != nil { showRestorePrompt = true }
            }
        }
    }

    // MARK: - Empty states

    @ViewBuilder
    private var emptyStateView: some View {
        if syncService.isActivating {
            VStack(spacing: 12) {
                ProgressView()
                Text("Connecting to Apple Watch…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else if !syncService.isPaired {
            VStack(spacing: 16) {
                ContentUnavailableView(
                    "No Apple Watch Paired",
                    systemImage: "applewatch.slash",
                    description: Text("Pair an Apple Watch with DeuceMate installed to sync your match history here.")
                )
                Button {
                    showManualEntry = true
                } label: {
                    Label("Enter a match manually", systemImage: "square.and.pencil")
                }
                .buttonStyle(.bordered)
            }
        } else {
            VStack(spacing: 16) {
                ContentUnavailableView(
                    "No Matches Yet",
                    systemImage: "figure.tennis",
                    description: Text("Open DeuceMate on your Apple Watch — your match history will sync automatically.")
                )
                Button {
                    showManualEntry = true
                } label: {
                    Label("Enter a match manually", systemImage: "square.and.pencil")
                }
                .buttonStyle(.bordered)
                iCloudStatusLabel
                    .font(.footnote)
            }
        }
    }

    // MARK: - iCloud status

    /// Inline iCloud backup status: a Label when backed up, a tappable Button
    /// (opening Settings) when off or unavailable. Font and padding are left to
    /// the call site so this can appear in both section footers and empty states.
    @ViewBuilder
    private var iCloudStatusLabel: some View {
        let status = ICloudBackupCopy.current(
            isEnabled: true,
            isAvailable: store.isICloudAvailable,
            isRestoring: store.isRestoringFromICloud,
            hasPendingRestore: store.pendingRestorePreview != nil,
            isUploaded: store.isBackupUploaded
        )
        switch status {
        case .backedUp, .restoring, .pendingUpload:
            Label(status.text, systemImage: status.systemImage)
                .foregroundStyle(.secondary)
        case .pendingRestore:
            Button { showRestorePrompt = true } label: {
                HStack(spacing: 4) {
                    Label(status.text, systemImage: status.systemImage)
                    Image(systemName: "chevron.right").font(.caption2)
                }
                .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows iCloud restore options")
        case .notBackedUp, .unavailable:
            Button { showICloudGuide = true } label: {
                HStack(spacing: 4) {
                    Label(status.text, systemImage: status.systemImage)
                    Image(systemName: "chevron.right").font(.caption2)
                }
                .foregroundStyle(status == .unavailable ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows steps to enable iCloud Drive")
        }
    }

    // MARK: - iCloud guide sheet

    @ViewBuilder
    private var iCloudGuideSheet: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.icloud.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("iCloud Drive Unavailable")
                .font(.headline)

            Text("Your matches are stored on this iPhone only. To keep DeuceMate's app-managed archive in iCloud Drive, follow these steps:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 12) {
                iCloudStep(number: "1.circle.fill", text: "Tap **Open Settings** below")
                iCloudStep(number: "2.circle.fill", text: "Return to the main Settings screen, then tap your **Apple Account**")
                iCloudStep(number: "3.circle.fill", text: "Tap **iCloud** → **Drive**, then turn on **Sync this iPhone**")
                iCloudStep(number: "4.circle.fill", text: "Under **Saved to iCloud**, tap **See All** and turn on **DeuceMate**")
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Text("Open Settings")
                    .bold()
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
    }

    private func iCloudStep(number: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: number)
                .foregroundStyle(.blue)
            Text(text)
        }
        .font(.callout)
    }

    // MARK: - Row actions

    /// True when there are no rows to show: the archive is empty and there are no
    /// watch-only matches to surface (no watch paired, or an empty mirror).
    private var hasNoRows: Bool {
        if !store.history.isEmpty { return false }
        return !syncService.isPaired || syncService.watchMirror.isEmpty
    }

    /// A tappable past-match row with storage-aware swipe and context actions.
    /// `archiveIDs` is built once per render by the caller so membership is O(1).
    @ViewBuilder
    private func pastMatchRow(_ record: MatchRecord, archiveIDs: Set<UUID>) -> some View {
        let onWatch = syncService.isPaired && syncService.onWatchIDs.contains(record.id)
        let location = rowLocation(for: record, inHistory: archiveIDs.contains(record.id))
        Button {
            selected = record
        } label: {
            rowView(for: record, location: location)
        }
        .buttonStyle(.plain)
        // Full-swipe is reserved for the safe, recoverable "Remove from Watch" (only
        // on `.both`). `.phoneOnly` and `.watchOnly` offer only permanent deletion,
        // which must go through the confirmation dialog — so no full-swipe there.
        .swipeActions(edge: .trailing, allowsFullSwipe: location == .both) {
            rowDeleteSwipe(for: record, location: location, onWatch: onWatch)
        }
        .contextMenu {
            rowContextActions(for: record, location: location, onWatch: onWatch)
        }
        .confirmationDialog(
            "Delete permanently?",
            isPresented: Binding(
                get: { pendingDelete?.id == record.id },
                set: { if !$0 && pendingDelete?.id == record.id { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                if let pending = pendingDelete { performPermanentDelete(pending) }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            if onWatch {
                Text("This deletes the match from iPhone and Apple Watch for good — this can't be undone.")
            } else {
                Text("This deletes the match from iPhone for good — this can't be undone.")
            }
        }
    }

    /// Resolves a row's storage location from the phone archive and the watch
    /// manifest (consulted only when paired). `.watchOnly` means the match is on the
    /// watch but not yet in the iPhone archive — the at-risk-while-freeing-space case.
    private func rowLocation(for record: MatchRecord, inHistory: Bool) -> MatchStorageLocation {
        MatchStorageResolver.location(
            matchID: record.id,
            onPhone: inHistory,
            watchIDs: syncService.isPaired ? syncService.onWatchIDs : []
        )
    }

    @ViewBuilder
    private func rowDeleteSwipe(for record: MatchRecord, location: MatchStorageLocation, onWatch: Bool) -> some View {
        switch location {
        case .both:
            // Recoverable free-up-space: the iPhone keeps its archive copy; only the
            // watch copy is dropped. "Sync to Watch" can push it back later.
            removeFromWatchButton(record)
                .tint(.orange)
        case .phoneOnly, .watchOnly:
            // The only remaining action is permanent deletion, gated behind the dialog.
            Button(role: .destructive) {
                pendingDelete = PendingDelete(record: record, onWatch: onWatch)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
        }
    }

    @ViewBuilder
    private func rowContextActions(for record: MatchRecord, location: MatchStorageLocation, onWatch: Bool) -> some View {
        switch location {
        case .both:
            removeFromWatchButton(record)
            deletePermanentlyButton(record, onWatch: onWatch)
        case .phoneOnly:
            if syncService.isPaired {
                Button {
                    syncService.sendMatchToWatch(record)
                } label: {
                    Label("Sync to Watch", systemImage: "applewatch")
                }
            }
            deletePermanentlyButton(record, onWatch: onWatch)
        case .watchOnly:
            Button {
                store.syncToPhone(record)
            } label: {
                Label("Sync to iPhone", systemImage: "iphone")
            }
            deletePermanentlyButton(record, onWatch: onWatch)
        }
    }

    /// "Remove from Watch" — frees watch space while the iPhone keeps its archive
    /// copy. Reversible via "Sync to Watch". Shared by the swipe and context menu.
    @ViewBuilder
    private func removeFromWatchButton(_ record: MatchRecord) -> some View {
        Button {
            syncService.sendDeleteMatchOnWatch(record.id)
        } label: {
            Label("Remove from Watch", systemImage: "applewatch.slash")
        }
    }

    @ViewBuilder
    private func deletePermanentlyButton(_ record: MatchRecord, onWatch: Bool) -> some View {
        Button(role: .destructive) {
            pendingDelete = PendingDelete(record: record, onWatch: onWatch)
        } label: {
            Label("Delete Permanently", systemImage: "trash")
        }
    }

    /// Permanent deletion: drop the phone's retained copy and, when the match is
    /// also on the watch, issue the watch-side delete so it can't re-sync back.
    private func performPermanentDelete(_ pending: PendingDelete) {
        store.deletePermanently(id: pending.record.id)
        if pending.onWatch {
            syncService.sendDeleteMatchOnWatch(pending.record.id)
        }
        pendingDelete = nil
    }

    // MARK: - Row

    @ViewBuilder
    private func rowView(for record: MatchRecord, location: MatchStorageLocation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Text(Self.dateFormatter.string(from: record.startTime))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    statusBadge(for: record)
                    storageBadge(for: record, location: location)
                }
            }

            if let score = record.isInProgress ? inProgressScoreString(for: record) : scoreString(for: record) {
                Text(styledScore(score, superSize: 11))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(.primary)
            }

            HStack(spacing: 8) {
                if !record.isInProgress && record.iWon == nil {
                    Text("Draw")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(theme.colors.server)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(theme.colors.server.opacity(0.15)))
                } else if let won = didWin(record) {
                    let tint = won ? theme.colors.me : theme.colors.opponent
                    Text(won ? "Won" : "Lost")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(tint.opacity(0.15)))
                }
                Text(formatLabel(for: record))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func statusBadge(for record: MatchRecord) -> some View {
        if record.isInProgress && record.id == syncService.activeMatchID {
            Label("Live", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(theme.colors.server)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(theme.colors.server.opacity(0.15)))
        } else if record.isInProgress {
            Label("In Progress", systemImage: "pause.circle")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color(.secondarySystemFill)))
        } else if hasPointStats(record) {
            Label("Stats", systemImage: "chart.bar.fill")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color(.secondarySystemFill)))
        } else {
            Label("Score", systemImage: "list.number")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color(.secondarySystemFill)))
        }
    }

    /// Small badge reflecting the row's state. The cross-device badges (both /
    /// iPhone-only / watch-only) show only when a watch is paired — without one,
    /// every match is simply on the phone and the badge would be noise. The
    /// "Removed from iPhone" badge shows regardless: it's a phone-local signal that
    /// the match was retired from the active list but kept.
    @ViewBuilder
    private func storageBadge(for record: MatchRecord, location: MatchStorageLocation) -> some View {
        switch location {
        case .both:
            badgeCapsule {
                HStack(spacing: 2) {
                    Image(systemName: "applewatch")
                    Image(systemName: "iphone")
                }
                .accessibilityLabel("Stored on Apple Watch and iPhone")
            }
        case .phoneOnly:
            if syncService.isPaired {
                badgeCapsule {
                    Image(systemName: "iphone")
                        .accessibilityLabel("Stored on iPhone only")
                }
            }
        case .watchOnly:
            // On the watch but not yet in the iPhone archive — at risk if the user
            // frees watch space before syncing it down. Flag it as not-backed-up so
            // "Sync to iPhone" is the obvious next step. (The watch-side free-space
            // delete can't itself confirm the phone has a copy — this is the surface
            // that warns the user before that happens.)
            badgeCapsule(tint: .orange) {
                HStack(spacing: 2) {
                    Image(systemName: "applewatch")
                    Image(systemName: "exclamationmark.icloud")
                }
                .accessibilityLabel("On Apple Watch only — not yet backed up to iPhone")
            }
        }
    }

    /// Shared chrome for the storage badge — small glyph in a capsule. `tint`
    /// defaults to secondary; the watch-only "not backed up" badge passes `.orange`.
    @ViewBuilder
    private func badgeCapsule<Content: View>(
        tint: Color = .secondary,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        content()
            .font(.caption2)
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color(.secondarySystemFill)))
    }

    // MARK: - Helpers

    /// Foot-of-list note: the iPhone archive is uncapped, so reassure that the
    /// full history is kept here while noting the watch's rolling limit. Mirrors
    /// the watch's foot-of-list note (which counts up to its cap) from the phone's
    /// keeps-everything perspective.
    private var archiveFooterText: String {
        let count = store.history.count
        let noun = count == 1 ? "match" : "matches"
        return "\(count) \(noun) kept on iPhone — your full history stays here. Apple Watch holds the most recent \(WatchHistory.cap)."
    }

    private func resultLabel(for record: MatchRecord) -> String {
        if record.isInProgress { return "In Progress" }
        let result = (record.iWon ?? false) ? "Won" : "Lost"
        if record.matchFormat == .perpetualPoints, let tb = record.setScores.first {
            return "Final \(tb.tieBreakPointsMe)-\(tb.tieBreakPointsOpponent)"
        }
        if record.matchFormat == .superTiebreak, let tb = record.setScores.first {
            return "\(result) \(tb.tieBreakPointsMe)-\(tb.tieBreakPointsOpponent)"
        }
        if record.matchFormat == .perpetualSuperTiebreak {
            let scores = record.setScores.map { "\($0.tieBreakPointsMe)-\($0.tieBreakPointsOpponent)" }
            if scores.count > 4 {
                return scores.prefix(3).joined(separator: ", ") + ", … (\(scores.count) sets)"
            }
            return scores.joined(separator: ", ")
        }
        let parts = record.setScores.map { set -> String in
            if set.isTieBreak && set.gamesMe + set.gamesOpponent > 0 {
                return "\(set.gamesMe)-\(set.gamesOpponent)(\(set.tieBreakPointsMe)-\(set.tieBreakPointsOpponent))"
            } else if set.isTieBreak {
                return "\(set.tieBreakPointsMe)-\(set.tieBreakPointsOpponent)"
            }
            return "\(set.gamesMe)-\(set.gamesOpponent)"
        }
        return "\(result) \(parts.joined(separator: ", "))"
    }

    private func hasPointStats(_ record: MatchRecord) -> Bool { !record.stats.isEmpty }

    private func formatLabel(for record: MatchRecord) -> String {
        var parts: [String] = []
        switch record.matchFormat {
        case .standard:               parts.append("Best of 3")
        case .bestOf3FullFinalSet:    parts.append("Best of 3 (Full Final Set)")
        case .superTiebreak:          parts.append("Super Tiebreak")
        case .perpetualSuperTiebreak: parts.append("Perpetual Tiebreak")
        case .quick4Games:            parts.append("Quick 4 Games")
        case .perpetualPoints:        parts.append("Perpetual Points")
        }
        parts.append(record.matchType == .doubles ? "Doubles" : "Singles")
        return parts.joined(separator: " · ")
    }

    /// Score string for in-progress matches: completed set scores + current set
    /// games + current game score (e.g. "6–4  2–1  (30–0)").
    private func inProgressScoreString(for record: MatchRecord) -> String? {
        guard !record.setScores.isEmpty else { return nil }
        var parts: [String] = []

        // All completed sets (everything except the last)
        for set in record.setScores.dropLast() {
            if set.isTieBreak && set.gamesMe + set.gamesOpponent > 0 {
                parts.append("\(set.gamesMe)–\(set.gamesOpponent)(\(set.tieBreakPointsMe)–\(set.tieBreakPointsOpponent))")
            } else if set.isTieBreak {
                parts.append("\(set.tieBreakPointsMe)–\(set.tieBreakPointsOpponent)")
            } else {
                parts.append("\(set.gamesMe)–\(set.gamesOpponent)")
            }
        }

        // Current in-progress set (last element)
        if let current = record.setScores.last {
            if current.isTieBreak {
                parts.append("TB \(current.tieBreakPointsMe)–\(current.tieBreakPointsOpponent)")
            } else {
                parts.append("\(current.gamesMe)–\(current.gamesOpponent)")
                if let gs = MatchRecord.gameScoreString(mePoints: record.currentPointsMe, oppPoints: record.currentPointsOpponent) {
                    parts.append("(\(gs))")
                }
            }
        }

        return parts.isEmpty ? nil : parts.joined(separator: "  ")
    }


    private func scoreString(for record: MatchRecord) -> String? {
        guard !record.isInProgress else { return nil }
        if record.matchFormat == .perpetualPoints, let tb = record.setScores.first {
            return "\(tb.tieBreakPointsMe)–\(tb.tieBreakPointsOpponent)"
        }
        if record.matchFormat == .superTiebreak, let tb = record.setScores.first {
            return "\(tb.tieBreakPointsMe)–\(tb.tieBreakPointsOpponent)"
        }
        if record.matchFormat == .perpetualSuperTiebreak {
            let scores = record.setScores.map { "\($0.tieBreakPointsMe)–\($0.tieBreakPointsOpponent)" }
            if scores.count > 4 {
                return scores.prefix(3).joined(separator: "  ") + "  …(\(scores.count))"
            }
            return scores.joined(separator: "  ")
        }
        let cfg = record.matchFormat.config
        let parts = record.setScores.enumerated().map { index, set -> String in
            if cfg.isDecidingSuperTiebreak(setIndex: index) && set.isTieBreak {
                return "\(set.tieBreakPointsMe)–\(set.tieBreakPointsOpponent)"
            }
            if set.isTieBreak && set.gamesMe + set.gamesOpponent > 0 {
                return "\(set.gamesMe)–\(set.gamesOpponent)(\(set.tieBreakPointsMe)–\(set.tieBreakPointsOpponent))"
            } else if set.isTieBreak {
                return "\(set.tieBreakPointsMe)–\(set.tieBreakPointsOpponent)"
            }
            return "\(set.gamesMe)–\(set.gamesOpponent)"
        }
        return parts.joined(separator: "  ")
    }

    private func didWin(_ record: MatchRecord) -> Bool? {
        guard !record.isInProgress else { return nil }
        return record.iWon  // nil = draw
    }
}
