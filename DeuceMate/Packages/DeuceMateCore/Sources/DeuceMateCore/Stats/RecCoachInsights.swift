// RecCoachInsights.swift — deterministic rule engine that surfaces
// high-leverage observations for recreational players without requiring
// heart-rate data. Complements PulseCoachInsights (HR-gated) so iPhone-only
// users still get coaching.
//
// UE-rate convention: per-set unforced-error rate is computed as the share
// of own losses that were unforced errors (setUEs / setFocalLostPoints),
// not as a share of all points or all categorized points. This mirrors how
// recreational players think about "errors as a fraction of points I gave
// away," which is the metric the engine is meant to highlight.
//
// Set scoping: callers pass the full match's points plus a `SetScope`. With
// `.all` the engine looks at the whole match; with `.set(i)` the single-set
// rules are restricted to that set and the cross-set fatigue rules compare
// the selected set against the one before it. This lets the same engine back
// the "All / Set 1 / Set 2" filter shown above Coaching Insights.
import Foundation

public enum RecCoachInsights {

    /// Which slice of the match the insights should describe.
    public enum SetScope: Sendable, Hashable {
        /// The whole match.
        case all
        /// A single set, identified by its zero-based index.
        case set(Int)
    }

    /// Returns up to three short coaching sentences derived from
    /// point-level outcome data. Always returns an empty array when there is
    /// insufficient data so callers can safely treat empty as "hide the
    /// section." Insights are emitted in priority order:
    ///   1. self-inflicted-loss share
    ///   2. per-set UE drift (HR-free fatigue proxy)
    ///   3. double-fault leakage
    ///   4. pressure-point performance drop
    ///   5. shorten-the-points (rally length)
    ///   6. second-serve vulnerability
    ///   7. return unforced errors
    ///   8. set-duration energy decline
    ///
    /// - Parameters:
    ///   - stats: the full match's points. The engine slices them itself
    ///     based on `setScope`, so callers should not pre-filter.
    ///   - setScope: `.all` for the whole match, or `.set(i)` to scope the
    ///     single-set rules to set `i` and retarget the cross-set fatigue
    ///     rules to the `i-1 → i` transition. Cross-set rules are suppressed
    ///     for `.set(0)` since there is no preceding set.
    public static func generate(
        stats: [PointStat],
        focal: Player,
        setElapsedSeconds: [Int: TimeInterval] = [:],
        setScope: SetScope = .all
    ) -> [String] {
        let other: Player = focal == .me ? .opponent : .me

        // Points in scope for the single-set rules.
        let scopedStats: [PointStat]
        // The pair of set indices the cross-set fatigue rules compare.
        let earlierSet: Int
        let laterSet: Int
        // Cross-set rules need a preceding set to compare against.
        let crossSetEnabled: Bool
        switch setScope {
        case .all:
            scopedStats = stats
            earlierSet = 0
            laterSet = 1
            crossSetEnabled = true
        case .set(let i):
            scopedStats = stats.filter { $0.setIndex == i }
            earlierSet = i - 1
            laterSet = i
            crossSetEnabled = i >= 1
        }

        let categorized = scopedStats.filter { $0.outcome != .uncategorized }
        guard categorized.count >= 20 else { return [] }

        // Cross-set rules always reason over the whole match so they can see
        // both the earlier and later set regardless of the single-set scope.
        let fullCategorized = stats.filter { $0.outcome != .uncategorized }

        var insights: [String] = []

        if let line = selfInflictedInsight(categorized: categorized, focal: focal, other: other) {
            insights.append(line)
        }
        if crossSetEnabled,
           let line = perSetUEDriftInsight(
               categorized: fullCategorized,
               focal: focal,
               other: other,
               earlierSet: earlierSet,
               laterSet: laterSet
           ) {
            insights.append(line)
        }
        if let line = doubleFaultInsight(stats: scopedStats, categorized: categorized, focal: focal) {
            insights.append(line)
        }
        if let line = pressurePointDropInsight(categorized: categorized, focal: focal) {
            insights.append(line)
        }
        if let line = rallyLengthInsight(stats: scopedStats, focal: focal) {
            insights.append(line)
        }
        if let line = secondServeVulnerabilityInsight(stats: scopedStats, focal: focal) {
            insights.append(line)
        }
        if let line = returnUnforcedErrorInsight(categorized: categorized, focal: focal, other: other) {
            insights.append(line)
        }
        if crossSetEnabled,
           let line = setDurationDeclineInsight(
               stats: stats,
               focal: focal,
               setElapsedSeconds: setElapsedSeconds,
               earlierSet: earlierSet,
               laterSet: laterSet
           ) {
            insights.append(line)
        }

        return Array(insights.prefix(3))
    }

