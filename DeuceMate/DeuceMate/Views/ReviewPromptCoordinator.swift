// ReviewPromptCoordinator.swift — tracks one open match report and answers, when
// it closes, whether to request an App Store rating. The rule is Core's
// `ReviewPromptPolicy`; this owns the timing state and the two local flags.
import Foundation
import DeuceMateCore

@MainActor
final class ReviewPromptCoordinator {
    /// Phone-local; never synced (CLAUDE.md §0).
    static let lastRequestDateKey = "reviewPromptLastRequestDate"
    static let lastRequestVersionKey = "reviewPromptLastRequestVersion"

    private struct OpenReport {
        let matchID: UUID
        var timer: ReviewAttentionTimer
    }

    private let defaults: UserDefaults
    private let appVersion: String
    private var openReport: OpenReport?

    init(
        defaults: UserDefaults = .standard,
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    ) {
        self.defaults = defaults
        self.appVersion = appVersion
    }

    func reportOpened(matchID: UUID, isActive: Bool, now: Date = Date()) {
        openReport = OpenReport(matchID: matchID, timer: ReviewAttentionTimer(startedAt: now, isActive: isActive))
    }

    func scenePhaseChanged(isActive: Bool, now: Date = Date()) {
        openReport?.timer.setActive(isActive, at: now)
    }

    /// Consumes the open report, so one close can only ever be judged once.
    /// `history` is passed in rather than read from the sheet's copy: the record
    /// may have changed while open, or been deleted, which must not prompt.
    func shouldRequestReviewOnClose(history: [MatchRecord], now: Date = Date()) -> Bool {
        guard let report = openReport else { return false }
        openReport = nil
        guard let record = history.first(where: { $0.id == report.matchID }) else { return false }
        return ReviewPromptPolicy.shouldRequestReview(
            closing: record,
            completedMatchCount: history.lazy.filter { !$0.isInProgress }.count,
            reportAttention: report.timer.elapsed(at: now),
            history: ReviewPromptPolicy.RequestHistory(
                lastRequestDate: defaults.object(forKey: Self.lastRequestDateKey) as? Date,
                lastRequestVersion: defaults.string(forKey: Self.lastRequestVersionKey)
            ),
            appVersion: appVersion,
            now: now
        )
    }

    /// Call only once the request is really being made. Apple doesn't say whether
    /// anything appeared, so this counts requests, not prompts seen.
    func recordRequest(now: Date = Date()) {
        defaults.set(now, forKey: Self.lastRequestDateKey)
        defaults.set(appVersion, forKey: Self.lastRequestVersionKey)
    }
}
