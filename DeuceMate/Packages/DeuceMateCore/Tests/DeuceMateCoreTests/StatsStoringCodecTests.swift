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

    // MARK: - PersistedArchiveCodec dual-format reader (TECHNICAL_DEBT #19)

    func test_persistedArchiveCodec_roundTripsVersion1EnvelopeAndLegacyBareArray() throws {
        let records = [makeRecord()]
        let bareData = try MemoryStore.encode(records)
        XCTAssertEqual(bareData.first, UInt8(ascii: "["), "step-1 writers keep emitting bare arrays")
        XCTAssertEqual(
            try PersistedArchiveCodec.decode([MatchRecord].self, from: bareData, expectedFormat: PersistedArchiveCodec.historyFormat),
            records
        )

        let envelopeData = try PersistedArchiveCodec.encodeEnvelope(records, format: PersistedArchiveCodec.historyFormat)
        XCTAssertEqual(envelopeData.first, UInt8(ascii: "{"))
        XCTAssertEqual(try MemoryStore.decode(envelopeData), records)
        XCTAssertEqual(try MatchSyncMessage.decodeArray(envelopeData), records)
    }

    func test_persistedArchiveCodec_acceptsRecordsKeyAliasInEnvelope() throws {
        let record = makeRecord()
        let recordJSON = String(decoding: try JSONEncoder().encode([record]), as: UTF8.self)
        let envelopeJSON = """
        {"format":"deucemate.matchHistory","schemaVersion":1,"records":\(recordJSON)}
        """
        let decoded = try PersistedArchiveCodec.decode(
            [MatchRecord].self,
            from: Data(envelopeJSON.utf8),
            expectedFormat: PersistedArchiveCodec.historyFormat
        )
        XCTAssertEqual(decoded, [record])
    }

    func test_persistedArchiveCodec_rejectsNewerSchemaVersionBeforeDecodingElements() {
        // Contains an incompatible body (`items` is not valid `[MatchRecord]`):
        // header validation must fire first and surface `.newerSchemaVersion`.
        let futureJSON = """
        {"format":"deucemate.matchHistory","schemaVersion":2,"items":[{"id":"not-a-uuid","outcome":"smash"}]}
        """
        XCTAssertThrowsError(
            try PersistedArchiveCodec.decode(
                [MatchRecord].self,
                from: Data(futureJSON.utf8),
                expectedFormat: PersistedArchiveCodec.historyFormat
            )
        ) { error in
            XCTAssertEqual(
                error as? PersistedArchiveCodec.CodecError,
                .newerSchemaVersion(version: 2, maxSupported: PersistedArchiveCodec.currentSchemaVersion)
            )
        }
        XCTAssertThrowsError(try MatchSyncMessage.decodeArray(Data(futureJSON.utf8))) { error in
            XCTAssertEqual(
                error as? PersistedArchiveCodec.CodecError,
                .newerSchemaVersion(version: 2, maxSupported: PersistedArchiveCodec.currentSchemaVersion)
            )
        }
    }

    func test_persistedArchiveCodec_rejectsWrongFormatAndUnsupportedOldVersion() {
        let wrongFormat = Data(#"{"format":"other.format","schemaVersion":1,"items":[]}"#.utf8)
        XCTAssertThrowsError(
            try PersistedArchiveCodec.decode([UUID].self, from: wrongFormat, expectedFormat: PersistedArchiveCodec.tombstonesFormat)
        ) { error in
            XCTAssertEqual(
                error as? PersistedArchiveCodec.CodecError,
                .wrongFormat(expected: PersistedArchiveCodec.tombstonesFormat, actual: "other.format")
            )
        }

        let zeroVersion = Data(#"{"format":"deucemate.deletedMatchIDs","schemaVersion":0,"items":[]}"#.utf8)
        XCTAssertThrowsError(
            try PersistedArchiveCodec.decode([UUID].self, from: zeroVersion, expectedFormat: PersistedArchiveCodec.tombstonesFormat)
        ) { error in
            XCTAssertEqual(error as? PersistedArchiveCodec.CodecError, .unsupportedSchemaVersion(0))
        }

        XCTAssertThrowsError(
            try PersistedArchiveCodec.decode([UUID].self, from: Data("   \n\t ".utf8), expectedFormat: PersistedArchiveCodec.tombstonesFormat)
        ) { error in
            XCTAssertEqual(error as? PersistedArchiveCodec.CodecError, .emptyData)
        }
    }
}
