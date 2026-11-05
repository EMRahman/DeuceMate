// WatchHistoryCap.swift — the watch's rolling match-history limit.
//
// The Apple Watch retains only its most recent matches; older ones roll off as
// new matches are added. The iPhone archive is uncapped (see PhoneStatsStore).
// The limit lives here, in the shared package, so the watch (which enforces it)
// and the phone (which explains it in the UI) reference one number and can't
// drift apart.
import Foundation

public enum WatchHistory {
    /// Maximum number of matches the Apple Watch keeps. Older matches are trimmed
    /// on append. The iPhone keeps everything it ever received.
    public static let cap = 25

    /// The records a full-history push may carry while `liveMatchID` is live.
    ///
    /// The phone accepts any in-progress record it receives (see
    /// `MatchMergePolicy`), so a stored in-progress copy of the live match would
    /// overwrite the newer checkpoints it already holds. Resume removes that copy,
    /// but one can remain after a failed write. Completed copies always pass: the
    /// merge policy never lets them be replaced by an in-progress record.
    ///
    /// Retire this once checkpoints carry a revision (TECHNICAL_DEBT #2).
    public static func recordsForPush(_ records: [MatchRecord], liveMatchID: UUID?) -> [MatchRecord] {
        guard let liveMatchID else { return records }
        return records.filter { $0.id != liveMatchID || !$0.isInProgress }
    }
}
