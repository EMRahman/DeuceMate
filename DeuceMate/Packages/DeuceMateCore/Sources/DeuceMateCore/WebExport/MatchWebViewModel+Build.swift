// MatchWebViewModel+Build.swift — the pure derivation helpers behind
// `MatchWebViewModel.make`. Mirrors the section structure and per-perspective
// logic of `MatchExporter` (the plain-text exporter) so the HTML and text
// exports stay in lock-step, but emits structured rows instead of padded text.
import Foundation

extension MatchWebViewModel {

    // MARK: - Perspective

    static func perspective(
        record: MatchRecord,
        focal: Player,
        full: MatchStatsSummary,
        categorized: MatchStatsSummary,
        hasStats: Bool,
        hasOutcomes: Bool,
        mixed: Bool,
        categorizedCount: Int,
        totalCount: Int
    ) -> PerspectiveVM {
        var sections: [StatSection] = []

        if hasStats {
            sections.append(StatSection(
                title: "Points",
                rows: [
                    StatRow(label: "Total Played", value: "\(full.totalPoints)", hint: nil),
                    StatRow(label: "Won", value: countAndPct(full.pointsWon, full.totalPoints), hint: nil,
                            fraction: frac(full.pointsWon, full.totalPoints)),
                    StatRow(label: "Lost", value: countAndPct(full.lostPoints, full.totalPoints), hint: nil,
                            fraction: frac(full.lostPoints, full.totalPoints))
                ],
                note: nil, bullets: nil
            ))
        }

        if hasOutcomes {
            if mixed {
                sections.append(StatSection(
                    title: "Data Note",
                    rows: [],
                    note: "Outcome tracking was off for \(totalCount - categorizedCount) of \(totalCount) points "
                        + "(toggled mid-match). The categorised sections below are based on the "
                        + "\(categorizedCount) categorised points only.",
                    bullets: nil
                ))
            }
            sections.append(serveSection(categorized))
            sections.append(returnSection(categorized))
            sections.append(breakPointSection(categorized))
            sections.append(errorAnalysis(categorized, focal: focal))
            sections.append(opponentErrors(categorized, focal: focal))
            if !categorized.recCoachInsights.isEmpty {
                sections.append(StatSection(title: "Coaching Insights", rows: [],
                                            note: nil, bullets: categorized.recCoachInsights))
            }
            if !categorized.rallyDepth.isEmpty {
                sections.append(rallyDepthSection(categorized))
            }
            if categorized.bigPointTotal > 0 && categorized.normalPointTotal > 0 {
                sections.append(pressureSection(categorized))
            }
            if !categorized.scoreStates.isEmpty {
                sections.append(scoreStatesSection(categorized))
            }
        } else {
            sections.append(StatSection(
                title: "Data Note",
                rows: [],
                note: hasStats
                    ? "Some or all points were recorded without outcome tracking — only score-level data is available."
                    : "Point outcome tracking was not enabled for this match — only score-level data is available.",
                bullets: nil
            ))
        }

        // PulseCoach (HR-derived) insights are recorder-only.
        let pulse: [String]? = (focal == .me && !full.autoInsights.isEmpty) ? full.autoInsights : nil

        // Per-outcome counts attributed to this perspective's player. The `my…`
        // fields are already focal-attributed (winner = focal struck it; UE/FE =
        // focal erred; DF = focal served it), matching PointsGraphView's pills.
        let outcomeCounts: [String: Int] = [
            PointOutcome.winner.rawValue:        categorized.myWinners,
            PointOutcome.unforcedError.rawValue: categorized.myUnforcedErrors,
            PointOutcome.forcedError.rawValue:   categorized.myForcedErrors,
            PointOutcome.doubleFault.rawValue:   categorized.myDoubleFaults
        ]
        // The mirror set for the *other* player — drives the "Opp" outcome pills.
        let outcomeCountsOpponent: [String: Int] = [
            PointOutcome.winner.rawValue:        categorized.opponentWinners,
            PointOutcome.unforcedError.rawValue: categorized.opponentUnforcedErrors,
            PointOutcome.forcedError.rawValue:   categorized.opponentForcedErrors,
            PointOutcome.doubleFault.rawValue:   categorized.opponentDoubleFaults
        ]

        // Ending-shot phases split into points the focal player won vs. lost.
        // Computed over *all* stats (an ending shot can sit on an uncategorised
        // point), keyed/ordered by EndingShot — mirrors PointsGraphData.
        var endingWonByPhase: [String: Int] = [:]
        var endingLostByPhase: [String: Int] = [:]
        for stat in record.stats {
            guard let es = stat.endingShot else { continue }
            if stat.winner == focal { endingWonByPhase[es.rawValue, default: 0] += 1 }
            else                    { endingLostByPhase[es.rawValue, default: 0] += 1 }
        }
        let presentEndingPhases = EndingShot.allCases
            .filter { (endingWonByPhase[$0.rawValue] ?? 0) + (endingLostByPhase[$0.rawValue] ?? 0) > 0 }
            .map { $0.rawValue }

        return PerspectiveVM(
            result: result(record: record, focal: focal),
            scoreDisplay: scoreString(record: record, focal: focal) ?? "—",
            totalPoints: full.totalPoints,
            pointsWon: full.pointsWon,
            pointsLost: full.lostPoints,
            hasOutcomes: hasOutcomes,
            sections: sections,
            outcomeCounts: outcomeCounts,
            outcomeCountsOpponent: outcomeCountsOpponent,
            endingWonByPhase: endingWonByPhase,
            endingLostByPhase: endingLostByPhase,
            presentEndingPhases: presentEndingPhases,
            pulseInsights: pulse
        )
    }

