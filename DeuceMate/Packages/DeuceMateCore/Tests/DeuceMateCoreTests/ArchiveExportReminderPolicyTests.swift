// ArchiveExportReminderPolicyTests.swift — pure policy and copy tests for
// docs/features/ARCHIVE_EXPORT_REMINDER_PLAN.md (§6, §7).
import XCTest
@testable import DeuceMateCore

final class ArchiveExportReminderPolicyTests: XCTestCase {

    private let baseTime = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeRecord(
        id: UUID = UUID(),
        endOffset: TimeInterval? = 0,
        iWon: Bool? = true,
        totalSteps: Int? = nil,
        totalCaloriesKcal: Double? = nil,
        totalDistanceMeters: Double? = nil,
        heartRateBPM: Int? = nil,
        stepsCumulative: Int? = nil
    ) -> MatchRecord {
        let stats: [PointStat] = (heartRateBPM != nil || stepsCumulative != nil)
            ? [PointStat(
                setIndex: 0,
                server: .me,
                winner: .me,
                outcome: .winner,
                heartRateBPM: heartRateBPM,
                stepsCumulative: stepsCumulative
            )]
            : []
        let endTime = endOffset.map { baseTime.addingTimeInterval($0) }
        return MatchRecord(
            id: id,
            startTime: baseTime.addingTimeInterval((endOffset ?? 0) - 3600),
            endTime: endTime,
            setScores: [],
            stats: stats,
            iWon: endTime == nil ? nil : iWon,
            totalSteps: totalSteps,
            totalDistanceMeters: totalDistanceMeters,
            totalCaloriesKcal: totalCaloriesKcal
        )
    }

    // MARK: - Constants pinned

    func test_constantsArePinned() {
        XCTAssertEqual(ArchiveExportReminderPolicy.threshold, 5)
        XCTAssertEqual(ArchiveExportReminderPolicy.enabledKey, "archiveExportReminderEnabled")
        XCTAssertEqual(ArchiveExportReminderPolicy.baselineKey, "archiveExportReminderBaseline")
        XCTAssertEqual(ArchiveExportReminderPolicy.lastExportDateKey, "archiveLastExportDate")
    }

    // MARK: - Threshold boundaries (4 / 5 / 6)

    func test_thresholdBoundaries_fourHidden_fiveAndSixDue() {
        let records = (1...6).map { i in
            makeRecord(endOffset: TimeInterval(i * 60), totalSteps: 1000)
        }

        let four = ArchiveExportReminderPolicy.state(
            records: Array(records.prefix(4)),
            matchIDsWithNotes: [],
            isEnabled: true,
            archiveOpenedNormally: true,
            backupProtectsNonHealthData: true,
            baseline: nil
        )
        XCTAssertEqual(four, .hidden)

        let five = ArchiveExportReminderPolicy.state(
            records: Array(records.prefix(5)),
            matchIDsWithNotes: [],
            isEnabled: true,
            archiveOpenedNormally: true,
            backupProtectsNonHealthData: true,
            baseline: nil
        )
        XCTAssertEqual(five, .due(count: 5, missing: [.health]))

        let six = ArchiveExportReminderPolicy.state(
            records: records,
            matchIDsWithNotes: [],
            isEnabled: true,
            archiveOpenedNormally: true,
            backupProtectsNonHealthData: true,
            baseline: nil
        )
        XCTAssertEqual(six, .due(count: 6, missing: [.health]))
    }

    // MARK: - What counts (§3.2)

    func test_plainMatchesNotCountedWhenICloudProtectsNonHealthData() {
        let plain = (1...6).map { i in
            makeRecord(endOffset: TimeInterval(i * 60))
        }
        let state = ArchiveExportReminderPolicy.state(
            records: plain,
            matchIDsWithNotes: [],
            isEnabled: true,
            archiveOpenedNormally: true,
            backupProtectsNonHealthData: true,
            baseline: nil
        )
        XCTAssertEqual(state, .hidden)
    }

    func test_plainMatchesCountedWhenICloudOffOrUnavailable() {
        let plain = (1...5).map { i in
            makeRecord(endOffset: TimeInterval(i * 60))
        }
        let state = ArchiveExportReminderPolicy.state(
            records: plain,
            matchIDsWithNotes: [],
            isEnabled: true,
            archiveOpenedNormally: true,
            backupProtectsNonHealthData: false,
            baseline: nil
        )
        XCTAssertEqual(state, .due(count: 5, missing: [.everything]))
    }

    func test_inProgressMatchesNeverCount() {
        let inProgress = (1...6).map { _ in
            makeRecord(endOffset: nil, iWon: nil, totalSteps: 500)
        }
        let countWithCloud = ArchiveExportReminderPolicy.countableMatchCount(
            records: inProgress,
            matchIDsWithNotes: Set(inProgress.map(\.id)),
            backupProtectsNonHealthData: true,
            since: nil
        )
        let countWithoutCloud = ArchiveExportReminderPolicy.countableMatchCount(
            records: inProgress,
            matchIDsWithNotes: Set(inProgress.map(\.id)),
            backupProtectsNonHealthData: false,
            since: nil
        )
        XCTAssertEqual(countWithCloud, 0)
        XCTAssertEqual(countWithoutCloud, 0)
    }

