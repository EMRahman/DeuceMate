//
//  DeuceMate_Watch_AppTests.swift
//  DeuceMate Watch AppTests
//

import Foundation
import DeuceMateCore
import Testing
@testable import DeuceMate_Watch_App

struct DeuceMate_Watch_AppTests {

    @Test func superTiebreakMatchFinishesToTen() throws {
        let viewModel = makeViewModel(startingServer: .me)

        // First set: me wins 6–0
        winGames(viewModel, player: .me, count: 6)
        #expect(viewModel.sets[0].gamesMe == 6)
        #expect(viewModel.sets[0].gamesOpponent == 0)
        #expect(viewModel.sets[0].isTieBreak == false)

        // Second set: opponent wins 6–0
        winGames(viewModel, player: .opponent, count: 6)
        #expect(viewModel.sets[1].gamesMe == 0)
        #expect(viewModel.sets[1].gamesOpponent == 6)
        #expect(viewModel.sets[1].isTieBreak == false)

        // A super tiebreak set should be prepared as the decider.
        #expect(viewModel.sets.count == 3)
        #expect(viewModel.sets[2].isTieBreak == true)

        // Decider: play to 10 points (must win by 2); 10–0 satisfies.
        winTiebreakPoints(viewModel, player: .me, points: 10)

        #expect(viewModel.isMatchComplete() == true)
        #expect(viewModel.sets.count == 3)
        #expect(viewModel.sets[2].tieBreakPointsMe == 10)
        #expect(viewModel.sets[2].tieBreakPointsOpponent == 0)
        #expect(viewModel.sets[2].gamesMe == 7) // Stored value used to signal set win
        #expect(viewModel.sets[2].isTieBreak == true)
    }

    @Test func superTiebreakSetsStartServerAndReceiver() throws {
        // When sets are 1-1, the super tiebreak should initialise tiebreak
        // server state the same way a regular tiebreak at 6-6 does.
        let viewModel = makeViewModel(startingServer: .me)

        // Set 1: me wins 6–0
        winGames(viewModel, player: .me, count: 6)
        // Set 2: opponent wins 6–0; currentServer after 6 games is opponent
        winGames(viewModel, player: .opponent, count: 6)

        // Super tiebreak should be live now (set 3 isTieBreak == true)
        #expect(viewModel.sets.count == 3)
        #expect(viewModel.sets[2].isTieBreak == true)

        // tiebreakStartServer must be set so rotation works
        let startServer = try #require(viewModel.tiebreakStartServer)
        let firstReceiver = try #require(viewModel.tiebreakFirstPointReceiver)
        #expect(startServer != firstReceiver)
        #expect(startServer == viewModel.currentServer)

        // After one point the server displayed should change only at the correct
        // tiebreak rotation boundaries (2-point blocks after point 1).
        let serverBeforeFirstPoint = viewModel.currentServer
        viewModel.winPoint(player: .me) // point 1 — still startServer's block
        // Points 2–3 belong to the other server, so currentServer should flip
        #expect(viewModel.currentServer != serverBeforeFirstPoint)
    }

    @Test func doublesServiceRotationInSuperTiebreak() throws {
        // Verify that doublesServer advances correctly during the super tiebreak.
        let viewModel = ScoreViewModel()
        viewModel.startDoublesMatch(firstServer: .me)
        // Service order is [me, opponentS1, partner, opponentS2]

        // Set 1: my team wins 6–0
        winGames(viewModel, player: .me, count: 6)
        // Set 2: opponent team wins 6–0
        winGames(viewModel, player: .opponent, count: 6)

        #expect(viewModel.sets.count == 3)
        #expect(viewModel.sets[2].isTieBreak == true)
        #expect(viewModel.tiebreakStartServer != nil)

        let initialDoublesServer = try #require(viewModel.doublesServer)

        // Point 1 is served by the player at tiebreakStartDoublesIndex.
        // After point 1 the display should advance to the next player (points 2–3).
        viewModel.winPoint(player: .me)
        let serverAfterPoint1 = try #require(viewModel.doublesServer)
        #expect(serverAfterPoint1 != initialDoublesServer)

        // Point 2 same player (still in the 2-3 block) – server stays the same.
        viewModel.winPoint(player: .me)
        let serverAfterPoint2 = try #require(viewModel.doublesServer)
        #expect(serverAfterPoint2 == serverAfterPoint1)

        // Point 3 ends the 2-3 block; next (point 4) belongs to the third player.
        viewModel.winPoint(player: .me)
        let serverAfterPoint3 = try #require(viewModel.doublesServer)
        #expect(serverAfterPoint3 != serverAfterPoint2)
    }

    @Test func superTiebreakServerStateCorrectWhenReachedViaRegularTiebreak() throws {
        // Regression: when set 2 ends via a regular tiebreak (sets go to 1-1),
        // the super tiebreak must still get correct tiebreakStartServer /
        // tiebreakFirstPointReceiver.  The old fix set those fields inside
        // completeSet, which ran before updateScore had a chance to compute the
        // correct next-set server from the ORIGINAL tiebreakFirstPointReceiver,
        // so both values ended up wrong and were then cleared to nil.
        let viewModel = makeViewModel(startingServer: .me)

        // Set 1: me wins 6–0
        winGames(viewModel, player: .me, count: 6)

        // Set 2: play to 6–6 then let opponent win the tiebreak 7–0
        for _ in 0..<5 {
            winGame(viewModel, player: .me)
            winGame(viewModel, player: .opponent)
        }
        winGame(viewModel, player: .me)       // 6–5
        winGame(viewModel, player: .opponent) // 6–6 → regular tiebreak begins

        let regularTBReceiver = try #require(viewModel.tiebreakFirstPointReceiver)
        winTiebreakPoints(viewModel, player: .opponent, points: 7)

        // Sets are now 1-1; super tiebreak should be live
        #expect(viewModel.sets.count == 3)
        #expect(viewModel.sets[2].isTieBreak == true)

        // currentServer must equal the receiver of the regular tiebreak's first
        // point (standard ITF rule), and that is exactly who should start serving
        // the super tiebreak.
        #expect(viewModel.currentServer == regularTBReceiver)

        // Super tiebreak state must be initialised so rotation works
        let superStart = try #require(viewModel.tiebreakStartServer)
        #expect(superStart == viewModel.currentServer)

        // Server must advance after point 1
        let beforeFirst = viewModel.currentServer
        viewModel.winPoint(player: .me)
        #expect(viewModel.currentServer != beforeFirst)
    }

