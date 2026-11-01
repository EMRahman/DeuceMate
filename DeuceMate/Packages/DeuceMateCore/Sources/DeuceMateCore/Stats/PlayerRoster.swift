// PlayerRoster.swift — the "selectable later" player list, head-to-head
// records and roster management, all DERIVED from the match archive.
//
// There is deliberately no separate roster database: the archive already has
// local + iCloud + manual-archive + tombstone handling, and a second store
// would need all four plus its own sync. A player is remembered while at least
// one match carries them; the forgotten-ID ledger (ForgottenPlayerLedger)
// handles deletion intent. See MATCH_TAGS_PLAN.md §5 and §7.1.
import Foundation

// MARK: - Results

/// The recorder's result in one match. Only completed matches have one — an
/// in-progress record never infers a win or loss.
public enum MatchResult: String, Equatable, Sendable {
    case win, loss, draw

    /// `nil` while the match is in progress. A completed record with no winner
    /// (`iWon == nil`) is a draw.
    public init?(record: MatchRecord) {
        guard !record.isInProgress else { return nil }
        switch record.iWon {
        case true?:  self = .win
        case false?: self = .loss
        case nil:    self = .draw
        }
    }

    /// "W" / "L" / "D" for compact form strings ("last 3: W W L").
    public var shortLabel: String {
        switch self {
        case .win:  return "W"
        case .loss: return "L"
        case .draw: return "D"
        }
    }
}

// MARK: - Matchup identity

/// Who a match was against, as an identity two matches can share. Singles:
/// exactly one tagged opponent. Doubles: both opponents as an UNORDERED pair
/// plus the same partner — a different partner is a different team, and a
/// partner appearance is never counted as opposition.
public struct Matchup: Hashable, Sendable {
    public let matchType: MatchType
    public let opponentIDs: Set<UUID>
    /// Always `nil` in singles.
    public let partnerID: UUID?

    public init(matchType: MatchType, opponentIDs: Set<UUID>, partnerID: UUID?) {
        self.matchType = matchType
        self.opponentIDs = opponentIDs
        self.partnerID = matchType == .singles ? nil : partnerID
    }

    /// The record's complete identity, or `nil` when it is incomplete
    /// (untagged, singles without exactly one opponent, doubles without two
    /// opponents and a partner). An incomplete identity never claims a rematch.
    public init?(record: MatchRecord) {
        guard let tags = record.tags else { return nil }
        let opponents = Set(tags.opponents.map(\.id))
        switch record.matchType {
        case .singles:
            guard opponents.count == 1 else { return nil }
            self.init(matchType: .singles, opponentIDs: opponents, partnerID: nil)
        case .doubles:
            guard opponents.count == 2, let partner = tags.partner,
                  !opponents.contains(partner.id) else { return nil }
            self.init(matchType: .doubles, opponentIDs: opponents, partnerID: partner.id)
        }
    }
}

// MARK: - Roster

/// One selectable player, derived from every match that carries their id.
public struct RosterEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// From the most recently updated tag revision that carries this id.
    public let name: String
    public let age: Int?
    public let sexRaw: String?
    public var sex: PlayerSex? { sexRaw.flatMap(PlayerSex.init(rawValue:)) }
    public var taggedPlayer: TaggedPlayer { TaggedPlayer(id: id, name: name, age: age, sexRaw: sexRaw) }
    /// Distinct matches carrying this id in any role (opponent or partner).
    public let matchCount: Int
    /// Start time of the most recent such match.
    public let lastPlayed: Date

    public init(id: UUID, name: String, matchCount: Int, lastPlayed: Date, age: Int? = nil, sexRaw: String? = nil) {
        self.id = id
        self.name = name
        self.age = TaggedPlayer.sanitizedAge(age)
        self.sexRaw = TaggedPlayer.sanitizedSexRaw(sexRaw)
        self.matchCount = matchCount
        self.lastPlayed = lastPlayed
    }
}

/// Result of a roster-wide edit: the full record list with the changed records
/// re-stamped, plus which matches changed (the phone pushes a
/// `matchTagsUpdate` for each one the watch holds — §6.1 also catches any it
/// misses).
public struct RosterMutation: Equatable, Sendable {
    public let records: [MatchRecord]
    public let affectedMatchIDs: Set<UUID>

    public init(records: [MatchRecord], affectedMatchIDs: Set<UUID>) {
        self.records = records
        self.affectedMatchIDs = affectedMatchIDs
    }
}

public enum PlayerRoster {

