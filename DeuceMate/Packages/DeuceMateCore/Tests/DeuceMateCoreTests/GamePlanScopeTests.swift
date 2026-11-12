// GamePlanScopeTests.swift — Opponent Game Plan eligibility and selection
// (OPPONENT_GAME_PLAN_PROPOSAL.md §4, §9).
import XCTest
@testable import DeuceMateCore

final class GamePlanScopeTests: XCTestCase {
    private typealias F = GamePlanFixtures

    private func singles(_ day: Double, id: UUID = UUID(), opponents: [TaggedPlayer] = [F.opponent()],
                         competition: CompetitionType? = nil, raw: String? = nil,
                         inProgress: Bool = false) -> MatchRecord {
        let start = TagFixtures.base.addingTimeInterval(day * F.day)
        return MatchRecord(id: id, startTime: start, endTime: inProgress ? nil : start.addingTimeInterval(3_600),
                           setScores: [SetScore(gamesMe: 6, gamesOpponent: 4)], stats: [],
                           iWon: inProgress ? nil : true,
                           tags: F.tags(opponents: opponents, competitionRaw: raw ?? competition?.rawValue))
    }

    private func candidates(_ records: [MatchRecord], includeInProgress: Bool = false,
                            forgotten: ForgottenPlayerLedger = ForgottenPlayerLedger()) -> GamePlanCandidates {
        GamePlanEligibility.candidates(for: F.opponentID, in: records, forgotten: forgotten,
                                       includeInProgress: includeInProgress)
    }

    // MARK: Default count

    func test_defaultSelection_isLatestFive() {
        let selection = GamePlanSelection()
        XCTAssertEqual(selection.mode, .latest(5))
        XCTAssertEqual(selection.label, "Last 5")
    }

    func test_zeroEligible_resolvesEmpty() {
        let c = candidates([])
        XCTAssertTrue(GamePlanSelection().resolve(c).isEmpty)
        XCTAssertTrue(GamePlanSelection(mode: .all).resolve(c).isEmpty)
    }

    func test_fewerThanFive_takesAllAvailable() {
        let records = (0..<3).map { singles(Double($0)) }
        XCTAssertEqual(GamePlanSelection().resolve(candidates(records)).count, 3)
    }

    func test_exactlyFive_takesAll() {
        let records = (0..<5).map { singles(Double($0)) }
        XCTAssertEqual(GamePlanSelection().resolve(candidates(records)).count, 5)
    }

    func test_moreThanTen_lastFiveLastTenCustomAndAll() {
        let records = (0..<14).map { singles(Double($0)) }
        let c = candidates(records)
        let newestFirst = records.sorted { $0.startTime > $1.startTime }.map(\.id)
        XCTAssertEqual(GamePlanSelection().resolve(c).map(\.id), Array(newestFirst.prefix(5)))
        XCTAssertEqual(GamePlanSelection(mode: .latest(10)).resolve(c).map(\.id), Array(newestFirst.prefix(10)))
        XCTAssertEqual(GamePlanSelection(mode: .latest(7)).resolve(c).count, 7)
        XCTAssertEqual(GamePlanSelection(mode: .all).resolve(c).count, 14)
        XCTAssertEqual(GamePlanSelection(mode: .latest(7)).label, "Last 7")
    }

    func test_allMatches_includesHistoryOlderThanTheWatchCap() {
        let records = (0..<(WatchHistory.cap + 15)).map { singles(Double($0)) }
        XCTAssertEqual(GamePlanSelection(mode: .all).resolve(candidates(records)).count, WatchHistory.cap + 15)
    }

    func test_clampedCount() {
        XCTAssertEqual(GamePlanSelection.clampedCount(0, available: 8), 1)
        XCTAssertEqual(GamePlanSelection.clampedCount(12, available: 8), 8)
        XCTAssertEqual(GamePlanSelection.clampedCount(3, available: 0), 1)
    }

    // MARK: Ordering

