// ICloudBackupCopy.swift — single source of truth for the global iCloud backup
// status line shown above the iPhone match list (and mirrored in match detail).
//
// The archive's canonical copy always lives on-device (`PhoneStatsStore`);
// iCloud Drive holds a file-based background backup used for backup and
// fresh-install restore. The status is derived from evidence — account
// availability, whether a pending restore prompt is shown, and whether the
// most-recently-pushed files have been uploaded by the iCloud daemon. Kept in
// the package — like `SettingsCopy` — so the list and detail views can never
// show drifting copy, and so it stays unit-testable with no simulator.
import Foundation

/// The global "is my history backed up to iCloud?" indicator.
public enum ICloudBackupCopy: CaseIterable, Sendable {
    /// iCloud sync is on and the last-pushed files are confirmed uploaded.
    case backedUp
    /// iCloud sync is off — the archive is on this device only, by choice.
    case notBackedUp
    /// iCloud sync is on but the account/container is unavailable (signed out of
    /// iCloud, or iCloud Drive off). The archive itself is safe — it always lives
    /// on-device — but backup pushes pause until iCloud returns. Distinct from
    /// `.notBackedUp` so the user can tell it apart and fix it — and so we never
    /// claim "Backed up" while backup is paused.
    case unavailable
    /// A fresh install is still pulling the archive out of the iCloud backup;
    /// the list may be momentarily incomplete while the restore finishes.
    case restoring
    /// An iCloud backup was found on a fresh install and is waiting for the user
    /// to decide whether to restore it. Backup pushes stay paused (the marker is
    /// absent) until the user responds, so the old backup is never overwritten
    /// while the question is open.
    case pendingRestore
    /// The archive has been pushed to the local iCloud replica, but the iCloud
    /// daemon has not yet confirmed the upload. Shown instead of `.backedUp`
    /// until both backup files report `.ubiquitousItemIsUploaded == true`, and
    /// also when nothing has ever been pushed (nil receipt → don't claim backed up).
    case pendingUpload

    /// Short status label (not a full sentence) for the indicator strip.
    public var text: String {
        switch self {
        case .backedUp:       return "Backed up to iCloud"
        case .notBackedUp:    return "Not backed up to iCloud"
        case .unavailable:    return "iCloud unavailable — stored on iPhone"
        case .restoring:      return "Restoring from iCloud…"
        case .pendingRestore: return "iCloud backup found — restore pending"
        case .pendingUpload:  return "Waiting to upload to iCloud"
        }
    }

    /// SF Symbol name paired with the label.
    public var systemImage: String {
        switch self {
        case .backedUp:       return "checkmark.icloud"
        case .notBackedUp:    return "icloud.slash"
        case .unavailable:    return "exclamationmark.icloud"
        case .restoring:      return "arrow.triangle.2.circlepath.icloud"
        case .pendingRestore: return "icloud.and.arrow.down"
        case .pendingUpload:  return "arrow.clockwise.icloud"
        }
    }

    /// Resolves the indicator from the iCloud sync toggle, account/container
    /// availability, restore state, and the upload receipt for the most-recently-
    /// pushed files.
    ///
    /// Resolution order (higher entries win):
    /// 1. Toggle off → `.notBackedUp`
    /// 2. iCloud unavailable → `.unavailable`
    /// 3. Restore in flight → `.restoring`
    /// 4. Restore prompt pending user decision → `.pendingRestore`
    /// 5. Files not yet confirmed uploaded (`nil` = never pushed, `false` = uploading) → `.pendingUpload`
    /// 6. Otherwise → `.backedUp`
    public static func current(
        isEnabled: Bool,
        isAvailable: Bool,
        isRestoring: Bool = false,
        hasPendingRestore: Bool = false,
        isUploaded: Bool? = nil
    ) -> ICloudBackupCopy {
        guard isEnabled else { return .notBackedUp }
        guard isAvailable else { return .unavailable }
        if isRestoring { return .restoring }
        if hasPendingRestore { return .pendingRestore }
        guard isUploaded == true else { return .pendingUpload }
        return .backedUp
    }
}
