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
    /// A failed write can leave an unfinished copy in history after resume.
    /// Omit it from history pushes, including to older phones that still apply
    /// unfinished records in arrival order. Completed copies always pass.
    public static func recordsForPush(_ records: [MatchRecord], liveMatchID: UUID?) -> [MatchRecord] {
        guard let liveMatchID else { return records }
        return records.filter { $0.id != liveMatchID || !$0.isInProgress }
    }
}
