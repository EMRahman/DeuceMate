// MatchStorageLocation.swift — derives where a match is stored across devices.
//
// The phone keeps every match it has ever received; the watch keeps only its
// most recent matches (capped by `StatsStore.historyCap`). Correlating "the same match" across the
// two stores is done purely by `MatchRecord.id`. The watch reports the set of IDs
// it currently holds via `MatchSyncKey.watchManifest`; this file turns that set
// plus the phone's own membership into a displayable location.
//
// Pure Foundation so it stays unit-testable in the package with no platform deps.
import Foundation

/// Where a given match currently lives across the paired devices.
public enum MatchStorageLocation: Equatable {
    /// Stored on both the Apple Watch and the iPhone.
    case both
    /// Stored only on the iPhone (e.g. the watch trimmed it past its match cap).
    case phoneOnly
    /// Stored only on the Apple Watch (not yet synced down to the phone).
    case watchOnly
}

/// Pure derivation of storage location from set membership.
public enum MatchStorageResolver {
    /// Resolves a single match's location. `onPhone` is whether the phone's store
    /// holds the id; `watchIDs` is the watch's reported manifest. A match that is
    /// on neither falls back to `.phoneOnly` (it cannot be shown from a store that
    /// doesn't contain it, so this branch is defensive only).
    public static func location(
        matchID: UUID,
        onPhone: Bool,
        watchIDs: Set<UUID>
    ) -> MatchStorageLocation {
        let onWatch = watchIDs.contains(matchID)
        switch (onPhone, onWatch) {
        case (true, true):   return .both
        case (true, false):  return .phoneOnly
        case (false, true):  return .watchOnly
        case (false, false): return .phoneOnly
        }
    }

    /// IDs the watch holds that the phone does not — the matches that need pulling
    /// down. These have no record on the phone, so callers can only surface them as
    /// a count plus a "sync now" action, not as full rows.
    public static func watchOnlyIDs(
        phoneIDs: Set<UUID>,
        watchIDs: Set<UUID>
    ) -> Set<UUID> {
        watchIDs.subtracting(phoneIDs)
    }
}
