// GamePlanEvidence.swift — the allowlisted projection behind an Opponent Game
// Plan evidence pack. Pure and platform-neutral.
//
// This is the export boundary (OPPONENT_GAME_PLAN_PROPOSAL.md §5, §7): whole
// `MatchRecord`s go in, and only tennis facts come out. The text builder
// (`GamePlanPackBuilder`) sees nothing but this value, so it cannot leak what
// was left out:
//
// - Health: every record is health-stripped before any figure is derived, and
//   no heart-rate, step, calorie or distance field is carried. Point rows
//   carry no timestamps or physiological samples.
// - Names: the opponent's name is held only when the caller opted in.
// - Notes: a note is held only when notes were opted in, the match is
//   selected, the note has text, and the player did not omit it.
//
// Figures reuse the existing rules rather than restating them: one
// `MatchStatsSummary` per side feeds a `MatchTrendSample`, rates are read
// through `TrendMetric.rawPair`, serve/return splits use categorized points
// only (the `MatchComparison` rule), and pooling is Σnumerator / Σdenominator
// over the matches that recorded the metric — never a mean of percentages.
import Foundation

// MARK: - Options

public enum GamePlanDetailMode: String, CaseIterable, Identifiable, Sendable {
    /// Every saved point row for every selected match (the default).
    case full
    /// Every selected match's summary and opted-in note; point rows omitted
    /// and the omission labelled.
    case summaryOnly

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .full:        return "Full detail"
        case .summaryOnly: return "Summary only"
        }
    }
}

// MARK: - Projected values

/// How one match ended, without inferring anything the record does not say.
public enum GamePlanMatchStatus: Equatable, Sendable {
    public enum Ending: Equatable, Sendable {
        /// The configured format reached its normal finish.
        case formatFinished
        /// Recorded as completed before the format's normal finish — for
        /// example "End at Current Score" or a manual entry.
        case stoppedEarly
        /// An open-ended format, which only ever ends when the recorder stops it.
        case openEnded
    }
    case completed(MatchResult, Ending)
    /// A saved checkpoint only. Never a result, never head-to-head evidence.
    case inProgress

    public init(record: MatchRecord) {
        guard let result = MatchResult(record: record) else { self = .inProgress; return }
        let config = record.matchFormat.config
        if config.isEndless {
            self = .completed(result, .openEnded)
            return
        }
        let state = ScoringState(
            sets: record.setScores,
            currentPointsMe: record.currentPointsMe,
            currentPointsOpponent: record.currentPointsOpponent,
            matchFormat: record.matchFormat
        )
        self = .completed(result, ScoringEngine.isMatchComplete(state) ? .formatFinished : .stoppedEarly)
    }

    public var isCompleted: Bool {
        if case .completed = self { return true }
        return false
    }

    public var result: MatchResult? {
        if case .completed(let result, _) = self { return result }
        return nil
    }

    /// "Won", "Lost — stopped at the recorded score…", "In progress — …".
    public var label: String {
        switch self {
        case .inProgress:
            return "In progress — saved checkpoint only (partial evidence, not a result; the Watch may hold a newer score)"
        case .completed(let result, let ending):
            let base: String
            switch result {
            case .win:  base = "Won"
            case .loss: base = "Lost"
            case .draw: base = "Draw (completed level)"
            }
            switch ending {
            case .formatFinished: return base
            case .stoppedEarly:   return base + " — completed at the recorded score before the format's normal finish"
            case .openEnded:      return base + " — open-ended format, ended by the recorder"
            }
        }
    }
}

/// What a match saved, so every figure can say how much it rests on.
public struct GamePlanCoverage: Equatable, Sendable {
    public let pointsSaved: Int
    public let pointsWithOutcome: Int
    public let pointsWithEndingPhase: Int
    public let pointsWithScoreContext: Int

    public init(points: [PointStat]) {
        pointsSaved = points.count
        pointsWithOutcome = points.filter { $0.outcome != .uncategorized }.count
        pointsWithEndingPhase = points.filter { $0.endingShot != nil }.count
        pointsWithScoreContext = points.filter { $0.gameScoreAtStart != nil }.count
    }

