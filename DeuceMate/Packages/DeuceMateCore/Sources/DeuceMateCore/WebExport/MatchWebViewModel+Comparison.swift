// MatchWebViewModel+Comparison.swift — builds the TV-style Me-vs-Opponent stat
// comparison the self-contained HTML viewer renders as split bars. A faithful,
// pure mirror of `MatchDetailView`'s comparison sections (same titles, order,
// gating, and percent/count/ratio rows), so the web export and the iOS archive
// detail read the same. Recorder-framed: "Me" is always the recorder.
//
// Both summaries are computed over the *full* (unfiltered) match — exactly like
// MatchDetailView's `meSummary`/`oppSummary` (setFilter == .all). Outcome tallies
// inside the summary already draw only from categorised points, so a single
// all-stats summary serves both the serve/return/break stats and the outcome
// counts without double-counting.
import Foundation

extension MatchWebViewModel {

    // MARK: - Set-filter views (mirror MatchDetailView's set picker)

    /// `All` plus one filter per set, each with the comparison / points-won /
    /// duration for that scope — mirrors `availableSetFilters` recomputing
    /// `meSummary`/`oppSummary` over `filteredStats`.
    static func buildFilters(_ record: MatchRecord, maxHR: Int) -> [FilterVM] {
        var out: [FilterVM] = [filterView(record, key: "all", label: "All", setIndex: nil, maxHR: maxHR)]
        for i in record.setScores.indices {
            out.append(filterView(record, key: "set-\(i)", label: setLabel(record, i), setIndex: i, maxHR: maxHR))
        }
        return out
    }

    static func setLabel(_ record: MatchRecord, _ i: Int) -> String {
        record.matchFormat.config.isDecidingSuperTiebreak(setIndex: i) ? "TB" : "Set \(i + 1)"
    }

    private static func filterView(_ record: MatchRecord, key: String, label: String,
                                   setIndex: Int?, maxHR: Int) -> FilterVM {
        let stats = setIndex.map { idx in record.stats.filter { $0.setIndex == idx } } ?? record.stats
        let meFull  = MatchStatsSummary(stats: stats, focal: .me,
                                        setElapsedSeconds: record.setElapsedSeconds, maxHR: maxHR)
        let oppFull = MatchStatsSummary(stats: stats, focal: .opponent,
                                        setElapsedSeconds: record.setElapsedSeconds, maxHR: maxHR)
        return FilterVM(
            key: key, label: label,
            pointsWon: pointsWonVM(meFull),
            durationRows: durationRows(record, setIndex: setIndex),
            comparison: buildComparison(meFull: meFull, oppFull: oppFull)
        )
    }

    private static func pointsWonVM(_ meFull: MatchStatsSummary) -> PointsWonVM {
        let total = meFull.totalPoints
        let meWon = meFull.pointsWon
        let oppWon = total - meWon
        func pct(_ n: Int) -> Int { total > 0 ? Int((Double(n) / Double(total) * 100).rounded()) : 0 }
        return PointsWonVM(meWon: meWon, oppWon: oppWon, total: total, mePct: pct(meWon), oppPct: pct(oppWon))
    }

    /// Duration row(s) + Steps/Calories for a filter (mirrors `setDurationRows`
    /// plus the Stats-tab Steps/Calories). Steps/Calories are prorated per set by
    /// `SetActivitySplit` when a single set is selected; whole-match totals for `All`.
    private static func durationRows(_ record: MatchRecord, setIndex: Int?) -> [LabeledValue] {
        var rows: [LabeledValue] = []
        let indices: [Int] = setIndex.map { [$0] } ?? Array(record.setScores.indices)
        for i in indices {
            let lbl = indices.count > 1 ? "\(setLabel(record, i)) Duration" : "Duration"
            if let secs = record.setElapsedSeconds[i] {
                rows.append(LabeledValue(label: lbl, value: "\(Int(secs) / 60) min"))
            } else {
                let pts = record.stats.filter { $0.setIndex == i }
                if let first = pts.map(\.timestamp).min(), let last = pts.map(\.timestamp).max() {
                    rows.append(LabeledValue(label: lbl, value: "\(Int(last.timeIntervalSince(first)) / 60) min"))
                }
            }
        }
        let split = SetActivitySplit(setCount: record.setScores.count, stats: record.stats,
                                     setElapsedSeconds: record.setElapsedSeconds,
                                     totalSteps: record.totalSteps, totalCaloriesKcal: record.totalCaloriesKcal)
        let steps = setIndex.map { split.steps[$0] } ?? record.totalSteps
        let kcal  = setIndex.map { split.calories[$0] } ?? record.totalCaloriesKcal
        if let s = steps, s > 0 { rows.append(LabeledValue(label: "Steps", value: s.formatted())) }
        if let k = kcal, k > 0 { rows.append(LabeledValue(label: "Calories", value: MatchRecord.formattedCalories(k))) }
        return rows
    }

