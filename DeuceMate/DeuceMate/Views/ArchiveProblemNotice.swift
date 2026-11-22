// ArchiveProblemNotice.swift — the archive screen's explanation when the
// iPhone archive could not be loaded, a backup push was withheld, or a Watch
// sync write failed (TECHNICAL_DEBT #18).
//
// Copy lives in Core's `ArchiveLoadProblem` and `ArchiveRecovery`. Actions run
// in `ArchiveRecoveryModel`, whose alerts hang off `PastMatchesView` so they
// outlive a dismissed notice.
import SwiftUI
import DeuceMateCore

struct ArchiveProblemNotice: View {
    let problem: ArchiveLoadProblem
    let recovery: ArchiveRecoveryModel
    let store: PhoneStatsStore
    let syncService: PhoneMatchSyncService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Label(problem.title, systemImage: problem.systemImage)
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(problem.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("archive-problem-notice")

            actions
                .disabled(recovery.isWorking)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var actions: some View {
        switch problem {
        case .unreadable:
            Button(ArchiveRecoveryCopy.tryAgain) { recovery.tryAgain(store, syncService: syncService) }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("archive-try-again")
        case .undecodable:
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { undecodableButtons }
                VStack(alignment: .leading, spacing: 10) { undecodableButtons }
            }
            Text(ArchiveRecoveryCopy.importHint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var undecodableButtons: some View {
        Button(ArchiveRecoveryCopy.restoreFromICloud) { recovery.offerRestore(store) }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("archive-restore-icloud")
        Button(ArchiveRecoveryCopy.saveCopy) { recovery.saveCopy(store) }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("archive-save-copy")
    }
}

/// Shown when the last iCloud push kept matches in the backup that are no
/// longer on this iPhone, with nothing recording their deletion
/// (`BackupPushGuard`). Bring Them Back is the safe choice; Remove from Backup
/// asks first and keeps a copy of the backup.
struct BackupWithheldNotice: View {
    let count: Int
    let recovery: ArchiveRecoveryModel
    let store: PhoneStatsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Label(BackupWithheldCopy.title, systemImage: BackupWithheldCopy.systemImage)
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(BackupWithheldCopy.message(count: count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("backup-withheld-notice")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { buttons }
                VStack(alignment: .leading, spacing: 10) { buttons }
            }
            .disabled(recovery.isWorking)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var buttons: some View {
        Button(BackupWithheldCopy.bringBack) { recovery.bringBack(store) }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("backup-bring-back")
        Button(BackupWithheldCopy.remove, role: .destructive) { recovery.confirmRemove(count: count) }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("backup-remove")
    }
}

/// Shown when a Watch delivery arrived on a healthy archive but failed to write
/// to disk. Retrying via Sync Now attempts to commit the retained Watch copies
/// and reconcile tags/match-type revisions.
struct WatchSaveFailedNotice: View {
    let syncService: PhoneMatchSyncService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Watch Matches Couldn't Be Saved", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text("Received matches couldn't be saved to this iPhone's storage. Free up storage if needed, then try again.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("watch-save-failed-notice")

            Button("Try Again") {
                syncService.requestFullHistorySync()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("watch-save-retry")
        }
        .padding(.vertical, 4)
    }
}
