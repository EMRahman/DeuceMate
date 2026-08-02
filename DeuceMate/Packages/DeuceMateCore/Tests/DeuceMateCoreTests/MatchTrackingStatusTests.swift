// MatchTrackingStatusTests.swift — the rule behind the pre-match tracking strip:
// what counts as "on", what counts as "degraded but still recording", and what
// counts as "this match will not capture that". Pure logic, no simulator.
import XCTest
@testable import DeuceMateCore

final class MatchTrackingStatusTests: XCTestCase {

    private let year = 2026

    // MARK: - Point tracking

    func test_pointTracking_reflectsTheToggle() {
        let on = MatchTrackingStatus.pointTracking(isEnabled: true)
        XCTAssertEqual(on.readiness, .on)
        XCTAssertEqual(on.stateLabel, "On")
        XCTAssertEqual(on.detail, SettingsCopy.trackPointOutcome.text)

        let off = MatchTrackingStatus.pointTracking(isEnabled: false)
        XCTAssertEqual(off.readiness, .off)
        XCTAssertEqual(off.stateLabel, "Off")
    }

    // MARK: - Health tracking

    func test_healthTracking_authorized_isOn() {
        let status = MatchTrackingStatus.healthTracking(access: .authorized)
        XCTAssertEqual(status.readiness, .on)
        XCTAssertEqual(status.stateLabel, "On")
    }

    func test_healthTracking_notDetermined_isPartialNotOff() {
        // The prompt has not been answered yet — reporting "Off" would be wrong
        // (the match may well record) and reporting "On" would over-promise.
        let status = MatchTrackingStatus.healthTracking(access: .notDetermined)
        XCTAssertEqual(status.readiness, .partial)
        XCTAssertEqual(status.stateLabel, "Ask")
    }

    func test_healthTracking_denied_isOffAndSaysHowToFixIt() {
        let status = MatchTrackingStatus.healthTracking(access: .denied)
        XCTAssertEqual(status.readiness, .off)
        XCTAssertEqual(status.stateLabel, "Off")
        XCTAssertTrue(status.detail.contains(MatchTrackingStatus.healthAccessFixItNote))
    }

    func test_healthTracking_unavailable_isOffWithoutFixItAdvice() {
        // Nothing the user can do on a device with no Health support, so the
        // copy must not send them to a settings screen that cannot help.
        let status = MatchTrackingStatus.healthTracking(access: .unavailable)
        XCTAssertEqual(status.readiness, .off)
        XCTAssertFalse(status.detail.contains(MatchTrackingStatus.healthAccessFixItNote))
    }

    // MARK: - Pulse Coach

    func test_pulseCoach_needsHealthAccess() {
        for access in [HealthAccess.denied, .unavailable] {
            let status = MatchTrackingStatus.pulseCoach(
                access: access,
                birthYear: 1990,
                maxHROverride: 0,
                currentYear: year
            )
            XCTAssertEqual(status.readiness, .off, "\(access) should disable Pulse Coach")
            XCTAssertEqual(status.stateLabel, "Off")
        }
    }

    func test_pulseCoach_healthOnButUncalibrated_isPartial() {
        let status = MatchTrackingStatus.pulseCoach(
            access: .authorized,
            birthYear: 0,
            maxHROverride: 0,
            currentYear: year
        )
        XCTAssertEqual(status.readiness, .partial)
        XCTAssertEqual(status.stateLabel, "Est.")
        XCTAssertEqual(status.detail, SettingsCopy.defaultMaxHRNote)
    }

    func test_pulseCoach_birthYearCalibrated_isOnAndQuotesResolvedMaxHR() {
        let status = MatchTrackingStatus.pulseCoach(
            access: .authorized,
            birthYear: 1990,
            maxHROverride: 0,
            currentYear: year
        )
        XCTAssertEqual(status.readiness, .on)
        XCTAssertEqual(status.stateLabel, "On")
        XCTAssertTrue(status.detail.contains("184 bpm"), status.detail)
    }