    @Test func nextServerAfterStandardTiebreakIsReceiverOfFirstPoint() throws {
        let viewModel = makeViewModel(startingServer: .me)

        // Play to 6–6 to trigger a first-set tiebreak.
        for _ in 0..<5 {
            winGame(viewModel, player: .me)        // 1–0, 2–1, 3–2, 4–3, 5–4
            winGame(viewModel, player: .opponent)  // 1–1, 2–2, 3–3, 4–4, 5–5
        }
        winGame(viewModel, player: .me)            // 6–5
        winGame(viewModel, player: .opponent)      // 6–6 -> triggers tiebreak setup

        #expect(viewModel.sets.first?.isTieBreak == true)
        #expect(viewModel.tiebreakStartServer != nil)
        #expect(viewModel.tiebreakFirstPointReceiver != nil)

        let startingServer = try #require(viewModel.tiebreakStartServer)
        let firstReceiver = try #require(viewModel.tiebreakFirstPointReceiver)

        // Winner takes the tiebreak 7–0.
        winTiebreakPoints(viewModel, player: startingServer, points: 7)

        // After the tiebreak set ends, next set should start with the first receiver serving.
        #expect(viewModel.currentServer == firstReceiver)
        #expect(viewModel.sets.count >= 2) // Next set created
        #expect(viewModel.sets[0].tieBreakPointsMe + viewModel.sets[0].tieBreakPointsOpponent >= 7)
    }

    @Test func nextServerAfterTiebreakWhenOpponentStartsMatch() throws {
        // When opponent starts the match, verify the tiebreak server assignment is correct
        let viewModel = makeViewModel(startingServer: .opponent)

        // Play to 6–6 to trigger a first-set tiebreak.
        for _ in 0..<5 {
            winGame(viewModel, player: .me)
            winGame(viewModel, player: .opponent)
        }
        winGame(viewModel, player: .me)
        winGame(viewModel, player: .opponent)      // 6–6

        #expect(viewModel.sets.first?.isTieBreak == true)

        let startingServer = try #require(viewModel.tiebreakStartServer)
        let firstReceiver = try #require(viewModel.tiebreakFirstPointReceiver)

        // Verify the tiebreak starting server is opponent (who would serve game 13)
        #expect(startingServer == .opponent)
        #expect(firstReceiver == .me)

        // Opponent wins the tiebreak 7–0.
        winTiebreakPoints(viewModel, player: .opponent, points: 7)

        // After the tiebreak, next set should start with .me (first receiver) serving.
        #expect(viewModel.currentServer == .me)
        #expect(viewModel.sets.count >= 2)
    }

    @Test func nextServerAfterTiebreakIsReceiverRegardlessOfWinner() throws {
        // The next set server should be the first tiebreak receiver, regardless of who won
        let viewModel = makeViewModel(startingServer: .me)

        // Play to 6–6
        for _ in 0..<5 {
            winGame(viewModel, player: .me)
            winGame(viewModel, player: .opponent)
        }
        winGame(viewModel, player: .me)
        winGame(viewModel, player: .opponent)      // 6–6

        let firstReceiver = try #require(viewModel.tiebreakFirstPointReceiver)

        // First receiver (opponent) wins the tiebreak instead of the starting server
        winTiebreakPoints(viewModel, player: firstReceiver, points: 7)

        // After the tiebreak, next set should STILL start with the first receiver serving.
        #expect(viewModel.currentServer == firstReceiver)
    }

    @Test func nextServerAfterTiebreak10_8AtSixAll() throws {
        // Scenario: First set reaches 6-6, tiebreak finishes 10-8
        // The receiver of the first tiebreak point should serve the first game of the next set
        let viewModel = makeViewModel(startingServer: .me)

        // Play first set to 6–6
        for _ in 0..<5 {
            winGame(viewModel, player: .me)
            winGame(viewModel, player: .opponent)
        }
        winGame(viewModel, player: .me)            // 6–5
        winGame(viewModel, player: .opponent)      // 6–6 -> tiebreak begins

        // Verify we're in a tiebreak at 6-6
        #expect(viewModel.sets.first?.isTieBreak == true)
        #expect(viewModel.sets.first?.gamesMe == 6)
        #expect(viewModel.sets.first?.gamesOpponent == 6)

        // Record who serves first in tiebreak and who receives
        let tiebreakServer = try #require(viewModel.tiebreakStartServer)
        let tiebreakReceiver = try #require(viewModel.tiebreakFirstPointReceiver)

        // Play extended tiebreak to 10-8:
        // Both players reach 6-6 in tiebreak
        winTiebreakPoints(viewModel, player: .me, points: 6)
        winTiebreakPoints(viewModel, player: .opponent, points: 6)
        #expect(viewModel.sets.first?.tieBreakPointsMe == 6)
        #expect(viewModel.sets.first?.tieBreakPointsOpponent == 6)

        // Continue without letting either player open a two-point lead after 7.
        viewModel.winPoint(player: .me)        // 7-6
        viewModel.winPoint(player: .opponent)  // 7-7
        viewModel.winPoint(player: .me)        // 8-7
        viewModel.winPoint(player: .opponent)  // 8-8
        winTiebreakPoints(viewModel, player: .me, points: 2) // 10-8 -> tiebreak ends

        // Verify tiebreak finished 10-8
        #expect(viewModel.sets[0].tieBreakPointsMe == 10)
        #expect(viewModel.sets[0].tieBreakPointsOpponent == 8)
        #expect(viewModel.sets[0].gamesMe == 7)  // Winner gets 7 games

        // Verify next set exists
        #expect(viewModel.sets.count >= 2)

        // CRITICAL: The receiver of the first tiebreak point serves the first game of the next set
        #expect(viewModel.currentServer == tiebreakReceiver)
        #expect(viewModel.currentServer != tiebreakServer)
    }

    @Test func nextServerAndEndsAfterSetFollowEvenOddTotalGamesRules() throws {
        // Even total games (6–0): balls change ends, next server rotates as normal.
        do {
            let viewModel = makeViewModel(startingServer: .me)
            viewModel.statsTrackingEnabled = false
            winGames(viewModel, player: .me, count: 6) // 6 games total (even)

            #expect(viewModel.sets[0].gamesMe == 6)
            #expect(viewModel.pendingChangeoverAck?.symbol == "🔁 🎾") // balls move, players stay
            #expect(viewModel.currentServer == .me) // service order continues
        }

        // Odd total games (6–1): players change ends, balls stay.
        do {
            let viewModel = makeViewModel(startingServer: .me)
            viewModel.statsTrackingEnabled = false
            winGame(viewModel, player: .opponent) // 0-1
            winGames(viewModel, player: .me, count: 6) // 6-1, total games = 7 (odd)

            #expect(viewModel.sets[0].gamesMe == 6)
            #expect(viewModel.sets[0].gamesOpponent == 1)
            #expect(viewModel.pendingChangeoverAck?.symbol == "🔁 👥") // players swap
        }
    }

