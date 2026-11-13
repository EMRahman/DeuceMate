// GamePlanView.swift — Prepare Game Plan: the iPhone flow that turns the
// recorded history against one opponent into a reviewable evidence pack and
// hands it to an AI app (docs/features/OPPONENT_GAME_PLAN_PROPOSAL.md §3).
//
// DeuceMate only PREPARES the pack. The plan is written and read in whichever
// AI app the player chooses; nothing is sent automatically, and opening an
// app does not mean it received or analysed anything.
//
// Ready on arrival: the main screen is one summary row per choice (upcoming
// match, matches, pack contents), the optional preparation text, then the
// hand-off. Each row pushes the full controls (`GamePlanUpcomingView`,
// `GamePlanEvidenceView`, `GamePlanContentsView`, `GamePlanAdvancedView`).
// The upcoming competition and format are pre-filled from the previous match
// against the opponent; when that match is unfinished, the next match is
// finishing it (always selected as evidence; the pack asks how to close it
// out from the saved score). Unfinished matches are evidence by default.
// Names, playing style notes and private notes start on, and any note can be
// left out. The summaries state all of it before
// anything is copied or shared.
//
// Session-local by design: everything lives in @State and is gone when the
// screen closes.
import SwiftUI
import UIKit
import DeuceMateCore

struct GamePlanView: View {
    let opponentID: UUID

    @EnvironmentObject private var store: PhoneStatsStore
    @ObservedObject private var notesStore: MatchNotesStore = .shared

    // Upcoming match — pre-filled once from the previous match.
    @State private var upcoming = GamePlanUpcomingMatch()
    @State private var hasUpcomingDate = false
    @State private var upcomingDate = Date()
    @State private var didPrefill = false
    @State private var prefilledFrom: Date?

    // Evidence selection.
    @State private var evidence = GamePlanEvidenceChoices()

    // Inclusion choices — on by default; the player prepares this for their own AI app.
    @State private var includeNames = true
    @State private var includeNotes = true
    @State private var includePlayingNotes = true
    /// Notes the player chose to leave out, by match.
    @State private var notesLeftOut: Set<UUID> = []

    // Output.
    @State private var detailMode: GamePlanDetailMode = .full
    @State private var delivery: GamePlanDelivery = .singleFile
    @State private var output: GamePlanBuildOutput?
    @State private var buildProgress: Double = 0
    @State private var buildFailure: String?
    @State private var shareRequest: GamePlanShareRequest?
    /// Retired generations whose files an open share sheet is still handing out.
    @State private var heldGenerations: Set<ExportStaging.Generation> = []
    @State private var installedApps: [AICoachApp] = []
    @State private var toast: String?
    @State private var toastWork: DispatchWorkItem?

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    // MARK: - Derived

    private var opponent: RosterEntry? {
        OpponentDirectory.entries(from: store.history, forgotten: store.forgottenPlayers)
            .first { $0.id == opponentID }
    }

    private var opponentName: String { opponent?.name ?? "this opponent" }

    private var candidates: GamePlanCandidates {
        GamePlanEligibility.candidates(for: opponentID, in: store.history,
                                       forgotten: store.forgottenPlayers,
                                       includeInProgress: evidence.includeInProgress,
                                       alwaysInclude: upcoming.finishingMatchID)
    }

    private var pool: [MatchRecord] { evidence.selection.filtered(candidates) }
    /// The selection, plus the match being finished if it was left out.
    private var selected: [MatchRecord] {
        evidence.selection.resolve(candidates, pinning: finishingRecord?.id)
    }

    /// The unfinished match being finished, while it is still unfinished. A
    /// match completed meanwhile (say, from the Watch) is no longer pinned,
    /// and the pack falls back to a new match.
    private var finishingRecord: MatchRecord? {
        guard let id = upcoming.finishingMatchID else { return nil }
        return candidates.unfinishedMatches.first { $0.id == id }
    }

    private var notesUnreadable: Bool { notesStore.loadFailure != nil }

    /// Stored notes of the selected matches (none when the notes file is unreadable).
    private var selectedNotes: [UUID: String] {
        guard !notesUnreadable else { return [:] }
        var notes: [UUID: String] = [:]
        for record in selected {
            let text = MatchNotesPolicy.sanitizedText(notesStore.note(for: record.id)?.text ?? "")
            if !text.isEmpty { notes[record.id] = text }
        }
        return notes
    }