    public var isScoreOnly: Bool { pointsSaved == 0 }
    /// Some, but not all, points carry an outcome.
    public var isPartiallyTracked: Bool { pointsWithOutcome > 0 && pointsWithOutcome < pointsSaved }
}

/// Which serve a point was played on. `nil` on a point without a recorded
/// outcome: its default `isSecondServe == false` is not evidence of a first serve.
public enum GamePlanServe: String, Equatable, Sendable {
    case first, second
}

/// One saved point, projected to tennis facts only.
public struct GamePlanPoint: Equatable, Sendable {
    /// "M001-P023": match reference plus 1-based position in recorded order.
    public let reference: String
    public let setNumber: Int
    public let server: Player
    public let winner: Player
    public let serve: GamePlanServe?
    public let outcome: PointOutcome
    /// The PHASE the point ended in — never a shot count.
    public let endingShot: EndingShot?
    public let isBreakPoint: Bool
    /// Me–Opponent game score before the point ("30–15", "Deuce", "5–4" in a tiebreak).
    public let gameScoreBefore: String?
    /// Me–Opponent match score before the point ("6–4  3–2"), only when it
    /// can be attributed safely.
    public let matchScoreBefore: String?
}

/// One metric's value for one match and one side. `nil` = not recorded.
public struct GamePlanMetricValue: Equatable, Sendable {
    public let metric: TrendMetric
    public let ratio: TrendMetric.Ratio?
}

/// A metric pooled across a scope: Σnumerator / Σdenominator over the
/// matches that recorded it, with how many matches that was.
public struct GamePlanPooledValue: Equatable, Sendable {
    public let ratio: TrendMetric.Ratio?
    public let contributingMatches: Int
    public let matchesInScope: Int
}

public struct GamePlanPooledRow: Equatable, Sendable {
    public let metric: TrendMetric
    public let me: GamePlanPooledValue
    /// `nil` for recorder-only rows (rally-phase metrics, which are the same
    /// points seen from the other side).
    public let opponent: GamePlanPooledValue?
}

/// Recorder-framed results at one score state ("At 30-All", "At Deuce/Ad", "In Tiebreak").
public struct GamePlanScoreState: Equatable, Sendable {
    public let label: String
    public let total: Int
    public let wins: Int
}

/// One selected match, projected.
public struct GamePlanMatch: Equatable, Sendable {
    public let reference: String
    public let startTime: Date
    public let endTime: Date?
    public let competition: GamePlanCompetition
    public let matchFormat: MatchFormat
    public let status: GamePlanMatchStatus
    /// Recorder-framed set scores; a trailing unstarted set of a checkpoint is omitted.
    public let setScoreLabels: [String]
    /// The checkpoint's current game ("30–15"), in-progress records only.
    public let checkpointGameScore: String?
    public let durationSeconds: TimeInterval?
    /// How many times play was explicitly resumed from history.
    public let resumeCount: Int
    /// The opponent's playing profile as tagged on THIS match (user-entered).
    public let opponentProfileAtMatch: String?
    public let coverage: GamePlanCoverage
    public let recorderFigures: [GamePlanMetricValue]
    public let opponentFigures: [GamePlanMetricValue]
    /// Recorder-framed score-state results ("At 30-All", "At Deuce/Ad", "In Tiebreak").
    public let scoreStates: [GamePlanScoreState]
    /// Recorder rally-phase figures (share of phase-recorded points, and win rate there).
    public let rallyFigures: [GamePlanMetricValue]
    public let limitations: [String]
    /// Empty in Summary only mode.
    public let points: [GamePlanPoint]
    /// The opted-in, reviewed private note. `nil` otherwise.
    public let note: String?

    // Pooling inputs.
    let recorderSample: MatchTrendSample
    let recorderServeSample: MatchTrendSample
    let opponentSample: MatchTrendSample
    let opponentServeSample: MatchTrendSample
}

