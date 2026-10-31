// ForgottenPlayerLedger.swift — persistent deletion intent for "Forget player".
//
// A per-match clear only protects records the phone still holds. A stale
// watch copy, an old iCloud backup or an old manual archive can carry a
// forgotten player on a match the phone no longer has — or an older tag
// revision on one it does. The ledger is the minimal set of forgotten player
// UUIDs (never names) that every inbound path scrubs against, regardless of
// timestamps. See MATCH_TAGS_PLAN.md §6.2.
//
// Pure value type; the iPhone persists it next to the archive tombstones,
// backs it up with them, and unions it on every merge, replace import and
// initial restore. Old files lacking a ledger never erase the current one.
import Foundation

public struct ForgottenPlayerLedger: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    /// Format version of this value as persisted. Additive fields decode with
    /// defaults; a newer version is still read for the ids it shares.
    public var schemaVersion: Int
    /// Forgotten player ids. No names are ever stored.
    public private(set) var playerIDs: Set<UUID>

    public init(playerIDs: Set<UUID> = []) {
        self.schemaVersion = Self.currentSchemaVersion
        self.playerIDs = playerIDs
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, playerIDs }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = (try? c.decodeIfPresent(Int.self, forKey: .schemaVersion)) ?? 1
        let raw = (try? c.decodeIfPresent([String].self, forKey: .playerIDs)) ?? []
        playerIDs = Set(raw.compactMap(UUID.init(uuidString:)))
    }

    /// Sorted id strings, so the persisted/backed-up bytes are deterministic.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(playerIDs.map(\.uuidString).sorted(), forKey: .playerIDs)
    }

    public var isEmpty: Bool { playerIDs.isEmpty }

    public func contains(_ playerID: UUID) -> Bool { playerIDs.contains(playerID) }

    /// This ledger plus `playerID`.
    public func forgetting(_ playerID: UUID) -> ForgottenPlayerLedger {
        var copy = self
        copy.playerIDs.insert(playerID)
        return copy
    }

    /// Union with another ledger. `nil` (an old backup/archive without a
    /// ledger) leaves this one unchanged — it can never erase deletion intent.
    public func union(_ other: ForgottenPlayerLedger?) -> ForgottenPlayerLedger {
        guard let other else { return self }
        var copy = self
        copy.playerIDs.formUnion(other.playerIDs)
        copy.schemaVersion = max(schemaVersion, other.schemaVersion)
        return copy
    }

    // MARK: - Scrubbing

    /// `tags` with every forgotten player removed from every role. Unchanged
    /// (same revision) when nothing was forgotten. When a player IS removed,
    /// the result is a fresh revision stamped after `tags` (and at or after
    /// `now`), so it supersedes the stale copy on every peer and is sent back
    /// to the watch by §6.1 reconciliation — including when the result is an
    /// empty clear.
    public func scrubbed(_ tags: MatchTags, now: Date, revisionID: UUID = UUID()) -> MatchTags {
        guard !playerIDs.isEmpty, !tags.playerIDs.isDisjoint(with: playerIDs) else { return tags }
        var cleaned = tags
        cleaned.opponents.removeAll { playerIDs.contains($0.id) }
        if let partner = cleaned.partner, playerIDs.contains(partner.id) { cleaned.partner = nil }
        return cleaned.revised(after: tags, now: now, revisionID: revisionID)
    }

    /// `record` with its tags scrubbed (body untouched).
    public func scrubbed(_ record: MatchRecord, now: Date) -> MatchRecord {
        guard let tags = record.tags else { return record }
        let cleaned = scrubbed(tags, now: now)
        guard cleaned != tags else { return record }
        var copy = record
        copy.tags = cleaned
        return copy
    }

    public func scrubbed(_ records: [MatchRecord], now: Date) -> [MatchRecord] {
        guard !playerIDs.isEmpty else { return records }
        return records.map { scrubbed($0, now: now) }
    }

    /// Ids of `records` whose tags mention a forgotten player — i.e. what a
    /// scrub would change.
    public func affectedMatchIDs(in records: [MatchRecord]) -> Set<UUID> {
        Set(records.compactMap { record in
            guard let ids = record.tags?.playerIDs, !ids.isDisjoint(with: playerIDs) else { return nil }
            return record.id
        })
    }
}
