// StatFormattingTests.swift — the count/ratio/percent strings every stats
// surface prints, plus the comparison-row RatioDisplay.
import XCTest
@testable import DeuceMateCore

final class StatFormattingTests: XCTestCase {

    func test_countAndPercent_truncatesAndHonoursGap() {
        XCTAssertEqual(StatFormatting.countAndPercent(76, of: 140), "76 (54%)")
        XCTAssertEqual(StatFormatting.countAndPercent(76, of: 140, gap: "  "), "76  (54%)")
        XCTAssertEqual(StatFormatting.countAndPercent(0, of: 0), "0")
    }

    func test_fractionAndPercent_truncatesAndHonoursGap() {
        XCTAssertEqual(StatFormatting.fractionAndPercent(3, 8), "3/8 (37%)")
        XCTAssertEqual(StatFormatting.fractionAndPercent(3, 8, gap: "  "), "3/8  (37%)")
        XCTAssertEqual(StatFormatting.fractionAndPercent(0, 0), "0/0")
    }

    func test_truncatedVersusRoundedPercent() {
        // 5/8 = 62.5%: exports truncate, the points-won headers round.
        XCTAssertEqual(StatFormatting.truncatedPercent(5, of: 8), 62)
        XCTAssertEqual(StatFormatting.roundedPercent(5, of: 8), 63)
        XCTAssertEqual(StatFormatting.truncatedPercent(1, of: 0), 0)
        XCTAssertEqual(StatFormatting.roundedPercent(1, of: 0), 0)
    }

    func test_ratioDisplay_resolvesFractionPercentAndCount() {
        let ratio = RatioDisplay(numerator: 12, denominator: 15)
        XCTAssertEqual(ratio.fraction, 0.8, accuracy: 0.0001)
        XCTAssertEqual(ratio.percentText, "80%")
        XCTAssertEqual(ratio.countText, "12/15")
    }

    func test_ratioDisplay_emptyDenominatorRendersDash() {
        let ratio = RatioDisplay(numerator: 0, denominator: 0)
        XCTAssertEqual(ratio.fraction, 0)
        XCTAssertEqual(ratio.percentText, "—")
        XCTAssertNil(ratio.countText)
    }
}