    func test_tiedStartTimes_breakTiesByUUIDDeterministically() {
        let a = singles(1, id: TagFixtures.uuid(2))
        let b = singles(1, id: TagFixtures.uuid(1))
        let c = singles(0, id: TagFixtures.uuid(3))
        let forward = candidates([a, b, c]).eligible.map(\.id)
        let reversed = candidates([c, b, a]).eligible.map(\.id)
        XCTAssertEqual(forward, [TagFixtures.uuid(1), TagFixtures.uuid(2), TagFixtures.uuid(3)])
        XCTAssertEqual(forward, reversed)
    }

    func test_ordersByStartTimeNotFinishTime() {
        // Started earlier but finished later: still older by start time.
        let start = TagFixtures.base
        let longMatch = MatchRecord(startTime: start, endTime: start.addingTimeInterval(10 * F.day),
                                    setScores: [], stats: [], iWon: true, tags: F.tags())
        let later = singles(1)
        XCTAssertEqual(candidates([longMatch, later]).eligible.map(\.id), [later.id, longMatch.id])
    }

    // MARK: Filters

    func test_filterAppliesBeforeTheLimit() {
        var records = (0..<6).map { singles(Double($0), competition: .friendly) }
        records += (10..<13).map { singles(Double($0), competition: .league) }
        let c = candidates(records)
        let selection = GamePlanSelection(mode: .latest(5), filter: GamePlanFilter(competitions: [.friendly]))
        let resolved = selection.resolve(c)
        // The latest five FRIENDLIES, even though three newer leagues exist.
        XCTAssertEqual(resolved.count, 5)
        XCTAssertTrue(resolved.allSatisfy { GamePlanCompetition(record: $0) == .friendly })
    }

