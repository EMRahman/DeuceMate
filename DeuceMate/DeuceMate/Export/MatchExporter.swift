// MatchExporter.swift — Generates plain-text exports for a single match.
// Three modes: summary-only, summary + raw points, and AI coaching prompt (summary + raw points + prompt).
import Foundation
import DeuceMateCore

struct MatchExporter {

    // MARK: - Public API

    /// Summarised stats only. No AI references.
    nonisolated static func summaryExport(for record: MatchRecord, maxHR: Int = 190, focal: Player = .me) -> String {
        buildDataSections(for: record, includeRawPoints: false, focal: focal, maxHR: maxHR)
    }

    /// Summarised stats + raw point-by-point table. No AI references.
    /// Only useful when outcome tracking was enabled.
    nonisolated static func fullExport(for record: MatchRecord, maxHR: Int = 190, focal: Player = .me) -> String {
        buildDataSections(for: record, includeRawPoints: true, focal: focal, maxHR: maxHR)
    }

    /// AI coaching prompt followed by summary stats and raw points.
    /// Designed to be pasted directly into a GenAI tool. The prompt and title
    /// switch perspective based on `focal` so the opponent variant can be
    /// shared with the opponent for coaching tips on their side of the match.
    /// `playerNTRP` is used to tailor the prompt preamble to the player's level
    /// (e.g. "3.0–3.5") so the AI gives appropriately targeted advice.
    nonisolated static func aiPromptExport(
        for record: MatchRecord,
        maxHR: Int = 190,
        focal: Player = .me,
        playerNTRP: String = "3.0–3.5"
    ) -> String {
        let hasStats = !record.stats.isEmpty
        let title = focal == .opponent
            ? "# DeuceMate Match Export (Opponent Perspective)"
            : "# DeuceMate Match Export"
        let prompt = focal == .opponent
            ? opponentCoachingPrompt(includeRawPoints: hasStats, playerNTRP: playerNTRP)
            : coachingPrompt(includeRawPoints: hasStats, playerNTRP: playerNTRP)
        var sections: [String] = []
        sections.append("<!-- Paste into your favorite GenAI tool — then delete this line -->")
        sections.append(title)
        sections.append(prompt)
        sections.append(contentsOf: dataSections(for: record, includeRawPoints: true, focal: focal, maxHR: maxHR))
        return sections.joined(separator: "\n\n")
    }

    // MARK: - Core builders

    private nonisolated static func buildDataSections(for record: MatchRecord, includeRawPoints: Bool, focal: Player, maxHR: Int) -> String {
        var sections: [String] = []
        let title = focal == .opponent
            ? "# DeuceMate Match Export (Opponent Perspective)"
            : "# DeuceMate Match Export"
        sections.append(title)
        sections.append(contentsOf: dataSections(for: record, includeRawPoints: includeRawPoints, focal: focal, maxHR: maxHR))
        return sections.joined(separator: "\n\n")
    }