    /// Every distinct tagged player, most recently played first (then name,
    /// then id, for a stable order). Players in `forgotten` are excluded even
    /// if a stale record still carries them.
    public static func entries(
        from records: [MatchRecord],
        forgotten: ForgottenPlayerLedger = ForgottenPlayerLedger()
    ) -> [RosterEntry] {
        struct Accumulator {
            var player: TaggedPlayer
            var nameRevision: MatchTags
            var matchIDs: Set<UUID>
            var lastPlayed: Date
        }
        var byID: [UUID: Accumulator] = [:]
        for record in records {
            guard let tags = record.tags else { continue }
            for player in tags.allPlayers where !forgotten.contains(player.id) && !player.name.isEmpty {
                if var acc = byID[player.id] {
                    acc.matchIDs.insert(record.id)
                    acc.lastPlayed = max(acc.lastPlayed, record.startTime)
                    if tags.supersedes(acc.nameRevision) {
                        acc.player = player
                        acc.nameRevision = tags
                    }
                    byID[player.id] = acc
                } else {
                    byID[player.id] = Accumulator(
                        player: player, nameRevision: tags,
                        matchIDs: [record.id], lastPlayed: record.startTime
                    )
                }
            }
        }
        return byID
            .map { RosterEntry(id: $0.key, name: $0.value.player.name,
                               matchCount: $0.value.matchIDs.count, lastPlayed: $0.value.lastPlayed,
                               age: $0.value.player.age, sexRaw: $0.value.player.sexRaw) }
            .sorted { a, b in
                if a.lastPlayed != b.lastPlayed { return a.lastPlayed > b.lastPlayed }
                let byName = a.name.localizedCaseInsensitiveCompare(b.name)
                if byName != .orderedSame { return byName == .orderedAscending }
                return a.id.uuidString < b.id.uuidString
            }
    }

    /// Picker suggestions for `query`. An empty query returns every entry
    /// (recent first). Otherwise matching is case- and diacritic-insensitive
    /// on the sanitized query: exact name matches first (so typing an existing
    /// "alex" offers that Alex before "Add new" can mint a duplicate), then
    /// names starting with the query, then names with a word starting with it,
    /// then names containing it — each group keeping `entries`' recency order.
    public static func suggestions(_ query: String, in entries: [RosterEntry]) -> [RosterEntry] {
        let needle = fold(MatchTags.sanitizedName(query))
        guard !needle.isEmpty else { return entries }
        var exact: [RosterEntry] = [], prefix: [RosterEntry] = [], word: [RosterEntry] = [], contains: [RosterEntry] = []
        for entry in entries {
            let name = fold(entry.name)
            if name == needle {
                exact.append(entry)
            } else if name.hasPrefix(needle) {
                prefix.append(entry)
            } else if name.split(separator: " ").contains(where: { $0.hasPrefix(needle) }) {
                word.append(entry)
            } else if name.contains(needle) {
                contains.append(entry)
            }
        }
        return exact + prefix + word + contains
    }

    /// The entry whose name equals `name` ignoring case/diacritics/whitespace,
    /// if any — the "this would duplicate an existing player" check.
    public static func existingEntry(named name: String, in entries: [RosterEntry]) -> RosterEntry? {
        let needle = fold(MatchTags.sanitizedName(name))
        guard !needle.isEmpty else { return nil }
        return entries.first { fold($0.name) == needle }
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    // MARK: Roster management (Settings → Players)

    /// Renames `playerID` in every record carrying it (any role), re-stamping
    /// each changed record's tags so the rename supersedes older copies.
    /// An empty sanitized name is rejected (no change).
    public static func renaming(
        _ playerID: UUID,
        to newName: String,
        in records: [MatchRecord],
        now: Date = Date()
    ) -> RosterMutation {
        let name = MatchTags.sanitizedName(newName)
        guard !name.isEmpty else { return RosterMutation(records: records, affectedMatchIDs: []) }
        return rewriting(records, now: now) { tags in
            if tags.partner?.id == playerID { tags.partner?.name = name }
            for i in tags.opponents.indices where tags.opponents[i].id == playerID {
                tags.opponents[i].name = name
            }
        }
    }

    /// Updates the profile in every role; nil deliberately clears a field.
    public static func updatingDetails(
        _ playerID: UUID, age: Int?, sexRaw: String?, in records: [MatchRecord], now: Date = Date()
    ) -> RosterMutation {
        guard let current = entries(from: records).first(where: { $0.id == playerID }) else {
            return RosterMutation(records: records, affectedMatchIDs: [])
        }
        return rewriting(records, now: now) { tags in
            if tags.partner?.id == playerID {
                tags.partner?.name = current.name
                tags.partner?.age = age
                tags.partner?.sexRaw = sexRaw
            }
            for i in tags.opponents.indices where tags.opponents[i].id == playerID {
                tags.opponents[i].name = current.name
                tags.opponents[i].age = age
                tags.opponents[i].sexRaw = sexRaw
            }
        }
    }

    /// Merges duplicate `duplicateID` into `keptID`: every occurrence is
    /// rewritten to the kept id and the kept player's current roster name. A
    /// match that ends up naming the kept player twice is de-duplicated by
    /// `MatchTags.sanitized()`. Merging an id into itself is a no-op.
    public static func merging(
        _ duplicateID: UUID,
        into keptID: UUID,
        in records: [MatchRecord],
        now: Date = Date()
    ) -> RosterMutation {
        guard duplicateID != keptID,
              let kept = entries(from: records).first(where: { $0.id == keptID }) else {
            return RosterMutation(records: records, affectedMatchIDs: [])
        }
        let replacement = kept.taggedPlayer
        return rewriting(records, now: now) { tags in
            guard tags.playerIDs.contains(duplicateID) else { return }
            if tags.partner?.id == duplicateID || tags.partner?.id == keptID { tags.partner = replacement }
            for i in tags.opponents.indices where tags.opponents[i].id == duplicateID || tags.opponents[i].id == keptID {
                tags.opponents[i] = replacement
            }
        }
    }

    /// Removes `playerID` from every role in every record ("Forget player").
    /// The caller must ALSO add the id to its `ForgottenPlayerLedger` in the
    /// same serialized mutation, so stale copies cannot bring them back.
    public static func forgetting(
        _ playerID: UUID,
        in records: [MatchRecord],
        now: Date = Date()
    ) -> RosterMutation {
        rewriting(records, now: now) { tags in
            if tags.partner?.id == playerID { tags.partner = nil }
            tags.opponents.removeAll { $0.id == playerID }
        }
    }

    /// Applies `edit` to every tagged record; records whose sanitized tags
    /// changed get a fresh revision stamped after their previous one.
    private static func rewriting(
        _ records: [MatchRecord],
        now: Date,
        edit: (inout MatchTags) -> Void
    ) -> RosterMutation {
        var affected: Set<UUID> = []
        let updated = records.map { record -> MatchRecord in
            guard let tags = record.tags else { return record }
            var edited = tags
            edit(&edited)
            edited = edited.sanitized()
            guard edited != tags else { return record }
            var copy = record
            copy.tags = edited.revised(after: tags, now: now)
            affected.insert(record.id)
            return copy
        }
        return RosterMutation(records: updated, affectedMatchIDs: affected)
    }
}

// MARK: - Head-to-head

/// Completed-only record against an opponent or team.
public struct HeadToHeadRecord: Equatable, Sendable {
    public let wins: Int
    public let losses: Int
    public let draws: Int
    /// Results newest first (start time, then id) — "last 3: W W L".
    public let recentResults: [MatchResult]
    public let lastPlayed: Date?

