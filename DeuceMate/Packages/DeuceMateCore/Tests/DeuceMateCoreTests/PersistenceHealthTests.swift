// PersistenceHealthTests.swift — the precedence and clearing rules for the
// user-facing persistence warning. These rules decide whether a user is told
// that a match didn't reach disk, so they are asserted rather than assumed.
import XCTest
@testable import DeuceMateCore

final class PersistenceHealthTests: XCTestCase {

    private func failure(_ operation: PersistenceOperation,
                         _ detail: String = "boom") -> PersistenceFailure {
        PersistenceFailure(operation: operation, detail: detail)
    }

    func test_healthyStore_hasNoWarning() {
        let health = PersistenceHealth()
        XCTAssertNil(health.failure)
        XCTAssertNil(health.warning)
    }

    func test_recordedFailure_producesWarningCopyForItsOperation() {
        var health = PersistenceHealth()
        XCTAssertTrue(health.record(failure(.saveLiveMatch)))
        XCTAssertEqual(health.warning, PersistenceHealth.warning(for: .saveLiveMatch))
        XCTAssertEqual(health.warning?.severity, .critical)
    }

    func test_warningLevelFailure_doesNotDisplaceCriticalOne() {
        var health = PersistenceHealth()
        health.record(failure(.saveLiveMatch))
        XCTAssertFalse(health.record(failure(.readMatchHistory)))
        XCTAssertEqual(health.failure?.operation, .saveLiveMatch)
    }

    func test_criticalFailure_displacesWarningLevelOne() {
        var health = PersistenceHealth()
        health.record(failure(.readMatchHistory))
        XCTAssertTrue(health.record(failure(.saveMatchHistory)))
        XCTAssertEqual(health.failure?.operation, .saveMatchHistory)
    }

    func test_equallySevereFailure_replacesTheOlderOne() {
        var health = PersistenceHealth()
        health.record(failure(.saveLiveMatch, "first"))
        XCTAssertTrue(health.record(failure(.saveMatchHistory, "second")))
        XCTAssertEqual(health.failure?.operation, .saveMatchHistory)
        XCTAssertEqual(health.failure?.detail, "second")
    }

    func test_successClearsOnlyTheSameOperation() {
        var health = PersistenceHealth()
        health.record(failure(.saveLiveMatch))

        // A history write landing says nothing about the live-match checkpoint.
        XCTAssertFalse(health.recordSuccess(of: .saveMatchHistory))
        XCTAssertEqual(health.failure?.operation, .saveLiveMatch)

        XCTAssertTrue(health.recordSuccess(of: .saveLiveMatch))
        XCTAssertNil(health.failure)
        XCTAssertNil(health.warning)
    }

    func test_successOnHealthyStore_isANoOp() {
        var health = PersistenceHealth()
        XCTAssertFalse(health.recordSuccess(of: .saveLiveMatch))
        XCTAssertNil(health.failure)
    }

    func test_acknowledgeClearsAnyFailure() {
        var health = PersistenceHealth()
        health.record(failure(.archiveWritesSuspended))
        health.acknowledge()
        XCTAssertNil(health.failure)
    }

    func test_applyFoldsOutcomesInBothDirections() {
        var health = PersistenceHealth()
        XCTAssertTrue(health.apply(.failed(failure(.saveMatchHistory))))
        XCTAssertEqual(health.failure?.operation, .saveMatchHistory)
        XCTAssertTrue(health.apply(.succeeded(.saveMatchHistory)))
        XCTAssertNil(health.failure)
    }

    func test_everyOperationHasNonEmptyDistinctCopy() {
        var titles: Set<String> = []
        for operation in PersistenceOperation.allCases {
            let warning = PersistenceHealth.warning(for: operation)
            XCTAssertFalse(warning.title.isEmpty, "\(operation) has no title")
            XCTAssertFalse(warning.message.isEmpty, "\(operation) has no message")
            XCTAssertFalse(warning.systemImage.isEmpty, "\(operation) has no symbol")
            titles.insert(warning.title)
        }
        // Two operations may legitimately share copy only if they share a
        // consequence; today none do, so a collision means a copy/paste slip.
        XCTAssertEqual(titles.count, PersistenceOperation.allCases.count)
    }

    func test_saveFailuresAreCriticalAndReadFailuresAreNot() {
        XCTAssertEqual(PersistenceOperation.saveLiveMatch.severity, .critical)
        XCTAssertEqual(PersistenceOperation.saveMatchHistory.severity, .critical)
        XCTAssertEqual(PersistenceOperation.archiveWritesSuspended.severity, .critical)
        XCTAssertEqual(PersistenceOperation.restoreLiveMatch.severity, .warning)
        XCTAssertEqual(PersistenceOperation.readMatchHistory.severity, .warning)
        XCTAssertEqual(PersistenceOperation.archiveQuarantined.severity, .warning)
    }
}
