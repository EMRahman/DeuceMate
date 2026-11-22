// ArchiveLoadProblem.swift — why the iPhone archive stopped saving, and what
// the archive screen tells the user about it (TECHNICAL_DEBT #18).
//
// A canonical archive file (match history, deletion tombstones or the
// forgotten-player ledger) that exists but cannot be used is never treated as
// an empty archive. `PhoneStatsStore` leaves the file exactly where it is,
// suspends every canonical write and iCloud backup push, and publishes one of
// these so the screen can explain why the list is unavailable instead of
// showing "No Matches Yet".
//
// The copy states only what the app really does: it has not deleted anything,
// it is not saving or backing up, and the Watch still holds its recent matches
// (`WatchHistory.cap`). The recovery actions themselves (Try Again, Restore
// from iCloud, Save a Copy) are worded in `ArchiveRecoveryCopy`; the message
// never promises an action that isn't on screen.
import Foundation

public enum ArchiveLoadProblem: String, CaseIterable, Sendable {
    /// The file exists but could not be read (an I/O or data-protection
    /// error). Often transient, so Try Again or the next launch may succeed.
    case unreadable
    /// The file was read but could not be decoded — damaged, written by a
    /// newer version of DeuceMate, an orphaned legacy `.corrupt` quarantine, or
    /// an initialized archive missing required files. Deterministic: the bytes
    /// are preserved in place so every launch reaches the same diagnosis until
    /// resolved.
    case undecodable

    /// When two files fail differently, keep the more persistent diagnosis:
    /// an undecodable file will not fix itself on relaunch.
    public func combined(with other: ArchiveLoadProblem?) -> ArchiveLoadProblem {
        self == .undecodable || other == .undecodable ? .undecodable : self
    }

    public var title: String {
        switch self {
        case .unreadable:  return "Matches Couldn't Be Opened"
        case .undecodable: return "Matches Couldn't Be Read"
        }
    }

    public var message: String {
        let common = "DeuceMate has left them untouched and won't save changes or back up to iCloud until this is resolved. Your Apple Watch keeps its recent matches."
        switch self {
        case .unreadable:
            return "This iPhone couldn't open your saved matches. \(common) This is often temporary, so try again in a moment."
        case .undecodable:
            return "This version of DeuceMate couldn't read your saved matches. \(common) If an update to DeuceMate is available, install it."
        }
    }

    public var systemImage: String { "exclamationmark.triangle.fill" }
}
