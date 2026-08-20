// MatchDetailView.swift — iPhone stats view.
// Shows Me vs Opponent stats side-by-side with split bars; no Me/Opp toggle needed.
import SwiftUI
import UIKit
import DeuceMateCore

struct MatchDetailView: View {
    let record: MatchRecord

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @EnvironmentObject private var syncService: PhoneMatchSyncService
    // Must be supplied by every presenter of MatchDetailView (only the
    // PastMatchesView sheet today). Used to tell whether this match is still in
    // the phone archive and to restore it on "Sync to iPhone".
    @EnvironmentObject private var store: PhoneStatsStore

    @AppStorage("userBirthYear") private var userBirthYear: Int = 0
    @AppStorage("userMaxHROverride") private var userMaxHROverride: Int = 0
    @AppStorage("playerNTRP") private var playerNTRP: String = "3.0–3.5"
    @State private var tab: Tab = .stats
    @State private var setFilter: SetFilter = .all
    @State private var exportSummary: String = ""
    @State private var exportFull: String = ""
    @State private var exportAI: String = ""
    @State private var exportSummaryOpp: String = ""
    @State private var exportFullOpp: String = ""
    @State private var exportAIOpp: String = ""
    /// Temp-file URL of the self-contained interactive HTML export, shared as a
    /// file (both perspectives live inside it behind a toggle, so it is a single
    /// entry rather than per-perspective). Built once in `.task`.
    @State private var htmlExportURL: URL?
    @State private var showAICoachSheet: Bool = false
    /// A user action (a share, or the AI Coach hand-off) whose payload carries
    /// HealthKit-derived data, awaiting the per-export disclosure. Non-nil ⇒ the
    /// "Share health data?" alert is shown.
    @State private var pendingDisclosure: PendingHealthDisclosure?
    /// The export currently presented in the system share sheet (set directly for
    /// health-free exports, or after the user confirms the disclosure).
    @State private var activeShare: ShareRequest?

    private enum Tab { case stats, points }

    private enum SetFilter: Hashable {
        case all
        case set(Int)

        func label(matchFormat: MatchFormat) -> String {
            switch self {
            case .all: return "All"
            case .set(let i):
                return matchFormat.config.isDecidingSuperTiebreak(setIndex: i) ? "TB" : "Set \(i + 1)"
            }
        }
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
        var result: [SetFilter] = [.all]
        for i in 0..<record.setScores.count { result.append(.set(i)) }
        return result
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

    private var resolvedMaxHR: Int {
        HRZone.resolveMaxHR(
            manualOverride: userMaxHROverride > 0 ? userMaxHROverride : nil,
            birthYear: userBirthYear > 0 ? userBirthYear : nil
        )
    }

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
        let request = ShareRequest(items: items, healthFields: fields)
        if fields.isEmpty {
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
        case .share(let request): activeShare = request
        case .aiCoach:            showAICoachSheet = true
        }
    }

