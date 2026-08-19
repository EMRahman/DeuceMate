// HealthAccessSettlePolicyTests.swift — the schedule that lets a freshly
// granted HealthKit permission settle, instead of the strip showing a yellow
// "Ask" until the next launch. Pure logic, no HealthKit, no simulator.
import XCTest
@testable import DeuceMateCore

final class HealthAccessSettlePolicyTests: XCTestCase {

    // MARK: - Keep going while the answer is still missing

    func testUndeterminedWalksTheScheduleInOrderThenStops() {
        let delays = HealthAccessSettlePolicy.retryDelays
        for (attempt, expected) in delays.enumerated() {
            XCTAssertEqual(
                HealthAccessSettlePolicy.nextRetryDelay(attempt: attempt, access: .notDetermined),
                expected,
                "Attempt \(attempt) should wait \(expected)s"
            )
        }
        XCTAssertNil(
            HealthAccessSettlePolicy.nextRetryDelay(attempt: delays.count, access: .notDetermined),
            "The schedule must be bounded — a sheet dismissed without an answer cannot poll forever"
        )
    }

    func testScheduleIsShortAndBacksOff() {
        let delays = HealthAccessSettlePolicy.retryDelays
        XCTAssertFalse(delays.isEmpty)
        XCTAssertTrue(delays.allSatisfy { $0 > 0 })
        XCTAssertEqual(delays, delays.sorted(), "Delays should back off, not jitter")
        XCTAssertLessThan(
            delays.reduce(0, +), 5,
            "Total settle window should stay well under 5s so the user sees it resolve"
        )
    }

    // MARK: - Stop as soon as there is a conclusive answer

    func testConclusiveStatesStopImmediately() {
        for access in [HealthAccess.authorized, .denied, .unavailable] {
            XCTAssertNil(
                HealthAccessSettlePolicy.nextRetryDelay(attempt: 0, access: access),
                "\(access) is a settled answer and must not be re-read"
            )
        }
    }

    /// The reported bug: the grant lands, but the read in
    /// `requestAuthorization`'s completion still says `.notDetermined`. The
    /// first retry must be scheduled, and the moment a later read comes back
    /// authorized the polling must stop.
    func testLateArrivingGrantSettles() {
        XCTAssertNotNil(
            HealthAccessSettlePolicy.nextRetryDelay(attempt: 0, access: .notDetermined),
            "A still-undetermined read right after the sheet closes must schedule a retry"
        )
        XCTAssertNil(
            HealthAccessSettlePolicy.nextRetryDelay(attempt: 1, access: .authorized),
            "Once the grant is visible the polling must stop"
        )
    }

    // MARK: - Defensive

    func testNegativeAttemptNeverSchedules() {
        XCTAssertNil(HealthAccessSettlePolicy.nextRetryDelay(attempt: -1, access: .notDetermined))
    }
}
