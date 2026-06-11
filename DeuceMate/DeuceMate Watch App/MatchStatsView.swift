// MatchStatsView.swift
import SwiftUI
import DeuceMateCore

/// Renders match statistics for a given collection of `PointStat`s. Used both
/// for the live "swipe-right" stats overlay during a match and for the
/// post-match view from the history list.
struct MatchStatsView: View {
    let stats: [PointStat]
    let setScores: [SetScore]
    let title: String
    let matchType: MatchType
    let matchFormat: MatchFormat
    let matchIsComplete: Bool
    /// If non-nil, the in-progress match record this view is showing.
    let resumableRecord: MatchRecord?
    let setElapsedSeconds: [Int: TimeInterval]
    let currentSetSessionStart: Date?
    let totalSteps: Int?
    let totalCaloriesKcal: Double?

    @EnvironmentObject private var viewModel: ScoreViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var setFilter: SetFilter = .all
    @State private var showResumeConflictAlert = false

    init(stats: [PointStat],
         setScores: [SetScore],
         title: String,
         matchType: MatchType = .singles,
         matchFormat: MatchFormat = .standard,
         matchIsComplete: Bool = false,
         resumableRecord: MatchRecord? = nil,
         setElapsedSeconds: [Int: TimeInterval] = [:],
         currentSetSessionStart: Date? = nil,
         totalSteps: Int? = nil,
         totalCaloriesKcal: Double? = nil) {
        self.stats = stats
        self.setScores = setScores
        self.title = title
        self.matchType = matchType
        self.matchFormat = matchFormat
        self.matchIsComplete = matchIsComplete
        self.resumableRecord = resumableRecord
        self.setElapsedSeconds = setElapsedSeconds
        self.currentSetSessionStart = currentSetSessionStart
        self.totalSteps = totalSteps
        self.totalCaloriesKcal = totalCaloriesKcal
    }

    private enum SetFilter: Hashable {
        case all
        case set(Int)

        func label(matchFormat: MatchFormat) -> String {
            switch self {
            case .all: return "All"
            case .set(let i):
                return matchFormat.config.isDecidingSuperTiebreak(setIndex: i) ? "TB" : "S\(i + 1)"
            }
        }
    }

    private var meColor:  Color { viewModel.selectedTheme.colors.me }
    private var oppColor: Color { viewModel.selectedTheme.colors.opponent }

    private var focalLabel: String { matchType == .doubles ? "Our" : "Me" }
    private var opponentLabel: String { "Opp" }

    private var availableSetFilters: [SetFilter] {
        var result: [SetFilter] = [.all]
        for index in 0..<setScores.count { result.append(.set(index)) }
        return result
    }

    private var filteredStats: [PointStat] {
        switch setFilter {
        case .all: return stats
        case .set(let i): return stats.filter { $0.setIndex == i }
        }
    }

    /// Per-set attribution of the match's Steps and Calories totals.
    private var activitySplit: SetActivitySplit {
        SetActivitySplit(setCount: setScores.count,
                         stats: stats,
                         setElapsedSeconds: setElapsedSeconds,
                         totalSteps: totalSteps,
                         totalCaloriesKcal: totalCaloriesKcal)
    }

    /// Steps for the current filter: match total for "All", set-specific otherwise.
    private var displayedSteps: Int? {
        switch setFilter {
        case .all: return totalSteps
        case .set(let i): return activitySplit.steps[i]
        }
    }

    /// Calories for the current filter: match total for "All", set-specific otherwise.
    private var displayedCalories: Double? {
        switch setFilter {
        case .all: return totalCaloriesKcal
        case .set(let i): return activitySplit.calories[i]
        }
    }