    private static func dataSections(for record: MatchRecord, includeRawPoints: Bool, focal: Player, maxHR: Int = 190) -> [String] {
        let allStats = record.stats
        let hasStats = !allStats.isEmpty
        // Compute outcome stats on the categorized subset only, mirroring MatchDetailView's
        // approach. This preserves coaching data even when tracking was toggled mid-match.
        let categorizedStats = allStats.filter { $0.outcome != .uncategorized }
        let hasSomeOutcomes = !categorizedStats.isEmpty
        let hasMixedData = hasSomeOutcomes && categorizedStats.count < allStats.count

        // Points summary uses all stats; outcome sections use categorized subset.
        let fullSummary = MatchStatsSummary(
            stats: allStats,
            focal: focal,
            setElapsedSeconds: record.setElapsedSeconds,
            maxHR: maxHR
        )
        let categorizedSummary = hasSomeOutcomes ? MatchStatsSummary(
            stats: categorizedStats,
            focal: focal,
            setElapsedSeconds: record.setElapsedSeconds,
            maxHR: maxHR
        ) : fullSummary

        var sections: [String] = []
        sections.append(matchOverview(record: record, focal: focal))

        if hasStats {
            sections.append(pointsSummary(summary: fullSummary))
        }

        if !hasSomeOutcomes {
            sections.append(dataNote(hasAnyStats: hasStats))
        } else {
            if hasMixedData {
                sections.append(partialDataNote(categorized: categorizedStats.count, total: allStats.count))
            }
            sections.append(serveSection(summary: categorizedSummary))
            sections.append(returnSection(summary: categorizedSummary))
            sections.append(breakPointSection(summary: categorizedSummary))
            sections.append(errorAnalysis(summary: categorizedSummary, focal: focal))
            sections.append(opponentErrors(summary: categorizedSummary, focal: focal))
            if !categorizedSummary.recCoachInsights.isEmpty {
                sections.append(recCoachSection(summary: categorizedSummary))
            }
            if !categorizedSummary.rallyDepth.isEmpty {
                sections.append(rallyDepthSection(summary: categorizedSummary))
            }
            if categorizedSummary.bigPointTotal > 0 && categorizedSummary.normalPointTotal > 0 {
                sections.append(pressurePoints(summary: categorizedSummary))
            }
            if !categorizedSummary.scoreStates.isEmpty {
                sections.append(scoreStates(summary: categorizedSummary))
            }
        }

        // HR data (heartRateBPM) is always the recorder's — never the opponent's.
        // Including it in opponent exports would cross-map recorder physiology to
        // opponent win rates, producing physiologically invalid coaching feedback.
        if focal == .me {
            if !fullSummary.zoneWinRates.isEmpty {
                sections.append(heartRateSection(summary: fullSummary))
            }
            if !fullSummary.autoInsights.isEmpty {
                sections.append(pulseCoachSection(summary: fullSummary))
            }
            if !fullSummary.stepsTimeline.isEmpty {
                sections.append(movementSection(record: record, summary: fullSummary))
            }
        }

        sections.append(setBySetScores(record: record, focal: focal))

        if includeRawPoints && hasStats {
            sections.append(rawPointData(stats: allStats, focal: focal))
        }

        return sections
    }

    // MARK: - Section builders

    private static func matchOverview(record: MatchRecord, focal: Player) -> String {
        let result: String
        if record.isInProgress {
            result = "In Progress"
        } else if let recorderWon = record.iWon {
            let focalWon = focal == .me ? recorderWon : !recorderWon
            result = focalWon ? "Won" : "Lost"
        } else {
            result = "Draw"
        }

        var lines = ["## Match Overview"]
        lines.append(row("Date:", exportDateFormatter.string(from: record.startTime)))
        lines.append(row("Format:", formatLabel(record: record)))
        lines.append(row("Result:", result))
        lines.append(row("Score:", scoreString(record: record, focal: focal) ?? "—"))
        lines.append(row("Duration:", totalDurationString(record: record)))
        if let steps = record.totalSteps, steps > 0 {
            lines.append(row("Steps:", steps.formatted()))
        }
        if let kcal = record.totalCaloriesKcal, kcal > 0 {
            lines.append(row("Calories:", MatchRecord.formattedCalories(kcal)))
        }
        if let meters = record.totalDistanceMeters, meters > 0 {
            lines.append(row("Distance:", MatchRecord.formattedDistance(meters)))
        }
        return lines.joined(separator: "\n")
    }

    private static func pointsSummary(summary: MatchStatsSummary) -> String {
        var lines = ["## Points Summary"]
        lines.append(row("Total Points Played:", "\(summary.totalPoints)"))
        lines.append(row("Points Won:", countAndPct(summary.pointsWon, summary.totalPoints)))
        lines.append(row("Points Lost:", countAndPct(summary.lostPoints, summary.totalPoints)))
        return lines.joined(separator: "\n")
    }

    private static func dataNote(hasAnyStats: Bool) -> String {
        if hasAnyStats {
            return """
            ## Data Note
            Some or all points in this match were recorded without outcome tracking.
            Only score-level data is available. For shot-by-shot analysis, enable
            outcome tracking before your next match in DeuceMate settings.
            """
        } else {
            return """
            ## Data Note
            Point outcome tracking was not enabled for this match.
            Only score-level data is available. For detailed shot-by-shot analysis,
            enable outcome tracking before your next match in DeuceMate settings.
            """
        }
    }