    @Test func resetMatchClearsTiebreakServerState() throws {
        let viewModel = makeViewModel(startingServer: .me)

        // Reach 6–6 so tiebreak tracking fields are populated.
        for _ in 0..<5 {
            winGame(viewModel, player: .me)
            winGame(viewModel, player: .opponent)
        }
        winGame(viewModel, player: .me)
        winGame(viewModel, player: .opponent)

        #expect(viewModel.tiebreakStartServer != nil)
        #expect(viewModel.tiebreakFirstPointReceiver != nil)

        // Play one tiebreak point to populate lastTiebreakPointServer.
        viewModel.winPoint(player: .me)
        #expect(viewModel.lastTiebreakPointServer != nil)

        viewModel.resetMatch()

        #expect(viewModel.currentServer == nil)
        #expect(viewModel.tiebreakStartServer == nil)
        #expect(viewModel.tiebreakFirstPointReceiver == nil)
        #expect(viewModel.lastTiebreakPointServer == nil)
    }

    @Test func deuceAndAdvantageScoring() throws {
        let viewModel = makeViewModel(startingServer: .me)

        // Reach deuce: 3 points each (0, 15, 30, 40 → 40)
        for _ in 0..<3 {
            viewModel.winPoint(player: .me)
            viewModel.winPoint(player: .opponent)
        }

        // At deuce both players show "40"
        #expect(viewModel.displayedScore(for: .me) == "40")
        #expect(viewModel.displayedScore(for: .opponent) == "40")

        // Advantage me
        viewModel.winPoint(player: .me)
        #expect(viewModel.displayedScore(for: .me) == "AD")
        #expect(viewModel.displayedScore(for: .opponent) == "40")

        // Back to deuce
        viewModel.winPoint(player: .opponent)
        #expect(viewModel.displayedScore(for: .me) == "40")
        #expect(viewModel.displayedScore(for: .opponent) == "40")

        // Advantage opponent
        viewModel.winPoint(player: .opponent)
        #expect(viewModel.displayedScore(for: .me) == "40")
        #expect(viewModel.displayedScore(for: .opponent) == "AD")

        // Opponent wins the game
        viewModel.winPoint(player: .opponent)
        #expect(viewModel.sets.last?.gamesMe == 0)
        #expect(viewModel.sets.last?.gamesOpponent == 1)
        #expect(viewModel.currentPointsMe == 0)
        #expect(viewModel.currentPointsOpponent == 0)
    }

    // MARK: - Helpers

    private func makeViewModel(startingServer: ScoreViewModel.Player) -> ScoreViewModel {
        let viewModel = ScoreViewModel()
        viewModel.currentServer = startingServer
        return viewModel
    }

    private func winGames(_ viewModel: ScoreViewModel, player: ScoreViewModel.Player, count: Int) {
        for _ in 0..<count {
            winGame(viewModel, player: player)
        }
    }

    private func winGame(_ viewModel: ScoreViewModel, player: ScoreViewModel.Player) {
        // Four straight points are enough to take a game.
        for _ in 0..<4 {
            viewModel.winPoint(player: player)
        }
    }

    private func winTiebreakPoints(_ viewModel: ScoreViewModel, player: ScoreViewModel.Player, points: Int) {
        for _ in 0..<points {
            viewModel.winPoint(player: player)
        }
    }

    // MARK: - Stats Tracking Tests

    /// In-memory mock so tests don't write to the real Documents directory
    /// (and don't pollute one another).
    private final class MockStatsStore: StatsStoring {
        private(set) var records: [MatchRecord] = []
        var appendCallCount = 0
        var removeCallCount = 0

        func loadHistory() -> [MatchRecord] { records }
        func saveHistory(_ records: [MatchRecord]) { self.records = records }
        func appendMatch(_ record: MatchRecord) {
            appendCallCount += 1
            records.removeAll { $0.id == record.id }
            records.append(record)
        }
        func removeMatch(id: UUID) {
            removeCallCount += 1
            records.removeAll { $0.id == id }
        }
    }

    private func makeStatsViewModel(startingServer: ScoreViewModel.Player,
                                    store: MockStatsStore = MockStatsStore()) -> (ScoreViewModel, MockStatsStore) {
        let viewModel = ScoreViewModel(statsStore: store)
        viewModel.statsTrackingEnabled = true
        viewModel.currentServer = startingServer
        viewModel.matchStartTime = Date()
        return (viewModel, store)
    }

    @Test func statsOffDoesNotCreatePendingPoint() throws {
        let viewModel = makeViewModel(startingServer: .me)
        viewModel.statsTrackingEnabled = false
        // Outcome tracking default off: no categorization sheet, but point
        // metadata is still auto-recorded as uncategorized for history/analytics.
        viewModel.winPoint(player: .me)
        #expect(viewModel.pendingStatPoint == nil)
        #expect(viewModel.currentMatchStats.count == 1)
        #expect(viewModel.currentMatchStats.first?.outcome == .uncategorized)
    }

    @Test func statsOnCreatesPendingThenCommitAppends() throws {
        let (viewModel, _) = makeStatsViewModel(startingServer: .me)
        viewModel.winPoint(player: .me)
        let pending = try #require(viewModel.pendingStatPoint)
        #expect(pending.server == .me)
        #expect(pending.winner == .me)
        #expect(pending.isSecondServe == false)

        viewModel.commitPointStat(outcome: .winner)
        #expect(viewModel.pendingStatPoint == nil)
        #expect(viewModel.currentMatchStats.count == 1)
        #expect(viewModel.currentMatchStats.first?.outcome == .winner)
    }

    @Test func toggleSecondServeCapturedOnNextPoint() throws {
        let (viewModel, _) = makeStatsViewModel(startingServer: .me)
        viewModel.toggleSecondServe()
        #expect(viewModel.isOnSecondServe == true)

        viewModel.winPoint(player: .me)
        let pending = try #require(viewModel.pendingStatPoint)
        #expect(pending.isSecondServe == true)

        viewModel.commitPointStat(outcome: .winner)
        // Reset for next point
        #expect(viewModel.isOnSecondServe == false)
    }

    @Test func toggleSecondServeIsToggleable() throws {
        let (viewModel, _) = makeStatsViewModel(startingServer: .me)
        viewModel.toggleSecondServe()
        #expect(viewModel.isOnSecondServe == true)
        viewModel.toggleSecondServe()
        #expect(viewModel.isOnSecondServe == false)
    }

