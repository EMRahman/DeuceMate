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

    func test_refusedSwipeFeedback_onlyWhenInputIsOnAndTheWatchIsUnreachable() {
        XCTAssertTrue(LiveScoreboardStatus(isWatchReachable: false, isInputEnabled: true).refusesSwipeWithFeedback)
        XCTAssertFalse(LiveScoreboardStatus(isWatchReachable: false, isInputEnabled: false).refusesSwipeWithFeedback,
                       "A spectator's drag isn't a scoring attempt")
        XCTAssertFalse(LiveScoreboardStatus(isWatchReachable: true, isInputEnabled: true).refusesSwipeWithFeedback,
                       "A reachable Watch accepts the swipe instead")
        XCTAssertFalse(LiveScoreboardStatus(isWatchReachable: true, isInputEnabled: false).refusesSwipeWithFeedback)
    }

    func test_refusedSwipeFeedback_neverOverlapsAcceptedInput() {
        for reachable in [true, false] {
            for input in [true, false] {
                let status = LiveScoreboardStatus(isWatchReachable: reachable, isInputEnabled: input)
                XCTAssertFalse(status.acceptsInput && status.refusesSwipeWithFeedback)
            }
        }
    }

    func test_commandFailureMessage_doesNotClaimThePointWasLost() {
        // The Watch may have applied a command whose send reported failure.
        XCTAssertTrue(LiveScoreboardStatus.commandFailureMessage.contains("Check the score"))
        XCTAssertFalse(LiveScoreboardStatus.commandFailureMessage.localizedCaseInsensitiveContains("not counted"))
    }

    // MARK: - Watch prompts (changeover, "Who serves next?")

    private let changeover = LiveWatchPrompt.changeover(symbol: "🔁 🎾", reason: "Even games – balls change ends")
    private let blocker = "Continue on the Watch before scoring."

    func test_prompt_isAnswerableFromThePhoneWhileScoringStaysBlocked() {
        let status = LiveScoreboardStatus(isWatchReachable: true, isInputEnabled: true,
                                          blockingReason: blocker, prompt: changeover)
        XCTAssertTrue(status.showsPrompt)
        XCTAssertTrue(status.acceptsPromptAnswer)
        XCTAssertFalse(status.acceptsInput, "Points wait until the prompt is answered")
        XCTAssertFalse(status.showsSwipeHint)
        XCTAssertNil(status.detail, "The card replaces 'Continue on the Watch'")
        XCTAssertEqual(status.badgeLabel, "LIVE")
        XCTAssertEqual(status.promptCaption, "Answer here or on the Watch. Both screens clear together.")
    }

    func test_prompt_spectatorSeesItWithoutAnswering() {
        let status = LiveScoreboardStatus(isWatchReachable: true, isInputEnabled: false,
                                          blockingReason: blocker, prompt: .doublesServer)
        XCTAssertTrue(status.showsPrompt)
        XCTAssertFalse(status.acceptsPromptAnswer)
        XCTAssertEqual(status.promptCaption, "Waiting for the Watch. Turn on iPhone Input to answer here.")
        XCTAssertFalse(status.refusesSwipeWithFeedback, "A spectator's drag isn't a scoring attempt")
    }

    func test_prompt_answersFollowTheSameConnectionRulesAsScoring() {
        for (reachable, confirmed, inFlight) in [(false, true, false), (true, false, false), (true, true, true)] {
            let status = LiveScoreboardStatus(isWatchReachable: reachable, isInputEnabled: true,
                isStateConfirmed: confirmed, isRequestInFlight: inFlight,
                blockingReason: blocker, prompt: changeover)
            XCTAssertFalse(status.acceptsPromptAnswer, "reachable \(reachable) confirmed \(confirmed) inFlight \(inFlight)")
            XCTAssertNotNil(status.detail, "Connection trouble still explains itself")
        }
    }

    func test_prompt_swipeIsRefusedWithFeedbackAndNeverAccepted() {
        let status = LiveScoreboardStatus(isWatchReachable: true, isInputEnabled: true, prompt: changeover)
        XCTAssertTrue(status.refusesSwipeWithFeedback)
        XCTAssertFalse(status.acceptsInput, "Even a Watch that omits the blocker text cannot be scored past a prompt")
    }

    func test_unknownPromptKind_fallsBackToTheBlockerText() {
        let future = LiveWatchPrompt(kindRaw: "medicalTimeout", title: "Timeout")
        let status = LiveScoreboardStatus(isWatchReachable: true, isInputEnabled: true,
                                          blockingReason: blocker, prompt: future)
        XCTAssertFalse(status.showsPrompt)
        XCTAssertFalse(status.acceptsPromptAnswer)
        XCTAssertFalse(status.acceptsInput)
        XCTAssertEqual(status.detail, blocker)
        XCTAssertNil(status.promptCaption)
    }
}
