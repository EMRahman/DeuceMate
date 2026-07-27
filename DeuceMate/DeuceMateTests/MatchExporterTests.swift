// MatchExporterTests.swift — the plain-text / AI-prompt exporter's HEALTH content.
//
// MatchExporter is deliberately full-fidelity (a user-consented export path, see
// docs/architecture/health-data-flow.md §5), so what matters here is not that
// health is absent but that it appears exactly where the per-export disclosure
// promises: recorder-only heart rate / zones / movement, step/calorie/distance
// totals for both perspectives only when > 0, and per-point HR/steps only via the
// raw-point table. The final test cross-checks that `HealthExportConsent`
// (Core, the disclosure's single source of truth) agrees with what the exporter
// actually emits — the `MatchExporter` half of the disclosure↔export agreement
// that HealthExportConsentTests can only assert for the HTML export (Core cannot
// import app-side `MatchExporter`).
import Foundation
import DeuceMateCore
import Testing
@testable import DeuceMate

struct MatchExporterTests {

    // MARK: - Fixtures

    private func point(
        offset: TimeInterval,
        hr: Int?,
        steps: Int?,
        winner: Player,
        outcome: PointOutcome = .winner
    ) -> PointStat {
        PointStat(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 1_000 + offset),
            setIndex: 0,
            server: .me,
            winner: winner,
            outcome: outcome,
            heartRateBPM: hr,
            stepsCumulative: steps
        )
    }

    /// Fully-populated multi-point record: all five HealthKit-derived fields
    /// present and every total > 0, so the recorder export renders every health
    /// section and the disclosure exposes all five categories.
    private func richRecord() -> MatchRecord {
        MatchRecord(
            id: UUID(),
            startTime: Date(timeIntervalSince1970: 1_000),
            endTime: Date(timeIntervalSince1970: 2_000),
            setScores: [SetScore(gamesMe: 6, gamesOpponent: 4)],
            stats: [
                point(offset: 100, hr: 140, steps: 10, winner: .me),
                point(offset: 200, hr: 150, steps: 25, winner: .opponent),
                point(offset: 300, hr: 160, steps: 42, winner: .me),
                point(offset: 400, hr: 155, steps: 60, winner: .me, outcome: .unforcedError)
            ],
            iWon: true,
            totalSteps: 1_234,
            totalDistanceMeters: 3_210,
            totalCaloriesKcal: 456
        )
    }

    private func makeRecord(
        hr: Int?,
        perPointSteps: Int?,
        totalSteps: Int?,
        distance: Double?,
        calories: Double?
    ) -> MatchRecord {
        MatchRecord(
            id: UUID(),
            startTime: Date(timeIntervalSince1970: 1_000),
            endTime: Date(timeIntervalSince1970: 2_000),
            setScores: [SetScore(gamesMe: 6, gamesOpponent: 4)],
            stats: [point(offset: 100, hr: hr, steps: perPointSteps, winner: .me)],
            iWon: true,
            totalSteps: totalSteps,
            totalDistanceMeters: distance,
            totalCaloriesKcal: calories
        )
    }

    // MARK: - Value-based health signatures
    //
    // These detect actual health VALUES, never the raw-table column *headers*
    // (which always render "My HR"/"Steps/Pt"/"Total Steps" even for a health-free
    // match, with "—" in every cell). Detecting values keeps the agreement test
    // honest: a table full of "—" exposes nothing and discloses nothing.

    private func exposesHeartRate(_ s: String) -> Bool {
        // Recorder zone section, or an actual per-point "bpm" value in the table.
        s.contains("## Heart Rate Analysis") || s.contains(" bpm")
    }
    private func exposesHeartRateZones(_ s: String) -> Bool {
        s.contains("## Heart Rate Analysis") // recorder-only; never for the opponent
    }
    private func exposesSteps(_ s: String) -> Bool {
        // Overview total ("Steps:") or the recorder movement section.
        s.contains("Steps:") || s.contains("## Movement & Fatigue")
    }
    private func exposesCalories(_ s: String) -> Bool { s.contains("Calories:") }
    private func exposesDistance(_ s: String) -> Bool { s.contains("Distance:") }

    private func exportExposes(_ field: HealthExportField, in s: String) -> Bool {
        switch field {
        case .heartRate:      return exposesHeartRate(s)
        case .heartRateZones: return exposesHeartRateZones(s)
        case .steps:          return exposesSteps(s)
        case .calories:       return exposesCalories(s)
        case .distance:       return exposesDistance(s)
        }
    }

    // MARK: - Recorder-only rule

    @Test func recorderExportIncludesHeartRateAndMovementSections() {
        // The recorder's HR and movement summaries render regardless of the raw
        // table, so even the summary export carries them.
        let s = MatchExporter.summaryExport(for: richRecord(), focal: .me)
        #expect(s.contains("## Heart Rate Analysis"))
        #expect(s.contains("## Movement & Fatigue"))
    }

    @Test func opponentExportOmitsRecorderOnlyHealthSections() {
        // Heart rate belongs to the recorder; it is never mapped onto the opponent
        // as a derived section. Match totals still appear (they are neutral).
        for export in [
            MatchExporter.summaryExport(for: richRecord(), focal: .opponent),
            MatchExporter.fullExport(for: richRecord(), focal: .opponent)
        ] {
            #expect(!export.contains("## Heart Rate Analysis"))
            #expect(!export.contains("## PulseCoach Insights"))
            #expect(!export.contains("## Movement & Fatigue"))
            #expect(export.contains("Steps:"))
            #expect(export.contains("Calories:"))
            #expect(export.contains("Distance:"))
        }
    }

    // MARK: - Totals gating (> 0, both perspectives)

    @Test func matchTotalsAppearForBothPerspectivesOnlyWhenPositive() {
        let positive = richRecord()
        for focal in [Player.me, .opponent] {
            let s = MatchExporter.summaryExport(for: positive, focal: focal)
            #expect(s.contains("Steps:"))
            #expect(s.contains("Calories:"))
            #expect(s.contains("Distance:"))
        }

        // 0 and nil totals (with no per-point health) must not render overview rows.
        for record in [
            makeRecord(hr: nil, perPointSteps: nil, totalSteps: 0, distance: 0, calories: 0),
            makeRecord(hr: nil, perPointSteps: nil, totalSteps: nil, distance: nil, calories: nil)
        ] {
            for focal in [Player.me, .opponent] {
                let s = MatchExporter.summaryExport(for: record, focal: focal)
                #expect(!s.contains("Steps:"))
                #expect(!s.contains("Calories:"))
                #expect(!s.contains("Distance:"))
            }
        }
    }

    // MARK: - Per-point HR/steps only via the raw table

    @Test func perPointHealthReachesOnlyTheRawTable() {
        let record = richRecord()

        // Summary has no raw table, so no per-point "bpm" values leak.
        let meSummary = MatchExporter.summaryExport(for: record, focal: .me)
        #expect(!meSummary.contains("## Raw Point Data"))
        let oppSummary = MatchExporter.summaryExport(for: record, focal: .opponent)
        #expect(!oppSummary.contains(" bpm"))

        // Full export appends the raw table with per-point HR values.
        let meFull = MatchExporter.fullExport(for: record, focal: .me)
        #expect(meFull.contains("## Raw Point Data"))
        #expect(meFull.contains(" bpm"))
        #expect(meFull.contains("My HR"))

        // The opponent full export exposes per-point HR only as the recorder's
        // "Opponent HR" column — never derived zones.
        let oppFull = MatchExporter.fullExport(for: record, focal: .opponent)
        #expect(oppFull.contains("Opponent HR"))
        #expect(oppFull.contains(" bpm"))
        #expect(!oppFull.contains("## Heart Rate Analysis"))
    }

    // MARK: - AI prompt

    @Test func aiPromptRecorderIncludesMovementAndOpponentPromptDisclaimsRecorderHealth() {
        let record = richRecord()

        let me = MatchExporter.aiPromptExport(for: record, focal: .me)
        #expect(me.contains("Movement & Fitness"))     // the prompt's fitness section
        #expect(me.contains("## Heart Rate Analysis"))  // recorder HR data section
        #expect(me.contains("## Raw Point Data"))

        let opponent = MatchExporter.aiPromptExport(for: record, focal: .opponent)
        // The opponent prompt tells the AI the HR/steps belong to the recorder.
        #expect(opponent.contains("belongs to the recorder (your opponent)"))
        #expect(opponent.contains("Opponent HR"))       // raw table, recorder-framed
        #expect(!opponent.contains("## Heart Rate Analysis"))
    }

    // MARK: - Disclosure ↔ export agreement (the MatchExporter half)

    @Test func disclosureAgreesWithTextExport() {
        let record = richRecord()
        for focal in [Player.me, .opponent] {
            for includesRawPoints in [false, true] {
                let fields = Set(HealthExportConsent.presentFields(
                    in: record, focal: focal, includesRawPoints: includesRawPoints
                ))
                let export = includesRawPoints
                    ? MatchExporter.fullExport(for: record, focal: focal)
                    : MatchExporter.summaryExport(for: record, focal: focal)
                for field in HealthExportField.allCases {
                    #expect(
                        fields.contains(field) == exportExposes(field, in: export),
                        "focal=\(focal) raw=\(includesRawPoints) field=\(field): disclosure=\(fields.contains(field)) export=\(exportExposes(field, in: export))"
                    )
                }
            }
        }
    }

    @Test func healthFreeRecordDisclosesNothingAndExportEmitsNoHealth() {
        let record = makeRecord(hr: nil, perPointSteps: nil, totalSteps: nil, distance: nil, calories: nil)
        for focal in [Player.me, .opponent] {
            for includesRawPoints in [false, true] {
                #expect(HealthExportConsent.presentFields(
                    in: record, focal: focal, includesRawPoints: includesRawPoints
                ).isEmpty)
            }
            // Even with the raw table present, every cell is "—": no real health.
            let full = MatchExporter.fullExport(for: record, focal: focal)
            #expect(!full.contains(" bpm"))
            #expect(!full.contains("## Heart Rate Analysis"))
            #expect(!full.contains("## Movement & Fatigue"))
            #expect(!full.contains("Steps:"))
            #expect(!full.contains("Calories:"))
            #expect(!full.contains("Distance:"))
        }
    }
}
