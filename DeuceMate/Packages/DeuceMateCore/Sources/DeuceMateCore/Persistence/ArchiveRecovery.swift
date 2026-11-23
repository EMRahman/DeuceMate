// ArchiveRecovery.swift — the ways out of a paused iPhone archive or iCloud
// backup, and what the archive screen says about them (TECHNICAL_DEBT #18).
//
// Fail-closed loading and `BackupPushGuard` stop the damage: an archive file
// that can't be used is kept and writes stop (`ArchiveLoadProblem`), and a push
// that would drop matches with no deletion to explain it is withheld. This file
// holds the pure parts of getting out again:
//   • `LenientRecordList` reads a backup one match at a time, so one match from
//     a newer build can't stop every other match from coming back.
//   • `ICloudArchiveRestore` is what the iCloud backup can offer an archive
//     that couldn't be read, with the wording for each outcome.
//   • `ArchiveRecoveryCopy` and `BackupWithheldCopy` are the buttons, alerts
//     and results.
//
// Every destructive choice keeps a copy of what it replaces (the store copies
// the preserved files, or the backup's record file, before writing), and the
// copy says so. Nothing here deletes.
import Foundation

/// A backup's records decoded one at a time. A record this build can't decode
/// (a newer format, or an unknown enum value) is counted and skipped instead
/// of failing the whole list, which is what a plain `[MatchRecord]` decode does.
/// Use ONLY for deliberate recovery reads — never the normal archive load.
public struct LenientRecordList: Decodable, Sendable {
    public let records: [MatchRecord]
    /// Records that were present but couldn't be decoded by this build.
    public let undecodableCount: Int
    /// Valid UUID `id` values extracted from records this build couldn't fully
    /// decode (e.g. a newer-format match with an unknown enum case).
    public let undecodableRecordIDs: Set<UUID>
    /// Undecodable elements from which even a UUID `id` couldn't be read.
    public let unidentifiedUndecodableCount: Int

    public init(
        records: [MatchRecord],
        undecodableCount: Int,
        undecodableRecordIDs: Set<UUID> = []
    ) {
        self.records = records
        self.undecodableCount = undecodableCount
        self.undecodableRecordIDs = undecodableRecordIDs
        self.unidentifiedUndecodableCount = max(0, undecodableCount - undecodableRecordIDs.count)
    }

    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var records: [MatchRecord] = []
        var skipped = 0
        var skippedIDs: Set<UUID> = []
        var unidentified = 0
        while !container.isAtEnd {
            if let record = try? container.decode(MatchRecord.self) {
                records.append(record)
            } else {
                // A failed decode doesn't advance the container; consume the
                // element with a decode that always succeeds while retaining
                // its UUID `id` whenever present.
                let skippedElement = try container.decode(SkippedElement.self)
                skipped += 1
                if let id = skippedElement.id {
                    skippedIDs.insert(id)
                } else {
                    unidentified += 1
                }
            }
        }
        self.records = records
        self.undecodableCount = skipped
        self.undecodableRecordIDs = skippedIDs
        self.unidentifiedUndecodableCount = unidentified
    }

    /// All record IDs known to be present in the list (fully decoded plus
    /// undecodable elements whose UUID `id` was readable).
    public var allKnownRecordIDs: Set<UUID> {
        Set(records.map(\.id)).union(undecodableRecordIDs)
    }

    /// True when at least one undecodable element didn't carry a valid UUID `id`,
    /// so `allKnownRecordIDs` cannot represent the whole list.
    public var hasUnidentifiedUndecodable: Bool {
        unidentifiedUndecodableCount > 0
    }

    /// Undecodable matches that are NOT already accounted for by `tombstones`.
    /// Any undecodable element without a readable UUID is conservatively kept.
    public func undecodableCount(excluding tombstones: Set<UUID>) -> Int {
        undecodableRecordIDs.subtracting(tombstones).count + unidentifiedUndecodableCount
    }

    private struct SkippedElement: Decodable {
        let id: UUID?

        private enum CodingKeys: String, CodingKey {
            case id
        }

        init(from decoder: Decoder) throws {
            if let container = try? decoder.container(keyedBy: CodingKeys.self),
               let id = try? container.decode(UUID.self, forKey: .id) {
                self.id = id
            } else {
                self.id = nil
            }
        }
    }
}

