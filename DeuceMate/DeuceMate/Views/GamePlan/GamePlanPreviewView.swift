// GamePlanPreviewView.swift — the evidence overview and the complete pack
// text exactly as it will be copied or shared. The full text can run to
// megabytes, so it is shown in a read-only UITextView rather than a SwiftUI
// Text, which lays the whole string out at once.
import SwiftUI
import UIKit
import DeuceMateCore

struct GamePlanPreviewView: View {
    let output: GamePlanBuildOutput

    @State private var partIndex = 0

    private var evidence: GamePlanEvidence { output.evidence }
    private var pack: GamePlanPack { output.pack }

    var body: some View {
        List {
            Section("Overview") {
                LabeledContent("Upcoming", value: upcomingLine)
                LabeledContent("Matches", value: "\(evidence.matches.count) of \(evidence.availableCount) available")
                LabeledContent("Dates", value: GamePlanText.dateRange(evidence.firstStart, evidence.lastStart, timeZone: .current))
                LabeledContent("Head to head", value: MatchComparisonFormat.headToHeadSummary(evidence.headToHead))
                ForEach(evidence.competitionRows, id: \.competition) { row in
                    LabeledContent(row.competition.label + (row.matchesUpcoming ? " (upcoming)" : ""),
                                   value: "\(row.completedCount + row.inProgressCount) · \(GamePlanText.tally(row.record))")
                }
                if evidence.upcomingCompetitionHasNoHistory, let upcoming = evidence.upcomingCompetition {
                    Label("No selected \(upcoming.displayLabel) matches — the plan will be provisional.",
                          systemImage: "exclamationmark.circle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                LabeledContent("Detail", value: evidence.detailMode.label)
                LabeledContent("Names", value: evidence.includesNames ? "Included" : "Not included")
                LabeledContent("Notes", value: evidence.includesNotes ? "\(evidence.notesIncludedCount) of \(evidence.notesAvailableCount)" : "Not included")
                LabeledContent("Size", value: "\(pack.totalEstimate.label) · \(ByteCountFormatter.string(fromByteCount: Int64(pack.totalBytes), countStyle: .file))")
                    .accessibilityLabel("\(pack.totalEstimate.inputLabel), \(ByteCountFormatter.string(fromByteCount: Int64(pack.totalBytes), countStyle: .file))")
            }

            Section {
                if pack.isSplit {
                    Picker("Part", selection: $partIndex) {
                        ForEach(pack.parts.indices, id: \.self) { index in
                            Text("Part \(index + 1)").tag(index)
                        }
                    }
                    .pickerStyle(.menu)
                    Text(pack.parts[safe: partIndex]?.contents ?? "")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                NavigationLink {
                    GamePlanTextView(text: pack.parts[safe: partIndex]?.text ?? "")
                        .navigationTitle(pack.isSplit ? "Part \(partIndex + 1) of \(pack.parts.count)" : "Evidence Pack")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Label(pack.isSplit ? "View Part \(partIndex + 1) Text" : "View Complete Text", systemImage: "doc.plaintext")
                }
                .accessibilityIdentifier("game-plan-view-text")
            } header: {
                Text("Exact Contents")
            } footer: {
                Text("This is exactly what is copied or shared, including the coaching request\(pack.isSplit ? " in the final part" : " at the end").")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Preview")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var upcomingLine: String {
        let competition = evidence.upcomingCompetition?.displayLabel ?? "Competition not set"
        let format = evidence.upcomingFormat.map(GamePlanText.formatLabel) ?? "format not set"
        return "\(competition) · \(format)"
    }
}

/// Read-only, selectable, scrollable text that copes with very long strings.
struct GamePlanTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.font = UIFontMetrics(forTextStyle: .footnote)
            .scaledFont(for: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular))
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        view.accessibilityIdentifier = "game-plan-text"
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text { view.text = text }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
