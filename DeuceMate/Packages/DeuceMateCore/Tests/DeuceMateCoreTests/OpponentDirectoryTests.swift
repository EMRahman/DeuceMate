import XCTest
@testable import DeuceMateCore

final class OpponentDirectoryTests: XCTestCase {
    func testEntriesAreOpponentOnlyAndKeepDistinctIdentitiesWithSameName() {
        let opponentA = TagFixtures.uuid(1)
        let opponentB = TagFixtures.uuid(2)
        let partnerOnly = TagFixtures.uuid(3)
        let records = [
            TagFixtures.record(id: TagFixtures.uuid(10), start: 2,
                               tags: TagFixtures.tags(opponents: [TagFixtures.player("Alex", id: opponentA)],
                                                      partner: TagFixtures.player("Partner", id: partnerOnly))),
            TagFixtures.record(id: TagFixtures.uuid(11), start: 1,
                               tags: TagFixtures.tags(opponents: [TagFixtures.player("Alex", id: opponentB)]))
        ]

        let entries = OpponentDirectory.entries(from: records)
        XCTAssertEqual(entries.map(\.id), [opponentA, opponentB])
        XCTAssertEqual(entries.map(\.name), ["Alex", "Alex"])
        XCTAssertEqual(entries.map(\.matchCount), [1, 1])
        XCTAssertFalse(entries.contains { $0.id == partnerOnly })
    }

    func testEqualDatesSortByNameThenIDAndRepeatedOpponentCountsOncePerMatch() {
        let alexA = TagFixtures.uuid(1), alexB = TagFixtures.uuid(2), zoe = TagFixtures.uuid(3)
        let records = [
            TagFixtures.record(id: TagFixtures.uuid(10), start: 1,
                tags: TagFixtures.tags(opponents: [TagFixtures.player("Zoe", id: zoe)])),
            TagFixtures.record(id: TagFixtures.uuid(11), start: 1,
                tags: TagFixtures.tags(opponents: [TagFixtures.player("Alex", id: alexB),
                                                   TagFixtures.player("Alex", id: alexA),
                                                   TagFixtures.player("Alex", id: alexA)])),
            TagFixtures.record(id: TagFixtures.uuid(12), start: 2,
                tags: TagFixtures.tags(opponents: [TagFixtures.player("Alex", id: alexA),
                                                   TagFixtures.player("Alex", id: alexA)]))
        ]

        let entries = OpponentDirectory.entries(from: records)
        XCTAssertEqual(entries.map(\.id), [alexA, alexB, zoe])
        XCTAssertEqual(entries.map(\.matchCount), [2, 1, 1], "duplicate tags count once per match")
        XCTAssertEqual(entries[0].lastPlayed, records[2].startTime)
    }

    func testDirectoryCountsEachOpponentInAnIncompleteSinglesIdentity() {
        let a = TagFixtures.uuid(1), b = TagFixtures.uuid(2)
        let record = TagFixtures.record(tags: TagFixtures.tags(opponents: [
            TagFixtures.player("A", id: a), TagFixtures.player("B", id: b)
        ]))

        XCTAssertEqual(OpponentDirectory.entries(from: [record]).map(\.id), [a, b])
        XCTAssertNil(Matchup(record: record), "a malformed singles opponent list is not a complete H2H identity")
    }

    func testNameUsesLatestIdentityRevisionEvenWhenLatestAppearanceIsPartner() throws {
        let id = TagFixtures.uuid(1)
        let old = TagFixtures.record(start: 1,
            tags: TagFixtures.tags(opponents: [TagFixtures.player("Old", id: id)], at: 1))
        let latest = TagFixtures.record(start: 2,
            tags: TagFixtures.tags(partner: TagFixtures.player("Renamed", id: id), at: 2))

        let entry = try XCTUnwrap(OpponentDirectory.entries(from: [old, latest]).first)
        XCTAssertEqual(entry.name, "Renamed")
        XCTAssertEqual(entry.matchCount, 1)
        XCTAssertEqual(entry.lastPlayed, old.startTime)
    }

    func testForgottenPlayersAreExcludedAndInProgressOppositionIsCounted() {
        let forgottenID = TagFixtures.uuid(1)
        let activeID = TagFixtures.uuid(2)
        let record = TagFixtures.record(start: 4, end: nil, iWon: nil,
            tags: TagFixtures.tags(opponents: [TagFixtures.player("Hidden", id: forgottenID),
                                               TagFixtures.player("Active", id: activeID)]))

        let entries = OpponentDirectory.entries(from: [record],
            forgotten: ForgottenPlayerLedger().forgetting(forgottenID))
        XCTAssertEqual(entries.map(\.id), [activeID])
        XCTAssertEqual(entries[0].matchCount, 1)
        XCTAssertNil(MatchResult(record: record))
    }

