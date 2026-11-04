// LiveScoreboardStatus.swift — What the iPhone live scoreboard may claim and accept.
//
// A pure rule so the badge, the swipe gate, the category panel and the browser
// demo cannot disagree about whether the Watch can currently hear the phone.
// Reachability is the only signal available without a command acknowledgement,
// and it does not prove the displayed score is current, so the unavailable copy
// only ever describes the score as the last one received.
import Foundation

public struct LiveScoreboardStatus: Equatable, Sendable {
    public let isWatchReachable: Bool
    public let isInputEnabled: Bool

    public init(isWatchReachable: Bool, isInputEnabled: Bool) {
        self.isWatchReachable = isWatchReachable
        self.isInputEnabled = isInputEnabled
    }

    /// "Waiting", not "disconnected": an in-range Watch is also unreachable while
    /// DeuceMate isn't active on it, for example wrist-down without a workout.
    public var badgeLabel: String {
        isWatchReachable ? "LIVE" : "WAITING FOR WATCH"
    }

    /// Whether swipes, their previews and haptics, and category actions may run.
    public var acceptsInput: Bool {
        isInputEnabled && isWatchReachable
    }

    /// Whether to show the swipe directions. They must not be offered when a
    /// swipe would do nothing.
    public var showsSwipeHint: Bool {
        acceptsInput
    }

    /// Why the score may be stale and, when relevant, how to resume scoring.
    public var detail: String? {
        guard !isWatchReachable else { return nil }
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
