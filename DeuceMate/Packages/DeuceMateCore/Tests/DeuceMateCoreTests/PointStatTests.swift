// PointStatTests.swift — the point atom's own queries and identifiers, plus the
// `PendingPointInfo` hand-off the watch persists mid-categorisation.
import XCTest
@testable import DeuceMateCore

final class PointStatTests: XCTestCase {

    private func point(
        server: Player = .me,
        winner: Player = .me,
        outcome: PointOutcome = .winner,
        endingShot: EndingShot? = nil
    ) -> PointStat {
        PointStat(
            setIndex: 0,
            server: server,
            winner: winner,
            outcome: outcome,
            endingShot: endingShot
        )
    }

    // MARK: - Point queries

    func test_isDoubleFault_onlyForDoubleFaultOutcome() {
        XCTAssertTrue(point(outcome: .doubleFault).isDoubleFault)
        for outcome in [PointOutcome.winner, .forcedError, .unforcedError, .uncategorized] {
            XCTAssertFalse(point(outcome: outcome).isDoubleFault, "\(outcome) is not a double fault")
        }
    }

    func test_wasServing_andWasWonBy_areSideSpecific() {
        let served = point(server: .me, winner: .opponent)
        XCTAssertTrue(served.wasServing(.me))
        XCTAssertFalse(served.wasServing(.opponent))
        XCTAssertTrue(served.wasWonBy(.opponent))
        XCTAssertFalse(served.wasWonBy(.me))
    }

    // MARK: - Identifiers

    func test_categoryEnums_identifyThemselvesByRawValue() {
        // The graph/chip lists are `Identifiable`-driven; ids must be the stable
        // persisted raw values, and unique within each enum.
        for outcome in PointOutcome.allCases { XCTAssertEqual(outcome.id, outcome.rawValue) }
        for shot in EndingShot.allCases { XCTAssertEqual(shot.id, shot.rawValue) }
        for category in ServingPointCategory.allCases { XCTAssertEqual(category.id, category.rawValue) }

        XCTAssertEqual(Set(PointOutcome.allCases.map(\.id)).count, PointOutcome.allCases.count)
        XCTAssertEqual(Set(EndingShot.allCases.map(\.id)).count, EndingShot.allCases.count)
        XCTAssertEqual(Set(ServingPointCategory.allCases.map(\.id)).count,
                       ServingPointCategory.allCases.count)
    }

    func test_userSelectableOutcomes_excludeUncategorized() {
        XCTAssertFalse(PointOutcome.userSelectable.contains(.uncategorized))
        XCTAssertEqual(Set(PointOutcome.userSelectable),
                       Set(PointOutcome.allCases).subtracting([.uncategorized]))
    }

    // MARK: - Health projection

    func test_strippingHealthData_keepsTennisFactsAndDropsHealthOnly() {
        let full = PointStat(
            setIndex: 1,
            server: .opponent,
            winner: .me,
            outcome: .forcedError,
            isSecondServe: true,
            isBreakPoint: true,
            endingShot: .return,
            gameScoreAtStart: GameScoreSnapshot(server: 3, returner: 2, isTiebreak: false),
            heartRateBPM: 168,
            stepsCumulative: 900
        )

        let stripped = full.strippingHealthData()

        XCTAssertNil(stripped.heartRateBPM)
        XCTAssertNil(stripped.stepsCumulative)
        XCTAssertEqual(stripped.id, full.id)
        XCTAssertEqual(stripped.setIndex, 1)
        XCTAssertEqual(stripped.server, .opponent)
        XCTAssertEqual(stripped.outcome, .forcedError)
        XCTAssertTrue(stripped.isSecondServe)
        XCTAssertTrue(stripped.isBreakPoint)
        XCTAssertEqual(stripped.endingShot, .return)
        XCTAssertEqual(stripped.gameScoreAtStart?.server, 3)
    }

    func test_fillingMissingHealthData_onlyFillsNilFields() {
        let base = PointStat(setIndex: 0, server: .me, winner: .me, outcome: .winner,
                             heartRateBPM: 140, stepsCumulative: nil)
        let source = PointStat(id: base.id, setIndex: 0, server: .me, winner: .me, outcome: .winner,
                               heartRateBPM: 199, stepsCumulative: 750)

        let filled = base.fillingMissingHealthData(from: source)

        XCTAssertEqual(filled.heartRateBPM, 140)
        XCTAssertEqual(filled.stepsCumulative, 750)
    }

    // MARK: - PendingPointInfo backward compatibility

    func test_pendingPointInfo_decodesLegacyJSONWithoutBreakPointOrScore() throws {
        let json = """
        {"server":"me","winner":"opponent","setIndex":2,"isSecondServe":true}
        """
        let decoded = try JSONDecoder().decode(PendingPointInfo.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.server, .me)
        XCTAssertEqual(decoded.winner, .opponent)
        XCTAssertEqual(decoded.setIndex, 2)
        XCTAssertTrue(decoded.isSecondServe)
        XCTAssertFalse(decoded.isBreakPoint)
        XCTAssertNil(decoded.gameScoreAtStart)
    }

    func test_pendingPointInfo_roundTripsFullShape() throws {
        let pending = PendingPointInfo(
            server: .opponent, winner: .me, setIndex: 0,
            isSecondServe: false, isBreakPoint: true,
            gameScoreAtStart: GameScoreSnapshot(server: 6, returner: 5, isTiebreak: true)
        )
        let decoded = try JSONDecoder().decode(
            PendingPointInfo.self, from: try JSONEncoder().encode(pending)
        )
        XCTAssertEqual(decoded, pending)
    }
}
