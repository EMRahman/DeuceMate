// GamePlanView.swift — Prepare Game Plan: the iPhone flow that turns the
// recorded history against one opponent into a reviewable evidence pack and
// hands it to an AI app (docs/features/OPPONENT_GAME_PLAN_PROPOSAL.md §3).
//
// DeuceMate only PREPARES the pack. The plan is written and read in whichever
// AI app the player chooses; nothing is sent automatically, and opening an
// app does not mean it received or analysed anything.
//
// Session-local by design: the upcoming context, selection and inclusion
// choices live in @State and are gone when the screen closes. Names and notes
// start OFF every time. Each note must be reviewed before it can be included;
// a note that changes after review, or a newly selected match's note, is left
// out until it is reviewed again.
import SwiftUI
import UIKit
import DeuceMateCore

struct GamePlanView: View {
    let opponentID: UUID

    @EnvironmentObject private var store: PhoneStatsStore
    @ObservedObject private var notesStore: MatchNotesStore = .shared

    // Upcoming match (user statements, all unset to begin with).
    @State private var upcoming = GamePlanUpcomingMatch()
    @State private var hasUpcomingDate = false
    @State private var upcomingDate = Date()

    // Evidence selection.
    @State private var selection = GamePlanSelection()
    @State private var customCount = 3
    /// The Count preset is on, so 5 or 10 chosen with the stepper stays a count.
    @State private var usesCustomCount = false
    @State private var includeInProgress = false
    @State private var useFromDate = false
    @State private var fromDate = Date()
    @State private var useThroughDate = false
    @State private var throughDate = Date()
    @State private var competitionFilter: Set<GamePlanCompetition>?

    // Inclusion choices — off every session.
    @State private var includeNames = false
    @State private var includeNotes = false
    /// The opponent's Playing Style notes. On by default: the player wrote them as scouting for exactly this.
    @State private var includePlayingNotes = true
    /// Note text as it was when the player approved it, by match.
    @State private var reviewedNotes: [UUID: String] = [:]
    /// Notes the player chose to leave out at their last review.
    @State private var notesLeftOut: Set<UUID> = []
    @State private var showNotesReview = false

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

