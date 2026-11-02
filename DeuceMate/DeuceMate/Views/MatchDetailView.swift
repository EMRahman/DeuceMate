// MatchDetailView.swift — iPhone stats view.
// Shows Me vs Opponent stats side-by-side with split bars; no Me/Opp toggle needed.
import SwiftUI
import UIKit
import DeuceMateCore

struct MatchDetailView: View {
    /// The displayed match, re-resolved by id from the live store whenever the
    /// archive changes (tag edits, watch syncs, imports), so the header, Match
    /// Info and the export snapshot never show a stale copy. A watch-only row
    /// (not in the archive) keeps the value it was opened with.
    @State private var record: MatchRecord

    init(record: MatchRecord) {
        _record = State(initialValue: record)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @EnvironmentObject private var syncService: PhoneMatchSyncService
    // Must be supplied by every presenter of MatchDetailView (the PastMatchesView
    // and opponent-history sheets). Used to tell whether this match is still in
    // the phone archive and to restore it on "Sync to iPhone".
    @EnvironmentObject private var store: PhoneStatsStore

    /// Shared reader for the two stored max-HR settings (see MaxHRSetting) so
    /// this view doesn't carry its own copy of their UserDefaults keys.
    var maxHRSetting = MaxHRSetting()
    @AppStorage("playerNTRP") private var playerNTRP: String = "3.0–3.5"
    @State private var tab: Tab = .stats
    @State private var setFilter: SetFilter = .all
    @State private var exportSummary: String = ""
    @State private var exportFull: String = ""
    @State private var exportSummaryOpp: String = ""
    @State private var exportFullOpp: String = ""
    /// Temp-file URLs of the self-contained interactive HTML exports, shared as
    /// files: one framed for me, one framed for the opponent (their "Me", so it
    /// says they won when they did). Built in `.task`, each build in its own
    /// `ExportStaging` generation directory so builds never share a path.
    @State private var htmlExportURL: URL?
    @State private var htmlExportURLOpp: URL?
    @State private var showAICoachSheet: Bool = false
    /// A user action (a share, or the AI Coach hand-off) whose payload carries
    /// HealthKit-derived data, awaiting the per-export disclosure. Non-nil ⇒ the
    /// "Share health data?" alert is shown.
    @State private var pendingDisclosure: PendingHealthDisclosure?
    /// The export currently presented in the system share sheet (set directly for
    /// health-free exports, or after the user confirms the disclosure).
    @State private var activeShare: ShareRequest?
    /// Retired export generations whose files the open share sheet is still
    /// handing out; deleted when that sheet closes (`releaseHeldExports`).
    @State private var exportGenerationsHeldByShare: Set<ExportStaging.Generation> = []
    @State private var showEndAtCurrentScoreConfirmation = false
    @State private var showMatchInfoEditor = false
    @State private var showNotesEditor = false
    /// Share-menu choices for the TEXT and HTML reports (MATCH_TAGS_PLAN.md
    /// 7.3): names ON by default (OQ-2), the private note OFF by default and
    /// only enabled through its review sheet. The AI Coach sheet keeps its own
    /// toggles (both off). Both feed `ExportInputs`, so changing either
    /// rebuilds the snapshot and clears the old files first.
    @State private var shareIncludeNames = true
    @State private var shareIncludeNotes = false
    @State private var showShareNotesReview = false
    @ObservedObject private var notesStore: MatchNotesStore = .shared

    private enum Tab { case stats, points }

    /// Everything the prebuilt export snapshot depends on. A change to any of
    /// these restarts the export task, which clears every cached string and
    /// file URL first - so a file built with a toggle on can never be shared
    /// after the toggle is turned off - and stages its files in a fresh
    /// `ExportStaging` generation.
    private struct ExportInputs: Equatable {
        let record: MatchRecord
        let maxHR: Int
        let ntrp: String
        let includeNames: Bool
        let includeNotes: Bool
        /// The stored note text (so editing a note rebuilds an included copy).
        let noteText: String?
        /// Completed-only head-to-head; a new result rebuilds the context.
        let headToHead: HeadToHeadRecord?
    }

    /// The live private note for this match (nil when none).
    private var noteText: String? { notesStore.note(for: record.id)?.text }

    /// Completed-only head-to-head for this match's own matchup - the same
    /// value Match Info and the compare screen show.
    private var headToHead: HeadToHeadRecord? { HeadToHead.record(for: record, in: store.history) }

    private var hasTaggedPeople: Bool {
        guard let tags = record.tags else { return false }
        return !tags.opponents.isEmpty || tags.partner != nil
    }

    /// The match context the TEXT/HTML reports carry right now.
    private var shareDetails: MatchExportDetails {
        MatchExportDetails(record: record, note: noteText, headToHead: headToHead,
                           includeNames: shareIncludeNames, includeNotes: shareIncludeNotes)
    }

    private var currentExportInputs: ExportInputs {
        ExportInputs(record: record, maxHR: resolvedMaxHR, ntrp: playerNTRP,
                     includeNames: shareIncludeNames,
                     includeNotes: shareIncludeNotes && noteText != nil,
                     noteText: noteText, headToHead: headToHead)
    }

    private var meColor:  Color { theme.colors.me }
    private var oppColor: Color { theme.colors.opponent }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private var title: String {
        if record.isInProgress {
            return Self.dateFormatter.string(from: record.startTime)
        }
        switch record.matchFormat {
        case .superTiebreak: return "Super Tiebreak"
        case .perpetualSuperTiebreak: return "Perpetual Tiebreak"
        case .quick4Games: return "Quick 4 Games"
        case .perpetualPoints: return "Perpetual Points"
        case .standard, .bestOf3FullFinalSet:
            let allUncategorized = record.stats.isEmpty ||
                record.stats.allSatisfy { $0.outcome == .uncategorized }
            return allUncategorized ? "Score Only Match" : "Match Stats"
        }
    }

    private var formatLabel: String {
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

    /// Storage location + iCloud status collapsed into one compact row.
    /// Paired-watch line is still guarded by `isPaired`; iCloud shows unconditionally.
    @ViewBuilder
    private var storageInfoRow: some View {
        let location = MatchStorageResolver.location(
            matchID: record.id,
            onPhone: store.history.contains { $0.id == record.id },
            watchIDs: syncService.onWatchIDs
        )
        let iCloudStatus = ICloudBackupCopy.current(
            isEnabled: true,
            isAvailable: store.isICloudAvailable,
            isRestoring: store.isRestoringFromICloud,
            hasPendingRestore: store.pendingRestorePreview != nil,
            isUploaded: store.isBackupUploaded
        )
        VStack(alignment: .leading, spacing: 4) {
            if syncService.isPaired {
                HStack(spacing: 6) {
                    switch location {
                    case .both:
                        Label("Saved on Apple Watch & iPhone", systemImage: "applewatch")
                        Spacer()
                        Button {
                            syncService.sendDeleteMatchOnWatch(record.id)
                        } label: {
                            Label("Remove from Watch", systemImage: "applewatch.slash")
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    case .phoneOnly:
                        Label("Saved on iPhone only", systemImage: "iphone")
                        Spacer()
                        Button {
                            syncService.sendMatchToWatch(record)
                        } label: {
                            Label("Sync to Watch", systemImage: "applewatch")
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.bordered)
                        .tint(.green)
                    case .watchOnly:
                        Label("Saved on Apple Watch only", systemImage: "applewatch")
                        Spacer()
                        Button {
                            store.syncToPhone(record)
                        } label: {
                            Label("Sync to iPhone", systemImage: "iphone")
                                .fontWeight(.semibold)
                        }
                    }
                }
                .buttonStyle(.borderless)
            }
            Label(iCloudStatus.text, systemImage: iCloudStatus.systemImage)
                .foregroundStyle(
                    iCloudStatus == .unavailable ? AnyShapeStyle(.orange) :
                    iCloudStatus == .pendingRestore ? AnyShapeStyle(.blue) :
                    AnyShapeStyle(.secondary)
                )
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var scoreString: String? {
        guard !record.setScores.isEmpty else { return nil }
        var parts = record.setScores.enumerated().map { index, set in
            SetScoreLabel.string(
                for: set,
                setIndex: index,
                matchFormat: record.matchFormat
            )
        }

        if record.isInProgress,
           record.matchFormat.config.playRegularSets,
           record.setScores.last?.isTieBreak == false,
           let game = MatchRecord.gameScoreString(
               mePoints: record.currentPointsMe,
               oppPoints: record.currentPointsOpponent
           ) {
            parts.append("(\(game))")
        }
        return parts.joined(separator: "  ")
    }


    private var availableSetFilters: [SetFilter] {
        SetFilter.filters(setCount: record.setScores.count)
    }

    private var filteredStats: [PointStat] {
        switch setFilter {
        case .all: return record.stats
        case .set(let i): return record.stats.filter { $0.setIndex == i }
        }
    }

    /// Per-set attribution of the match's Steps and Calories totals.
    private var activitySplit: SetActivitySplit {
        SetActivitySplit(setCount: record.setScores.count,
                         stats: record.stats,
                         setElapsedSeconds: record.setElapsedSeconds,
                         totalSteps: record.totalSteps,
                         totalCaloriesKcal: record.totalCaloriesKcal)
    }

    /// Steps for the current filter: match total for "All", set-specific otherwise.
    private var displayedSteps: Int? {
        switch setFilter {
        case .all: return record.totalSteps
        case .set(let i): return activitySplit.steps[i]
        }
    }

    /// Calories for the current filter: match total for "All", set-specific otherwise.
    private var displayedCalories: Double? {
        switch setFilter {
        case .all: return record.totalCaloriesKcal
        case .set(let i): return activitySplit.calories[i]
        }
    }

    /// Coaching Insights are generated from the whole match plus the selected
    /// set scope so cross-set fatigue rules can still compare against the
    /// preceding set when a single set is chosen.
    private var coachSetScope: RecCoachInsights.SetScope {
        switch setFilter {
        case .all: return .all
        case .set(let i): return .set(i)
        }
    }

    private var coachingInsights: [String] {
        RecCoachInsights.generate(
            stats: record.stats,
            focal: .me,
            setElapsedSeconds: record.setElapsedSeconds,
            setScope: coachSetScope
        )
    }

    private var coachScopeLabel: String? {
        switch setFilter {
        case .all: return nil
        case .set: return setFilter.label(matchFormat: record.matchFormat)
        }
    }

    private var hasOutcomeData: Bool {
        !filteredStats.isEmpty && filteredStats.allSatisfy { $0.outcome != .uncategorized }
    }

    private var hasAnyOutcomeData: Bool {
        filteredStats.contains { $0.outcome != .uncategorized }
    }

    private var resolvedMaxHR: Int { maxHRSetting.resolved }

    private var meSummary: MatchStatsSummary {
        MatchStatsSummary(
            stats: filteredStats,
            focal: .me,
            setElapsedSeconds: record.setElapsedSeconds,
            maxHR: resolvedMaxHR
        )
    }

    private var oppSummary: MatchStatsSummary {
        MatchStatsSummary(
            stats: filteredStats,
            focal: .opponent,
            setElapsedSeconds: record.setElapsedSeconds,
            maxHR: resolvedMaxHR
        )
    }

    private enum ExportMode {
        case summary, full, ai
        case summaryOpp, fullOpp, aiOpp
    }

    private enum SharePerspective { case me, opponent }

    @ViewBuilder
    private func shareButtons(for perspective: SharePerspective) -> some View {
        let isMe = perspective == .me
        let focal: Player = isMe ? .me : .opponent
        let summaryItem = isMe ? exportSummary : exportSummaryOpp
        let fullItem    = isMe ? exportFull    : exportFullOpp
        let summarySubject = isMe ? "Tennis Match Summary" : "Tennis Match Summary — Opponent Perspective"
        let fullSubject    = isMe ? "Tennis Match Summary + Raw Points" : "Tennis Match Summary + Raw Points — Opponent Perspective"

        // Summary omits the raw point-by-point table (includesRawPoints: false);
        // "+ Raw Points" includes it. This distinction matters for the opponent
        // disclosure: only the raw table exposes per-point "Opponent HR".
        Button {
            beginShare(
                items: [TextExportActivityItem(text: summaryItem, subject: summarySubject)],
                focal: focal,
                includesRawPoints: false
            )
        } label: {
            Label("Share Summary", systemImage: "chart.bar.doc.horizontal")
        }
        if !record.stats.isEmpty {
            Button {
                beginShare(
                    items: [TextExportActivityItem(text: fullItem, subject: fullSubject)],
                    focal: focal,
                    includesRawPoints: true
                )
            } label: {
                Label("Share Summary + Raw Points", systemImage: "tablecells")
            }
        }
    }

    /// Route an export through the per-export HealthKit disclosure. When the
    /// export carries no health data for this perspective/kind, share directly;
    /// otherwise show the "Share health data?" alert first. `focal: .me` +
    /// `includesRawPoints: true` covers the recorder-framed HTML and manual paths.
    private func beginShare(items: [Any], focal: Player, includesRawPoints: Bool) {
        let fields = HealthExportConsent.presentFields(
            in: record, focal: focal, includesRawPoints: includesRawPoints
        )
        // An included private note is disclosed in the SAME alert as any
        // health data, so everything leaving the device is one reviewable step.
        let sharesNote = shareDetails.note != nil
        let request = ShareRequest(items: items, healthFields: fields,
                                   includesNote: sharesNote, includeNames: shareIncludeNames)
        if fields.isEmpty && !sharesNote {
            activeShare = request
        } else {
            pendingDisclosure = .share(request)
        }
    }

    /// Route the AI Coach hand-off through the disclosure. The sheet hands the
    /// coaching prompt — which can include the recorder's heart rate, zones,
    /// steps, calories, and distance — to a third-party AI, so disclose the
    /// recorder's full set (`.me`, raw points included: the superset of both
    /// perspectives' prompts). No health ⇒ open the sheet directly.
    private func beginAICoach() {
        let fields = HealthExportConsent.presentFields(in: record, focal: .me, includesRawPoints: true)
        if fields.isEmpty {
            showAICoachSheet = true
        } else {
            pendingDisclosure = .aiCoach(fields)
        }
    }

    /// Perform a disclosed action once the user confirms.
    private func confirmDisclosure(_ disclosure: PendingHealthDisclosure) {
        switch disclosure {
        case .share(let request):
            // The snapshot was rebuilt while the alert was up: its files are
            // gone, and the share menu now offers the current ones instead.
            guard request.stagedFilesExist else { return }
            activeShare = request
        case .aiCoach:            showAICoachSheet = true
        }
    }

    private func exportFilename(for record: MatchRecord, mode: ExportMode = .summary) -> String {
        let suffix: String
        switch mode {
        case .summary:    suffix = ""
        case .full:       suffix = "_full"
        case .ai:         suffix = "_ai_prompt"
        case .summaryOpp: suffix = "_opponent"
        case .fullOpp:    suffix = "_full_opponent"
        case .aiOpp:      suffix = "_ai_prompt_opponent"
        }
        // Date-based only: names and tags never reach a filename.
        return ExportFilenames.text(startTime: record.startTime, suffix: suffix)
    }

    /// Filename for the interactive HTML export framed for `perspective` — the
    /// name the recipient sees. Paths are kept apart by the per-build
    /// `ExportStaging` directory, not by this name. POSIX locale keeps the
    /// format deterministic.
    private func htmlExportFilename(for perspective: Player) -> String {
        ExportFilenames.html(startTime: record.startTime, opponentPerspective: perspective == .opponent)
    }

    /// A published export generation stops being current (newer inputs, or the
    /// screen went away). A pending "Share health data?" for its files is
    /// dropped — it would share a superseded report — and its files are
    /// deleted, unless the share sheet is handing them out right now, in which
    /// case they go when that sheet closes.
    private func retireExportGeneration(_ generation: ExportStaging.Generation) {
        if case .share(let request)? = pendingDisclosure, request.references(generation) {
            pendingDisclosure = nil
        }
        if let activeShare, activeShare.references(generation) {
            exportGenerationsHeldByShare.insert(generation)
        } else {
            ExportStaging.shared.endGeneration(generation)
        }
    }

    private func releaseHeldExports() {
        for generation in exportGenerationsHeldByShare where !(activeShare?.references(generation) ?? false) {
            ExportStaging.shared.endGeneration(generation)
            exportGenerationsHeldByShare.remove(generation)
        }
    }

    /// Generate the interactive HTML framed for `perspective` and stage it in
    /// this build's own `generation` directory, so a superseded build can never
    /// overwrite the file a newer one published. The page carries the full
    /// match record, including HealthKit-derived values, so the staged file
    /// gets the same data-at-rest class as the canonical archive (see
    /// `ExportStaging.write`). `nil` if the write fails.
    nonisolated private static func stageHTMLExport(
        record: MatchRecord, maxHR: Int, perspective: Player,
        aiPromptMe: String, aiPromptOpponent: String?, details: MatchExportDetails, filename: String,
        generation: ExportStaging.Generation, staging: ExportStaging
    ) -> URL? {
        let html = MatchHTMLExporter.html(for: record, maxHR: maxHR, perspective: perspective,
                                          aiPromptMe: aiPromptMe, aiPromptOpponent: aiPromptOpponent,
                                          details: details)
        return try? staging.write(Data(html.utf8), named: filename, in: generation)
    }

    var body: some View {
        List {
            // Header
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(Self.dateFormatter.string(from: record.startTime))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("·")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                        Text(formatLabel)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let score = scoreString {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(styledScore(score, superSize: 14))
                                .font(.title.weight(.bold).monospacedDigit())
                                .accessibilityIdentifier("match-header-score")
                            if !record.isInProgress && record.iWon == nil {
                                Text("Draw")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.orange)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                            } else if let won = record.iWon {
                                Text(won ? "Won" : "Lost")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(won ? meColor : oppColor)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(won
                                                  ? meColor.opacity(0.15)
                                                  : oppColor.opacity(0.15))
                                    )
                            }
                        }
                    }

                    if record.isInProgress {
                        Label("In Progress", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        Button(role: .destructive) {
                            showEndAtCurrentScoreConfirmation = true
                        } label: {
                            Label("End at Current Score", systemImage: "stop.circle.fill")
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.bordered)
                    }
                    if !filteredStats.isEmpty && tab == .stats {
                        pointsWonHeader
                    }
                }
                .padding(.vertical, 6)
            }

            // Opponent / competition, private note, and the previous-match
            // comparison (MATCH_TAGS_PLAN.md §7.1). Editable for completed and
            // in-progress archived matches; never changes the score.
            MatchInfoSection(
                record: record,
                isInArchive: store.history.contains { $0.id == record.id },
                showEditor: $showMatchInfoEditor,
                showNotesEditor: $showNotesEditor
            )

            // Keep the graph route visible for manually entered matches. Its
            // explicit empty state explains why there is no point-level chart.
            Section("Points Graph") {
                PointsGraphView(record: record)
            }

            if !record.stats.isEmpty {
                // Stats / Points tab switcher
                Section {
                    Picker("View", selection: $tab) {
                        Text("Stats").tag(Tab.stats)
                        Text("Points").tag(Tab.points)
                    }
                    .pickerStyle(.segmented)
                }
            }

            if !record.stats.isEmpty && tab == .stats {
                // Set filter
                if availableSetFilters.count > 2 {
                    Section {
                        Picker("Set", selection: $setFilter) {
                            ForEach(availableSetFilters, id: \.self) { f in
                                Text(f.label(matchFormat: record.matchFormat)).tag(f)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                // Set durations + activity
                Section("Duration") {
                    setDurationRows
                    if let steps = displayedSteps, steps > 0 {
                        statRow("Steps", steps.formatted())
                    }
                    if let kcal = displayedCalories, kcal > 0 {
                        statRow("Calories", MatchRecord.formattedCalories(kcal))
                    }
                }

                RecCoachSection(
                    insights: coachingInsights,
                    scopeLabel: coachScopeLabel,
                    categorizedCount: filteredStats.filter { $0.outcome != .uncategorized }.count
                )

                PulseCoachSection(
                    summary: meSummary,
                    record: record,
                    filteredStats: filteredStats
                )

                if hasAnyOutcomeData {
                    Section(header: comparisonSectionHeader("Outcome Breakdown")) {
                        wueRatioRow
                        countComparisonRow("Winners",
                            meCount: meSummary.myWinners,       oppCount: oppSummary.myWinners)
                        countComparisonRow("Unforced Errors",
                            meCount: meSummary.myUnforcedErrors, oppCount: oppSummary.myUnforcedErrors)
                        countComparisonRow("Forced Errors",
                            meCount: meSummary.myForcedErrors,   oppCount: oppSummary.myForcedErrors)
                        countComparisonRow("Double Faults",
                            meCount: meSummary.myDoubleFaults,   oppCount: oppSummary.myDoubleFaults)
                        comparisonRow("Aggression Index",
                            subtitle: "W ÷ (W + UE)",
                            meNum: meSummary.myWinners,
                                   meDen: meSummary.myWinners + meSummary.myUnforcedErrors,
                            oppNum: oppSummary.myWinners,
                                   oppDen: oppSummary.myWinners + oppSummary.myUnforcedErrors)
                        comparisonRow("Own Errors %",
                            meNum: meSummary.myDoubleFaults + meSummary.myUnforcedErrors,
                                   meDen: meSummary.lostPoints,
                            oppNum: oppSummary.myDoubleFaults + oppSummary.myUnforcedErrors,
                                   oppDen: oppSummary.lostPoints)
                    }
                } else {
                    Section("Outcome Breakdown") {
                        Text("Outcome tracking not collected for this match.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if hasOutcomeData {
                    Section(header: comparisonSectionHeader("Serve")) {
                        comparisonRow("1st Serve In",
                            meNum: meSummary.firstServeIn,    meDen: meSummary.firstServeTotal,
                            oppNum: oppSummary.firstServeIn,  oppDen: oppSummary.firstServeTotal)
                        comparisonRow("2nd Serve In",
                            meNum: meSummary.secondServeIn,    meDen: meSummary.secondServeTotal,
                            oppNum: oppSummary.secondServeIn,  oppDen: oppSummary.secondServeTotal)
                        comparisonRow("1st Serve Win",
                            meNum: meSummary.firstServeWins,   meDen: meSummary.firstServeIn,
                            oppNum: oppSummary.firstServeWins, oppDen: oppSummary.firstServeIn)
                        comparisonRow("2nd Serve Win",
                            meNum: meSummary.secondServeWins,   meDen: meSummary.secondServeIn,
                            oppNum: oppSummary.secondServeWins, oppDen: oppSummary.secondServeIn)
                        comparisonRow("DF Rate (2nd)",
                            meNum: meSummary.doubleFaults,    meDen: meSummary.secondServeTotal,
                            oppNum: oppSummary.doubleFaults,  oppDen: oppSummary.secondServeTotal)
                    }

                    Section(header: comparisonSectionHeader("Return")) {
                        comparisonRow("vs 1st Serve",
                            meNum: meSummary.returnWinsOnFirst,    meDen: meSummary.returnOppsOnFirst,
                            oppNum: oppSummary.returnWinsOnFirst,  oppDen: oppSummary.returnOppsOnFirst)
                        comparisonRow("vs 2nd Serve",
                            meNum: meSummary.returnWinsOnSecond,   meDen: meSummary.returnOppsOnSecond,
                            oppNum: oppSummary.returnWinsOnSecond, oppDen: oppSummary.returnOppsOnSecond)
                    }
                }

                Section(header: comparisonSectionHeader("Break Points")) {
                    comparisonRow("BPs Won (Returner)",
                        meNum: meSummary.breakPointWins,   meDen: meSummary.breakPointOpps,
                        oppNum: oppSummary.breakPointWins, oppDen: oppSummary.breakPointOpps)
                    comparisonRow("BPs Saved (Server)",
                        meNum: meSummary.breakPointsFaced - meSummary.breakPointsLost,
                               meDen: meSummary.breakPointsFaced,
                        oppNum: oppSummary.breakPointsFaced - oppSummary.breakPointsLost,
                               oppDen: oppSummary.breakPointsFaced)
                }

                if meSummary.bigPointTotal > 0 && meSummary.normalPointTotal > 0 {
                    Section(header: comparisonSectionHeader("Pressure vs Normal")) {
                        comparisonRow("Big Points",
                            meNum: meSummary.bigPointWins,    meDen: meSummary.bigPointTotal,
                            oppNum: oppSummary.bigPointWins,  oppDen: oppSummary.bigPointTotal)
                        comparisonRow("Normal Points",
                            meNum: meSummary.normalPointWins,   meDen: meSummary.normalPointTotal,
                            oppNum: oppSummary.normalPointWins, oppDen: oppSummary.normalPointTotal)
                    }
                }

                if !meSummary.rallyDepth.isEmpty {
                    Section(header: comparisonSectionHeader("Rally Depth Won")) {
                        ForEach(meSummary.rallyDepth, id: \.shot) { meRd in
                            let oppRd = oppSummary.rallyDepth.first { $0.shot == meRd.shot }
                            comparisonRow("@ \(meRd.shot.displayLabel)",
                                meNum: meRd.wins,        meDen: meRd.total,
                                oppNum: oppRd?.wins ?? 0, oppDen: oppRd?.total ?? 0)
                        }
                    }
                }

                if !meSummary.scoreStates.isEmpty {
                    Section(header: comparisonSectionHeader("Score States")) {
                        ForEach(meSummary.scoreStates, id: \.label) { meSs in
                            let oppSs = oppSummary.scoreStates.first { $0.label == meSs.label }
                            comparisonRow(meSs.label,
                                meNum: meSs.wins,        meDen: meSs.total,
                                oppNum: oppSs?.wins ?? 0, oppDen: oppSs?.total ?? 0)
                        }
                    }
                }

                if meSummary.uncategorizedCount > 0 {
                    Section {
                        Text("\(meSummary.uncategorizedCount) uncategorized point(s) excluded from outcome stats.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

            } else if !record.stats.isEmpty && tab == .points {
                pointsListSections
            } else if record.stats.isEmpty {
                Section {
                    Text("No point-by-point statistics were recorded for this match.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Storage Info") {
                storageInfoRow
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        // Keep the shown record current: tag edits, watch syncs and imports
        // replace the archive copy, and the export snapshot below is rebuilt
        // from whatever this resolves to.
        .onReceive(store.$history) { history in
            if let latest = history.first(where: { $0.id == record.id }), latest != record {
                record = latest
            }
        }
        // The share/AI exports are a prebuilt snapshot of `record`. Rebuild
        // them whenever the record (or an export input) changes, and clear the
        // old snapshot first so a stale copy can never be shared meanwhile.
        // Each run owns one `ExportStaging` generation (its own directory) for
        // the files it stages: a superseded run deletes its own files instead
        // of publishing them, and a published run keeps its files only until
        // SwiftUI cancels it (newer inputs, or the screen going away).
        .task(id: currentExportInputs) {
            exportSummary = ""; exportFull = ""; exportSummaryOpp = ""; exportFullOpp = ""
            htmlExportURL = nil; htmlExportURLOpp = nil
            let record = record
            let maxHR = resolvedMaxHR
            let filename = htmlExportFilename(for: .me)
            let filenameOpp = htmlExportFilename(for: .opponent)
            let ntrp = playerNTRP
            let staging = ExportStaging.shared
            let generation = staging.beginGeneration()
            // The names/notes choices were applied when `details` was built, so
            // none of the builders below can see what the user left out.
            let details = shareDetails
            async let summary    = Task.detached { MatchExporter.summaryExport(for: record, maxHR: maxHR, focal: .me, details: details)       }.value
            async let full       = Task.detached { MatchExporter.fullExport(for: record,    maxHR: maxHR, focal: .me, details: details)       }.value
            async let summaryOpp = Task.detached { MatchExporter.summaryExport(for: record, maxHR: maxHR, focal: .opponent, details: details) }.value
            async let fullOpp    = Task.detached { MatchExporter.fullExport(for: record,    maxHR: maxHR, focal: .opponent, details: details) }.value
            // Generate AND write both interactive HTML files (mine + the
            // opponent's) off the main thread so the ~30-80 KB file writes never
            // stutter the UI. The AI coaching prompts embedded in the page follow
            // the SAME names/notes choices as the page itself; the opponent's
            // page offers only theirs.
            async let htmlURLs   = Task.detached { () -> (URL?, URL?) in
                // Leftovers of builds that never ended (e.g. the app was killed).
                staging.sweepInactive()
                let aiMe  = MatchExporter.aiPromptExport(for: record, maxHR: maxHR, focal: .me, playerNTRP: ntrp, details: details)
                let aiOpp = record.stats.isEmpty
                    ? nil
                    : MatchExporter.aiPromptExport(for: record, maxHR: maxHR, focal: .opponent, playerNTRP: ntrp, details: details)
                let mine = Self.stageHTMLExport(record: record, maxHR: maxHR, perspective: .me,
                                                aiPromptMe: aiMe, aiPromptOpponent: aiOpp, details: details,
                                                filename: filename, generation: generation, staging: staging)
                let theirs = Self.stageHTMLExport(record: record, maxHR: maxHR, perspective: .opponent,
                                                  aiPromptMe: aiMe, aiPromptOpponent: aiOpp, details: details,
                                                  filename: filenameOpp, generation: generation, staging: staging)
                return (mine, theirs)
            }.value
            // Awaiting the detached writer means its files are complete before
            // either branch below can delete them.
            let (s, f, so, fo, urls) = await (summary, full, summaryOpp, fullOpp, htmlURLs)
            // A newer record or toggle superseded this build while it ran: drop
            // it, files included - they were never published.
            guard !Task.isCancelled else {
                staging.endGeneration(generation)
                return
            }
            exportSummary = s; exportFull = f; exportSummaryOpp = so; exportFullOpp = fo
            (htmlExportURL, htmlExportURLOpp) = urls
            // Keep this generation's files exactly as long as they are the
            // published snapshot. The next run clears the URLs before it
            // starts, so deleting here never strands a shown share option.
            await ExportStaging.waitUntilCancelled()
            retireExportGeneration(generation)
        }
        // A deleted note can no longer be "included": reset the opt-in so a
        // later note starts from the default (off) and is reviewed again.
        .onChange(of: noteText) { _, newValue in
            if newValue == nil { shareIncludeNotes = false }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if exportSummary.isEmpty {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        beginAICoach()
                    } label: {
                        Label("AI Coach", systemImage: "sparkles")
                            .labelStyle(.titleAndIcon)
                    }
                    .accessibilityLabel("AI Coach")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if !exportSummary.isEmpty {
                    Menu {
                        if hasTaggedPeople || noteText != nil {
                            Section {
                                if hasTaggedPeople {
                                    Toggle("Include player names", isOn: $shareIncludeNames)
                                }
                                if noteText != nil {
                                    Toggle("Include private note", isOn: Binding(
                                        get: { shareIncludeNotes },
                                        set: { wantsOn in
                                            // ON goes through the review sheet; OFF is immediate.
                                            if wantsOn { showShareNotesReview = true } else { shareIncludeNotes = false }
                                        }
                                    ))
                                }
                            } header: {
                                Text("Include in Reports")
                            }
                        }
                        if htmlExportURL != nil || htmlExportURLOpp != nil {
                            Section {
                                Menu {
                                    // Each page carries the per-point HR/steps, so
                                    // disclose as that perspective + raw points.
                                    if let htmlExportURL {
                                        Button("My Perspective") {
                                            beginShare(items: [htmlExportURL], focal: .me, includesRawPoints: true)
                                        }
                                    }
                                    if let htmlExportURLOpp {
                                        Button("Opponent's Perspective") {
                                            beginShare(items: [htmlExportURLOpp], focal: .opponent,
                                                       includesRawPoints: true)
                                        }
                                    }
                                } label: {
                                    Label("Interactive Web Page", systemImage: "safari")
                                }
                            } header: {
                                Text("Interactive")
                            }
                        }
                        Section {
                            shareButtons(for: .me)
                        } header: {
                            Text("My Stats")
                                .foregroundStyle(meColor)
                        }
                        Section {
                            shareButtons(for: .opponent)
                        } header: {
                            Text("Opponent's Stats")
                                .foregroundStyle(oppColor)
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export match")
                }
            }
        }
        .sheet(isPresented: $showAICoachSheet) {
            aiCoachSheet
        }
        .confirmationDialog(
            "End at current score?",
            isPresented: $showEndAtCurrentScoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("End at Current Score", role: .destructive) {
                endAtCurrentScore()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This marks the match completed and it can no longer be resumed. A tied score is saved as a draw.")
        }
        // Per-export HealthKit disclosure (Blocker 4), shared by the export share
        // sheet and the AI Coach hand-off. Naming + the recipient clause come
        // from Core's single source; confirming proceeds full-fidelity.
        .alert(
            disclosureTitle,
            isPresented: Binding(
                get: { pendingDisclosure != nil },
                set: { if !$0 { pendingDisclosure = nil } }
            ),
            presenting: pendingDisclosure
        ) { disclosure in
            Button(disclosure.confirmLabel) {
                // Defer to the next runloop so the alert fully dismisses before
                // the share / AI Coach sheet presents (a same-tick present can be
                // dropped mid-transition).
                DispatchQueue.main.async { confirmDisclosure(disclosure) }
            }
            Button("Cancel", role: .cancel) { }
        } message: { disclosure in
            Text(disclosureMessage(for: disclosure))
        }
        .sheet(isPresented: $showShareNotesReview) {
            if let noteText {
                NotesExportReviewSheet(
                    noteText: noteText,
                    includeNames: shareIncludeNames,
                    destination: "text and web reports",
                    onConfirm: {
                        shareIncludeNotes = true
                        showShareNotesReview = false
                    },
                    onCancel: { showShareNotesReview = false }
                )
            }
        }
        .sheet(item: $activeShare, onDismiss: releaseHeldExports) { request in
            ShareSheet(activityItems: request.items) { activeShare = nil }
        }
        .sheet(isPresented: $showMatchInfoEditor) {
            MatchInfoEditorView(record: record)
                .environmentObject(store)
                .environmentObject(syncService)
        }
        .sheet(isPresented: $showNotesEditor) {
            MatchNotesEditorView(matchID: record.id)
        }
    }

    /// AI Coach hand-off. The sheet owns its own names/notes toggles (both off
    /// by default) and rebuilds the prompt from this pure closure on change.
    private var aiCoachSheet: some View {
        let record = record
        let maxHR = resolvedMaxHR
        let ntrp = playerNTRP
        let note = noteText
        let h2h = headToHead
        return AICoachSheet(
            buildPrompt: { focal, names, notes in
                MatchExporter.aiPromptExport(
                    for: record, maxHR: maxHR, focal: focal, playerNTRP: ntrp,
                    details: MatchExportDetails(record: record, note: note, headToHead: h2h,
                                                includeNames: names, includeNotes: notes)
                )
            },
            hasOpponentPrompt: !record.stats.isEmpty,
            filenameMe: exportFilename(for: record, mode: .ai),
            filenameOpponent: exportFilename(for: record, mode: .aiOpp),
            hasTaggedPeople: hasTaggedPeople,
            noteText: note,
            sourceIdentity: AICoachSourceIdentity(
                record: record, maxHR: maxHR, playerNTRP: ntrp, note: note, headToHead: h2h)
        )
    }

    private var disclosureTitle: String {
        guard let disclosure = pendingDisclosure else { return "Share health data?" }
        switch (disclosure.fields.isEmpty, disclosure.includesNote) {
        case (false, false): return "Share health data?"
        case (false, true):  return "Share health data and private note?"
        case (true, _):      return "Share private note?"
        }
    }

    private func disclosureMessage(for disclosure: PendingHealthDisclosure) -> String {
        let health = disclosure.fields.isEmpty
            ? nil
            : HealthExportConsent.disclosure(fields: disclosure.fields, destination: disclosure.destination).message
        return MatchExportDisclosure.combinedMessage(
            healthMessage: health,
            includesNotes: disclosure.includesNote,
            includeNames: disclosure.includeNames
        ) ?? ""
    }

    private func endAtCurrentScore() {
        let latest = store.loadHistory().first(where: { $0.id == record.id }) ?? record
        guard latest.isInProgress else {
            dismiss()
            return
        }
        let completed = latest.endingAtCurrentScore()
        let shouldUpdateWatch = syncService.onWatchIDs.contains(record.id)
            || syncService.activeMatchID == record.id
        store.appendMatch(completed)
        if shouldUpdateWatch {
            syncService.sendMatchToWatch(completed)
        }
        dismiss()
    }

    // MARK: - Points list

    @ViewBuilder
    private var pointsListSections: some View {
        let grouped = Dictionary(grouping: record.stats, by: \.setIndex)
        let setIndices = grouped.keys.sorted()
        let matchScores = PointMatchScore.atStart(of: record.stats, record: record)
        let perPointSteps = perPointStepsByID
        ForEach(setIndices, id: \.self) { setIdx in
            let points = grouped[setIdx] ?? []
            Section(SetFilter.set(setIdx).label(matchFormat: record.matchFormat)) {
                ForEach(Array(points.enumerated()), id: \.element.id) { idx, pt in
                    pointRow(
                        number: idx + 1,
                        point: pt,
                        matchScore: matchScores[pt.id],
                        perPointSteps: perPointSteps[pt.id]
                    )
                }
            }
        }
    }

    private var perPointStepsByID: [PointStat.ID: Int] {
        let series = StepsSeries.make(stats: record.stats, totalSteps: record.totalSteps)
        return Dictionary(uniqueKeysWithValues: series.compactMap { sample in
            guard record.stats.indices.contains(sample.pointIndex) else { return nil }
            return (record.stats[sample.pointIndex].id, sample.perPoint)
        })
    }

    @ViewBuilder
    private func pointRow(
        number: Int,
        point: PointStat,
        matchScore: PointMatchScore.Snapshot?,
        perPointSteps: Int?
    ) -> some View {
        HStack(spacing: 8) {
            Text("\(number)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(minWidth: 22, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                if let matchScore, !matchScore.label.isEmpty {
                    Text(matchScore.label)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 4) {
                    PointServiceStatusLabel(isServing: point.server == .me)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if let score = point.gameScoreAtStart {
                        Text(GameScoreLabel.string(for: score, server: point.server))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if point.isBreakPoint {
                        Text("BP")
                            .font(.caption2.bold())
                            .foregroundStyle(.orange)
                    }
                    if point.isSecondServe {
                        Text("2nd")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    outcomeChip(for: point)
                    Text(outcomeLabel(point))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            }

            Spacer()

            if point.endingShot != nil || point.heartRateBPM != nil || perPointSteps != nil {
                VStack(alignment: .trailing, spacing: 2) {
                    if let shot = point.endingShot {
                        Text(shot.displayLabel)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if let bpm = point.heartRateBPM {
                        Text("My HR: \(bpm) bpm")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if let perPointSteps {
                        Text("\(perPointSteps) steps")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(pointAccessibilityLabel(
                number: number,
                point: point,
                matchScore: matchScore,
                perPointSteps: perPointSteps
            ))
        )
    }

    private func pointAccessibilityLabel(
        number: Int,
        point: PointStat,
        matchScore: PointMatchScore.Snapshot?,
        perPointSteps: Int?
    ) -> String {
        var parts = [
            "Set \(point.setIndex + 1), point \(number)",
            point.server == .me ? "Serving" : "Receiving"
        ]
        if let label = matchScore?.label, !label.isEmpty {
            parts.append("Match score \(label)")
        }
        if let score = point.gameScoreAtStart {
            parts.append("Game score \(GameScoreLabel.string(for: score, server: point.server))")
        }
        if point.isBreakPoint { parts.append("Break point") }
        if point.isSecondServe { parts.append("Second serve") }
        parts.append(outcomeLabel(point))
        if let shot = point.endingShot { parts.append(shot.displayLabel) }
        if let bpm = point.heartRateBPM { parts.append("My heart rate \(bpm) beats per minute") }
        if let perPointSteps { parts.append("\(perPointSteps) steps") }
        return parts.joined(separator: ", ")
    }

    private func outcomeLabel(_ point: PointStat) -> String {
        let winnerName = point.winner == .me ? "Me" : "Opp"
        switch point.outcome {
        case .winner:        return "Winner — \(winnerName)"
        case .doubleFault:   return "Double Fault — \(point.server == .me ? "Me" : "Opp")"
        case .unforcedError: return "Unforced Err — \(point.winner == .me ? "Opp" : "Me")"
        case .forcedError:   return "Forced Err — \(point.winner == .me ? "Opp" : "Me")"
        case .uncategorized: return "Point — \(winnerName)"
        }
    }

    @ViewBuilder
    private func outcomeChip(for point: PointStat) -> some View {
        let isWin = point.winner == .me
        let (chipColor, chipText): (Color, String) = {
            switch point.outcome {
            case .winner:
                return (isWin ? meColor : oppColor, isWin ? "W" : "Opp W")
            case .doubleFault:
                // Color the server who committed the double fault
                return (point.server == .me ? meColor : oppColor, "DF")
            case .unforcedError:
                // Color the player who made the error (loser of the point)
                return (isWin ? oppColor : meColor, "UE")
            case .forcedError:
                return (isWin ? oppColor : meColor, "FE")
            case .uncategorized:
                return (isWin ? meColor : oppColor, isWin ? "+" : "−")
            }
        }()
        Text(chipText)
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(chipColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(chipColor.opacity(0.15)))
    }

    // MARK: - Duration

    @ViewBuilder
    private var setDurationRows: some View {
        let indices = setFilter.setIndices(setCount: record.setScores.count)
        ForEach(indices, id: \.self) { i in
            let label = indices.count > 1 ? "\(SetFilter.set(i).label(matchFormat: record.matchFormat)) Duration" : "Duration"
            if let secs = MatchDurations.setElapsedSeconds(record, setIndex: i) {
                statRow(label, MatchDurations.minutesString(secs))
            }
        }
    }

    // MARK: - Visual header bar

    @ViewBuilder
    private var pointsWonHeader: some View {
        let total  = meSummary.totalPoints
        let meWon  = meSummary.pointsWon
        let oppWon = total - meWon
        if total > 0 {
            let mePct  = StatFormatting.roundedPercent(meWon,  of: total)
            let oppPct = StatFormatting.roundedPercent(oppWon, of: total)
            VStack(spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Me")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(meColor)
                        Text("\(meWon) pts · \(mePct)%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(meColor)
                    }
                    Spacer()
                    VStack(spacing: 1) {
                        Text("Points Won")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(total) total")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Opp")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(oppColor)
                        Text("\(oppWon) pts · \(oppPct)%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(oppColor)
                    }
                }

                GeometryReader { geo in
                    let meFrac  = Double(meWon)  / Double(total)
                    let oppFrac = Double(oppWon) / Double(total)
                    let spacing: CGFloat = 3
                    let availableWidth = max(0, geo.size.width - spacing)
                    HStack(spacing: spacing) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(meColor)
                            .frame(width: availableWidth * meFrac)
                        RoundedRectangle(cornerRadius: 5)
                            .fill(oppColor)
                            .frame(width: availableWidth * oppFrac)
                    }
                }
                .frame(height: 16)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var wueRatioRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Win : Unforced Err")
                    .foregroundStyle(.primary)
                Text("aim for > 1.0")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 4) {
                Text(meSummary.wueRatio.formatted)
                    .foregroundStyle(meColor)
                Text("/")
                    .foregroundStyle(.secondary)
                Text(oppSummary.wueRatio.formatted)
                    .foregroundStyle(oppColor)
            }
            .font(.body.monospacedDigit())
        }
    }

    // MARK: - Comparison primitives

    @ViewBuilder
    private func comparisonSectionHeader(_ title: String) -> some View {
        HStack {
            Text("Me")
                .font(.caption.weight(.semibold))
                .foregroundStyle(meColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(meColor.opacity(0.15)))
            Spacer()
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(nil)
            Spacer()
            Text("Opp")
                .font(.caption.weight(.semibold))
                .foregroundStyle(oppColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(oppColor.opacity(0.15)))
        }
    }

    @ViewBuilder
    private func comparisonRow(
        _ label: String,
        subtitle: String? = nil,
        meNum: Int, meDen: Int,
        oppNum: Int, oppDen: Int
    ) -> some View {
        let me  = RatioDisplay(numerator: meNum,  denominator: meDen)
        let opp = RatioDisplay(numerator: oppNum, denominator: oppDen)
        let meFrac  = me.fraction
        let oppFrac = opp.fraction
        let meText  = me.percentText
        let oppText = opp.percentText
        let meLabel  = me.countText
        let oppLabel = opp.countText

        VStack(spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            HStack(spacing: 4) {
                Text(meText)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(meColor)
                    .frame(width: 44, alignment: .trailing)
                splitBar(meFrac: meFrac, oppFrac: oppFrac, meLabel: meLabel, oppLabel: oppLabel)
                Text(oppText)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(oppColor)
                    .frame(width: 44, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func countComparisonRow(_ label: String, meCount: Int, oppCount: Int) -> some View {
        let maxVal  = max(meCount, oppCount, 1)
        let meFrac  = Double(meCount)  / Double(maxVal)
        let oppFrac = Double(oppCount) / Double(maxVal)

        VStack(spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            HStack(spacing: 4) {
                Text("\(meCount)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(meColor)
                    .frame(width: 44, alignment: .trailing)
                splitBar(meFrac: meFrac, oppFrac: oppFrac)
                Text("\(oppCount)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(oppColor)
                    .frame(width: 44, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func splitBar(
        meFrac: Double, oppFrac: Double,
        meLabel: String? = nil, oppLabel: String? = nil
    ) -> some View {
        GeometryReader { geo in
            let halfW = max(0, (geo.size.width - 1) / 2)
            HStack(spacing: 0) {
                Rectangle()
                    .fill(meColor.opacity(0.15))
                    .frame(width: halfW)
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(meColor)
                            .frame(width: halfW * meFrac)
                    }
                    .overlay { barLabel(meLabel) }
                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: 1)
                Rectangle()
                    .fill(oppColor.opacity(0.15))
                    .frame(width: halfW)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(oppColor)
                            .frame(width: halfW * oppFrac)
                    }
                    .overlay { barLabel(oppLabel) }
            }
        }
        .frame(height: 18)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    /// Raw count (e.g. "12/15") centered inside a bar half. `.primary` keeps it
    /// legible over both the pale track and the saturated fill in light/dark.
    @ViewBuilder
    private func barLabel(_ text: String?) -> some View {
        if let text {
            Text(text)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 2)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Share plumbing

/// An export the user chose to share, plus the HealthKit-derived fields it
/// carries (empty ⇒ no disclosure needed). `Identifiable` drives `.sheet(item:)`.
private struct ShareRequest: Identifiable {
    let id = UUID()
    let items: [Any]
    let healthFields: [HealthExportField]
    /// Whether the shared files/text carry the user's private note, and whether
    /// names were on - both are disclosed in the same alert as health data.
    var includesNote: Bool = false
    var includeNames: Bool = true

    private var fileURLs: [URL] { items.compactMap { $0 as? URL }.filter(\.isFileURL) }

    /// Whether this share hands out a file staged in `generation`.
    func references(_ generation: ExportStaging.Generation) -> Bool {
        fileURLs.contains(where: generation.contains)
    }

    /// False once a staged file it carries has been deleted (its generation
    /// was retired while the request waited).
    var stagedFilesExist: Bool {
        fileURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
    }
}

/// A user action awaiting the per-export HealthKit disclosure: either a system
/// share (present the share sheet) or the AI Coach hand-off (open its sheet).
/// Drives one shared "Share health data?" alert so the copy stays consistent.
private enum PendingHealthDisclosure: Identifiable {
    case share(ShareRequest)
    case aiCoach([HealthExportField])

    var id: String {
        switch self {
        case .share(let request): return "share-\(request.id)"
        case .aiCoach:            return "ai-coach"
        }
    }

    var fields: [HealthExportField] {
        switch self {
        case .share(let request):  return request.healthFields
        case .aiCoach(let fields): return fields
        }
    }

    var includesNote: Bool {
        if case .share(let request) = self { return request.includesNote }
        return false
    }

    var includeNames: Bool {
        if case .share(let request) = self { return request.includeNames }
        return true
    }

    var destination: HealthExportDestination {
        // Both use `.sharedReport`: the AI Coach sheet hands off to an AI app but
        // also exposes general share options (Mail, Files, …), so its disclosure
        // must name the broad set of recipients, not just "an AI service".
        .sharedReport
    }

    /// Affirmative button label: a share "Share"s; the AI hand-off "Continue"s to
    /// the AI Coach sheet (nothing leaves until the user launches/copies there).
    var confirmLabel: String {
        switch self {
        case .share:   return "Share"
        case .aiCoach: return "Continue"
        }
    }
}

/// Wraps a text export so the system share sheet still offers a Mail subject
/// (parity with the previous `ShareLink(subject:)`).
private final class TextExportActivityItem: NSObject, UIActivityItemSource {
    private let text: String
    private let subject: String

    init(text: String, subject: String) {
        self.text = text
        self.subject = subject
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any { text }

    func activityViewController(
        _ controller: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? { text }

    func activityViewController(
        _ controller: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String { subject }
}

/// Minimal `UIActivityViewController` bridge so the share sheet can be presented
/// programmatically after the disclosure — SwiftUI's `ShareLink` shares on tap
/// with no pre-share hook. `onComplete` clears the presenting binding once the
/// user finishes or cancels the share.
private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var onComplete: () -> Void = {}

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onComplete() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
