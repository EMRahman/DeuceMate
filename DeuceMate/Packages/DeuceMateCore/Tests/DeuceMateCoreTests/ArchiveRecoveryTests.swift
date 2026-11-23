// ArchiveRecoveryTests.swift — reading a backup one match at a time, and the
// recovery wording (TECHNICAL_DEBT #18).
import XCTest
@testable import DeuceMateCore

final class ArchiveRecoveryTests: XCTestCase {

    private func record(_ id: UUID = UUID()) -> MatchRecord {
        MatchRecord(
            id: id,
            startTime: Date(timeIntervalSince1970: 1_000),
            endTime: Date(timeIntervalSince1970: 2_000),
            setScores: [SetScore(gamesMe: 6, gamesOpponent: 4)],
            stats: [],
            iWon: true
        )
    }

    private func json(_ records: [MatchRecord]) throws -> String {
        String(decoding: try JSONEncoder().encode(records), as: UTF8.self)
    }

    // MARK: - LenientRecordList

    func test_lenientList_readsEveryMatchWhenAllDecode() throws {
        let a = record(), b = record()
        let list = try JSONDecoder().decode(LenientRecordList.self, from: JSONEncoder().encode([a, b]))
        XCTAssertEqual(list.records, [a, b])
        XCTAssertEqual(list.undecodableCount, 0)
    }

    func test_lenientList_skipsOnlyTheMatchFromANewerBuild() throws {
        let before = record(), after = record()
        let newer = #"{"id":"\#(UUID().uuidString)","stats":[{"outcome":"smash"}]}"#
        let text = "[\(try json([before]).dropFirst().dropLast()),\(newer),\(try json([after]).dropFirst().dropLast())]"
        let data = Data(text.utf8)
        XCTAssertNil(try? JSONDecoder().decode([MatchRecord].self, from: data))

        let list = try JSONDecoder().decode(LenientRecordList.self, from: data)
        XCTAssertEqual(list.records, [before, after])
        XCTAssertEqual(list.undecodableCount, 1)
    }

