// HealthExportConsentTests.swift — the per-export HealthKit disclosure policy.
import XCTest
@testable import DeuceMateCore

final class HealthExportConsentTests: XCTestCase {

    private func record(
        heartRateBPM: Int? = 156,
        stepsCumulative: Int? = 42,
        totalSteps: Int? = 1_234,
        totalDistanceMeters: Double? = 3_210,
        totalCaloriesKcal: Double? = 456
    ) -> MatchRecord {
        MatchRecord(
            id: UUID(),
            startTime: Date(timeIntervalSince1970: 1_000),
            endTime: Date(timeIntervalSince1970: 2_000),
            setScores: [SetScore(gamesMe: 6, gamesOpponent: 4)],
            stats: [PointStat(
                id: UUID(),
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
            totalDistanceMeters: totalDistanceMeters,
            totalCaloriesKcal: totalCaloriesKcal
        )
    }

    private func point(offset: TimeInterval, hr: Int?, steps: Int?, winner: Player) -> PointStat {
        PointStat(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 1_000 + offset),
            setIndex: 0,
            server: .me,
            winner: winner,
            outcome: .winner,
            heartRateBPM: hr,
            stepsCumulative: steps
        )
    }

    /// Multi-point, fully-populated record so the HTML export's HR/steps/totals
    /// blocks are all non-nil for the agreement test.
    private func richRecord() -> MatchRecord {
        MatchRecord(
            id: UUID(),
            startTime: Date(timeIntervalSince1970: 1_000),
            endTime: Date(timeIntervalSince1970: 2_000),
            setScores: [SetScore(gamesMe: 6, gamesOpponent: 4)],
            stats: [
                point(offset: 100, hr: 140, steps: 10, winner: .me),
                point(offset: 200, hr: 150, steps: 25, winner: .opponent),
                point(offset: 300, hr: 160, steps: 42, winner: .me)
            ],
            iWon: true,
            totalSteps: 1_234,
            totalDistanceMeters: 3_210,
            totalCaloriesKcal: 456
        )
    }

    // MARK: - presentFields

    func test_presentFieldsIncludesAllFiveForRecorderWhenPresent() {
        XCTAssertEqual(
            HealthExportConsent.presentFields(in: record(), focal: .me),
            [.heartRate, .heartRateZones, .steps, .calories, .distance]
        )
    }

    func test_presentFieldsForOpponentOmitsHeartRateZones() {
        // The opponent full/AI export still exposes per-point "Opponent HR", but
        // heart-rate zones are the recorder's own and are never shown for the opponent.
        XCTAssertEqual(
            HealthExportConsent.presentFields(in: record(), focal: .opponent),
            [.heartRate, .steps, .calories, .distance]
        )
    }

    func test_presentFieldsReflectsOnlyRecordedFields() {
        let stepsOnly = record(
            heartRateBPM: nil, stepsCumulative: nil,
            totalSteps: 900, totalDistanceMeters: nil, totalCaloriesKcal: nil
        )
        XCTAssertEqual(HealthExportConsent.presentFields(in: stepsOnly, focal: .me), [.steps])
        XCTAssertEqual(HealthExportConsent.presentFields(in: stepsOnly, focal: .opponent), [.steps])

        let hrOnly = record(
            heartRateBPM: 150, stepsCumulative: nil,
            totalSteps: nil, totalDistanceMeters: nil, totalCaloriesKcal: nil
        )
        XCTAssertEqual(HealthExportConsent.presentFields(in: hrOnly, focal: .me), [.heartRate, .heartRateZones])
        XCTAssertEqual(HealthExportConsent.presentFields(in: hrOnly, focal: .opponent), [.heartRate])
    }

    func test_presentFieldsUsesPerPointStepsEvenWithoutMatchTotal() {
        let perPointOnly = record(
            heartRateBPM: nil, stepsCumulative: 30,
            totalSteps: nil, totalDistanceMeters: nil, totalCaloriesKcal: nil
        )
        XCTAssertEqual(HealthExportConsent.presentFields(in: perPointOnly, focal: .me), [.steps])
    }

    func test_presentFieldsEmptyForHealthFreeRecord() {
        let none = record(
            heartRateBPM: nil, stepsCumulative: nil,
            totalSteps: nil, totalDistanceMeters: nil, totalCaloriesKcal: nil
        )
        XCTAssertTrue(HealthExportConsent.presentFields(in: none, focal: .me).isEmpty)
        XCTAssertTrue(HealthExportConsent.presentFields(in: none, focal: .opponent).isEmpty)
    }

    // MARK: - disclosure fidelity

    func test_disclosureNamesExactlyTheGivenFields() {
        for fields: [HealthExportField] in [
            [.heartRate, .steps, .distance],
            [.steps, .calories],
            HealthExportField.allCases
        ] {
            let (title, message) = HealthExportConsent.disclosure(fields: fields, destination: .sharedReport)
            XCTAssertFalse(title.isEmpty)
            for f in fields {
                XCTAssertTrue(message.contains(f.displayName), "\(fields) missing \(f.displayName)")
            }
            for f in HealthExportField.allCases where !fields.contains(f) {
                XCTAssertFalse(message.contains(f.displayName), "\(fields) unexpectedly names \(f.displayName)")
            }
        }
    }

    func test_disclosureRecipientClauseVariesByDestination() {
        let fields: [HealthExportField] = [.heartRate]
        XCTAssertTrue(HealthExportConsent.disclosure(fields: fields, destination: .archiveFile)
            .message.contains("Files app or iCloud Drive location"))
        let shared = HealthExportConsent.disclosure(fields: fields, destination: .sharedReport).message
        XCTAssertTrue(shared.contains("a person"))
        XCTAssertTrue(shared.contains("AI service"))
        XCTAssertTrue(HealthExportConsent.disclosure(fields: fields, destination: .aiService)
            .message.contains("AI app or website"))
    }

    func test_disclosureFormatsFieldListWithOxfordCommas() {
        func message(_ fields: [HealthExportField]) -> String {
            HealthExportConsent.disclosure(fields: fields, destination: .sharedReport).message
        }
        XCTAssertTrue(message([.steps]).contains("recorded steps."))
        XCTAssertTrue(message([.steps, .calories]).contains("steps and calories."))
        XCTAssertTrue(message([.steps, .calories, .distance]).contains("steps, calories, and distance."))
    }

    // MARK: - disclosure ↔ export agreement (Core, recorder-framed HTML)

    func test_presentFieldsForRecorderAgreesWithHtmlExport() {
        let record = richRecord()
        let fields = Set(HealthExportConsent.presentFields(in: record, focal: .me))
        let vm = MatchWebViewModel.make(from: record)

        // Heart rate + its zones (recorder-only) ⟺ the HTML hr block.
        XCTAssertEqual(fields.contains(.heartRate), vm.hr != nil)
        XCTAssertEqual(fields.contains(.heartRateZones), vm.hr != nil)
        // Steps ⟺ steps series or the totals row.
        let htmlHasSteps = vm.steps != nil || vm.meta.totals?.stepsDisplay != nil
        XCTAssertEqual(fields.contains(.steps), htmlHasSteps)
        // Calories / distance ⟺ their totals rows.
        XCTAssertEqual(fields.contains(.calories), vm.meta.totals?.caloriesDisplay != nil)
        XCTAssertEqual(fields.contains(.distance), vm.meta.totals?.distanceDisplay != nil)
        // A fully-populated record exposes all five.
        XCTAssertEqual(fields, Set(HealthExportField.allCases))
    }

    func test_healthFreeRecordDisclosesNothingAndHtmlEmitsNoHealth() {
        let record = record(
            heartRateBPM: nil, stepsCumulative: nil,
            totalSteps: nil, totalDistanceMeters: nil, totalCaloriesKcal: nil
        )
        XCTAssertTrue(HealthExportConsent.presentFields(in: record, focal: .me).isEmpty)
        let vm = MatchWebViewModel.make(from: record)
        XCTAssertNil(vm.hr)
        XCTAssertNil(vm.steps)
        XCTAssertNil(vm.meta.totals?.caloriesDisplay)
        XCTAssertNil(vm.meta.totals?.distanceDisplay)
    }
}