    func test_completedDrawCounts() {
        let draws = (1...5).map { i in
            makeRecord(endOffset: TimeInterval(i * 60), iWon: nil, totalSteps: 500)
        }
        let state = ArchiveExportReminderPolicy.state(
            records: draws,
            matchIDsWithNotes: [],
            isEnabled: true,
            archiveOpenedNormally: true,
            backupProtectsNonHealthData: true,
            baseline: nil
        )
        XCTAssertEqual(state, .due(count: 5, missing: [.health]))
    }

    func test_storedZeroHealthFieldCounts() {
        let zeroHealthRecords = [
            makeRecord(endOffset: 60, totalSteps: 0),
            makeRecord(endOffset: 120, totalCaloriesKcal: 0),
            makeRecord(endOffset: 180, totalDistanceMeters: 0),
            makeRecord(endOffset: 240, heartRateBPM: 0),
            makeRecord(endOffset: 300, stepsCumulative: 0),
        ]
        let state = ArchiveExportReminderPolicy.state(
            records: zeroHealthRecords,
            matchIDsWithNotes: [],
            isEnabled: true,
            archiveOpenedNormally: true,
            backupProtectsNonHealthData: true,
            baseline: nil
        )
        XCTAssertEqual(state, .due(count: 5, missing: [.health]))
    }

    func test_privateNotesOnlyCountsAndMarksNotesMissing() {
        let records = (1...5).map { i in
            makeRecord(endOffset: TimeInterval(i * 60))
        }
        let noteIDs = Set(records.map(\.id))
        let state = ArchiveExportReminderPolicy.state(
            records: records,
            matchIDsWithNotes: noteIDs,
            isEnabled: true,
            archiveOpenedNormally: true,
            backupProtectsNonHealthData: true,
            baseline: nil
        )
        XCTAssertEqual(state, .due(count: 5, missing: [.notes]))
    }

    func test_healthAndNotesMarksBothMissing() {
        let records = (1...5).map { i in
            makeRecord(endOffset: TimeInterval(i * 60), totalSteps: i == 1 ? 1000 : nil)
        }
        let noteIDs = Set(records.dropFirst().map(\.id))
        let state = ArchiveExportReminderPolicy.state(
            records: records,
            matchIDsWithNotes: noteIDs,
            isEnabled: true,
            archiveOpenedNormally: true,
            backupProtectsNonHealthData: true,
            baseline: nil
        )
        XCTAssertEqual(state, .due(count: 5, missing: [.health, .notes]))
    }

    // MARK: - Baseline & gates

    func test_baselineExcludesEarlierAndEqualCompletionDates() {
        let baseline = baseTime.addingTimeInterval(300)
        let records = [
            makeRecord(endOffset: 100, totalSteps: 100), // before
            makeRecord(endOffset: 300, totalSteps: 100), // equal -> excluded
            makeRecord(endOffset: 301, totalSteps: 100), // after (1)
            makeRecord(endOffset: 400, totalSteps: 100), // after (2)
            makeRecord(endOffset: 500, totalSteps: 100), // after (3)
            makeRecord(endOffset: 600, totalSteps: 100), // after (4)
            makeRecord(endOffset: 700, totalSteps: 100), // after (5)
        ]
        XCTAssertEqual(
            ArchiveExportReminderPolicy.countableMatchCount(
                records: records,
                matchIDsWithNotes: [],
                backupProtectsNonHealthData: true,
                since: baseline
            ),
            5
        )
        let hiddenAfterDelete = ArchiveExportReminderPolicy.state(
            records: Array(records.dropLast()),
            matchIDsWithNotes: [],
            isEnabled: true,
            archiveOpenedNormally: true,
            backupProtectsNonHealthData: true,
            baseline: baseline
        )
        XCTAssertEqual(hiddenAfterDelete, .hidden)
    }

    func test_disabledOrUnreadableArchiveAlwaysHides() {
        let records = (1...6).map { i in
            makeRecord(endOffset: TimeInterval(i * 60), totalSteps: 500)
        }
        XCTAssertEqual(
            ArchiveExportReminderPolicy.state(
                records: records,
                matchIDsWithNotes: [],
                isEnabled: false,
                archiveOpenedNormally: true,
                backupProtectsNonHealthData: true,
                baseline: nil
            ),
            .hidden
        )
        XCTAssertEqual(
            ArchiveExportReminderPolicy.state(
                records: records,
                matchIDsWithNotes: [],
                isEnabled: true,
                archiveOpenedNormally: false,
                backupProtectsNonHealthData: true,
                baseline: nil
            ),
            .hidden
        )
    }

