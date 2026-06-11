// WatchMirror.swift — phone-side mirror of the watch's current match set.
//
// The iPhone keeps every match in its durable archive (PhoneStatsStore), but a
// match the user deletes from the phone is discarded there (only a tombstone
// remains). To still show matches that live on the watch — including ones the
// user removed from the phone — the iPhone keeps a small, device-local *mirror*
// of the watch's records (≤ StatsStore.historyCap). This file holds the pure
// rules that keep that mirror in step with what the watch reports; the file I/O
// lives in the app target.
//
// Pure Foundation so it stays unit-testable in the package with no platform deps.
import Foundation

/// Pure maintenance rules for the phone's mirror of the watch's match records.
public enum WatchMirror {

    /// Fold freshly received records into the mirror.
    ///
    /// - `existing`:  the current mirror.
    /// - `incoming`:  records just received from the watch (a single checkpoint or
    ///   a full-history push).
    /// - `manifest`:  the watch's most recently reported set of held ids.
    ///
    /// Rules:
    /// 1. Only **completed** records are mirrored. In-progress checkpoints arrive
    ///    per point and are shown via the live-match path from the archive, never
    ///    from the mirror, so they are ignored here.
    /// 2. Each incoming record is upserted by id (a newer body replaces an older).
    /// 3. The result is pruned to the records the watch still holds — but an id we
    ///    just received in `incoming` is always retained even when it is missing
    ///    from `manifest`. The watch sends the manifest as a *separate* message
    ///    from the record, so `manifest` is frequently stale at the instant a
    ///    record lands; a record that just arrived over the wire is on the watch
    ///    by definition. This makes the merge independent of which message arrives
    ///    first.
    public static func merged(
        existing: [MatchRecord],
        incoming: [MatchRecord],
        manifest: Set<UUID>
    ) -> [MatchRecord] {
        let completed = incoming.filter { !$0.isInProgress }
        // `uniquingKeysWith:` rather than `uniqueKeysWithValues:` so a corrupted
        // cache that somehow holds a duplicate id can't trap at launch — keep one.
        var byID: [UUID: MatchRecord] = Dictionary(
            existing.map { ($0.id, $0) },
            uniquingKeysWith: { _, new in new }
        )
        for record in completed {
            byID[record.id] = record
        }
        let keep = manifest.union(completed.map(\.id))
        return sortedByRecency(byID.values.filter { keep.contains($0.id) })
    }

    /// Drop mirror records the watch no longer holds. Used when only a manifest
    /// arrives (e.g. after a watch-side delete) with no record bodies to fold in.
    public static func pruned(_ existing: [MatchRecord], manifest: Set<UUID>) -> [MatchRecord] {
        sortedByRecency(existing.filter { manifest.contains($0.id) })
    }

    /// Newest first, with a stable id tiebreak so equal start times never reorder
    /// the list between renders (avoids spurious SwiftUI row animations).
    private static func sortedByRecency(_ records: [MatchRecord]) -> [MatchRecord] {
        records.sorted {
            $0.startTime != $1.startTime
                ? $0.startTime > $1.startTime
                : $0.id.uuidString < $1.id.uuidString
        }
    }
}
