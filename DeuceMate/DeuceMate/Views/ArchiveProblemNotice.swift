// ArchiveProblemNotice.swift — the archive screen's explanation when the
// iPhone archive could not be loaded (TECHNICAL_DEBT #18).
//
// `PhoneStatsStore.archiveProblem` is set when a canonical file exists but
// could not be read or decoded. The store then keeps the file, stops saving and
// stops backing up, so the list may be empty or incomplete. This notice is shown
// above the list and in place of "No Matches Yet", which would otherwise read as
// data loss. Copy lives in Core's `ArchiveLoadProblem`.
import SwiftUI
import DeuceMateCore

struct ArchiveProblemNotice: View {
    let problem: ArchiveLoadProblem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(problem.title, systemImage: problem.systemImage)
                .font(.headline)
                .foregroundStyle(.orange)
            Text(problem.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("archive-problem-notice")
    }
}
