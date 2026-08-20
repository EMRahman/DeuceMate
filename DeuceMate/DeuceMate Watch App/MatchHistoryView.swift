// MatchHistoryView.swift
import SwiftUI
import DeuceMateCore

/// Renders a score string with the tiebreak parenthetical (e.g. "(7-2)") as superscript.
/// Identifies the tiebreak paren by checking that the preceding character is a digit,
/// distinguishing it from a game-score paren like "(30-0)" that follows whitespace.
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
            result[tbRange].swiftUI.font = .system(size: superSize, weight: .semibold).monospacedDigit()
            result[tbRange].swiftUI.baselineOffset = superSize * 0.5
            searchStart = closeParen.upperBound
        } else {
            searchStart = openParen.upperBound
        }
    }
    return result
}

/// Lists the last `StatsStore.historyCap` matches, completed and in-progress.
/// Tapping a row drills into a `MatchStatsView`. In-progress rows include a
/// "Resume this match" button inside that drill-down.
struct MatchHistoryView: View {
    @EnvironmentObject private var viewModel: ScoreViewModel
    @State private var records: [MatchRecord] = []
    @State private var selected: MatchRecord?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MMM-dd HH:mm"
        return f
    }()

    var body: some View {
        Group {
            if records.isEmpty {
                VStack(spacing: 8) {
                    Text("No past matches yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Finish a match to see it here. Enable Point Outcome Tracking to include full match stats.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                List {
                    ForEach(records) { record in
                        Button { selected = record } label: {
                            rowView(for: record)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                StatsStore.shared.removeMatch(id: record.id)
                                records = StatsStore.shared.loadHistory()
                                WatchMatchSyncService.shared.sendManifest()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    // Always shown at the foot of the list so the count and the
                    // watch's rolling-cap behaviour are visible, not just near the cap.
                    Label(
                        "\(records.count) of \(StatsStore.historyCap) on Apple Watch — oldest is replaced as you add more (synced matches stay on iPhone).",
                        systemImage: "externaldrive.badge.icloud"
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .onAppear {
            records = StatsStore.shared.loadHistory()
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchMatchHistoryDidChange)) { _ in
            records = StatsStore.shared.loadHistory()
        }
        .sheet(item: $selected, onDismiss: {
            records = StatsStore.shared.loadHistory()
        }) { record in
            MatchStatsView(stats: record.stats,
                           setScores: record.setScores,
                           title: title(for: record),
                           matchType: record.matchType,
                           matchFormat: record.matchFormat,
                           matchIsComplete: !record.isInProgress,
                           resumableRecord: record.isInProgress ? record : nil,
                           setElapsedSeconds: record.setElapsedSeconds,
                           currentSetSessionStart: nil,
                           totalSteps: record.totalSteps,
                           totalCaloriesKcal: record.totalCaloriesKcal)
                .environmentObject(viewModel)
        }
    }

    @ViewBuilder
    private func rowView(for record: MatchRecord) -> some View {
        let isInProgress = record.isInProgress
        let formatLine = record.matchFormat.displayLabel
            + (record.matchType == .doubles ? " · Doubles" : " · Singles")
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(MatchHistoryView.dateFormatter.string(from: record.startTime))
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if isInProgress {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9))
                        .foregroundStyle(.yellow)
                }
            }
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(styledScore(resultLabel(for: record), superSize: 7))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(formatLine)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if isInProgress {
                    Text("\(record.stats.count) pts")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else if hasPointOutcomeStats(record) {
                    Label("Match Stats", systemImage: "chart.bar")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    Label("Score Only", systemImage: "list.number")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func resultLabel(for record: MatchRecord) -> String {
        if record.isInProgress { return inProgressScoreLabel(for: record) }
        if record.matchFormat == .perpetualPoints, let tb = record.setScores.first {
            return "Final \(CompactScoreLine.setScore(tb, setIndex: 0, matchFormat: record.matchFormat))"
        }
        if record.matchFormat == .superTiebreak, let tb = record.setScores.first {
            let result = record.iWon == true ? "Won" : "Lost"
            return "\(result) \(CompactScoreLine.setScore(tb, setIndex: 0, matchFormat: record.matchFormat))"
        }
        if record.matchFormat == .perpetualSuperTiebreak {
            let scores = record.setScores.enumerated().map {
                CompactScoreLine.setScore($1, setIndex: $0, matchFormat: record.matchFormat)
            }
            let scoreStr = scores.count > 4
                ? scores.prefix(3).joined(separator: ", ") + ", … (\(scores.count))"
                : scores.joined(separator: ", ")
            if record.iWon == nil { return "Draw \(scoreStr)" }
            let result = record.iWon == true ? "Won" : "Lost"
            return "\(result) \(scoreStr)"
        }
        let result = record.iWon == true ? "Won" : "Lost"
        let scores = CompactScoreLine.completed(
            setScores: record.setScores,
            matchFormat: record.matchFormat,
            separator: ", "
        )
        return "\(result) \(scores)"
    }

    private func inProgressScoreLabel(for record: MatchRecord) -> String {
        CompactScoreLine.inProgress(record) ?? "In Progress"
    }


    private func title(for record: MatchRecord) -> String {
        if record.isInProgress {
            return MatchHistoryView.dateFormatter.string(from: record.startTime)
        }
        return hasPointOutcomeStats(record) ? "Match Stats" : "Score Only Match"
    }

    private func hasPointOutcomeStats(_ record: MatchRecord) -> Bool {
        !record.stats.isEmpty
    }
}