    private static let dayFormatter: DateFormatter = {
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

    private var candidates: GamePlanCandidates {
        GamePlanEligibility.candidates(for: opponentID, in: store.history,
                                       forgotten: store.forgottenPlayers,
                                       includeInProgress: includeInProgress)
    }

    private var filter: GamePlanFilter {
        GamePlanFilter(from: useFromDate ? fromDate : nil,
                       through: useThroughDate ? throughDate : nil,
                       competitions: competitionFilter)
    }

    private var pool: [MatchRecord] { selection.filtered(candidates) }
    private var selected: [MatchRecord] { selection.resolve(candidates) }

    /// Competition contexts present among eligible matches, for the filter.
    private var availableCompetitions: [GamePlanCompetition] {
        Set(candidates.eligible.map(GamePlanCompetition.init(record:)))
            .sorted { GamePlanCompetition.ordered($0, $1) }
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

    /// Notes left out of the pack: everything the player has not approved in
    /// its current form.
    private var omittedNoteIDs: Set<UUID> {
        Set(selectedNotes.compactMap { id, text in reviewedNotes[id] == text ? nil : id })
    }

    private var unreviewedNoteCount: Int {
        selectedNotes.filter { id, text in reviewedNotes[id] == nil || reviewedNotes[id] != text }.count
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
            selectionDescription: selection.manifestDescription(timeZone: .current)
        )
    }

    // MARK: - Body

    var body: some View {
        List {
            introSection
            upcomingSection
            evidenceSection
            privacySection
            detailSection
            estimateSection
            handOffSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Prepare Game Plan")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("game-plan")
        .overlay(alignment: .bottom) { toastView }
        .animation(.easeInOut(duration: 0.2), value: toast)
        .onAppear { installedApps = AICoachLauncher.installedApps() }
        .onChange(of: filter) { _, newFilter in
            selection.setFilter(newFilter, candidates: candidates)
        }
        .onChange(of: upcoming.preparationText) { _, text in
            if text.count > GamePlanUpcomingMatch.maxPreparationLength {
                upcoming.preparationText = String(text.prefix(GamePlanUpcomingMatch.maxPreparationLength))
            }
        }
        // A rebuild whenever anything the pack depends on changes: records,
        // roster, notes, upcoming context, selection or inclusion choices.
        .task(id: buildInputs) { await rebuild(buildInputs) }
        .sheet(isPresented: $showNotesReview) {
            GamePlanNotesReviewView(
                notes: reviewableNotes,
                includeNames: includeNames,
                initiallyExcluded: notesLeftOut,
                onConfirm: { approved in
                    notesLeftOut = Set(reviewableNotes.map(\.matchID)).subtracting(approved.keys)
                    reviewedNotes = approved
                    includeNotes = true
                    showNotesReview = false
                },
                onCancel: { showNotesReview = false }
            )
        }
        .sheet(item: $shareRequest, onDismiss: releaseHeldGenerations) { request in
            GamePlanShareSheet(activityItems: request.items) { shareRequest = nil }
        }
    }

    // MARK: - Sections

    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Prepare Game Plan", systemImage: "list.bullet.clipboard")
                    .font(.headline)
                Text("Builds an evidence pack from the matches you recorded against \(opponent?.name ?? "this opponent"). You hand it to an AI app of your choice, which writes the game plan. DeuceMate never sends it anywhere itself.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var upcomingSection: some View {
        Section {
            Picker("Competition", selection: $upcoming.competition) {
                Text("Not set").tag(CompetitionType?.none)
                ForEach(CompetitionType.allCases) { type in
                    Text(type.displayLabel).tag(Optional(type))
                }
            }
            .accessibilityIdentifier("game-plan-competition")
            Picker("Format", selection: $upcoming.format) {
                Text("Not set").tag(MatchFormat?.none)
                ForEach(GamePlanText.selectableFormats, id: \.self) { format in
                    Text(GamePlanText.formatLabel(format)).tag(Optional(format))
                }
            }
            Toggle("Set a date", isOn: $hasUpcomingDate)
            if hasUpcomingDate {
                DatePicker("Date", selection: $upcomingDate, displayedComponents: .date)
            }
            VStack(alignment: .leading, spacing: 4) {
                TextField("Surface, conditions or a concern (optional)", text: $upcoming.preparationText, axis: .vertical)
                    .lineLimit(2...6)
                    .accessibilityIdentifier("game-plan-preparation")
                Text("\(upcoming.preparationText.count)/\(GamePlanUpcomingMatch.maxPreparationLength)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } header: {
            Text("Upcoming Match")
        } footer: {
            Text("Your own statements, not tracked data. Competition starts unset so the plan doesn’t assume another friendly. Preparation text is included as written.")
        }
    }

    @ViewBuilder
    private var evidenceSection: some View {
        Section {
            if candidates.eligible.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No singles matches against \(opponent?.name ?? "this opponent") yet")
                        .font(.subheadline.weight(.semibold))
                    Text("Tag them as the opponent in Match Info on a past singles match to use it here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .accessibilityIdentifier("game-plan-empty")
            } else {
                presetPicker
                if preset == .count {
                    Stepper(value: Binding(
                        get: { customCount },
                        set: { value in
                            customCount = GamePlanSelection.clampedCount(value, available: pool.count)
                            selection.mode = .latest(customCount)
                        }
                    ), in: 1...max(1, pool.count)) {
                        Text("Latest \(customCount) \(customCount == 1 ? "match" : "matches")")
                    }
                    .accessibilityIdentifier("game-plan-custom-count")
                }
                if case .custom = selection.mode {
                    HStack {
                        Text("Custom selection")
                        Spacer()
                        Button("Reset to Last 5") {
                            usesCustomCount = false
                            selection.mode = .latest(GamePlanSelection.defaultCount)
                        }
                            .font(.footnote)
                    }
                }
                NavigationLink {
                    GamePlanMatchPickerView(
                        pool: pool,
                        selectedIDs: Set(selected.map(\.id)),
                        notesMatchIDs: Set(selectedNotes.keys),
                        toggle: { id in selection.toggle(id, candidates: candidates) }
                    )
                } label: {
                    LabeledContent("Matches", value: "\(selected.count) of \(pool.count) selected")
                }
                .accessibilityIdentifier("game-plan-choose-matches")
                selectionSummary
                filtersGroup
            }
            Toggle("Include unfinished matches", isOn: $includeInProgress)
                .accessibilityIdentifier("game-plan-include-in-progress")
        } header: {
            Text("Evidence")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Only the selected matches are used. Unfinished matches are saved checkpoints: partial evidence, never results.")
                if let exclusions = exclusionsText { Text(exclusions) }
            }
        }
    }

    private enum Preset: Hashable { case last5, last10, count, all, custom }

    private var preset: Preset {
        switch selection.mode {
        case .latest where usesCustomCount: return .count
        case .latest(5):  return .last5
        case .latest(10): return .last10
        case .latest:     return .count
        case .all:        return .all
        case .custom:     return .custom
        }
    }

    private var presetPicker: some View {
        Picker("Selection", selection: Binding(
            get: { preset },
            set: { newValue in
                usesCustomCount = newValue == .count
                switch newValue {
                case .last5:  selection.mode = .latest(5)
                case .last10: selection.mode = .latest(10)
                case .count:
                    customCount = GamePlanSelection.clampedCount(customCount, available: pool.count)
                    selection.mode = .latest(customCount)
                case .all:    selection.mode = .all
                case .custom: break
                }
            }
        )) {
            Text("Last 5").tag(Preset.last5)
            Text("Last 10").tag(Preset.last10)
            Text("Count").tag(Preset.count)
            Text("All").tag(Preset.all)
            if preset == .custom { Text("Custom").tag(Preset.custom) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("game-plan-preset")
    }

    private var selectionSummary: some View {
        let points = selected.reduce(0) { $0 + $1.stats.count }
        let withOutcome = selected.reduce(0) { $0 + $1.stats.filter { $0.outcome != .uncategorized }.count }
        let starts = selected.map(\.startTime)
        let range: String = {
            guard let first = starts.min(), let last = starts.max() else { return "—" }
            let a = Self.dayFormatter.string(from: first), b = Self.dayFormatter.string(from: last)
            return a == b ? a : "\(a) – \(b)"
        }()
        let competitions = Dictionary(grouping: selected, by: GamePlanCompetition.init(record:))
            .sorted { GamePlanCompetition.ordered($0.key, $1.key) }
            .map { "\($0.key.label) \($0.value.count)" }
            .joined(separator: " · ")
        let scoreOnly = selected.filter { $0.stats.isEmpty }.count
        let partial = selected.filter { record in
            let tracked = record.stats.filter { $0.outcome != .uncategorized }.count
            return tracked > 0 && tracked < record.stats.count
        }.count
        return VStack(alignment: .leading, spacing: 3) {
            Text("Dates: \(range)")
            Text("Points: \(points) saved · outcomes on \(GamePlanText.percent(withOutcome, of: points))")
            if !competitions.isEmpty { Text("Competition: \(competitions)") }
            Text("Notes: \(selectedNotes.count) on selected matches")
            if scoreOnly > 0 || partial > 0 {
                Text("Coverage: \(scoreOnly) score only · \(partial) partially tracked")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("game-plan-selection-summary")
    }

    private var filtersGroup: some View {
        DisclosureGroup("Filters\(filter.isActive ? " (on)" : "")") {
            Toggle("From", isOn: $useFromDate)
            if useFromDate {
                DatePicker("From date", selection: $fromDate, displayedComponents: .date)
            }
            Toggle("Through", isOn: $useThroughDate)
            if useThroughDate {
                DatePicker("Through date", selection: $throughDate, displayedComponents: .date)
            }
            ForEach(availableCompetitions) { competition in
                Toggle(competition.label, isOn: Binding(
                    get: { competitionFilter?.contains(competition) ?? true },
                    set: { isOn in
                        var set = competitionFilter ?? Set(availableCompetitions)
                        if isOn { set.insert(competition) } else { set.remove(competition) }
                        competitionFilter = set == Set(availableCompetitions) ? nil : set
                    }
                ))
            }
        }
        .accessibilityIdentifier("game-plan-filters")
    }

    private var exclusionsText: String? {
        let c = candidates
        var parts: [String] = []
        if !c.excludedDoubles.isEmpty {
            parts.append("\(GamePlanText.plural(c.excludedDoubles.count, "doubles match", "doubles matches")) left out: this version prepares singles, and team points can’t show one opponent’s pattern.")
        }
        if !c.excludedInProgress.isEmpty {
            parts.append("\(GamePlanText.plural(c.excludedInProgress.count, "unfinished match", "unfinished matches")) left out.")
        }
        if c.untaggedSinglesCount > 0 {
            parts.append("\(GamePlanText.plural(c.untaggedSinglesCount, "singles match", "singles matches")) in your archive have no opponent tagged and can’t be used until tagged in Match Info.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

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

    @ViewBuilder
    private var privacySection: some View {
        Section {
            Toggle("Include player names", isOn: $includeNames)
                .accessibilityIdentifier("game-plan-include-names")
            if opponent?.playingNotes != nil {
                Toggle("Include playing style notes", isOn: $includePlayingNotes)
                    .accessibilityIdentifier("game-plan-include-playing-notes")
            }
            if notesUnreadable {
                Label("Private notes couldn’t be read, so none can be included. Your notes haven’t been changed.",
                      systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("game-plan-notes-unreadable")
            } else if !selectedNotes.isEmpty {
                Toggle("Include private notes", isOn: Binding(
                    get: { includeNotes },
                    set: { wantsOn in
                        if wantsOn { showNotesReview = true } else { includeNotes = false }
                    }
                ))
                .accessibilityIdentifier("game-plan-include-notes")
                if includeNotes {
                    Button(unreviewedNoteCount > 0
                           ? "Review Notes (\(unreviewedNoteCount) not yet reviewed)"
                           : "Review Notes") { showNotesReview = true }
                }
            }
        } header: {
            Text("Pack Contents")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(MatchExportDisclosure.namesCaption(isOn: includeNames, forAI: true))
                if includePlayingNotes, opponent?.playingNotes != nil {
                    Text("Your Playing Style notes for this opponent are quoted exactly as written. They may mention names or health.")
                }
                if includeNotes && !notesUnreadable {
                    Text("\(selectedNotes.count - omittedNoteIDs.count) of \(selectedNotes.count) notes included, quoted exactly as written. A note added or edited after review stays out until you review it.")
                    if !includeNames {
                        Text(MatchExportDisclosure.namesOffNotesWarning)
                            .foregroundStyle(.orange)
                    }
                }
                Text("Heart rate, steps, calories and other Health data are never included. Notes may still mention health or names.")
            }
        }
    }

    private var detailSection: some View {
        Section {
            Picker("Detail", selection: $detailMode) {
                ForEach(GamePlanDetailMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("game-plan-detail")
            Picker("Delivery", selection: $delivery) {
                Text("One file").tag(GamePlanDelivery.singleFile)
                ForEach(GamePlanDelivery.partTargets, id: \.self) { target in
                    Text("Parts of ~\(GamePlanTokenEstimate(tokens: target).label)").tag(GamePlanDelivery.parts(targetTokens: target))
                }
            }
            .accessibilityIdentifier("game-plan-delivery")
        } header: {
            Text("Detail")
        } footer: {
            Text(detailMode == .full
                 ? "Full detail includes every saved point of every selected match. Nothing is trimmed to fit."
                 : "Summary only keeps each match’s figures and included notes but leaves out the point rows, and says so in the pack.")
        }
    }

    @ViewBuilder
    private var estimateSection: some View {
        Section {
            if let output {
                VStack(alignment: .leading, spacing: 4) {
                    Text(output.pack.totalEstimate.inputLabel)
                        .font(.headline)
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
                NavigationLink {
                    GamePlanPreviewView(output: output)
                } label: {
                    Label("Preview Evidence Pack", systemImage: "doc.text.magnifyingglass")
                }
                .accessibilityIdentifier("game-plan-preview")
            } else if let buildFailure {
                Label(buildFailure, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else {
                HStack(spacing: 10) {
                    ProgressView(value: buildProgress)
                    Text("Estimating…").font(.footnote).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Building the evidence pack")
            }
        } header: {
            Text("Size")
        } footer: {
            Text("An on-device estimate of the input the AI app will read, usually within about \(GamePlanTokenEstimator.documentedErrorPercent)% for tennis tables and English text; notes in other languages vary more. Each AI service counts differently and may add its own overhead. The answer isn’t included. Large packs work best as a shared file.")
        }
    }

    @ViewBuilder
    private var handOffSection: some View {
        Section {
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
            } else {
                Text("Available once the pack is ready.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Hand Off")
        } footer: {
            Text(handOffFooter)
        }
    }

    private var handOffFooter: String {
        let split = output?.pack.isSplit == true
        var text = split
            ? "Send the parts in order. The pack asks the AI to acknowledge each part and wait for the last one."
            : "Copy Prompt copies the whole pack, request included, for pasting. Share Evidence File attaches it as a .txt file with a short message — better for large packs."
        if !installedApps.isEmpty {
            text += split
                ? " Opening an app copies part 1; paste it, then come back for the next part."
                : " Opening an app copies the pack; paste it or attach the file there."
        }
        text += " Opening an app doesn’t mean it received or analysed anything, and copies you share can’t be recalled later."
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
