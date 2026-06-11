// SettingsCopyTests.swift — invariants for the shared setting summaries: every
// case must have concise, well-formed, single-line copy. This is the cheapest
// correctness signal (pure logic, no simulator) guarding the copy from regressions.
import XCTest
@testable import DeuceMateCore

final class SettingsCopyTests: XCTestCase {

    func test_everyCase_hasWellFormedCopy() {
        for setting in SettingsCopy.allCases {
            let text = setting.text
            XCTAssertFalse(text.isEmpty, "\(setting) has empty copy")
            XCTAssertEqual(
                text,
                text.trimmingCharacters(in: .whitespacesAndNewlines),
                "\(setting) has leading/trailing whitespace"
            )
            XCTAssertFalse(text.contains("\n"), "\(setting) must be a single line")
            XCTAssertTrue(text.hasSuffix("."), "\(setting) must end with a period")
            XCTAssertLessThanOrEqual(
                text.count,
                SettingsCopy.maxLength,
                "\(setting) is \(text.count) chars (> \(SettingsCopy.maxLength))"
            )
        }
    }

    func test_caseCount_matchesKnownSettings() {
        // Guards against a forgotten or accidentally duplicated case.
        XCTAssertEqual(SettingsCopy.allCases.count, 10)
    }
}
