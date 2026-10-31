// MatchTagsFixtures.swift — shared builders for the match-tags test files.
import Foundation
@testable import DeuceMateCore

enum TagFixtures {
    static let base = Date(timeIntervalSince1970: 1_700_000_000)

    /// Deterministic UUID whose `uuidString` sorts by `n`.
    static func uuid(_ n: Int) -> UUID {
        // Test-only fixture; the format string always yields a valid UUID.
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    static func player(_ name: String, id: UUID = UUID()) -> TaggedPlayer {
        TaggedPlayer(id: id, name: name)
    }

    static func tags(
        opponents: [TaggedPlayer] = [],
        partner: TaggedPlayer? = nil,
        competition: CompetitionType? = nil,
        at offset: TimeInterval = 0,
        revision: UUID = UUID()
    ) -> MatchTags {
        MatchTags(
            opponents: opponents,
            partner: partner,
            competitionType: competition,
            updatedAt: base.addingTimeInterval(offset),
            revisionID: revision
        )
    }

    /// A record. `end == nil && iWon == nil` is in progress.
    static func record(
        id: UUID = UUID(),
        start offset: TimeInterval = 0,
        end endOffset: TimeInterval? = 3_600,
        iWon: Bool? = true,
        type: MatchType = .singles,
        format: MatchFormat = .standard,
        tags: MatchTags? = nil,
        stats: [PointStat] = [],
        setScores: [SetScore] = [SetScore(gamesMe: 6, gamesOpponent: 4)]
    ) -> MatchRecord {
        MatchRecord(
            id: id,
            startTime: base.addingTimeInterval(offset),
            endTime: endOffset.map { base.addingTimeInterval(offset + $0) },
            setScores: setScores,
            stats: stats,
            iWon: iWon,
            matchType: type,
            matchFormat: format,
            tags: tags
        )
    }

    /// `count` categorized points served by `server`; the first `won` are won by me.
    static func points(
        _ count: Int,
        won: Int,
        server: Player = .me,
        outcome: PointOutcome = .winner,
        secondServe: Bool = false
    ) -> [PointStat] {
        (0..<count).map { i in
            let winner: Player = i < won ? .me : .opponent
            return PointStat(setIndex: 0, server: server, winner: winner,
                             outcome: outcome, isSecondServe: secondServe)
        }
    }
}
