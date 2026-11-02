// MatchTags.swift — who a match was played against/with and its competition
// type. Phone-edited, watch-displayed metadata that rides on `MatchRecord`
// but merges by its OWN clock, independently of the record body.
//
// See docs/features/MATCH_TAGS_PLAN.md §3, §4 and §6.1. The two invariants
// every caller relies on:
//
// - `tags == nil` means "this copy never heard of tags" (an older build
//   re-encoded it), never "cleared". Clearing is an EMPTY `MatchTags` with a
//   newer `updatedAt`, so it beats an older non-empty copy.
// - Decoding a `MatchTags` never throws for bad field contents. A persisted
//   value an older/newer build cannot understand degrades to a default rather
//   than failing the whole `[MatchRecord]` archive decode (TECHNICAL_DEBT #18).
import Foundation

// MARK: - Player tennis profile

/// Deliberately **not** `Codable`: only `TaggedPlayer.handednessRaw` is
/// persisted so an unknown future case round-trips instead of failing archive
/// decode on an older build. Never rename a raw value (pinned in `MatchTagsTests`).
public enum PlayerHandedness: String, CaseIterable, Sendable, Identifiable {
    case rightHanded
    case leftHanded

    public var id: String { rawValue }

    public var displayLabel: String {
        switch self {
        case .rightHanded: return "Right-handed"
        case .leftHanded:  return "Left-handed"
        }
    }
}

/// Deliberately **not** `Codable`: only `TaggedPlayer.backhandRaw` is persisted.
/// Never rename a raw value (pinned in `MatchTagsTests`).
public enum PlayerBackhand: String, CaseIterable, Sendable, Identifiable {
    case twoHanded
    case oneHanded

    public var id: String { rawValue }

    public var displayLabel: String {
        switch self {
        case .twoHanded: return "Two-handed"
        case .oneHanded: return "One-handed"
        }
    }
}

/// Deliberately **not** `Codable`: only `TaggedPlayer.playStyleRaw` is persisted.
/// Never rename a raw value (pinned in `MatchTagsTests`).
public enum PlayerPlayStyle: String, CaseIterable, Sendable, Identifiable {
    case allCourt
    case aggressiveBaseliner
    case counterpuncher
    case serveAndVolley
    case pusher

    public var id: String { rawValue }

    public var displayLabel: String {
        switch self {
        case .allCourt:            return "All-Court"
        case .aggressiveBaseliner: return "Aggressive Baseliner"
        case .counterpuncher:      return "Counterpuncher"
        case .serveAndVolley:      return "Serve & Volley"
        case .pusher:              return "Pusher"
        }
    }
}

// MARK: - TaggedPlayer

