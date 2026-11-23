// ArchiveExportReminderCoordinatorTests.swift — iPhone-local UserDefaults
// persistence and state transitions around Core's `ArchiveExportReminderPolicy`
// (docs/features/ARCHIVE_EXPORT_REMINDER_PLAN.md §7).
import Foundation
import Testing
import DeuceMateCore
@testable import DeuceMate

@MainActor
struct ArchiveExportReminderCoordinatorTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let defaults: UserDefaults

    init() throws {
        let suite = "archive-export-reminder-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
    }

    private func healthMatch(endOffset: TimeInterval) -> MatchRecord {
        MatchRecord(
            id: UUID(),
            startTime: now.addingTimeInterval(endOffset - 3_600),
            endTime: now.addingTimeInterval(endOffset),
            setScores: [],
            stats: [PointStat(setIndex: 0, server: .me, winner: .me, outcome: .winner, heartRateBPM: 145)],
            iWon: true,
            totalSteps: 1200
        )
    }

    private func plainMatch(endOffset: TimeInterval) -> MatchRecord {
        MatchRecord(
            id: UUID(),
            startTime: now.addingTimeInterval(endOffset - 3_600),
            endTime: now.addingTimeInterval(endOffset),
            setScores: [],
            stats: [],
            iWon: true
        )
    }

    private func coordinator() -> ArchiveExportReminderCoordinator {
        ArchiveExportReminderCoordinator(defaults: defaults)
    }

    @Test func defaultsEnabledWithNoBaselineOrLastExport() {
        let c = coordinator()
        #expect(c.isEnabled)
        #expect(c.baseline == nil)
        #expect(c.lastExportDate == nil)
    }

    @Test func recordExportMovesBaselineAndLastExportDateAndHidesCard() {
        let records = (1...5).map { healthMatch(endOffset: TimeInterval($0 * 60)) }
        let c = coordinator()
        #expect(
            c.reminder(for: records, matchIDsWithNotes: [], archiveOpenedNormally: true, icloudStatus: .backedUp)
                == .due(count: 5, missing: [.health])
        )

        let exportedAt = now.addingTimeInterval(600)
        c.recordExport(now: exportedAt)
        #expect(c.baseline == exportedAt)
        #expect(c.lastExportDate == exportedAt)
        #expect(
            c.reminder(for: records, matchIDsWithNotes: [], archiveOpenedNormally: true, icloudStatus: .backedUp)
                == .hidden
        )

        // Persisted across coordinator instances sharing the same UserDefaults.
        let reloaded = coordinator()
        #expect(reloaded.baseline == exportedAt)
        #expect(reloaded.lastExportDate == exportedAt)

        // 5 more after the export brings the card back.
        let more = records + (1...5).map { healthMatch(endOffset: TimeInterval(600 + $0 * 60)) }
        #expect(
            reloaded.reminder(for: more, matchIDsWithNotes: [], archiveOpenedNormally: true, icloudStatus: .backedUp)
                == .due(count: 5, missing: [.health])
        )
    }

    @Test func snoozeAdvancesBaselineWithoutTouchingLastExportDate() {
        let records = (1...5).map { healthMatch(endOffset: TimeInterval($0 * 60)) }
        let c = coordinator()
        let snoozedAt = now.addingTimeInterval(600)
        c.snooze(now: snoozedAt)

        #expect(c.baseline == snoozedAt)
        #expect(c.lastExportDate == nil)
        #expect(
            c.reminder(for: records, matchIDsWithNotes: [], archiveOpenedNormally: true, icloudStatus: .backedUp)
                == .hidden
        )

        // Preserves an existing lastExportDate too.
        let firstExport = now.addingTimeInterval(700)
        c.recordExport(now: firstExport)
        let secondSnooze = now.addingTimeInterval(900)
        c.snooze(now: secondSnooze)
        #expect(c.baseline == secondSnooze)
        #expect(c.lastExportDate == firstExport)
    }

    @Test func disableHidesCardAndReenableShowsImmediatelyWithoutMovingBaseline() {
        let records = (1...8).map { healthMatch(endOffset: TimeInterval($0 * 60)) }
        let c = coordinator()
        c.disable()
        #expect(!c.isEnabled)
        #expect(
            c.reminder(for: records, matchIDsWithNotes: [], archiveOpenedNormally: true, icloudStatus: .backedUp)
                == .hidden
        )

        // Export while disabled still records lastExportDate.
        let exported = now.addingTimeInterval(200)
        c.recordExport(now: exported)
        #expect(c.lastExportDate == exported)

        // Re-enabling preserves baseline (5 matches after `exported` show straight away).
        let reloaded = coordinator()
        #expect(!reloaded.isEnabled)
        reloaded.setEnabled(true)
        #expect(reloaded.isEnabled)
        #expect(
            reloaded.reminder(for: records, matchIDsWithNotes: [], archiveOpenedNormally: true, icloudStatus: .backedUp)
                == .due(count: 5, missing: [.health])
        )
    }

    @Test func recordImportAdvancesBaselineWithoutMovingBackwardsOrTouchingLastExport() {
        let records = (1...5).map { healthMatch(endOffset: TimeInterval($0 * 60)) }
        let c = coordinator()

        let fileExportedAt = now.addingTimeInterval(500)
        c.recordImport(exportedAt: fileExportedAt)
        #expect(c.baseline == fileExportedAt)
        #expect(c.lastExportDate == nil)
        #expect(
            c.reminder(for: records, matchIDsWithNotes: [], archiveOpenedNormally: true, icloudStatus: .backedUp)
                == .hidden
        )

        // Importing an older file never moves the baseline backwards.
        c.recordImport(exportedAt: now.addingTimeInterval(100))
        #expect(c.baseline == fileExportedAt)
    }

    @Test func unreadableArchiveOrUnavailableICloudBehavesPerPolicy() {
        let plain = (1...5).map { plainMatch(endOffset: TimeInterval($0 * 60)) }
        let c = coordinator()

        #expect(
            c.reminder(for: plain, matchIDsWithNotes: [], archiveOpenedNormally: true, icloudStatus: .unavailable)
                == .due(count: 5, missing: [.everything])
        )
        #expect(
            c.reminder(for: plain, matchIDsWithNotes: [], archiveOpenedNormally: false, icloudStatus: .unavailable)
                == .hidden
        )
    }
}
