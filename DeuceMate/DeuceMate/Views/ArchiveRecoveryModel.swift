// ArchiveRecoveryModel.swift — runs the archive screen's recovery actions and
// owns what they present (TECHNICAL_DEBT #18).
//
// Every alert and the share sheet hang off `PastMatchesView` through
// `archiveRecoveryPresentations`, not off the notices: a successful recovery
// removes its notice from the screen, and a presentation attached to it would
// vanish with it. Copy lives in Core's `ArchiveRecoveryCopy`,
// `ICloudArchiveRestore` and `BackupWithheldCopy`.
import SwiftUI
import UIKit
import DeuceMateCore

@MainActor
@Observable
final class ArchiveRecoveryModel {
    struct Outcome: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    struct SharedFiles: Identifiable {
        let id = UUID()
        let urls: [URL]
    }

    /// True while an action runs; the notices disable their buttons.
    private(set) var isWorking = false
    /// What Restore from iCloud found; drives its confirmation (or explanation) alert.
    var restoreOffer: ICloudArchiveRestore?
    /// The withheld matches Remove from Backup would let go, captured when its
    /// confirmation opens so the removal acts on exactly the set the user saw.
    var removeIDs: Set<UUID>?
    var removeCount: Int? { removeIDs?.count }
    var outcome: Outcome?
    var sharedFiles: SharedFiles?

    // MARK: Archive couldn't be loaded

    func tryAgain(_ store: PhoneStatsStore, syncService: PhoneMatchSyncService) {
        run {
            if await store.retryArchiveLoad() != nil {
                self.outcome = Outcome(
                    title: ArchiveRecoveryCopy.stillUnavailableTitle,
                    message: ArchiveRecoveryCopy.stillUnavailableMessage
                )
            } else {
                syncService.requestFullHistorySync()
            }
        }
    }

    func offerRestore(_ store: PhoneStatsStore) {
        run { self.restoreOffer = await store.iCloudRestoreOffer() }
    }

    func restore(_ store: PhoneStatsStore, syncService: PhoneMatchSyncService) {
        run {
            do {
                let count = try await store.restoreArchiveFromICloud()
                syncService.requestFullHistorySync()
                self.outcome = Outcome(
                    title: ArchiveRecoveryCopy.restoredTitle,
                    message: ArchiveRecoveryCopy.restoredMessage(count: count)
                )
            } catch PhoneStatsStore.RecoveryError.restoredButBackupNotResumed {
                syncService.requestFullHistorySync()
                self.outcome = Outcome(
                    title: ArchiveRecoveryCopy.restoredTitle,
                    message: ArchiveRecoveryCopy.restoredBackupNotResumedMessage
                )
            } catch {
                self.outcome = Outcome(title: ArchiveRecoveryCopy.failedTitle, message: ArchiveRecoveryCopy.failedMessage)
            }
        }
    }

    func saveCopy(_ store: PhoneStatsStore) {
        do {
            sharedFiles = SharedFiles(urls: try store.copyPreservedArchiveForSharing())
        } catch {
            outcome = Outcome(
                title: ArchiveRecoveryCopy.saveCopyFailedTitle,
                message: ArchiveRecoveryCopy.saveCopyFailedMessage
            )
        }
    }

    // MARK: Backup push withheld

    func bringBack(_ store: PhoneStatsStore) {
        run {
            do {
                let result = try await store.bringBackWithheldMatches()
                if result.restored == 0 && result.stillMissing == 0 {
                    self.outcome = result.backupUpdated
                        ? Outcome(title: BackupWithheldCopy.removedTitle, message: BackupWithheldCopy.removedMessage)
                        : Outcome(title: BackupWithheldCopy.failedTitle, message: BackupWithheldCopy.failedMessage)
                } else {
                    self.outcome = Outcome(
                        title: BackupWithheldCopy.broughtBackTitle,
                        message: result.backupUpdated
                            ? BackupWithheldCopy.broughtBackMessage(count: result.restored, stillMissing: result.stillMissing)
                            : BackupWithheldCopy.broughtBackPendingMessage(count: result.restored, stillMissing: result.stillMissing)
                    )
                }
            } catch PhoneStatsStore.RecoveryError.nothingReadable {
                self.outcome = Outcome(title: BackupWithheldCopy.failedTitle, message: BackupWithheldCopy.noneReadableMessage)
            } catch PhoneStatsStore.RecoveryError.notPersisted {
                self.outcome = Outcome(
                    title: ArchiveSaveFailureCopy.matchNotSavedTitle,
                    message: ArchiveSaveFailureCopy.message(savingPaused: store.isArchiveBlocked)
                )
            } catch {
                self.outcome = Outcome(title: BackupWithheldCopy.failedTitle, message: BackupWithheldCopy.failedMessage)
            }
        }
    }

