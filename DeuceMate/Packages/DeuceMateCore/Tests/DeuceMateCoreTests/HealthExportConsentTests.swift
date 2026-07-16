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

    func test_presentFieldsIncludesAllFiveForRecorderRegardlessOfExportKind() {
        // For the recorder the HR/movement summary sections render regardless of
        // the raw-point table, so summary and full expose the same categories.
        for includesRawPoints in [true, false] {
            XCTAssertEqual(
                HealthExportConsent.presentFields(in: record(), focal: .me, includesRawPoints: includesRawPoints),
                [.heartRate, .heartRateZones, .steps, .calories, .distance]
            )
        }
    }

    func test_presentFieldsForOpponentFullExposesHeartRateButNeverZones() {
        // The opponent full/AI export exposes per-point "Opponent HR" via the raw
        // table, but heart-rate zones are the recorder's own and never shown.
        XCTAssertEqual(
            HealthExportConsent.presentFields(in: record(), focal: .opponent, includesRawPoints: true),
            [.heartRate, .steps, .calories, .distance]
        )
    }

    func test_presentFieldsForOpponentSummaryOmitsHeartRate() {
        // The opponent SUMMARY omits the raw table and the recorder HR section, so
        // no heart rate is shared — only the match totals.
        XCTAssertEqual(
            HealthExportConsent.presentFields(in: record(), focal: .opponent, includesRawPoints: false),
            [.steps, .calories, .distance]
        )
    }

    func test_presentFieldsReflectsOnlyRecordedFields() {
        let stepsOnly = record(
            heartRateBPM: nil, stepsCumulative: nil,
            totalSteps: 900, totalDistanceMeters: nil, totalCaloriesKcal: nil
        )
        for includesRawPoints in [true, false] {
            XCTAssertEqual(HealthExportConsent.presentFields(in: stepsOnly, focal: .me, includesRawPoints: includesRawPoints), [.steps])
            // A match total (> 0) shows in the overview for both perspectives and kinds.
            XCTAssertEqual(HealthExportConsent.presentFields(in: stepsOnly, focal: .opponent, includesRawPoints: includesRawPoints), [.steps])
        }

        let hrOnly = record(
            heartRateBPM: 150, stepsCumulative: nil,
            totalSteps: nil, totalDistanceMeters: nil, totalCaloriesKcal: nil
        )
        for includesRawPoints in [true, false] {
            XCTAssertEqual(HealthExportConsent.presentFields(in: hrOnly, focal: .me, includesRawPoints: includesRawPoints), [.heartRate, .heartRateZones])
        }
        XCTAssertEqual(HealthExportConsent.presentFields(in: hrOnly, focal: .opponent, includesRawPoints: true), [.heartRate])
        XCTAssertEqual(HealthExportConsent.presentFields(in: hrOnly, focal: .opponent, includesRawPoints: false), [])
    }

    func test_presentFieldsUsesPerPointStepsOnlyViaRawTableForOpponent() {
        let perPointOnly = record(
            heartRateBPM: nil, stepsCumulative: 30,
            totalSteps: nil, totalDistanceMeters: nil, totalCaloriesKcal: nil
        )
        // Recorder: the movement summary shows per-point steps regardless of kind.
        XCTAssertEqual(HealthExportConsent.presentFields(in: perPointOnly, focal: .me, includesRawPoints: false), [.steps])
        // Opponent: per-point-only steps reach the export solely via the raw table.
        XCTAssertEqual(HealthExportConsent.presentFields(in: perPointOnly, focal: .opponent, includesRawPoints: true), [.steps])
        XCTAssertEqual(HealthExportConsent.presentFields(in: perPointOnly, focal: .opponent, includesRawPoints: false), [])
    }

    func test_presentFieldsExcludesZeroValuedTotals() {
        // Totals recorded as 0 are not emitted by the exporters (they gate on > 0),
        // so they must not be disclosed. Heart rate is still present.
        let zeroTotals = record(
            heartRateBPM: 150, stepsCumulative: nil,
            totalSteps: 0, totalDistanceMeters: 0, totalCaloriesKcal: 0
        )
        XCTAssertEqual(
            HealthExportConsent.presentFields(in: zeroTotals, focal: .me, includesRawPoints: true),
            [.heartRate, .heartRateZones]
        )
    }

    func test_presentFieldsEmptyForHealthFreeRecord() {
        let none = record(
            heartRateBPM: nil, stepsCumulative: nil,
            totalSteps: nil, totalDistanceMeters: nil, totalCaloriesKcal: nil
        )
        for focal in [Player.me, .opponent] {
            for includesRawPoints in [true, false] {
                XCTAssertTrue(HealthExportConsent.presentFields(in: none, focal: focal, includesRawPoints: includesRawPoints).isEmpty)
            }
        }
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
        // `.sharedReport` is used for text, HTML, and the AI Coach hand-off, so it
        // must name the broad recipient set (including "an AI service").
        let shared = HealthExportConsent.disclosure(fields: fields, destination: .sharedReport).message
        XCTAssertTrue(shared.contains("a person"))
        XCTAssertTrue(shared.contains("AI service"))
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
        let fields = Set(HealthExportConsent.presentFields(in: record, focal: .me, includesRawPoints: true))
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
        XCTAssertTrue(HealthExportConsent.presentFields(in: record, focal: .me, includesRawPoints: true).isEmpty)
        let vm = MatchWebViewModel.make(from: record)
        XCTAssertNil(vm.hr)
        XCTAssertNil(vm.steps)
        XCTAssertNil(vm.meta.totals?.caloriesDisplay)
        XCTAssertNil(vm.meta.totals?.distanceDisplay)
    }
}
