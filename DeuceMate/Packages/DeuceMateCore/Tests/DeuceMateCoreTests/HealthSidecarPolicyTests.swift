// HealthSidecarPolicyTests.swift — device-local Health sidecar projection rules.
import XCTest
@testable import DeuceMateCore

final class HealthSidecarPolicyTests: XCTestCase {
    private let matchID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let pointID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!

    private func record(
        totalSteps: Int? = 1_234,
        heartRateBPM: Int? = 156,
        stepsCumulative: Int? = 42
    ) -> MatchRecord {
        MatchRecord(
            id: matchID,
            startTime: Date(timeIntervalSince1970: 1_000),
            endTime: Date(timeIntervalSince1970: 2_000),
            setScores: [SetScore(gamesMe: 6, gamesOpponent: 4)],
            stats: [PointStat(
                id: pointID,
                timestamp: Date(timeIntervalSince1970: 1_100),
                setIndex: 0,
                server: .me,
                winner: .me,
                outcome: .winner,
                heartRateBPM: heartRateBPM,
                stepsCumulative: stepsCumulative
            )],
            iWon: true,
            totalSteps: totalSteps,
            totalDistanceMeters: 3_210,
            totalCaloriesKcal: 456
        )
    }

    func test_splitThenMergeIsFullFidelityIdentity() {
        let original = record()
        let split = HealthSidecarPolicy.split([original])

        XCTAssertEqual(HealthSidecarPolicy.merge(stripped: split.stripped, health: split.health), [original])
    }

    func test_splitStripsEveryHealthFieldAndProjectsOnlyHealth() throws {
        let split = HealthSidecarPolicy.split([record()])
        let stripped = try XCTUnwrap(split.stripped.first)
        XCTAssertNil(stripped.totalSteps)
        XCTAssertNil(stripped.totalDistanceMeters)
        XCTAssertNil(stripped.totalCaloriesKcal)
        XCTAssertNil(stripped.stats.first?.heartRateBPM)
        XCTAssertNil(stripped.stats.first?.stepsCumulative)

        let encodedMain = try JSONEncoder().encode(split.stripped)
        let mainJSON = String(decoding: encodedMain, as: UTF8.self)
        for forbiddenKey in [
            "totalSteps",
            "totalDistanceMeters",
            "totalCaloriesKcal",
            "heartRateBPM",
            "stepsCumulative"
        ] {
            XCTAssertFalse(mainJSON.contains("\"\(forbiddenKey)\""), "Main archive contains \(forbiddenKey)")
        }

        let health = try XCTUnwrap(split.health.first)
        XCTAssertEqual(health.matchID, matchID)
        XCTAssertEqual(health.points.map(\.pointID), [pointID])
    }

    func test_splitOmitsRecordsAndPointsWithoutHealth() throws {
        var noHealth = record(totalSteps: nil, heartRateBPM: nil, stepsCumulative: nil)
        noHealth.totalDistanceMeters = nil
        noHealth.totalCaloriesKcal = nil
        XCTAssertTrue(HealthSidecarPolicy.split([noHealth]).health.isEmpty)

        let totalsOnly = MatchRecord(
            id: matchID,
            startTime: Date(),
            setScores: [],
            stats: [PointStat(setIndex: 0, server: .me, winner: .me, outcome: .winner)],
            totalSteps: 5
        )
        let projected = try XCTUnwrap(HealthSidecarPolicy.split([totalsOnly]).health.first)
        XCTAssertTrue(projected.points.isEmpty)
    }

    func test_missingAndOrphanSidecarEntriesAreIgnored() {
        let stripped = record().strippingHealthData()
        XCTAssertEqual(HealthSidecarPolicy.merge(stripped: [stripped], health: []), [stripped])

        let orphan = MatchHealthData(matchID: UUID(), totalSteps: 999)
        XCTAssertEqual(HealthSidecarPolicy.merge(stripped: [stripped], health: [orphan]), [stripped])
    }

    func test_mergeDoesNotOverwriteExistingHealth() throws {
        let existing = record(totalSteps: 10, heartRateBPM: 100, stepsCumulative: 20)
        let sidecar = MatchHealthData(
            matchID: matchID,
            totalSteps: 99,
            totalDistanceMeters: 99,
            totalCaloriesKcal: 99,
            points: [PointHealthData(pointID: pointID, heartRateBPM: 199, stepsCumulative: 99)]
        )
        let merged = try XCTUnwrap(HealthSidecarPolicy.merge(stripped: [existing], health: [sidecar]).first)
        XCTAssertEqual(merged.totalSteps, 10)
        XCTAssertEqual(merged.stats.first?.heartRateBPM, 100)
        XCTAssertEqual(merged.stats.first?.stepsCumulative, 20)
    }

    func test_matchHealthDataDecodesLegacyShapeWithoutPoints() throws {
        let json = """
        {"matchID":"\(matchID.uuidString)","totalSteps":123}
        """
        let decoded = try JSONDecoder().decode(MatchHealthData.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.totalSteps, 123)
        XCTAssertEqual(decoded.points, [])
    }
}
