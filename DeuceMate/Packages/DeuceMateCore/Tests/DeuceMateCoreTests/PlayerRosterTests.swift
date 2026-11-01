// PlayerRosterTests.swift — the derived roster, picker suggestions, roster
// management and head-to-head. MATCH_TAGS_PLAN.md §5, §7.1.
import XCTest
@testable import DeuceMateCore

final class PlayerRosterTests: XCTestCase {

    private typealias F = TagFixtures

    private let alex = TagFixtures.player("Alex", id: TagFixtures.uuid(1))
    private let alex2 = TagFixtures.player("alex", id: TagFixtures.uuid(2))   // a duplicate someone minted
    private let jo = TagFixtures.player("Jo", id: TagFixtures.uuid(3))
    private let sam = TagFixtures.player("Sam", id: TagFixtures.uuid(4))
    private let kim = TagFixtures.player("Kim", id: TagFixtures.uuid(5))

    func test_profileFollowsLatestRevisionAndMutationsAcrossRoles() throws {
        let older = TaggedPlayer(id: alex.id, name: "Alex", age: 30, sexRaw: "male")
        let newer = TaggedPlayer(id: alex.id, name: "Alexandra", age: 31, sexRaw: "future")
        let a = F.record(start: 100, tags: F.tags(opponents: [older], at: 1))
        let b = F.record(start: 0, type: .doubles, tags: F.tags(opponents: [jo], partner: newer, at: 2))
        let records = [a, b]
        let entry = try XCTUnwrap(PlayerRoster.entries(from: records).first { $0.id == alex.id })
        XCTAssertEqual(entry.taggedPlayer, newer)
        XCTAssertEqual(OpponentDirectory.entries(from: records).first?.taggedPlayer, newer)
        let renamed = PlayerRoster.renaming(alex.id, to: "Ali", in: records)
        XCTAssertEqual(renamed.records[0].tags?.opponents.first?.age, 30)
        let updated = PlayerRoster.updatingDetails(alex.id, age: 40, sexRaw: "female", in: records)
        XCTAssertEqual(updated.affectedMatchIDs, [a.id, b.id])
        XCTAssertEqual(updated.records[0].tags?.opponents.first?.name, "Alexandra")
        XCTAssertEqual(updated.records[1].tags?.partner?.name, "Alexandra")
        XCTAssertEqual(PlayerRoster.entries(from: updated.records).first { $0.id == alex.id }?.name, "Alexandra")
        XCTAssertEqual(updated.records[0].tags?.opponents.first?.sex, .female)
        XCTAssertEqual(updated.records[1].tags?.partner?.age, 40)
        let cleared = PlayerRoster.updatingDetails(alex.id, age: nil, sexRaw: nil, in: updated.records)
        XCTAssertNil(cleared.records[0].tags?.opponents.first?.age)
        XCTAssertNil(cleared.records[1].tags?.partner?.sexRaw)
        let duplicate = F.record(tags: F.tags(opponents: [alex2]))
        let merged = PlayerRoster.merging(alex2.id, into: alex.id, in: records + [duplicate])
        XCTAssertEqual(merged.records[2].tags?.opponents.first, newer)
    }

    // MARK: - Roster

    func test_entries_mostRecentFirst_countsDistinctMatchesInAnyRole() {
        let records = [
            F.record(start: 0, tags: F.tags(opponents: [alex])),
            F.record(start: 100, tags: F.tags(opponents: [jo])),
            F.record(start: 200, type: .doubles, tags: F.tags(opponents: [jo, kim], partner: alex)),
            F.record(start: 300, tags: nil),
            F.record(start: 400, tags: F.tags())   // explicitly cleared
        ]
        let entries = PlayerRoster.entries(from: records)
        XCTAssertEqual(entries.first { $0.id == alex.id }?.matchCount, 2, "partner in one, opponent in another")
        XCTAssertEqual(entries.first { $0.id == jo.id }?.matchCount, 2)
        XCTAssertEqual(entries.first { $0.id == alex.id }?.lastPlayed, F.base.addingTimeInterval(200))
        // All three last played at 200 → tie broken by name.
        XCTAssertEqual(entries.map(\.name), ["Alex", "Jo", "Kim"])
    }

    func test_entries_recencyOrder() {
        let records = [
            F.record(start: 0, tags: F.tags(opponents: [jo])),
            F.record(start: 500, tags: F.tags(opponents: [alex])),
            F.record(start: 100, tags: F.tags(opponents: [sam]))
        ]
        XCTAssertEqual(PlayerRoster.entries(from: records).map(\.name), ["Alex", "Sam", "Jo"])
    }

    func test_entries_nameComesFromMostRecentlyUpdatedTag_notMostRecentMatch() {
        let renamed = F.player("Alexandra", id: alex.id)
        let records = [
            F.record(start: 1_000, tags: F.tags(opponents: [alex], at: 10)),     // later match, older tag
            F.record(start: 0, tags: F.tags(opponents: [renamed], at: 50))       // older match, newer tag
        ]
        let entry = PlayerRoster.entries(from: records).first
        XCTAssertEqual(entry?.name, "Alexandra")
        XCTAssertEqual(entry?.lastPlayed, F.base.addingTimeInterval(1_000))
    }

