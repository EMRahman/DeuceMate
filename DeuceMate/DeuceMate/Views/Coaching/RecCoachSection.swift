// RecCoachSection.swift — HR-independent coaching insights surfaced in
// MatchDetailView for recreational players. Sits immediately above the
// PulseCoach section so both coaching panels group together just below
// Duration. The insights are set-scoped: the caller regenerates them when the
// All / Set 1 / Set 2 filter changes and passes a `scopeLabel` so the header
// reflects which slice of the match is being coached.
import SwiftUI

struct RecCoachSection: View {
    let insights: [String]
    /// When non-nil, appended to the section header (e.g. "Set 2") so the user
    /// can see the insights are scoped to the selected set.
    var scopeLabel: String? = nil
    /// Total number of categorized points in the current scope. When insights are
    /// empty and this is 1…19, a progress nudge is shown instead of hiding the
    /// section entirely. Pass nil (default) to preserve the old hide-when-empty behavior.
    var categorizedCount: Int? = nil

    private var headerText: String {
        if let scopeLabel {
            return "Coaching Insights · \(scopeLabel)"
        }
        return "Coaching Insights"
    }

    private var pointsNeeded: Int? {
        guard insights.isEmpty, let count = categorizedCount, count > 0, count < 20 else { return nil }
        return 20 - count
    }

    var body: some View {
        if !insights.isEmpty {
            Section(headerText) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(insights, id: \.self) { line in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "figure.tennis")
                                .foregroundStyle(.tint)
                                .font(.footnote)
                            Text(line)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        } else if let needed = pointsNeeded {
            Section(headerText) {
                Label(
                    "Track \(needed) more point\(needed == 1 ? "" : "s") to unlock coaching insights.",
                    systemImage: "lock"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 2)
            }
        }
    }
}
