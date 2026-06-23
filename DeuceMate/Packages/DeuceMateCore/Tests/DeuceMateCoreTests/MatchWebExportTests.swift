// MatchWebExportTests.swift — locks the self-contained interactive HTML export:
// the view-model shape, both-perspective consistency, the recorder-only-HR rule,
// and that the produced HTML is genuinely offline / self-contained.
import XCTest
import Foundation
@testable import DeuceMateCore

final class MatchWebExportTests: XCTestCase {

    // MARK: - Fixtures

    private func snap(_ sv: Int, _ rt: Int, _ tb: Bool) -> GameScoreSnapshot {
        GameScoreSnapshot(server: sv, returner: rt, isTiebreak: tb)
    }

    /// A representative completed match with mixed outcomes and per-point HR.
    private func makeRecord(withHR: Bool = true) -> MatchRecord {
        let stats: [PointStat] = [
            PointStat(setIndex: 0, server: .me,       winner: .me,       outcome: .winner,        isSecondServe: false, isBreakPoint: false, endingShot: .serve,       gameScoreAtStart: snap(0, 0, false), heartRateBPM: withHR ? 140 : nil, stepsCumulative: withHR ? 100 : nil),
            PointStat(setIndex: 0, server: .me,       winner: .opponent, outcome: .doubleFault,   isSecondServe: true,  isBreakPoint: false, endingShot: .serve,       gameScoreAtStart: snap(1, 0, false), heartRateBPM: withHR ? 145 : nil, stepsCumulative: withHR ? 180 : nil),
            PointStat(setIndex: 0, server: .me,       winner: .opponent, outcome: .unforcedError, isSecondServe: false, isBreakPoint: false, endingShot: .rally,       gameScoreAtStart: snap(2, 1, false), heartRateBPM: withHR ? 150 : nil, stepsCumulative: withHR ? 260 : nil),
            PointStat(setIndex: 0, server: .opponent, winner: .me,       outcome: .winner,        isSecondServe: false, isBreakPoint: false, endingShot: .return,      gameScoreAtStart: snap(0, 0, false), heartRateBPM: withHR ? 152 : nil, stepsCumulative: withHR ? 340 : nil),
            PointStat(setIndex: 0, server: .opponent, winner: .me,       outcome: .forcedError,   isSecondServe: true,  isBreakPoint: true,  endingShot: .servePlusOne, gameScoreAtStart: snap(3, 3, false), heartRateBPM: withHR ? 158 : nil, stepsCumulative: withHR ? 420 : nil),
            PointStat(setIndex: 1, server: .me,       winner: .me,       outcome: .winner,        isSecondServe: false, isBreakPoint: false, endingShot: .rally,       gameScoreAtStart: snap(4, 4, true),  heartRateBPM: withHR ? 160 : nil, stepsCumulative: withHR ? 500 : nil)
        ]
        return MatchRecord(
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_003_600),
            setScores: [
                SetScore(gamesMe: 6, gamesOpponent: 4),
                SetScore(gamesMe: 7, gamesOpponent: 5)
            ],
            stats: stats,
            iWon: true,
            matchType: .singles,
            matchFormat: .standard,
            matchElapsedSeconds: 3600,
            setElapsedSeconds: [0: 2400, 1: 1200],
            totalSteps: withHR ? 1200 : nil,
            totalDistanceMeters: withHR ? 900 : nil,
            totalCaloriesKcal: withHR ? 310 : nil
        )
    }

    /// A score-only match: every point uncategorized, no HR/steps.
    private func makeScoreOnlyRecord() -> MatchRecord {
        let stats: [PointStat] = (0..<4).map { i in
            PointStat(setIndex: 0, server: i % 2 == 0 ? .me : .opponent,
                      winner: i % 2 == 0 ? .me : .opponent, outcome: .uncategorized)
        }
        return MatchRecord(
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_001_000),
            setScores: [SetScore(gamesMe: 4, gamesOpponent: 1)],
            stats: stats,
            iWon: true,
            matchFormat: .quick4Games
        )
    }

    private func jsonObject(_ vm: MatchWebViewModel) throws -> [String: Any] {
        let data = try JSONEncoder().encode(vm)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - 1. Shape / required keys

    func test_viewModel_hasRequiredTopLevelKeys() throws {
        let vm = MatchWebViewModel.make(from: makeRecord())
        let obj = try jsonObject(vm)
        for key in ["schemaVersion", "generatedAt", "meta", "perspectives", "points", "setBands", "palette"] {
            XCTAssertNotNil(obj[key], "missing top-level key: \(key)")
        }
        let persp = try XCTUnwrap(obj["perspectives"] as? [String: Any])
        XCTAssertNotNil(persp["me"])
        XCTAssertNotNil(persp["opponent"])
        XCTAssertEqual(obj["schemaVersion"] as? Int, MatchWebViewModel.currentSchemaVersion)
    }

    func test_points_carryCumulativeAndColours() {
        let vm = MatchWebViewModel.make(from: makeRecord())
        XCTAssertEqual(vm.points.count, 6)
        // Running tallies end at the final per-player totals (I won 4, lost 2).
        XCTAssertEqual(vm.points.last?.cumulativeMe, 4)
        XCTAssertEqual(vm.points.last?.cumulativeOpp, 2)
        // Every categorised point carries a colour + symbol for the scatter.
        for p in vm.points where p.outcome != "uncategorized" {
            XCTAssertTrue(p.outcomeColorHex.hasPrefix("#"))
            XCTAssertFalse(p.outcomeSymbol.isEmpty)
        }
        // Set bands cover both sets.
        XCTAssertEqual(Set(vm.setBands.map { $0.setNumber }), [1, 2])
    }

    // MARK: - 2. Both perspectives consistent

    func test_perspectives_areMirrorConsistent() {
        let vm = MatchWebViewModel.make(from: makeRecord())
        let me = vm.perspectives.me
        let opp = vm.perspectives.opponent
        XCTAssertEqual(me.pointsWon + me.pointsLost, me.totalPoints)
        XCTAssertEqual(me.totalPoints, opp.totalPoints)
        // What I won, the opponent lost — and vice versa.
        XCTAssertEqual(me.pointsWon, opp.pointsLost)
        XCTAssertEqual(me.pointsLost, opp.pointsWon)
        // Result flips: I won, so the opponent lost.
        XCTAssertEqual(me.result, "won")
        XCTAssertEqual(opp.result, "lost")
    }

    func test_outcomeCounts_attributedPerPerspective() {
        let vm = MatchWebViewModel.make(from: makeRecord())
        // Me: winners at 0/3/5, one double fault (1), one unforced error (2).
        let me = vm.perspectives.me.outcomeCounts
        XCTAssertEqual(me["winner"], 3)
        XCTAssertEqual(me["doubleFault"], 1)
        XCTAssertEqual(me["unforcedError"], 1)
        XCTAssertEqual(me["forcedError"], 0)
        // Opponent owns the single forced error (point 4, which I won).
        let opp = vm.perspectives.opponent.outcomeCounts
        XCTAssertEqual(opp["forcedError"], 1)
        XCTAssertEqual(opp["winner"], 0)
    }

    // MARK: - 3. Recorder-only HR rule

    func test_hr_isRecorderOnly() throws {
        let vm = MatchWebViewModel.make(from: makeRecord(withHR: true))
        // HR block present (recorder data) and scoped at the top level, not per-perspective.
        XCTAssertNotNil(vm.hr)
        XCTAssertNotNil(vm.steps)
        // PulseCoach insights never attach to the opponent perspective.
        XCTAssertNil(vm.perspectives.opponent.pulseInsights)

        let obj = try jsonObject(vm)
        let persp = try XCTUnwrap(obj["perspectives"] as? [String: Any])
        let opp = try XCTUnwrap(persp["opponent"] as? [String: Any])
        XCTAssertNil(opp["pulseInsights"], "opponent perspective must not carry HR-derived insights")
        // No opponent stat section should reference heart rate.
        let oppJSON = String(decoding: try JSONSerialization.data(withJSONObject: opp), as: UTF8.self)
        XCTAssertFalse(oppJSON.lowercased().contains("heart rate"))
        XCTAssertFalse(oppJSON.lowercased().contains("pulsecoach"))
    }

    func test_noHR_omitsHRBlock() {
        let vm = MatchWebViewModel.make(from: makeRecord(withHR: false))
        XCTAssertNil(vm.hr)
        XCTAssertNil(vm.steps)
        XCTAssertNil(vm.meta.totals)
        XCTAssertNil(vm.perspectives.me.pulseInsights)
    }

    // MARK: - 4. Self-contained HTML

    func test_html_isSelfContained() {
        let html = MatchHTMLExporter.html(for: makeRecord())
        // Carries the embedded data + inline viewer.
        XCTAssertTrue(html.contains("\"schemaVersion\""))
        XCTAssertTrue(html.contains("const DATA ="))
        XCTAssertTrue(html.contains("<style>"))
        XCTAssertTrue(html.contains("<script>"))
        XCTAssertTrue(html.contains("DeuceMate Match"))
        // Embeds known data values so we know the match data made it in.
        XCTAssertTrue(html.contains("Best of 3"))
        XCTAssertTrue(html.contains("\"perspectives\""))

        // No external resource loads. The only permissible "http" is the SVG
        // namespace identifier (not a network fetch); assert every "http"
        // occurrence is exactly that.
        XCTAssertFalse(html.contains("https://"))
        XCTAssertFalse(html.contains("src="))
        XCTAssertFalse(html.contains("<link"))
        XCTAssertFalse(html.lowercased().contains("cdn"))
        XCTAssertFalse(html.contains("@import"))
        let httpCount = occurrences(of: "http://", in: html)
        let nsCount = occurrences(of: "http://www.w3.org/2000/svg", in: html)
        XCTAssertEqual(httpCount, nsCount, "the only http:// reference may be the SVG namespace")
    }

    // MARK: - 5. Score-only match still renders

    func test_scoreOnlyMatch_producesValidSelfContainedHTML() throws {
        let vm = MatchWebViewModel.make(from: makeScoreOnlyRecord())
        // No outcomes → a data note, no HR.
        XCTAssertFalse(vm.perspectives.me.hasOutcomes)
        XCTAssertNil(vm.hr)
        XCTAssertTrue(vm.perspectives.me.sections.contains { $0.title == "Data Note" })

        let html = MatchHTMLExporter.html(for: makeScoreOnlyRecord())
        XCTAssertTrue(html.contains("\"schemaVersion\""))
        XCTAssertTrue(html.contains("const DATA ="))
        XCTAssertFalse(html.contains("https://"))
        XCTAssertFalse(html.contains("src="))
        let httpCount = occurrences(of: "http://", in: html)
        let nsCount = occurrences(of: "http://www.w3.org/2000/svg", in: html)
        XCTAssertEqual(httpCount, nsCount)
    }

    // MARK: - 6. Percentage rows carry a bar fraction + keep their counts

    /// First matching row by label across all of a perspective's sections.
    private func row(_ vm: MatchWebViewModel, _ player: KeyPath<MatchWebViewModel.Perspectives, MatchWebViewModel.PerspectiveVM>, label: String) -> MatchWebViewModel.StatRow? {
        vm.perspectives[keyPath: player].sections
            .flatMap { $0.rows }
            .first { $0.label == label }
    }

    func test_percentageRows_carryFraction_andKeepCounts() throws {
        let vm = MatchWebViewModel.make(from: makeRecord())

        // A percentage row exposes a 0…1 fraction AND still shows the raw counts.
        let firstIn = try XCTUnwrap(row(vm, \.me, label: "1st Serve In"))
        let f = try XCTUnwrap(firstIn.fraction)
        XCTAssertGreaterThanOrEqual(f, 0)
        XCTAssertLessThanOrEqual(f, 1)
        XCTAssertTrue(firstIn.value.contains("("), "value should still carry the count, got: \(firstIn.value)")

        // Break-point conversion is a fraction row too.
        let conv = try XCTUnwrap(row(vm, \.me, label: "Converted (as returner)"))
        XCTAssertNotNil(conv.fraction)
        XCTAssertTrue(conv.value.contains("/"))

        // Plain-count rows have no bar.
        XCTAssertNil(try XCTUnwrap(row(vm, \.me, label: "Total Played")).fraction)
        XCTAssertNil(try XCTUnwrap(row(vm, \.me, label: "Winners")).fraction)
        // W:UE Ratio is a ratio, not a 0…1 percentage — no bar.
        XCTAssertNil(try XCTUnwrap(row(vm, \.me, label: "W:UE Ratio")).fraction)
    }

    func test_fraction_roundTripsThroughJSON() throws {
        let vm = MatchWebViewModel.make(from: makeRecord())
        let obj = try jsonObject(vm)
        let persp = try XCTUnwrap(obj["perspectives"] as? [String: Any])
        let me = try XCTUnwrap(persp["me"] as? [String: Any])
        let sections = try XCTUnwrap(me["sections"] as? [[String: Any]])
        let rows = sections.flatMap { ($0["rows"] as? [[String: Any]]) ?? [] }
        let firstIn = try XCTUnwrap(rows.first { ($0["label"] as? String) == "1st Serve In" })
        XCTAssertNotNil(firstIn["fraction"] as? Double, "fraction must survive JSON encoding")
    }

    // MARK: - script-safety of the embedded JSON

    func test_scriptSafe_neutralisesClosingTags() {
        let escaped = MatchHTMLExporter.scriptSafe("{\"x\":\"</script><!--\"}")
        XCTAssertFalse(escaped.contains("</script>"))
        XCTAssertFalse(escaped.contains("<!--"))
        XCTAssertTrue(escaped.contains("<\\/script>"))
    }

    // MARK: - Helpers

    private func occurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var range = haystack.startIndex..<haystack.endIndex
        while let found = haystack.range(of: needle, range: range) {
            count += 1
            range = found.upperBound..<haystack.endIndex
        }
        return count
    }
}
