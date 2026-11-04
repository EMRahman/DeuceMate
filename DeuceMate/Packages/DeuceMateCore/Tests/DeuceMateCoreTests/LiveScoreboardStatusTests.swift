import XCTest
@testable import DeuceMateCore

final class LiveScoreboardStatusTests: XCTestCase {
    func test_reachableWithInput_isLiveAndAcceptsInput() {
        let status = LiveScoreboardStatus(isWatchReachable: true, isInputEnabled: true)

        XCTAssertEqual(status.badgeLabel, "LIVE")
        XCTAssertTrue(status.acceptsInput)
        XCTAssertTrue(status.showsSwipeHint)
        XCTAssertNil(status.detail)
    }

    func test_reachableSpectator_isLiveWithoutInput() {
        let status = LiveScoreboardStatus(isWatchReachable: true, isInputEnabled: false)

        XCTAssertEqual(status.badgeLabel, "LIVE")
        XCTAssertFalse(status.acceptsInput)
        XCTAssertFalse(status.showsSwipeHint)
        XCTAssertNil(status.detail)
    }

    func test_unreachableWithInput_blocksInputAndExplainsHowToResume() {
        let status = LiveScoreboardStatus(isWatchReachable: false, isInputEnabled: true)

        XCTAssertEqual(status.badgeLabel, "WAITING FOR WATCH")
        XCTAssertFalse(status.acceptsInput)
        XCTAssertFalse(status.showsSwipeHint)
        XCTAssertEqual(status.detail,
                       "Last score shown. Open DeuceMate on the Watch to score here.")
    }

    func test_unreachableSpectator_saysTheScoreMayBeOldWithoutMentioningScoring() {
        let status = LiveScoreboardStatus(isWatchReachable: false, isInputEnabled: false)

        XCTAssertEqual(status.badgeLabel, "WAITING FOR WATCH")
        XCTAssertFalse(status.acceptsInput)
        XCTAssertFalse(status.showsSwipeHint)
        XCTAssertEqual(status.detail,
                       "Last score shown. Updates resume when the Watch reconnects.")
    }

    func test_reconnecting_restoresInput() {
        let waiting = LiveScoreboardStatus(isWatchReachable: false, isInputEnabled: true)
        let restored = LiveScoreboardStatus(isWatchReachable: true,
                                            isInputEnabled: waiting.isInputEnabled)

        XCTAssertFalse(waiting.acceptsInput)
        XCTAssertTrue(restored.acceptsInput)
    }

    func test_commandFailureMessage_doesNotClaimThePointWasLost() {
        // The Watch may have applied a command whose send reported failure.
        XCTAssertTrue(LiveScoreboardStatus.commandFailureMessage.contains("Check the score"))
        XCTAssertFalse(LiveScoreboardStatus.commandFailureMessage.localizedCaseInsensitiveContains("not counted"))
    }
}
