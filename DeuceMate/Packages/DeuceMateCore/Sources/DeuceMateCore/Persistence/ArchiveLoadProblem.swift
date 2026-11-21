// ArchiveLoadProblem.swift — why the iPhone archive stopped saving, and what
// the archive screen tells the user about it (TECHNICAL_DEBT #18).
//
// A canonical archive file (match history, deletion tombstones or the
// forgotten-player ledger) that exists but cannot be used is never treated as
// an empty archive. `PhoneStatsStore` leaves the file exactly where it is,
// suspends every canonical write and iCloud backup push for the process, and
// publishes one of these so the screen can explain why the list looks empty or
// incomplete instead of showing "No Matches Yet".
//
// The copy states only what the app really does: it has not deleted anything,
// it is not saving or backing up, and the Watch still holds its recent matches
// (the Watch is the source of live scoring and keeps `WatchHistory.cap`
// matches). It does not promise a recovery action this build cannot offer.
import Foundation

public enum ArchiveLoadProblem: String, CaseIterable, Sendable {
    /// The file exists but could not be read (an I/O or data-protection
    /// error). Often transient, so the next launch may succeed.
    case unreadable
    /// The file was read but could not be decoded — damaged, or written by a
    /// newer version of DeuceMate. Deterministic: the bytes are preserved in
    /// place, so every launch reaches the same diagnosis until it is resolved.
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
            return "This iPhone couldn't open your saved matches. \(common) Restart DeuceMate to try again."
        case .undecodable:
            return "This version of DeuceMate couldn't read your saved matches. \(common) If an update to DeuceMate is available, install it."
        }
    }

    public var systemImage: String { "exclamationmark.triangle.fill" }
}
