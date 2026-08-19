// HealthAccessSettlePolicy.swift — when to re-read the HealthKit share status
// after the authorization sheet closes.
//
// The problem this solves: `HKHealthStore.requestAuthorization`'s completion
// fires as the permission sheet dismisses, but the share status it writes is
// not always readable by the time it does. A single `authorizationStatus` read
// in that completion can still answer `.notDetermined` even though the user has
// just granted access — and nothing else re-reads it:
//
//   • the scene never leaves `.active` for a system sheet in the same process,
//     so the `scenePhase` refresh in `DeuceMateApp` does not fire;
//   • the start screen's `onAppear` already ran, before the sheet was answered.
//
// So the strip keeps showing Health as a yellow "Ask" until the next launch,
// which is exactly what a user reported after a fresh install. Re-reading on a
// short, bounded schedule lets the value settle on its own.
//
// The schedule lives here, not in `WorkoutManager`, so it is unit-testable with
// no HealthKit and no simulator — the same split as `MatchTrackingStatus`, which
// resolves the strip from a `HealthAccess` the watch app maps for it.
import Foundation

/// Decides whether to re-read HealthKit's share status again, and after how
/// long, once the authorization sheet has been answered.
public enum HealthAccessSettlePolicy {
    /// Gaps between re-reads, in seconds. Front-loaded because the value is
    /// usually readable almost immediately; the tail covers a slow write. Total
    /// span is ~2.6s, short enough that a user watching the strip sees it
    /// resolve, bounded so a genuinely undecided permission stops asking.
    public static let retryDelays: [TimeInterval] = [0.3, 0.8, 1.5]

    /// How long to wait before re-read number `attempt`, or `nil` to stop.
    ///
    /// Stops as soon as `access` is anything other than `.notDetermined`: the
    /// other three states are all conclusive answers that will not change on
    /// their own. Also stops once the delays are exhausted, so a user who
    /// dismissed the sheet without answering is not polled indefinitely.
    ///
    /// - Parameters:
    ///   - attempt: zero-based index of the re-read being scheduled.
    ///   - access: the value the most recent read produced.
    public static func nextRetryDelay(attempt: Int, access: HealthAccess) -> TimeInterval? {
        guard access == .notDetermined else { return nil }
        guard attempt >= 0, attempt < retryDelays.count else { return nil }
        return retryDelays[attempt]
    }
}