    static func buildComparison(meFull: MatchStatsSummary, oppFull: MatchStatsSummary) -> Comparison {
        // Gating mirrors MatchDetailView: `hasAny` = at least one categorised
        // point; `hasAll` = a non-empty match with *every* point categorised.
        let total = meFull.totalPoints
        let hasAny = (total - meFull.uncategorizedCount) > 0
        let hasAll = total > 0 && meFull.uncategorizedCount == 0

        var sections: [CmpSection] = []

        // Outcome Breakdown
        if hasAny {
            sections.append(CmpSection(title: "Outcome Breakdown", rows: [
                CmpRow(label: "Win : Unforced Err", subtitle: "aim for > 1.0", kind: .ratio,
                       meValue: meFull.wueRatio, oppValue: oppFull.wueRatio,
                       meFraction: 0, oppFraction: 0, meBarLabel: nil, oppBarLabel: nil),
                count("Winners",         meFull.myWinners,        oppFull.myWinners),
                count("Unforced Errors", meFull.myUnforcedErrors, oppFull.myUnforcedErrors),
                count("Forced Errors",   meFull.myForcedErrors,   oppFull.myForcedErrors),
                count("Double Faults",   meFull.myDoubleFaults,   oppFull.myDoubleFaults),
                percent("Aggression Index", subtitle: "W ÷ (W + UE)",
                        meNum: meFull.myWinners,  meDen: meFull.myWinners + meFull.myUnforcedErrors,
                        oppNum: oppFull.myWinners, oppDen: oppFull.myWinners + oppFull.myUnforcedErrors),
                percent("Own Errors %",
                        meNum: meFull.myDoubleFaults + meFull.myUnforcedErrors,  meDen: meFull.lostPoints,
                        oppNum: oppFull.myDoubleFaults + oppFull.myUnforcedErrors, oppDen: oppFull.lostPoints)
            ], placeholder: nil))
        } else {
            sections.append(CmpSection(title: "Outcome Breakdown", rows: [],
                                       placeholder: "Outcome tracking not collected for this match."))
        }

        // Serve & Return — only when every point is categorised (mirrors iOS).
        if hasAll {
            sections.append(CmpSection(title: "Serve", rows: [
                percent("1st Serve In",
                        meNum: meFull.firstServeIn,  meDen: meFull.firstServeTotal,
                        oppNum: oppFull.firstServeIn, oppDen: oppFull.firstServeTotal),
                percent("2nd Serve In",
                        meNum: meFull.secondServeIn,  meDen: meFull.secondServeTotal,
                        oppNum: oppFull.secondServeIn, oppDen: oppFull.secondServeTotal),
                percent("1st Serve Win",
                        meNum: meFull.firstServeWins,  meDen: meFull.firstServeIn,
                        oppNum: oppFull.firstServeWins, oppDen: oppFull.firstServeIn),
                percent("2nd Serve Win",
                        meNum: meFull.secondServeWins,  meDen: meFull.secondServeIn,
                        oppNum: oppFull.secondServeWins, oppDen: oppFull.secondServeIn),
                percent("DF Rate (2nd)",
                        meNum: meFull.doubleFaults,  meDen: meFull.secondServeTotal,
                        oppNum: oppFull.doubleFaults, oppDen: oppFull.secondServeTotal)
            ], placeholder: nil))

            sections.append(CmpSection(title: "Return", rows: [
                percent("vs 1st Serve",
                        meNum: meFull.returnWinsOnFirst,  meDen: meFull.returnOppsOnFirst,
                        oppNum: oppFull.returnWinsOnFirst, oppDen: oppFull.returnOppsOnFirst),
                percent("vs 2nd Serve",
                        meNum: meFull.returnWinsOnSecond,  meDen: meFull.returnOppsOnSecond,
                        oppNum: oppFull.returnWinsOnSecond, oppDen: oppFull.returnOppsOnSecond)
            ], placeholder: nil))
        }

        // Break Points — always shown.
        sections.append(CmpSection(title: "Break Points", rows: [
            percent("BPs Won (Returner)",
                    meNum: meFull.breakPointWins,  meDen: meFull.breakPointOpps,
                    oppNum: oppFull.breakPointWins, oppDen: oppFull.breakPointOpps),
            percent("BPs Saved (Server)",
                    meNum: meFull.breakPointsFaced - meFull.breakPointsLost,  meDen: meFull.breakPointsFaced,
                    oppNum: oppFull.breakPointsFaced - oppFull.breakPointsLost, oppDen: oppFull.breakPointsFaced)
        ], placeholder: nil))

        // Pressure vs Normal
        if meFull.bigPointTotal > 0 && meFull.normalPointTotal > 0 {
            sections.append(CmpSection(title: "Pressure vs Normal", rows: [
                percent("Big Points",
                        meNum: meFull.bigPointWins,  meDen: meFull.bigPointTotal,
                        oppNum: oppFull.bigPointWins, oppDen: oppFull.bigPointTotal),
                percent("Normal Points",
                        meNum: meFull.normalPointWins,  meDen: meFull.normalPointTotal,
                        oppNum: oppFull.normalPointWins, oppDen: oppFull.normalPointTotal)
            ], placeholder: nil))
        }

        // Rally Depth Won
        if !meFull.rallyDepth.isEmpty {
            let rows = meFull.rallyDepth.map { meRd -> CmpRow in
                let oppRd = oppFull.rallyDepth.first { $0.shot == meRd.shot }
                return percent("@ \(meRd.shot.displayLabel)",
                               meNum: meRd.wins,  meDen: meRd.total,
                               oppNum: oppRd?.wins ?? 0, oppDen: oppRd?.total ?? 0)
            }
            sections.append(CmpSection(title: "Rally Depth Won", rows: rows, placeholder: nil))
        }

        // Score States
        if !meFull.scoreStates.isEmpty {
            let rows = meFull.scoreStates.map { meSs -> CmpRow in
                let oppSs = oppFull.scoreStates.first { $0.label == meSs.label }
                return percent(meSs.label,
                               meNum: meSs.wins,  meDen: meSs.total,
                               oppNum: oppSs?.wins ?? 0, oppDen: oppSs?.total ?? 0)
            }
            sections.append(CmpSection(title: "Score States", rows: rows, placeholder: nil))
        }

        let note = meFull.uncategorizedCount > 0
            ? "\(meFull.uncategorizedCount) uncategorized point(s) excluded from outcome stats."
            : nil
        return Comparison(hasAnyOutcomeData: hasAny, sections: sections, note: note)
    }

