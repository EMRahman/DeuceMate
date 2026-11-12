// GamePlanScope.swift — which matches an Opponent Game Plan may draw on, and
// how the user's selection resolves against them. Pure and platform-neutral.
//
// Rules (docs/features/OPPONENT_GAME_PLAN_PROPOSAL.md §4):
// - Opposition is matched by the selected player's UUID in the match's
//   OPPONENT tags, never by name, and never by a partner appearance.
// - The canonical phone archive is the source; duplicates are collapsed by
//   match UUID. Untagged matches cannot be assigned automatically.
// - v1 is singles-only: doubles matches against the player are listed as
//   exclusions with a reason, never silently folded in.
// - In-progress checkpoints are excluded unless the user opts in, and then
//   only as partial evidence (never results or head-to-head).
// - Selection order is `startTime` descending with the UUID string as a
//   deterministic tie-break. Filters apply BEFORE the count is taken.
import Foundation

// MARK: - Competition buckets

/// One competition context as the game plan groups it. Unlike
/// `CompetitionType?`, this keeps "never set" (`.unspecified`) apart from a
/// tagged raw value this build does not recognise (`.unrecognized`) — an
/// unknown future type is neither Friendly nor Unspecified.
public enum GamePlanCompetition: Hashable, Sendable, Identifiable {
    case friendly, league, tournament, practice
    case unspecified
    case unrecognized(String)

    public init(raw: String?) {
        guard let raw, !raw.isEmpty else { self = .unspecified; return }
        switch CompetitionType(rawValue: raw) {
        case .friendly?:   self = .friendly
        case .league?:     self = .league
        case .tournament?: self = .tournament
        case .practice?:   self = .practice
        case nil:          self = .unrecognized(raw)
        }
    }

    public init(_ type: CompetitionType) {
        self.init(raw: type.rawValue)
    }

    public init(record: MatchRecord) {
        self.init(raw: record.tags?.competitionTypeRaw)
    }

    public var id: String {
        switch self {
        case .unrecognized(let raw): return "unrecognized:\(raw)"
        default: return label
        }
    }

    public var label: String {
        switch self {
        case .friendly:     return "Friendly"
        case .league:       return "League"
        case .tournament:   return "Tournament"
        case .practice:     return "Practice"
        case .unspecified:  return "Unspecified"
        case .unrecognized: return "Unrecognised type"
        }
    }

    /// Stable display order: the four known types, Unspecified, then unknown
    /// raw values alphabetically.
    var sortKey: (Int, String) {
        switch self {
        case .friendly:              return (0, "")
        case .league:                return (1, "")
        case .tournament:            return (2, "")
        case .practice:              return (3, "")
        case .unspecified:           return (4, "")
        case .unrecognized(let raw): return (5, raw)
        }
    }

    public static func ordered(_ a: GamePlanCompetition, _ b: GamePlanCompetition) -> Bool {
        a.sortKey < b.sortKey
    }
}

// MARK: - Upcoming match

/// What the player says about the match they are preparing for. These are
/// user statements, not tracked measurements. A bare value starts unset; the
/// iPhone screen pre-fills competition and format from the previous match
/// against the opponent (`init(prefilledFrom:)`) and shows them on its first
/// row, so the statement the pack makes is always visible and editable.
public struct GamePlanUpcomingMatch: Equatable, Sendable {
    public var competition: CompetitionType?
    public var format: MatchFormat?
    public var date: Date?
    /// Free text (surface, conditions, a concern), as typed. Exports only
    /// ever read `sanitizedPreparationText`.
    public var preparationText: String

    public static let maxPreparationLength = 1_000

    public init(competition: CompetitionType? = nil, format: MatchFormat? = nil,
                date: Date? = nil, preparationText: String = "") {
        self.competition = competition
        self.format = format
        self.date = date
        self.preparationText = preparationText
    }

    /// The previous match's competition and format, as a starting point for
    /// the next one. An untagged or unrecognised competition stays unset (it
    /// is never guessed as Friendly or League), and a format the upcoming
    /// picker doesn't offer stays unset. Date and preparation text never carry over.
    public init(prefilledFrom record: MatchRecord) {
        self.init(
            competition: record.tags?.competitionTypeRaw.flatMap(CompetitionType.init(rawValue:)),
            format: GamePlanText.selectableFormats.contains(record.matchFormat) ? record.matchFormat : nil
        )
    }

