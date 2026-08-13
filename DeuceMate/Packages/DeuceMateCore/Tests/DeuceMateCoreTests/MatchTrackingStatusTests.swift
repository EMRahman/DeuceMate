// MatchTrackingStatusTests.swift — the rule behind the pre-match tracking strip:
// what counts as "on", what counts as "degraded but still recording", and what
// counts as "this match will not capture that". Pure logic, no simulator.
import XCTest
@testable import DeuceMateCore

final class MatchTrackingStatusTests: XCTestCase {

    private let year = 2026

    // MARK: - Point tracking

    func test_pointTracking_reflectsTheToggle() {
        let on = MatchTrackingStatus.pointTracking(isEnabled: true, matchFormat: .standard)
        XCTAssertEqual(on.readiness, .on)
        XCTAssertEqual(on.stateLabel, "On")
        XCTAssertEqual(on.detail, SettingsCopy.trackPointOutcome.text)

        let off = MatchTrackingStatus.pointTracking(isEnabled: false, matchFormat: .standard)
        XCTAssertEqual(off.readiness, .off)
        XCTAssertEqual(off.stateLabel, "Off")
    }

    func test_pointTracking_perpetualPoints_isSuppressedRegardlessOfToggle() {
        // MatchFormat.perpetualPoints sets disablesPointTracking: true — the
        // format overrides the user's toggle either way (§3.3's hard coupling).
        for enabled in [true, false] {
            let status = MatchTrackingStatus.pointTracking(isEnabled: enabled, matchFormat: .perpetualPoints)
            XCTAssertEqual(status.readiness, .off, "toggle=\(enabled)")
            XCTAssertEqual(status.stateLabel, "—", "toggle=\(enabled)")
            XCTAssertTrue(status.detail.contains("Perpetual Points"), status.detail)
        }
    }

