// ManualMatchArchiveBackupTests.swift — full-fidelity manual archive export/import.
import XCTest
@testable import DeuceMateCore

final class ManualMatchArchiveBackupTests: XCTestCase {

    private let exportedAt = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeRecord(
        id: UUID = UUID(),
        startTime: Date = Date(timeIntervalSince1970: 1_700_000_000),
        endTime: Date? = Date(timeIntervalSince1970: 1_700_003_600),
        iWon: Bool? = true,
        pointID: UUID = UUID(),
        heartRateBPM: Int? = 156,
        stepsCumulative: Int? = 42,
        totalSteps: Int? = 1_234,
        totalDistanceMeters: Double? = 3_210,
        totalCaloriesKcal: Double? = 456
    ) -> MatchRecord {
        MatchRecord(
            id: id,
            startTime: startTime,
            endTime: endTime,
            setScores: [
                SetScore(gamesMe: 7, gamesOpponent: 6, isTieBreak: true, tieBreakPointsMe: 7, tieBreakPointsOpponent: 4),
                SetScore(gamesMe: 6, gamesOpponent: 4)
            ],
            stats: [
                PointStat(
                    id: pointID,
                    timestamp: startTime.addingTimeInterval(90),
                    setIndex: 0,
                    server: .me,
                    winner: .me,
                    outcome: .winner,
                    isSecondServe: true,
                    isBreakPoint: true,
                    endingShot: .servePlusOne,
                    gameScoreAtStart: GameScoreSnapshot(server: 3, returner: 2, isTiebreak: false),
                    heartRateBPM: heartRateBPM,
                    stepsCumulative: stepsCumulative
                )
            ],
            iWon: iWon,
            currentPointsMe: 4,
            currentPointsOpponent: 2,
            currentServer: .me,
            gameCount: 19,
            pointCountInTiebreak: 11,
            tiebreakStartServer: .opponent,
            tiebreakFirstPointReceiver: .me,
            lastTiebreakPointServer: .me,
            isOnSecondServe: true,
            matchType: .doubles,
            matchFormat: .bestOf3FullFinalSet,
            doublesServer: .partner,
            doublesServiceOrder: [.me, .opponentS1, .partner, .opponentS2],
            doublesServiceIndex: 2,
            tiebreakStartDoublesIndex: 1,
            matchElapsedSeconds: 4_200,
            setElapsedSeconds: [0: 2_200, 1: 2_000],
            totalSteps: totalSteps,
            totalDistanceMeters: totalDistanceMeters,
            totalCaloriesKcal: totalCaloriesKcal,
            recentPoints: [.me, .opponent, .me],
            momentumEnabled: true
        )
    }

    func test_encodeDecode_roundTripsFullArchiveIncludingHealthData() throws {
        let record = makeRecord()

        let data = try ManualMatchArchiveBackup.encode(records: [record], exportedAt: exportedAt)
        let decoded = try ManualMatchArchiveBackup.decode(data)

        XCTAssertEqual(decoded.format, ManualMatchArchiveBackup.format)
        XCTAssertEqual(decoded.schemaVersion, ManualMatchArchiveBackup.supportedSchemaVersion)
        XCTAssertEqual(decoded.exportedAt, exportedAt)
        XCTAssertTrue(decoded.includesHealthData)
        XCTAssertEqual(decoded.records, [record])
        XCTAssertEqual(decoded.records.first?.stats.first?.heartRateBPM, 156)
        XCTAssertEqual(decoded.records.first?.stats.first?.stepsCumulative, 42)
        XCTAssertEqual(decoded.records.first?.totalSteps, 1_234)
        XCTAssertEqual(decoded.records.first?.totalDistanceMeters, 3_210)
        XCTAssertEqual(decoded.records.first?.totalCaloriesKcal, 456)
    }