    /// Same cleaning as private notes (control and bidi characters, line
    /// endings, surrounding whitespace), capped at `maxPreparationLength`.
    /// `nil` when nothing remains.
    public var sanitizedPreparationText: String? {
        let clean = MatchNotesPolicy.sanitizedText(preparationText)
        let capped = String(clean.prefix(Self.maxPreparationLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return capped.isEmpty ? nil : capped
    }
}

// MARK: - Eligibility

/// Every match the archive holds against one opponent, split into what the
/// game plan may use and what it must disclose as excluded.
public struct GamePlanCandidates: Equatable, Sendable {
    public let opponentID: UUID
    /// Singles matches with the player tagged as an opponent, newest first by
    /// start time (UUID tie-break). Completed records always; in-progress
    /// checkpoints only when the caller opted in.
    public let eligible: [MatchRecord]
    /// Doubles matches with the player among the opponents — v1 cannot
    /// attribute team-level points to one opponent.
    public let excludedDoubles: [MatchRecord]
    /// Singles in-progress checkpoints left out because the caller did not opt in.
    public let excludedInProgress: [MatchRecord]
    /// Singles matches in the archive with no tagged opponent at all. They
    /// might be against this player, but cannot be assigned automatically.
    public let untaggedSinglesCount: Int

    public var eligibleIDs: Set<UUID> { Set(eligible.map(\.id)) }
    /// The exclusion counts a pack discloses — cheap to compare, unlike the records.
    public var counts: GamePlanCandidateCounts {
        GamePlanCandidateCounts(doubles: excludedDoubles.count, inProgressNotIncluded: excludedInProgress.count,
                                untaggedSingles: untaggedSinglesCount)
    }
    public var completedEligibleCount: Int { eligible.filter { !$0.isInProgress }.count }

    /// The most recent singles match against this opponent by start time,
    /// finished or not, and whether or not unfinished matches are opted in as
    /// evidence. It pre-fills the upcoming match; it is not evidence itself.
    public var latestMatch: MatchRecord? {
        (eligible + excludedInProgress).min(by: GamePlanEligibility.newestFirst)
    }
}

public struct GamePlanCandidateCounts: Equatable, Sendable {
    public let doubles: Int
    public let inProgressNotIncluded: Int
    public let untaggedSingles: Int

    public init(doubles: Int, inProgressNotIncluded: Int, untaggedSingles: Int) {
        self.doubles = doubles
        self.inProgressNotIncluded = inProgressNotIncluded
        self.untaggedSingles = untaggedSingles
    }
}

public enum GamePlanEligibility {

    /// The selection order: newest `startTime` first, UUID string ascending
    /// on ties so equal start times always resolve the same way.
    public static func newestFirst(_ a: MatchRecord, _ b: MatchRecord) -> Bool {
        a.startTime != b.startTime ? a.startTime > b.startTime : a.id.uuidString < b.id.uuidString
    }

    public static func candidates(
        for opponentID: UUID,
        in records: [MatchRecord],
        forgotten: ForgottenPlayerLedger = ForgottenPlayerLedger(),
        includeInProgress: Bool = false
    ) -> GamePlanCandidates {
        // A forgotten player has no evidence, even if a stale copy still carries them.
        let isForgotten = forgotten.contains(opponentID)
        var seen: Set<UUID> = []
        var eligible: [MatchRecord] = []
        var doubles: [MatchRecord] = []
        var inProgress: [MatchRecord] = []
        var untagged = 0
        for record in records where seen.insert(record.id).inserted {
            let opponents = record.tags?.opponents ?? []
            if record.matchType == .singles && opponents.isEmpty {
                untagged += 1
                continue
            }
            guard !isForgotten, opponents.contains(where: { $0.id == opponentID }) else { continue }
            switch record.matchType {
            case .doubles:
                doubles.append(record)
            case .singles:
                if record.isInProgress && !includeInProgress {
                    inProgress.append(record)
                } else {
                    eligible.append(record)
                }
            }
        }
        return GamePlanCandidates(
            opponentID: opponentID,
            eligible: eligible.sorted(by: newestFirst),
            excludedDoubles: doubles.sorted(by: newestFirst),
            excludedInProgress: inProgress.sorted(by: newestFirst),
            untaggedSinglesCount: untagged
        )
    }
}

// MARK: - Filters

/// Optional narrowing applied before any count is taken. Dates compare the
/// match's start time against whole local days.
public struct GamePlanFilter: Equatable, Sendable {
    /// Inclusive start-of-day bound; `nil` = no lower bound.
    public var from: Date?
    /// Inclusive end-of-day bound; `nil` = no upper bound.
    public var through: Date?
    /// `nil` = every competition context.
    public var competitions: Set<GamePlanCompetition>?

    public init(from: Date? = nil, through: Date? = nil, competitions: Set<GamePlanCompetition>? = nil) {
        self.from = from
        self.through = through
        self.competitions = competitions
    }

    public static let none = GamePlanFilter()

    public var isActive: Bool { from != nil || through != nil || competitions != nil }

    public func includes(_ record: MatchRecord, calendar: Calendar = .current) -> Bool {
        if let from, record.startTime < calendar.startOfDay(for: from) { return false }
        if let through,
           let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: through)),
           record.startTime >= endOfDay { return false }
        if let competitions, !competitions.contains(GamePlanCompetition(record: record)) { return false }
        return true
    }
}