    func test_baselineAfterImport_neverMovesBackwards() {
        let older = baseTime.addingTimeInterval(100)
        let newer = baseTime.addingTimeInterval(500)
        XCTAssertEqual(
            ArchiveExportReminderPolicy.baselineAfterImport(current: nil, archiveExportedAt: older),
            older
        )
        XCTAssertEqual(
            ArchiveExportReminderPolicy.baselineAfterImport(current: older, archiveExportedAt: newer),
            newer
        )
        XCTAssertEqual(
            ArchiveExportReminderPolicy.baselineAfterImport(current: newer, archiveExportedAt: older),
            newer
        )
    }

    func test_backupProtectsNonHealthData_matchesICloudBackupCopy() {
        XCTAssertTrue(ArchiveExportReminderPolicy.backupProtectsNonHealthData(for: .backedUp))
        XCTAssertTrue(ArchiveExportReminderPolicy.backupProtectsNonHealthData(for: .pendingUpload))
        XCTAssertTrue(ArchiveExportReminderPolicy.backupProtectsNonHealthData(for: .restoring))
        XCTAssertTrue(ArchiveExportReminderPolicy.backupProtectsNonHealthData(for: .pendingRestore))
        XCTAssertFalse(ArchiveExportReminderPolicy.backupProtectsNonHealthData(for: .notBackedUp))
        XCTAssertFalse(ArchiveExportReminderPolicy.backupProtectsNonHealthData(for: .unavailable))
    }

    // MARK: - Copy invariants (§1, §2.1, §4, §6)

    func test_copyVariants_matchCategoriesAndAvoidOverclaims() {
        let healthOnly = ArchiveExportReminderCopy.body(count: 5, missing: [.health])
        XCTAssertTrue(healthOnly.contains("5 matches"))
        XCTAssertTrue(healthOnly.contains("heart rate"))
        XCTAssertTrue(healthOnly.contains("steps"))
        XCTAssertTrue(healthOnly.contains("distance"))
        XCTAssertTrue(healthOnly.contains("calories"))
        XCTAssertFalse(healthOnly.localizedCaseInsensitiveContains("private notes"))

        let notesOnly = ArchiveExportReminderCopy.body(count: 5, missing: [.notes])
        XCTAssertTrue(notesOnly.contains("5 matches"))
        XCTAssertTrue(notesOnly.localizedCaseInsensitiveContains("private notes"))
        XCTAssertTrue(notesOnly.localizedCaseInsensitiveContains("choose"))
        XCTAssertFalse(notesOnly.localizedCaseInsensitiveContains("heart rate"))
        XCTAssertFalse(notesOnly.localizedCaseInsensitiveContains("calories"))

        let healthAndNotes = ArchiveExportReminderCopy.body(count: 8, missing: [.health, .notes])
        XCTAssertTrue(healthAndNotes.contains("8 matches"))
        XCTAssertTrue(healthAndNotes.contains("heart rate"))
        XCTAssertTrue(healthAndNotes.localizedCaseInsensitiveContains("private notes"))
        XCTAssertTrue(healthAndNotes.localizedCaseInsensitiveContains("choose"))

        let noCloud = ArchiveExportReminderCopy.body(count: 5, missing: [.everything])
        XCTAssertTrue(noCloud.contains("Your matches aren't backed up anywhere else."))
        XCTAssertFalse(noCloud.localizedCaseInsensitiveContains("iCloud"))

        let noCloudWithNotes = ArchiveExportReminderCopy.body(count: 5, missing: [.everything, .notes])
        XCTAssertTrue(noCloudWithNotes.contains("Your matches aren't backed up anywhere else."))
        XCTAssertTrue(noCloudWithNotes.localizedCaseInsensitiveContains("private notes"))
        XCTAssertTrue(noCloudWithNotes.localizedCaseInsensitiveContains("choose"))

        // Honesty and Guideline 5.1.3(ii) guardrails across every variant:
        // never claim "lost forever"/"gone forever"/"always recoverable", and
        // never steer the user to save the file in iCloud Drive.
        let allVariants = [
            healthOnly,
            notesOnly,
            healthAndNotes,
            noCloud,
            noCloudWithNotes,
            ArchiveExportReminderCopy.body(count: 5, missing: []),
        ]
        for text in allVariants {
            XCTAssertFalse(text.localizedCaseInsensitiveContains("lost forever"), text)
            XCTAssertFalse(text.localizedCaseInsensitiveContains("gone forever"), text)
            XCTAssertFalse(text.localizedCaseInsensitiveContains("always recoverable"), text)
            XCTAssertFalse(text.localizedCaseInsensitiveContains("iCloud Drive"), text)
        }
    }

    func test_lastExportedText() {
        XCTAssertEqual(ArchiveExportReminderCopy.lastExportedText(formattedDate: nil), "Never exported")
        XCTAssertEqual(ArchiveExportReminderCopy.lastExportedText(formattedDate: ""), "Never exported")
        XCTAssertEqual(
            ArchiveExportReminderCopy.lastExportedText(formattedDate: "12 Nov 2026"),
            "Last exported 12 Nov 2026"
        )
    }
}
