// MatchTypeConversionTests.swift — Unit tests for completed match type conversion (Doubles ↔ Singles).
import XCTest
@testable import DeuceMateCore

final class MatchTypeConversionTests: XCTestCase {

    // MARK: - Core conversion & preservation

    func test_convertingCompleted_doublesToSingles_and_singlesToDoubles_preservesAllData() {
        let matchID = UUID()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = Date(timeIntervalSince1970: 1_700_003_600)
        let setScores = [
            SetScore(gamesMe: 6, gamesOpponent: 4),
            SetScore(gamesMe: 7, gamesOpponent: 6, isTieBreak: true, tieBreakPointsMe: 7, tieBreakPointsOpponent: 5)
        ]
        let pointID = UUID()
        let stats = [
            PointStat(
                id: pointID,
                timestamp: start.addingTimeInterval(60),
                setIndex: 0,
                server: .me,
                winner: .me,
                outcome: .winner,
                isSecondServe: false,
                isBreakPoint: false,
                endingShot: .serve,
                heartRateBPM: 155,
                stepsCumulative: 35
            )
        ]
        let partner = TaggedPlayer(id: UUID(), name: "Sam")
        let opponent1 = TaggedPlayer(id: UUID(), name: "Alex")
        let opponent2 = TaggedPlayer(id: UUID(), name: "Jo")
        let tags = MatchTags(
            opponents: [opponent1, opponent2],
            partner: partner,
            competitionType: .league,
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        let doublesRecord = MatchRecord(
            id: matchID,
            startTime: start,
            endTime: end,
            setScores: setScores,
            stats: stats,
            iWon: true,
            currentPointsMe: 0,
            currentPointsOpponent: 0,
            matchType: .doubles,
            matchFormat: .standard,
            doublesServer: .partner,
            doublesServiceOrder: [.me, .opponentS1, .partner, .opponentS2],
            doublesServiceIndex: 2,
            tiebreakStartDoublesIndex: 1,
            matchElapsedSeconds: 3600,
            setElapsedSeconds: [0: 1800, 1: 1800],
            totalSteps: 4200,
            totalDistanceMeters: 2850.5,
            totalCaloriesKcal: 480.0,
            recentPoints: [.me, .opponent, .me],
            momentumEnabled: true,
            tags: tags
        )

        let convertTime = Date(timeIntervalSince1970: 1_700_005_000)
        let revID = UUID()
        let singlesRecord = doublesRecord.convertingMatchType(to: .singles, at: convertTime, revisionID: revID)

        // Conversion fields
        XCTAssertEqual(singlesRecord.matchType, .singles)
        XCTAssertEqual(singlesRecord.matchTypeRevision?.matchType, .singles)
        XCTAssertEqual(singlesRecord.matchTypeRevision?.updatedAt, convertTime)
        XCTAssertEqual(singlesRecord.matchTypeRevision?.revisionID, revID)

        // Preserved metadata & scoring
        XCTAssertEqual(singlesRecord.id, matchID)
        XCTAssertEqual(singlesRecord.startTime, start)
        XCTAssertEqual(singlesRecord.endTime, end)
        XCTAssertEqual(singlesRecord.iWon, true)
        XCTAssertEqual(singlesRecord.setScores, setScores)
        XCTAssertEqual(singlesRecord.stats, stats)
        XCTAssertEqual(singlesRecord.matchFormat, .standard)
        XCTAssertEqual(singlesRecord.matchElapsedSeconds, 3600)
        XCTAssertEqual(singlesRecord.setElapsedSeconds, [0: 1800, 1: 1800])
        XCTAssertEqual(singlesRecord.recentPoints, [.me, .opponent, .me])
        XCTAssertTrue(singlesRecord.momentumEnabled)

        // Preserved HealthKit fields
        XCTAssertEqual(singlesRecord.totalSteps, 4200)
        XCTAssertEqual(singlesRecord.totalDistanceMeters, 2850.5)
        XCTAssertEqual(singlesRecord.totalCaloriesKcal, 480.0)
        XCTAssertEqual(singlesRecord.stats[0].heartRateBPM, 155)
        XCTAssertEqual(singlesRecord.stats[0].stepsCumulative, 35)

        // Cleared doubles rotation fields
        XCTAssertNil(singlesRecord.doublesServer)
        XCTAssertEqual(singlesRecord.doublesServiceOrder, [])
        XCTAssertEqual(singlesRecord.doublesServiceIndex, 0)
        XCTAssertEqual(singlesRecord.tiebreakStartDoublesIndex, 0)

        // Convert back to doubles
        let convertBackTime = Date(timeIntervalSince1970: 1_700_006_000)
        let revID2 = UUID()
        let doublesAgain = singlesRecord.convertingMatchType(to: .doubles, at: convertBackTime, revisionID: revID2)
        XCTAssertEqual(doublesAgain.matchType, .doubles)
        XCTAssertEqual(doublesAgain.matchTypeRevision?.matchType, .doubles)
        XCTAssertEqual(doublesAgain.matchTypeRevision?.updatedAt, convertBackTime)
        XCTAssertEqual(doublesAgain.matchTypeRevision?.revisionID, revID2)
        XCTAssertEqual(doublesAgain.id, matchID)
        XCTAssertEqual(doublesAgain.totalSteps, 4200)
    }

    func test_convertingCompletedDraw_preservesDrawStatus() {
        let drawRecord = MatchRecord(
            startTime: Date(timeIntervalSince1970: 100),
            endTime: Date(timeIntervalSince1970: 200),
            setScores: [SetScore(gamesMe: 6, gamesOpponent: 6)],
            stats: [],
            iWon: nil,
            matchType: .doubles
        )
        XCTAssertFalse(drawRecord.isInProgress)
        XCTAssertNil(drawRecord.iWon)

        let converted = drawRecord.convertingMatchType(to: .singles)
        XCTAssertEqual(converted.matchType, .singles)
        XCTAssertNil(converted.iWon)
        XCTAssertEqual(converted.endTime, Date(timeIntervalSince1970: 200))
        XCTAssertFalse(converted.isInProgress)
    }

    // MARK: - In-progress and same-type guards

    func test_inProgressMatch_isNeverConvertedOrMerged() {
        let inProgress = MatchRecord(
            startTime: Date(timeIntervalSince1970: 100),
            endTime: nil,
            setScores: [],
            stats: [],
            iWon: nil,
            matchType: .doubles,
            doublesServer: .partner
        )
        XCTAssertTrue(inProgress.isInProgress)
        XCTAssertNil(inProgress.convertibleTargetMatchType)

        let converted = inProgress.convertingMatchType(to: .singles)
        XCTAssertEqual(converted, inProgress)
        XCTAssertNil(converted.matchTypeRevision)
        XCTAssertEqual(converted.matchType, .doubles)
        XCTAssertEqual(converted.doublesServer, .partner)

        let incomingRev = MatchTypeRevision(matchType: .singles, updatedAt: Date())
        let merged = inProgress.mergingMatchTypeRevision(incomingRev)
        XCTAssertEqual(merged, inProgress)
        XCTAssertNil(merged.matchTypeRevision)
    }

    func test_convertingToSameMatchType_isNoOp() {
        let completed = MatchRecord(
            startTime: Date(timeIntervalSince1970: 100),
            endTime: Date(timeIntervalSince1970: 200),
            setScores: [],
            stats: [],
            iWon: true,
            matchType: .doubles
        )
        let converted = completed.convertingMatchType(to: .doubles)
        XCTAssertEqual(converted, completed)
        XCTAssertNil(converted.matchTypeRevision)
    }

    // MARK: - Tag normalization on doubles → singles

    func test_tagNormalization_partnerAndTwoOpponents_dropsPartnerAndSecondOpponent() {
        let partner = TaggedPlayer(id: UUID(), name: "Sam")
        let op1 = TaggedPlayer(id: UUID(), name: "Alex")
        let op2 = TaggedPlayer(id: UUID(), name: "Jo")
        let tags = MatchTags(opponents: [op1, op2], partner: partner, competitionType: .league, updatedAt: Date(timeIntervalSince1970: 100))
        let record = MatchRecord(
            startTime: Date(timeIntervalSince1970: 100),
            endTime: Date(timeIntervalSince1970: 200),
            setScores: [],
            stats: [],
            iWon: true,
            matchType: .doubles,
            tags: tags
        )

        let revTime = Date(timeIntervalSince1970: 300)
        let revID = UUID()
        let converted = record.convertingMatchType(to: .singles, at: revTime, revisionID: revID)

        XCTAssertEqual(converted.matchType, .singles)
        XCTAssertNil(converted.tags?.partner)
        XCTAssertEqual(converted.tags?.opponents.map(\.name), ["Alex"])
        XCTAssertEqual(converted.tags?.competitionType, .league)
        XCTAssertEqual(converted.tags?.updatedAt, revTime)
        XCTAssertEqual(converted.tags?.revisionID, revID)
    }

    func test_tagNormalization_partnerOnly_becomesEmptyTagsWithNewerClock() {
        let partner = TaggedPlayer(id: UUID(), name: "Sam")
        let tags = MatchTags(opponents: [], partner: partner, competitionType: nil, updatedAt: Date(timeIntervalSince1970: 100))
        let record = MatchRecord(
            startTime: Date(timeIntervalSince1970: 100),
            endTime: Date(timeIntervalSince1970: 200),
            setScores: [],
            stats: [],
            iWon: true,
            matchType: .doubles,
            tags: tags
        )

        let revTime = Date(timeIntervalSince1970: 300)
        let revID = UUID()
        let converted = record.convertingMatchType(to: .singles, at: revTime, revisionID: revID)

        guard let convertedTags = converted.tags else {
            XCTFail("Converted tags must not be nil; must be empty newer revision")
            return
        }
        XCTAssertTrue(convertedTags.isEmpty)
        XCTAssertNil(convertedTags.partner)
        XCTAssertEqual(convertedTags.opponents, [])
        XCTAssertNil(convertedTags.competitionType)
        XCTAssertEqual(convertedTags.updatedAt, revTime)
        XCTAssertEqual(convertedTags.revisionID, revID)

        // Verify that this empty newer tag revision beats an older tag with a partner on merge
        let mergedTags = MatchTags.merged(tags, convertedTags)
        XCTAssertEqual(mergedTags, convertedTags)
    }

    func test_tagNormalization_singleOpponentAndNilPartner_leavesTagsUntouched() {
        let op = TaggedPlayer(id: UUID(), name: "Alex")
        let originalTagRevID = UUID()
        let tags = MatchTags(opponents: [op], partner: nil, competitionType: .tournament, updatedAt: Date(timeIntervalSince1970: 100), revisionID: originalTagRevID)
        let record = MatchRecord(
            startTime: Date(timeIntervalSince1970: 100),
            endTime: Date(timeIntervalSince1970: 200),
            setScores: [],
            stats: [],
            iWon: true,
            matchType: .doubles,
            tags: tags
        )

        let converted = record.convertingMatchType(to: .singles, at: Date(timeIntervalSince1970: 300))
        XCTAssertEqual(converted.tags, tags, "Single opponent with nil partner must not advance tag clock")
    }

    func test_singlesToDoubles_keepsExistingTagsUntouched() {
        let op = TaggedPlayer(id: UUID(), name: "Alex")
        let tags = MatchTags(opponents: [op], partner: nil, competitionType: .friendly, updatedAt: Date(timeIntervalSince1970: 100))
        let record = MatchRecord(
            startTime: Date(timeIntervalSince1970: 100),
            endTime: Date(timeIntervalSince1970: 200),
            setScores: [],
            stats: [],
            iWon: true,
            matchType: .singles,
            tags: tags
        )

        let converted = record.convertingMatchType(to: .doubles, at: Date(timeIntervalSince1970: 300))
        XCTAssertEqual(converted.tags, tags)
    }

    // MARK: - UI helper properties

    func test_convertibleTargetMatchType_and_playersDroppedConvertingToSingles() {
        let partner = TaggedPlayer(id: UUID(), name: "Sam")
        let op1 = TaggedPlayer(id: UUID(), name: "Alex")
        let op2 = TaggedPlayer(id: UUID(), name: "Jo")
        let tags = MatchTags(opponents: [op1, op2], partner: partner, updatedAt: Date())

        let doublesRecord = MatchRecord(
            startTime: Date(timeIntervalSince1970: 100),
            endTime: Date(timeIntervalSince1970: 200),
            setScores: [],
            stats: [],
            iWon: true,
            matchType: .doubles,
            tags: tags
        )
        XCTAssertEqual(doublesRecord.convertibleTargetMatchType, .singles)
        let dropped = doublesRecord.playersDroppedConvertingToSingles
        XCTAssertEqual(dropped.map(\.name), ["Sam", "Jo"])

        let singlesRecord = MatchRecord(
            startTime: Date(timeIntervalSince1970: 100),
            endTime: Date(timeIntervalSince1970: 200),
            setScores: [],
            stats: [],
            iWon: true,
            matchType: .singles,
            tags: MatchTags(opponents: [op1], partner: nil, updatedAt: Date())
        )
        XCTAssertEqual(singlesRecord.convertibleTargetMatchType, .doubles)
        XCTAssertTrue(singlesRecord.playersDroppedConvertingToSingles.isEmpty)

        let untaggedDoubles = MatchRecord(
            startTime: Date(timeIntervalSince1970: 100),
            endTime: Date(timeIntervalSince1970: 200),
            setScores: [],
            stats: [],
            iWon: true,
            matchType: .doubles,
            tags: nil
        )
        XCTAssertTrue(untaggedDoubles.playersDroppedConvertingToSingles.isEmpty)
    }

    // MARK: - Monotonic clock advancement

    func test_monotonicClockAdvancement_evenWhenClockMovesBackwards() {
        let baseDate = Date(timeIntervalSince1970: 1_000)
        var record = MatchRecord(
            startTime: Date(timeIntervalSince1970: 100),
            endTime: Date(timeIntervalSince1970: 200),
            setScores: [],
            stats: [],
            iWon: true,
            matchType: .doubles
        )

        record = record.convertingMatchType(to: .singles, at: baseDate)
        XCTAssertEqual(record.matchTypeRevision?.updatedAt, baseDate)

        // Clock moves backwards:
        let earlierDate = Date(timeIntervalSince1970: 500)
        record = record.convertingMatchType(to: .doubles, at: earlierDate)
        let expectedStep1 = baseDate.addingTimeInterval(MatchTypeRevision.minimumClockStep)
        XCTAssertEqual(record.matchTypeRevision?.updatedAt, expectedStep1)

        // Clock moves backwards again:
        let evenEarlierDate = Date(timeIntervalSince1970: 100)
        record = record.convertingMatchType(to: .singles, at: evenEarlierDate)
        let expectedStep2 = expectedStep1.addingTimeInterval(MatchTypeRevision.minimumClockStep)
        XCTAssertEqual(record.matchTypeRevision?.updatedAt, expectedStep2)
    }

    // MARK: - Critical Equal-endTime Regression

    func test_criticalEqualEndTimeRegression_phoneConvertsToSingles_watchPushesDoubles() {
        let id = UUID()
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 2_000)
        let partner = TaggedPlayer(id: UUID(), name: "Sam")
        let op1 = TaggedPlayer(id: UUID(), name: "Alex")
        let op2 = TaggedPlayer(id: UUID(), name: "Jo")
        let tags = MatchTags(opponents: [op1, op2], partner: partner, updatedAt: Date(timeIntervalSince1970: 100))

        let originalRecord = MatchRecord(
            id: id,
            startTime: start,
            endTime: end,
            setScores: [SetScore(gamesMe: 6, gamesOpponent: 3)],
            stats: [],
            iWon: true,
            matchType: .doubles,
            doublesServer: .partner,
            doublesServiceOrder: [.me, .opponentS1, .partner, .opponentS2],
            doublesServiceIndex: 2,
            tiebreakStartDoublesIndex: 1,
            tags: tags
        )

        // Phone converts match to .singles
        let conversionTime = Date(timeIntervalSince1970: 3_000)
        let revID = UUID()
        let phoneCopy = originalRecord.convertingMatchType(to: .singles, at: conversionTime, revisionID: revID)

        // Watch pushes original .doubles copy with identical endTime and matchTypeRevision == nil
        let watchCopy = originalRecord

        // Test commutativity in both argument orders
        let resolvedWatchPhone = MatchMergePolicy.resolve(incoming: watchCopy, existing: phoneCopy)
        let resolvedPhoneWatch = MatchMergePolicy.resolve(incoming: phoneCopy, existing: watchCopy)

        for resolved in [resolvedWatchPhone, resolvedPhoneWatch] {
            XCTAssertEqual(resolved.id, id)
            XCTAssertEqual(resolved.matchType, .singles)
            XCTAssertEqual(resolved.matchTypeRevision?.matchType, .singles)
            XCTAssertEqual(resolved.matchTypeRevision?.updatedAt, conversionTime)
            XCTAssertNil(resolved.doublesServer)
            XCTAssertEqual(resolved.doublesServiceOrder, [])
            XCTAssertEqual(resolved.doublesServiceIndex, 0)
            XCTAssertEqual(resolved.tiebreakStartDoublesIndex, 0)
            XCTAssertNil(resolved.tags?.partner)
            XCTAssertEqual(resolved.tags?.opponents.map(\.name), ["Alex"])
        }

        XCTAssertEqual(resolvedWatchPhone, resolvedPhoneWatch, "MatchMergePolicy.resolve must be strictly commutative")
    }