    // MARK: - Section builders (structured analogues of MatchExporter's)

    private static func serveSection(_ s: MatchStatsSummary) -> StatSection {
        let dfNote: String
        if s.secondServeTotal > 0 {
            let p = Int((Double(s.doubleFaults) / Double(s.secondServeTotal)) * 100)
            dfNote = "\(s.doubleFaults) (\(p)% of 2nd serves)"
        } else {
            dfNote = "—"
        }
        let servicePointsWon = s.firstServeWins + s.secondServeWins
        return StatSection(title: "Serve", rows: [
            StatRow(label: "Service Points Win", value: MatchStatsSummary.pct(num: servicePointsWon, den: s.firstServeTotal), hint: nil,
                    fraction: frac(servicePointsWon, s.firstServeTotal)),
            StatRow(label: "1st Serve In", value: MatchStatsSummary.pct(num: s.firstServeIn, den: s.firstServeTotal), hint: nil,
                    fraction: frac(s.firstServeIn, s.firstServeTotal)),
            StatRow(label: "1st Serve Win", value: MatchStatsSummary.pct(num: s.firstServeWins, den: s.firstServeIn), hint: nil,
                    fraction: frac(s.firstServeWins, s.firstServeIn)),
            StatRow(label: "2nd Serve In", value: MatchStatsSummary.pct(num: s.secondServeIn, den: s.secondServeTotal), hint: nil,
                    fraction: frac(s.secondServeIn, s.secondServeTotal)),
            StatRow(label: "2nd Serve Win", value: MatchStatsSummary.pct(num: s.secondServeWins, den: s.secondServeIn), hint: nil,
                    fraction: frac(s.secondServeWins, s.secondServeIn)),
            // Plain text, not a bar: dfNote ("12 (100% of 2nd serves)") is too
            // long for the fixed-width statbar, and a fuller bar would wrongly
            // read as "better".
            StatRow(label: "Double Faults", value: dfNote, hint: nil)
        ], note: nil, bullets: nil)
    }

    private static func returnSection(_ s: MatchStatsSummary) -> StatSection {
        StatSection(title: "Return", rows: [
            StatRow(label: "Win vs. 1st Serve", value: MatchStatsSummary.pct(num: s.returnWinsOnFirst, den: s.returnOppsOnFirst), hint: nil,
                    fraction: frac(s.returnWinsOnFirst, s.returnOppsOnFirst)),
            StatRow(label: "Win vs. 2nd Serve", value: MatchStatsSummary.pct(num: s.returnWinsOnSecond, den: s.returnOppsOnSecond), hint: nil,
                    fraction: frac(s.returnWinsOnSecond, s.returnOppsOnSecond))
        ], note: nil, bullets: nil)
    }

    private static func breakPointSection(_ s: MatchStatsSummary) -> StatSection {
        StatSection(title: "Break Points", rows: [
            StatRow(label: "Converted (as returner)", value: fractionAndPct(s.breakPointWins, s.breakPointOpps), hint: nil,
                    fraction: frac(s.breakPointWins, s.breakPointOpps)),
            StatRow(label: "Saved (as server)", value: fractionAndPct(s.breakPointsFaced - s.breakPointsLost, s.breakPointsFaced), hint: nil,
                    fraction: frac(s.breakPointsFaced - s.breakPointsLost, s.breakPointsFaced))
        ], note: nil, bullets: nil)
    }