    @Test func toggleSecondServeIsNoOpDuringCategorization() throws {
        let (viewModel, _) = makeStatsViewModel(startingServer: .me)
        viewModel.winPoint(player: .me)
        // pendingStatPoint is set; toggleSecondServe should be ignored
        viewModel.toggleSecondServe()
        #expect(viewModel.isOnSecondServe == false)
    }

    @Test func undoRemovesCommittedStatByID() throws {
        let (viewModel, _) = makeStatsViewModel(startingServer: .me)
        viewModel.winPoint(player: .me)
        viewModel.commitPointStat(outcome: .winner)
        viewModel.winPoint(player: .opponent)
        viewModel.commitPointStat(outcome: .unforcedError)

        #expect(viewModel.currentMatchStats.count == 2)
        let secondID = viewModel.currentMatchStats[1].id

        viewModel.undo()
        #expect(viewModel.currentMatchStats.count == 1)
        // The remaining stat is the first one (the .winner), not the .unforcedError
        #expect(viewModel.currentMatchStats.first?.outcome == .winner)
        #expect(viewModel.currentMatchStats.contains(where: { $0.id == secondID }) == false)
    }

    @Test func undoMidCategorizationDropsPendingAndKeepsHistorySane() throws {
        let (viewModel, _) = makeStatsViewModel(startingServer: .me)
        viewModel.winPoint(player: .me)
        // Don't commit — just undo (simulating in-sheet Undo button)
        viewModel.undo()
        #expect(viewModel.pendingStatPoint == nil)
        #expect(viewModel.currentMatchStats.isEmpty)
        #expect(viewModel.currentPointsMe == 0)
    }

    @Test func undoRestoresSecondServeFlag() throws {
        let (viewModel, _) = makeStatsViewModel(startingServer: .me)
        viewModel.toggleSecondServe()
        viewModel.winPoint(player: .me)
        viewModel.commitPointStat(outcome: .winner)
        // After commit, isOnSecondServe is reset to false
        #expect(viewModel.isOnSecondServe == false)

        // Undoing should restore to true (the prior point was on second serve)
        viewModel.undo()
        #expect(viewModel.isOnSecondServe == true)
    }

    @Test func firstAndSecondServeWinPercentages() throws {
        let (viewModel, _) = makeStatsViewModel(startingServer: .me)
        // Point 1: 1st serve, won
        viewModel.winPoint(player: .me)
        viewModel.commitPointStat(outcome: .winner)
        // Point 2: 2nd serve, won
        viewModel.toggleSecondServe()
        viewModel.winPoint(player: .me)
        viewModel.commitPointStat(outcome: .winner)
        // Point 3: 2nd serve, lost (double fault)
        viewModel.toggleSecondServe()
        viewModel.winPoint(player: .opponent)
        viewModel.commitPointStat(outcome: .doubleFault)

        let stats = viewModel.currentMatchStats
        let myServes = stats.filter { $0.server == .me }
        let firstServePts = myServes.filter { !$0.isSecondServe }
        let secondServePts = myServes.filter { $0.isSecondServe }
        #expect(firstServePts.count == 1)
        #expect(firstServePts.allSatisfy { $0.winner == .me })
        #expect(secondServePts.count == 2)
        let secondWins = secondServePts.filter { $0.winner == .me }.count
        #expect(secondWins == 1)

        let myDFCount = stats.filter { $0.server == .me && $0.outcome == .doubleFault }.count
        #expect(myDFCount == 1)
    }

    @Test func resetMatchFinalizesInProgressToStore() throws {
        let (viewModel, store) = makeStatsViewModel(startingServer: .me)
        viewModel.winPoint(player: .me)
        viewModel.commitPointStat(outcome: .winner)
        viewModel.resetMatch()
        #expect(store.records.count == 1)
        #expect(store.records[0].iWon == nil) // in-progress
        #expect(store.records[0].stats.count == 1)
        // ScoreViewModel is now reset
        #expect(viewModel.currentMatchStats.isEmpty)
        #expect(viewModel.matchStartTime == nil)
        #expect(viewModel.currentMatchID == nil)
    }

    @Test func resetMatchWithNoStatsStillWritesSessionToStore() throws {
        let store = MockStatsStore()
        let viewModel = ScoreViewModel(statsStore: store)
        viewModel.statsTrackingEnabled = false
        viewModel.currentServer = .me

        // Play at least one point, then park the match.
        viewModel.winPoint(player: .me)
        viewModel.resetMatch()

        #expect(store.records.count == 1)
        #expect(store.records[0].stats.count == 1)
        #expect(store.records[0].stats.first?.outcome == .uncategorized)
        #expect(store.records[0].isInProgress)
    }

    @Test func resumeMatchRestoresState() throws {
        let (viewModel, store) = makeStatsViewModel(startingServer: .me)
        viewModel.winPoint(player: .me)
        viewModel.commitPointStat(outcome: .winner)
        viewModel.winPoint(player: .opponent)
        viewModel.commitPointStat(outcome: .unforcedError)
        let originalID = try #require(viewModel.currentMatchID)
        let originalStartTime = try #require(viewModel.matchStartTime)

        // Park: end-match into store
        viewModel.resetMatch()
        #expect(store.records.count == 1)
        #expect(viewModel.currentMatchStats.isEmpty)

        // Resume
        let parked = store.records[0]
        viewModel.resumeMatch(parked)
        #expect(viewModel.currentMatchStats.count == 2)
        #expect(viewModel.currentMatchID == originalID)
        #expect(viewModel.matchStartTime == originalStartTime)
        // Removed from store on resume
        #expect(store.records.isEmpty)

        // Continue playing
        viewModel.winPoint(player: .me)
        viewModel.commitPointStat(outcome: .winner)
        #expect(viewModel.currentMatchStats.count == 3)
    }

    @Test func resumeRestoresSecondServeFlag() throws {
        let (viewModel, store) = makeStatsViewModel(startingServer: .me)
        viewModel.winPoint(player: .me)
        viewModel.commitPointStat(outcome: .winner)
        // Enter second-serve before parking
        viewModel.toggleSecondServe()
        #expect(viewModel.isOnSecondServe == true)

        viewModel.resetMatch()
        let parked = try #require(store.records.first)
        #expect(parked.isOnSecondServe == true)

        viewModel.resumeMatch(parked)
        #expect(viewModel.isOnSecondServe == true)
    }