    // MARK: - Offline Cross-Peer Tag + Conversion Merge

    func test_offlineCrossPeerTagAndConversionMerge_inBothOrders_andIdempotent() {
        let id = UUID()
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 2_000)
        let baseRecord = MatchRecord(
            id: id,
            startTime: start,
            endTime: end,
            setScores: [SetScore(gamesMe: 6, gamesOpponent: 4)],
            stats: [],
            iWon: true,
            matchType: .doubles,
            doublesServer: .partner,
            doublesServiceOrder: [.me, .opponentS1, .partner, .opponentS2]
        )

        // Watch converts .doubles → .singles at t=200 with tags == nil
        let watchCopy = baseRecord.convertingMatchType(to: .singles, at: Date(timeIntervalSince1970: 200))

        for tTag in [100.0, 300.0] {
            // Phone tagged partner: Sam, opponents: [Alex, Jo] at tTag with matchTypeRevision == nil
            let phoneTags = MatchTags(
                opponents: [TaggedPlayer(name: "Alex"), TaggedPlayer(name: "Jo")],
                partner: TaggedPlayer(name: "Sam"),
                competitionType: .league,
                updatedAt: Date(timeIntervalSince1970: tTag)
            )
            var phoneCopy = baseRecord
            phoneCopy.tags = phoneTags

            let r1 = MatchMergePolicy.resolve(incoming: watchCopy, existing: phoneCopy)
            let r2 = MatchMergePolicy.resolve(incoming: phoneCopy, existing: watchCopy)

            XCTAssertEqual(r1, r2, "Commutative resolve for tTag=\(tTag)")
            XCTAssertEqual(r1.matchType, .singles)
            XCTAssertEqual(r1.matchTypeRevision?.matchType, .singles)
            XCTAssertNil(r1.tags?.partner, "Partner must be normalized away in singles")
            XCTAssertEqual(r1.tags?.opponents.map(\.name), ["Alex"], "Only first opponent preserved")
            XCTAssertEqual(r1.tags?.competitionType, .league)
            XCTAssertNil(r1.doublesServer)
            XCTAssertEqual(r1.doublesServiceOrder, [])

            // Idempotent re-merge
            let remerged = MatchMergePolicy.resolve(incoming: r1, existing: r1)
            XCTAssertEqual(remerged, r1, "Merge must be idempotent")
        }
    }

    // MARK: - Guard test for legacy singles records

    func test_guard_legacySinglesWithPartnerAndNilRevision_isNotStripped() {
        let partner = TaggedPlayer(id: UUID(), name: "Sam")
        let tags = MatchTags(opponents: [TaggedPlayer(name: "Alex")], partner: partner, updatedAt: Date(timeIntervalSince1970: 100))
        let legacyRecord = MatchRecord(
            startTime: Date(timeIntervalSince1970: 100),
            endTime: Date(timeIntervalSince1970: 200),
            setScores: [],
            stats: [],
            iWon: true,
            matchType: .singles,
            tags: tags,
            matchTypeRevision: nil
        )

        // MatchMergePolicy.resolve with nil existing
        let resolvedMergeNil = MatchMergePolicy.resolve(incoming: legacyRecord, existing: nil)
        XCTAssertEqual(resolvedMergeNil.tags?.partner?.name, "Sam")

        // MatchMergePolicy.resolve with existing having same
        let resolvedMergeExisting = MatchMergePolicy.resolve(incoming: legacyRecord, existing: legacyRecord)
        XCTAssertEqual(resolvedMergeExisting.tags?.partner?.name, "Sam")

        // ArchiveBackupPolicy.resolveBackup with nil local
        let resolvedBackupNil = ArchiveBackupPolicy.resolveBackup(backup: legacyRecord, local: nil)
        XCTAssertEqual(resolvedBackupNil.tags?.partner?.name, "Sam")

        // ArchiveBackupPolicy.resolveBackup with local having same
        let resolvedBackupLocal = ArchiveBackupPolicy.resolveBackup(backup: legacyRecord, local: legacyRecord)
        XCTAssertEqual(resolvedBackupLocal.tags?.partner?.name, "Sam")
    }

    // MARK: - Backup and import policies

    func test_archiveBackupPolicy_and_manualArchiveBackup_preserveRevisionAcrossEqualEndTime() {
        let base = MatchRecord(
            id: UUID(),
            startTime: Date(timeIntervalSince1970: 1_000),
            endTime: Date(timeIntervalSince1970: 2_000),
            setScores: [SetScore(gamesMe: 6, gamesOpponent: 2)],
            stats: [],
            iWon: true,
            matchType: .doubles,
            doublesServer: .partner
        )

        let converted = base.convertingMatchType(to: .singles, at: Date(timeIntervalSince1970: 2_500))

        // Backup has converted revision, local has base (equal endTime)
        let resolvedBackup1 = ArchiveBackupPolicy.resolveBackup(backup: converted, local: base)
        XCTAssertEqual(resolvedBackup1.matchType, .singles)
        XCTAssertEqual(resolvedBackup1.matchTypeRevision, converted.matchTypeRevision)
        XCTAssertNil(resolvedBackup1.doublesServer)

        // Local has converted revision, backup has base (equal endTime)
        let resolvedBackup2 = ArchiveBackupPolicy.resolveBackup(backup: base, local: converted)
        XCTAssertEqual(resolvedBackup2.matchType, .singles)
        XCTAssertEqual(resolvedBackup2.matchTypeRevision, converted.matchTypeRevision)
        XCTAssertNil(resolvedBackup2.doublesServer)

        // ManualMatchArchiveBackup .merge import
        let snapshot = ManualMatchArchiveBackup.importSnapshot(
            importing: [converted],
            into: [base],
            tombstones: [],
            mode: .merge
        )
        XCTAssertEqual(snapshot.records.count, 1)
        XCTAssertEqual(snapshot.records[0].matchType, .singles)
        XCTAssertEqual(snapshot.records[0].matchTypeRevision, converted.matchTypeRevision)
        XCTAssertNil(snapshot.records[0].doublesServer)
    }

    // MARK: - Derived stats reflect converted matchType

    func test_derivedStats_matchStatsSummary_matchTrendSample_headToHead_reflectConversion() {
        let alexID = UUID()
        let alex = TaggedPlayer(id: alexID, name: "Alex")
        let jo = TaggedPlayer(id: UUID(), name: "Jo")
        let sam = TaggedPlayer(id: UUID(), name: "Sam")

        let stats = (0..<20).map { i in
            PointStat(setIndex: 0, server: .me, winner: i % 2 == 0 ? .me : .opponent, outcome: .winner, isSecondServe: false)
        }
        let doublesRecord = MatchRecord(
            startTime: Date(timeIntervalSince1970: 1_000),
            endTime: Date(timeIntervalSince1970: 2_000),
            setScores: [SetScore(gamesMe: 6, gamesOpponent: 3)],
            stats: stats,
            iWon: true,
            matchType: .doubles,
            tags: MatchTags(opponents: [alex, jo], partner: sam, updatedAt: Date(timeIntervalSince1970: 100))
        )

        let singlesRecord = doublesRecord.convertingMatchType(to: .singles, at: Date(timeIntervalSince1970: 3_000))

        // MatchStatsSummary preserves points won
        let doublesSummary = MatchStatsSummary(stats: doublesRecord.stats, focal: .me)
        let singlesSummary = MatchStatsSummary(stats: singlesRecord.stats, focal: .me)
        XCTAssertEqual(doublesSummary.pointsWon, singlesSummary.pointsWon)

        // MatchTrendSample reflects matchType
        let sampleDoubles = MatchTrendSample(record: doublesRecord)
        let sampleSingles = MatchTrendSample(record: singlesRecord)
        XCTAssertEqual(sampleDoubles?.matchType, .doubles)
        XCTAssertEqual(sampleSingles?.matchType, .singles)

        // HeadToHead tally moves from doubles to singles
        let h2hSinglesBefore = HeadToHead.record(vs: alexID, in: [doublesRecord], excluding: nil, matchType: .singles)
        let h2hDoublesBefore = HeadToHead.record(vs: alexID, in: [doublesRecord], excluding: nil, matchType: .doubles)
        XCTAssertEqual(h2hSinglesBefore.wins, 0)
        XCTAssertEqual(h2hDoublesBefore.wins, 1)

        let h2hSinglesAfter = HeadToHead.record(vs: alexID, in: [singlesRecord], excluding: nil, matchType: .singles)
        let h2hDoublesAfter = HeadToHead.record(vs: alexID, in: [singlesRecord], excluding: nil, matchType: .doubles)
        XCTAssertEqual(h2hSinglesAfter.wins, 1)
        XCTAssertEqual(h2hDoublesAfter.wins, 0)
    }

    // MARK: - Wire round-trip & reconciliation

    func test_wireRoundTrip_and_payloadBuilder() throws {
        XCTAssertEqual(MatchSyncKey.matchTypeUpdate, "matchTypeUpdate", "Wire key pinned")

        let matchID = UUID()
        let rev = MatchTypeRevision(
            matchType: .singles,
            updatedAt: Date(timeIntervalSince1970: 1_234),
            revisionID: UUID()
        )
        let update = MatchTypeUpdate(matchID: matchID, revision: rev)

        let payload = try MatchSyncPayloadBuilder.matchTypeUpdate(update)
        XCTAssertNotNil(payload[MatchSyncKey.matchTypeUpdate] as? Data)

        let events = SyncIncomingPayload.decode(payload)
        XCTAssertEqual(events, [.matchTypeUpdate(matchID: matchID, revision: rev)])

        // Convenience overload
        let payload2 = try MatchSyncPayloadBuilder.matchTypeUpdate(matchID: matchID, revision: rev)
        let events2 = SyncIncomingPayload.decode(payload2)
        XCTAssertEqual(events2, [.matchTypeUpdate(matchID: matchID, revision: rev)])

        // Malformed data degrades to decodeError
        let malformedPayload: [String: Any] = [MatchSyncKey.matchTypeUpdate: Data("not valid json".utf8)]
        let malformedEvents = SyncIncomingPayload.decode(malformedPayload)
        XCTAssertEqual(malformedEvents.count, 1)
        if case .decodeError(let key, _) = malformedEvents[0] {
            XCTAssertEqual(key, MatchSyncKey.matchTypeUpdate)
        } else {
            XCTFail("Expected decodeError for malformed matchTypeUpdate payload")
        }
    }

    func test_pendingWatchUpdates_filtersAndReconciles() {
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()
        let id4 = UUID()
        let id5 = UUID()

        let rev1 = MatchTypeRevision(matchType: .singles, updatedAt: Date(timeIntervalSince1970: 200))
        let rev2 = MatchTypeRevision(matchType: .doubles, updatedAt: Date(timeIntervalSince1970: 300))
        let rev3 = MatchTypeRevision(matchType: .singles, updatedAt: Date(timeIntervalSince1970: 400))
        let rev4 = MatchTypeRevision(matchType: .doubles, updatedAt: Date(timeIntervalSince1970: 500))

        let record1 = MatchRecord(id: id1, startTime: Date(), endTime: Date(), setScores: [], stats: [], iWon: true, matchType: .singles, matchTypeRevision: rev1)
        let record2 = MatchRecord(id: id2, startTime: Date(), endTime: Date(), setScores: [], stats: [], iWon: true, matchType: .doubles, matchTypeRevision: rev2)
        // In-progress record: must be excluded from pending updates
        let record3 = MatchRecord(id: id3, startTime: Date(), endTime: nil, setScores: [], stats: [], iWon: nil, matchType: .singles, matchTypeRevision: rev3)
        let record4 = MatchRecord(id: id4, startTime: Date(), endTime: Date(), setScores: [], stats: [], iWon: true, matchType: .doubles, matchTypeRevision: rev4)
        // Record without revision: must not produce an update
        let record5 = MatchRecord(id: id5, startTime: Date(), endTime: Date(), setScores: [], stats: [], iWon: true, matchType: .doubles, matchTypeRevision: nil)

        let archive = [record1, record2, record3, record4, record5]

        // Watch copies:
        // - copy1: has nil revision -> needs update (phone rev1)
        let watchCopy1 = MatchRecord(id: id1, startTime: Date(), endTime: Date(), setScores: [], stats: [], iWon: true, matchType: .doubles, matchTypeRevision: nil)
        // - copy2: has older revision (t=100 < 300) -> needs update (phone rev2)
        let olderRev2 = MatchTypeRevision(matchType: .singles, updatedAt: Date(timeIntervalSince1970: 100))
        let watchCopy2 = MatchRecord(id: id2, startTime: Date(), endTime: Date(), setScores: [], stats: [], iWon: true, matchType: .singles, matchTypeRevision: olderRev2)
        // - copy4: has newer revision (t=600 > 500) -> does not need update
        let newerRev4 = MatchTypeRevision(matchType: .singles, updatedAt: Date(timeIntervalSince1970: 600))
        let watchCopy4 = MatchRecord(id: id4, startTime: Date(), endTime: Date(), setScores: [], stats: [], iWon: true, matchType: .singles, matchTypeRevision: newerRev4)
        // - copy3: in-progress on watch -> ignored
        let watchCopy3 = MatchRecord(id: id3, startTime: Date(), endTime: nil, setScores: [], stats: [], iWon: nil, matchType: .singles, matchTypeRevision: nil)

        // Newly held: id4 newly reported (e.g. fresh manifest arrival) -> should queue rev4
        let newlyHeld: Set<UUID> = [id4]

        let updates = MatchTypeRevision.pendingWatchUpdates(
            archive: archive,
            watchCopies: [watchCopy1, watchCopy2, watchCopy3, watchCopy4],
            newlyHeld: newlyHeld
        )

        let updatedIDs = updates.map(\.matchID)
        XCTAssertTrue(updatedIDs.contains(id1), "copy with nil revision should be updated")
        XCTAssertTrue(updatedIDs.contains(id2), "copy with older revision should be updated")
        XCTAssertTrue(updatedIDs.contains(id4), "newly held match should be updated with phone revision")
        XCTAssertFalse(updatedIDs.contains(id3), "in-progress match should never be queued")
        XCTAssertFalse(updatedIDs.contains(id5), "match without revision should not be queued")

        // Verify deterministic sorting by UUID string
        let sortedIDs = updates.map(\.matchID.uuidString)
        XCTAssertEqual(sortedIDs, sortedIDs.sorted())
    }
}