/// A group of matches summarised together (all selected, latest five, one
/// competition context, or in-progress checkpoints).
public struct GamePlanScopeFigures: Equatable, Sendable {
    public let title: String
    public let references: [String]
    public let firstStart: Date?
    public let lastStart: Date?
    /// Completed-only tally. Empty for the in-progress scope.
    public let record: HeadToHeadRecord
    public let pointsSaved: Int
    public let pointsWithOutcome: Int
    public let rows: [GamePlanPooledRow]
    public let isPartialScope: Bool
}

/// One competition context in the breakdown table.
public struct GamePlanCompetitionRow: Equatable, Sendable {
    public let competition: GamePlanCompetition
    public let completedCount: Int
    public let inProgressCount: Int
    public let record: HeadToHeadRecord
    public let pointsSaved: Int
    public let references: [String]
    /// True when this is the upcoming match's own competition.
    public let matchesUpcoming: Bool
}

public struct GamePlanExclusions: Equatable, Sendable {
    public let doublesCount: Int
    public let inProgressNotIncludedCount: Int
    public let untaggedSinglesCount: Int
    /// Eligible matches (after filters) the selection did not include.
    public let unselectedEligibleCount: Int
}

// MARK: - Evidence

public struct GamePlanEvidence: Equatable, Sendable {
    public static let packFormat = "deucemate.gamePlanPack"
    public static let packVersion = 1

    /// Shown once completed matches exceed this many: a second scope with
    /// the latest five completed matches.
    public static let recentScopeCount = 5

    /// Per-side figures in display order.
    public static let sideMetrics: [TrendMetric] = [
        .pointsWon,
        .firstServeIn, .firstServeWin, .secondServeWin, .doubleFaults,
        .returnWinFirst, .returnWinSecond,
        .breakPointsConverted, .breakPointsSaved, .bigPointWin,
        .winners, .unforcedErrors, .forcedErrorsConceded
    ]

    /// Recorder rally-phase figures: where points ended and how they went there.
    public static let rallyMetrics: [TrendMetric] = [
        .depthShareServe, .depthShareReturn, .depthShareServePlusOne, .depthShareRally,
        .depthWinServe, .depthWinReturn, .depthWinServePlusOne, .depthWinRally
    ]

    public let builtAt: Date
    public let upcomingCompetition: CompetitionType?
    public let upcomingFormat: MatchFormat?
    public let upcomingDate: Date?
    public let preparationText: String?
    public let includesNames: Bool
    /// Only when names are included.
    public let opponentName: String?
    /// Current roster profile (user-entered, may postdate older matches).
    public let opponentProfile: String?
    /// The player's free-text scouting notes about the opponent's game
    /// (`TaggedPlayer.playingNotes`). `nil` unless opted in AND present.
    public let opponentPlayingNotes: String?
    /// Whether the opponent has playing notes at all (so the manifest can say
    /// they were withheld rather than absent).
    public let playingNotesAvailable: Bool
    public let detailMode: GamePlanDetailMode
    /// Selected matches, oldest first: M001 is the earliest.
    public let matches: [GamePlanMatch]
    /// Eligible matches after filters, before the count/selection.
    public let availableCount: Int
    public let exclusions: GamePlanExclusions
    public let notesAvailableCount: Int
    public let notesIncludedCount: Int
    public let notesOmittedCount: Int
    public let includesNotes: Bool
    /// Completed-only head-to-head within the selection.
    public let headToHead: HeadToHeadRecord
    public let scopes: [GamePlanScopeFigures]
    public let competitionRows: [GamePlanCompetitionRow]

