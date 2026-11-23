// ArchiveExportReminderCard.swift — non-blocking inline Matches-screen section
// nudging the user to export a full-fidelity archive file
// (docs/features/ARCHIVE_EXPORT_REMINDER_PLAN.md §2.1–§2.2).
import SwiftUI
import DeuceMateCore

struct ArchiveExportReminderCard: View {
    let count: Int
    let missing: Set<ArchiveExportReminderPolicy.MissingCategory>
    let onExport: () -> Void
    let onLater: () -> Void
    let onDisable: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label(ArchiveExportReminderCopy.title, systemImage: "square.and.arrow.up.on.square")
                    .font(.headline)

                Text(ArchiveExportReminderCopy.body(count: count, missing: missing))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button(ArchiveExportReminderCopy.exportButtonTitle, action: onExport)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("export-reminder-export")

                    Button(ArchiveExportReminderCopy.laterButtonTitle, action: onLater)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("export-reminder-later")
                }
                .padding(.top, 2)

                Button(ArchiveExportReminderCopy.disableButtonTitle, action: onDisable)
                    .buttonStyle(.borderless)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("export-reminder-never")
                    .accessibilityHint(ArchiveExportReminderCopy.disableAccessibilityHint)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("export-reminder-card")
        }
    }
}
