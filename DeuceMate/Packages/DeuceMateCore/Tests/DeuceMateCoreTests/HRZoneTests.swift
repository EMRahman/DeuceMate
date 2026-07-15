// HRZoneTests.swift — boundary cases for the HR zone classifier and the
// max-HR resolution chain.
import XCTest
@testable import DeuceMateCore

final class HRZoneTests: XCTestCase {

    // MARK: - zone(forBPM:maxHR:)

    func test_zoneBoundaries_at190MaxHR() {
        // Boundaries: 60% = 114, 70% = 133, 80% = 152, 90% = 171
        XCTAssertEqual(HRZone.zone(forBPM: 60,  maxHR: 190), .z1)
        XCTAssertEqual(HRZone.zone(forBPM: 113, maxHR: 190), .z1)
        XCTAssertEqual(HRZone.zone(forBPM: 114, maxHR: 190), .z2)
        XCTAssertEqual(HRZone.zone(forBPM: 132, maxHR: 190), .z2)
        XCTAssertEqual(HRZone.zone(forBPM: 133, maxHR: 190), .z3)
        XCTAssertEqual(HRZone.zone(forBPM: 151, maxHR: 190), .z3)
        XCTAssertEqual(HRZone.zone(forBPM: 152, maxHR: 190), .z4)
        XCTAssertEqual(HRZone.zone(forBPM: 170, maxHR: 190), .z4)
        XCTAssertEqual(HRZone.zone(forBPM: 171, maxHR: 190), .z5)
        XCTAssertEqual(HRZone.zone(forBPM: 200, maxHR: 190), .z5)
    }

    func test_zone_zeroMaxHR_falsBackToZ1() {
        XCTAssertEqual(HRZone.zone(forBPM: 150, maxHR: 0), .z1)
    }

    // MARK: - resolveMaxHR

    func test_resolveMaxHR_overrideWinsOverAge() {
        let resolved = HRZone.resolveMaxHR(
            manualOverride: 175,
            birthYear: 1990,
            currentYear: 2026
        )
        XCTAssertEqual(resolved, 175)
    }

    func test_resolveMaxHR_ageFallback() {
        // 2026 - 1990 = 36 → 220 - 36 = 184
        let resolved = HRZone.resolveMaxHR(
            manualOverride: nil,
            birthYear: 1990,
            currentYear: 2026
        )
        XCTAssertEqual(resolved, 184)
    }

    func test_resolveMaxHR_ultimateFallback() {
        let resolved = HRZone.resolveMaxHR(
            manualOverride: nil,
            birthYear: nil,
            currentYear: 2026
        )
        XCTAssertEqual(resolved, 190)
    }

    func test_resolveMaxHR_overrideOutOfRangeFallsThroughToAge() {
        // Override 999 is outside 120…220 → ignored → age formula wins.
        let resolved = HRZone.resolveMaxHR(
            manualOverride: 999,
            birthYear: 1990,
            currentYear: 2026
        )
        XCTAssertEqual(resolved, 184)
    }

    func test_resolveMaxHR_invalidBirthYearFallsBack() {
        let resolved = HRZone.resolveMaxHR(
            manualOverride: nil,
            birthYear: 2030,
            currentYear: 2026
        )
        XCTAssertEqual(resolved, 190)
    }

    // MARK: - ceilingBPM(for:maxHR:)

    func test_ceilingBPM_at190MaxHR() {
        // Each ceiling is one below the next zone's lower boundary.
        XCTAssertEqual(HRZone.ceilingBPM(for: .z1, maxHR: 190), 113)
        XCTAssertEqual(HRZone.ceilingBPM(for: .z2, maxHR: 190), 132)
        XCTAssertEqual(HRZone.ceilingBPM(for: .z3, maxHR: 190), 151)
        XCTAssertEqual(HRZone.ceilingBPM(for: .z4, maxHR: 190), 170)
        XCTAssertEqual(HRZone.ceilingBPM(for: .z5, maxHR: 190), 190)
    }

    func test_ceilingBPM_isInverseOfZoneClassifier() {
        // One bpm above a zone's ceiling lands in the next zone up.
        let maxHR = 190
        for zone in [HRZone.z1, .z2, .z3, .z4] {
            let ceiling = HRZone.ceilingBPM(for: zone, maxHR: maxHR)
            XCTAssertEqual(HRZone.zone(forBPM: ceiling, maxHR: maxHR), zone)
            XCTAssertEqual(HRZone.zone(forBPM: ceiling + 1, maxHR: maxHR).rawValue, zone.rawValue + 1)
        }
    }

    // MARK: - isValidOverride

    func test_isValidOverride_boundaries() {
        XCTAssertFalse(HRZone.isValidOverride(HRZone.overrideMinBPM - 1))   // 119
        XCTAssertTrue(HRZone.isValidOverride(HRZone.overrideMinBPM))        // 120
        XCTAssertTrue(HRZone.isValidOverride(HRZone.defaultOverrideBPM))    // 180
        XCTAssertTrue(HRZone.isValidOverride(HRZone.overrideMaxBPM))        // 220
        XCTAssertFalse(HRZone.isValidOverride(HRZone.overrideMaxBPM + 1))   // 221
    }

    func test_overrideConstants() {
        XCTAssertEqual(HRZone.overrideMinBPM, 120)
        XCTAssertEqual(HRZone.overrideMaxBPM, 220)
        XCTAssertEqual(HRZone.defaultOverrideBPM, 180)
    }
}