    private static func partialDataNote(categorized: Int, total: Int) -> String {
        """
        ## Data Note
        Outcome tracking was off for \(total - categorized) of \(total) points in this match
        (tracking was toggled mid-match). The sections below are based on the \(categorized)
        categorized points only and may not reflect the full match.
        """
    }

    private static func serveSection(summary: MatchStatsSummary) -> String {
        let dfNote: String
        if summary.secondServeTotal > 0 {
            let p = Int((Double(summary.doubleFaults) / Double(summary.secondServeTotal)) * 100)
            dfNote = "\(summary.doubleFaults)  (\(p)% of 2nd serve opportunities)"
        } else {
            dfNote = "—"
        }

        let servicePointsWon = summary.firstServeWins + summary.secondServeWins

        var lines = ["## Serve Performance"]
        lines.append(row("Service Points Win %:", MatchStatsSummary.pct(num: servicePointsWon, den: summary.firstServeTotal)))
        lines.append(row("1st Serve In %:", MatchStatsSummary.pct(num: summary.firstServeIn, den: summary.firstServeTotal)))
        lines.append(row("1st Serve Win %:", MatchStatsSummary.pct(num: summary.firstServeWins, den: summary.firstServeIn)))
        lines.append(row("2nd Serve In %:", MatchStatsSummary.pct(num: summary.secondServeIn, den: summary.secondServeTotal)))
        lines.append(row("2nd Serve Win %:", MatchStatsSummary.pct(num: summary.secondServeWins, den: summary.secondServeIn)))
        lines.append(row("Double Faults:", dfNote))
        return lines.joined(separator: "\n")
    }

    private static func returnSection(summary: MatchStatsSummary) -> String {
        var lines = ["## Return Performance"]
        lines.append(row("Return Win vs. 1st Serve:", MatchStatsSummary.pct(num: summary.returnWinsOnFirst, den: summary.returnOppsOnFirst)))
        lines.append(row("Return Win vs. 2nd Serve:", MatchStatsSummary.pct(num: summary.returnWinsOnSecond, den: summary.returnOppsOnSecond)))
        return lines.joined(separator: "\n")
    }

    private static func breakPointSection(summary: MatchStatsSummary) -> String {
        var lines = ["## Break Points"]
        lines.append(row("Chances as Returner:", fractionAndPct(summary.breakPointWins, summary.breakPointOpps) + " converted"))
        lines.append(row("Saved as Server:", fractionAndPct(summary.breakPointsFaced - summary.breakPointsLost, summary.breakPointsFaced) + " saved"))
        return lines.joined(separator: "\n")
    }

    private static func errorAnalysis(summary: MatchStatsSummary, focal: Player) -> String {
        let heading = focal == .me ? "## Error Analysis (My Points Lost)" : "## Error Analysis (Your Points Lost)"
        var lines = [heading]
        lines.append(row("Winners:", "\(summary.myWinners)"))
        lines.append(row("Unforced Errors:", "\(summary.myUnforcedErrors)"))
        lines.append(row("Forced Errors:", "\(summary.myForcedErrors)"))
        lines.append(row("Double Faults:", "\(summary.myDoubleFaults)"))
        lines.append(row("Self-Inflicted Losses:", summary.ownErrorsPct + "  (own errors / points lost)"))
        lines.append(row("W:UE Ratio:", summary.wueRatio + "  ← aim for >1.0"))
        lines.append(row("Aggression Index:", summary.aggressionIndex + "  (winners / winners+UE)"))
        return lines.joined(separator: "\n")
    }

    private static func opponentErrors(summary: MatchStatsSummary, focal: Player) -> String {
        let heading = focal == .me ? "## Opponent Errors (Points I Won)" : "## Opponent Errors (Points You Won)"
        var lines = [heading]
        lines.append(row("Opponent Unforced Errors:", "\(summary.opponentUnforcedErrors)"))
        lines.append(row("Opponent Forced Errors:", "\(summary.opponentForcedErrors)"))
        lines.append(row("Opponent Double Faults:", "\(summary.opponentDoubleFaults)"))
        lines.append(row("Opponent Winners:", "\(summary.opponentWinners)"))
        return lines.joined(separator: "\n")
    }