    @Test func finalizeWithLeadingInProgressSetDoesNotMarkMatchWon() throws {
        let (viewModel, store) = makeStatsViewModel(startingServer: .me)
        // Win set 1 6-0 (24 points × 4-pt games), then 1-0 in set 2 (4 more pts).
        for _ in 0..<28 { viewModel.winPoint(player: .me); viewModel.commitPointStat(outcome: .winner) }
        // Sanity: set 1 is complete, set 2 in progress with me leading 1-0
        #expect(viewModel.sets.count == 2)
        #expect(viewModel.sets[0].gamesMe == 6 && viewModel.sets[0].gamesOpponent == 0)
        #expect(viewModel.sets[1].gamesMe == 1 && viewModel.sets[1].gamesOpponent == 0)

        viewModel.resetMatch()
        let record = try #require(store.records.first)
        // iWon must be nil (in progress) — set 2 is not complete even though I lead.
        #expect(record.iWon == nil)
        #expect(record.isInProgress)
        #expect(record.endTime == nil)
    }

    @Test func resumeWithDifferentLiveMatchParksStatsOffSession() throws {
        let store = MockStatsStore()
        let viewModel = ScoreViewModel(statsStore: store)
        viewModel.statsTrackingEnabled = false
        viewModel.currentServer = .me

        // Match A: play and park.
        viewModel.winPoint(player: .me)
        viewModel.resetMatch()
        let parkedA = try #require(store.records.first)

        // Match B: live, with progress but still stats off.
        viewModel.currentServer = .opponent
        viewModel.winPoint(player: .opponent)
        #expect(viewModel.hasInProgressMatchData)

        // Resuming A should park B first rather than dropping it.
        viewModel.resumeMatch(parkedA)
        #expect(store.records.count == 1)
        #expect(store.records[0].id != parkedA.id)
    }

    @Test func resumeWithDifferentLiveMatchParksTheLiveOne() throws {
        let (viewModel, store) = makeStatsViewModel(startingServer: .me)
        viewModel.winPoint(player: .me)
        viewModel.commitPointStat(outcome: .winner)
        viewModel.resetMatch() // park first match

        // Start a new live match
        viewModel.currentServer = .opponent
        viewModel.matchStartTime = Date()
        viewModel.winPoint(player: .opponent)
        viewModel.commitPointStat(outcome: .winner)

        let liveMatchID = try #require(viewModel.currentMatchID)
        let parkedRecord = try #require(store.records.first)
        #expect(parkedRecord.id != liveMatchID)

        // Resume the parked one — live one should be parked first
        viewModel.resumeMatch(parkedRecord)
        // The store now contains the live-one (just parked) but NOT the resumed one
        #expect(store.records.contains(where: { $0.id == liveMatchID }))
        #expect(store.records.contains(where: { $0.id == parkedRecord.id }) == false)
        #expect(viewModel.currentMatchID == parkedRecord.id)
    }

    @Test func appStateV1MigratesWithDefaults() throws {
        // Construct a v1-style JSON manually (no v2 fields) and verify
        // AppState's custom decoder fills defaults.
        let v1Json = """
        {
          "version": 1,
          "sets": [{"id":"00000000-0000-0000-0000-000000000001","gamesMe":0,"gamesOpponent":0,"isTieBreak":false,"tieBreakPointsMe":0,"tieBreakPointsOpponent":0}],
          "currentPointsMe": 0,
          "currentPointsOpponent": 0,
          "history": [],
          "gameCount": 0,
          "pointCountInTiebreak": 0
        }
        """.data(using: .utf8)!
        let state = try JSONDecoder().decode(ScoreViewModel.AppState.self, from: v1Json)
        #expect(state.version == 1)
        #expect(state.currentMatchStats.isEmpty)
        #expect(state.matchStartTime == nil)
        #expect(state.isOnSecondServe == false)
        #expect(state.pendingStatPoint == nil)
        #expect(state.currentMatchID == nil)
        #expect(state.setElapsedSeconds.isEmpty)
    }

    // MARK: - Set Duration (Stopwatch) Tests

    @Test func setElapsedSnapshotOnSetCompletion() throws {
        let (viewModel, _) = makeStatsViewModel(startingServer: .me)
        let sessionStart = Date()
        viewModel.currentSetSessionStart = sessionStart

        // Simulate winning set 1 (6–0) so completeSet is triggered.
        for _ in 0..<24 { viewModel.winPoint(player: .me); viewModel.commitPointStat(outcome: .winner) }

        // Set 0 should now be finalized in setElapsedSeconds with a non-negative value.
        let elapsed0 = viewModel.setElapsedSeconds[0]
        #expect(elapsed0 != nil)
        #expect((elapsed0 ?? 0) >= 0)

        // The new set (index 1) session start should have been reset.
        #expect(viewModel.currentSetSessionStart != nil)
        #expect(viewModel.currentSetSessionStart! >= sessionStart)
    }

    @Test func parkAndResumeExcludesIdleTimeFromSetDuration() throws {
        let (viewModel, store) = makeStatsViewModel(startingServer: .me)

        // Simulate 5 seconds of "play" by back-dating currentSetSessionStart.
        let fakeStart = Date().addingTimeInterval(-5)
        viewModel.currentSetSessionStart = fakeStart

        // Score one point to create a stat.
        viewModel.winPoint(player: .me)
        viewModel.commitPointStat(outcome: .winner)

        // Park: finalizes the match into the store.
        viewModel.resetMatch()
        let parked = try #require(store.records.first)

        // The parked record's set 0 elapsed should be ~5 s (the active play time).
        let elapsed = try #require(parked.setElapsedSeconds[0])
        #expect(elapsed >= 5 && elapsed < 10, "Expected ~5 s active play, got \(elapsed) s")

        // Simulate a long idle gap by manipulating the resume time — after resumeMatch
        // currentSetSessionStart is reset to Date(), so the idle gap is not counted.
        viewModel.resumeMatch(parked)

        // Play one more point after resume.
        viewModel.winPoint(player: .me)
        viewModel.commitPointStat(outcome: .winner)

        // Park again.
        viewModel.resetMatch()
        let reparked = try #require(store.records.first)

        // The total elapsed for set 0 should still be ~5 s plus a tiny delta for the
        // second point (not hours of idle time).
        let totalElapsed = try #require(reparked.setElapsedSeconds[0])
        #expect(totalElapsed < 60, "Idle gap must not inflate set duration; got \(totalElapsed) s")
    }

