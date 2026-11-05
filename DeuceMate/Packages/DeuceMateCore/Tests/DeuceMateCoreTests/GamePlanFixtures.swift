// GamePlanFixtures.swift — deterministic, fictional matches for the Opponent
// Game Plan tests. Matches are played through the real ScoringEngine so game
// scores, break points and set scores are internally consistent.
import Foundation
@testable import DeuceMateCore

/// Small deterministic generator (SplitMix64) so fixtures never change.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum GamePlanFixtures {
    static let opponentID = TagFixtures.uuid(9_001)
    static let otherOpponentID = TagFixtures.uuid(9_002)
    static let partnerID = TagFixtures.uuid(9_003)
    static let day: TimeInterval = 86_400

    static func opponent(_ name: String = "Alex Rivera", id: UUID = opponentID,
                         handedness: PlayerHandedness? = .leftHanded) -> TaggedPlayer {
        TaggedPlayer(id: id, name: name, handednessRaw: handedness?.rawValue,
                     backhandRaw: PlayerBackhand.oneHanded.rawValue)
    }

    static func tags(opponents: [TaggedPlayer] = [opponent()], partner: TaggedPlayer? = nil,
                     competitionRaw: String? = nil) -> MatchTags {
        MatchTags(opponents: opponents, partner: partner, competitionTypeRaw: competitionRaw,
                  updatedAt: TagFixtures.base, revisionID: TagFixtures.uuid(1))
    }

    /// A completed singles match against the fixture opponent, played point by
    /// point. `serveWinBias` tilts how often the server wins.
    static func simulatedMatch(
        id: UUID = UUID(),
        seed: UInt64,
        startDay: Double,
        competition: CompetitionType? = nil,
        competitionRaw: String? = nil,
        opponents: [TaggedPlayer] = [opponent()],
        format: MatchFormat = .standard,
        outcomeCoverage: Double = 1.0,
        withHealth: Bool = true,
        stopAfterPoints: Int? = nil
    ) -> MatchRecord {
        var rng = SeededGenerator(seed: seed)
        let start = TagFixtures.base.addingTimeInterval(startDay * day)
        var state = ScoringState(currentServer: .me, matchFormat: format)
        var stats: [PointStat] = []
        var steps = 0
        let outcomes: [PointOutcome] = [.winner, .unforcedError, .forcedError]
        let shots: [EndingShot] = [.serve, .return, .servePlusOne, .rally]
        while !ScoringEngine.isMatchComplete(state), stats.count < (stopAfterPoints ?? 600) {
            guard let server = state.currentServer else { break }
            let snapshot = ScoringEngine.gameScoreSnapshotAtPointStart(state)
            let isBreakPoint = ScoringEngine.isCurrentPointBreakPoint(state)
            let secondServe = Double.random(in: 0..<1, using: &rng) < 0.35
            let doubleFault = secondServe && Double.random(in: 0..<1, using: &rng) < 0.12
            let serverWins = Double.random(in: 0..<1, using: &rng) < (secondServe ? 0.5 : 0.62)
            let winner: Player = doubleFault ? (server == .me ? .opponent : .me) : (serverWins ? server : (server == .me ? .opponent : .me))
            let tracked = Double.random(in: 0..<1, using: &rng) < outcomeCoverage
            let outcome: PointOutcome = !tracked ? .uncategorized
                : (doubleFault ? .doubleFault : outcomes[Int.random(in: 0..<outcomes.count, using: &rng)])
            let shot: EndingShot? = !tracked ? nil : (doubleFault ? .serve : shots[Int.random(in: 0..<shots.count, using: &rng)])
            steps += Int.random(in: 4...30, using: &rng)
            stats.append(PointStat(
                timestamp: start.addingTimeInterval(Double(stats.count) * 40),
                setIndex: state.sets.count - 1,
                server: server,
                winner: winner,
                outcome: outcome,
                isSecondServe: secondServe,
                isBreakPoint: isBreakPoint,
                endingShot: shot,
                gameScoreAtStart: snapshot,
                heartRateBPM: withHealth ? Int.random(in: 120...175, using: &rng) : nil,
                stepsCumulative: withHealth ? steps : nil
            ))
            state = ScoringEngine.pointWon(by: winner, in: state).state
        }
        let completed = ScoringEngine.isMatchComplete(state)
        let winner = ScoringEngine.matchWinner(state)
        var tags = Self.tags(opponents: opponents, competitionRaw: competitionRaw ?? competition?.rawValue)
        tags.updatedAt = start
        return MatchRecord(
            id: id,
            startTime: start,
            endTime: completed ? start.addingTimeInterval(Double(stats.count) * 40 + 60) : nil,
            setScores: state.sets,
            stats: stats,
            iWon: completed ? winner.map { $0 == .me } : nil,
            currentPointsMe: state.currentPointsMe,
            currentPointsOpponent: state.currentPointsOpponent,
            currentServer: state.currentServer,
            matchType: .singles,
            matchFormat: format,
            matchElapsedSeconds: Double(stats.count) * 40,
            totalSteps: withHealth ? steps : nil,
            totalDistanceMeters: withHealth ? Double(steps) * 0.7 : nil,
            totalCaloriesKcal: withHealth ? Double(stats.count) * 1.4 : nil,
            tags: tags
        )
    }

    /// A score-only completed match (manual entry): sets but no points.
    static func scoreOnly(id: UUID = UUID(), startDay: Double, iWon: Bool = false,
                          competition: CompetitionType? = nil) -> MatchRecord {
        let start = TagFixtures.base.addingTimeInterval(startDay * day)
        return MatchRecord(
            id: id, startTime: start, endTime: start.addingTimeInterval(5_400),
            setScores: [SetScore(gamesMe: iWon ? 6 : 3, gamesOpponent: iWon ? 3 : 6),
                        SetScore(gamesMe: iWon ? 6 : 2, gamesOpponent: iWon ? 2 : 6)],
            stats: [], iWon: iWon,
            tags: tags(competitionRaw: competition?.rawValue)
        )
    }

    static func roster(_ records: [MatchRecord], id: UUID = opponentID) -> RosterEntry? {
        PlayerRoster.entries(from: records).first { $0.id == id }
    }

    static func evidence(
        _ records: [MatchRecord],
        selection: GamePlanSelection = GamePlanSelection(),
        upcoming: GamePlanUpcomingMatch = GamePlanUpcomingMatch(),
        notes: [UUID: String] = [:],
        includeNotes: Bool = false,
        omitted: Set<UUID> = [],
        includeNames: Bool = false,
        detail: GamePlanDetailMode = .full,
        includeInProgress: Bool = false
    ) throws -> GamePlanEvidence {
        let candidates = GamePlanEligibility.candidates(for: opponentID, in: records,
                                                         includeInProgress: includeInProgress)
        let selected = selection.resolve(candidates)
        return try GamePlanEvidence(
            opponentID: opponentID,
            opponent: roster(records),
            selected: selected,
            candidateCounts: candidates.counts,
            availableCount: selection.filtered(candidates).count,
            upcoming: upcoming,
            notes: notes,
            includeNotes: includeNotes,
            omittedNoteMatchIDs: omitted,
            includeNames: includeNames,
            detailMode: detail,
            builtAt: TagFixtures.base.addingTimeInterval(400 * day)
        )
    }

    static let utc = TimeZone(identifier: "UTC") ?? .current
}