    private static func rallyDepthSection(summary: MatchStatsSummary) -> String {
        var lines = ["## Rally Depth"]
        for stat in summary.rallyDepth {
            let label = rallyDepthLabel(stat.shot) + ":"
            lines.append(row(label, "Win " + MatchStatsSummary.pct(num: stat.wins, den: stat.total)))
        }
        return lines.joined(separator: "\n")
    }

    private static func pressurePoints(summary: MatchStatsSummary) -> String {
        var lines = ["## Pressure vs. Normal Points"]
        lines.append(row("Big Points (BP/Deuce/Tiebreak):", MatchStatsSummary.pct(num: summary.bigPointWins, den: summary.bigPointTotal)))
        lines.append(row("Normal Points:", MatchStatsSummary.pct(num: summary.normalPointWins, den: summary.normalPointTotal)))
        return lines.joined(separator: "\n")
    }

    private static func scoreStates(summary: MatchStatsSummary) -> String {
        var lines = ["## Score State Win Rates"]
        for stat in summary.scoreStates {
            lines.append(row(stat.label + ":", MatchStatsSummary.pct(num: stat.wins, den: stat.total)))
        }
        return lines.joined(separator: "\n")
    }

    private static func setBySetScores(record: MatchRecord, focal: Player) -> String {
        var lines = ["## Set-by-Set Scores"]
        guard !record.setScores.isEmpty else {
            lines.append("No sets completed.")
            return lines.joined(separator: "\n")
        }
        let cfg = record.matchFormat.config
        let decidingSetIndex = cfg.setsToWin * 2 - 2
        for (i, set) in record.setScores.enumerated() {
            let scoreStr: String
            // Tiebreak-only formats (Super/Perpetual Tiebreak, Perpetual
            // Points) store the running score in tieBreakPoints* with
            // games* left at 0; treat every set as a tiebreak score.
            // Otherwise only the deciding-set super-tiebreak slot uses the
            // tiebreak score. Matches the property-based check in
            // scoreString(record:focal:) below.
            if !cfg.playRegularSets ||
               (cfg.finalSetStyle == .superTiebreak && i == decidingSetIndex && set.isTieBreak) {
                let a = focal == .me ? set.tieBreakPointsMe : set.tieBreakPointsOpponent
                let b = focal == .me ? set.tieBreakPointsOpponent : set.tieBreakPointsMe
                scoreStr = "\(a)–\(b) tiebreak"
            } else if set.isTieBreak && set.gamesMe + set.gamesOpponent > 0 {
                let ga = focal == .me ? set.gamesMe : set.gamesOpponent
                let gb = focal == .me ? set.gamesOpponent : set.gamesMe
                let ta = focal == .me ? set.tieBreakPointsMe : set.tieBreakPointsOpponent
                let tb = focal == .me ? set.tieBreakPointsOpponent : set.tieBreakPointsMe
                scoreStr = "\(ga)–\(gb) (\(ta)–\(tb))"
            } else {
                let a = focal == .me ? set.gamesMe : set.gamesOpponent
                let b = focal == .me ? set.gamesOpponent : set.gamesMe
                scoreStr = "\(a)–\(b)"
            }
            let durationStr: String
            if let secs = record.setElapsedSeconds[i], secs > 0 {
                durationStr = "  (\(durationString(secs)))"
            } else {
                durationStr = ""
            }
            lines.append(row("Set \(i + 1):", scoreStr + durationStr))
        }
        return lines.joined(separator: "\n")
    }

    private static func heartRateSection(summary: MatchStatsSummary) -> String {
        var lines = ["## Heart Rate Analysis"]
        for zwr in summary.zoneWinRates {
            let label = "\(zwr.zone.displayLabel) \(zwr.zone.descriptiveLabel) Win %:"
            lines.append(row(label, MatchStatsSummary.pct(num: zwr.wins, den: zwr.total)))
        }

        return lines.joined(separator: "\n")
    }

    private static func pulseCoachSection(summary: MatchStatsSummary) -> String {
        var lines = ["## PulseCoach Insights"]
        for insight in summary.autoInsights {
            lines.append("- \(insight)")
        }
        return lines.joined(separator: "\n")
    }