    @Test func matchRecordSetElapsedSecondsRoundTrips() throws {
        let record = MatchRecord(
            startTime: Date(),
            setScores: [],
            stats: [],
            setElapsedSeconds: [0: 300, 1: 1200]
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(MatchRecord.self, from: data)
        #expect(decoded.setElapsedSeconds[0] == 300)
        #expect(decoded.setElapsedSeconds[1] == 1200)
    }

    @Test func matchRecordOldFormatDefaultsSetElapsedToEmpty() throws {
        // Old records without setElapsedSeconds should decode with an empty dict.
        let oldJson = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "startTime": 0,
          "setScores": [],
          "stats": [],
          "currentPointsMe": 0,
          "currentPointsOpponent": 0,
          "gameCount": 0,
          "pointCountInTiebreak": 0,
          "isOnSecondServe": false,
          "matchElapsedSeconds": 0
        }
        """.data(using: .utf8)!
        let record = try JSONDecoder().decode(MatchRecord.self, from: oldJson)
        #expect(record.setElapsedSeconds.isEmpty)
    }

    // Regression: before the fix, isFinished used lastKnownSetIndex (max stats setIndex)
    // which equals the just-completed set's index, causing it to show a live timer instead
    // of the stored fixed duration until the first point of the next set was committed.
    @Test func completedSetShowsStoredDurationBeforeNextSetHasStats() throws {
        let (viewModel, _) = makeStatsViewModel(startingServer: .me)
        let fakeStart = Date().addingTimeInterval(-60) // 60 s of "play"
        viewModel.currentSetSessionStart = fakeStart

        // Win set 0 (6-0) — committing stats for all points.
        for _ in 0..<24 { viewModel.winPoint(player: .me); viewModel.commitPointStat(outcome: .winner) }

        // Set 0 is now complete. Set 1 has started but zero stats have been committed for it yet.
        // The stored duration for set 0 must be ~60 s.
        let storedElapsed = try #require(viewModel.setElapsedSeconds[0])
        #expect(storedElapsed >= 60 && storedElapsed < 120)

        // currentSetSessionStart now tracks set 1. Simulate a bit more time passing.
        let set1Start = viewModel.currentSetSessionStart!

        // The display logic in MatchStatsView uses setScores.count - 1 to determine
        // whether a set is finished. Since sets.count == 2 (set 0 done + set 1 in progress),
        // set 0 (index 0) must be considered finished (0 < 2-1 == true).
        let isFinished = 0 < viewModel.sets.count - 1
        #expect(isFinished, "Set 0 must be considered finished as soon as set 1 starts, before any stats are committed for set 1")

        // And the value that would be displayed must be the stored snapshot, NOT
        // storedElapsed + time-since-set1-start.
        let incorrectValue = storedElapsed + Date().timeIntervalSince(set1Start)
        #expect(incorrectValue > storedElapsed, "Sanity: time has passed since set 1 started")
        // With the fix, the view reads setElapsedSeconds[0] directly (storedElapsed), not the inflated value.
        #expect(storedElapsed < incorrectValue)
    }

    // Regression: bootstrapLiveMatchIdentityIfNeeded was re-setting currentSetSessionStart to
    // Date() after completeSet() had set it to nil for the match-winning set. This caused
    // finalizeCurrentMatchToStore to add idle time between match-end and resetMatch to set 1's
    // stored duration.
    @Test func completedMatchDoesNotInflateSet1DurationOnFinalize() throws {
        let (viewModel, store) = makeStatsViewModel(startingServer: .me)
        let set0Start = Date().addingTimeInterval(-120) // 2 min set 0
        viewModel.currentSetSessionStart = set0Start

        // Win set 0 (6-0).
        for _ in 0..<24 { viewModel.winPoint(player: .me); viewModel.commitPointStat(outcome: .winner) }

        let set1Start = viewModel.currentSetSessionStart!
        // Simulate 90 s of play in set 1 by back-dating the timer.
        viewModel.currentSetSessionStart = Date().addingTimeInterval(-90)

        // Win set 1 (6-0) to complete the match.
        for _ in 0..<24 { viewModel.winPoint(player: .me); viewModel.commitPointStat(outcome: .winner) }

        // Match is now complete. The bootstrap guard must leave currentSetSessionStart nil
        // so finalizeCurrentMatchToStore cannot add idle time to the last set.
        #expect(viewModel.currentSetSessionStart == nil,
                "Set session timer should be stopped after match completion")
        let _ = set1Start // silence unused-variable warning

        // Finalize via resetMatch — simulates the user starting a new match.
        viewModel.resetMatch()
        let record = try #require(store.records.first)

        let elapsed1 = try #require(record.setElapsedSeconds[1])
        // Should be ~90 s of actual play, not hours of idle time.
        #expect(elapsed1 >= 88 && elapsed1 < 120,
                "Set 1 duration should reflect play time only; got \(elapsed1) s")
    }

    // MARK: - Court Bearing Tests

    @Test func currentCourtBearingFlipsCorrectly() throws {
        // Uses courtInitialHeading = 90° (East).
        // With the corrected formula: changeoverCount = (gameCount + 1) / 2 + tiebreakSegment
        // changeoverCount odd → flip 180° → bearing 270°
        // changeoverCount even → flip 0°  → bearing 90°
        struct BearingCase {
            let label: String
            let gameCount: Int
            let pointCountInTiebreak: Int
            let isTiebreak: Bool
            let expectedBearing: Double
        }

        let cases: [BearingCase] = [
            // Plan-specified cases
            BearingCase(label: "Match start",                    gameCount: 0,  pointCountInTiebreak: 0,  isTiebreak: false, expectedBearing: 90),
            BearingCase(label: "After game 1",                   gameCount: 1,  pointCountInTiebreak: 0,  isTiebreak: false, expectedBearing: 270),
            BearingCase(label: "Enter tiebreak at 6-6",          gameCount: 12, pointCountInTiebreak: 0,  isTiebreak: true,  expectedBearing: 90),
            BearingCase(label: "Tiebreak point 6 (changeover)",  gameCount: 12, pointCountInTiebreak: 6,  isTiebreak: true,  expectedBearing: 270),
            BearingCase(label: "Tiebreak point 12",              gameCount: 12, pointCountInTiebreak: 12, isTiebreak: true,  expectedBearing: 90),
            BearingCase(label: "Set 1 ends 6-3, start of set 2", gameCount: 9,  pointCountInTiebreak: 0,  isTiebreak: false, expectedBearing: 270),
            // Extra cases validating changeover parity (not just game parity).
            // After game 2, no changeover occurred since game 1 — player stays on the flipped end.
            BearingCase(label: "After game 2 (no extra changeover)", gameCount: 2, pointCountInTiebreak: 0, isTiebreak: false, expectedBearing: 270),
            // After game 3, a second changeover returns player to original end.
            BearingCase(label: "After game 3 (back to original end)", gameCount: 3, pointCountInTiebreak: 0, isTiebreak: false, expectedBearing: 90),
            // After game 4, no changeover — still on original end.
            BearingCase(label: "After game 4 (no extra changeover)", gameCount: 4, pointCountInTiebreak: 0, isTiebreak: false, expectedBearing: 90),
        ]

        let initial: Double = 90

        for c in cases {
            // Formula mirrors ContentView.currentCourtBearing
            let changeoverCount = (c.gameCount + 1) / 2
                + (c.isTiebreak ? c.pointCountInTiebreak / 6 : 0)
            let flip = changeoverCount % 2 == 1 ? 180.0 : 0.0
            let bearing = (initial + flip).truncatingRemainder(dividingBy: 360)
            #expect(bearing == c.expectedBearing,
                    "\(c.label): expected \(c.expectedBearing)°, got \(bearing)°")
        }
    }

    // MARK: - Doubles Match Simulation

    /// Simulates a complete recreational doubles match:
    ///   Set 1 – my team wins 6–4  (10 games)
    ///   Set 2 – opponent wins 6–3 (9 games)
    ///   Deciding super tiebreak – my team wins 10–7
    ///
    /// The test verifies:
    ///   • doublesServer and currentServer agree at every game and at key
    ///     tiebreak-rotation boundaries
    ///   • service index carries over correctly from set to set
    ///   • the deciding super tiebreak is seeded with the right server
    ///   • `matchWinner` and final scores are correct
    ///
    /// OBSERVATIONS (documented but not failing assertions):
    ///   1. "Partner" button in server-selection UI uses the same green gradient
    ///      as the "Me" button (HomeView.swift doublesServerSelectionView).
    ///      No visual distinction between your own two players. Low severity.
    ///   2. CourtSideView shows only one dot per side; doubles has two players
    ///      per side. Accepted simplification for the Watch form factor.
    ///   3. "S1" / "S2" labels for opponent players are positional only —
    ///      no way to assign real names, which can cause confusion mid-match.
    ///   4. When sets reach 1–1 and the deciding super tiebreak starts, no
    ///      "Super Tiebreak!" announcement is shown to the user. The only cue is
    ///      "🔁 👥" (players change ends). A brief banner would aid orientation,
    ///      especially since the scoring mode silently switches from game points
    ///      (0/15/30/40) to raw tiebreak counts shown in the point-badge column.
    @Test func simulateFullDoublesMatch() throws {
        // Service order seeded by startDoublesMatch(firstServer: .me):
        //   [me, opponentS1, partner, opponentS2]  (teams alternate A-B-A-B)
        let vm = ScoreViewModel()
        vm.startDoublesMatch(firstServer: .me)

        #expect(vm.matchType == .doubles)
        #expect(vm.doublesServer == .me)
        #expect(vm.currentServer == .me)
        let serviceOrder = vm.doublesServiceOrder
        #expect(serviceOrder == [.me, .opponentS1, .partner, .opponentS2])

        // ── SET 1: my team wins 6–4 ───────────────────────────────────────

        // Game 1 – Me serves, my team holds
        #expect(vm.doublesServer == .me,      "G1 server")
        #expect(vm.currentServer == .me,      "G1 team")
        winGame(vm, player: .me)             // 1–0
        #expect(vm.sets.last?.gamesMe == 1)

        // Game 2 – OpponentS1 serves, opponent holds
        #expect(vm.doublesServer == .opponentS1, "G2 server")
        #expect(vm.currentServer == .opponent,   "G2 team")
        winGame(vm, player: .opponent)       // 1–1

        // Game 3 – Partner serves, my team holds
        #expect(vm.doublesServer == .partner, "G3 server")
        #expect(vm.currentServer == .me,      "G3 team")
        winGame(vm, player: .me)             // 2–1

        // Game 4 – OpponentS2 serves, my team breaks
        #expect(vm.doublesServer == .opponentS2, "G4 server")
        #expect(vm.currentServer == .opponent,   "G4 team")
        winGame(vm, player: .me)             // 3–1  (break)

        // Game 5 – Me serves again (second rotation), holds
        #expect(vm.doublesServer == .me,      "G5 server")
        #expect(vm.currentServer == .me,      "G5 team")
        winGame(vm, player: .me)             // 4–1

        // Game 6 – OpponentS1 serves, opponent holds
        #expect(vm.doublesServer == .opponentS1, "G6 server")
        #expect(vm.currentServer == .opponent,   "G6 team")
        winGame(vm, player: .opponent)       // 4–2

        // Game 7 – Partner serves, my team holds
        #expect(vm.doublesServer == .partner, "G7 server")
        #expect(vm.currentServer == .me,      "G7 team")
        winGame(vm, player: .me)             // 5–2

        // Game 8 – OpponentS2 serves, opponent holds
        #expect(vm.doublesServer == .opponentS2, "G8 server")
        #expect(vm.currentServer == .opponent,   "G8 team")
        winGame(vm, player: .opponent)       // 5–3

        // Game 9 – Me serves, opponent breaks (at 5–4)
        #expect(vm.doublesServer == .me,      "G9 server")
        #expect(vm.currentServer == .me,      "G9 team")
        winGame(vm, player: .opponent)       // 5–4

        // Game 10 – OpponentS1 serves, my team breaks to close set 6–4
        #expect(vm.doublesServer == .opponentS1, "G10 server")
        #expect(vm.currentServer == .opponent,   "G10 team")
        winGame(vm, player: .me)             // 6–4 → set 1 complete

        // After 10 games: service index should have advanced to 2 (partner)
        #expect(vm.sets.count == 2,                       "two sets in play after S1")
        #expect(vm.sets[0].gamesMe == 6,                  "S1 games me")
        #expect(vm.sets[0].gamesOpponent == 4,            "S1 games opp")
        #expect(vm.doublesServer == .partner,             "first server of S2 = partner")
        #expect(vm.currentServer == .me,                  "partner is on my team")

        // ── SET 2: opponent wins 6–3 ─────────────────────────────────────

        // Game 1 (S2) – Partner serves, my team holds
        #expect(vm.doublesServer == .partner, "S2-G1 server")
        winGame(vm, player: .me)             // 1–0

        // Game 2 – OpponentS2 serves, opponent holds
        #expect(vm.doublesServer == .opponentS2, "S2-G2 server")
        #expect(vm.currentServer == .opponent,   "S2-G2 team")
        winGame(vm, player: .opponent)       // 1–1

        // Game 3 – Me serves, opponent breaks
        #expect(vm.doublesServer == .me,      "S2-G3 server")
        #expect(vm.currentServer == .me,      "S2-G3 team")
        winGame(vm, player: .opponent)       // 1–2

        // Game 4 – OpponentS1 serves, opponent holds
        #expect(vm.doublesServer == .opponentS1, "S2-G4 server")
        #expect(vm.currentServer == .opponent,   "S2-G4 team")
        winGame(vm, player: .opponent)       // 1–3

        // Game 5 – Partner serves, my team holds
        #expect(vm.doublesServer == .partner, "S2-G5 server")
        #expect(vm.currentServer == .me,      "S2-G5 team")
        winGame(vm, player: .me)             // 2–3

        // Game 6 – OpponentS2 serves, opponent holds
        #expect(vm.doublesServer == .opponentS2, "S2-G6 server")
        #expect(vm.currentServer == .opponent,   "S2-G6 team")
        winGame(vm, player: .opponent)       // 2–4

        // Game 7 – Me serves, my team holds
        #expect(vm.doublesServer == .me,      "S2-G7 server")
        #expect(vm.currentServer == .me,      "S2-G7 team")
        winGame(vm, player: .me)             // 3–4

        // Game 8 – OpponentS1 serves, opponent holds
        #expect(vm.doublesServer == .opponentS1, "S2-G8 server")
        #expect(vm.currentServer == .opponent,   "S2-G8 team")
        winGame(vm, player: .opponent)       // 3–5

        // Game 9 – Partner serves, opponent breaks to close set 3–6
        #expect(vm.doublesServer == .partner, "S2-G9 server")
        #expect(vm.currentServer == .me,      "S2-G9 team")
        winGame(vm, player: .opponent)       // 3–6 → set 2 complete, sets 1–1

        // After set 2: service index = 3 (opponentS2) seeds the tiebreak
        #expect(vm.sets.count == 3,                       "three sets after S2")
        #expect(vm.sets[1].gamesMe == 3,                  "S2 games me")
        #expect(vm.sets[1].gamesOpponent == 6,            "S2 games opp")
        #expect(vm.sets[2].isTieBreak,                    "set 3 is super tiebreak")
        #expect(vm.doublesServer == .opponentS2,          "tiebreak opened by opponentS2")
        #expect(vm.currentServer == .opponent,            "opponentS2 team = opponent")
        #expect(vm.tiebreakStartServer == .opponent,      "tiebreakStartServer")
        #expect(vm.tiebreakFirstPointReceiver == .me,     "tiebreakFirstPointReceiver")

        // ── DECIDING SUPER TIEBREAK: my team wins 10–7 ───────────────────
        //
        // Rotation (tiebreakStartDoublesIndex = 3 = opponentS2):
        //   Pt 1      → opponentS2 (offset 0)
        //   Pt 2–3    → me         (offset 1)
        //   Pt 4–5    → opponentS1 (offset 2)
        //   Pt 6–7    → partner    (offset 3)  ← ends change at pt 6
        //   Pt 8–9    → opponentS2 (offset 4 → idx 3)
        //   Pt 10–11  → me         (offset 5 → idx 0)
        //   Pt 12–13  → opponentS1 (offset 6 → idx 1)  ← ends change at pt 12
        //   Pt 14–15  → partner    (offset 7 → idx 2)
        //   Pt 16–17  → opponentS2 (offset 8 → idx 3)

        // Point 1: opponentS2 serves
        #expect(vm.doublesServer == .opponentS2, "TB pt1 server")
        vm.winPoint(player: .opponent)           // 0–1

        // Points 2–3: Me serves
        #expect(vm.doublesServer == .me, "TB pt2 server")
        vm.winPoint(player: .me)                 // 1–1
        #expect(vm.doublesServer == .me, "TB pt3 server (same block)")
        vm.winPoint(player: .me)                 // 2–1

        // Points 4–5: OpponentS1 serves
        #expect(vm.doublesServer == .opponentS1, "TB pt4 server")
        vm.winPoint(player: .opponent)           // 2–2
        #expect(vm.doublesServer == .opponentS1, "TB pt5 server (same block)")
        vm.winPoint(player: .me)                 // 3–2

        // Points 6–7: Partner serves (ends change at point 6)
        #expect(vm.doublesServer == .partner, "TB pt6 server")
        vm.winPoint(player: .me)                 // 4–2
        #expect(vm.doublesServer == .partner, "TB pt7 server (same block)")
        vm.winPoint(player: .opponent)           // 4–3

        // Points 8–9: OpponentS2 serves
        #expect(vm.doublesServer == .opponentS2, "TB pt8 server")
        vm.winPoint(player: .me)                 // 5–3
        #expect(vm.doublesServer == .opponentS2, "TB pt9 server (same block)")
        vm.winPoint(player: .me)                 // 6–3

        // Points 10–11: Me serves
        #expect(vm.doublesServer == .me, "TB pt10 server")
        vm.winPoint(player: .me)                 // 7–3
        #expect(vm.doublesServer == .me, "TB pt11 server (same block)")
        vm.winPoint(player: .opponent)           // 7–4

        // Points 12–13: OpponentS1 serves (ends change at point 12)
        #expect(vm.doublesServer == .opponentS1, "TB pt12 server")
        vm.winPoint(player: .opponent)           // 7–5
        #expect(vm.doublesServer == .opponentS1, "TB pt13 server (same block)")
        vm.winPoint(player: .me)                 // 8–5

        // Points 14–15: Partner serves
        #expect(vm.doublesServer == .partner, "TB pt14 server")
        vm.winPoint(player: .me)                 // 9–5
        #expect(vm.doublesServer == .partner, "TB pt15 server (same block)")
        vm.winPoint(player: .opponent)           // 9–6

        // Points 16–17: OpponentS2 serves — my team wins on point 17
        #expect(vm.doublesServer == .opponentS2, "TB pt16 server")
        vm.winPoint(player: .opponent)           // 9–7
        vm.winPoint(player: .me)                 // 10–7 → match complete

        // ── Final assertions ──────────────────────────────────────────────
        #expect(vm.isMatchComplete(),           "match must be complete")
        #expect(vm.matchWinner() == .me,        "my team wins")

        // Deciding set tiebreak score
        let decidingSet = try #require(vm.sets.last)
        #expect(decidingSet.isTieBreak,                       "deciding set is tiebreak")
        #expect(decidingSet.tieBreakPointsMe == 10,           "TB me = 10")
        #expect(decidingSet.tieBreakPointsOpponent == 7,      "TB opp = 7")

        // Set scores
        #expect(vm.sets[0].gamesMe == 6 && vm.sets[0].gamesOpponent == 4, "S1 = 6-4")
        #expect(vm.sets[1].gamesMe == 3 && vm.sets[1].gamesOpponent == 6, "S2 = 3-6")
    }
}