    func testDoublesMatchupsDeduplicateSwappedPairsAndKeepPartnerGroupsSeparate() {
        let a = TagFixtures.uuid(1), b = TagFixtures.uuid(2)
        let partner1 = TagFixtures.uuid(3), partner2 = TagFixtures.uuid(4)
        let single = TagFixtures.record(start: 10, tags: TagFixtures.tags(opponents: [TagFixtures.player("A", id: a)]))
        func doubles(_ n: Int, _ offset: TimeInterval, _ opponents: [UUID], _ partner: UUID?) -> MatchRecord {
            TagFixtures.record(id: TagFixtures.uuid(n), start: offset, type: .doubles,
                tags: TagFixtures.tags(opponents: opponents.map { TagFixtures.player("P", id: $0) },
                                       partner: partner.map { TagFixtures.player("Partner", id: $0) }))
        }
        let olderGroup = doubles(20, 1, [a, b], partner1)
        let swappedRepeat = doubles(21, 2, [b, a], partner1)
        let otherGroup = doubles(22, 3, [a, b], partner2)
        let incomplete = doubles(23, 20, [a, b], nil)

        let matchups = OpponentDirectory.doublesMatchups(vs: a,
            in: [single, olderGroup, swappedRepeat, otherGroup, incomplete])
        XCTAssertEqual(matchups.count, 2)
        XCTAssertEqual(matchups.map(\.partnerID), [partner2, partner1])
        XCTAssertEqual(matchups[0].opponentIDs, Set([a, b]))
    }

    func testHeadToHeadSeparatesSinglesAndDoublesAndExcludesInProgressResults() {
        let opponent = TagFixtures.uuid(1), secondOpponent = TagFixtures.uuid(2)
        let partner = TagFixtures.uuid(3)
        let records = [
            TagFixtures.record(id: TagFixtures.uuid(10), start: 1, iWon: true,
                tags: TagFixtures.tags(opponents: [TagFixtures.player("Opponent", id: opponent)])),
            TagFixtures.record(id: TagFixtures.uuid(11), start: 2, iWon: false,
                tags: TagFixtures.tags(opponents: [TagFixtures.player("Opponent", id: opponent)])),
            TagFixtures.record(id: TagFixtures.uuid(12), start: 3, end: 60, iWon: nil,
                tags: TagFixtures.tags(opponents: [TagFixtures.player("Opponent", id: opponent)])),
            TagFixtures.record(id: TagFixtures.uuid(13), start: 4, end: nil, iWon: nil,
                tags: TagFixtures.tags(opponents: [TagFixtures.player("Opponent", id: opponent)])),
            TagFixtures.record(id: TagFixtures.uuid(14), start: 5, iWon: false, type: .doubles,
                tags: TagFixtures.tags(opponents: [TagFixtures.player("Opponent", id: opponent),
                                                   TagFixtures.player("Second", id: secondOpponent)],
                                       partner: TagFixtures.player("Partner", id: partner))),
            TagFixtures.record(id: TagFixtures.uuid(15), start: 6, iWon: true, type: .doubles,
                tags: TagFixtures.tags(opponents: [TagFixtures.player("Opponent", id: opponent),
                                                   TagFixtures.player("Second", id: secondOpponent)],
                                       partner: TagFixtures.player("Partner", id: partner))),
            TagFixtures.record(id: TagFixtures.uuid(16), start: 7, end: 60, iWon: nil, type: .doubles,
                tags: TagFixtures.tags(opponents: [TagFixtures.player("Opponent", id: opponent),
                                                   TagFixtures.player("Second", id: secondOpponent)],
                                       partner: TagFixtures.player("Partner", id: partner)))
        ]

        let singles = HeadToHead.record(vs: opponent, in: records, excluding: nil, matchType: .singles)
        XCTAssertEqual(singles.wins, 1)
        XCTAssertEqual(singles.losses, 1)
        XCTAssertEqual(singles.draws, 1)
        XCTAssertEqual(singles.played, 3, "the live singles checkpoint has no result")
        let doubles = HeadToHead.record(vs: opponent, in: records, excluding: nil, matchType: .doubles)
        XCTAssertEqual(doubles.wins, 1)
        XCTAssertEqual(doubles.losses, 1)
        XCTAssertEqual(doubles.draws, 1)
        XCTAssertEqual(doubles.played, 3, "the live doubles checkpoint has no result")
    }
}
