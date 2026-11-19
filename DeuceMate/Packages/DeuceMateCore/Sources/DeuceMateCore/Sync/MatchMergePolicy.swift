// MatchMergePolicy.swift — merge / dedupe rules for phone-side history.
import Foundation

/// Applies the watch-as-source-of-truth merge rules when a record arrives on
/// the phone. Operates purely on value types; no I/O.
public enum MatchMergePolicy {

    /// Merge `incoming` into `existing` and return the record that should be
    /// persisted.
    ///
    /// The **body** is chosen by these rules (in priority order):
    /// 1. If no existing record with the same id → insert (return `incoming`).
    /// 2. If incoming is completed and existing is in-progress → replace.
    /// 3. If incoming is in-progress and existing is completed → keep existing
    ///    (a late-arriving checkpoint must never downgrade a completed match).
    /// 4. If both completed → keep the one with the later `endTime`.
    /// 5. If both are in progress, the higher Watch checkpoint revision wins, including undo.
    ///    Two legacy records retain arrival ordering.
    ///
    /// **Tags** then merge by their own clock on every path
    /// (`MatchTags.merged`), whichever body won. Without this, case 4's `>=`
    /// let the watch's untagged copy of a finished match (same `endTime`)
    /// silently wipe the phone's tags on the next history push
    /// (MATCH_TAGS_PLAN.md §3).
    ///
    /// **MatchTypeRevision** also merges by its own clock on every path.
    /// Tags merge FIRST, then `mergingMatchTypeRevision` runs SECOND so if a
    /// completed match was converted to `.singles`, any merged doubles
    /// partner/2nd opponent from an offline peer is deterministically normalized.
    /// This is the single site the phone ← watch sync, the manual-archive `.merge`
    /// import and the watch's `.singleMatch` handler all go through.
    public static func resolve(incoming: MatchRecord, existing: MatchRecord?) -> MatchRecord {
        guard let existing else { return incoming.mergingMatchTypeRevision(incoming.matchTypeRevision) }
        var winner = resolveBody(incoming: incoming, existing: existing)
        winner = winner.mergingResumeEvents(existing.resumeEvents + incoming.resumeEvents)
        winner.tags = MatchTags.merged(existing.tags, incoming.tags)
        winner = winner.mergingMatchTypeRevision(
            MatchTypeRevision.merged(existing.matchTypeRevision, incoming.matchTypeRevision)
        )
        return winner
    }

    private static func resolveBody(incoming: MatchRecord, existing: MatchRecord) -> MatchRecord {
        // Completion is represented by an end time or a winner. A completed
        // draw intentionally has no winner, so `iWon` alone is insufficient.
        let incomingIsCompleted = !incoming.isInProgress
        let existingIsCompleted = !existing.isInProgress

        // Case 2: in-progress → completed transition
        if incomingIsCompleted && !existingIsCompleted {
            return incoming
        }

        // Case 3: completed → in-progress (ignore; completed is final)
        if !incomingIsCompleted && existingIsCompleted {
            return existing
        }

        // Case 4: both completed — keep newer endTime
        if incomingIsCompleted && existingIsCompleted {
            let incomingEnd = incoming.endTime ?? incoming.startTime
            let existingEnd = existing.endTime ?? existing.startTime
            return incomingEnd >= existingEnd ? incoming : existing
        }

        if incoming.checkpointRevision != existing.checkpointRevision {
            return incoming.checkpointRevision > existing.checkpointRevision ? incoming : existing
        }
        guard existing.checkpointRevision > 0 else { return incoming }

        // A refresh can sample more elapsed time or activity at the same score.
        // Keep the already accepted score, including on a conflicting duplicate.
        var refreshed = existing.fillingMissingHealthData(from: incoming)
        refreshed.matchElapsedSeconds = max(existing.matchElapsedSeconds, incoming.matchElapsedSeconds)
        refreshed.setElapsedSeconds.merge(incoming.setElapsedSeconds, uniquingKeysWith: max)
        if let steps = incoming.totalSteps { refreshed.totalSteps = max(existing.totalSteps ?? steps, steps) }
        if let distance = incoming.totalDistanceMeters { refreshed.totalDistanceMeters = max(existing.totalDistanceMeters ?? distance, distance) }
        if let calories = incoming.totalCaloriesKcal { refreshed.totalCaloriesKcal = max(existing.totalCaloriesKcal ?? calories, calories) }
        return refreshed
    }

    /// Merge `incoming` records into `current` history, applying `resolve` for
    /// each and returning the deduplicated, newest-first sorted result.
    /// Records whose IDs appear in `tombstones` are skipped. Every record an
    /// incoming copy touched is then scrubbed of `forgottenPlayers`
    /// (MATCH_TAGS_PLAN.md §6.2) regardless of its timestamp; a scrub that
    /// changes tags stamps a fresh revision (at or after `now`) so it
    /// supersedes the stale copy everywhere and §6.1 reconciliation sends it
    /// back to the watch.
    public static func merge(
        incoming: [MatchRecord],
        into current: [MatchRecord],
        tombstones: Set<UUID> = [],
        forgottenPlayers: ForgottenPlayerLedger = ForgottenPlayerLedger(),
        now: Date = Date()
    ) -> [MatchRecord] {
        var byID: [UUID: MatchRecord] = Dictionary(
            uniqueKeysWithValues: current.map { ($0.id, $0) }
        )

        for record in incoming {
            guard !tombstones.contains(record.id) else { continue }
            let resolved = resolve(incoming: record, existing: byID[record.id])
            byID[record.id] = forgottenPlayers.scrubbed(
                resolved.fillingMissingHealthData(from: record),
                now: now
            )
        }

        // Stable id tiebreak so equal start times never reorder the list
        // between merges (mirrors `WatchMirror.sortedByRecency`).
        return byID.values
            .sorted(by: MatchChronology.newestFirst)
    }
}