    /// - Parameters:
    ///   - selected: the resolved selection (any order; re-sorted here).
    ///   - availableCount: filtered eligible matches the selection drew from.
    ///   - notes: stored private note text by match id. Only selected,
    ///     non-omitted, non-empty notes survive, and only with `includeNotes`.
    ///   - progress: called after each match is projected (done, total).
    public init(
        opponentID: UUID,
        opponent: RosterEntry?,
        selected: [MatchRecord],
        candidateCounts: GamePlanCandidateCounts,
        availableCount: Int,
        upcoming: GamePlanUpcomingMatch,
        notes: [UUID: String],
        includeNotes: Bool,
        omittedNoteMatchIDs: Set<UUID>,
        includeNames: Bool,
        includePlayingNotes: Bool = false,
        detailMode: GamePlanDetailMode,
        builtAt: Date,
        progress: ((Int, Int) -> Void)? = nil
    ) throws {
        // Oldest first, so references read chronologically.
        let ordered = selected.sorted { GamePlanEligibility.newestFirst($1, $0) }
        var seen: Set<UUID> = []
        let unique = ordered.filter { seen.insert($0.id).inserted }

        var projected: [GamePlanMatch] = []
        projected.reserveCapacity(unique.count)
        var notesAvailable = 0, notesIncluded = 0, notesOmitted = 0
        for (index, record) in unique.enumerated() {
            try Task.checkCancellation()
            let reference = Self.reference(index)
            let clean = notes[record.id].map(MatchNotesPolicy.sanitizedText) ?? ""
            var note: String?
            if !clean.isEmpty {
                notesAvailable += 1
                if includeNotes {
                    if omittedNoteMatchIDs.contains(record.id) {
                        notesOmitted += 1
                    } else {
                        note = clean
                        notesIncluded += 1
                    }
                }
            }
            projected.append(Self.project(record, opponentID: opponentID, reference: reference,
                                          note: note, includePoints: detailMode == .full))
            progress?(index + 1, unique.count)
        }

        self.builtAt = builtAt
        self.upcomingCompetition = upcoming.competition
        self.upcomingFormat = upcoming.format
        self.upcomingDate = upcoming.date
        self.preparationText = upcoming.sanitizedPreparationText
        self.includesNames = includeNames
        self.opponentName = includeNames ? opponent?.name : nil
        self.opponentProfile = opponent?.taggedPlayer.profileSummary
        self.playingNotesAvailable = opponent?.playingNotes != nil
        self.opponentPlayingNotes = includePlayingNotes ? opponent?.playingNotes : nil
        self.detailMode = detailMode
        self.matches = projected
        self.availableCount = availableCount
        self.exclusions = GamePlanExclusions(
            doublesCount: candidateCounts.doubles,
            inProgressNotIncludedCount: candidateCounts.inProgressNotIncluded,
            untaggedSinglesCount: candidateCounts.untaggedSingles,
            unselectedEligibleCount: max(0, availableCount - unique.count)
        )
        self.notesAvailableCount = notesAvailable
        self.notesIncludedCount = notesIncluded
        self.notesOmittedCount = notesOmitted
        self.includesNotes = includeNotes
        self.headToHead = HeadToHead.record(vs: opponentID, in: unique, excluding: nil, matchType: .singles)
        self.scopes = Self.scopes(for: projected)
        self.competitionRows = Self.competitionRows(for: projected, upcoming: upcoming.competition)
    }

    // MARK: Derived

    public var completedMatches: [GamePlanMatch] { matches.filter { $0.status.isCompleted } }
    public var inProgressMatches: [GamePlanMatch] { matches.filter { !$0.status.isCompleted } }
    public var pointsSaved: Int { matches.reduce(0) { $0 + $1.coverage.pointsSaved } }
    public var pointRowCount: Int { matches.reduce(0) { $0 + $1.points.count } }
    public var scoreOnlyCount: Int { matches.filter(\.coverage.isScoreOnly).count }
    public var partiallyTrackedCount: Int { matches.filter(\.coverage.isPartiallyTracked).count }
    public var firstStart: Date? { matches.first?.startTime }
    public var lastStart: Date? { matches.last?.startTime }

    /// Upcoming competition with no selected completed match of that type.
    public var upcomingCompetitionHasNoHistory: Bool {
        guard let upcoming = upcomingCompetition else { return false }
        let bucket = GamePlanCompetition(upcoming)
        return !completedMatches.contains { $0.competition == bucket }
    }