/// What the iCloud backup can offer an iPhone archive that couldn't be read.
public enum ICloudArchiveRestore: Equatable, Sendable {
    /// The backup can be restored. `newerFormatCount` matches in it can't be
    /// read by this build; they stay in the backup (the push guard keeps them).
    case available(ArchiveBackupPolicy.BackupPreview, newerFormatCount: Int)
    case noBackup
    case iCloudUnavailable
    case downloading
    /// The backup exists, but either a remote file declared a newer schema
    /// version (`count == nil`) or every match in it requires a newer build
    /// (`count == N > 0`). Updating DeuceMate is required to restore it.
    case requiresNewerVersion(count: Int?)
    /// The backup exists but its records, deletions, or forgotten players can't
    /// be read, so restoring could bring back something the user deleted.
    case unreadable

    public var title: String {
        switch self {
        case .available:            return "Restore from iCloud Backup?"
        case .noBackup:             return "No iCloud Backup Found"
        case .iCloudUnavailable:    return "iCloud Isn't Available"
        case .downloading:          return "iCloud Backup Is Downloading"
        case .requiresNewerVersion: return "Update DeuceMate to Restore"
        case .unreadable:           return "iCloud Backup Couldn't Be Read"
        }
    }

    public var message: String {
        switch self {
        case .available(let preview, let newer):
            var parts: [String] = []
            let count = BackupWithheldCopy.matches(preview.recordCount)
            if let latest = preview.newestMatchDate {
                parts.append("Your iCloud backup has \(count), latest \(latest.formatted(date: .abbreviated, time: .omitted)).")
            } else {
                parts.append("Your iCloud backup has \(count).")
            }
            if newer > 0 {
                parts.append("\(BackupWithheldCopy.matches(newer).capitalizedFirst) need\(newer == 1 ? "s" : "") a newer version of DeuceMate and will stay in the backup.")
            }
            parts.append("DeuceMate keeps a copy of the files it couldn't read on this iPhone before restoring.")
            return parts.joined(separator: " ")
        case .noBackup:
            return "There's no DeuceMate backup in iCloud to restore from."
        case .iCloudUnavailable:
            return "Sign in to iCloud and turn on iCloud Drive for DeuceMate, then try again."
        case .downloading:
            return "The backup is still downloading from iCloud. Try again in a moment."
        case .requiresNewerVersion(let count):
            if let count, count > 0 {
                return "\(BackupWithheldCopy.matches(count).capitalizedFirst) in your iCloud backup need\(count == 1 ? "s" : "") a newer version of DeuceMate. Update DeuceMate to restore. Nothing has been changed."
            }
            return "Your iCloud backup was written by a newer version of DeuceMate. Update DeuceMate to restore. Nothing has been changed."
        case .unreadable:
            return "This version of DeuceMate couldn't read the backup either. Nothing has been changed."
        }
    }
}

/// Why outbound iCloud backup pushes are paused due to the remote backup files
/// themselves (corrupt or newer-schema remote history/tombstones/ledger, or a
/// fresh-install backup whose every match requires a newer build).
public enum RemoteBackupProblem: String, CaseIterable, Equatable, Sendable {
    case newerVersion
    case unreadable

    public var title: String {
        switch self {
        case .newerVersion: return "iCloud Backup Needs an Update"
        case .unreadable:   return "iCloud Backup Paused"
        }
    }

    public var message: String {
        switch self {
        case .newerVersion:
            return "Your iCloud backup was written by a newer version of DeuceMate. DeuceMate has left it untouched and paused automatic backups until you update DeuceMate. Your matches on this iPhone are unaffected."
        case .unreadable:
            return "DeuceMate couldn't read the existing iCloud backup files cleanly, so it has left them untouched and paused automatic backups. Your matches on this iPhone are unaffected."
        }
    }

    public var systemImage: String { "exclamationmark.icloud" }
}

/// Buttons, alerts and results for recovering an archive that couldn't be loaded.
public enum ArchiveRecoveryCopy {
    public static let tryAgain = "Try Again"
    public static let restoreFromICloud = "Restore from iCloud"
    public static let restoreConfirm = "Restore"
    public static let saveCopy = "Save a Copy"
    public static let importHint = "You can also replace them with a backup file in Settings › Backup & Transfer."

