// ArchiveLoadProblemTests.swift — the archive screen's copy and diagnosis
// precedence when the iPhone archive can't be loaded (TECHNICAL_DEBT #18).
import XCTest
@testable import DeuceMateCore

final class ArchiveLoadProblemTests: XCTestCase {

    func test_undecodableIsTheMorePersistentDiagnosis() {
        XCTAssertEqual(ArchiveLoadProblem.unreadable.combined(with: nil), .unreadable)
        XCTAssertEqual(ArchiveLoadProblem.undecodable.combined(with: nil), .undecodable)
        XCTAssertEqual(ArchiveLoadProblem.unreadable.combined(with: .undecodable), .undecodable)
        XCTAssertEqual(ArchiveLoadProblem.undecodable.combined(with: .unreadable), .undecodable)
        XCTAssertEqual(ArchiveLoadProblem.unreadable.combined(with: .unreadable), .unreadable)
    }

    func test_copyStatesWhatTheAppDoesAndNeverClaimsLossOrRecovery() {
        for problem in ArchiveLoadProblem.allCases {
            XCTAssertFalse(problem.title.isEmpty)
            XCTAssertFalse(problem.systemImage.isEmpty)
            let message = problem.message
            XCTAssertTrue(message.contains("untouched"), "\(problem) must say nothing was deleted")
            XCTAssertTrue(message.contains("won't save changes or back up to iCloud"), "\(problem) must say saving and backup stopped")
            XCTAssertTrue(message.contains("Apple Watch"))
            for overclaim in ["deleted", "lost", "recovered", "Restore"] {
                XCTAssertFalse(message.contains(overclaim), "\(problem) copy must not say \"\(overclaim)\"")
            }
        }
        // Only the transient diagnosis suggests trying again (stage 3 put a
        // Try Again button beside it, replacing "Restart DeuceMate"); only the
        // deterministic one suggests an update.
        XCTAssertTrue(ArchiveLoadProblem.unreadable.message.contains("try again"))
        XCTAssertFalse(ArchiveLoadProblem.undecodable.message.contains("try again"))
        XCTAssertTrue(ArchiveLoadProblem.undecodable.message.contains("update"))
    }
}
