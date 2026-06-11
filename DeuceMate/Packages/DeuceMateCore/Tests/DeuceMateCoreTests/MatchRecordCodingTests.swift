// MatchRecordCodingTests.swift — JSON round-trip for MatchRecord and PointStat.
import XCTest
@testable import DeuceMateCore

final class MatchRecordCodingTests: XCTestCase {

    func test_matchRecord_roundTrip() throws {
        let record = MatchRecord(
            id: UUID(),
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_003_600),
            setScores: [
                SetScore(gamesMe: 6, gamesOpponent: 3),
                SetScore(gamesMe: 6, gamesOpponent: 4)
            ],
            stats: [
                PointStat(
                    setIndex: 0,
                    server: .me,
                    winner: .me,
                    outcome: .winner,
                    isSecondServe: false,
                    isBreakPoint: true,
                    endingShot: .serve,
                    gameScoreAtStart: GameScoreSnapshot(server: 0, returner: 0, isTiebreak: false)
                )
            ],
            iWon: true,
            matchType: .singles,
            matchFormat: .standard,
            matchElapsedSeconds: 3600,
            setElapsedSeconds: [0: 1200, 1: 2400]
        )

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(MatchRecord.self, from: data)

        XCTAssertEqual(decoded.id, record.id)
        XCTAssertEqual(decoded.iWon, true)
        XCTAssertEqual(decoded.setScores.count, 2)
        XCTAssertEqual(decoded.stats.count, 1)
        XCTAssertEqual(decoded.stats[0].outcome, .winner)
        XCTAssertEqual(decoded.stats[0].endingShot, .serve)
        XCTAssertEqual(decoded.stats[0].isBreakPoint, true)
        XCTAssertEqual(decoded.stats[0].gameScoreAtStart?.isTiebreak, false)
        XCTAssertEqual(decoded.matchElapsedSeconds, 3600)
        XCTAssertEqual(decoded.setElapsedSeconds[0], 1200)
        XCTAssertEqual(decoded.setElapsedSeconds[1], 2400)
    }

    func test_matchRecord_inProgress_roundTrip() throws {
        let record = MatchRecord(
            startTime: Date(),
            setScores: [SetScore()],
            stats: [],
            iWon: nil,
            matchType: .doubles,
            matchFormat: .superTiebreak,
            doublesServer: .partner,
            doublesServiceOrder: [.me, .opponentS1, .partner, .opponentS2],
            doublesServiceIndex: 2,
            tiebreakStartDoublesIndex: 1
        )

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(MatchRecord.self, from: data)

        XCTAssertNil(decoded.iWon)
        XCTAssertEqual(decoded.matchType, .doubles)
        XCTAssertEqual(decoded.matchFormat, .superTiebreak)
        XCTAssertEqual(decoded.doublesServer, .partner)
        XCTAssertEqual(decoded.doublesServiceOrder, [.me, .opponentS1, .partner, .opponentS2])
        XCTAssertEqual(decoded.doublesServiceIndex, 2)
    }

    func test_pointStat_missingOptionalFields_defaultsGracefully() throws {
        // Simulate a record written before isBreakPoint / gameScoreAtStart shipped.
        let minimalJSON = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "timestamp": 1700000000,
          "setIndex": 0,
          "server": "me",
          "winner": "me",
          "outcome": "winner",
          "isSecondServe": false
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(PointStat.self, from: minimalJSON)
        XCTAssertFalse(decoded.isBreakPoint)
        XCTAssertNil(decoded.endingShot)
        XCTAssertNil(decoded.gameScoreAtStart)
    }

    func test_pointStat_decodesPreFeatureJSONWithoutSecondServe() throws {
        // Simulates an archive written before per-point second-serve capture: the
        // isSecondServe key is absent entirely and must default to false rather
        // than failing to decode.
        let legacyJSON = """
        {
          "id": "00000000-0000-0000-0000-000000000002",
          "timestamp": 1700000000,
          "setIndex": 0,
          "server": "me",
          "winner": "me",
          "outcome": "winner"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(PointStat.self, from: legacyJSON)
        XCTAssertFalse(decoded.isSecondServe)
        XCTAssertEqual(decoded.outcome, .winner)
    }

    func test_arrayRoundTrip_viaStatsStoring() throws {
        let records = [
            MatchRecord(startTime: Date(), setScores: [], stats: [], iWon: true),
            MatchRecord(startTime: Date(), setScores: [], stats: [], iWon: nil)
        ]
        let data = try StatsStore_Codec.encode(records)
        let decoded = try StatsStore_Codec.decode(data)
        XCTAssertEqual(decoded.count, 2)
    }

    // MARK: - Heart-rate field backward compatibility

    func test_pointStat_heartRateRoundTrips() throws {
        let original = PointStat(
            setIndex: 0,
            server: .me,
            winner: .me,
            outcome: .winner,
            isSecondServe: false,
            heartRateBPM: 156
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PointStat.self, from: data)
        XCTAssertEqual(decoded.heartRateBPM, 156)
    }

    func test_pointStat_decodesPreFeatureJSONAsNilHeartRate() throws {
        // Simulates an archive written before heartRateBPM existed.
        let legacyJSON = """
        {
            "id": "11111111-2222-3333-4444-555555555555",
            "timestamp": 1700000000,
            "setIndex": 0,
            "server": "me",
            "winner": "me",
            "outcome": "winner",
            "isSecondServe": false,
            "isBreakPoint": false
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PointStat.self, from: legacyJSON)
        XCTAssertNil(decoded.heartRateBPM)
        XCTAssertEqual(decoded.outcome, .winner)
    }

    // MARK: - Per-point steps field backward compatibility

    func test_pointStat_stepsCumulativeRoundTrips() throws {
        let original = PointStat(
            setIndex: 0,
            server: .me,
            winner: .me,
            outcome: .winner,
            isSecondServe: false,
            stepsCumulative: 412
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PointStat.self, from: data)
        XCTAssertEqual(decoded.stepsCumulative, 412)
    }

    func test_pointStat_decodesPreFeatureJSONAsNilSteps() throws {
        // Simulates an archive written before stepsCumulative existed
        // (i.e. includes heartRateBPM but not steps).
        let legacyJSON = """
        {
            "id": "22222222-3333-4444-5555-666666666666",
            "timestamp": 1700000000,
            "setIndex": 0,
            "server": "me",
            "winner": "me",
            "outcome": "winner",
            "isSecondServe": false,
            "isBreakPoint": false,
            "heartRateBPM": 142
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PointStat.self, from: legacyJSON)
        XCTAssertNil(decoded.stepsCumulative)
        XCTAssertEqual(decoded.heartRateBPM, 142)
        XCTAssertEqual(decoded.outcome, .winner)
    }

    func test_matchRecord_preservesPerPointStepsAlongsideTotal() throws {
        let record = MatchRecord(
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            setScores: [SetScore(gamesMe: 1, gamesOpponent: 0)],
            stats: [
                PointStat(setIndex: 0, server: .me, winner: .me,
                          outcome: .winner, isSecondServe: false,
                          stepsCumulative: 18),
                PointStat(setIndex: 0, server: .me, winner: .opponent,
                          outcome: .unforcedError, isSecondServe: false,
                          stepsCumulative: 47)
            ],
            iWon: true,
            totalSteps: 53
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(MatchRecord.self, from: data)
        XCTAssertEqual(decoded.stats.count, 2)
        XCTAssertEqual(decoded.stats[0].stepsCumulative, 18)
        XCTAssertEqual(decoded.stats[1].stepsCumulative, 47)
        XCTAssertEqual(decoded.totalSteps, 53)
    }
}

/// Wraps the static helpers on StatsStoring for testing.
private enum StatsStore_Codec {
    static func encode(_ records: [MatchRecord]) throws -> Data {
        try JSONEncoder().encode(records)
    }
    static func decode(_ data: Data) throws -> [MatchRecord] {
        try JSONDecoder().decode([MatchRecord].self, from: data)
    }
}
