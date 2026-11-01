import SwiftUI
import DeuceMateCore

/// Compact archive entry point for the opponent directory.
struct OpponentsSection: View {
    let records: [MatchRecord]
    let forgotten: ForgottenPlayerLedger

    private var opponents: [RosterEntry] {
        OpponentDirectory.entries(from: records, forgotten: forgotten)
    }

    var body: some View {
        Section {
            NavigationLink {
                OpponentsView()
            } label: {
                HStack {
                    Label("Head-to-head records", systemImage: "person.2")
                    Spacer()
                    Text(opponents.count.formatted())
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .accessibilityIdentifier("opponents-section-link")
        } header: {
            Text("Opponents")
        } footer: {
            if opponents.isEmpty {
                Text("Add opponent names in Match Info to see head-to-head records here.")
            }
        }
    }
}