    func test_lenientList_stillRejectsAFileThatIsNotAList() {
        XCTAssertThrowsError(try JSONDecoder().decode(LenientRecordList.self, from: Data("{}".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(LenientRecordList.self, from: Data("not json".utf8)))
    }

    // MARK: - Wording

    func test_matchCountsArePluralised() {
        XCTAssertEqual(BackupWithheldCopy.matches(1), "1 match")
        XCTAssertEqual(BackupWithheldCopy.matches(3), "3 matches")
        XCTAssertTrue(BackupWithheldCopy.message(count: 1).hasPrefix("1 match in your iCloud backup isn't on this iPhone"))
        XCTAssertTrue(BackupWithheldCopy.message(count: 2).hasPrefix("2 matches in your iCloud backup aren't on this iPhone"))
        XCTAssertEqual(BackupWithheldCopy.removeTitle(count: 2), "Remove 2 matches from iCloud Backup?")
    }

    func test_destructiveChoicesSayACopyIsKept() {
        XCTAssertTrue(BackupWithheldCopy.removeMessage(count: 2).contains("keeps a copy"))
        let preview = ArchiveBackupPolicy.BackupPreview(recordCount: 4, newestMatchDate: nil)
        XCTAssertTrue(ICloudArchiveRestore.available(preview, newerFormatCount: 0).message.contains("keeps a copy"))
    }

    func test_restoreSaysWhichMatchesStayInTheBackup() {
        let preview = ArchiveBackupPolicy.BackupPreview(recordCount: 4, newestMatchDate: nil)
        let none = ICloudArchiveRestore.available(preview, newerFormatCount: 0).message
        XCTAssertTrue(none.hasPrefix("Your iCloud backup has 4 matches."))
        XCTAssertFalse(none.contains("newer version"))
        XCTAssertTrue(ICloudArchiveRestore.available(preview, newerFormatCount: 1).message
            .contains("1 match needs a newer version of DeuceMate and will stay in the backup."))
        XCTAssertTrue(BackupWithheldCopy.broughtBackMessage(count: 2, stillMissing: 1)
            .contains("1 match needs a newer version of DeuceMate and stays in the backup."))
        XCTAssertFalse(BackupWithheldCopy.broughtBackMessage(count: 2, stillMissing: 0).contains("newer"))
    }

    func test_restorePromptNamesMatchesThatStayInTheBackup() {
        XCTAssertNil(ArchiveRecoveryCopy.restorePromptNewerNote(count: 0))
        XCTAssertEqual(
            ArchiveRecoveryCopy.restorePromptNewerNote(count: 1),
            "1 match needs a newer version of DeuceMate and will stay in the backup."
        )
        XCTAssertTrue(ArchiveRecoveryCopy.restorePromptNewerNote(count: 3)?.hasPrefix("3 matches need a newer") == true)
        let preview = ArchiveBackupPolicy.BackupPreview.from(records: [], newerFormatCount: 2)
        XCTAssertEqual(preview.newerFormatCount, 2)
        XCTAssertEqual(ArchiveBackupPolicy.BackupPreview.from(records: []).newerFormatCount, 0)
    }

    func test_broughtBackWhileBackupIsPendingDoesNotClaimNothingChanged() {
        let message = BackupWithheldCopy.broughtBackPendingMessage(count: 2, stillMissing: 1)
        XCTAssertTrue(message.hasPrefix("Brought back 2 matches"))
        XCTAssertTrue(message.contains("will update it when it can"))
        XCTAssertFalse(message.contains("Nothing has been changed"))
        XCTAssertFalse(ArchiveRecoveryCopy.restoredBackupNotResumedMessage.contains("Nothing has been changed"))
    }

    func test_replaceConfirmationSaysACopyOfTheBackupIsKept() {
        XCTAssertTrue(ArchiveRecoveryCopy.replaceKeepsBackupCopyNote.contains("keeps a copy of the current iCloud backup"))
    }

    func test_everyOutcomeHasCopy() {
        let preview = ArchiveBackupPolicy.BackupPreview(recordCount: 1, newestMatchDate: Date())
        let outcomes: [ICloudArchiveRestore] = [
            .available(preview, newerFormatCount: 0),
            .noBackup,
            .iCloudUnavailable,
            .downloading,
            .requiresNewerVersion(count: nil),
            .requiresNewerVersion(count: 2),
            .unreadable,
        ]
        for outcome in outcomes {
            XCTAssertFalse(outcome.title.isEmpty)
            XCTAssertFalse(outcome.message.isEmpty)
        }
        XCTAssertTrue(ICloudArchiveRestore.requiresNewerVersion(count: nil).message.contains("newer version"))
        XCTAssertTrue(ICloudArchiveRestore.requiresNewerVersion(count: nil).message.contains("Nothing has been changed"))
        XCTAssertTrue(ICloudArchiveRestore.requiresNewerVersion(count: 2).message.contains("2 matches"))
        XCTAssertTrue(ICloudArchiveRestore.requiresNewerVersion(count: 1).message.contains("1 match in your iCloud backup needs"))
        XCTAssertTrue(ICloudArchiveRestore.unreadable.message.contains("Nothing has been changed"))
        XCTAssertTrue(BackupWithheldCopy.failedMessage.contains("Nothing has been changed"))
        XCTAssertTrue(ArchiveRecoveryCopy.stillUnavailableMessage.contains("Nothing has been changed"))
    }

    func test_remoteBackupProblemHasTruthfulCopy() {
        for problem in RemoteBackupProblem.allCases {
            XCTAssertFalse(problem.title.isEmpty)
            XCTAssertFalse(problem.message.isEmpty)
            XCTAssertFalse(problem.systemImage.isEmpty)
            XCTAssertTrue(problem.message.contains("untouched"))
            XCTAssertTrue(problem.message.contains("paused"))
        }
        XCTAssertTrue(RemoteBackupProblem.newerVersion.message.contains("newer version"))
    }

    func testSaveFailureCopySaysNothingChangedAndNamesThePauseOnlyWhenPaused() {
        for paused in [true, false] {
            XCTAssertTrue(ArchiveSaveFailureCopy.message(savingPaused: paused).contains("Nothing has been changed"))
        }
        XCTAssertTrue(ArchiveSaveFailureCopy.message(savingPaused: true).contains("Saving is paused"))
        XCTAssertFalse(ArchiveSaveFailureCopy.message(savingPaused: false).contains("paused"))
    }
}