    /// Selected matches' notes the player left out.
    private var omittedNoteIDs: Set<UUID> { notesLeftOut.intersection(selectedNotes.keys) }

    private var reviewableNotes: [GamePlanNotesReviewView.Item] {
        selected.compactMap { record in
            guard let text = selectedNotes[record.id] else { return nil }
            return GamePlanNotesReviewView.Item(
                matchID: record.id,
                title: "\(Self.dayFormatter.string(from: record.startTime)) · \(GamePlanCompetition(record: record).label)",
                text: text
            )
        }
    }

    private var buildInputs: GamePlanBuildInputs {
        var upcomingValue = upcoming
        upcomingValue.date = hasUpcomingDate ? upcomingDate : nil
        return GamePlanBuildInputs(
            opponentID: opponentID,
            opponent: opponent,
            selected: selected,
            candidateCounts: candidates.counts,
            availableCount: pool.count,
            upcoming: upcomingValue,
            notes: selectedNotes,
            includeNotes: includeNotes && !notesUnreadable,
            omittedNoteMatchIDs: omittedNoteIDs,
            includeNames: includeNames,
            includePlayingNotes: includePlayingNotes,
            detailMode: detailMode,
            delivery: delivery,
            selectionDescription: evidence.selection.manifestDescription(timeZone: .current)
        )
    }

    // MARK: - Body