    // MARK: - Row builders (mirror MatchDetailView.comparisonRow / countComparisonRow)

    /// Percentage row: each side fills its half by `num/den`, with the raw
    /// count ("12/15") centred inside the bar; the side value shows the percent.
    private static func percent(_ label: String, subtitle: String? = nil,
                                meNum: Int, meDen: Int, oppNum: Int, oppDen: Int) -> CmpRow {
        let meFrac  = meDen  > 0 ? Double(meNum)  / Double(meDen)  : 0
        let oppFrac = oppDen > 0 ? Double(oppNum) / Double(oppDen) : 0
        return CmpRow(
            label: label, subtitle: subtitle, kind: .percent,
            meValue:  meDen  > 0 ? "\(Int((meFrac  * 100).rounded()))%" : "—",
            oppValue: oppDen > 0 ? "\(Int((oppFrac * 100).rounded()))%" : "—",
            meFraction: meFrac, oppFraction: oppFrac,
            meBarLabel:  meDen  > 0 ? "\(meNum)/\(meDen)"   : nil,
            oppBarLabel: oppDen > 0 ? "\(oppNum)/\(oppDen)" : nil
        )
    }

    /// Raw-count row: bars are scaled to the larger of the two counts so the
    /// taller side fills its half; the side values show the counts themselves.
    private static func count(_ label: String, _ meCount: Int, _ oppCount: Int) -> CmpRow {
        let maxVal = max(meCount, oppCount, 1)
        return CmpRow(
            label: label, subtitle: nil, kind: .count,
            meValue: "\(meCount)", oppValue: "\(oppCount)",
            meFraction: Double(meCount) / Double(maxVal),
            oppFraction: Double(oppCount) / Double(maxVal),
            meBarLabel: nil, oppBarLabel: nil
        )
    }
}