    // MARK: - Rule 1: self-inflicted-loss share

    private static func selfInflictedInsight(
        categorized: [PointStat],
        focal: Player,
        other: Player
    ) -> String? {
        guard categorized.count >= 25 else { return nil }
        let lost = categorized.filter { $0.winner == other }
        guard lost.count >= 15 else { return nil }
        let selfInflicted = lost.filter {
            $0.outcome == .unforcedError ||
            ($0.outcome == .doubleFault && $0.server == focal)
        }.count
        let share = Double(selfInflicted) / Double(lost.count)
        guard share >= 0.55 else { return nil }
        let pct = Int((share * 100).rounded())
        return "\(pct)% of points you lost were unforced errors or double faults (\(selfInflicted)/\(lost.count)) — reliability is your biggest lever."
    }

    // MARK: - Rule 2: per-set UE drift

    private static func perSetUEDriftInsight(
        categorized: [PointStat],
        focal: Player,
        other: Player,
        earlierSet: Int,
        laterSet: Int
    ) -> String? {
        let set1 = categorized.filter { $0.setIndex == earlierSet }
        let set2 = categorized.filter { $0.setIndex == laterSet }
        let set1Lost = set1.filter { $0.winner == other }
        let set2Lost = set2.filter { $0.winner == other }
        guard set1Lost.count >= 12, set2Lost.count >= 12 else { return nil }
        let set1UE = set1Lost.filter { $0.outcome == .unforcedError }.count
        let set2UE = set2Lost.filter { $0.outcome == .unforcedError }.count
        let r1 = Double(set1UE) / Double(set1Lost.count)
        let r2 = Double(set2UE) / Double(set2Lost.count)
        guard r2 - r1 >= 0.10, r2 >= 0.25 else { return nil }
        let p1 = Int((r1 * 100).rounded())
        let p2 = Int((r2 * 100).rounded())
        return "Your unforced-error rate climbed from \(p1)% in set \(earlierSet + 1) to \(p2)% in set \(laterSet + 1) — fatigue may be changing your shot selection."
    }

    // MARK: - Rule 3: double-fault leakage

    private static func doubleFaultInsight(
        stats: [PointStat],
        categorized: [PointStat],
        focal: Player
    ) -> String? {
        let dfs = categorized.filter { $0.server == focal && $0.outcome == .doubleFault }.count
        guard dfs >= 3 else { return nil }
        let games = focalServiceGames(stats: stats, focal: focal)
        guard games >= 4 else { return nil }
        let perGame = Double(dfs) / Double(games)
        guard perGame >= 0.5 else { return nil }
        return "\(dfs) double faults in \(games) service games — each one is a free point at the worst time."
    }

    // MARK: - Rule 4: pressure-point drop

    private static func pressurePointDropInsight(
        categorized: [PointStat],
        focal: Player
    ) -> String? {
        let isBig: (PointStat) -> Bool = { pt in
            if pt.isBreakPoint { return true }
            guard let g = pt.gameScoreAtStart else { return false }
            return g.isTiebreak || (g.server >= 3 && g.returner >= 3)
        }
        let bigPts    = categorized.filter(isBig)
        let normalPts = categorized.filter { !isBig($0) }
        guard bigPts.count >= 8, normalPts.count >= 15 else { return nil }
        let bigRate    = Double(bigPts.filter    { $0.winner == focal }.count) / Double(bigPts.count)
        let normalRate = Double(normalPts.filter { $0.winner == focal }.count) / Double(normalPts.count)
        guard normalRate - bigRate >= 0.20 else { return nil }
        let bigPct    = Int((bigRate    * 100).rounded())
        let normalPct = Int((normalRate * 100).rounded())
        return "You won \(normalPct)% of normal points but only \(bigPct)% on big points (break/deuce/tiebreak) — try playing the same ball you'd hit at 0-0."
    }

    // MARK: - Rule 5: rally-length / shorten-the-points