    func test_pulseCoach_ageThirty_resolvesTo190ButStillCountsAsCalibrated() {
        // 220 − 30 = 190, the same number as the uncalibrated fallback. The
        // status must come from whether a birth year was set, never from
        // comparing the resolved value against 190.
        let status = MatchTrackingStatus.pulseCoach(
            access: .authorized,
            birthYear: year - 30,
            maxHROverride: 0,
            currentYear: year
        )
        XCTAssertEqual(status.readiness, .on)
        XCTAssertTrue(status.detail.contains("190 bpm"), status.detail)
    }

    func test_pulseCoach_outOfRangeOverrideWithNoBirthYear_isPartial() {
        // 300 bpm is ignored by resolveMaxHR, so it must not be reported as
        // calibrated either.
        let status = MatchTrackingStatus.pulseCoach(
            access: .authorized,
            birthYear: 0,
            maxHROverride: 300,
            currentYear: year
        )
        XCTAssertEqual(status.readiness, .partial)
    }

    func test_pulseCoach_overrideWinsOverBirthYear() {
        let status = MatchTrackingStatus.pulseCoach(
            access: .authorized,
            birthYear: 1990,
            maxHROverride: 175,
            currentYear: year
        )
        XCTAssertEqual(status.readiness, .on)
        XCTAssertTrue(status.detail.contains("175 bpm"), status.detail)
    }

    func test_pulseCoach_notDeterminedHealth_stillReportsCalibration() {
        // Health has not been answered yet — Pulse Coach is not "off", it is
        // whatever the max-HR calibration says.
        let status = MatchTrackingStatus.pulseCoach(
            access: .notDetermined,
            birthYear: 1990,
            maxHROverride: 0,
            currentYear: year
        )
        XCTAssertEqual(status.readiness, .on)
    }

    // MARK: - Strip

    func test_all_returnsThreeFacetsInDisplayOrder() {
        let statuses = MatchTrackingStatus.all(
            pointTrackingEnabled: false,
            healthAccess: .denied,
            birthYear: 0,
            maxHROverride: 0,
            currentYear: year
        )
        XCTAssertEqual(statuses.map(\.facet), [.pointTracking, .healthTracking, .pulseCoach])
        XCTAssertEqual(statuses.map(\.readiness), [.off, .off, .off])
        XCTAssertEqual(statuses.map(\.stateLabel), ["Off", "Off", "Off"])
    }

    func test_all_everythingConfigured_isAllOn() {
        let statuses = MatchTrackingStatus.all(
            pointTrackingEnabled: true,
            healthAccess: .authorized,
            birthYear: 1990,
            maxHROverride: 0,
            currentYear: year
        )
        XCTAssertEqual(statuses.map(\.readiness), [.on, .on, .on])
    }

    // MARK: - Copy invariants

    func test_everyResolvableStatus_hasWellFormedLabels() {
        var seen: [MatchTrackingStatus] = []
        for access in HealthAccess.allCases {
            for enabled in [true, false] {
                for (birthYear, override) in [(0, 0), (1990, 0), (0, 175)] {
                    seen += MatchTrackingStatus.all(
                        pointTrackingEnabled: enabled,
                        healthAccess: access,
                        birthYear: birthYear,
                        maxHROverride: override,
                        currentYear: year
                    )
                }
            }
        }
        for status in seen {
            XCTAssertFalse(status.detail.isEmpty, "\(status.facet) has empty detail")
            XCTAssertFalse(status.detail.contains("\n"), "\(status.facet) detail must be one line")
            XCTAssertFalse(status.stateLabel.isEmpty)
            XCTAssertLessThanOrEqual(
                status.stateLabel.count, 4,
                "\(status.stateLabel) is too wide for a watch chip"
            )
            XCTAssertLessThanOrEqual(
                status.shortTitle.count, 6,
                "\(status.shortTitle) is too wide for a watch chip"
            )
            XCTAssertFalse(status.systemImage.isEmpty)
        }
    }

    func test_accessibilityDescription_namesTheFacetAndItsState() {
        let status = MatchTrackingStatus.pointTracking(isEnabled: false)
        XCTAssertTrue(status.accessibilityDescription.hasPrefix("Point tracking: Off."))
    }
}
