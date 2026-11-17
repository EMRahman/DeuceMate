// LiveScoreboardStatus.swift — What the iPhone live scoreboard may claim and accept.
//
// A pure rule so the badge, the swipe gate, the category panel and the browser
// demo cannot disagree about whether the Watch can currently hear the phone.
// Reachability, current-state confirmation and command waits gate input together.
import Foundation

public struct LiveScoreboardStatus: Equatable, Sendable {
    public let isWatchReachable: Bool
    public let isInputEnabled: Bool
    public let isStateConfirmed: Bool
    public let isRequestInFlight: Bool
    public let blockingReason: String?
    /// The Watch screen pausing play (changeover, "Who serves next?"), if any.
    public let prompt: LiveWatchPrompt?
    /// Whole seconds until the phone automatically asks the Watch for the score
    /// again after a refresh failed, or nil when no retry is scheduled.
    public let retryCountdown: Int?

    public init(isWatchReachable: Bool, isInputEnabled: Bool,
                isStateConfirmed: Bool = true, isRequestInFlight: Bool = false,
                blockingReason: String? = nil, prompt: LiveWatchPrompt? = nil,
                retryCountdown: Int? = nil) {
        self.isWatchReachable = isWatchReachable
        self.isInputEnabled = isInputEnabled
        self.isStateConfirmed = isStateConfirmed
        self.isRequestInFlight = isRequestInFlight
        self.blockingReason = blockingReason
        self.prompt = prompt
        self.retryCountdown = retryCountdown
    }

    /// A prompt this build can show with its answers. An unknown kind from a
    /// newer Watch is not answerable and falls back to `blockingReason`.
    private var knownPrompt: LiveWatchPrompt? {
        prompt.flatMap { $0.answers.isEmpty ? nil : $0 }
    }

    /// Whether the scoreboard shows the Watch's prompt as a card.
    public var showsPrompt: Bool { knownPrompt != nil }

    /// Whether the prompt card's buttons may send. Same connection rules as
    /// scoring, but a prompt is itself the blocker, so `blockingReason` does
    /// not apply. The Watch still checks the prompt is the one being answered.
    public var acceptsPromptAnswer: Bool {
        knownPrompt != nil && isInputEnabled && isWatchReachable && isStateConfirmed && !isRequestInFlight
    }

    /// The line under the prompt card's buttons.
    public var promptCaption: String? {
        guard showsPrompt else { return nil }
        if !isInputEnabled { return "Waiting for the Watch. Turn on iPhone Input to answer here." }
        return "Answer here or on the Watch. Both screens clear together."
    }

    /// "Waiting", not "disconnected": an in-range Watch is also unreachable while
    /// DeuceMate isn't active on it, for example wrist-down without a workout.
    public var badgeLabel: String {
        guard isWatchReachable else { return "WAITING FOR WATCH" }
        if !isStateConfirmed { return isRequestInFlight ? "SYNCING WITH WATCH" : "WAITING FOR WATCH" }
        return isRequestInFlight ? "SENDING TO WATCH" : "LIVE"
    }

    /// Whether swipes, their previews and haptics, and category actions may run.
    public var acceptsInput: Bool {
        isInputEnabled && isWatchReachable && isStateConfirmed && !isRequestInFlight
            && blockingReason == nil && prompt == nil
    }

    /// Whether to show the swipe directions. They must not be offered when a
    /// swipe would do nothing.
    public var showsSwipeHint: Bool {
        acceptsInput
    }

    /// Whether a swipe that can't be sent should say so: a warning haptic and
    /// a flash of `detail`. Only when iPhone Input is on, so the swipe was a
    /// real scoring attempt; a spectator's stray drag stays silent. The swipe
    /// itself is still never sent. Also while a Watch prompt is open: the
    /// scorer must answer it first, and the card on screen says so.
    public var refusesSwipeWithFeedback: Bool {
        isInputEnabled && (!isWatchReachable || showsPrompt)
    }

    /// Why the score may be stale and, when relevant, how to resume scoring.
    public var detail: String? {
        if isWatchReachable {
            if !isStateConfirmed {
                if isRequestInFlight { return "Getting the current score from the Watch." }
                if let seconds = retryCountdown { return Self.retryMessage(seconds: seconds) }
                return "Current score not confirmed. Refresh to reconnect."
            }
            if isRequestInFlight { return "Waiting for the Watch to confirm." }
            // The prompt card explains itself; repeating "Continue on the
            // Watch" beside a button that does exactly that would mislead.
            return showsPrompt ? nil : blockingReason
        }
        return isInputEnabled
            ? "Last score shown. Open DeuceMate on the Watch to score here."
            : "Last score shown. Updates resume when the Watch reconnects."
    }

    /// The countdown line while an automatic score refresh is scheduled.
    public static func retryMessage(seconds: Int) -> String {
        "No reply from the Watch. Trying again in \(max(seconds, 1))…"
    }

    /// Shown when a send fails. A failed send is ambiguous, because the Watch may
    /// still have applied it, so this asks the user to check rather than retry
    /// blindly. Live commands are never retried automatically.
    public static let commandFailureMessage =
        "Not confirmed by the Watch. Check the score before retrying."
}

/// When the phone asks the Watch for the live score again after a read-only
/// refresh fails (no reply, a timeout, or a reply without a state).
///
/// Only refreshes retry. Score commands and prompt answers never do: a failed
/// send is ambiguous, so replaying it could score a point twice. The budget is
/// bounded so a Watch that stays reachable but never answers (for example an
/// older build) leaves the Refresh button rather than polling forever. Every
/// fresh request — the scoreboard opening, Refresh, the app returning to the
/// foreground, or the Watch becoming reachable — starts a new budget.
public enum LiveRefreshRetry {
    /// Seconds to wait before each automatic retry, in order.
    public static let delays: [Int] = [3, 5, 10, 15, 30]

    /// The wait before the next retry after `failures` consecutive failed
    /// refreshes (1 = the first failure), or nil once the budget is spent.
    public static func delay(afterFailures failures: Int) -> Int? {
        guard failures >= 1, failures <= delays.count else { return nil }
        return delays[failures - 1]
    }
}