    private static func errorAnalysis(_ s: MatchStatsSummary, focal: Player) -> StatSection {
        let title = focal == .me ? "Error Analysis (My Points Lost)" : "Error Analysis (Points Lost)"
        return StatSection(title: title, rows: [
            StatRow(label: "Winners", value: "\(s.myWinners)", hint: nil),
            StatRow(label: "Unforced Errors", value: "\(s.myUnforcedErrors)", hint: nil),
            StatRow(label: "Forced Errors", value: "\(s.myForcedErrors)", hint: nil),
            StatRow(label: "Double Faults", value: "\(s.myDoubleFaults)", hint: nil),
            StatRow(label: "Self-Inflicted Losses", value: s.ownErrorsPct, hint: "own errors / points lost",
                    fraction: frac(s.myDoubleFaults + s.myUnforcedErrors, s.lostPoints)),
            StatRow(label: "W:UE Ratio", value: s.wueRatio, hint: "aim for > 1.0"),
            StatRow(label: "Aggression Index", value: s.aggressionIndex, hint: "winners / (winners + UE)",
                    fraction: frac(s.myWinners, s.myWinners + s.myUnforcedErrors))
        ], note: nil, bullets: nil)
    }

    private static func opponentErrors(_ s: MatchStatsSummary, focal: Player) -> StatSection {
        let title = focal == .me ? "Opponent Errors (Points I Won)" : "Opponent Errors (Points Won)"
        return StatSection(title: title, rows: [
            StatRow(label: "Unforced Errors", value: "\(s.opponentUnforcedErrors)", hint: nil),
            StatRow(label: "Forced Errors", value: "\(s.opponentForcedErrors)", hint: nil),
            StatRow(label: "Double Faults", value: "\(s.opponentDoubleFaults)", hint: nil),
            StatRow(label: "Winners", value: "\(s.opponentWinners)", hint: nil)
        ], note: nil, bullets: nil)
    }

    private static func rallyDepthSection(_ s: MatchStatsSummary) -> StatSection {
        let rows = s.rallyDepth.map {
            StatRow(label: rallyDepthLabel($0.shot),
                    value: "Win " + MatchStatsSummary.pct(num: $0.wins, den: $0.total), hint: nil,
                    fraction: frac($0.wins, $0.total))
        }
        return StatSection(title: "Rally Depth", rows: rows, note: nil, bullets: nil)
    }

    private static func pressureSection(_ s: MatchStatsSummary) -> StatSection {
        StatSection(title: "Pressure vs. Normal Points", rows: [
            StatRow(label: "Big Points (BP / Deuce / TB)", value: MatchStatsSummary.pct(num: s.bigPointWins, den: s.bigPointTotal), hint: nil,
                    fraction: frac(s.bigPointWins, s.bigPointTotal)),
            StatRow(label: "Normal Points", value: MatchStatsSummary.pct(num: s.normalPointWins, den: s.normalPointTotal), hint: nil,
                    fraction: frac(s.normalPointWins, s.normalPointTotal))
        ], note: nil, bullets: nil)
    }

    private static func scoreStatesSection(_ s: MatchStatsSummary) -> StatSection {
        let rows = s.scoreStates.map {
            StatRow(label: $0.label, value: MatchStatsSummary.pct(num: $0.wins, den: $0.total), hint: nil,
                    fraction: frac($0.wins, $0.total))
        }
        return StatSection(title: "Score State Win Rates", rows: rows, note: nil, bullets: nil)
    }

    // MARK: - Points / set bands / HR / steps

