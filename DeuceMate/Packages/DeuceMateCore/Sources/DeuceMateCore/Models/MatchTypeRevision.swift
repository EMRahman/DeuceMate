// MatchTypeRevision.swift — post-completion match-type conversion (Doubles ↔ Singles).
//
// Allows a completed match whose type was set incorrectly to be converted
// between singles and doubles while preserving all scores, points, statistics,
// and health metrics.
//
// Like MatchTags, MatchTypeRevision carries its own monotonic clock (updatedAt + revisionID)
// and merges independently of the record body across all merge paths so an
// equal-endTime watch history push cannot revert a user-initiated conversion.
import Foundation

// MARK: - MatchTypeRevision

/// Post-completion match-type edit revision (`Doubles ↔ Singles`).
/// `nil` on `MatchRecord` means `matchType` has never been edited post-completion.
public struct MatchTypeRevision: Codable, Equatable, Sendable {
    public var matchType: MatchType
    public var updatedAt: Date
    public var revisionID: UUID

    /// The fixed zero UUID used for a revision that predates `revisionID`.
    public static let legacyRevisionID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    /// The smallest step `revised(to:after:)` advances the clock by when the
    /// device clock has not moved past the previous revision.
    public static let minimumClockStep: TimeInterval = 0.001

    public init(matchType: MatchType, updatedAt: Date, revisionID: UUID = UUID()) {
        self.matchType = matchType
        self.updatedAt = updatedAt
        self.revisionID = revisionID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        matchType = try c.decode(MatchType.self, forKey: .matchType)
        updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? .distantPast
        revisionID = (try? c.decodeIfPresent(UUID.self, forKey: .revisionID)) ?? Self.legacyRevisionID
    }

    // MARK: Merge & ordering

    /// Merges two revisions by revision clock. Strictly commutative:
    /// `merged(a, b) == merged(b, a)`.
    /// - `nil` = never edited post-completion;
    /// - non-nil beats `nil`;
    /// - two non-nil: the one that `supersedes` the other wins.
    public static func merged(_ existing: MatchTypeRevision?, _ incoming: MatchTypeRevision?) -> MatchTypeRevision? {
        switch (existing, incoming) {
        case (nil, nil): return nil
        case (let e?, nil): return e
        case (nil, let i?): return i
        case (let e?, let i?): return i.supersedes(e) ? i : e
        }
    }

    /// Strict total order: compare `updatedAt` (>), then `revisionID.uuidString` (>),
    /// then `matchType.rawValue` (>). Returns `false` when equal.
    public func supersedes(_ other: MatchTypeRevision) -> Bool {
        if updatedAt != other.updatedAt { return updatedAt > other.updatedAt }
        if revisionID != other.revisionID { return revisionID.uuidString > other.revisionID.uuidString }
        return matchType.rawValue > other.matchType.rawValue
    }

    /// `now`, or the smallest step past `previous.updatedAt` when the clock
    /// has not advanced past it.
    public static func nextClock(after previous: MatchTypeRevision?, now: Date) -> Date {
        guard let previous else { return now }
        return max(now, previous.updatedAt.addingTimeInterval(minimumClockStep))
    }

    /// Creates a new revision transitioning to `matchType`, advancing the clock past `previous`.
    public static func revised(
        to matchType: MatchType,
        after previous: MatchTypeRevision?,
        now: Date = Date(),
        revisionID: UUID = UUID()
    ) -> MatchTypeRevision {
        MatchTypeRevision(
            matchType: matchType,
            updatedAt: nextClock(after: previous, now: now),
            revisionID: revisionID
        )
    }
}

// MARK: - MatchRecord extensions

public extension MatchRecord {

    /// Converts this completed record to `newType` (`.singles` ↔ `.doubles`),
    /// advancing the `matchTypeRevision` clock.
    /// In-progress matches or conversions to the same type are returned unchanged.
    func convertingMatchType(
        to newType: MatchType,
        at now: Date = Date(),
        revisionID: UUID = UUID()
    ) -> MatchRecord {
        guard !isInProgress && matchType != newType else { return self }
        let rev = MatchTypeRevision.revised(to: newType, after: matchTypeRevision, now: now, revisionID: revisionID)
        return applyingMatchTypeRevision(rev)
    }