    private static func rallyLengthInsight(
        stats: [PointStat],
        focal: Player
    ) -> String? {
        let withShot = stats.filter { $0.endingShot != nil }
        let s1Pts = withShot.filter { $0.endingShot == .servePlusOne }
        let rallyPts = withShot.filter { $0.endingShot == .rally }
        guard s1Pts.count >= 8, rallyPts.count >= 8 else { return nil }
        let s1Rate = Double(s1Pts.filter { $0.winner == focal }.count) / Double(s1Pts.count)
        let rallyRate = Double(rallyPts.filter { $0.winner == focal }.count) / Double(rallyPts.count)
        guard s1Rate - rallyRate >= 0.15 else { return nil }
        let a = Int((s1Rate * 100).rounded())
        let b = Int((rallyRate * 100).rounded())
        return "You won \(a)% of points ending by Serve+1 but only \(b)% in long rallies — try to finish earlier."
    }

    // MARK: - Rule 6: second-serve vulnerability

    private static func secondServeVulnerabilityInsight(
        stats: [PointStat],
        focal: Player
    ) -> String? {
        let focalServes  = stats.filter { $0.server == focal }
        let firstSrvPts  = focalServes.filter { !$0.isSecondServe }
        // Exclude double faults — the denominator should be second-serve points in play.
        let secondSrvPts = focalServes.filter { $0.isSecondServe && $0.outcome != .doubleFault }
        guard firstSrvPts.count >= 8, secondSrvPts.count >= 8 else { return nil }
        let firstRate  = Double(firstSrvPts.filter  { $0.winner == focal }.count) / Double(firstSrvPts.count)
        let secondRate = Double(secondSrvPts.filter { $0.winner == focal }.count) / Double(secondSrvPts.count)
        guard firstRate - secondRate >= 0.20 else { return nil }
        let firstPct  = Int((firstRate  * 100).rounded())
        let secondPct = Int((secondRate * 100).rounded())
        return "You won \(firstPct)% on 1st serve but only \(secondPct)% on 2nd serve (\(secondSrvPts.count) points) — a slower, spin-heavy 2nd serve keeps you in the point."
    }

    // MARK: - Rule 7: return unforced errors

    private static func returnUnforcedErrorInsight(
        categorized: [PointStat],
        focal: Player,
        other: Player
    ) -> String? {
        let returnLosses = categorized.filter { $0.server == other && $0.winner == other }
        guard returnLosses.count >= 10 else { return nil }
        let returnUEs = returnLosses.filter { $0.outcome == .unforcedError }.count
        let share = Double(returnUEs) / Double(returnLosses.count)
        guard share >= 0.40 else { return nil }
        let pct = Int((share * 100).rounded())
        return "\(pct)% of your return losses (\(returnUEs)/\(returnLosses.count)) were unforced errors — aim for a safe, deep crosscourt return instead of going for the lines."
    }

    // MARK: - Rule 8: set-duration energy decline

    private static func setDurationDeclineInsight(
        stats: [PointStat],
        focal: Player,
        setElapsedSeconds: [Int: TimeInterval],
        earlierSet: Int,
        laterSet: Int
    ) -> String? {
        guard let earlierDuration = setElapsedSeconds[earlierSet],
              setElapsedSeconds[laterSet] != nil,
              earlierDuration >= 30 * 60 else { return nil }
        let set1 = stats.filter { $0.setIndex == earlierSet }
        let set2 = stats.filter { $0.setIndex == laterSet }
        guard set1.count >= 20, set2.count >= 20 else { return nil }
        let r1 = Double(set1.filter { $0.winner == focal }.count) / Double(set1.count)
        let r2 = Double(set2.filter { $0.winner == focal }.count) / Double(set2.count)
        guard r1 - r2 >= 0.15 else { return nil }
        let minutes = Int((earlierDuration / 60).rounded())
        let p1 = Int((r1 * 100).rounded())
        let p2 = Int((r2 * 100).rounded())
        return "After a \(minutes)-minute set \(earlierSet + 1), your set \(laterSet + 1) win rate dropped from \(p1)% to \(p2)%."
    }

    // MARK: - Helpers

    /// Count completed focal service games by walking points in time order and
    /// incrementing each time the server changes from focal to other (i.e. the
    /// previous focal service game ended). A trailing focal service game is
    /// counted only if it had at least one point.
    private static func focalServiceGames(stats: [PointStat], focal: Player) -> Int {
        let sorted = stats.sorted { $0.timestamp < $1.timestamp }
        var games = 0
        var inFocalGame = false
        for pt in sorted {
            if pt.server == focal {
                if !inFocalGame { inFocalGame = true }
            } else if inFocalGame {
                games += 1
                inFocalGame = false
            }
        }
        if inFocalGame { games += 1 }
        return games
    }
}
