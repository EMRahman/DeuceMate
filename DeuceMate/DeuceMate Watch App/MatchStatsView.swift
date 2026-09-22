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
    @State private var showEndAtCurrentScoreConfirmation = false

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

    private var availableSetFilters: [SetFilter] {
        SetFilter.filters(setCount: setScores.count)
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

                // Surfaced right under the score so an in-progress match can be
                // resumed without scrolling past the stats below.
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
                    .padding(.vertical, 4)

                    Button(role: .destructive) {
                        showEndAtCurrentScoreConfirmation = true
                    } label: {
                        Label("End at Current Score", systemImage: "stop.circle.fill")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .padding(.bottom, 4)
                }

                if shouldShowStatControls && availableSetFilters.count > 1 {
                    HStack(spacing: 4) {
                        ForEach(availableSetFilters, id: \.self) { f in
                            Button { setFilter = f } label: {
                                Text(f.label(matchFormat: matchFormat, style: .short))
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
                    MatchStatsContent(stats: filteredStats, matchType: matchType,
                                      setElapsedSeconds: setElapsedSeconds)
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
        .confirmationDialog(
            "End at current score?",
            isPresented: $showEndAtCurrentScoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("End at Current Score", role: .destructive) {
                if let record = resumableRecord,
                   viewModel.endStoredMatchAtCurrentScore(record) {
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This marks the match completed and it can no longer be resumed. A tied score is saved as a draw.")
        }
    }

    private var setsForDuration: [Int] {
        setFilter.setIndices(setCount: setScores.count)
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
            return CompactScoreLine.inProgress(record)
        }

        return CompactScoreLine.completed(setScores: setScores, matchFormat: matchFormat)
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
                    setDurationRow(for: i, label: toShow.count > 1 ? "\(SetFilter.set(i).label(matchFormat: matchFormat, style: .short)) Duration" : "Duration")
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
            if let secs = MatchDurations.setElapsedSeconds(
                setIndex: setIndex, stats: stats, stored: setElapsedSeconds
            ) {
                statRow(label, MatchDurations.minutesString(secs, unit: "m"))
            }
        } else if let sessionStart = currentSetSessionStart {
            let prior = setElapsedSeconds[setIndex] ?? 0
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let total = prior + max(0, ctx.date.timeIntervalSince(sessionStart))
                statRow(label, MatchDurations.minutesSecondsString(total))
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

}