    static func pointRows(_ stats: [PointStat]) -> [PointVM] {
        var cumMe = 0
        var cumOpp = 0
        return stats.enumerated().map { idx, pt in
            if pt.winner == .me { cumMe += 1 } else { cumOpp += 1 }
            let shot = pt.endingShot
            let chip = pointChip(pt)
            return PointVM(
                index: idx,
                setIndex: pt.setIndex,
                server: pt.server == .me ? "me" : "opp",
                winner: pt.winner == .me ? "me" : "opp",
                outcome: pt.outcome.rawValue,
                outcomeLabel: pt.outcome.displayLabel,
                outcomeColorHex: WebExportColors.outcomeColorHex(pt.outcome),
                outcomeSymbol: WebExportColors.outcomeSymbol(pt.outcome),
                chipText: chip.text,
                chipColorHex: chip.colorHex,
                outcomeText: pointOutcomeText(pt),
                pointScoreLabel: pointScoreLabel(pt),
                endingShot: shot?.rawValue,
                endingShotLabel: shot?.displayLabel,
                endingShotColorHex: shot.map { WebExportColors.endingShotColorHex($0) },
                endingShotSymbol: shot.map { WebExportColors.endingShotSymbol($0) },
                isSecondServe: pt.isSecondServe,
                isBreakPoint: pt.isBreakPoint,
                gameScoreLabel: gameScoreLabel(pt),
                cumulativeMe: cumMe,
                cumulativeOpp: cumOpp,
                heartRateBPM: pt.heartRateBPM,
                stepsCumulative: pt.stepsCumulative
            )
        }
    }

    static func setBands(_ points: [PointVM]) -> [SetBandVM] {
        guard !points.isEmpty else { return [] }
        // Group consecutive runs by setIndex (match order is already chronological).
        var bands: [SetBandVM] = []
        var runStart = 0
        var runSet = points[0].setIndex
        func close(at end: Int) {
            let isTb = false // setIndex alone does not distinguish a tiebreak band;
                              // the underlying score view does, but per-point we lack
                              // it cheaply, so colour by set number only.
            let setNumber = runSet + 1
            bands.append(SetBandVM(
                setNumber: setNumber,
                isTiebreak: isTb,
                startIndex: points[runStart].index,
                endIndex: points[end].index,
                colorHex: WebExportColors.setBandColorHex(setNumber: setNumber, isTiebreak: isTb),
                opacity: WebExportColors.setBandOpacity(isTiebreak: isTb),
                label: "Set \(setNumber)"
            ))
        }
        for i in 1..<points.count {
            if points[i].setIndex != runSet {
                close(at: i - 1)
                runStart = i
                runSet = points[i].setIndex
            }
        }
        close(at: points.count - 1)
        return bands
    }

    static func hrBlock(_ meFull: MatchStatsSummary) -> HRBlock? {
        guard !meFull.hrTimeline.isEmpty else { return nil }
        let timeline = meFull.hrTimeline.map {
            HRBlock.Sample(pointIndex: $0.pointIndex, bpm: $0.bpm, setIndex: $0.setIndex, wonByMe: $0.wonByFocal)
        }
        let zones = meFull.zoneWinRates.map {
            HRBlock.Zone(
                label: $0.zone.displayLabel,
                descriptiveLabel: $0.zone.descriptiveLabel,
                total: $0.total,
                wins: $0.wins,
                winPct: MatchStatsSummary.pct(num: $0.wins, den: $0.total),
                colorHex: hrZoneColorHex($0.zone)
            )
        }
        return HRBlock(timeline: timeline, zones: zones, resolvedMaxHR: meFull.resolvedMaxHR)
    }

    static func stepsBlock(stats: [PointStat], totalSteps: Int?) -> StepsBlock? {
        // Derivation lives in Core's StepsSeries so the iOS chart and this export
        // can't diverge; the JSON ships both the cumulative total and per-point
        // delta and the viewer only paints whichever the user toggles.
        let series = StepsSeries.make(stats: stats, totalSteps: totalSteps)
        guard !series.isEmpty else { return nil }
        return StepsBlock(timeline: series.map {
            StepsBlock.Sample(pointIndex: $0.pointIndex, cumulative: $0.cumulative, perPoint: $0.perPoint)
        })
    }

    // MARK: - Meta helpers

    static func setRows(_ record: MatchRecord) -> [SetVM] {
        record.setScores.enumerated().map { i, _ in
            let secs = record.setElapsedSeconds[i] ?? 0
            return SetVM(
                setNumber: i + 1,
                scoreMe: setScoreString(record: record, index: i, focal: .me),
                scoreOpponent: setScoreString(record: record, index: i, focal: .opponent),
                durationSeconds: Int(secs),
                durationDisplay: secs > 0 ? minutesString(secs) : nil
            )
        }
    }