    func test_encodeDecode_preservesFractionalTimestamps() throws {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000.123456)
        let end = Date(timeIntervalSinceReferenceDate: 800_004_200.654321)
        let pointID = UUID()
        var record = makeRecord(
            startTime: start,
            endTime: end,
            pointID: pointID
        )
        record.stats = [
            PointStat(
                id: pointID,
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_090.987654),
                setIndex: 0,
                server: .me,
                winner: .me,
                outcome: .winner,
                heartRateBPM: 156
            )
        ]
        let exportedAt = Date(timeIntervalSinceReferenceDate: 800_010_000.456789)

        let data = try ManualMatchArchiveBackup.encode(records: [record], exportedAt: exportedAt)
        let decoded = try ManualMatchArchiveBackup.decode(data)

        XCTAssertEqual(
            decoded.exportedAt.timeIntervalSinceReferenceDate,
            exportedAt.timeIntervalSinceReferenceDate,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            decoded.records[0].startTime.timeIntervalSinceReferenceDate,
            start.timeIntervalSinceReferenceDate,
            accuracy: 0.000_001
        )
        let decodedEnd = try XCTUnwrap(decoded.records[0].endTime)
        XCTAssertEqual(
            decodedEnd.timeIntervalSinceReferenceDate,
            end.timeIntervalSinceReferenceDate,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            decoded.records[0].stats[0].timestamp.timeIntervalSinceReferenceDate,
            record.stats[0].timestamp.timeIntervalSinceReferenceDate,
            accuracy: 0.000_001
        )
    }

    func test_encode_usesReadableVersionedJSON() throws {
        let record = makeRecord()

        let data = try ManualMatchArchiveBackup.encode(records: [record], exportedAt: exportedAt)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(json.contains("\"format\" : \"deucemate.matchArchive\""))
        XCTAssertTrue(json.contains("\"schemaVersion\" : 1"))
        XCTAssertTrue(json.contains("\"includesHealthData\" : true"))
        XCTAssertTrue(json.contains("\"heartRateBPM\" : 156"))
    }

    func test_preview_reportsCountAndHealthDisclosureFlag() throws {
        let data = try ManualMatchArchiveBackup.encode(records: [makeRecord()], exportedAt: exportedAt)

        let preview = try ManualMatchArchiveBackup.preview(data)

        XCTAssertEqual(preview.recordCount, 1)
        XCTAssertTrue(preview.includesHealthData)
        XCTAssertEqual(preview.exportedAt, exportedAt)
    }

    func test_decode_rejectsWrongFormat() throws {
        let archive = ManualMatchArchiveBackup.Archive(format: "other", exportedAt: exportedAt, records: [])
        let data = try JSONEncoder.iso8601ManualArchiveTestEncoder.encode(archive)

        XCTAssertThrowsError(try ManualMatchArchiveBackup.decode(data)) { error in
            XCTAssertEqual(error as? ManualMatchArchiveBackup.ArchiveError, .wrongFormat("other"))
        }
    }

    func test_decode_rejectsUnsupportedSchemaVersion() throws {
        let archive = ManualMatchArchiveBackup.Archive(
            schemaVersion: 99,
            exportedAt: exportedAt,
            records: []
        )
        let data = try JSONEncoder.iso8601ManualArchiveTestEncoder.encode(archive)

        XCTAssertThrowsError(try ManualMatchArchiveBackup.decode(data)) { error in
            XCTAssertEqual(error as? ManualMatchArchiveBackup.ArchiveError, .unsupportedSchemaVersion(99))
        }
    }

    func test_decode_rejectsEmptyFile() {
        XCTAssertThrowsError(try ManualMatchArchiveBackup.decode(Data())) { error in
            XCTAssertEqual(error as? ManualMatchArchiveBackup.ArchiveError, .emptyFile)
        }
    }

    func test_decode_rejectsCorruptJSON() {
        XCTAssertThrowsError(try ManualMatchArchiveBackup.decode(Data("{".utf8)))
    }

    func test_decode_rejectsOversizedFileBeforeParsing() {
        // One byte over the ceiling, non-empty and not valid JSON — the size guard
        // must fire before the decoder is ever handed the blob.
        let data = Data(count: ManualMatchArchiveBackup.maxArchiveBytes + 1)

        XCTAssertThrowsError(try ManualMatchArchiveBackup.decode(data)) { error in
            XCTAssertEqual(error as? ManualMatchArchiveBackup.ArchiveError, .fileTooLarge)
        }
    }

    func test_decode_rejectsTooManyRecords() throws {
        let count = ManualMatchArchiveBackup.maxArchiveRecords + 1
        let records = (0..<count).map { _ in
            MatchRecord(startTime: Date(timeIntervalSince1970: 1_700_000_000), setScores: [], stats: [])
        }
        let archive = ManualMatchArchiveBackup.Archive(exportedAt: exportedAt, records: records)
        let data = try JSONEncoder.iso8601ManualArchiveTestEncoder.encode(archive)

        XCTAssertThrowsError(try ManualMatchArchiveBackup.decode(data)) { error in
            XCTAssertEqual(error as? ManualMatchArchiveBackup.ArchiveError, .tooManyRecords(count))
        }
    }

    func test_decode_acceptsArchiveAtRecordLimit() throws {
        // A full archive at the record ceiling still imports — the cap is defensive
        // headroom, not a product limit a real user would hit.
        let records = (0..<ManualMatchArchiveBackup.maxArchiveRecords).map { _ in
            MatchRecord(startTime: Date(timeIntervalSince1970: 1_700_000_000), setScores: [], stats: [])
        }
        let archive = ManualMatchArchiveBackup.Archive(exportedAt: exportedAt, records: records)
        let data = try JSONEncoder.iso8601ManualArchiveTestEncoder.encode(archive)

        let decoded = try ManualMatchArchiveBackup.decode(data)

        XCTAssertEqual(decoded.records.count, ManualMatchArchiveBackup.maxArchiveRecords)
    }

    func test_importSnapshot_mergeAddsMissingRecordsAndClearsImportedTombstones() {
        let existing = makeRecord(startTime: Date(timeIntervalSince1970: 1_000))
        let imported = makeRecord(startTime: Date(timeIntervalSince1970: 2_000))

        let snapshot = ManualMatchArchiveBackup.importSnapshot(
            importing: [imported],
            into: [existing],
            tombstones: [imported.id],
            mode: .merge
        )

        XCTAssertEqual(Set(snapshot.records.map(\.id)), Set([existing.id, imported.id]))
        XCTAssertFalse(snapshot.tombstones.contains(imported.id))
        XCTAssertEqual(snapshot.records.first?.id, imported.id)
    }

    func test_importSnapshot_mergeResolvesDuplicateIDsDeterministically() {
        let id = UUID()
        let older = makeRecord(
            id: id,
            startTime: Date(timeIntervalSince1970: 1_000),
            endTime: Date(timeIntervalSince1970: 1_100),
            iWon: false
        )
        let newer = makeRecord(
            id: id,
            startTime: Date(timeIntervalSince1970: 1_000),
            endTime: Date(timeIntervalSince1970: 1_200),
            iWon: true
        )

        let snapshot = ManualMatchArchiveBackup.importSnapshot(
            importing: [newer],
            into: [older],
            tombstones: [],
            mode: .merge
        )

        XCTAssertEqual(snapshot.records.count, 1)
        XCTAssertEqual(snapshot.records.first?.iWon, true)
    }

    func test_importSnapshot_mergeRestoresMissingHealthFieldsForSameMatch() {
        let id = UUID()
        let pointID = UUID()
        let local = makeRecord(
            id: id,
            pointID: pointID,
            heartRateBPM: nil,
            stepsCumulative: nil,
            totalSteps: nil,
            totalDistanceMeters: nil,
            totalCaloriesKcal: nil
        )
        let imported = makeRecord(
            id: id,
            pointID: pointID,
            heartRateBPM: 161,
            stepsCumulative: 88,
            totalSteps: 1_111,
            totalDistanceMeters: 2_222,
            totalCaloriesKcal: 333
        )

        let snapshot = ManualMatchArchiveBackup.importSnapshot(
            importing: [imported],
            into: [local],
            tombstones: [],
            mode: .merge
        )

        let merged = snapshot.records.first
        XCTAssertEqual(merged?.stats.first?.heartRateBPM, 161)
        XCTAssertEqual(merged?.stats.first?.stepsCumulative, 88)
        XCTAssertEqual(merged?.totalSteps, 1_111)
        XCTAssertEqual(merged?.totalDistanceMeters, 2_222)
        XCTAssertEqual(merged?.totalCaloriesKcal, 333)
    }

    func test_importSnapshot_replaceAdoptsImportedRecordsAndHealthData() {
        let local = makeRecord(startTime: Date(timeIntervalSince1970: 1_000))
        let imported = makeRecord(startTime: Date(timeIntervalSince1970: 2_000), heartRateBPM: 170)

        let snapshot = ManualMatchArchiveBackup.importSnapshot(
            importing: [imported],
            into: [local],
            tombstones: [imported.id, local.id],
            mode: .replace
        )

        XCTAssertEqual(snapshot.records.map(\.id), [imported.id])
        XCTAssertEqual(snapshot.records.first?.stats.first?.heartRateBPM, 170)
        XCTAssertFalse(snapshot.tombstones.contains(imported.id))
        XCTAssertTrue(snapshot.tombstones.contains(local.id))
    }
}

private extension JSONEncoder {
    static var iso8601ManualArchiveTestEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
