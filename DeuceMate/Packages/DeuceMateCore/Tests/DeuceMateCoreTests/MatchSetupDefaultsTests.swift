// MatchSetupDefaultsTests.swift — the remembered match setup must decode
// totally: nothing here should ever be able to crash a launch.
import XCTest
@testable import DeuceMateCore

final class MatchSetupDefaultsTests: XCTestCase {

    private let allFormats: [MatchFormat] = [
        .standard, .bestOf3FullFinalSet, .superTiebreak,
        .perpetualSuperTiebreak, .quick4Games, .perpetualPoints
    ]
    private let allTypes: [MatchType] = [.singles, .doubles]

    func test_resolve_bothNil_fallsBackToStandardSingles() {
        let resolved = MatchSetupDefaults.resolve(formatRaw: nil, typeRaw: nil)
        XCTAssertEqual(resolved, .fallback)
        XCTAssertEqual(resolved.format, .standard)
        XCTAssertEqual(resolved.type, .singles)
    }

    func test_resolve_emptyStrings_fallBack() {
        let resolved = MatchSetupDefaults.resolve(formatRaw: "", typeRaw: "")
        XCTAssertEqual(resolved, .fallback)
    }

    func test_resolve_unknownRawValues_fallBack() {
        // Simulates a format/type retired in a future build.
        let resolved = MatchSetupDefaults.resolve(formatRaw: "octupleOvertime", typeRaw: "mixed")
        XCTAssertEqual(resolved, .fallback)
    }

    func test_resolve_onlyTheInvalidHalfFallsBack() {
        let formatOnly = MatchSetupDefaults.resolve(formatRaw: MatchFormat.quick4Games.rawValue, typeRaw: "unknown")
        XCTAssertEqual(formatOnly.format, .quick4Games)
        XCTAssertEqual(formatOnly.type, .singles)

        let typeOnly = MatchSetupDefaults.resolve(formatRaw: "unknown", typeRaw: MatchType.doubles.rawValue)
        XCTAssertEqual(typeOnly.format, .standard)
        XCTAssertEqual(typeOnly.type, .doubles)
    }

    func test_resolve_roundTrips_everyFormatByTypePair() {
        for format in allFormats {
            for type in allTypes {
                let resolved = MatchSetupDefaults.resolve(formatRaw: format.rawValue, typeRaw: type.rawValue)
                XCTAssertEqual(resolved.format, format)
                XCTAssertEqual(resolved.type, type)
            }
        }
    }
}
