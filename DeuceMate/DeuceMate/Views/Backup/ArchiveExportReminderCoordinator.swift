// ArchiveExportReminderCoordinator.swift — owns the three phone-local
// UserDefaults keys around Core's `ArchiveExportReminderPolicy`
// (docs/features/ARCHIVE_EXPORT_REMINDER_PLAN.md §5.2–§5.3).
import Foundation
import Combine
import DeuceMateCore

@MainActor
final class ArchiveExportReminderCoordinator: ObservableObject {
    static let shared = ArchiveExportReminderCoordinator()

    @Published private(set) var isEnabled: Bool
    @Published private(set) var baseline: Date?
    @Published private(set) var lastExportDate: Date?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Absent key means enabled (default ON).
        self.isEnabled = defaults.object(forKey: ArchiveExportReminderPolicy.enabledKey) as? Bool ?? true
        self.baseline = defaults.object(forKey: ArchiveExportReminderPolicy.baselineKey) as? Date
        self.lastExportDate = defaults.object(forKey: ArchiveExportReminderPolicy.lastExportDateKey) as? Date
    }

    func reminder(
        for records: [MatchRecord],
        matchIDsWithNotes: Set<UUID>,
        archiveOpenedNormally: Bool,
        icloudStatus: ICloudBackupCopy
    ) -> ArchiveExportReminderPolicy.Reminder {
        ArchiveExportReminderPolicy.state(
            records: records,
            matchIDsWithNotes: matchIDsWithNotes,
            isEnabled: isEnabled,
            archiveOpenedNormally: archiveOpenedNormally,
            backupProtectsNonHealthData: ArchiveExportReminderPolicy.backupProtectsNonHealthData(for: icloudStatus),
            baseline: baseline
        )
    }

    /// Call only after `fileExporter` reports a successful save.
    func recordExport(now: Date = Date()) {
        baseline = now
        lastExportDate = now
        defaults.set(now, forKey: ArchiveExportReminderPolicy.baselineKey)
        defaults.set(now, forKey: ArchiveExportReminderPolicy.lastExportDateKey)
    }

    /// "Later": advances the baseline so the card hides until another 5
    /// countable matches complete. Deliberately leaves `lastExportDate` alone.
    func snooze(now: Date = Date()) {
        baseline = now
        defaults.set(now, forKey: ArchiveExportReminderPolicy.baselineKey)
    }

    /// "Don't Remind Me Again": reversible through Settings › Backup & Transfer.
    func disable() {
        setEnabled(false)
    }

    /// Settings toggle: turning reminders back on leaves the baseline intact so
    /// any already-unexported matches above threshold show the card straight away.
    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: ArchiveExportReminderPolicy.enabledKey)
    }

    /// Advances the baseline after a successful manual archive import (Merge or
    /// Replace) so restoring a file on a new iPhone doesn't trigger an instant
    /// card. Never moves backwards and never touches `lastExportDate`.
    func recordImport(exportedAt: Date) {
        let next = ArchiveExportReminderPolicy.baselineAfterImport(
            current: baseline,
            archiveExportedAt: exportedAt
        )
        baseline = next
        defaults.set(next, forKey: ArchiveExportReminderPolicy.baselineKey)
    }
}
