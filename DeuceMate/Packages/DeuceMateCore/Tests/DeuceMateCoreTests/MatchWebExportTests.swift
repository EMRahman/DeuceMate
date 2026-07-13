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
        for key in ["schemaVersion", "generatedAt", "meta", "perspectives", "points", "setBands", "palette", "filters", "setLabels"] {
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

    func test_outcomeCountsOpponent_isTheMirrorRow() {
        let vm = MatchWebViewModel.make(from: makeRecord())
        // From my perspective, the "Opp" row owns the single forced error and
        // nothing else — the mirror of the opponent perspective's own counts.
        let meOpp = vm.perspectives.me.outcomeCountsOpponent
        XCTAssertEqual(meOpp["forcedError"], 1)
        XCTAssertEqual(meOpp["winner"], 0)
        XCTAssertEqual(meOpp["unforcedError"], 0)
        XCTAssertEqual(meOpp["doubleFault"], 0)
        // The "Opp" row of one perspective equals the self row of the other.
        XCTAssertEqual(vm.perspectives.me.outcomeCountsOpponent,
                       vm.perspectives.opponent.outcomeCounts)
        XCTAssertEqual(vm.perspectives.opponent.outcomeCountsOpponent,
                       vm.perspectives.me.outcomeCounts)
    }

    func test_endingShotPhases_splitWonAndLostPerPerspective() {
        let vm = MatchWebViewModel.make(from: makeRecord())
        // All four phases occur this match, exposed in rally order.
        let order = ["serve", "return", "servePlusOne", "rally"]
        XCTAssertEqual(vm.perspectives.me.presentEndingPhases, order)
        XCTAssertEqual(vm.perspectives.opponent.presentEndingPhases, order)

        // Me: won on serve(0)/return(3)/S+1(4)/rally(5); lost on serve(1)/rally(2).
        let me = vm.perspectives.me
        XCTAssertEqual(me.endingWonByPhase["serve"], 1)
        XCTAssertEqual(me.endingWonByPhase["return"], 1)
        XCTAssertEqual(me.endingWonByPhase["servePlusOne"], 1)
        XCTAssertEqual(me.endingWonByPhase["rally"], 1)
        XCTAssertEqual(me.endingLostByPhase["serve"], 1)
        XCTAssertEqual(me.endingLostByPhase["rally"], 1)
        XCTAssertEqual(me.endingLostByPhase["return"] ?? 0, 0)

        // Won/lost flip on the opponent perspective.
        let opp = vm.perspectives.opponent
        XCTAssertEqual(opp.endingWonByPhase["serve"], 1)   // opp won the double fault point
        XCTAssertEqual(opp.endingWonByPhase["rally"], 1)
        XCTAssertEqual(opp.endingLostByPhase["serve"], 1)
        XCTAssertEqual(opp.endingLostByPhase["return"], 1)
    }

    func test_scoreOnlyMatch_hasNoEndingPhases() {
        let vm = MatchWebViewModel.make(from: makeScoreOnlyRecord())
        // No ending shots tracked → empty phase list hides the ending-shot pills.
        XCTAssertTrue(vm.perspectives.me.presentEndingPhases.isEmpty)
        XCTAssertTrue(vm.perspectives.me.endingWonByPhase.isEmpty)
        XCTAssertTrue(vm.perspectives.me.endingLostByPhase.isEmpty)
    }

    // MARK: - TV-style Me vs Opp comparison (mirrors MatchDetailView)

    /// The `All`-filter comparison (the whole-match view).
    private func allComparison(_ vm: MatchWebViewModel) -> MatchWebViewModel.Comparison {
        vm.filters.first { $0.key == "all" }!.comparison
    }
    private func cmpSection(_ vm: MatchWebViewModel, _ title: String) -> MatchWebViewModel.CmpSection? {
        allComparison(vm).sections.first { $0.title == title }
    }
    private func cmpRow(_ vm: MatchWebViewModel, section: String, label: String) -> MatchWebViewModel.CmpRow? {
        cmpSection(vm, section)?.rows.first { $0.label == label }
    }

    func test_comparison_sectionsAndGating_fullMatch() throws {
        let vm = MatchWebViewModel.make(from: makeRecord())
        XCTAssertEqual(vm.schemaVersion, 6)
        XCTAssertTrue(allComparison(vm).hasAnyOutcomeData)
        let titles = allComparison(vm).sections.map { $0.title }
        // Outcome Breakdown leads; Serve/Return present (every point categorised).
        XCTAssertEqual(titles.first, "Outcome Breakdown")
        XCTAssertTrue(titles.contains("Serve"))
        XCTAssertTrue(titles.contains("Return"))
        XCTAssertTrue(titles.contains("Break Points"))
        // No uncategorised points → no footer note, no placeholder.
        XCTAssertNil(allComparison(vm).note)
        XCTAssertNil(cmpSection(vm, "Outcome Breakdown")?.placeholder)
    }

    func test_comparison_countRow_mirrorsAttribution() throws {
        let vm = MatchWebViewModel.make(from: makeRecord())
        let winners = try XCTUnwrap(cmpRow(vm, section: "Outcome Breakdown", label: "Winners"))
        XCTAssertEqual(winners.kind, .count)
        XCTAssertEqual(winners.meValue, "3")    // recorder struck 3 winners
        XCTAssertEqual(winners.oppValue, "0")   // opponent none
        XCTAssertEqual(winners.meFraction, 1.0, accuracy: 0.0001)   // scaled to max(3, 0)
        XCTAssertEqual(winners.oppFraction, 0.0, accuracy: 0.0001)
        XCTAssertNil(winners.meBarLabel)        // count rows carry no inner bar label
    }

    func test_comparison_ratioRow_hasNoBars() throws {
        let vm = MatchWebViewModel.make(from: makeRecord())
        let wue = try XCTUnwrap(cmpRow(vm, section: "Outcome Breakdown", label: "Win : Unforced Err"))
        XCTAssertEqual(wue.kind, .ratio)
        XCTAssertEqual(wue.subtitle, "aim for > 1.0")
        XCTAssertEqual(wue.meValue, "3.0 : 1")  // 3 winners : 1 unforced error
        XCTAssertEqual(wue.oppValue, "—")       // opponent had no winners/UEs
    }

    func test_comparison_percentRow_carriesValueAndCount() throws {
        let vm = MatchWebViewModel.make(from: makeRecord())
        let row = try XCTUnwrap(cmpRow(vm, section: "Serve", label: "1st Serve In"))
        XCTAssertEqual(row.kind, .percent)
        XCTAssertTrue(row.meValue.hasSuffix("%"))
        XCTAssertTrue(try XCTUnwrap(row.meBarLabel).contains("/"))  // inner raw count
        XCTAssertGreaterThanOrEqual(row.meFraction, 0)
        XCTAssertLessThanOrEqual(row.meFraction, 1)
    }

    func test_comparison_scoreOnly_placeholderAndNote() throws {
        let vm = MatchWebViewModel.make(from: makeScoreOnlyRecord())
        XCTAssertFalse(allComparison(vm).hasAnyOutcomeData)
        let breakdown = try XCTUnwrap(cmpSection(vm, "Outcome Breakdown"))
        XCTAssertTrue(breakdown.rows.isEmpty)
        XCTAssertEqual(breakdown.placeholder, "Outcome tracking not collected for this match.")
        // Serve/Return hidden unless every point is categorised; Break Points stays.
        XCTAssertNil(cmpSection(vm, "Serve"))
        XCTAssertNil(cmpSection(vm, "Return"))
        XCTAssertNotNil(cmpSection(vm, "Break Points"))
        XCTAssertEqual(allComparison(vm).note, "4 uncategorized point(s) excluded from outcome stats.")
    }

    func test_comparison_roundTripsThroughJSON() throws {
        let vm = MatchWebViewModel.make(from: makeRecord())
        let obj = try jsonObject(vm)
        let filters = try XCTUnwrap(obj["filters"] as? [[String: Any]])
        let all = try XCTUnwrap(filters.first { ($0["key"] as? String) == "all" })
        let cmp = try XCTUnwrap(all["comparison"] as? [String: Any])
        let sections = try XCTUnwrap(cmp["sections"] as? [[String: Any]])
        XCTAssertEqual(sections.first?["title"] as? String, "Outcome Breakdown")
        let rows = try XCTUnwrap(sections.first?["rows"] as? [[String: Any]])
        XCTAssertTrue(rows.contains { ($0["kind"] as? String) == "ratio" })
        XCTAssertTrue(rows.contains { ($0["kind"] as? String) == "count" })
    }

    // MARK: - Set filters / Stats-Points tabs / point display

    private func filter(_ vm: MatchWebViewModel, _ key: String) -> MatchWebViewModel.FilterVM? {
        vm.filters.first { $0.key == key }
    }

    func test_filters_allPlusPerSet() {
        let vm = MatchWebViewModel.make(from: makeRecord())   // two sets
        XCTAssertEqual(vm.filters.map { $0.key }, ["all", "set-0", "set-1"])
        XCTAssertEqual(vm.filters.map { $0.label }, ["All", "Set 1", "Set 2"])
        XCTAssertEqual(vm.setLabels, ["Set 1", "Set 2"])
    }

    func test_filter_pointsWon_perSet() throws {
        let vm = MatchWebViewModel.make(from: makeRecord())
        let all = try XCTUnwrap(filter(vm, "all")).pointsWon
        XCTAssertEqual(all.total, 6)
        XCTAssertEqual(all.meWon, 4)
        XCTAssertEqual(all.oppWon, 2)
        // Set 1 (index 0): points 0/3/4 won, 1/2 lost.
        let s0 = try XCTUnwrap(filter(vm, "set-0")).pointsWon
        XCTAssertEqual(s0.total, 5)
        XCTAssertEqual(s0.meWon, 3)
        XCTAssertEqual(s0.mePct, 60)
        // Set 2 (index 1): single point, won.
        let s1 = try XCTUnwrap(filter(vm, "set-1")).pointsWon
        XCTAssertEqual(s1.total, 1)
        XCTAssertEqual(s1.meWon, 1)
        XCTAssertEqual(s1.mePct, 100)
    }

    func test_filter_comparison_recomputesPerSet() throws {
        let vm = MatchWebViewModel.make(from: makeRecord())
        func winners(_ key: String) throws -> String {
            let f = try XCTUnwrap(filter(vm, key))
            let row = try XCTUnwrap(f.comparison.sections.first { $0.title == "Outcome Breakdown" }?
                .rows.first { $0.label == "Winners" })
            return row.meValue
        }
        XCTAssertEqual(try winners("all"), "3")    // winners at points 0, 3, 5
        XCTAssertEqual(try winners("set-0"), "2")  // points 0, 3 in set 1
        XCTAssertEqual(try winners("set-1"), "1")  // point 5 in set 2
    }

    func test_filter_durationRows() throws {
        let vm = MatchWebViewModel.make(from: makeRecord())
        let all = try XCTUnwrap(filter(vm, "all")).durationRows
        XCTAssertTrue(all.contains { $0.label == "Set 1 Duration" && $0.value == "40 min" })
        XCTAssertTrue(all.contains { $0.label == "Set 2 Duration" && $0.value == "20 min" })
        XCTAssertTrue(all.contains { $0.label == "Steps" })
        XCTAssertTrue(all.contains { $0.label == "Calories" })
        // A single-set filter collapses to one "Duration" row.
        let s0 = try XCTUnwrap(filter(vm, "set-0")).durationRows
        XCTAssertTrue(s0.contains { $0.label == "Duration" && $0.value == "40 min" })
        XCTAssertFalse(s0.contains { $0.label == "Set 1 Duration" })
    }

    func test_singleSetMatch_hasNoSetFilters() {
        let vm = MatchWebViewModel.make(from: makeScoreOnlyRecord())   // one set
        // All + the single set → 2 filters, so the viewer hides the picker (> 2).
        XCTAssertEqual(vm.filters.map { $0.key }, ["all", "set-0"])
        XCTAssertEqual(vm.setLabels, ["Set 1"])
    }

    func test_pointDisplayFields_mirrorPointRow() {
        let p = MatchWebViewModel.make(from: makeRecord()).points
        // Point 0: my winner on serve at 0–0.
        XCTAssertEqual(p[0].chipText, "W")
        XCTAssertEqual(p[0].chipColorHex, WebExportColors.meLineHex)
        XCTAssertEqual(p[0].outcomeText, "Winner — Me")
        XCTAssertEqual(p[0].pointScoreLabel, "0–0")
        XCTAssertEqual(p[0].gamesScoreLabel, "0–0")   // first game of the set
        // Point 1: my double fault.
        XCTAssertEqual(p[1].chipText, "DF")
        XCTAssertEqual(p[1].outcomeText, "Double Fault — Me")
        // Point 2: I made the unforced error (opponent won) → my colour.
        XCTAssertEqual(p[2].chipText, "UE")
        XCTAssertEqual(p[2].outcomeText, "Unforced Err — Me")
        XCTAssertEqual(p[2].chipColorHex, WebExportColors.meLineHex)
        // Point 3's 0–0 reset means point 2 (opponent's UE won) closed out the
        // first game, so opponent leads 0–1 games heading into point 3.
        XCTAssertEqual(p[3].gamesScoreLabel, "0–1")
        // Point 4: deuce game state.
        XCTAssertEqual(p[4].pointScoreLabel, "Deuce")
        // Point 5 starts set 2 fresh — 0–0 games regardless of set 1's outcome.
        XCTAssertEqual(p[5].gamesScoreLabel, "0–0")
    }

    // MARK: - AI Coach (mirrors AICoachSheet)

    func test_aiCoach_builtFromInjectedPrompts() throws {
        let vm = MatchWebViewModel.make(from: makeRecord(),
                                        aiPromptMe: "MY PROMPT", aiPromptOpponent: "OPP PROMPT")
        let ai = try XCTUnwrap(vm.aiCoach)
        XCTAssertEqual(ai.title, "Get AI Coaching Tips")
        XCTAssertEqual(ai.mePrompt, "MY PROMPT")
        XCTAssertEqual(ai.opponentPrompt, "OPP PROMPT")
        // Same apps, same order as the iOS launcher.
        XCTAssertEqual(ai.apps.map { $0.name },
                       ["ChatGPT", "Claude", "Gemini", "Perplexity", "Copilot", "Poe", "Grok"])
        // Only Perplexity pre-fills via ?q= (mirrors iOS); every launch URL is https.
        XCTAssertEqual(ai.apps.filter { $0.supportsPromptParam }.map { $0.name }, ["Perplexity"])
        for app in ai.apps { XCTAssertTrue(app.url.hasPrefix("https://"), "non-https launch URL: \(app.url)") }
    }

    func test_aiCoach_absentWithoutPrompt() {
        XCTAssertNil(MatchWebViewModel.make(from: makeRecord()).aiCoach)
        // An empty prompt is treated as absent.
        XCTAssertNil(MatchWebViewModel.make(from: makeRecord(), aiPromptMe: "").aiCoach)
    }

    func test_aiCoach_meOnlyWhenNoOpponentPrompt() throws {
        let vm = MatchWebViewModel.make(from: makeRecord(), aiPromptMe: "MY PROMPT")
        let ai = try XCTUnwrap(vm.aiCoach)
        XCTAssertNil(ai.opponentPrompt)   // viewer hides the My/Opponent toggle
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
        // The prompt-free page (no AI Coach) — strictly zero external URLs.
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
        // occurrence is exactly that. Without AI prompts there are no links at all.
        XCTAssertFalse(html.contains("https://"))
        XCTAssertFalse(html.contains("src="))
        XCTAssertFalse(html.contains("<link"))
        XCTAssertFalse(html.lowercased().contains("cdn"))
        XCTAssertFalse(html.contains("@import"))
        let httpCount = occurrences(of: "http://", in: html)
        let nsCount = occurrences(of: "http://www.w3.org/2000/svg", in: html)
        XCTAssertEqual(httpCount, nsCount, "the only http:// reference may be the SVG namespace")
    }

    /// The real (shipped) page embeds AI coaching prompts, which add opt-in
    /// AI-app launch links. The page must STILL load zero external resources on
    /// open — every external URL is a user-clicked `<a>` to a known AI host (the
    /// links live JSON-slash-escaped in the embedded data, e.g. `https:\/\/…`),
    /// never a `src=`/`<link>`/`@import`/CDN resource fetched automatically.
    func test_html_withAICoach_addsOnlyOptInLinks() {
        let html = MatchHTMLExporter.html(for: makeRecord(),
                                          aiPromptMe: "ME PROMPT", aiPromptOpponent: "OPP PROMPT")
        XCTAssertTrue(html.contains("\"aiCoach\""))
        XCTAssertTrue(html.contains("Get AI Coaching Tips"))
        // Zero auto-loaded resources.
        XCTAssertFalse(html.contains("src="))
        XCTAssertFalse(html.contains("<link"))
        XCTAssertFalse(html.lowercased().contains("cdn"))
        XCTAssertFalse(html.contains("@import"))
        let httpCount = occurrences(of: "http://", in: html)
        let nsCount = occurrences(of: "http://www.w3.org/2000/svg", in: html)
        XCTAssertEqual(httpCount, nsCount, "the only http:// reference may be the SVG namespace")
        // Un-escape JSON slashes, then assert every https:// is a known AI host.
        let normalized = html.replacingOccurrences(of: "\\/", with: "/")
        let allowedHosts = ["chatgpt.com", "claude.ai", "gemini.google.com",
                            "www.perplexity.ai", "copilot.microsoft.com", "poe.com", "grok.com"]
        var range = normalized.startIndex..<normalized.endIndex
        var sawLink = false
        while let r = normalized.range(of: "https://", range: range) {
            sawLink = true
            let tail = normalized[r.upperBound...].prefix(40)
            XCTAssertTrue(allowedHosts.contains { tail.hasPrefix($0) }, "unexpected https:// target: \(tail)")
            range = r.upperBound..<normalized.endIndex
        }
        XCTAssertTrue(sawLink, "AI app launch links should be present")
    }

    /// Progressive enhancement: `#root` carries a real static summary so no-JS
    /// previews (iOS Quick Look, many local-file opens) show the match, not a
    /// blank page. The viewer JS clears `#root` and rebuilds when it runs.
    func test_html_hasStaticFallback_forNoJSPreviews() {
        let html = MatchHTMLExporter.html(for: makeRecord())
        // #root is no longer empty.
        XCTAssertFalse(html.contains("<div id=\"root\"></div>"), "#root must carry a static fallback")
        XCTAssertTrue(html.contains("Open in a web browser"), "fallback should explain how to get the interactive view")
        // Real match content rendered statically (styled with the viewer's CSS).
        XCTAssertTrue(html.contains("class=\"score\""))
        XCTAssertTrue(html.contains("Points Won"))
        XCTAssertTrue(html.contains("Outcome Breakdown"))
        // The fallback adds no external resources.
        XCTAssertFalse(html.contains("src="))
        XCTAssertFalse(html.contains("https://"))
        XCTAssertFalse(html.contains("<link"))
    }

    func test_staticFallback_scoreOnly_showsHeaderAndNote() {
        let html = MatchHTMLExporter.html(for: makeScoreOnlyRecord())
        XCTAssertTrue(html.contains("DeuceMate Match"))
        // Score-only → the breakdown placeholder appears statically too.
        XCTAssertTrue(html.contains("Outcome tracking not collected for this match."))
    }

    /// The static fallback renders the Me-vs-Opp stats as the same TV-style
    /// split bars the iOS app and interactive viewer use — not plain tables —
    /// reusing the shared `.pw-*` / `.cmp-*` CSS classes (no external resources).
    func test_staticFallback_rendersTVStyleComparisonBars() {
        let html = MatchHTMLExporter.html(for: makeRecord())
        // Points-won header bar (mirrors the viewer's pointsWonBar).
        XCTAssertTrue(html.contains("class=\"pw-head\""))
        XCTAssertTrue(html.contains("class=\"pw-bar\""))
        XCTAssertTrue(html.contains("Points Won"))
        XCTAssertTrue(html.contains("total"))
        // Split-bar comparison rows with Me/Opp caps + inner count labels.
        XCTAssertTrue(html.contains("class=\"cmp-head\""))
        XCTAssertTrue(html.contains("class=\"cap\""))
        XCTAssertTrue(html.contains("class=\"cmp-row\""))
        XCTAssertTrue(html.contains("class=\"splitbar\""))
        XCTAssertTrue(html.contains("class=\"cmp-half\""))
        XCTAssertTrue(html.contains("class=\"cmp-blab\""), "percent rows carry an inner count label")
        XCTAssertTrue(html.contains("class=\"cmp-ratio\""), "the W:UE ratio row renders as a bare ratio")
        // The old plain Me/Opp table header is gone.
        XCTAssertFalse(html.contains("(Me / Opp)"))
        // Still self-contained — the bars add no external resources.
        XCTAssertFalse(html.contains("https://"))
        XCTAssertFalse(html.contains("src="))
        XCTAssertFalse(html.contains("<link"))
    }

    /// With more than one set the static page stacks a per-set breakdown (it
    /// can't toggle like the viewer): the whole match plus one labelled scope
    /// per set, each with its own recomputed points-won bar.
    func test_staticFallback_rendersPerSetBreakdown() {
        let html = MatchHTMLExporter.html(for: makeRecord())   // two sets
        XCTAssertTrue(html.contains("Match Statistics"))
        // Labelled scope dividers: All + Set 1 + Set 2.
        XCTAssertTrue(html.contains(">All</div>"))
        XCTAssertTrue(html.contains(">Set 1</div>"))
        XCTAssertTrue(html.contains(">Set 2</div>"))
        // One points-won bar per scope (All, Set 1, Set 2), each recomputed:
        // All = 6 points, Set 1 = 5, Set 2 = 1.
        XCTAssertEqual(occurrences(of: "class=\"pw-bar\"", in: html), 3)
        XCTAssertTrue(html.contains("6 total"))
        XCTAssertTrue(html.contains("5 total"))
        XCTAssertTrue(html.contains("1 total"))
    }

    /// A single-set match shows just the whole-match scope — no redundant
    /// per-set duplicate, and no scope dividers (mirrors the viewer hiding its
    /// set picker at ≤ 2 filters).
    func test_staticFallback_singleSet_omitsScopeBreakdown() {
        let html = MatchHTMLExporter.html(for: makeScoreOnlyRecord())   // one set
        // No labelled scope divider (its inline style is the marker).
        XCTAssertFalse(html.contains("font-size:16px;font-weight:700"))
        // Exactly one points-won bar (the whole match).
        XCTAssertEqual(occurrences(of: "class=\"pw-bar\"", in: html), 1)
        // The uncategorised footer note now renders statically too.
        XCTAssertTrue(html.contains("uncategorized point(s) excluded"))
    }

    /// The no-JS fallback renders the momentum chart once per preset selection —
    /// Points Won/Lost (outcome scatter) and Ending Shots All Won/Lost (shot
    /// scatter) — each with its scatter overlay + pills, mirroring the interactive
    /// quick-selects. The `=` attribute forms only occur in the static SVG (the
    /// viewer JS uses object-key syntax), proving the static chart is present.
    func test_staticFallback_rendersFourScatterMomentumCharts() {
        let html = MatchHTMLExporter.html(for: makeRecord())   // 2 sets, 6 points, mixed outcomes
        // Four titled momentum charts.
        XCTAssertTrue(html.contains("Points Momentum — Points Won"))
        XCTAssertTrue(html.contains("Points Momentum — Points Lost"))
        XCTAssertTrue(html.contains("Points Momentum — Ending Shots: All Won"))
        XCTAssertTrue(html.contains("Points Momentum — Ending Shots: All Lost"))
        XCTAssertEqual(occurrences(of: "<svg viewBox=\"0 0 920 380\"", in: html), 4, "four charts")
        // Each chart has 2 set bands → 8 across the four.
        XCTAssertEqual(occurrences(of: "fill-opacity=", in: html), 8)
        // The me/opp step lines + gridlines + legend appear on each.
        XCTAssertTrue(html.contains("stroke=\"\(WebExportColors.meLineHex)\""))
        XCTAssertTrue(html.contains("stroke=\"\(WebExportColors.opponentLineHex)\""))
        XCTAssertTrue(html.contains("class=\"gridline\""))
        XCTAssertTrue(html.contains("class=\"legendline\""))
        // Pills are rendered (colour + label + count) — coloured scatter chips.
        XCTAssertTrue(html.contains("class=\"schip\""))
        // Scatter marks are drawn (e.g. winner circles + double-fault squares).
        XCTAssertTrue(html.contains("<circle"))
        // Still self-contained — the SVG adds no external resources.
        XCTAssertFalse(html.contains("https://"))
        XCTAssertFalse(html.contains("src="))
        XCTAssertFalse(html.contains("<link"))
    }

    func test_staticScatter_pointsWonAndLost_markCounts() {
        // makeRecord: I won points 0(W),3(W),4(FE by opp),5(W); lost 1(DF mine),2(UE mine).
        // Points Won chart → marks for my 3 winners + opp's 1 forced error = 4.
        let won = MatchHTMLExporter.staticChartSVG(MatchWebViewModel.make(from: makeRecord()), scatter: .pointsWon)
        XCTAssertEqual(occurrences(of: "<circle", in: won), 3, "3 winner circles")     // winner = circle
        XCTAssertEqual(occurrences(of: "<polygon", in: won), 1, "1 forced-error triangle") // FE = triangle
        // Points Lost chart → my double fault (square) + my unforced error (cross = 2 lines).
        let lost = MatchHTMLExporter.staticChartSVG(MatchWebViewModel.make(from: makeRecord()), scatter: .pointsLost)
        XCTAssertEqual(occurrences(of: "<rect", in: lost), 1 + 2, "1 DF square + 2 set bands")  // DF = rect square
        XCTAssertTrue(lost.contains("<line"))   // UE = cross (line strokes)
    }

    func test_staticScatter_endingShots_onlyWonOrLostSide() {
        let vm = MatchWebViewModel.make(from: makeRecord())
        // All Won: ending-shot marks only on points I won (4 such points carry a shot).
        let won = MatchHTMLExporter.staticChartSVG(vm, scatter: .allWon)
        // All Lost: ending-shot marks only on points I lost (2 such points).
        let lost = MatchHTMLExporter.staticChartSVG(vm, scatter: .allLost)
        // Count scatter glyphs (pentagon/asterisk/plus/triangle/etc.) beyond the
        // 2 step <path>s and the gridlines — won has more marks than lost here.
        func glyphs(_ s: String) -> Int { occurrences(of: "<polygon", in: s) + occurrences(of: "<line ", in: s) }
        XCTAssertGreaterThan(glyphs(won), glyphs(lost))
    }

    func test_staticPills_outcomeAndPhaseCounts() {
        let html = MatchHTMLExporter.html(for: makeRecord())
        // Outcome pills use the short labels; phase pills use the shot labels.
        XCTAssertTrue(html.contains(">W 3<") || html.contains("W 3</span>"), "Points Won pill: W 3")
        // Pills carry a coloured dot + label + count inside a schip.
        XCTAssertGreaterThanOrEqual(occurrences(of: "class=\"schip\"", in: html), 4 * 4 - 4) // ≥ outcome+phase pills across charts
    }

    /// Each static momentum chart leads its pill row with the preset's own
    /// total (mirrors the interactive quick-select chips, which the static
    /// page can't render as toggles) — e.g. "Points Won 4" ahead of the W/UE/
    /// FE/DF breakdown pills.
    func test_staticPills_presetTotalLeadsEachChart() {
        let html = MatchHTMLExporter.html(for: makeRecord())
        // Points Won: my 3 winners + opp's 1 forced error = 4. Points Lost: my
        // DF + my UE = 2. Ending shots: 4 points I won carry a shot, 2 lost.
        XCTAssertTrue(html.contains(">Points Won 4<"), "Points Won preset total pill")
        XCTAssertTrue(html.contains(">Points Lost 2<"), "Points Lost preset total pill")
        XCTAssertTrue(html.contains(">All Won 4<"), "All Won preset total pill")
        XCTAssertTrue(html.contains(">All Lost 2<"), "All Lost preset total pill")
    }

    func test_staticChartSVG_yAxisFromCumulative() {
        let svg = MatchHTMLExporter.staticChartSVG(MatchWebViewModel.make(from: makeRecord()))
        XCTAssertTrue(svg.hasPrefix("<svg viewBox=\"0 0 920 380\""))
        // I won 4, lost 2 → yMax = 4; gridline labels at 0 / 50% / 100% = 0, 2, 4.
        XCTAssertTrue(svg.contains(">4</text>"), "top Y label = cumulative max (4)")
        XCTAssertTrue(svg.contains(">2</text>"))
        XCTAssertTrue(svg.contains(">0</text>"))
        // Exactly two momentum step paths.
        XCTAssertEqual(occurrences(of: "<path ", in: svg), 2)
    }

    func test_staticChartSVG_emptyWhenNoPoints() {
        let record = MatchRecord(
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            setScores: [SetScore(gamesMe: 6, gamesOpponent: 4)],
            stats: [], iWon: true, matchFormat: .standard)
        XCTAssertEqual(MatchWebViewModel.make(from: record).points.count, 0)
        XCTAssertTrue(MatchHTMLExporter.staticChartSVG(MatchWebViewModel.make(from: record)).isEmpty)
        // The page still renders the header (just no chart card).
        let html = MatchHTMLExporter.html(for: record)
        XCTAssertFalse(html.contains("<svg viewBox=\"0 0 920 380\""))
        XCTAssertTrue(html.contains("DeuceMate Match"))
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