    /// Merges an incoming `matchTypeRevision` with this record's revision, applying
    /// the winning revision if any. In-progress matches are returned unchanged.
    func mergingMatchTypeRevision(_ incoming: MatchTypeRevision?) -> MatchRecord {
        guard !isInProgress else { return self }
        guard let winning = MatchTypeRevision.merged(matchTypeRevision, incoming) else { return self }
        return applyingMatchTypeRevision(winning)
    }

    /// Applies `rev` to this completed record: updates `matchType` and `matchTypeRevision`,
    /// clears resume-only doubles rotation fields, and deterministically normalizes tags
    /// if converted to singles.
    func applyingMatchTypeRevision(_ rev: MatchTypeRevision) -> MatchRecord {
        guard !isInProgress else { return self }
        var copy = self
        copy.matchType = rev.matchType
        copy.matchTypeRevision = rev
        copy.doublesServer = nil
        copy.doublesServiceOrder = []
        copy.doublesServiceIndex = 0
        copy.tiebreakStartDoublesIndex = 0

        // Deterministic singles tag normalization: ONLY when rev.matchType == .singles
        // preserves (updatedAt, revisionID) so a stale doubles snapshot never promotes
        // ahead of newer tag edits made on another peer.
        if rev.matchType == .singles {
            copy.tags = copy.tags?.normalizedForSingles()
        }
        return copy
    }

    /// Convenience target type for UI conversion (`.doubles → .singles` or `.singles → .doubles`).
    /// `nil` for in-progress matches.
    var convertibleTargetMatchType: MatchType? {
        isInProgress ? nil : (matchType == .doubles ? .singles : .doubles)
    }

    /// Players from `tags` that would be dropped if converted to singles (`partner` and any opponents after the first).
    /// Empty if `tags == nil` or nothing would be dropped.
    var playersDroppedConvertingToSingles: [TaggedPlayer] {
        guard let tags else { return [] }
        var dropped: [TaggedPlayer] = []
        if let partner = tags.partner {
            dropped.append(partner)
        }
        if tags.opponents.count > 1 {
            dropped.append(contentsOf: tags.opponents.dropFirst())
        }
        return dropped
    }
}

// MARK: - Wire payload

/// Body of the `MatchSyncKey.matchTypeUpdate` payload: one match's post-completion match-type revision.
/// Bidirectional; applied only to completed records already held by the receiver, merged by the revision clock.
public struct MatchTypeUpdate: Codable, Equatable, Sendable {
    public let matchID: UUID
    public let revision: MatchTypeRevision

    public init(matchID: UUID, revision: MatchTypeRevision) {
        self.matchID = matchID
        self.revision = revision
    }
}

// MARK: - Reconciliation

public extension MatchTypeRevision {

    /// Match type updates the phone should (re)send so the watch eventually converges.
    /// Pure; only considers completed archive records with a non-nil `matchTypeRevision`.
    ///
    /// - `archive`: the phone's canonical records.
    /// - `watchCopies`: record bodies the watch just sent. For any completed copy whose id
    ///   has a phone revision that is missing on the watch or supersedes the watch revision, queue the phone revision.
    /// - `newlyHeld`: match IDs newly reported in the watch manifest. If the archive has a phone revision for the id, queue it.
    ///
    /// Returns one update per match id, sorted by `matchID.uuidString < $1.matchID.uuidString`.
    static func pendingWatchUpdates(
        archive: [MatchRecord],
        watchCopies: [MatchRecord],
        newlyHeld: Set<UUID>
    ) -> [MatchTypeUpdate] {
        let archiveRevisions: [UUID: MatchTypeRevision] = Dictionary(
            archive.filter { !$0.isInProgress }.compactMap { record in
                record.matchTypeRevision.map { (record.id, $0) }
            },
            uniquingKeysWith: { a, b in MatchTypeRevision.merged(a, b) ?? a }
        )
        var pending: [UUID: MatchTypeRevision] = [:]

        for copy in watchCopies where !copy.isInProgress {
            guard let phoneRev = archiveRevisions[copy.id] else { continue }
            if let watchRev = copy.matchTypeRevision, !phoneRev.supersedes(watchRev) { continue }
            pending[copy.id] = phoneRev
        }
        for id in newlyHeld {
            guard let phoneRev = archiveRevisions[id] else { continue }
            pending[id] = phoneRev
        }

        return pending
            .map { MatchTypeUpdate(matchID: $0.key, revision: $0.value) }
            .sorted { $0.matchID.uuidString < $1.matchID.uuidString }
    }
}