    /// Selected matches by competition context, in display order.
    public var competitionCounts: [(competition: GamePlanCompetition, count: Int)] {
        competitionRows.map { ($0.competition, $0.completedCount + $0.inProgressCount) }
    }

    // MARK: Projection

    static func reference(_ index: Int) -> String {
        String(format: "M%03d", index + 1)
    }

    static func project(_ raw: MatchRecord, opponentID: UUID, reference: String,
                        note: String?, includePoints: Bool) -> GamePlanMatch {
        // Health never enters a derivation below.
        let record = raw.strippingHealthData()
        let stats = record.stats
        let categorized = stats.filter { $0.outcome != .uncategorized }

        func sample(_ points: [PointStat], focal: Player) -> MatchTrendSample {
            let summary = MatchStatsSummary(stats: points, focal: focal,
                                            setElapsedSeconds: record.setElapsedSeconds,
                                            resumeEvents: record.resumeEvents, sessionPoints: stats)
            return MatchTrendSample(record: record, summary: summary)
        }
        let recorderSample = sample(stats, focal: .me)
        let recorderServe = sample(categorized, focal: .me)
        let opponentSample = sample(stats, focal: .opponent)
        let opponentServe = sample(categorized, focal: .opponent)

        func figures(_ all: MatchTrendSample, _ serve: MatchTrendSample) -> [GamePlanMetricValue] {
            sideMetrics.map { metric in
                GamePlanMetricValue(metric: metric, ratio: Self.ratio(metric, all: all, serve: serve))
            }
        }

        let coverage = GamePlanCoverage(points: stats)
        let status = GamePlanMatchStatus(record: record)
        let opponentTag = record.tags?.opponents.first { $0.id == opponentID }
        let recorderSummary = MatchStatsSummary(stats: stats, focal: .me, resumeEvents: record.resumeEvents,
                                                sessionPoints: stats)

        var points: [GamePlanPoint] = []
        if includePoints {
            let scores = PointMatchScore.atStart(of: stats, record: record)
            points.reserveCapacity(stats.count)
            for (index, point) in stats.enumerated() {
                points.append(GamePlanPoint(
                    reference: "\(reference)-P\(String(format: "%03d", index + 1))",
                    setNumber: point.setIndex + 1,
                    server: point.server,
                    winner: point.winner,
                    serve: point.outcome == .uncategorized ? nil : (point.isSecondServe ? .second : .first),
                    outcome: point.outcome,
                    endingShot: point.endingShot,
                    isBreakPoint: point.isBreakPoint,
                    gameScoreBefore: point.gameScoreAtStart.map {
                        GameScoreLabel.string(for: $0, server: point.server)
                    },
                    matchScoreBefore: scores[point.id]?.label
                ))
            }
        }

        return GamePlanMatch(
            reference: reference,
            startTime: record.startTime,
            endTime: record.endTime,
            competition: GamePlanCompetition(record: record),
            matchFormat: record.matchFormat,
            status: status,
            setScoreLabels: setScoreLabels(record),
            checkpointGameScore: checkpointGameScore(record),
            durationSeconds: MatchDurations.matchElapsedSeconds(record),
            resumeCount: record.resumeEvents.count,
            opponentProfileAtMatch: opponentTag?.profileSummary,
            coverage: coverage,
            recorderFigures: figures(recorderSample, recorderServe),
            opponentFigures: figures(opponentSample, opponentServe),
            scoreStates: recorderSummary.scoreStates.map {
                GamePlanScoreState(label: $0.label, total: $0.total, wins: $0.wins)
            },
            rallyFigures: rallyMetrics.map { GamePlanMetricValue(metric: $0, ratio: $0.ratio(in: recorderSample)) },
            limitations: limitations(record: record, coverage: coverage, status: status),
            points: points,
            note: note,
            recorderSample: recorderSample,
            recorderServeSample: recorderServe,
            opponentSample: opponentSample,
            opponentServeSample: opponentServe
        )
    }