    var body: some View {
        List {
            setupSection
            contextSection
            handOffSection
            moreSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Prepare Game Plan")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("game-plan")
        .overlay(alignment: .bottom) { toastView }
        .animation(.easeInOut(duration: 0.2), value: toast)
        .onAppear {
            installedApps = AICoachLauncher.installedApps()
            prefillUpcomingOnce()
        }
        .onChange(of: evidence.filter) { _, newFilter in
            evidence.selection.setFilter(newFilter, candidates: candidates)
        }
        .onChange(of: upcoming.preparationText) { _, text in
            if text.count > GamePlanUpcomingMatch.maxPreparationLength {
                upcoming.preparationText = String(text.prefix(GamePlanUpcomingMatch.maxPreparationLength))
            }
        }
        // A rebuild whenever anything the pack depends on changes: records,
        // roster, notes, upcoming context, selection or inclusion choices.
        .task(id: buildInputs) { await rebuild(buildInputs) }
        .sheet(item: $shareRequest, onDismiss: releaseHeldGenerations) { request in
            GamePlanShareSheet(activityItems: request.items) { shareRequest = nil }
        }
    }

    /// Competition and format from the previous match against this opponent,
    /// once per visit, so a later edit is never overwritten. An unfinished
    /// previous match becomes the match to finish.
    private func prefillUpcomingOnce() {
        guard !didPrefill else { return }
        didPrefill = true
        guard let latest = candidates.latestMatch else { return }
        let prefill = GamePlanUpcomingMatch(prefilledFrom: latest)
        upcoming.competition = prefill.competition
        upcoming.format = prefill.format
        upcoming.finishingMatchID = prefill.finishingMatchID
        prefilledFrom = latest.startTime
    }

    // MARK: - Sections

    private var setupSection: some View {
        Section {
            NavigationLink {
                GamePlanUpcomingView(upcoming: $upcoming, hasDate: $hasUpcomingDate,
                                     date: $upcomingDate, prefilledFrom: prefilledFrom,
                                     unfinished: candidates.unfinishedMatches)
            } label: {
                LabeledContent("Upcoming", value: GamePlanUpcomingView.summary(
                    upcoming, date: hasUpcomingDate ? upcomingDate : nil, finishing: finishingRecord))
            }
            .accessibilityIdentifier("game-plan-upcoming")

            NavigationLink {
                GamePlanEvidenceView(choices: $evidence, candidates: candidates,
                                     opponentName: opponentName, noteMatchIDs: Set(selectedNotes.keys),
                                     pinnedMatchID: finishingRecord?.id)
            } label: {
                LabeledContent("Matches", value: candidates.eligible.isEmpty
                               ? "None yet"
                               : "\(evidence.selection.label) · \(selected.count) of \(pool.count)")
            }
            .accessibilityIdentifier("game-plan-evidence")

            NavigationLink {
                GamePlanContentsView(includeNames: $includeNames, includePlayingNotes: $includePlayingNotes,
                                     includeNotes: $includeNotes, notesLeftOut: $notesLeftOut,
                                     hasPlayingNotes: opponent?.playingNotes != nil,
                                     notesUnreadable: notesUnreadable, notes: reviewableNotes)
            } label: {
                LabeledContent("Includes", value: GamePlanContentsView.summary(
                    includeNames: includeNames, includePlayingNotes: includePlayingNotes,
                    hasPlayingNotes: opponent?.playingNotes != nil,
                    includeNotes: includeNotes, notesUnreadable: notesUnreadable,
                    includedNoteCount: selectedNotes.count - omittedNoteIDs.count,
                    noteCount: selectedNotes.count))
            }
            .accessibilityIdentifier("game-plan-contents")
        } footer: {
            if candidates.eligible.isEmpty {
                Text("No singles matches against \(opponentName) yet. Tag them as the opponent in Match Info on a past singles match to use it here.")
                    .accessibilityIdentifier("game-plan-empty")
            } else if let exclusions = GamePlanEvidenceView.shortExclusionsText(candidates) {
                Text(exclusions)
            }
        }
    }

    private var contextSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                TextField(finishingRecord == nil
                          ? "Surface, conditions, or what you want to try (optional)"
                          : "What changed since the stop, or what you want to try (optional)",
                          text: $upcoming.preparationText, axis: .vertical)
                    .lineLimit(2...6)
                    .accessibilityIdentifier("game-plan-preparation")
                if !upcoming.preparationText.isEmpty {
                    Text("\(upcoming.preparationText.count)/\(GamePlanUpcomingMatch.maxPreparationLength)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            Text("Focus")
        }
    }

    @ViewBuilder
    private var handOffSection: some View {
        Section {
            estimateRow
            if let output {
                if output.pack.isSplit {
                    ForEach(output.pack.parts) { part in
                        Button {
                            copy(part.text, message: "Part \(part.number) of \(part.total) copied")
                        } label: {
                            Label("Copy Part \(part.number) of \(part.total)", systemImage: "doc.on.clipboard")
                        }
                    }
                } else {
                    Button {
                        copy(output.pack.parts[0].text, message: "Prompt and evidence copied")
                    } label: {
                        Label("Copy Prompt", systemImage: "doc.on.clipboard")
                    }
                    .accessibilityIdentifier("game-plan-copy")
                }
                Button {
                    shareRequest = GamePlanShareRequest(items: [output.pack.attachmentMessage as Any] + output.fileURLs.map { $0 as Any },
                                                        fileURLs: output.fileURLs)
                } label: {
                    Label(output.pack.isSplit ? "Share Evidence Files" : "Share Evidence File", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("game-plan-share")
                ForEach(installedApps) { app in
                    Button {
                        Task { await open(app, output: output) }
                    } label: {
                        Label("Open \(app.name)", systemImage: app.systemImage)
                    }
                }
            }
        } header: {
            Text("Hand Off")
        } footer: {
            Text(handOffFooter)
        }
    }

    @ViewBuilder
    private var estimateRow: some View {
        if let output {
            VStack(alignment: .leading, spacing: 2) {
                Text(output.pack.totalEstimate.inputLabel)
                    .font(.subheadline.weight(.semibold))
                Text("\(GamePlanText.plural(output.evidence.matches.count, "match", "matches")) · \(GamePlanText.plural(output.evidence.pointsSaved, "point")) · \(ByteCountFormatter.string(fromByteCount: Int64(output.pack.totalBytes), countStyle: .file))\(output.pack.isSplit ? " · \(output.pack.parts.count) parts" : "")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if output.pack.isSplit {
                    ForEach(output.pack.parts) { part in
                        Text("Part \(part.number): \(part.estimate.label)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(GamePlanText.plural(output.evidence.matches.count, "match", "matches")) selected. \(output.pack.totalEstimate.inputLabel).")
            .accessibilityValue(packContentsSummary(output.evidence))
            .accessibilityIdentifier("game-plan-estimate")
        } else if let buildFailure {
            Label(buildFailure, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        } else {
            HStack(spacing: 10) {
                ProgressView(value: buildProgress)
                Text("Preparing…").font(.footnote).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Building the evidence pack")
        }
    }

    private var moreSection: some View {
        Section {
            if let output {
                NavigationLink {
                    GamePlanPreviewView(output: output)
                } label: {
                    Label("Preview Evidence Pack", systemImage: "doc.text.magnifyingglass")
                }
                .accessibilityIdentifier("game-plan-preview")
            }
            NavigationLink {
                GamePlanAdvancedView(detailMode: $detailMode, delivery: $delivery)
            } label: {
                LabeledContent("Advanced", value: GamePlanAdvancedView.summary(detailMode: detailMode, delivery: delivery))
            }
            .accessibilityIdentifier("game-plan-advanced")
        }
    }

    private var handOffFooter: String {
        let split = output?.pack.isSplit == true
        var text = split
            ? "Send the parts in order; the pack asks the AI to wait for the last one."
            : "Copy and paste it, or share it as a file (better for large packs)."
        if !installedApps.isEmpty {
            text += split
                ? " Opening an app copies part 1 for you to paste."
                : " Opening an app copies the pack for you to paste."
        }
        text += " DeuceMate never sends it anywhere itself, and copies you share can’t be recalled."
        return text
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Text(toast)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule())
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// "Names not included, 2 of 3 notes included, full detail" — what the
    /// built pack holds, read after its size.
    private func packContentsSummary(_ evidence: GamePlanEvidence) -> String {
        let names = evidence.includesNames ? "Names included" : "Names not included"
        let notes = evidence.includesNotes
            ? "\(evidence.notesIncludedCount) of \(evidence.notesAvailableCount) notes included"
            : "notes not included"
        return "\(names), \(notes), \(evidence.detailMode.label.lowercased())"
    }

    // MARK: - Actions

    private func copy(_ text: String, message: String) {
        AICoachLauncher.copyToClipboard(text)
        showToast(message)
    }

    private func open(_ app: AICoachApp, output: GamePlanBuildOutput) async {
        let text = output.pack.parts[0].text
        let opened = await AICoachLauncher.openWithoutPrefill(app, copying: text)
        showToast(opened
                  ? (output.pack.isSplit ? "Part 1 copied — opening \(app.name)…" : "Pack copied — opening \(app.name)…")
                  : "Couldn’t open \(app.name). The pack is copied; you can also share the file.")
    }

    private func showToast(_ message: String) {
        toast = message
        toastWork?.cancel()
        let work = DispatchWorkItem { withAnimation { toast = nil } }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }

    // MARK: - Build

    /// One build per input change. Clears the old pack first, waits briefly
    /// so typing doesn't rebuild on every keystroke, then builds off the main
    /// actor in a fresh staging generation. A superseded build deletes its own
    /// files and never publishes.
    private func rebuild(_ inputs: GamePlanBuildInputs) async {
        output = nil
        buildFailure = nil
        buildProgress = 0
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }

        let staging = ExportStaging.shared
        let generation = staging.beginGeneration()
        let worker = Task.detached(priority: .userInitiated) { () throws -> GamePlanBuildOutput in
            staging.sweepInactive()
            return try GamePlanBuild.run(inputs, staging: staging, generation: generation) { fraction in
                Task { @MainActor in buildProgress = fraction }
            }
        }
        let result = await withTaskCancellationHandler {
            await worker.result
        } onCancel: {
            worker.cancel()
        }
        guard !Task.isCancelled else {
            staging.endGeneration(generation)
            return
        }
        switch result {
        case .success(let built):
            output = built
        case .failure(let error):
            staging.endGeneration(generation)
            if !(error is CancellationError) {
                buildFailure = "Couldn’t build the pack. Try again."
            }
            return
        }
        // Keep this generation's files exactly as long as they are current.
        await ExportStaging.waitUntilCancelled()
        retire(generation)
    }

    private func retire(_ generation: ExportStaging.Generation) {
        if let shareRequest, shareRequest.fileURLs.contains(where: generation.contains) {
            heldGenerations.insert(generation)
        } else {
            ExportStaging.shared.endGeneration(generation)
        }
    }

    private func releaseHeldGenerations() {
        for generation in heldGenerations {
            ExportStaging.shared.endGeneration(generation)
        }
        heldGenerations.removeAll()
    }
}

// MARK: - Share plumbing

struct GamePlanShareRequest: Identifiable {
    let id = UUID()
    let items: [Any]
    let fileURLs: [URL]
}

/// `UIActivityViewController` bridge, so the files can be shared with the
/// short accompanying message as one action.
struct GamePlanShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var onComplete: () -> Void = {}

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onComplete() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
