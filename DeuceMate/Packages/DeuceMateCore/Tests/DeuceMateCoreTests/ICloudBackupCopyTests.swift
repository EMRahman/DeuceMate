// ICloudBackupCopyTests.swift — truth table for the global iCloud backup indicator.
// Pure logic, no simulator — the cheapest signal.
import XCTest
@testable import DeuceMateCore

final class ICloudBackupCopyTests: XCTestCase {

    func test_everyCase_hasWellFormedLabel() {
        for status in ICloudBackupCopy.allCases {
            let text = status.text
            XCTAssertFalse(text.isEmpty, "\(status) has empty label")
            XCTAssertEqual(
                text,
                text.trimmingCharacters(in: .whitespacesAndNewlines),
                "\(status) has leading/trailing whitespace"
            )
            XCTAssertFalse(text.contains("\n"), "\(status) must be a single line")
            XCTAssertFalse(status.systemImage.isEmpty, "\(status) has empty systemImage")
        }
    }

    func test_current_toggleOff_alwaysNotBackedUp() {
        XCTAssertEqual(ICloudBackupCopy.current(isEnabled: false, isAvailable: true, isUploaded: true), .notBackedUp)
        XCTAssertEqual(ICloudBackupCopy.current(isEnabled: false, isAvailable: false), .notBackedUp)
        XCTAssertEqual(ICloudBackupCopy.current(isEnabled: false, isAvailable: true, isRestoring: true), .notBackedUp)
        XCTAssertEqual(ICloudBackupCopy.current(isEnabled: false, isAvailable: true, hasPendingRestore: true), .notBackedUp)
    }

    func test_current_pausedForDamagedArchive_winsOverEverythingButToggleOff() {
        // ARCHIVE_DERISK_PLAN.md §3.3: a dated damaged copy pauses iCloud, and
        // the indicator must say so whatever else is going on.
        XCTAssertEqual(
            ICloudBackupCopy.current(isEnabled: true, isPausedForDamagedArchive: true, isAvailable: true, isUploaded: true),
            .pausedDamagedArchive
        )
        XCTAssertEqual(
            ICloudBackupCopy.current(isEnabled: true, isPausedForDamagedArchive: true, isAvailable: false),
            .pausedDamagedArchive
        )
        XCTAssertEqual(
            ICloudBackupCopy.current(
                isEnabled: true, isPausedForDamagedArchive: true, isAvailable: true,
                isRestoring: true, hasPendingRestore: true, isUploaded: nil
            ),
            .pausedDamagedArchive
        )
        // Only "toggle off" outranks it.
        XCTAssertEqual(
            ICloudBackupCopy.current(isEnabled: false, isPausedForDamagedArchive: true, isAvailable: true),
            .notBackedUp
        )
        // The default leaves every existing resolution unchanged.
        XCTAssertEqual(ICloudBackupCopy.current(isEnabled: true, isAvailable: true, isUploaded: true), .backedUp)
    }

    func test_pausedForDamagedArchive_copy() {
        XCTAssertEqual(ICloudBackupCopy.pausedDamagedArchive.text, "iCloud backup paused — your iCloud copy is unchanged")
        XCTAssertEqual(ICloudBackupCopy.pausedDamagedArchive.systemImage, "exclamationmark.icloud")
    }

    func test_current_unavailableWhenSignedOut() {
        XCTAssertEqual(ICloudBackupCopy.current(isEnabled: true, isAvailable: false), .unavailable)
        // Unavailability outranks restoring and pendingRestore (they require iCloud).
        XCTAssertEqual(ICloudBackupCopy.current(isEnabled: true, isAvailable: false, isRestoring: true), .unavailable)
        XCTAssertEqual(ICloudBackupCopy.current(isEnabled: true, isAvailable: false, hasPendingRestore: true), .unavailable)
    }

    func test_current_restoringOutranksPendingRestore() {
        XCTAssertEqual(
            ICloudBackupCopy.current(isEnabled: true, isAvailable: true, isRestoring: true),
            .restoring
        )
        // restoring outranks pendingRestore
        XCTAssertEqual(
            ICloudBackupCopy.current(isEnabled: true, isAvailable: true, isRestoring: true, hasPendingRestore: true),
            .restoring
        )
    }

    func test_current_pendingRestoreOutranksPendingUpload() {
        XCTAssertEqual(
            ICloudBackupCopy.current(isEnabled: true, isAvailable: true, hasPendingRestore: true),
            .pendingRestore
        )
        // pendingRestore outranks both pendingUpload cases
        XCTAssertEqual(
            ICloudBackupCopy.current(isEnabled: true, isAvailable: true, hasPendingRestore: true, isUploaded: false),
            .pendingRestore
        )
        XCTAssertEqual(
            ICloudBackupCopy.current(isEnabled: true, isAvailable: true, hasPendingRestore: true, isUploaded: nil),
            .pendingRestore
        )
    }

    func test_current_pendingUploadWhenNotYetUploaded() {
        // nil (never pushed) → pendingUpload
        XCTAssertEqual(
            ICloudBackupCopy.current(isEnabled: true, isAvailable: true, isUploaded: nil),
            .pendingUpload
        )
        // false (pushed but uploading) → pendingUpload
        XCTAssertEqual(
            ICloudBackupCopy.current(isEnabled: true, isAvailable: true, isUploaded: false),
            .pendingUpload
        )
    }

    func test_current_backedUpOnlyWhenUploadConfirmed() {
        XCTAssertEqual(
            ICloudBackupCopy.current(isEnabled: true, isAvailable: true, isUploaded: true),
            .backedUp
        )
    }

    func test_caseCount_isSeven() {
        XCTAssertEqual(ICloudBackupCopy.allCases.count, 7)
    }
}
