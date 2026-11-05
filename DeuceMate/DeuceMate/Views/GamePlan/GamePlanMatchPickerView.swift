// GamePlanMatchPickerView.swift — choose individual matches for a game plan.
// Any add or remove switches the selection to Custom selection; the list is
// the filtered eligible pool, newest first, so nothing outside the filters
// can be picked.
import SwiftUI
import DeuceMateCore

struct GamePlanMatchPickerView: View {
    let pool: [MatchRecord]
    let selectedIDs: Set<UUID>
    let notesMatchIDs: Set<UUID>
    let toggle: (UUID) -> Void

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        List {
            Section {
                ForEach(pool) { record in
                    Button { toggle(record.id) } label: { row(record) }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedIDs.contains(record.id) ? .isSelected : [])
                        .accessibilityIdentifier("game-plan-match-\(record.id.uuidString)")
                }
            } footer: {
                Text("\(selectedIDs.count) of \(pool.count) selected. Changing this list makes it a custom selection.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Choose Matches")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ record: MatchRecord) -> some View {
        let selected = selectedIDs.contains(record.id)
        let status = GamePlanMatchStatus(record: record)
        let tracked = record.stats.filter { $0.outcome != .uncategorized }.count
        return HStack(spacing: 12) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(Self.formatter.string(from: record.startTime))
                    .font(.subheadline.weight(.semibold))
                Text("\(GamePlanCompetition(record: record).label) · \(GamePlanText.formatLabel(record.matchFormat)) · \(statusLabel(status))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(record.stats.isEmpty
                     ? "Score only"
                     : "\(record.stats.count) points · outcomes on \(GamePlanText.percent(tracked, of: record.stats.count))\(notesMatchIDs.contains(record.id) ? " · note" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    private func statusLabel(_ status: GamePlanMatchStatus) -> String {
        switch status {
        case .inProgress: return "Unfinished"
        case .completed(let result, let ending):
            let base: String
            switch result {
            case .win: base = "Won"
            case .loss: base = "Lost"
            case .draw: base = "Draw"
            }
            return ending == .stoppedEarly ? base + " (ended early)" : base
        }
    }
}