    func test_dateFilter_isInclusiveOfWholeDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = F.utc
        let records = (0..<10).map { singles(Double($0)) }
        let from = TagFixtures.base.addingTimeInterval(3 * F.day)
        let through = TagFixtures.base.addingTimeInterval(5 * F.day)
        let filter = GamePlanFilter(from: from, through: through)
        let selected = GamePlanSelection(mode: .all, filter: filter).resolve(candidates(records), calendar: calendar)
        XCTAssertEqual(selected.count, 3)
    }

    func test_customSelection_filterChangeIntersectsWithoutAdding() {
        let friendly = (0..<4).map { singles(Double($0), competition: .friendly) }
        let league = (10..<12).map { singles(Double($0), competition: .league) }
        let c = candidates(friendly + league)
        var selection = GamePlanSelection(mode: .custom([friendly[0].id, league[0].id]))
        selection.setFilter(GamePlanFilter(competitions: [.league]), candidates: c)
        XCTAssertEqual(selection.mode, .custom([league[0].id]))
        selection.setFilter(.none, candidates: c)
        // Clearing the filter does not bring the dropped friendly back.
        XCTAssertEqual(selection.resolve(c).map(\.id), [league[0].id])
    }

    func test_countPreset_recomputesAfterFilterChange() {
        let friendly = (0..<4).map { singles(Double($0), competition: .friendly) }
        let league = (10..<12).map { singles(Double($0), competition: .league) }
        let c = candidates(friendly + league)
        var selection = GamePlanSelection()
        XCTAssertEqual(selection.resolve(c).count, 5)
        selection.setFilter(GamePlanFilter(competitions: [.league]), candidates: c)
        XCTAssertEqual(selection.mode, .latest(5))
        XCTAssertEqual(selection.resolve(c).count, 2)
    }

    func test_toggle_switchesToCustomSeededFromCurrentSelection() throws {
        let records = (0..<8).map { singles(Double($0)) }
        let c = candidates(records)
        var selection = GamePlanSelection()
        let before = selection.resolve(c).map(\.id)
        let oldest = try XCTUnwrap(c.eligible.last).id
        selection.toggle(oldest, candidates: c)
        XCTAssertEqual(selection.label, "Custom selection")
        XCTAssertEqual(Set(selection.resolve(c).map(\.id)), Set(before + [oldest]))
        selection.toggle(before[0], candidates: c)
        XCTAssertFalse(selection.resolve(c).contains { $0.id == before[0] })
    }

    func test_customSelection_dropsDeletedMatches() {
        let records = (0..<4).map { singles(Double($0)) }
        let selection = GamePlanSelection(mode: .custom(Set(records.map(\.id))))
        let afterDelete = candidates(Array(records.dropFirst()))
        XCTAssertEqual(selection.resolve(afterDelete).count, 3)
    }

    // MARK: Identity

    func test_partnerAppearance_isNotOpposition() {
        let asPartner = MatchRecord(startTime: TagFixtures.base, endTime: TagFixtures.base, setScores: [], stats: [],
                                    iWon: true, matchType: .doubles,
                                    tags: F.tags(opponents: [F.opponent("X", id: F.otherOpponentID), F.opponent("Y", id: TagFixtures.uuid(77))],
                                                 partner: F.opponent()))
        let c = candidates([asPartner])
        XCTAssertTrue(c.eligible.isEmpty)
        XCTAssertTrue(c.excludedDoubles.isEmpty, "a partner appearance is not even an excluded opposition match")
    }

    func test_sameNameDifferentPlayer_staysDistinct() {
        let impostor = singles(1, opponents: [F.opponent("Alex Rivera", id: F.otherOpponentID)])
        let real = singles(2)
        XCTAssertEqual(candidates([impostor, real]).eligible.map(\.id), [real.id])
    }

    func test_unrelatedOpponentsAndUntaggedMatches() {
        let unrelated = singles(1, opponents: [F.opponent("Sam", id: F.otherOpponentID)])
        var untagged = singles(2)
        untagged.tags = nil
        let c = candidates([unrelated, untagged, singles(3)])
        XCTAssertEqual(c.eligible.count, 1)
        XCTAssertEqual(c.untaggedSinglesCount, 1)
    }

    func test_duplicateRecords_areCollapsedByUUID() {
        let record = singles(1)
        XCTAssertEqual(candidates([record, record]).eligible.count, 1)
    }

    func test_doublesAgainstPlayer_areExcludedWithReason() {
        let doubles = MatchRecord(startTime: TagFixtures.base, endTime: TagFixtures.base, setScores: [], stats: [],
                                  iWon: true, matchType: .doubles,
                                  tags: F.tags(opponents: [F.opponent(), F.opponent("Y", id: F.otherOpponentID)],
                                               partner: F.opponent("P", id: F.partnerID)))
        let c = candidates([doubles, singles(1)])
        XCTAssertEqual(c.eligible.count, 1)
        XCTAssertEqual(c.excludedDoubles.map(\.id), [doubles.id])
    }

    func test_forgottenPlayer_hasNoEvidence() {
        let c = candidates([singles(1)], forgotten: ForgottenPlayerLedger(playerIDs: [F.opponentID]))
        XCTAssertTrue(c.eligible.isEmpty)
    }

    func test_inProgress_excludedByDefault_includedOnRequest() {
        let checkpoint = singles(5, inProgress: true)
        let done = singles(1)
        let off = candidates([checkpoint, done])
        XCTAssertEqual(off.eligible.map(\.id), [done.id])
        XCTAssertEqual(off.excludedInProgress.map(\.id), [checkpoint.id])
        let on = candidates([checkpoint, done], includeInProgress: true)
        XCTAssertEqual(on.eligible.map(\.id), [checkpoint.id, done.id])
        XCTAssertTrue(on.excludedInProgress.isEmpty)
        XCTAssertEqual(on.completedEligibleCount, 1)
    }

    func test_completedDrawIsEligible() {
        var draw = singles(1)
        draw.iWon = nil
        XCTAssertFalse(draw.isInProgress)
        XCTAssertEqual(candidates([draw]).eligible.count, 1)
    }

    // MARK: Competition buckets

    func test_competitionBuckets_keepUnknownApartFromUnspecified() {
        XCTAssertEqual(GamePlanCompetition(raw: nil), .unspecified)
        XCTAssertEqual(GamePlanCompetition(raw: ""), .unspecified)
        XCTAssertEqual(GamePlanCompetition(raw: "league"), .league)
        XCTAssertEqual(GamePlanCompetition(raw: "exhibition"), .unrecognized("exhibition"))
        XCTAssertNotEqual(GamePlanCompetition(raw: "exhibition"), .friendly)
        XCTAssertEqual(GamePlanCompetition(raw: "exhibition").label, "Unrecognised type")
    }

    func test_competitionFilter_matchesUnknownValuesExactly() {
        let unknown = singles(1, raw: "exhibition")
        let unset = singles(2)
        let c = candidates([unknown, unset])
        let selection = GamePlanSelection(mode: .all, filter: GamePlanFilter(competitions: [.unspecified]))
        XCTAssertEqual(selection.resolve(c).map(\.id), [unset.id])
    }

    // MARK: Upcoming context

    func test_upcoming_startsUnset_andSanitizesPreparationText() {
        var upcoming = GamePlanUpcomingMatch()
        XCTAssertNil(upcoming.competition)
        XCTAssertNil(upcoming.format)
        XCTAssertNil(upcoming.date)
        XCTAssertNil(upcoming.sanitizedPreparationText)
        upcoming.preparationText = "  Clay court \u{202E}windy  \n"
        XCTAssertEqual(upcoming.sanitizedPreparationText, "Clay court windy")
        upcoming.preparationText = String(repeating: "a", count: 2_000)
        XCTAssertEqual(upcoming.sanitizedPreparationText?.count, GamePlanUpcomingMatch.maxPreparationLength)
    }

    func test_latestMatch_isNewestSinglesAgainstOpponent_evenWhenUnfinishedIsNotEvidence() {
        let older = singles(1, competition: .league)
        let unfinished = singles(5, competition: .friendly, inProgress: true)
        let otherOpponent = singles(9, opponents: [F.opponent("Sam", id: F.otherOpponentID)], competition: .tournament)
        var doubles = singles(10, competition: .practice)
        doubles.matchType = .doubles
        let c = candidates([older, unfinished, otherOpponent, doubles])
        XCTAssertEqual(c.eligible.map(\.id), [older.id], "Unfinished stays out of the evidence")
        XCTAssertEqual(c.latestMatch?.id, unfinished.id, "…but is still the previous match")
        XCTAssertEqual(candidates([older, unfinished], includeInProgress: true).latestMatch?.id, unfinished.id)
        XCTAssertNil(candidates([otherOpponent, doubles]).latestMatch, "Other opponents and doubles never pre-fill")
        XCTAssertNil(candidates([older], forgotten: ForgottenPlayerLedger(playerIDs: [F.opponentID])).latestMatch,
                     "A forgotten player pre-fills nothing")
    }

    func test_prefill_copiesCompetitionAndFormatOnly() {
        var league = singles(1, competition: .league)
        league.matchFormat = .bestOf3FullFinalSet
        let upcoming = GamePlanUpcomingMatch(prefilledFrom: league)
        XCTAssertEqual(upcoming.competition, .league)
        XCTAssertEqual(upcoming.format, .bestOf3FullFinalSet)
        XCTAssertNil(upcoming.date)
        XCTAssertNil(upcoming.sanitizedPreparationText)
        XCTAssertNil(upcoming.finishingMatchID, "A completed previous match means a new match next")
    }

    func test_prefill_fromUnfinishedMatch_finishesIt() {
        let unfinished = singles(3, competition: .league, inProgress: true)
        let upcoming = GamePlanUpcomingMatch(prefilledFrom: unfinished)
        XCTAssertEqual(upcoming.finishingMatchID, unfinished.id)
        XCTAssertEqual(upcoming.competition, .league)
    }

    func test_unfinishedMatches_newestFirst_whetherOrNotOptedIn() {
        let old = singles(1, inProgress: true), done = singles(2), recent = singles(4, inProgress: true)
        XCTAssertEqual(candidates([old, done, recent]).unfinishedMatches.map(\.id), [recent.id, old.id])
        XCTAssertEqual(candidates([old, done, recent], includeInProgress: true).unfinishedMatches.map(\.id),
                       [recent.id, old.id])
    }

    func test_alwaysInclude_makesOnlyTheFinishingMatchEligible() {
        let finishing = singles(5, inProgress: true), other = singles(4, inProgress: true), done = singles(1)
        let c = GamePlanEligibility.candidates(for: F.opponentID, in: [finishing, other, done],
                                               alwaysInclude: finishing.id)
        XCTAssertEqual(c.eligible.map(\.id), [finishing.id, done.id])
        XCTAssertEqual(c.excludedInProgress.map(\.id), [other.id], "Other unfinished matches still need the opt-in")
        let forgotten = GamePlanEligibility.candidates(
            for: F.opponentID, in: [finishing], forgotten: ForgottenPlayerLedger(playerIDs: [F.opponentID]),
            alwaysInclude: finishing.id)
        XCTAssertTrue(forgotten.eligible.isEmpty, "A forgotten player stays without evidence")
    }

    func test_resolvePinning_keepsTheFinishingMatchSelected() {
        let finishing = singles(0, competition: .friendly, inProgress: true)
        let newer = (1...5).map { singles(Double($0), competition: .league) }
        let c = candidates([finishing] + newer, includeInProgress: true)
        let lastFive = GamePlanSelection()
        XCTAssertFalse(lastFive.resolve(c).contains { $0.id == finishing.id }, "Older than the latest five")
        let pinned = lastFive.resolve(c, pinning: finishing.id)
        XCTAssertEqual(pinned.count, 6)
        XCTAssertEqual(pinned.last?.id, finishing.id, "Still newest first")
        let leagueOnly = GamePlanSelection(mode: .all, filter: GamePlanFilter(competitions: [.league]))
        XCTAssertTrue(leagueOnly.resolve(c, pinning: finishing.id).contains { $0.id == finishing.id },
                      "Filters can't drop it")
        XCTAssertEqual(GamePlanSelection(mode: .custom([])).resolve(c, pinning: finishing.id).map(\.id), [finishing.id])
        XCTAssertEqual(lastFive.resolve(c, pinning: UUID()).map(\.id), lastFive.resolve(c).map(\.id),
                       "Only an eligible match can be pinned")
        XCTAssertEqual(lastFive.resolve(c, pinning: nil).map(\.id), lastFive.resolve(c).map(\.id))
    }

    func test_prefill_leavesUntaggedUnknownAndUnofferedValuesUnset() {
        XCTAssertNil(GamePlanUpcomingMatch(prefilledFrom: singles(1)).competition, "Untagged is not guessed")
        XCTAssertNil(GamePlanUpcomingMatch(prefilledFrom: singles(1, raw: "ladder")).competition,
                     "An unknown future type is neither Friendly nor League")
        XCTAssertEqual(GamePlanUpcomingMatch(prefilledFrom: singles(1)).format, .standard)
        var quick = singles(1, competition: .friendly)
        quick.matchFormat = .quick4Games
        XCTAssertFalse(GamePlanText.selectableFormats.contains(.quick4Games))
        XCTAssertNil(GamePlanUpcomingMatch(prefilledFrom: quick).format, "Only offered formats are pre-filled")
        XCTAssertEqual(GamePlanUpcomingMatch(prefilledFrom: quick).competition, .friendly)
    }

    func test_manifestDescription_statesModeAndFilters() {
        let utc = F.utc
        XCTAssertEqual(GamePlanSelection().manifestDescription(timeZone: utc), "Last 5 by start date")
        XCTAssertEqual(GamePlanSelection(mode: .all).manifestDescription(timeZone: utc), "All matches")
        let filtered = GamePlanSelection(mode: .latest(10), filter: GamePlanFilter(
            from: TagFixtures.base, through: nil, competitions: [.league, .friendly]))
        XCTAssertEqual(filtered.manifestDescription(timeZone: utc), "Last 10 by start date · Friendly, League · from 2023-11-14")
        XCTAssertEqual(GamePlanSelection(mode: .custom([])).manifestDescription(timeZone: utc), "Custom selection")
    }
}