    /// Recorder-only movement/fatigue summary derived from per-point step data:
    /// the match step total, average steps per point, the first- vs second-half
    /// movement trend, and the accumulated-step fatigue insights. Gated on
    /// `focal == .me` by the caller — like HR, steps belong to the recorder.
    private static func movementSection(record: MatchRecord, summary: MatchStatsSummary) -> String {
        let timeline = summary.stepsTimeline
        var lines = ["## Movement & Fatigue"]
        if let steps = record.totalSteps, steps > 0 {
            lines.append(row("Total Steps:", steps.formatted()))
        }
        let perPoint = timeline.map(\.perPointSteps)
        if !perPoint.isEmpty {
            let avg = Int((Double(perPoint.reduce(0, +)) / Double(perPoint.count)).rounded())
            lines.append(row("Avg Steps / Point:", "\(avg)"))
        }
        if timeline.count >= 4 {
            let half = timeline.count / 2
            let firstAvg = averageSteps(Array(timeline.prefix(half)))
            let secondAvg = averageSteps(Array(timeline.suffix(timeline.count - half)))
            let trend = secondAvg > firstAvg ? "↑" : (secondAvg < firstAvg ? "↓" : "→")
            lines.append(row("Steps/Point by Half:", "\(firstAvg) → \(secondAvg)  \(trend)"))
        }
        for insight in summary.stepsInsights {
            lines.append("- \(insight)")
        }
        return lines.joined(separator: "\n")
    }

    private static func averageSteps(_ points: [MatchStatsSummary.StepPoint]) -> Int {
        guard !points.isEmpty else { return 0 }
        let total = points.reduce(0) { $0 + $1.perPointSteps }
        return Int((Double(total) / Double(points.count)).rounded())
    }

