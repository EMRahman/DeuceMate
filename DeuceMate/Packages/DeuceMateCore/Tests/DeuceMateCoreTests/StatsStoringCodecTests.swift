// StatsStoringCodecTests.swift — the shared JSON codec both stores persist through.
import XCTest
@testable import DeuceMateCore

final class StatsStoringCodecTests: XCTestCase {

    /// Minimal in-memory conformer: the codec helpers are static extension
    /// members, so a conforming type is needed to reach them.
    private final class MemoryStore: StatsStoring {
        var records: [MatchRecord] = []
        func loadHistory() -> [MatchRecord] { records }
        func saveHistory(_ records: [MatchRecord]) { self.records = records }
        func appendMatch(_ record: MatchRecord) { records.append(record) }
        func removeMatch(id: UUID) { records.removeAll { $0.id == id } }
    }

    private func makeRecord(
        id: UUID = UUID(),
        startTime: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> MatchRecord {
        MatchRecord(
            id: id,
            startTime: startTime,
            endTime: startTime.addingTimeInterval(3_600),
            setScores: [SetScore(gamesMe: 6, gamesOpponent: 4)],
            stats: [
                PointStat(
                    setIndex: 0,
                    server: .me,
                    winner: .me,
                    outcome: .winner,
                    isSecondServe: false,
                    isBreakPoint: true,
                    endingShot: .rally,
                    heartRateBPM: 152,
                    stepsCumulative: 480
                )
            ],
            iWon: true,
            matchType: .doubles,
            matchFormat: .bestOf3FullFinalSet,
            matchElapsedSeconds: 3_600,
            setElapsedSeconds: [0: 3_600],
            totalSteps: 480
        )
    }

    func test_encodeThenDecode_preservesRecords() throws {
        let records = [makeRecord(), makeRecord()]

        let data = try MemoryStore.encode(records)
        let decoded = try MemoryStore.decode(data)

        XCTAssertEqual(decoded, records)
        XCTAssertEqual(decoded.first?.stats.first?.heartRateBPM, 152)
        XCTAssertEqual(decoded.first?.matchFormat, .bestOf3FullFinalSet)
        XCTAssertEqual(decoded.first?.setElapsedSeconds[0], 3_600)
    }

    func test_encodeEmptyHistory_decodesBackToEmpty() throws {
        let data = try MemoryStore.encode([])
        XCTAssertEqual(try MemoryStore.decode(data), [])
    }

    func test_decodeRejectsCorruptData() {
        XCTAssertThrowsError(try MemoryStore.decode(Data("not json".utf8)))
    }

    func test_decodeRejectsRecordMissingRequiredField() {
        // `startTime` has no default — a record without it must fail loudly
        // rather than decode into a bogus match.
        let json = """
        [{"id":"00000000-0000-0000-0000-000000000001","setScores":[],"stats":[],
          "currentPointsMe":0,"currentPointsOpponent":0,"gameCount":0,"pointCountInTiebreak":0}]
        """
        XCTAssertThrowsError(try MemoryStore.decode(Data(json.utf8)))
    }

    func test_persistedArchiveCodec_envelopeRoundTripAndRecordsKeyCompatibility() throws {
        let records = [makeRecord()]
        let data = try PersistedArchiveCodec.encodeEnvelope(
            records,
            format: PersistedArchiveCodec.historyFormat
        )
        XCTAssertEqual(try MemoryStore.decode(data), records)

        let recordsPayload = try JSONEncoder().encode(records)
        let recordsText = String(decoding: recordsPayload, as: UTF8.self)
        let altJSON = #"{"format":"deucemate.matchHistory","schemaVersion":1,"records":\#(recordsText)}"#
        XCTAssertEqual(try MemoryStore.decode(Data(altJSON.utf8)), records)
    }

    func test_persistedArchiveCodec_rejectsNewerSchemaVersionBeforeDecodingItems() {
        // Even if the inner items contain a future enum case, schemaVersion > 1
        // must surface `.newerSchemaVersion(2)` rather than a generic decode error.
        let futureJSON = """
        {"format":"deucemate.matchHistory","schemaVersion":2,"items":[{"matchFormat":"futureFormat"}]}
        """
        XCTAssertThrowsError(try MemoryStore.decode(Data(futureJSON.utf8))) { error in
            XCTAssertEqual(error as? PersistedArchiveCodec.CodecError, .newerSchemaVersion(2))
        }
    }

    func test_persistedArchiveCodec_rejectsWrongFormatAndZeroSchemaVersion() {
        let wrongFormat = #"{"format":"other.app","schemaVersion":1,"items":[]}"#
        XCTAssertThrowsError(try MemoryStore.decode(Data(wrongFormat.utf8))) { error in
            XCTAssertEqual(error as? PersistedArchiveCodec.CodecError, .wrongFormat("other.app"))
        }

        let zeroVersion = #"{"format":"deucemate.matchHistory","schemaVersion":0,"items":[]}"#
        XCTAssertThrowsError(try MemoryStore.decode(Data(zeroVersion.utf8))) { error in
            XCTAssertEqual(error as? PersistedArchiveCodec.CodecError, .unsupportedSchemaVersion(0))
        }
    }
}
