import XCTest
@testable import DeuceMateCore

final class ReviewPromptPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    private func point(_ outcome: PointOutcome) -> PointStat {
        PointStat(setIndex: 0, server: .me, winner: .me, outcome: outcome)
    }

    private func record(
        iWon: Bool? = true,
        endedAgo: TimeInterval? = 3_600,
        outcomes: [PointOutcome] = [.winner]
    ) -> MatchRecord {
        MatchRecord(
            startTime: now.addingTimeInterval(-10_000),
            endTime: endedAgo.map { now.addingTimeInterval(-$0) },
            setScores: [],
            stats: outcomes.map(point),
            iWon: iWon
        )
    }

    private func should(
        _ record: MatchRecord,
        count: Int = 3,
        attention: TimeInterval = 20,
        history: ReviewPromptPolicy.RequestHistory = .init(),
        version: String = "1.4"
    ) -> Bool {
        ReviewPromptPolicy.shouldRequestReview(
            closing: record,
            completedMatchCount: count,
            reportAttention: attention,
            history: history,
            appVersion: version,
            now: now
        )
    }

    func test_recentTrackedWin_withEnoughMatches_requests() {
        XCTAssertTrue(should(record()))
    }

    // MARK: - The match

    func test_inProgressMatch_neverRequests() {
        XCTAssertFalse(should(record(iWon: nil, endedAgo: nil), count: 50))
    }

    func test_matchAgeBoundary() {
        XCTAssertTrue(should(record(endedAgo: ReviewPromptPolicy.maximumMatchAge)))
        XCTAssertFalse(should(record(endedAgo: ReviewPromptPolicy.maximumMatchAge + 1)))
    }

    func test_scoreOnlyMatch_neverRequests() {
        XCTAssertFalse(should(record(outcomes: []), count: 50))
        XCTAssertFalse(should(record(outcomes: [.uncategorized, .uncategorized]), count: 50))
    }

    func test_oneCategorizedPoint_isEnoughToBeTracked() {
        XCTAssertTrue(should(record(outcomes: [.uncategorized, .winner])))
    }

    // MARK: - Attention and experience

    func test_attentionBoundary() {
        XCTAssertTrue(should(record(), attention: ReviewPromptPolicy.minimumReportAttention))
        XCTAssertFalse(should(record(), attention: ReviewPromptPolicy.minimumReportAttention - 0.1))
    }

    func test_tooFewCompletedMatches_doesNotRequest() {
        XCTAssertFalse(should(record(), count: ReviewPromptPolicy.minimumCompletedMatches - 1))
    }

    // MARK: - The win rule

    func test_lossOrDraw_waitsForTheAnyResultThreshold() {
        for result in [false, nil] as [Bool?] {
            let match = record(iWon: result)
            XCTAssertFalse(should(match, count: ReviewPromptPolicy.completedMatchesForAnyResult - 1))
            XCTAssertTrue(should(match, count: ReviewPromptPolicy.completedMatchesForAnyResult))
        }
    }

    // MARK: - Frequency

    func test_alreadyRequestedOnThisVersion_doesNotRequest() {
        let history = ReviewPromptPolicy.RequestHistory(
            lastRequestDate: now.addingTimeInterval(-365 * day),
            lastRequestVersion: "1.4"
        )
        XCTAssertFalse(should(record(), history: history, version: "1.4"))
        XCTAssertTrue(should(record(), history: history, version: "1.5"))
    }

    func test_newVersionStillWaitsOutTheGap() {
        let gap = TimeInterval(ReviewPromptPolicy.minimumDaysBetweenRequests) * day
        func history(ago: TimeInterval) -> ReviewPromptPolicy.RequestHistory {
            .init(lastRequestDate: now.addingTimeInterval(-ago), lastRequestVersion: "1.3")
        }
        XCTAssertFalse(should(record(), history: history(ago: gap - 1)))
        XCTAssertTrue(should(record(), history: history(ago: gap)))
    }

    func test_spacingStaysWithinApplesThreePerYear() {
        XCTAssertLessThanOrEqual(365 / ReviewPromptPolicy.minimumDaysBetweenRequests, 3)
    }

    // MARK: - Links

    func test_writeReviewURL_pointsAtTheListingAndOpensTheComposer() {
        XCTAssertEqual(ReviewPromptPolicy.writeReviewURL,
                       "https://apps.apple.com/app/id6757105622?action=write-review")
    }

    // MARK: - Attention timer

    func test_timer_countsForegroundTimeOnly() {
        let start = now
        var timer = ReviewAttentionTimer(startedAt: start)
        XCTAssertEqual(timer.elapsed(at: start.addingTimeInterval(5)), 5)

        timer.setActive(false, at: start.addingTimeInterval(10))
        XCTAssertEqual(timer.elapsed(at: start.addingTimeInterval(9_999)), 10)

        timer.setActive(true, at: start.addingTimeInterval(10_000))
        XCTAssertEqual(timer.elapsed(at: start.addingTimeInterval(10_005)), 15)
    }

    func test_timer_repeatedPhaseEventsDontDoubleCount() {
        let start = now
        var timer = ReviewAttentionTimer(startedAt: start)
        timer.setActive(true, at: start.addingTimeInterval(5))
        XCTAssertEqual(timer.elapsed(at: start.addingTimeInterval(10)), 10)
        timer.setActive(false, at: start.addingTimeInterval(10))
        timer.setActive(false, at: start.addingTimeInterval(20))
        XCTAssertEqual(timer.elapsed(at: start.addingTimeInterval(30)), 10)
    }

    func test_timer_startedInBackground_waitsForForeground() {
        var timer = ReviewAttentionTimer(startedAt: now, isActive: false)
        XCTAssertEqual(timer.elapsed(at: now.addingTimeInterval(100)), 0)
        timer.setActive(true, at: now.addingTimeInterval(100))
        XCTAssertEqual(timer.elapsed(at: now.addingTimeInterval(103)), 3)
    }
}