    /// Opens the Remove from Backup confirmation for the matches withheld right now.
    func confirmRemove(_ store: PhoneStatsStore) {
        let ids = store.withheldBackupMatchIDs()
        if !ids.isEmpty { removeIDs = ids }
    }

    func remove(_ store: PhoneStatsStore, confirmed: Set<UUID>) {
        run {
            do {
                try await store.removeWithheldMatchesFromBackup(confirmed: confirmed)
                self.outcome = Outcome(title: BackupWithheldCopy.removedTitle, message: BackupWithheldCopy.removedMessage)
            } catch PhoneStatsStore.RecoveryError.withheldSetChanged {
                // More is withheld than the user agreed to remove: remove
                // nothing and ask again about the current set.
                self.confirmRemove(store)
            } catch {
                self.outcome = Outcome(title: BackupWithheldCopy.failedTitle, message: BackupWithheldCopy.failedMessage)
            }
        }
    }

    private func run(_ work: @escaping @MainActor () async -> Void) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            await work()
            isWorking = false
        }
    }
}

extension View {
    /// The recovery alerts and share sheet, attached where they outlive the notices.
    func archiveRecoveryPresentations(
        _ model: ArchiveRecoveryModel,
        store: PhoneStatsStore,
        syncService: PhoneMatchSyncService
    ) -> some View {
        modifier(ArchiveRecoveryPresentations(model: model, store: store, syncService: syncService))
    }
}

private struct ArchiveRecoveryPresentations: ViewModifier {
    @Bindable var model: ArchiveRecoveryModel
    let store: PhoneStatsStore
    let syncService: PhoneMatchSyncService

    func body(content: Content) -> some View {
        content
            .alert(
                model.restoreOffer?.title ?? "",
                isPresented: isPresented(\.restoreOffer),
                presenting: model.restoreOffer
            ) { offer in
                if case .available = offer {
                    Button(ArchiveRecoveryCopy.restoreConfirm) {
                        DispatchQueue.main.async {
                            model.restore(store, syncService: syncService)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } else {
                    Button("OK", role: .cancel) {}
                }
            } message: { offer in
                Text(offer.message)
            }
            .alert(
                BackupWithheldCopy.removeTitle(count: model.removeCount ?? 0),
                isPresented: isPresented(\.removeIDs),
                presenting: model.removeIDs
            ) { ids in
                Button(BackupWithheldCopy.removeConfirm, role: .destructive) {
                    DispatchQueue.main.async {
                        model.remove(store, confirmed: ids)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { ids in
                Text(BackupWithheldCopy.removeMessage(count: ids.count))
            }
            .alert(
                model.outcome?.title ?? "",
                isPresented: isPresented(\.outcome),
                presenting: model.outcome
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { outcome in
                Text(outcome.message)
            }
            // The copied files are deliberately not deleted when the sheet
            // closes: AirDrop or Mail may still be reading them. The store
            // sweeps old copies the next time one is made.
            .sheet(item: $model.sharedFiles) { files in
                RecoveryShareSheet(activityItems: files.urls)
            }
    }

    private func isPresented<T>(_ keyPath: ReferenceWritableKeyPath<ArchiveRecoveryModel, T?>) -> Binding<Bool> {
        Binding(
            get: { model[keyPath: keyPath] != nil },
            set: { if !$0 { model[keyPath: keyPath] = nil } }
        )
    }
}

/// The system share sheet for the copied archive files.
private struct RecoveryShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