    /// One match's plotted value under the comparison screen's rules.
    static func ratio(_ metric: TrendMetric, all: MatchTrendSample, serve: MatchTrendSample) -> TrendMetric.Ratio? {
        let split = MatchComparison.requiresOutcomeTracking(metric)
        let sample = split ? serve : all
        if split && sample.totalPoints == 0 { return nil }
        return metric.ratio(in: sample)
    }

    /// The pair a match contributes to a pool, or `nil` when it did not
    /// record the metric (no coverage, or a zero denominator).
    static func contribution(_ metric: TrendMetric, all: MatchTrendSample,
                             serve: MatchTrendSample) -> (Int, Int)? {
        let split = MatchComparison.requiresOutcomeTracking(metric)
        let sample = split ? serve : all
        if split && sample.totalPoints == 0 { return nil }
        guard let pair = metric.rawPair(in: sample), pair.denominator > 0 else { return nil }
        return pair
    }

    static func pooled(_ metric: TrendMetric, over matches: [GamePlanMatch], side: Player) -> GamePlanPooledValue {
        var numerator = 0, denominator = 0, contributing = 0
        for match in matches {
            let all = side == .me ? match.recorderSample : match.opponentSample
            let serve = side == .me ? match.recorderServeSample : match.opponentServeSample
            guard let pair = contribution(metric, all: all, serve: serve) else { continue }
            numerator += pair.0
            denominator += pair.1
            contributing += 1
        }
        return GamePlanPooledValue(
            ratio: denominator > 0 ? TrendMetric.Ratio(numerator: numerator, denominator: denominator) : nil,
            contributingMatches: contributing,
            matchesInScope: matches.count
        )
    }

    static func scope(_ title: String, _ matches: [GamePlanMatch], partial: Bool = false) -> GamePlanScopeFigures {
        var rows = sideMetrics.map { metric in
            GamePlanPooledRow(metric: metric,
                              me: pooled(metric, over: matches, side: .me),
                              opponent: pooled(metric, over: matches, side: .opponent))
        }
        rows += rallyMetrics.map { metric in
            GamePlanPooledRow(metric: metric, me: pooled(metric, over: matches, side: .me), opponent: nil)
        }
        return GamePlanScopeFigures(
            title: title,
            references: matches.map(\.reference),
            firstStart: matches.map(\.startTime).min(),
            lastStart: matches.map(\.startTime).max(),
            record: tally(matches),
            pointsSaved: matches.reduce(0) { $0 + $1.coverage.pointsSaved },
            pointsWithOutcome: matches.reduce(0) { $0 + $1.coverage.pointsWithOutcome },
            rows: rows,
            isPartialScope: partial
        )
    }

    static func tally(_ matches: [GamePlanMatch]) -> HeadToHeadRecord {
        let completed = matches.compactMap { match in match.status.result.map { (match, $0) } }
            .sorted { $0.0.startTime != $1.0.startTime ? $0.0.startTime > $1.0.startTime : $0.0.reference > $1.0.reference }
        let results = completed.map(\.1)
        return HeadToHeadRecord(
            wins: results.filter { $0 == .win }.count,
            losses: results.filter { $0 == .loss }.count,
            draws: results.filter { $0 == .draw }.count,
            recentResults: results,
            lastPlayed: completed.map(\.0.startTime).max()
        )
    }

    static func scopes(for matches: [GamePlanMatch]) -> [GamePlanScopeFigures] {
        var scopes: [GamePlanScopeFigures] = []
        let completed = matches.filter { $0.status.isCompleted }
        if !completed.isEmpty {
            scopes.append(scope("All selected completed matches", completed))
        }
        if completed.count > recentScopeCount {
            scopes.append(scope("Latest \(recentScopeCount) completed matches", Array(completed.suffix(recentScopeCount))))
        }
        let checkpoints = matches.filter { !$0.status.isCompleted }
        if !checkpoints.isEmpty {
            scopes.append(scope("In-progress checkpoints (partial evidence)", checkpoints, partial: true))
        }
        return scopes
    }

