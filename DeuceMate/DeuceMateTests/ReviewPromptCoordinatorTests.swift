// ReviewPromptCoordinatorTests.swift — the timing state and local flags around
// Core's `ReviewPromptPolicy`, which covers the rules themselves.
import Foundation
import Testing
import DeuceMateCore
@testable import DeuceMate

@MainActor
struct ReviewPromptCoordinatorTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let defaults: UserDefaults

    init() throws {
        let suite = "review-prompt-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    private func win(id: UUID = UUID()) -> MatchRecord {
        MatchRecord(
            id: id,
            startTime: now.addingTimeInterval(-7_200),
            endTime: now.addingTimeInterval(-3_600),
            setScores: [],
            stats: [PointStat(setIndex: 0, server: .me, winner: .me, outcome: .winner)],
            iWon: true
        )
    }

    private func coordinator(version: String = "1.4") -> ReviewPromptCoordinator {
        ReviewPromptCoordinator(defaults: defaults, appVersion: version)
    }

    @Test func closingAfterEnoughAttentionRequests() {
        let match = win()
        let c = coordinator()
        c.reportOpened(matchID: match.id, isActive: true, now: now)
        #expect(c.shouldRequestReviewOnClose(history: [match, win(), win()], now: now.addingTimeInterval(20)))
    }

    @Test func backgroundTimeDoesNotCountAsAttention() {
        let match = win()
        let c = coordinator()
        c.reportOpened(matchID: match.id, isActive: true, now: now)
        c.scenePhaseChanged(isActive: false, now: now.addingTimeInterval(5))
        c.scenePhaseChanged(isActive: true, now: now.addingTimeInterval(3_000))
        #expect(!c.shouldRequestReviewOnClose(history: [match, win(), win()], now: now.addingTimeInterval(3_001)))
    }

    @Test func oneCloseIsOnlyJudgedOnce() {
        let match = win()
        let history = [match, win(), win()]
        let c = coordinator()
        c.reportOpened(matchID: match.id, isActive: true, now: now)
        #expect(c.shouldRequestReviewOnClose(history: history, now: now.addingTimeInterval(30)))
        #expect(!c.shouldRequestReviewOnClose(history: history, now: now.addingTimeInterval(31)))
    }

    @Test func aMatchDeletedWhileOpenDoesNotRequest() {
        let match = win()
        let c = coordinator()
        c.reportOpened(matchID: match.id, isActive: true, now: now)
        #expect(!c.shouldRequestReviewOnClose(history: [win(), win(), win()], now: now.addingTimeInterval(30)))
    }

    @Test func aRecordedRequestBlocksThisVersionAcrossInstances() {
        let match = win()
        let history = [match, win(), win()]
        coordinator().recordRequest(now: now)

        let sameVersion = coordinator()
        sameVersion.reportOpened(matchID: match.id, isActive: true, now: now)
        #expect(!sameVersion.shouldRequestReviewOnClose(history: history, now: now.addingTimeInterval(30)))
    }

    @Test func onlyARecordedRequestBlocksTheNextOne() {
        let match = win()
        let history = [match, win(), win()]
        let c = coordinator()
        for offset in [0.0, 100.0] {
            c.reportOpened(matchID: match.id, isActive: true, now: now.addingTimeInterval(offset))
            #expect(c.shouldRequestReviewOnClose(history: history, now: now.addingTimeInterval(offset + 30)))
        }
    }
}