// MARK: - Selection

public enum GamePlanSelectionMode: Equatable, Sendable {
    /// The latest N filtered matches (Last 5, Last 10, or a custom count).
    case latest(Int)
    /// Every filtered eligible match.
    case all
    /// Exactly these matches (intersected with the filtered eligible set).
    case custom(Set<UUID>)
}

/// The user's evidence selection. A value: the view holds it in state and
/// resolves it against freshly derived candidates on every change, so a
/// deleted, merged or forgotten match drops out without any extra bookkeeping.
public struct GamePlanSelection: Equatable, Sendable {
    public static let defaultCount = 5
    public static let presetCounts = [5, 10]

    public var mode: GamePlanSelectionMode
    public private(set) var filter: GamePlanFilter

    public init(mode: GamePlanSelectionMode = .latest(GamePlanSelection.defaultCount),
                filter: GamePlanFilter = .none) {
        self.mode = mode
        self.filter = filter
    }

    /// Filtered eligible matches, newest first. The pool every preset counts from.
    public func filtered(_ candidates: GamePlanCandidates, calendar: Calendar = .current) -> [MatchRecord] {
        candidates.eligible.filter { filter.includes($0, calendar: calendar) }
    }

    /// The selected matches, newest first. Never more than were asked for,
    /// never anything outside the filtered eligible set.
    public func resolve(_ candidates: GamePlanCandidates, calendar: Calendar = .current) -> [MatchRecord] {
        let pool = filtered(candidates, calendar: calendar)
        switch mode {
        case .latest(let count):
            return Array(pool.prefix(max(0, count)))
        case .all:
            return pool
        case .custom(let ids):
            return pool.filter { ids.contains($0.id) }
        }
    }

    /// Changing a filter recomputes count presets automatically (they resolve
    /// against the new pool). A custom selection is intersected with the new
    /// filtered set — matches are only ever removed, never silently added.
    public mutating func setFilter(_ newFilter: GamePlanFilter, candidates: GamePlanCandidates,
                                   calendar: Calendar = .current) {
        filter = newFilter
        if case .custom(let ids) = mode {
            let allowed = Set(filtered(candidates, calendar: calendar).map(\.id))
            mode = .custom(ids.intersection(allowed))
        }
    }

    /// Adds or removes one match. The selection becomes a custom selection
    /// seeded from whatever was selected before the change.
    public mutating func toggle(_ matchID: UUID, candidates: GamePlanCandidates, calendar: Calendar = .current) {
        var ids = Set(resolve(candidates, calendar: calendar).map(\.id))
        if ids.contains(matchID) {
            ids.remove(matchID)
        } else if filtered(candidates, calendar: calendar).contains(where: { $0.id == matchID }) {
            ids.insert(matchID)
        }
        mode = .custom(ids)
    }

    /// Clamps a custom count to 1…available (or 1 when nothing is available).
    public static func clampedCount(_ requested: Int, available: Int) -> Int {
        min(max(1, requested), max(1, available))
    }

    /// The selection as the pack's manifest states it, filters included:
    /// "Last 5 by start date · League, Friendly · from 2026-01-01".
    public func manifestDescription(timeZone: TimeZone) -> String {
        var parts: [String]
        if case .latest = mode { parts = [label + " by start date"] } else { parts = [label] }
        if let competitions = filter.competitions {
            let names = competitions.sorted(by: GamePlanCompetition.ordered).map(\.label)
            parts.append(names.isEmpty ? "no competition types" : names.joined(separator: ", "))
        }
        if let from = filter.from { parts.append("from \(GamePlanText.day(from, timeZone: timeZone))") }
        if let through = filter.through { parts.append("through \(GamePlanText.day(through, timeZone: timeZone))") }
        return parts.joined(separator: " · ")
    }

    /// "Last 5", "Last 10", "Last 7", "All matches" or "Custom selection".
    public var label: String {
        switch mode {
        case .latest(let count): return "Last \(count)"
        case .all:               return "All matches"
        case .custom:            return "Custom selection"
        }
    }
}