    /// Per-context figures for every competition present among completed
    /// matches, so a long friendly cannot hide contrary league evidence.
    public var competitionScopes: [GamePlanScopeFigures] {
        competitionRows.compactMap { row in
            let matches = completedMatches.filter { $0.competition == row.competition }
            return matches.isEmpty ? nil : Self.scope("\(row.competition.label) completed matches", matches)
        }
    }

    static func competitionRows(for matches: [GamePlanMatch], upcoming: CompetitionType?) -> [GamePlanCompetitionRow] {
        let upcomingBucket = upcoming.map(GamePlanCompetition.init)
        let buckets = Set(matches.map(\.competition)).sorted { a, b in
            // The upcoming match's own context leads; the rest keep their stable order.
            if a == upcomingBucket { return b != upcomingBucket }
            if b == upcomingBucket { return false }
            return GamePlanCompetition.ordered(a, b)
        }
        return buckets.map { bucket in
            let inBucket = matches.filter { $0.competition == bucket }
            return GamePlanCompetitionRow(
                competition: bucket,
                completedCount: inBucket.filter { $0.status.isCompleted }.count,
                inProgressCount: inBucket.filter { !$0.status.isCompleted }.count,
                record: tally(inBucket),
                pointsSaved: inBucket.reduce(0) { $0 + $1.coverage.pointsSaved },
                references: inBucket.map(\.reference),
                matchesUpcoming: bucket == upcomingBucket
            )
        }
    }

    static func setScoreLabels(_ record: MatchRecord) -> [String] {
        var sets = record.setScores
        if record.isInProgress, sets.count > 1, let last = sets.last,
           last.gamesMe + last.gamesOpponent + last.tieBreakPointsMe + last.tieBreakPointsOpponent == 0 {
            sets.removeLast()
        }
        return sets.enumerated().map { index, set in
            SetScoreLabel.string(for: set, setIndex: index, matchFormat: record.matchFormat)
        }
    }

    static func checkpointGameScore(_ record: MatchRecord) -> String? {
        guard record.isInProgress, record.matchFormat.config.playRegularSets,
              record.setScores.last?.isTieBreak == false else { return nil }
        return MatchRecord.gameScoreString(mePoints: record.currentPointsMe, oppPoints: record.currentPointsOpponent)
    }

    static func limitations(record: MatchRecord, coverage: GamePlanCoverage, status: GamePlanMatchStatus) -> [String] {
        var notes: [String] = []
        if case .inProgress = status {
            notes.append("Saved checkpoint of an unfinished match: partial evidence, excluded from results and head-to-head.")
        }
        if case .completed(_, .stoppedEarly) = status {
            notes.append("Completed before the format's normal finish, so set and game totals are not a full match.")
        }
        if coverage.isScoreOnly {
            notes.append("Score only: no point-by-point data, so it contributes its result but no serve, return, error or pressure figures.")
            return notes
        }
        if record.matchFormat.config.disablesPointTracking {
            notes.append("This format records who won each point but not how it ended.")
        }
        if coverage.pointsWithOutcome == 0 {
            notes.append("No point outcomes were recorded: serve/return splits, winners and errors are not available.")
        } else if coverage.isPartiallyTracked {
            notes.append("Outcomes recorded on \(coverage.pointsWithOutcome) of \(coverage.pointsSaved) saved points; outcome-based figures cover only those.")
        }
        if coverage.pointsWithEndingPhase == 0 {
            notes.append("No ending phase was recorded.")
        } else if coverage.pointsWithEndingPhase < coverage.pointsSaved {
            notes.append("Ending phase recorded on \(coverage.pointsWithEndingPhase) of \(coverage.pointsSaved) saved points.")
        }
        if coverage.pointsWithScoreContext < coverage.pointsSaved {
            notes.append("Score context missing on \(coverage.pointsSaved - coverage.pointsWithScoreContext) saved points.")
        }
        if record.matchFormat != .standard {
            // Format differences matter for any cross-match comparison of totals.
            notes.append("Played as \(GamePlanText.formatLabel(record.matchFormat)); compare rates, not raw game totals, with other formats.")
        }
        return notes
    }
}
