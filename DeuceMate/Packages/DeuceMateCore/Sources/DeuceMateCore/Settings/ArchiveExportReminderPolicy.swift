// ArchiveExportReminderPolicy.swift — pure policy and copy for reminding the
// iPhone user every 5 matches to export a full-fidelity manual match archive
// (docs/features/ARCHIVE_EXPORT_REMINDER_PLAN.md).
//
// No UserDefaults, no SwiftUI, no Watch sync: the iPhone supplies the facts and
// persists the three phone-local keys pinned here.
import Foundation

public enum ArchiveExportReminderPolicy {

    /// Number of countable matches completed after the baseline before the
    /// Matches screen shows the reminder card (and after tapping Later).
    public static let threshold = 5

    /// Phone-local UserDefaults keys (CLAUDE.md §0 exceptions — never synced).
    /// Raw strings are pinned by `ArchiveExportReminderPolicyTests`.
    public static let enabledKey = "archiveExportReminderEnabled"
    public static let baselineKey = "archiveExportReminderBaseline"
    public static let lastExportDateKey = "archiveLastExportDate"

    /// What automatic backups cannot carry to a new iPhone for this archive.
    public enum MissingCategory: Hashable, Sendable {
        case health
        case notes
        case everything
    }

    public enum Reminder: Equatable, Sendable {
        case hidden
        case due(count: Int, missing: Set<MissingCategory>)
    }

    /// Whether the current iCloud backup state protects scores, points, stats
    /// and match details. Only `.notBackedUp` and `.unavailable` leave the
    /// whole archive unprotected; pending/restoring/uploaded states all have
    /// iCloud enabled and available.
    public static func backupProtectsNonHealthData(for status: ICloudBackupCopy) -> Bool {
        switch status {
        case .notBackedUp, .unavailable:
            return false
        case .backedUp, .pendingUpload, .restoring, .pendingRestore:
            return true
        }
    }

    /// Number of completed matches after `baseline` that hold data the
    /// automatic backup doesn't protect (or every completed match after
    /// `baseline` when iCloud backup is off or unavailable).
    public static func countableMatchCount(
        records: [MatchRecord],
        matchIDsWithNotes: Set<UUID>,
        backupProtectsNonHealthData: Bool,
        since baseline: Date?
    ) -> Int {
        records.reduce(into: 0) { count, record in
            if isCountable(
                record,
                matchIDsWithNotes: matchIDsWithNotes,
                backupProtectsNonHealthData: backupProtectsNonHealthData,
                since: baseline
            ) {
                count += 1
            }
        }
    }

    /// Resolves whether the Matches screen should show the export reminder card.
    public static func state(
        records: [MatchRecord],
        matchIDsWithNotes: Set<UUID>,
        isEnabled: Bool,
        archiveOpenedNormally: Bool,
        backupProtectsNonHealthData: Bool,
        baseline: Date?,
        threshold: Int = Self.threshold
    ) -> Reminder {
        guard isEnabled, archiveOpenedNormally, threshold > 0 else { return .hidden }

        let count = countableMatchCount(
            records: records,
            matchIDsWithNotes: matchIDsWithNotes,
            backupProtectsNonHealthData: backupProtectsNonHealthData,
            since: baseline
        )
        guard count >= threshold else { return .hidden }

        var missing: Set<MissingCategory> = []
        let hasHealth = records.contains { HealthExportConsent.hasRawHealthData(in: $0) }
        let hasNotes = records.contains { matchIDsWithNotes.contains($0.id) }

        if !backupProtectsNonHealthData {
            missing.insert(.everything)
            if hasNotes { missing.insert(.notes) }
        } else {
            if hasHealth { missing.insert(.health) }
            if hasNotes { missing.insert(.notes) }
        }

        return .due(count: count, missing: missing)
    }

    /// Advances the baseline after a manual archive import so restoring a file
    /// onto a new iPhone doesn't trigger an instant reminder. Never moves
    /// backwards.
    public static func baselineAfterImport(current: Date?, archiveExportedAt: Date) -> Date {
        guard let current else { return archiveExportedAt }
        return max(current, archiveExportedAt)
    }

    private static func isCountable(
        _ record: MatchRecord,
        matchIDsWithNotes: Set<UUID>,
        backupProtectsNonHealthData: Bool,
        since baseline: Date?
    ) -> Bool {
        guard !record.isInProgress else { return false }
        let completionDate = record.endTime ?? record.startTime
        if let baseline, completionDate <= baseline { return false }
        if !backupProtectsNonHealthData { return true }
        return HealthExportConsent.hasRawHealthData(in: record)
            || matchIDsWithNotes.contains(record.id)
    }
}

/// Copy for the export reminder card and Settings › Backup & Transfer.
/// Lives in Core so the iPhone app and browser demo stay aligned and tests pin
/// the honesty rules (no overclaiming "lost forever", no steering to iCloud,
/// and never implying private notes are exported automatically).
public enum ArchiveExportReminderCopy {
    public static let title = "Keep a full copy of your matches"
    public static let exportButtonTitle = "Export Archive"
    public static let laterButtonTitle = "Later"
    public static let disableButtonTitle = "Don't Remind Me Again"
    public static let disableAccessibilityHint = "You can turn reminders back on in Settings under Backup & Transfer."
    public static let settingsToggleTitle = "Remind Me to Export"
    public static let neverExportedText = "Never exported"

    public static func lastExportedText(formattedDate: String?) -> String {
        guard let formattedDate, !formattedDate.isEmpty else { return neverExportedText }
        return "Last exported \(formattedDate)"
    }

    public static func body(
        count: Int,
        missing: Set<ArchiveExportReminderPolicy.MissingCategory>
    ) -> String {
        let matchWord = count == 1 ? "match" : "matches"
        let lead = "You've recorded \(count) \(matchWord) since your last export."

        if missing.contains(.everything) {
            if missing.contains(.notes) {
                return "\(lead) Your matches aren't backed up anywhere else. An archive file keeps your matches, and can include your private notes if you choose to add them. Import it if you move to a new iPhone."
            }
            return "\(lead) Your matches aren't backed up anywhere else. An archive file keeps everything. Import it if you move to a new iPhone."
        }

        let hasHealth = missing.contains(.health)
        let hasNotes = missing.contains(.notes)

        switch (hasHealth, hasNotes) {
        case (true, true):
            return "\(lead) Your iCloud backup keeps scores and stats, but not heart rate, steps, distance, calories or private notes. An archive file keeps your health data, and can include your private notes if you choose to add them. Import it if you move to a new iPhone."
        case (true, false):
            return "\(lead) Your iCloud backup keeps scores and stats, but not heart rate, steps, distance or calories. An archive file keeps them all. Import it if you move to a new iPhone."
        case (false, true):
            return "\(lead) Your iCloud backup keeps scores and stats, but not private notes. An archive file can include your private notes when you choose to add them. Import it if you move to a new iPhone."
        case (false, false):
            return "\(lead) Save an archive file somewhere other than this iPhone so you can import it on a new iPhone."
        }
    }
}