    func test_entries_sameNameDifferentIDsStaySeparate() {
        let otherAlex = F.player("Alex", id: F.uuid(99))
        let entries = PlayerRoster.entries(from: [
            F.record(tags: F.tags(opponents: [alex])), F.record(tags: F.tags(opponents: [otherAlex]))
        ])
        XCTAssertEqual(entries.count, 2)
    }

    // MARK: - Suggestions

    func test_suggestions_emptyQueryReturnsEverything() {
        let entries = PlayerRoster.entries(from: [F.record(tags: F.tags(opponents: [alex, jo]))])
        XCTAssertEqual(PlayerRoster.suggestions("  ", in: entries), entries)
    }

    func test_suggestions_existingNameIsFirst_caseAndDiacriticInsensitive() {
        let zoe = F.player("Zoë", id: F.uuid(20))
        let alexander = F.player("Alexander", id: F.uuid(21))
        let entries = PlayerRoster.entries(from: [
            F.record(start: 300, tags: F.tags(opponents: [alexander])),   // most recent
            F.record(start: 200, tags: F.tags(opponents: [F.player("Big Alex", id: F.uuid(22))])),
            F.record(start: 100, tags: F.tags(opponents: [alex])),
            F.record(start: 50, tags: F.tags(opponents: [zoe, F.player("Malexa", id: F.uuid(23))]))
        ])
        XCTAssertEqual(PlayerRoster.suggestions("ALEX", in: entries).map(\.name),
                       ["Alex", "Alexander", "Big Alex", "Malexa"],
                       "exact, then prefix, then word-prefix, then contains")
        XCTAssertEqual(PlayerRoster.suggestions("zoe", in: entries).map(\.name), ["Zoë"])
        XCTAssertEqual(PlayerRoster.existingEntry(named: " alex ", in: entries)?.id, alex.id)
        XCTAssertNil(PlayerRoster.existingEntry(named: "Nobody", in: entries))
    }

    // MARK: - Roster management

    func test_renaming_rewritesEveryRole_andSupersedesOldCopies() throws {
        let a = F.record(tags: F.tags(opponents: [alex], at: 10))
        let b = F.record(type: .doubles, tags: F.tags(opponents: [jo, kim], partner: alex, at: 10))
        let c = F.record(tags: F.tags(opponents: [jo], at: 10))
        let result = PlayerRoster.renaming(alex.id, to: "  Alexandra ", in: [a, b, c],
                                           now: F.base.addingTimeInterval(5))
        XCTAssertEqual(result.affectedMatchIDs, [a.id, b.id])
        let byID = Dictionary(uniqueKeysWithValues: result.records.map { ($0.id, $0) })
        XCTAssertEqual(byID[a.id]?.tags?.opponents.first?.name, "Alexandra")
        XCTAssertEqual(byID[b.id]?.tags?.partner?.name, "Alexandra")
        XCTAssertEqual(byID[c.id], c, "untouched record keeps its revision")
        let oldTags = try XCTUnwrap(a.tags)
        XCTAssertEqual(byID[a.id]?.tags.map { $0.supersedes(oldTags) }, true,
                       "a stale watch copy cannot undo the rename")
    }

    func test_renaming_toBlankIsRejected() {
        let a = F.record(tags: F.tags(opponents: [alex]))
        XCTAssertEqual(PlayerRoster.renaming(alex.id, to: " \n ", in: [a]).affectedMatchIDs, [])
    }

    func test_merging_rewritesDuplicateToKeptIdentity() {
        let a = F.record(start: 100, tags: F.tags(opponents: [alex]))
        let b = F.record(start: 0, tags: F.tags(opponents: [alex2]))
        let both = F.record(start: 50, type: .doubles, tags: F.tags(opponents: [alex, alex2], partner: sam))
        let result = PlayerRoster.merging(alex2.id, into: alex.id, in: [a, b, both])
        XCTAssertEqual(result.affectedMatchIDs, [b.id, both.id])
        let entries = PlayerRoster.entries(from: result.records)
        XCTAssertEqual(entries.first { $0.id == alex.id }?.matchCount, 3)
        XCTAssertNil(entries.first { $0.id == alex2.id })
        let mergedBoth = result.records.first { $0.id == both.id }
        XCTAssertEqual(mergedBoth?.tags?.opponents, [alex], "a match naming both collapses to one")
        XCTAssertEqual(result.records.first { $0.id == b.id }?.tags?.opponents.first?.name, "Alex")
    }

    func test_merging_intoSelfOrUnknownIsNoOp() {
        let a = F.record(tags: F.tags(opponents: [alex]))
        XCTAssertEqual(PlayerRoster.merging(alex.id, into: alex.id, in: [a]).affectedMatchIDs, [])
        XCTAssertEqual(PlayerRoster.merging(alex.id, into: UUID(), in: [a]).affectedMatchIDs, [])
    }