    private var hasConflictingLiveMatch: Bool {
        guard let record = resumableRecord else { return false }
        return viewModel.matchStartTime != nil
            && viewModel.hasInProgressMatchData
            && viewModel.currentMatchID != record.id
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(matchFormat.displayLabel
                     + (matchType == .doubles ? " · Doubles" : " · Singles"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)

                if let score = scoreDisplayString {
                    Text(styledScore(score, superSize: 8))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if shouldShowStatControls && availableSetFilters.count > 1 {
                    HStack(spacing: 4) {
                        ForEach(availableSetFilters, id: \.self) { f in
                            Button { setFilter = f } label: {
                                Text(f.label(matchFormat: matchFormat))
                                    .font(.system(size: 11, weight: .semibold))
                                    .padding(.vertical, 3)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(setFilter == f ? .blue : .gray)
                        }
                    }
                    .padding(.vertical, 2)
                }

                setDurationSection

                if !shouldShowStatControls {
                    Text("Point outcome tracking was off for this match.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                } else if filteredStats.isEmpty {
                    Text("No tracked points yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 12)
                } else {
                    tvStatRows
                }

                if let record = resumableRecord, record.isInProgress {
                    Button {
                        if hasConflictingLiveMatch {
                            showResumeConflictAlert = true
                        } else {
                            viewModel.resumeMatch(record)
                            dismiss()
                        }
                    } label: {
                        Label("Resume this match", systemImage: "play.fill")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .alert("Replace current match?", isPresented: $showResumeConflictAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Replace", role: .destructive) {
                if let record = resumableRecord {
                    viewModel.resumeMatch(record)
                    dismiss()
                }
            }
        } message: {
            Text("Your current match will be saved as In Progress so you can resume it later.")
        }
    }

    private var setsForDuration: [Int] {
        switch setFilter {
        case .all: return Array(0..<setScores.count)
        case .set(let i): return [i]
        }
    }

    private var shouldShowStatControls: Bool {
        if isLiveMatchSession { return viewModel.statsTrackingEnabled }
        return !stats.isEmpty
    }

    private var isLiveMatchSession: Bool { resumableRecord == nil && !matchIsComplete }

    private var scoreDisplayString: String? {
        guard !isLiveMatchSession, !setScores.isEmpty else { return nil }

        // In-progress: all-but-last are completed sets; last is the current set.
        if let record = resumableRecord {
            let cfg = matchFormat.config
            var parts: [String] = []
            for (index, set) in setScores.dropLast().enumerated() {
                if cfg.isDecidingSuperTiebreak(setIndex: index) && set.isTieBreak {
                    parts.append("\(set.tieBreakPointsMe)-\(set.tieBreakPointsOpponent)")
                } else if set.isTieBreak && set.gamesMe + set.gamesOpponent > 0 {
                    parts.append("\(set.gamesMe)-\(set.gamesOpponent)(\(set.tieBreakPointsMe)-\(set.tieBreakPointsOpponent))")
                } else if set.isTieBreak {
                    parts.append("\(set.tieBreakPointsMe)-\(set.tieBreakPointsOpponent)")
                } else {
                    parts.append("\(set.gamesMe)-\(set.gamesOpponent)")
                }
            }
            if let current = setScores.last {
                if current.isTieBreak {
                    parts.append("TB \(current.tieBreakPointsMe)-\(current.tieBreakPointsOpponent)")
                } else {
                    parts.append("\(current.gamesMe)-\(current.gamesOpponent)")
                    if let gs = MatchRecord.gameScoreString(mePoints: record.currentPointsMe, oppPoints: record.currentPointsOpponent) {
                        parts.append("(\(gs))")
                    }
                }
            }
            return parts.isEmpty ? nil : parts.joined(separator: "  ")
        }

        // Completed match.
        let cfg = matchFormat.config
        let parts = setScores.enumerated().map { (index, set) -> String in
            if cfg.isDecidingSuperTiebreak(setIndex: index) && set.isTieBreak {
                return "\(set.tieBreakPointsMe)-\(set.tieBreakPointsOpponent)"
            }
            if set.isTieBreak && set.gamesMe + set.gamesOpponent > 0 {
                return "\(set.gamesMe)-\(set.gamesOpponent)(\(set.tieBreakPointsMe)-\(set.tieBreakPointsOpponent))"
            } else if set.isTieBreak {
                return "\(set.tieBreakPointsMe)-\(set.tieBreakPointsOpponent)"
            }
            return "\(set.gamesMe)-\(set.gamesOpponent)"
        }
        return parts.joined(separator: "  ")
    }

    @ViewBuilder
    private var setDurationSection: some View {
        let toShow = setsForDuration
        let hasData = stats.contains { toShow.contains($0.setIndex) }
                   || toShow.contains { setElapsedSeconds[$0] != nil }
        let hasActivity = (totalSteps ?? 0) > 0 || (totalCaloriesKcal ?? 0) > 0
        if (!toShow.isEmpty && hasData) || hasActivity {
            VStack(spacing: 2) {
                ForEach(toShow, id: \.self) { i in
                    setDurationRow(for: i, label: toShow.count > 1 ? "\(SetFilter.set(i).label(matchFormat: matchFormat)) Duration" : "Duration")
                }
                if let steps = displayedSteps, steps > 0 {
                    statRow("Steps", steps.formatted())
                }
                if let kcal = displayedCalories, kcal > 0 {
                    statRow("Calories", MatchRecord.formattedCalories(kcal))
                }
            }
            Divider().padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func setDurationRow(for setIndex: Int, label: String) -> some View {
        let isFinished = setIndex < setScores.count - 1 || matchIsComplete || resumableRecord != nil
        if isFinished {
            if let storedSecs = setElapsedSeconds[setIndex] {
                statRow(label, "\(Int(storedSecs) / 60) m")
            } else {
                let setPoints = stats.filter { $0.setIndex == setIndex }
                if let firstTS = setPoints.map(\.timestamp).min() {
                    let lastTS = setPoints.map(\.timestamp).max() ?? firstTS
                    statRow(label, "\(Int(lastTS.timeIntervalSince(firstTS)) / 60) m")
                }
            }
        } else if let sessionStart = currentSetSessionStart {
            let prior = setElapsedSeconds[setIndex] ?? 0
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let total = prior + max(0, ctx.date.timeIntervalSince(sessionStart))
                let mins = Int(total) / 60
                let secs = Int(total) % 60
                statRow(label, "\(mins) m \(secs) s")
            }
        }
    }

    @ViewBuilder
    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 12, weight: .semibold)).monospacedDigit()
        }
    }

    // MARK: - TV-style comparison primitives

    @ViewBuilder
    private func splitBar(meFrac: Double, oppFrac: Double) -> some View {
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
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 1)
                Rectangle()
                    .fill(oppColor.opacity(0.15))
                    .frame(width: halfW)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(oppColor)
                            .frame(width: halfW * oppFrac)
                    }
            }
        }
        .frame(height: 6)
        .clipShape(RoundedRectangle(cornerRadius: 2))
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

        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            HStack(spacing: 2) {
                Text(meText)
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(meColor)
                    .frame(width: 26, alignment: .trailing)
                splitBar(meFrac: meFrac, oppFrac: oppFrac)
                Text(oppText)
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(oppColor)
                    .frame(width: 26, alignment: .leading)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func countComparisonRow(_ label: String, meCount: Int, oppCount: Int) -> some View {
        let maxVal  = max(meCount, oppCount, 1)
        let meFrac  = Double(meCount)  / Double(maxVal)
        let oppFrac = Double(oppCount) / Double(maxVal)

        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            HStack(spacing: 2) {
                Text("\(meCount)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(meColor)
                    .frame(width: 26, alignment: .trailing)
                splitBar(meFrac: meFrac, oppFrac: oppFrac)
                Text("\(oppCount)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(oppColor)
                    .frame(width: 26, alignment: .leading)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func comparisonSectionHeader(_ title: String) -> some View {
        HStack {
            Text(focalLabel)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(meColor)
            Spacer()
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(opponentLabel)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(oppColor)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func tvPointsWonHeader(me meSummary: MatchStatsSummary) -> some View {
        let total = meSummary.totalPoints
        let meWon = meSummary.pointsWon
        let oppWon = total - meWon
        if total > 0 {
            VStack(spacing: 4) {
                HStack {
                    Text(focalLabel)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(meColor)
                    Spacer()
                    Text("Points Won")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Opp")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(oppColor)
                }
                GeometryReader { geo in
                    let spacing: CGFloat = 2
                    let available = max(0, geo.size.width - spacing)
                    let meFrac = Double(meWon) / Double(total)
                    HStack(spacing: spacing) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(meColor)
                            .frame(width: available * meFrac)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(oppColor)
                            .frame(width: available * (1 - meFrac))
                    }
                }
                .frame(height: 8)
                HStack {
                    Text("\(meWon) pts")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(meColor)
                    Spacer()
                    Text("\(total) total")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(oppWon) pts")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(oppColor)
                }
            }
            .padding(.vertical, 3)
            Divider().padding(.vertical, 2)
        }
    }

    // MARK: - TV stat rows (side-by-side comparison)

    @ViewBuilder
    private var tvStatRows: some View {
        let me  = MatchStatsSummary(stats: filteredStats, focal: .me,       setElapsedSeconds: setElapsedSeconds)
        let opp = MatchStatsSummary(stats: filteredStats, focal: .opponent, setElapsedSeconds: setElapsedSeconds)
        let hasAnyOutcomeData = me.totalPoints > me.uncategorizedCount

        VStack(spacing: 2) {
            tvPointsWonHeader(me: me)

            if hasAnyOutcomeData {
                comparisonSectionHeader("Outcome Breakdown")
                HStack(spacing: 2) {
                    Text(me.wueRatio)
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(meColor)
                        .frame(minWidth: 26, alignment: .trailing)
                    VStack(spacing: 0) {
                        Text("Win:Unforced Err")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                        Text("aim for > 1.0")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    Text(opp.wueRatio)
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(oppColor)
                        .frame(minWidth: 26, alignment: .leading)
                }
                .padding(.vertical, 3)
                countComparisonRow("Winners",
                    meCount: me.myWinners,       oppCount: opp.myWinners)
                countComparisonRow("Unforced Errors",
                    meCount: me.myUnforcedErrors, oppCount: opp.myUnforcedErrors)
                countComparisonRow("Forced Errors",
                    meCount: me.myForcedErrors,   oppCount: opp.myForcedErrors)
                countComparisonRow("Double Faults",
                    meCount: me.myDoubleFaults,   oppCount: opp.myDoubleFaults)
                comparisonRow("Aggression Index",
                    subtitle: "W ÷ (W + UE)",
                    meNum: me.myWinners,
                           meDen: me.myWinners + me.myUnforcedErrors,
                    oppNum: opp.myWinners,
                           oppDen: opp.myWinners + opp.myUnforcedErrors)
                comparisonRow("Own Errors %",
                    meNum: me.myDoubleFaults + me.myUnforcedErrors,
                           meDen: me.lostPoints,
                    oppNum: opp.myDoubleFaults + opp.myUnforcedErrors,
                           oppDen: opp.lostPoints)
                if me.uncategorizedCount > 0 {
                    Text("(\(me.uncategorizedCount) uncategorized)")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            } else {
                Text("Outcome Breakdown")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
                Text("Outcome tracking not collected for this match.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
            }

            Divider().padding(.vertical, 2)

            comparisonSectionHeader("Serve")
            comparisonRow("1st Serve In",
                meNum: me.firstServeIn,    meDen: me.firstServeTotal,
                oppNum: opp.firstServeIn,  oppDen: opp.firstServeTotal)
            comparisonRow("2nd Serve In",
                meNum: me.secondServeIn,    meDen: me.secondServeTotal,
                oppNum: opp.secondServeIn,  oppDen: opp.secondServeTotal)
            comparisonRow("1st Serve Win",
                meNum: me.firstServeWins,   meDen: me.firstServeIn,
                oppNum: opp.firstServeWins, oppDen: opp.firstServeIn)
            comparisonRow("2nd Serve Win",
                meNum: me.secondServeWins,   meDen: me.secondServeIn,
                oppNum: opp.secondServeWins, oppDen: opp.secondServeIn)
            comparisonRow("DF Rate (2nd)",
                meNum: me.doubleFaults,    meDen: me.secondServeTotal,
                oppNum: opp.doubleFaults,  oppDen: opp.secondServeTotal)

            Divider().padding(.vertical, 2)

            comparisonSectionHeader("Return")
            comparisonRow("vs 1st Serve",
                meNum: me.returnWinsOnFirst,    meDen: me.returnOppsOnFirst,
                oppNum: opp.returnWinsOnFirst,  oppDen: opp.returnOppsOnFirst)
            comparisonRow("vs 2nd Serve",
                meNum: me.returnWinsOnSecond,   meDen: me.returnOppsOnSecond,
                oppNum: opp.returnWinsOnSecond, oppDen: opp.returnOppsOnSecond)

            Divider().padding(.vertical, 2)

            comparisonSectionHeader("Break Points")
            comparisonRow("BPs Won (Returner)",
                meNum: me.breakPointWins,   meDen: me.breakPointOpps,
                oppNum: opp.breakPointWins, oppDen: opp.breakPointOpps)
            comparisonRow("BPs Saved (Server)",
                meNum: me.breakPointsFaced - me.breakPointsLost,   meDen: me.breakPointsFaced,
                oppNum: opp.breakPointsFaced - opp.breakPointsLost, oppDen: opp.breakPointsFaced)

            if me.bigPointTotal > 0 && me.normalPointTotal > 0 {
                Divider().padding(.vertical, 2)
                comparisonSectionHeader("Pressure vs Normal")
                comparisonRow("Big Points",
                    meNum: me.bigPointWins,    meDen: me.bigPointTotal,
                    oppNum: opp.bigPointWins,  oppDen: opp.bigPointTotal)
                comparisonRow("Normal Points",
                    meNum: me.normalPointWins,   meDen: me.normalPointTotal,
                    oppNum: opp.normalPointWins, oppDen: opp.normalPointTotal)
            }

            if !me.rallyDepth.isEmpty {
                Divider().padding(.vertical, 2)
                comparisonSectionHeader("Rally Depth Won")
                ForEach(me.rallyDepth, id: \.shot) { meRd in
                    let oppRd = opp.rallyDepth.first { $0.shot == meRd.shot }
                    comparisonRow("@ \(meRd.shot.displayLabel)",
                        meNum: meRd.wins,         meDen: meRd.total,
                        oppNum: oppRd?.wins ?? 0, oppDen: oppRd?.total ?? 0)
                }
            }

            if !me.scoreStates.isEmpty {
                Divider().padding(.vertical, 2)
                comparisonSectionHeader("Score States")
                ForEach(me.scoreStates, id: \.label) { meSs in
                    let oppSs = opp.scoreStates.first { $0.label == meSs.label }
                    comparisonRow(meSs.label,
                        meNum: meSs.wins,         meDen: meSs.total,
                        oppNum: oppSs?.wins ?? 0, oppDen: oppSs?.total ?? 0)
                }
            }

        }
    }
}
