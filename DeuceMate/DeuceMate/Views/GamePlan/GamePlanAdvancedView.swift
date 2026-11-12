// GamePlanAdvancedView.swift — detail level and delivery, pushed from
// Prepare Game Plan's Advanced row. The defaults (Full detail, one file) suit
// almost every pack.
//
// Deliberately shows no built-pack figures: the build belongs to the main
// screen's view-scoped task, which SwiftUI cancels while a pushed screen
// covers it, so a size shown here could not follow these pickers. The
// estimate, file size and per-part sizes live on the main screen, which
// rebuilds when it reappears.
import SwiftUI
import DeuceMateCore

struct GamePlanAdvancedView: View {
    @Binding var detailMode: GamePlanDetailMode
    @Binding var delivery: GamePlanDelivery

    var body: some View {
        List {
            Section {
                Picker("Detail", selection: $detailMode) {
                    ForEach(GamePlanDetailMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("game-plan-detail")
            } header: {
                Text("Detail")
            } footer: {
                Text(detailMode == .full
                     ? "Full detail includes every saved point of every selected match. Nothing is trimmed to fit."
                     : "Summary only keeps each match’s figures and included notes but leaves out the point rows, and says so in the pack.")
            }

            Section {
                Picker("Delivery", selection: $delivery) {
                    Text("One file").tag(GamePlanDelivery.singleFile)
                    ForEach(GamePlanDelivery.partTargets, id: \.self) { target in
                        Text("Parts of ~\(GamePlanTokenEstimate(tokens: target).label)").tag(GamePlanDelivery.parts(targetTokens: target))
                    }
                }
                .accessibilityIdentifier("game-plan-delivery")
            } header: {
                Text("Delivery")
            } footer: {
                Text("The size estimate on the previous screen is an on-device estimate of the input the AI app will read, usually within about \(GamePlanTokenEstimator.documentedErrorPercent)% for tennis tables and English text; notes in other languages vary more. Each AI service counts differently and may add its own overhead. The answer isn’t included. Large packs work best as a shared file; split only if your AI app rejects one.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// "Full detail · One file", for the main screen.
    static func summary(detailMode: GamePlanDetailMode, delivery: GamePlanDelivery) -> String {
        "\(detailMode.label) · \(delivery == .singleFile ? "One file" : "Parts")"
    }
}