    private static func recCoachSection(summary: MatchStatsSummary) -> String {
        var lines = ["## Coaching Insights"]
        for insight in summary.recCoachInsights {
            lines.append("- \(insight)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Raw point data table

    private static func rawPointData(stats: [PointStat], focal: Player) -> String {
        // HR and steps are always the recorder's. From the recorder's reading
        // they're "My …"; from the opponent's reading the recorder is their
        // opponent, so prefix "Opp …".
        let hrLabel = focal == .opponent ? "Opponent HR" : "My HR"
        let stepLabel = focal == .opponent ? "Opp Steps/Pt" : "Steps/Pt"
        let totalStepLabel = focal == .opponent ? "Opp Total Steps" : "Total Steps"

        // Per-point movement load (steps during each point), keyed by point id.
        let stepDeltas = MatchStatsSummary.perPointStepDeltas(stats)

        var lines = ["## Raw Point Data"]
        lines.append("Each row is one point in match order. " +
                     "\"Steps/Pt\" is steps taken during that point; \"Total Steps\" is the running match total.")
        if focal == .opponent {
            // The table is generated from the recorder's perspective, so
            // "Me"/"Opp" in Server/Winner refer to the recorder (your
            // opponent) and the focal player (you) respectively. The HR and
            // step columns are also the recorder's — i.e. your opponent's —
            // since they're only available from the recording device.
            lines.append("Note: \"Me\" = your opponent (the recorder), \"Opp\" = you. " +
                         "The HR and step columns are your opponent's (only available from the recording device).")
        }
        lines.append("")

        // Header
        lines.append("| # | Set | Game Score | Server | Winner | 2nd Srv | Break Pt | Outcome | Shot | \(hrLabel) | \(stepLabel) | \(totalStepLabel) |")
        lines.append("|---|-----|------------|--------|--------|---------|----------|---------|------|---------|---------|---------|")

        for (i, pt) in stats.enumerated() {
            let num = "\(i + 1)"
            let setNum = "\(pt.setIndex + 1)"
            let gameScore = gameScoreLabel(pt)
            let server = playerLabel(pt.server)
            let winner = playerLabel(pt.winner)
            let secondSrv = pt.isSecondServe ? "Yes" : "No"
            let bp = pt.isBreakPoint ? "Yes" : "No"
            let outcome = outcomeLabel(pt.outcome)
            let shot = pt.endingShot.map { endingShotLabel($0) } ?? "—"
            let hr = pt.heartRateBPM.map { "\($0) bpm" } ?? "—"
            let perPointSteps = stepDeltas[pt.id].map { "\($0)" } ?? "—"
            let totalSteps = pt.stepsCumulative.map { $0.formatted() } ?? "—"

            lines.append("| \(num) | \(setNum) | \(gameScore) | \(server) | \(winner) | \(secondSrv) | \(bp) | \(outcome) | \(shot) | \(hr) | \(perPointSteps) | \(totalSteps) |")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Coaching prompt

    private static func coachingPrompt(includeRawPoints: Bool, playerNTRP: String = "3.0–3.5") -> String {
        let rawPointsNote = includeRawPoints
            ? "\nThe match data below includes a full point-by-point table. Use it to spot patterns the summary stats alone may miss — e.g. error clusters in specific games, performance at key scores, or serve/return trends across the match.\n"
            : ""

        return """
        ## Coaching Prompt

        You are an experienced recreational tennis coach. Analyze the match data below, \
        which was automatically recorded by a smartwatch during the match. \
        The player is an amateur (NTRP \(playerNTRP) level).
        \(rawPointsNote)
        Please provide feedback in this structure:

        **1. Biggest Weakness — the single most impactful problem to fix**
        Identify it using the numbers. Explain specifically why it cost points.

        **2. Hidden Strength — one thing that is genuinely going well**
        Be specific: cite the stat.

        **3. Two Tactical Adjustments for the Next Match**
        Practical, in-match changes that need no extra practice. For example:
        - Serve strategy based on 1st/2nd serve win rates
        - Rally length target based on rally depth data
        - Break point approach based on pressure point performance

        **4. One Practice Drill**
        Exactly one drill targeting the biggest weakness.
        Keep it simple — doable on a public court without a coach.

        **5. Movement & Fitness** (only include this section when Heart Rate zone data, a Movement & Fatigue section, or Steps/Calories/Distance appear below)
        One or two sentences on physical effort and fatigue — HR zone distribution, per-point step load (Steps/Pt), how win rate changed as total steps accumulated, or set-to-set movement trend. \
        One actionable off-court conditioning habit if the data supports it. Skip this section entirely if none of those fields appear.

        Tone: Direct and specific. Use the numbers. Skip any section where the data shows "—" or is missing.
        """
    }

    private static func opponentCoachingPrompt(includeRawPoints: Bool, playerNTRP: String = "3.0–3.5") -> String {
        let rawPointsNote = includeRawPoints
            ? "\nThe match data below includes a full point-by-point table (labeled from your opponent's recording perspective: \"Me\" = the recorder, \"Opp\" = you). Use it to spot patterns the summary stats alone may miss.\n"
            : ""

        return """
        ## Coaching Prompt

        You are an experienced recreational tennis coach. Analyze the match data below. \
        The stats represent the OPPONENT's perspective from a match recorded by a smartwatch. \
        All numbers (serve %, return %, errors, winners) describe the opponent player — \
        treat them as "your" stats for coaching purposes. \
        The player is an amateur (NTRP \(playerNTRP) level).
        \(rawPointsNote)
        Please provide feedback in this structure:

        **1. Biggest Weakness — the single most impactful problem to fix**
        Identify it using the numbers. Explain specifically why it cost points.

        **2. Hidden Strength — one thing that is genuinely going well**
        Be specific: cite the stat.

        **3. Two Tactical Adjustments for the Next Match**
        Practical, in-match changes that need no extra practice. For example:
        - Serve strategy based on 1st/2nd serve win rates
        - Rally length target based on rally depth data
        - Break point approach based on pressure point performance

        **4. One Practice Drill**
        Exactly one drill targeting the biggest weakness.
        Keep it simple — doable on a public court without a coach.

        Note: Any Steps, Calories, Distance, or Heart Rate data in the export below belongs \
        to the recorder (your opponent), not to you. Do not use it to draw conclusions about \
        your own physical effort or fitness — omit those fields from your analysis.

        Tone: Direct and specific. Use the numbers. Skip any section where the data shows "—" or is missing.
        """
    }

    // MARK: - Formatting helpers

    private static let exportDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .short
        return f
    }()

    /// Right-pads label to `width` chars for fixed-column alignment.
    private static func row(_ label: String, _ value: String, width: Int = 30) -> String {
        let padded = label.padding(toLength: max(label.count, width), withPad: " ", startingAt: 0)
        return "\(padded)\(value)"
    }

    /// "76  (54%)" — used for points won/lost.
    private static func countAndPct(_ num: Int, _ total: Int) -> String {
        guard total > 0 else { return "0" }
        let p = Int((Double(num) / Double(total)) * 100.0)
        return "\(num)  (\(p)%)"
    }

    /// "3/8  (38%)" — used for break points.
    private static func fractionAndPct(_ num: Int, _ den: Int) -> String {
        guard den > 0 else { return "0/0" }
        let p = Int((Double(num) / Double(den)) * 100.0)
        return "\(num)/\(den)  (\(p)%)"
    }

    private static func durationString(_ seconds: TimeInterval) -> String {
        "\(Int(seconds) / 60) min"
    }

    private static func totalDurationString(record: MatchRecord) -> String {
        let total: TimeInterval
        if record.matchElapsedSeconds > 0 {
            total = record.matchElapsedSeconds
        } else if let end = record.endTime {
            total = end.timeIntervalSince(record.startTime)
        } else {
            return "—"
        }

        var parts = ["\(durationString(total)) total"]
        for i in 0..<record.setScores.count {
            if let secs = record.setElapsedSeconds[i], secs > 0 {
                parts.append("Set \(i + 1): \(durationString(secs))")
            }
        }
        return parts.joined(separator: "  |  ")
    }

    private static func scoreString(record: MatchRecord, focal: Player) -> String? {
        guard !record.setScores.isEmpty else { return nil }
        let parts = record.setScores.enumerated().map { index, set -> String in
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
        return parts.joined(separator: "  ")
    }

    private static func formatLabel(record: MatchRecord) -> String {
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

    private static func rallyDepthLabel(_ shot: EndingShot) -> String {
        switch shot {
        case .serve:        return "Serve (shot 1)"
        case .return:       return "Return (shot 2)"
        case .servePlusOne: return "S+1 (server's 3rd shot)"
        case .rally:        return "Rally (4+ shots)"
        }
    }

    // MARK: - Raw point table helpers

    private static func playerLabel(_ player: Player) -> String {
        player == .me ? "Me" : "Opp"
    }

    private static func outcomeLabel(_ outcome: PointOutcome) -> String {
        switch outcome {
        case .winner:        return "Winner"
        case .unforcedError: return "Unforced Err"
        case .forcedError:   return "Forced Err"
        case .doubleFault:   return "Double Fault"
        case .uncategorized: return "—"
        }
    }

    private static func endingShotLabel(_ shot: EndingShot) -> String {
        switch shot {
        case .serve:        return "Serve"
        case .return:       return "Return"
        case .servePlusOne: return "S+1"
        case .rally:        return "Rally"
        }
    }

    /// Tennis score notation for a game snapshot: "0-15", "30-30", "Ad-40", "7-5 TB", etc.
    private static func gameScoreLabel(_ pt: PointStat) -> String {
        guard let g = pt.gameScoreAtStart else { return "—" }
        if g.isTiebreak {
            // In a tiebreak, server/returner map directly to points
            // We want to show score from "my" perspective: need to know if focal=me is server
            return "\(g.server)-\(g.returner) TB"
        }
        let serverScore = tennisPoints(g.server, g.returner)
        let returnerScore = tennisPoints(g.returner, g.server)
        // Show as server–returner so the Server column gives context
        return "\(serverScore)-\(returnerScore)"
    }

    private static func tennisPoints(_ mine: Int, _ theirs: Int) -> String {
        switch mine {
        case 0: return "0"
        case 1: return "15"
        case 2: return "30"
        case 3: return theirs >= 3 ? (mine > theirs ? "Ad" : "40") : "40"
        default: return mine > theirs ? "Ad" : "40"
        }
    }
}
