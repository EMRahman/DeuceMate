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

    public init(isWatchReachable: Bool, isInputEnabled: Bool,
                isStateConfirmed: Bool = true, isRequestInFlight: Bool = false,
                blockingReason: String? = nil) {
        self.isWatchReachable = isWatchReachable
        self.isInputEnabled = isInputEnabled
        self.isStateConfirmed = isStateConfirmed
        self.isRequestInFlight = isRequestInFlight
        self.blockingReason = blockingReason
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
        isInputEnabled && isWatchReachable && isStateConfirmed && !isRequestInFlight && blockingReason == nil
    }

    /// Whether to show the swipe directions. They must not be offered when a
    /// swipe would do nothing.
    public var showsSwipeHint: Bool {
        acceptsInput
    }

    /// Whether a swipe that can't be sent should say so: a warning haptic and
    /// a flash of `detail`. Only when iPhone Input is on, so the swipe was a
    /// real scoring attempt; a spectator's stray drag stays silent. The swipe
    /// itself is still never sent.
    public var refusesSwipeWithFeedback: Bool {
        isInputEnabled && !isWatchReachable
    }

    /// Why the score may be stale and, when relevant, how to resume scoring.
    public var detail: String? {
        if isWatchReachable {
            if !isStateConfirmed {
                return isRequestInFlight ? "Getting the current score from the Watch."
                    : "Current score not confirmed. Refresh to reconnect."
            }
            if isRequestInFlight { return "Waiting for the Watch to confirm." }
            return blockingReason
        }
        return isInputEnabled
            ? "Last score shown. Open DeuceMate on the Watch to score here."
            : "Last score shown. Updates resume when the Watch reconnects."
    }

    /// Shown when a send fails. A failed send is ambiguous, because the Watch may
    /// still have applied it, so this asks the user to check rather than retry
    /// blindly. Live commands are never retried automatically.
    public static let commandFailureMessage =
        "Not confirmed by the Watch. Check the score before retrying."
}
