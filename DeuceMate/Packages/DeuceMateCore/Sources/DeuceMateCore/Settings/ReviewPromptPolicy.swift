// ReviewPromptPolicy.swift — when the iPhone may ask StoreKit for an App Store
// rating. Pure rule, no StoreKit: the app supplies the facts and owns the call.
//
// Apple decides whether a request actually shows anything and never reports the
// result, so `RequestHistory` records requests made, not prompts seen.
import Foundation

public enum ReviewPromptPolicy {

    /// The match must have ended this recently: the report is still fresh, and an
    /// old match being reread isn't the moment the player just got value from.
    public static let maximumMatchAge: TimeInterval = 48 * 60 * 60
    /// Foreground time with the report open, so a quick open-and-close doesn't count.
    public static let minimumReportAttention: TimeInterval = 20
    public static let minimumCompletedMatches = 3
    /// A player who rarely wins is still asked once they have this many matches.
    public static let completedMatchesForAnyResult = 6
    /// Apple allows three prompts per 365 days; this spacing stays inside it.
    public static let minimumDaysBetweenRequests = 120

    /// The user-initiated route ("Rate DeuceMate"). `requestReview` may silently
    /// do nothing, so Apple says not to call it from a button; this always works.
    public static let writeReviewURL = MatchWebViewModel.appStoreURL + "?action=write-review"

    public struct RequestHistory: Equatable, Sendable {
        public var lastRequestDate: Date?
        public var lastRequestVersion: String?

        public init(lastRequestDate: Date? = nil, lastRequestVersion: String? = nil) {
            self.lastRequestDate = lastRequestDate
            self.lastRequestVersion = lastRequestVersion
        }
    }

    /// Whether closing this match's report is a moment to request a rating.
    ///
    /// Deliberately has no "do you like the app?" input: favouring a win picks a
    /// good moment, but routing people by their opinion of the app is what App
    /// Review forbids.
    public static func shouldRequestReview(
        closing record: MatchRecord,
        completedMatchCount: Int,
        reportAttention: TimeInterval,
        history: RequestHistory,
        appVersion: String,
        now: Date
    ) -> Bool {
        guard let endTime = record.endTime,
              now.timeIntervalSince(endTime) <= maximumMatchAge else { return false }
        // Score-only matches have no stats report to have enjoyed.
        guard record.stats.contains(where: { $0.outcome != .uncategorized }) else { return false }
        guard reportAttention >= minimumReportAttention else { return false }
        guard completedMatchCount >= minimumCompletedMatches else { return false }
        guard record.iWon == true || completedMatchCount >= completedMatchesForAnyResult else { return false }

        if history.lastRequestVersion == appVersion { return false }
        if let last = history.lastRequestDate {
            let minimumGap = TimeInterval(minimumDaysBetweenRequests) * 24 * 60 * 60
            if now.timeIntervalSince(last) < minimumGap { return false }
        }
        return true
    }
}

/// Foreground time a report has been open. Time in the background doesn't count:
/// a report left open overnight wasn't read overnight.
public struct ReviewAttentionTimer: Equatable, Sendable {
    private var accumulated: TimeInterval = 0
    private var runningSince: Date?

    public init(startedAt now: Date, isActive: Bool = true) {
        runningSince = isActive ? now : nil
    }

    public mutating func setActive(_ isActive: Bool, at now: Date) {
        if isActive {
            if runningSince == nil { runningSince = now }
        } else if let start = runningSince {
            accumulated += max(0, now.timeIntervalSince(start))
            runningSince = nil
        }
    }

    public func elapsed(at now: Date) -> TimeInterval {
        guard let start = runningSince else { return accumulated }
        return accumulated + max(0, now.timeIntervalSince(start))
    }
}