    public static let stillUnavailableTitle = "Still Couldn't Open Matches"
    public static let stillUnavailableMessage = "DeuceMate still couldn't open your saved matches. Nothing has been changed. Try again later or restart DeuceMate."
    public static let restoredTitle = "Matches Restored"
    public static func restoredMessage(count: Int) -> String {
        "Restored \(BackupWithheldCopy.matches(count)) from your iCloud backup."
    }
    /// Appended to the first-launch "iCloud Backup Found" prompt when part of
    /// the backup is from a newer build; `nil` when every match is readable.
    public static func restorePromptNewerNote(count: Int) -> String? {
        guard count > 0 else { return nil }
        return "\(BackupWithheldCopy.matches(count).capitalizedFirst) need\(count == 1 ? "s" : "") a newer version of DeuceMate and will stay in the backup."
    }
    public static let restoredBackupNotResumedMessage = "Your matches are restored, but DeuceMate couldn't switch iCloud backup back on yet. It will try again the next time DeuceMate opens."
    /// Added to the Replace confirmation: Replace can drop matches that exist
    /// only in the iCloud backup, so it says that a copy is kept first.
    public static let replaceKeepsBackupCopyNote = "DeuceMate keeps a copy of the current iCloud backup on this iPhone first, since the backup will then match the imported archive."
    public static let failedTitle = "Couldn't Restore"
    public static let failedMessage = "DeuceMate couldn't restore your matches. Nothing has been changed. Try again in a moment."
    public static let saveCopyFailedTitle = "Couldn't Save a Copy"
    public static let saveCopyFailedMessage = "DeuceMate couldn't copy the files. They're still on this iPhone, untouched."
}

/// Alerts when the user's own save or permanent delete couldn't be written
/// (manual entry, End at Current Score, Delete Permanently). The store leaves
/// the archive as it was, so the copy only ever says nothing changed — and,
/// while the archive is paused, points at the notice that explains why.
public enum ArchiveSaveFailureCopy {
    public static let matchNotSavedTitle = "Match Not Saved"
    public static let matchNotDeletedTitle = "Match Not Deleted"

    public static func message(savingPaused: Bool) -> String {
        savingPaused
            ? "Saving is paused until the problem described on the Matches screen is resolved. Nothing has been changed."
            : "This iPhone couldn't save the change. Nothing has been changed. Try again, or restart DeuceMate if this keeps happening."
    }
}

/// The notice, buttons and results when a backup push was withheld because
/// matches left this iPhone with no deletion or Replace to explain it.
public enum BackupWithheldCopy {
    public static let title = "iCloud Backup Paused"
    public static let systemImage = "exclamationmark.icloud"
    public static let bringBack = "Bring Them Back"
    public static let remove = "Remove from Backup"
    public static let removeConfirm = "Remove"

    /// "1 match" / "3 matches".
    public static func matches(_ count: Int) -> String {
        "\(count) match\(count == 1 ? "" : "es")"
    }

    public static func message(count: Int) -> String {
        let them = count == 1 ? "it" : "them"
        let isAre = count == 1 ? "is" : "are"
        return "\(matches(count).capitalizedFirst) in your iCloud backup \(isAre)n't on this iPhone, and nothing records deleting \(them). DeuceMate is keeping \(them) in the backup until you choose."
    }

    public static func removeTitle(count: Int) -> String {
        "Remove \(matches(count).capitalizedFirst) from iCloud Backup?"
    }

    public static func removeMessage(count: Int) -> String {
        let they = count == 1 ? "It" : "They"
        return "\(they)'ll be removed from the backup to match this iPhone. DeuceMate keeps a copy of the current backup on this iPhone first. If your Apple Watch still has \(count == 1 ? "it" : "them"), \(count == 1 ? "it" : "they") can sync back."
    }

    public static let broughtBackTitle = "Matches Brought Back"
    public static func broughtBackMessage(count: Int, stillMissing: Int) -> String {
        var text = "Brought back \(matches(count)) from your iCloud backup."
        if stillMissing > 0 {
            text += " \(matches(stillMissing).capitalizedFirst) need\(stillMissing == 1 ? "s" : "") a newer version of DeuceMate and stay\(stillMissing == 1 ? "s" : "") in the backup."
        }
        return text
    }
    /// Matches were added back to this iPhone but the backup couldn't be
    /// updated yet; DeuceMate retries on its own.
    public static let broughtBackPendingTitle = "Matches Brought Back"
    public static func broughtBackPendingMessage(count: Int, stillMissing: Int) -> String {
        broughtBackMessage(count: count, stillMissing: stillMissing)
            + " DeuceMate couldn't reach your iCloud backup just now and will update it when it can."
    }
    public static let removedTitle = "Backup Updated"
    public static let removedMessage = "The iCloud backup now matches this iPhone."
    public static let failedTitle = "Couldn't Update the Backup"
    public static let failedMessage = "DeuceMate couldn't reach your iCloud backup. Nothing has been changed. Try again in a moment."
    public static let noneReadableMessage = "This version of DeuceMate couldn't read those matches in the backup. Nothing has been changed. If an update to DeuceMate is available, install it."
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