/// One named person attached to a match. The `id` is minted once, when the
/// player is first added, and reused whenever they are picked from the roster,
/// so two different "Alex"es stay separate and a rename can follow one person
/// across every match.
public struct TaggedPlayer: Codable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    /// Sanitized display snapshot (see `MatchTags.sanitizedName(_:)`).
    public var name: String

    public var handednessRaw: String?
    public var backhandRaw: String?
    public var playStyleRaw: String?

    public var handedness: PlayerHandedness? {
        get { handednessRaw.flatMap(PlayerHandedness.init(rawValue:)) }
        set { handednessRaw = newValue?.rawValue }
    }

    public var backhand: PlayerBackhand? {
        get { backhandRaw.flatMap(PlayerBackhand.init(rawValue:)) }
        set { backhandRaw = newValue?.rawValue }
    }

    public var playStyle: PlayerPlayStyle? {
        get { playStyleRaw.flatMap(PlayerPlayStyle.init(rawValue:)) }
        set { playStyleRaw = newValue?.rawValue }
    }

    /// Compact summary of known tennis attributes (e.g.
    /// "Left-handed · One-handed backhand · Serve & Volley"), or `nil`.
    public var profileSummary: String? {
        var parts: [String] = []
        if let handedness { parts.append(handedness.displayLabel) }
        if let backhand { parts.append("\(backhand.displayLabel) backhand") }
        if let playStyle { parts.append(playStyle.displayLabel) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    public static let maxAttributeRawLength = 64

    public init(
        id: UUID = UUID(),
        name: String,
        handednessRaw: String? = nil,
        backhandRaw: String? = nil,
        playStyleRaw: String? = nil
    ) {
        self.id = id
        self.name = name
        self.handednessRaw = Self.sanitizedAttributeRaw(handednessRaw)
        self.backhandRaw = Self.sanitizedAttributeRaw(backhandRaw)
        self.playStyleRaw = Self.sanitizedAttributeRaw(playStyleRaw)
    }

    static func sanitizedAttributeRaw(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              !raw.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else { return nil }
        return String(raw.prefix(maxAttributeRawLength))
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        handednessRaw = Self.sanitizedAttributeRaw(try? c.decodeIfPresent(String.self, forKey: .handednessRaw))
        backhandRaw = Self.sanitizedAttributeRaw(try? c.decodeIfPresent(String.self, forKey: .backhandRaw))
        playStyleRaw = Self.sanitizedAttributeRaw(try? c.decodeIfPresent(String.self, forKey: .playStyleRaw))
    }
}

// MARK: - CompetitionType

/// Friendly / League / Tournament / Practice — shown in the UI as
/// "Competition Type". Deliberately NOT `MatchType`, which already means
/// singles/doubles.
///
/// Deliberately **not** `Codable`: nothing persists this enum, only its raw
/// string (`MatchTags.competitionTypeRaw`). A case added by a future build
/// therefore decodes on this one as `competitionType == nil` and re-encodes
/// unchanged, instead of failing the whole archive. The raw values are still
/// persisted identifiers — never rename one (pinned in `MatchTagsTests`).
public enum CompetitionType: String, CaseIterable, Sendable, Identifiable {
    case friendly, league, tournament, practice

    public var id: String { rawValue }

    public var displayLabel: String {
        switch self {
        case .friendly:   return "Friendly"
        case .league:     return "League"
        case .tournament: return "Tournament"
        case .practice:   return "Practice"
        }
    }
}

// MARK: - MatchTags

/// Optional match details: opponent(s), partner (doubles), competition type.
public struct MatchTags: Codable, Equatable, Sendable {
    /// 0…1 in singles, 0…2 in doubles. The singles/doubles rule is the
    /// editor's job; decoding never drops an opponent an editor wrote.
    public var opponents: [TaggedPlayer]
    /// Doubles only (enforced by the editor, not by decoding).
    public var partner: TaggedPlayer?
    /// Raw storage so an unknown future case round-trips instead of failing
    /// the whole archive decode on an older build (TECHNICAL_DEBT #18/#19).
    public var competitionTypeRaw: String?
    /// Tag-only last-write-wins clock. Independent of the record's `endTime`.
    public var updatedAt: Date
    /// Deterministic secondary key for two revisions with the same
    /// `updatedAt` (lexicographic `uuidString` order, larger wins). Legacy
    /// tags without one decode as `legacyRevisionID`; every edit mints a new one.
    public var revisionID: UUID

    /// Typed view of `competitionTypeRaw`. `nil` for "not set" AND for a raw
    /// value this build does not know — the raw string is kept either way.
    public var competitionType: CompetitionType? {
        get { competitionTypeRaw.flatMap(CompetitionType.init(rawValue:)) }
        set { competitionTypeRaw = newValue?.rawValue }
    }

    /// The fixed zero UUID used for a revision that predates `revisionID`.
    public static let legacyRevisionID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    /// Display-name cap (characters), shared with the iOS picker's input limit.
    public static let maxNameLength = 40
    /// Opponents beyond this are dropped by `sanitized()` (doubles has two).
    public static let maxOpponents = 2
    /// Defensive bound on a raw competition string from a peer or file.
    public static let maxCompetitionRawLength = 64
    /// The smallest step `revised(after:)` advances the clock by when the
    /// device clock has not moved past the previous revision.
    public static let minimumClockStep: TimeInterval = 0.001

    public init(
        opponents: [TaggedPlayer] = [],
        partner: TaggedPlayer? = nil,
        competitionType: CompetitionType? = nil,
        updatedAt: Date,
        revisionID: UUID = UUID()
    ) {
        self.init(
            opponents: opponents,
            partner: partner,
            competitionTypeRaw: competitionType?.rawValue,
            updatedAt: updatedAt,
            revisionID: revisionID
        )
    }

    public init(
        opponents: [TaggedPlayer] = [],
        partner: TaggedPlayer? = nil,
        competitionTypeRaw: String?,
        updatedAt: Date,
        revisionID: UUID = UUID()
    ) {
        self.opponents = opponents
        self.partner = partner
        self.competitionTypeRaw = competitionTypeRaw
        self.updatedAt = updatedAt
        self.revisionID = revisionID
    }

    /// Every field is `decodeIfPresent` + default from day one, and a
    /// malformed field or player degrades instead of throwing, so additions
    /// follow CLAUDE.md §4 without a special case and one bad tag can never
    /// blank an archive. The decoded value is `sanitized()` — every input path
    /// (wire, iCloud restore, manual import) goes through here.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let lossyOpponents = try? c.decodeIfPresent([Lossy<TaggedPlayer>].self, forKey: .opponents)
        opponents = (lossyOpponents ?? []).compactMap(\.value)
        partner = try? c.decodeIfPresent(TaggedPlayer.self, forKey: .partner)
        competitionTypeRaw = try? c.decodeIfPresent(String.self, forKey: .competitionTypeRaw)
        updatedAt = (try? c.decodeIfPresent(Date.self, forKey: .updatedAt)) ?? .distantPast
        revisionID = (try? c.decodeIfPresent(UUID.self, forKey: .revisionID)) ?? Self.legacyRevisionID
        self = sanitized()
    }

    // MARK: Derived

    /// No opponent, no partner and no competition — what "Clear details" saves.
    public var isEmpty: Bool {
        opponents.isEmpty && partner == nil && competitionTypeRaw == nil
    }

    /// Partner (if any) then opponents, in display order.
    public var allPlayers: [TaggedPlayer] {
        (partner.map { [$0] } ?? []) + opponents
    }

    public var playerIDs: Set<UUID> { Set(allPlayers.map(\.id)) }

    /// One-line summary for archive rows and the watch caption, e.g.
    /// "vs Alex · League" or "With Sam vs Alex & Jo · Tournament". `nil` when
    /// there is nothing to show (empty, or only an unknown future competition).
    public var displayLine: String? {
        var who: [String] = []
        if let partner { who.append("With \(partner.name)") }
        if !opponents.isEmpty {
            who.append("vs " + opponents.map(\.name).joined(separator: " & "))
        }
        var parts: [String] = []
        if !who.isEmpty { parts.append(who.joined(separator: " ")) }
        if let competitionType { parts.append(competitionType.displayLabel) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Merge

    /// Tag merge applied on every record merge path (§3), independent of which
    /// record body won:
    ///
    /// - one side `nil` → the other (`nil` = "no information");
    /// - both present → the revision that `supersedes` the other.
    ///
    /// Commutative: `merged(a, b) == merged(b, a)`, so two peers converge in
    /// either arrival order.
    public static func merged(_ existing: MatchTags?, _ incoming: MatchTags?) -> MatchTags? {
        switch (existing, incoming) {
        case (nil, nil): return nil
        case (let e?, nil): return e
        case (nil, let i?): return i
        case (let e?, let i?): return i.supersedes(e) ? i : e
        }
    }

    /// Strict total order over revisions: later `updatedAt`, then larger
    /// `revisionID.uuidString`, then fewer `allPlayers` (so a singles-normalized
    /// copy supersedes its untrimmed source with the same clock), then (only for two
    /// legacy/identical-clock revisions with different contents) a canonical content
    /// key. `false` for an identical value.
    public func supersedes(_ other: MatchTags) -> Bool {
        if updatedAt != other.updatedAt { return updatedAt > other.updatedAt }
        if revisionID != other.revisionID { return revisionID.uuidString > other.revisionID.uuidString }
        if allPlayers.count != other.allPlayers.count { return allPlayers.count < other.allPlayers.count }
        return canonicalContentKey > other.canonicalContentKey
    }

    private var canonicalContentKey: String {
        func field(_ value: String?) -> String {
            guard let value else { return "N" }
            return "S\(value.utf8.count):\(value)"
        }
        func player(_ value: TaggedPlayer) -> String {
            field(value.id.uuidString)
                + field(value.name)
                + field(value.handednessRaw)
                + field(value.backhandRaw)
                + field(value.playStyleRaw)
        }
        return field(competitionTypeRaw) + field(partner.map(player))
            + "\(opponents.count):" + opponents.map(player).joined()
    }

    // MARK: Editing

    /// A local edit of these tags, stamped so it supersedes `previous`:
    /// sanitized, `updatedAt` strictly later than `previous.updatedAt` even if
    /// the device clock moved backwards (§11.2), and a freshly minted
    /// `revisionID`. Use this for every UI write — including "Clear details",
    /// which is `MatchTags.cleared(after:)`.
    public func revised(after previous: MatchTags?, now: Date = Date(), revisionID: UUID = UUID()) -> MatchTags {
        var next = sanitized()
        next.updatedAt = Self.nextClock(after: previous, now: now)
        next.revisionID = revisionID
        return next
    }

    /// An explicit clear that beats `previous` (an empty, newer revision).
    public static func cleared(after previous: MatchTags?, now: Date = Date(), revisionID: UUID = UUID()) -> MatchTags {
        MatchTags(competitionTypeRaw: nil, updatedAt: now).revised(after: previous, now: now, revisionID: revisionID)
    }

    /// `now`, or the smallest step past `previous.updatedAt` when the clock
    /// has not advanced past it.
    public static func nextClock(after previous: MatchTags?, now: Date) -> Date {
        guard let previous else { return now }
        return max(now, previous.updatedAt.addingTimeInterval(minimumClockStep))
    }

    // MARK: Sanitizing

    /// Applied on every input path — UI, wire decode, archive import. Names:
    /// see `sanitizedName(_:)`; players with an empty name are dropped;
    /// opponents are de-duplicated by id (an opponent who is also the partner
    /// is dropped from opponents) and capped at `maxOpponents`. An empty or
    /// whitespace competition raw becomes `nil`; an unknown one is kept
    /// verbatim (bounded). The singles/doubles shape is NOT enforced here —
    /// decode must never destroy data an editor wrote. Idempotent.
    public func sanitized() -> MatchTags {
        var copy = self
        copy.partner = partner.flatMap(Self.sanitizedPlayer)
        var seen: Set<UUID> = copy.partner.map { [$0.id] } ?? []
        copy.opponents = opponents
            .compactMap(Self.sanitizedPlayer)
            .filter { seen.insert($0.id).inserted }
        if copy.opponents.count > Self.maxOpponents {
            copy.opponents = Array(copy.opponents.prefix(Self.maxOpponents))
        }
        if let raw = competitionTypeRaw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
           !raw.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) {
            copy.competitionTypeRaw = String(raw.prefix(Self.maxCompetitionRawLength))
        } else {
            copy.competitionTypeRaw = nil
        }
        return copy
    }

    private static func sanitizedPlayer(_ player: TaggedPlayer) -> TaggedPlayer? {
        let name = sanitizedName(player.name)
        return name.isEmpty ? nil : TaggedPlayer(
            id: player.id,
            name: name,
            handednessRaw: player.handednessRaw,
            backhandRaw: player.backhandRaw,
            playStyleRaw: player.playStyleRaw
        )
    }

    /// Trim, turn line breaks into spaces, drop other control characters and
    /// bidirectional-override characters (spoofing), collapse internal
    /// whitespace runs to one space, cap at `maxNameLength` characters.
    /// Emoji sequences (ZWJ) survive.
    public static func sanitizedName(_ raw: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars {
            if isLineBreak(scalar) {
                scalars.append(" ")
            } else if scalar.properties.generalCategory == .control || isBidiControl(scalar) {
                continue
            } else {
                scalars.append(scalar)
            }
        }
        let collapsed = String(scalars)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return String(collapsed.prefix(maxNameLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns a copy trimmed to singles shape (`partner = nil`, at most one
    /// opponent) while preserving `(updatedAt, revisionID)` so normalizing a
    /// stale doubles tag snapshot on one peer never promotes unrelated fields
    /// ahead of newer tag edits made on another peer.
    public func normalizedForSingles() -> MatchTags {
        guard partner != nil || opponents.count > 1 else { return self }
        var copy = self
        copy.partner = nil
        copy.opponents = Array(opponents.prefix(1))
        return copy.sanitized()
    }

    static func isLineBreak(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0x2028, 0x2029: return true
        default: return false
        }
    }

    /// LRE/RLE/PDF/LRO/RLO, LRI/RLI/FSI/PDI, LRM/RLM/ALM — invisible
    /// direction controls that can make a name render as something else.
    static func isBidiControl(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x202A...0x202E, 0x2066...0x2069, 0x200E, 0x200F, 0x061C: return true
        default: return false
        }
    }
}

// MARK: - Applying tags to a record

public extension MatchRecord {
    /// This record with `incoming` tags merged in by the tag clock. The body
    /// (score, completion, stats, health) is never touched — a tag-only update
    /// can never advance a score or complete a match. The watch's
    /// `StatsStore.updateTags` and the phone's `PhoneStatsStore.updateTags`
    /// apply a `matchTagsUpdate` with this.
    ///
    /// If this completed record already has a `.singles` `matchTypeRevision`,
    /// the merged tags are trimmed to singles shape without advancing their clock.
    func mergingTags(_ incoming: MatchTags?) -> MatchRecord {
        var copy = self
        var merged = MatchTags.merged(tags, incoming)
        if !copy.isInProgress, copy.matchTypeRevision?.matchType == .singles {
            merged = merged?.normalizedForSingles()
        }
        copy.tags = merged
        return copy
    }
}

// MARK: - Wire payload

/// Body of the `MatchSyncKey.matchTagsUpdate` payload: one match's tags. Bidirectional;
/// applied only to a record the receiver already holds, merged by the tag clock.
public struct MatchTagsUpdate: Codable, Equatable, Sendable {
    public let matchID: UUID
    public let tags: MatchTags

    public init(matchID: UUID, tags: MatchTags) {
        self.matchID = matchID
        self.tags = tags
    }
}

// MARK: - Reconciliation (§6.1)

public extension MatchTags {
    /// Tag updates the phone should (re)send so the watch eventually converges,
    /// even if an edit-time send was skipped (manifest lag, older watch build
    /// upgraded later). Pure; resends are idempotent on the watch.
    ///
    /// - `archive`: the phone's canonical records (already merged and scrubbed).
    /// - `watchCopies`: record bodies the watch just sent (`.history` /
    ///   `.singleMatch`), carrying the WATCH's tags. Any id whose archive tags
    ///   supersede the watch copy's (`nil` on the watch counts as oldest) is
    ///   resent — this heals an upgraded watch whose first push has no tags.
    /// - `newlyHeld`: ids in the newest manifest that were NOT in the previous
    ///   one (see `newlyHeldIDs(previous:current:)`). Any non-nil archive tags
    ///   are sent, **including an empty clear** — an empty newer revision is a
    ///   deletion instruction, not an absence of data. Diffing (not resending
    ///   every held id) matters: a manifest rides on every live checkpoint.
    ///
    /// Returns one update per match id, sorted by id for determinism.
    static func pendingWatchUpdates(
        archive: [MatchRecord],
        watchCopies: [MatchRecord],
        newlyHeld: Set<UUID>
    ) -> [MatchTagsUpdate] {
        let archiveTags: [UUID: MatchTags] = Dictionary(
            archive.compactMap { record in record.tags.map { (record.id, $0) } },
            uniquingKeysWith: { a, b in MatchTags.merged(a, b) ?? a }
        )
        var pending: [UUID: MatchTags] = [:]

        for copy in watchCopies {
            guard let phoneTags = archiveTags[copy.id] else { continue }
            if let watchTags = copy.tags, !phoneTags.supersedes(watchTags) { continue }
            pending[copy.id] = phoneTags
        }
        for id in newlyHeld {
            guard let phoneTags = archiveTags[id] else { continue }
            pending[id] = phoneTags
        }

        return pending
            .map { MatchTagsUpdate(matchID: $0.key, tags: $0.value) }
            .sorted { $0.matchID.uuidString < $1.matchID.uuidString }
    }

    /// Ids present in `current` but not in `previous` — the manifest diff fed
    /// to `pendingWatchUpdates(newlyHeld:)`. An unchanged manifest yields `[]`.
    static func newlyHeldIDs(previous: Set<UUID>, current: Set<UUID>) -> Set<UUID> {
        current.subtracting(previous)
    }
}

// MARK: - Lossy element decoding

/// Decodes one array element, yielding `nil` instead of throwing, so one
/// malformed player cannot fail the surrounding record.
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