    func test_forgetting_removesFromEveryRoleWithNewerRevisions() {
        let a = F.record(tags: F.tags(opponents: [alex], competition: .league, at: 10))
        let b = F.record(type: .doubles, tags: F.tags(opponents: [jo, kim], partner: alex, at: 10))
        let result = PlayerRoster.forgetting(alex.id, in: [a, b], now: F.base.addingTimeInterval(20))
        XCTAssertEqual(result.affectedMatchIDs, [a.id, b.id])
        XCTAssertTrue(result.records.allSatisfy { !($0.tags?.playerIDs.contains(alex.id) ?? false) })
        let clearedA = result.records.first { $0.id == a.id }?.tags
        XCTAssertEqual(clearedA?.competitionType, .league)
        XCTAssertEqual(clearedA?.updatedAt, F.base.addingTimeInterval(20))
        XCTAssertNil(PlayerRoster.entries(from: result.records).first { $0.id == alex.id })
    }

    // MARK: - Head-to-head

    func test_headToHead_singles_completedOnly_excludingCurrent() {
        let current = F.record(start: 500, end: nil, iWon: nil, tags: F.tags(opponents: [alex]))
        let records = [
            current,
            F.record(start: 100, iWon: true, tags: F.tags(opponents: [alex])),
            F.record(start: 200, iWon: false, tags: F.tags(opponents: [alex])),
            F.record(start: 300, end: 60, iWon: nil, tags: F.tags(opponents: [alex])),   // completed draw
            F.record(start: 400, end: nil, iWon: nil, tags: F.tags(opponents: [alex])),  // other live match
            F.record(start: 450, iWon: true, tags: F.tags(opponents: [jo]))
        ]
        let h2h = HeadToHead.record(vs: alex.id, in: records, excluding: current.id)
        XCTAssertEqual(h2h.wins, 1)
        XCTAssertEqual(h2h.losses, 1)
        XCTAssertEqual(h2h.draws, 1)
        XCTAssertEqual(h2h.played, 3)
        XCTAssertEqual(h2h.recentResults, [.draw, .loss, .win], "newest first")
        XCTAssertEqual(h2h.lastPlayed, F.base.addingTimeInterval(300))
        XCTAssertEqual(HeadToHead.record(for: current, in: records), h2h)
    }

    func test_headToHead_keepsSinglesAndDoublesSeparate_andIgnoresPartnerAppearances() {
        let records = [
            F.record(iWon: true, tags: F.tags(opponents: [alex])),
            F.record(iWon: false, type: .doubles, tags: F.tags(opponents: [alex, jo], partner: sam)),
            F.record(iWon: true, type: .doubles, tags: F.tags(opponents: [jo, kim], partner: alex))
        ]
        XCTAssertEqual(HeadToHead.record(vs: alex.id, in: records, excluding: nil).played, 1)
        let doubles = HeadToHead.record(vs: alex.id, in: records, excluding: nil, matchType: .doubles)
        XCTAssertEqual(doubles.losses, 1)
        XCTAssertEqual(doubles.played, 1, "playing WITH Alex is not playing against Alex")
    }

    func test_headToHead_doublesTeamIdentity_unorderedPairSamePartner() {
        let team = Matchup(matchType: .doubles, opponentIDs: [alex.id, jo.id], partnerID: sam.id)
        let records = [
            F.record(iWon: true, type: .doubles, tags: F.tags(opponents: [jo, alex], partner: sam)),  // reversed order
            F.record(iWon: true, type: .doubles, tags: F.tags(opponents: [alex, jo], partner: kim)),  // other partner
            F.record(iWon: true, type: .doubles, tags: F.tags(opponents: [alex, kim], partner: sam))  // other pair
        ]
        XCTAssertEqual(HeadToHead.record(for: team, in: records, excluding: nil).played, 1)
    }

    func test_headToHead_incompleteIdentityHasNoRecord() {
        XCTAssertNil(HeadToHead.record(for: F.record(tags: nil), in: []))
        XCTAssertNil(HeadToHead.record(for: F.record(type: .doubles, tags: F.tags(opponents: [alex, jo])), in: []),
                     "doubles without a partner is not a complete team identity")
        XCTAssertEqual(HeadToHead.record(vs: alex.id, in: [], excluding: nil), .empty)
    }

    func test_matchResult_neverInferredForInProgress() {
        XCTAssertNil(MatchResult(record: F.record(end: nil, iWon: nil)))
        XCTAssertEqual(MatchResult(record: F.record(iWon: true)), .win)
        XCTAssertEqual(MatchResult(record: F.record(iWon: false)), .loss)
        XCTAssertEqual(MatchResult(record: F.record(end: 10, iWon: nil)), .draw)
        XCTAssertEqual([MatchResult.win, .loss, .draw].map(\.shortLabel), ["W", "L", "D"])
    }
}