    static func totals(_ record: MatchRecord) -> Totals? {
        let steps = (record.totalSteps ?? 0) > 0 ? record.totalSteps : nil
        let dist = (record.totalDistanceMeters ?? 0) > 0 ? record.totalDistanceMeters : nil
        let kcal = (record.totalCaloriesKcal ?? 0) > 0 ? record.totalCaloriesKcal : nil
        guard steps != nil || dist != nil || kcal != nil else { return nil }
        return Totals(
            steps: steps,
            stepsDisplay: steps.map { $0.formatted() },
            distanceDisplay: dist.map { MatchRecord.formattedDistance($0) },
            caloriesDisplay: kcal.map { MatchRecord.formattedCalories($0) }
        )
    }

    // MARK: - Shared formatting (parity with MatchExporter)

    // Computed (fresh instance per access) rather than shared `static let`:
    // `make` is `nonisolated static` and runs off the main actor, and
    // `DateFormatter`/`ISO8601DateFormatter` are not `Sendable`. A new instance
    // per export (a one-time user action, not a hot path) sidesteps any
    // shared-mutable-state data race.
    static var isoFormatter: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }

    static var displayFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .short
        return f
    }

    static func durationSeconds(_ record: MatchRecord) -> TimeInterval {
        if record.matchElapsedSeconds > 0 { return record.matchElapsedSeconds }
        if let end = record.endTime { return end.timeIntervalSince(record.startTime) }
        return 0
    }

    static func minutesString(_ seconds: TimeInterval) -> String { "\(Int(seconds) / 60) min" }

    static func countAndPct(_ num: Int, _ total: Int) -> String {
        guard total > 0 else { return "0" }
        let p = Int((Double(num) / Double(total)) * 100.0)
        return "\(num) (\(p)%)"
    }

    static func fractionAndPct(_ num: Int, _ den: Int) -> String {
        guard den > 0 else { return "0/0" }
        let p = Int((Double(num) / Double(den)) * 100.0)
        return "\(num)/\(den) (\(p)%)"
    }

    /// Bar fill fraction (0…1) for a percentage row, or `nil` when there is no
    /// meaningful denominator (so the row renders as plain text, no bar).
    static func frac(_ num: Int, _ den: Int) -> Double? {
        den > 0 ? Double(num) / Double(den) : nil
    }

    static func result(record: MatchRecord, focal: Player) -> String {
        if record.isInProgress { return "inProgress" }
        if let recorderWon = record.iWon {
            let focalWon = focal == .me ? recorderWon : !recorderWon
            return focalWon ? "won" : "lost"
        }
        return "draw"
    }

    static func formatLabel(_ record: MatchRecord) -> String {
        var parts: [String] = []
        switch record.matchFormat {
        case .standard:               parts.append("Best of 3")
        case .bestOf3FullFinalSet:    parts.append("Best of 3 (Full Final Set)")
        case .superTiebreak:          parts.append("Super Tiebreak")
        case .perpetualSuperTiebreak: parts.append("Perpetual Tiebreak")
        case .quick4Games:            parts.append("Quick 4 Games")
        case .perpetualPoints:        parts.append("Perpetual Points")
        }
        if record.matchType == .doubles { parts.append("Doubles") }
        return parts.joined(separator: " · ")
    }

    static func scoreString(record: MatchRecord, focal: Player) -> String? {
        guard !record.setScores.isEmpty else { return nil }
        return record.setScores.indices
            .map { setScoreString(record: record, index: $0, focal: focal) }
            .joined(separator: "  ")
    }

    /// One set's score from `focal`'s perspective (mirrors MatchExporter).
    static func setScoreString(record: MatchRecord, index: Int, focal: Player) -> String {
        let set = record.setScores[index]
        let cfg = record.matchFormat.config
        let decidingSetIndex = cfg.setsToWin * 2 - 2
        if !cfg.playRegularSets ||
            (cfg.finalSetStyle == .superTiebreak && index == decidingSetIndex && set.isTieBreak) {
            let a = focal == .me ? set.tieBreakPointsMe : set.tieBreakPointsOpponent
            let b = focal == .me ? set.tieBreakPointsOpponent : set.tieBreakPointsMe
            return "\(a)–\(b)"
        }
        if set.isTieBreak && set.gamesMe + set.gamesOpponent > 0 {
            let ga = focal == .me ? set.gamesMe : set.gamesOpponent
            let gb = focal == .me ? set.gamesOpponent : set.gamesMe
            let ta = focal == .me ? set.tieBreakPointsMe : set.tieBreakPointsOpponent
            let tb = focal == .me ? set.tieBreakPointsOpponent : set.tieBreakPointsMe
            return "\(ga)–\(gb) (\(ta)–\(tb))"
        }
        let a = focal == .me ? set.gamesMe : set.gamesOpponent
        let b = focal == .me ? set.gamesOpponent : set.gamesMe
        return "\(a)–\(b)"
    }

    static func rallyDepthLabel(_ shot: EndingShot) -> String {
        switch shot {
        case .serve:        return "Serve (shot 1)"
        case .return:       return "Return (shot 2)"
        case .servePlusOne: return "S+1 (server's 3rd shot)"
        case .rally:        return "Rally (4+ shots)"
        }
    }

    /// Tennis score notation for a point's starting game snapshot (server–returner).
    static func gameScoreLabel(_ pt: PointStat) -> String {
        guard let g = pt.gameScoreAtStart else { return "—" }
        if g.isTiebreak { return "\(g.server)-\(g.returner) TB" }
        return "\(tennisPoints(g.server, g.returner))-\(tennisPoints(g.returner, g.server))"
    }

    static func tennisPoints(_ mine: Int, _ theirs: Int) -> String {
        switch mine {
        case 0: return "0"
        case 1: return "15"
        case 2: return "30"
        case 3: return theirs >= 3 ? (mine > theirs ? "Ad" : "40") : "40"
        default: return mine > theirs ? "Ad" : "40"
        }
    }

    // MARK: - Points-tab display (mirror MatchDetailView.pointRow)

    /// Short outcome chip text + its colour, attributed exactly like
    /// `MatchDetailView.outcomeChip` (DF coloured by the server who served it,
    /// UE/FE by the player who erred, W by the striker).
    static func pointChip(_ pt: PointStat) -> (text: String, colorHex: String) {
        let isWin = pt.winner == .me
        let me = WebExportColors.meLineHex, opp = WebExportColors.opponentLineHex
        switch pt.outcome {
        case .winner:        return (isWin ? "W" : "Opp W", isWin ? me : opp)
        case .doubleFault:   return ("DF", pt.server == .me ? me : opp)
        case .unforcedError: return ("UE", isWin ? opp : me)
        case .forcedError:   return ("FE", isWin ? opp : me)
        case .uncategorized: return (isWin ? "+" : "−", isWin ? me : opp)
        }
    }

    /// The longer outcome line ("Winner — Me", "Unforced Err — Opp").
    static func pointOutcomeText(_ pt: PointStat) -> String {
        let winnerName = pt.winner == .me ? "Me" : "Opp"
        switch pt.outcome {
        case .winner:        return "Winner — \(winnerName)"
        case .doubleFault:   return "Double Fault — \(pt.server == .me ? "Me" : "Opp")"
        case .unforcedError: return "Unforced Err — \(pt.winner == .me ? "Opp" : "Me")"
        case .forcedError:   return "Forced Err — \(pt.winner == .me ? "Opp" : "Me")"
        case .uncategorized: return "Point — \(winnerName)"
        }
    }

    /// Server-relative game score in recorder frame ("0–15", "Deuce", "Ad Me").
    static func pointScoreLabel(_ pt: PointStat) -> String {
        guard let snap = pt.gameScoreAtStart else { return "" }
        let s = snap.server, r = snap.returner, server = pt.server
        if snap.isTiebreak { return server == .me ? "\(s)–\(r)" : "\(r)–\(s)" }
        let labels = ["0", "15", "30", "40"]
        if s >= 3 && r >= 3 {
            if s == r { return "Deuce" }
            if s > r  { return "Ad \(server == .me ? "Me" : "Opp")" }
            return "Ad \(server == .me ? "Opp" : "Me")"
        }
        let sLabel = s < labels.count ? labels[s] : "\(s)"
        let rLabel = r < labels.count ? labels[r] : "\(r)"
        return server == .me ? "\(sLabel)–\(rLabel)" : "\(rLabel)–\(sLabel)"
    }

    static func hrZoneColorHex(_ zone: HRZone) -> String {
        switch zone {
        case .z1: return "#34C759" // green  — Very Light
        case .z2: return "#30B0C7" // teal   — Light
        case .z3: return "#FFCC00" // yellow — Moderate
        case .z4: return "#FF9500" // orange — Hard
        case .z5: return "#FF3B30" // red    — Maximum
        }
    }
}