    private func exportFilename(for record: MatchRecord, mode: ExportMode = .summary) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        let suffix: String
        switch mode {
        case .summary:    suffix = ""
        case .full:       suffix = "_full"
        case .ai:         suffix = "_ai_prompt"
        case .summaryOpp: suffix = "_opponent"
        case .fullOpp:    suffix = "_full_opponent"
        case .aiOpp:      suffix = "_ai_prompt_opponent"
        }
        return "deuce_mate_\(f.string(from: record.startTime))\(suffix).txt"
    }

    /// Filename for the interactive HTML export (single file, both perspectives).
    /// Includes the match start time so same-day matches don't collide in the
    /// temporary directory. POSIX locale keeps the format deterministic.
    private var htmlExportFilename: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HHmm"
        return "deuce_mate_\(f.string(from: record.startTime)).html"
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
                        Label("In Progress — view only on iPhone", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if !filteredStats.isEmpty && tab == .stats {
                        pointsWonHeader
                    }
                }
                .padding(.vertical, 6)
            }

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
        .task {
            guard exportSummary.isEmpty else { return }
            let record = record
            let maxHR = resolvedMaxHR
            let filename = htmlExportFilename
            let ntrp = playerNTRP
            async let summary    = Task.detached { MatchExporter.summaryExport(for: record, maxHR: maxHR, focal: .me)       }.value
            async let full       = Task.detached { MatchExporter.fullExport(for: record,    maxHR: maxHR, focal: .me)       }.value
            async let summaryOpp = Task.detached { MatchExporter.summaryExport(for: record, maxHR: maxHR, focal: .opponent) }.value
            async let fullOpp    = Task.detached { MatchExporter.fullExport(for: record,    maxHR: maxHR, focal: .opponent) }.value
            // Generate AND write the interactive HTML off the main thread so the
            // ~30–80 KB file write never stutters the UI. The AI coaching prompts
            // (same builder as the AI Coach sheet) are embedded so the shared page
            // offers the same one-tap coaching launch.
            async let htmlURL    = Task.detached { () -> URL? in
                let aiMe  = MatchExporter.aiPromptExport(for: record, maxHR: maxHR, focal: .me, playerNTRP: ntrp)
                let aiOpp = record.stats.isEmpty
                    ? nil
                    : MatchExporter.aiPromptExport(for: record, maxHR: maxHR, focal: .opponent, playerNTRP: ntrp)
                let h = MatchHTMLExporter.html(for: record, maxHR: maxHR, aiPromptMe: aiMe, aiPromptOpponent: aiOpp)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                // The shared page carries the full match record, including
                // HealthKit-derived values, so the staged file gets the same
                // data-at-rest class as the canonical archive.
                do {
                    try Data(h.utf8).write(
                        to: url,
                        options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
                    )
                    return url
                } catch { return nil }
            }.value
            let (s, f, so, fo, url) = await (summary, full, summaryOpp, fullOpp, htmlURL)
            exportSummary = s; exportFull = f; exportSummaryOpp = so; exportFullOpp = fo
            htmlExportURL = url
        }
        .task(id: "\(playerNTRP)-\(resolvedMaxHR)") {
            let record = record
            let maxHR = resolvedMaxHR
            let ntRP = playerNTRP
            async let ai    = Task.detached { MatchExporter.aiPromptExport(for: record, maxHR: maxHR, focal: .me,       playerNTRP: ntRP) }.value
            async let aiOpp = Task.detached { MatchExporter.aiPromptExport(for: record, maxHR: maxHR, focal: .opponent, playerNTRP: ntRP) }.value
            (exportAI, exportAIOpp) = await (ai, aiOpp)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if exportSummary.isEmpty || exportAI.isEmpty {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        beginAICoach()
                    } label: {
                        Label("AI Coach", systemImage: "sparkles")
                            .labelStyle(.titleAndIcon)
                    }
                    .accessibilityLabel("Open AI Coach")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if !exportSummary.isEmpty {
                    Menu {
                        if let htmlExportURL {
                            Section {
                                Button {
                                    // Recorder-framed export (HR/steps are the
                                    // recorder's), so disclose as `.me` + full.
                                    beginShare(items: [htmlExportURL], focal: .me, includesRawPoints: true)
                                } label: {
                                    Label("Interactive Web Page", systemImage: "safari")
                                }
                            } header: {
                                Text("Interactive (both perspectives)")
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
            AICoachSheet(
                mePrompt: exportAI,
                opponentPrompt: exportAIOpp,
                hasOpponentPrompt: !record.stats.isEmpty,
                filenameMe: exportFilename(for: record, mode: .ai),
                filenameOpponent: exportFilename(for: record, mode: .aiOpp)
            )
        }
        // Per-export HealthKit disclosure (Blocker 4), shared by the export share
        // sheet and the AI Coach hand-off. Naming + the recipient clause come
        // from Core's single source; confirming proceeds full-fidelity.
        .alert(
            "Share health data?",
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
            Text(HealthExportConsent.disclosure(
                fields: disclosure.fields, destination: disclosure.destination
            ).message)
        }
        .sheet(item: $activeShare) { request in
            ShareSheet(activityItems: request.items) { activeShare = nil }
        }
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
        let indices: [Int] = {
            switch setFilter {
            case .all: return Array(0..<record.setScores.count)
            case .set(let i): return [i]
            }
        }()
        ForEach(indices, id: \.self) { i in
            let label = indices.count > 1 ? "\(SetFilter.set(i).label(matchFormat: record.matchFormat)) Duration" : "Duration"
            if let secs = record.setElapsedSeconds[i] {
                statRow(label, "\(Int(secs) / 60) min")
            } else {
                let pts = record.stats.filter { $0.setIndex == i }
                if let first = pts.map(\.timestamp).min(),
                   let last  = pts.map(\.timestamp).max() {
                    statRow(label, "\(Int(last.timeIntervalSince(first)) / 60) min")
                }
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
            let mePct  = Int((Double(meWon)  / Double(total) * 100).rounded())
            let oppPct = Int((Double(oppWon) / Double(total) * 100).rounded())
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
                Text(meSummary.wueRatio)
                    .foregroundStyle(meColor)
                Text("/")
                    .foregroundStyle(.secondary)
                Text(oppSummary.wueRatio)
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
        let meFrac  = meDen  > 0 ? Double(meNum)  / Double(meDen)  : 0.0
        let oppFrac = oppDen > 0 ? Double(oppNum) / Double(oppDen) : 0.0
        let meText  = meDen  > 0 ? "\(Int((meFrac  * 100).rounded()))%" : "—"
        let oppText = oppDen > 0 ? "\(Int((oppFrac * 100).rounded()))%" : "—"
        let meLabel  = meDen  > 0 ? "\(meNum)/\(meDen)"  : nil
        let oppLabel = oppDen > 0 ? "\(oppNum)/\(oppDen)" : nil

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