    public var played: Int { wins + losses + draws }

    public init(wins: Int, losses: Int, draws: Int, recentResults: [MatchResult], lastPlayed: Date?) {
        self.wins = wins
        self.losses = losses
        self.draws = draws
        self.recentResults = recentResults
        self.lastPlayed = lastPlayed
    }

    public static let empty = HeadToHeadRecord(wins: 0, losses: 0, draws: 0, recentResults: [], lastPlayed: nil)
}

public enum HeadToHead {

    /// Wins / losses / draws vs `playerID` **as an opponent** across completed
    /// matches of `matchType` (singles and doubles are never pooled), excluding
    /// the match `excluding`. Partner appearances never count as opposition.
    public static func record(
        vs playerID: UUID,
        in records: [MatchRecord],
        excluding: UUID?,
        matchType: MatchType = .singles
    ) -> HeadToHeadRecord {
        tally(records.filter { record in
            record.id != excluding
                && record.matchType == matchType
                && (record.tags?.opponents.contains { $0.id == playerID } ?? false)
        })
    }

    /// Completed record against exactly this `matchup` (singles: the same
    /// opponent; doubles: the same unordered opponent pair WITH the same
    /// partner) — the same identity rule as the previous-match baseline, so
    /// the on-screen summary and the AI prompt agree.
    public static func record(
        for matchup: Matchup,
        in records: [MatchRecord],
        excluding: UUID?
    ) -> HeadToHeadRecord {
        tally(records.filter { $0.id != excluding && Matchup(record: $0) == matchup })
    }

    /// The head-to-head for `current`'s own matchup, or `nil` when its
    /// identity is incomplete. `current` itself is always excluded.
    public static func record(for current: MatchRecord, in records: [MatchRecord]) -> HeadToHeadRecord? {
        guard let matchup = Matchup(record: current) else { return nil }
        return record(for: matchup, in: records, excluding: current.id)
    }

    private static func tally(_ candidates: [MatchRecord]) -> HeadToHeadRecord {
        let completed = candidates
            .compactMap { record in MatchResult(record: record).map { (record, $0) } }
            .sorted { a, b in
                a.0.startTime != b.0.startTime
                    ? a.0.startTime > b.0.startTime
                    : a.0.id.uuidString > b.0.id.uuidString
            }
        let results = completed.map(\.1)
        return HeadToHeadRecord(
            wins: results.filter { $0 == .win }.count,
            losses: results.filter { $0 == .loss }.count,
            draws: results.filter { $0 == .draw }.count,
            recentResults: results,
            lastPlayed: completed.first?.0.startTime
        )
    }
}