    func test_pointTracking_everyOtherFormat_stillReflectsTheToggle() {
        for format: MatchFormat in [.standard, .bestOf3FullFinalSet, .superTiebreak, .perpetualSuperTiebreak, .quick4Games] {
            XCTAssertFalse(format.config.disablesPointTracking, "\(format) unexpectedly suppresses point tracking")
            let status = MatchTrackingStatus.pointTracking(isEnabled: true, matchFormat: format)
            XCTAssertEqual(status.readiness, .on, "\(format)")
            XCTAssertNotEqual(status.stateLabel, "—", "\(format)")
        }
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

    func test_pulseCoach_healthOnButUncalibrated_isPartialAndSaysItsRetroactive() {
        let status = MatchTrackingStatus.pulseCoach(
            access: .authorized,
            birthYear: 0,
            maxHROverride: 0,
            currentYear: year
        )
        XCTAssertEqual(status.readiness, .partial)
        XCTAssertEqual(status.stateLabel, "Est.")
        XCTAssertTrue(status.detail.contains(SettingsCopy.defaultMaxHRNote), status.detail)
        // The change from the prior-art branch: Pulse is the one facet that is
        // recoverable, and the copy must say so (§2.1/§4.2).
        XCTAssertTrue(status.detail.contains("recompute"), status.detail)
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

    // MARK: - all(...)

    func test_all_returnsThreeFacetsInDisplayOrder() {
        let statuses = MatchTrackingStatus.all(
            matchFormat: .standard,
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
            matchFormat: .standard,
            pointTrackingEnabled: true,
            healthAccess: .authorized,
            birthYear: 1990,
            maxHROverride: 0,
            currentYear: year
        )
        XCTAssertEqual(statuses.map(\.readiness), [.on, .on, .on])
    }

    func test_all_perpetualPoints_suppressesPointsRegardlessOfOtherFacets() {
        let statuses = MatchTrackingStatus.all(
            matchFormat: .perpetualPoints,
            pointTrackingEnabled: true,
            healthAccess: .authorized,
            birthYear: 1990,
            maxHROverride: 0,
            currentYear: year
        )
        XCTAssertEqual(statuses[0].facet, .pointTracking)
        XCTAssertEqual(statuses[0].readiness, .off)
        XCTAssertEqual(statuses[0].stateLabel, "—")
        // The other two facets are unaffected by the format.
        XCTAssertEqual(statuses[1].readiness, .on)
        XCTAssertEqual(statuses[2].readiness, .on)
    }

    // MARK: - collapsingPulseWhenHealthOff(_:) — OQ-1

    func test_collapsingPulseWhenHealthOff_removesPulseWhenHealthDenied() {
        let statuses = MatchTrackingStatus.all(
            matchFormat: .standard,
            pointTrackingEnabled: true,
            healthAccess: .denied,
            birthYear: 0,
            maxHROverride: 0,
            currentYear: year
        )
        let collapsed = MatchTrackingStatus.collapsingPulseWhenHealthOff(statuses)
        XCTAssertEqual(collapsed.map(\.facet), [.pointTracking, .healthTracking])
    }

    func test_collapsingPulseWhenHealthOff_removesPulseWhenHealthUnavailable() {
        let statuses = MatchTrackingStatus.all(
            matchFormat: .standard,
            pointTrackingEnabled: true,
            healthAccess: .unavailable,
            birthYear: 0,
            maxHROverride: 0,
            currentYear: year
        )
        let collapsed = MatchTrackingStatus.collapsingPulseWhenHealthOff(statuses)
        XCTAssertEqual(collapsed.map(\.facet), [.pointTracking, .healthTracking])
    }

    func test_collapsingPulseWhenHealthOff_keepsPulseWhenHealthAuthorized() {
        let statuses = MatchTrackingStatus.all(
            matchFormat: .standard,
            pointTrackingEnabled: true,
            healthAccess: .authorized,
            birthYear: 0,
            maxHROverride: 0,
            currentYear: year
        )
        let collapsed = MatchTrackingStatus.collapsingPulseWhenHealthOff(statuses)
        XCTAssertEqual(collapsed.map(\.facet), [.pointTracking, .healthTracking, .pulseCoach])
    }

    func test_collapsingPulseWhenHealthOff_keepsPulseWhenHealthNotDetermined() {
        // Health "Ask" is .partial, not .off — the strip must still show all
        // three while the permission is unanswered.
        let statuses = MatchTrackingStatus.all(
            matchFormat: .standard,
            pointTrackingEnabled: true,
            healthAccess: .notDetermined,
            birthYear: 1990,
            maxHROverride: 0,
            currentYear: year
        )
        let collapsed = MatchTrackingStatus.collapsingPulseWhenHealthOff(statuses)
        XCTAssertEqual(collapsed.map(\.facet), [.pointTracking, .healthTracking, .pulseCoach])
    }

    // MARK: - Copy invariants

    func test_everyResolvableStatus_hasWellFormedLabels() {
        var seen: [MatchTrackingStatus] = []
        for format: MatchFormat in [.standard, .perpetualPoints] {
            for access in HealthAccess.allCases {
                for enabled in [true, false] {
                    for (birthYear, override) in [(0, 0), (1990, 0), (0, 175)] {
                        seen += MatchTrackingStatus.all(
                            matchFormat: format,
                            pointTrackingEnabled: enabled,
                            healthAccess: access,
                            birthYear: birthYear,
                            maxHROverride: override,
                            currentYear: year
                        )
                    }
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
        let status = MatchTrackingStatus.pointTracking(isEnabled: false, matchFormat: .standard)
        XCTAssertTrue(status.accessibilityDescription.hasPrefix("Point tracking: Off."))
    }

    func test_accessibilityDescription_stripsMarkdownEmphasis() {
        // The Pulse "Est." detail carries **bold** Markdown for the watch UI;
        // VoiceOver must speak the words, not literal asterisks.
        let status = MatchTrackingStatus.pulseCoach(
            access: .authorized,
            birthYear: 0,
            maxHROverride: 0,
            currentYear: year
        )
        XCTAssertFalse(status.accessibilityDescription.contains("*"), status.accessibilityDescription)
    }
}
