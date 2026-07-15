// MatchMergePolicy.swift — merge / dedupe rules for phone-side history.
import Foundation

/// Applies the watch-as-source-of-truth merge rules when a record arrives on
/// the phone. Operates purely on value types; no I/O.
public enum MatchMergePolicy {

    /// Merge `incoming` into `existing` and return the record that should be
    /// persisted.
    ///
    /// Rules (in priority order):
    /// 1. If no existing record with the same id → insert (return `incoming`).
    /// 2. If incoming is completed and existing is in-progress → replace.
    /// 3. If incoming is in-progress and existing is completed → keep existing
    ///    (a late-arriving checkpoint must never downgrade a completed match).
    /// 4. If both completed → keep the one with the later `endTime`.
    /// 5. If both in-progress → always accept the incoming record (the watch
    ///    is source of truth; always accepting preserves undo checkpoints that
    ///    have fewer points than the prior state).
    public static func resolve(incoming: MatchRecord, existing: MatchRecord?) -> MatchRecord {
        guard let existing else { return incoming }

        // Case 2: in-progress → completed transition
        if incoming.iWon != nil && existing.iWon == nil {
            return incoming
        }

        // Case 3: completed → in-progress (ignore; completed is final)
        if incoming.iWon == nil && existing.iWon != nil {
            return existing
        }

        // Case 4: both completed — keep newer endTime
        if incoming.iWon != nil && existing.iWon != nil {
            let incomingEnd = incoming.endTime ?? incoming.startTime
            let existingEnd = existing.endTime ?? existing.startTime
            return incomingEnd >= existingEnd ? incoming : existing
        }

        // Case 5: both in-progress — the watch is source of truth for an active
        // match and sends checkpoints via sendMessage (in-order). Always accept
        // the incoming record. Using stats.count as a proxy for "newer" broke
        // undos: an undo checkpoint has fewer stats than the prior one, causing
        // the phone to wrongly discard the reverted state.
        return incoming
    }

    /// Merge `incoming` records into `current` history, applying `resolve` for
    /// each and returning the deduplicated, newest-first sorted result.
    /// Records whose IDs appear in `tombstones` are skipped.
    public static func merge(
        incoming: [MatchRecord],
        into current: [MatchRecord],
        tombstones: Set<UUID> = []
    ) -> [MatchRecord] {
        var byID: [UUID: MatchRecord] = Dictionary(
            uniqueKeysWithValues: current.map { ($0.id, $0) }
        )

        for record in incoming {
            guard !tombstones.contains(record.id) else { continue }
            let resolved = resolve(incoming: record, existing: byID[record.id])
            byID[record.id] = resolved.fillingMissingHealthData(from: record)
        }

        // Stable id tiebreak so equal start times never reorder the list
        // between merges (mirrors `WatchMirror.sortedByRecency`).
        return byID.values
            .sorted {
                $0.startTime != $1.startTime
                    ? $0.startTime > $1.startTime
                    : $0.id.uuidString < $1.id.uuidString
            }
    }
}
