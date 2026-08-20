// SetFilterTests.swift — the shared "All / per-set" scope and its labels.
import XCTest
@testable import DeuceMateCore

final class SetFilterTests: XCTestCase {

    func test_allLabel_isStyleIndependent() {
        XCTAssertEqual(SetFilter.all.label(matchFormat: .standard), "All")
        XCTAssertEqual(SetFilter.all.label(matchFormat: .standard, style: .short), "All")
    }

    func test_regularSetLabels_useNumberInBothWidths() {
        XCTAssertEqual(SetFilter.set(0).label(matchFormat: .standard), "Set 1")
        XCTAssertEqual(SetFilter.set(1).label(matchFormat: .standard, style: .short), "S2")
        XCTAssertEqual(SetFilter.set(0).label(matchFormat: .quick4Games), "Set 1")
        // A full final set is still a regular set, not a "TB".
        XCTAssertEqual(SetFilter.set(2).label(matchFormat: .bestOf3FullFinalSet), "Set 3")
        XCTAssertEqual(SetFilter.set(2).label(matchFormat: .bestOf3FullFinalSet, style: .short), "S3")
    }

    func test_decidingSuperTiebreakLabel_isTB() {
        // .standard is best-of-3 with a super-tiebreak deciding set (index 2).
        XCTAssertEqual(SetFilter.set(2).label(matchFormat: .standard), "TB")
        XCTAssertEqual(SetFilter.set(2).label(matchFormat: .standard, style: .short), "TB")
    }

    func test_setIndices_coverAllSetsOrJustOne() {
        XCTAssertEqual(SetFilter.all.setIndices(setCount: 3), [0, 1, 2])
        XCTAssertEqual(SetFilter.all.setIndices(setCount: 0), [])
        XCTAssertEqual(SetFilter.set(1).setIndices(setCount: 3), [1])
    }

    func test_setIndex_isNilForAll() {
        XCTAssertNil(SetFilter.all.setIndex)
        XCTAssertEqual(SetFilter.set(2).setIndex, 2)
    }

    func test_filters_areAllPlusOnePerSet() {
        XCTAssertEqual(SetFilter.filters(setCount: 2), [.all, .set(0), .set(1)])
        XCTAssertEqual(SetFilter.filters(setCount: 0), [.all])
    }
}
