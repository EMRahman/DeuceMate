// MatchSetupDefaultsTests.swift — the remembered match setup must decode
// totally: nothing here should ever be able to crash a launch.
import XCTest
@testable import DeuceMateCore

final class MatchSetupDefaultsTests: XCTestCase {

    private let allFormats: [MatchFormat] = [
        .standard, .bestOf3FullFinalSet, .superTiebreak,
        .perpetualSuperTiebreak, .shortSets, .fast4, .perpetualPoints
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

    func test_resolve_quick4GamesFormat_isRemembered() {
        // Quick 4 Games is offered in match setup again, so a remembered
        // choice must be restored rather than falling back.
        let resolved = MatchSetupDefaults.resolve(
            formatRaw: MatchFormat.quick4Games.rawValue,
            typeRaw: MatchType.doubles.rawValue
        )
        XCTAssertEqual(resolved.format, .quick4Games)
        XCTAssertEqual(resolved.type, .doubles)
    }

    func test_resolve_everyOfferedFormat_roundTrips() {
        for format in MatchFormat.userSelectable {
            let resolved = MatchSetupDefaults.resolve(formatRaw: format.rawValue, typeRaw: MatchType.singles.rawValue)
            XCTAssertEqual(resolved.format, format, "\(format) is offered, so it must be remembered")
        }
    }

    func test_resolve_onlyTheInvalidHalfFallsBack() {
        let formatOnly = MatchSetupDefaults.resolve(formatRaw: MatchFormat.shortSets.rawValue, typeRaw: "unknown")
        XCTAssertEqual(formatOnly.format, .shortSets)
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
