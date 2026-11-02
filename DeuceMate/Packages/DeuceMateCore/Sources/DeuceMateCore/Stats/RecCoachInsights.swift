// Compact match coaching: rank supported observations, suppress overlapping
// advice, then show at most three. Rates use classified points with >=80%
// coverage of the relevant slice; an untracked default is not a first serve.
import Foundation

public enum RecCoachInsights {
    public enum SetScope: Sendable, Hashable {
        case all
        case set(Int)
    }

    // Scores are product heuristics (not predicted points recovered): severity
    // times a capped sample, plus an actionable-specificity weight. Exact
    // break-point losses get precedence over broad error summaries. Stable IDs
    // break ties. Topics prevent different descriptions of the same issue.
    struct Candidate {
        let id: String
        let score: Double
        let topics: Set<String>
        let line: String
    }

    /// Supply the FULL history, including unclassified points, so coverage and
    /// consecutive-point checks remain valid. Health advice requires an explicit
    /// singles match and the recorder's perspective; nil keeps health disabled.
    public static func generate(
        stats: [PointStat],
        focal: Player,
        setElapsedSeconds: [Int: TimeInterval] = [:],
        setScope: SetScope = .all,
        matchType: MatchType? = nil
    ) -> [String] {
        let scoped: [PointStat]
        switch setScope {
        case .all: scoped = stats
        case .set(let index): scoped = stats.filter { $0.setIndex == index }
        }
        let cat = scoped.filter { $0.outcome != .uncategorized }
        guard cat.count >= 20 else { return [] }
        let serves = cat.filter { $0.server == focal }
        let returns = cat.filter { $0.server != focal }
        let serveCoverage = covered(serves, within: scoped.filter { $0.server == focal })
        let returnCoverage = covered(returns, within: scoped.filter { $0.server != focal })
        var candidates: [Candidate] = []
        if let value = doubleFaults(scoped: scoped, cat: cat, focal: focal) { candidates.append(value) }
        if serveCoverage {
            if let value = firstServe(serves, focal: focal) { candidates.append(value) }
            if let value = secondServe(serves, focal: focal) { candidates.append(value) }
        }
        if serveCoverage && returnCoverage,
           let value = serveReturn(serves: serves, returns: returns, focal: focal) { candidates.append(value) }
        if returnCoverage { candidates += returnErrors(returns, focal: focal) }
        if let value = ownErrors(scoped: scoped, cat: cat, focal: focal) { candidates.append(value) }
        candidates += pressure(scoped: scoped, cat: cat, focal: focal)
        if let value = rallies(scoped: scoped, cat: cat, focal: focal) { candidates.append(value) }
        candidates += setChanges(stats, focal: focal, durations: setElapsedSeconds, scope: setScope)
        if focal == .me && matchType == .singles {
            candidates += exertion(scoped)
        }
        var topics: Set<String> = []
        var result: [String] = []
        for candidate in candidates.sorted(by: {
            $0.score == $1.score ? $0.id < $1.id : $0.score > $1.score
        }) where topics.isDisjoint(with: candidate.topics) {
            result.append(candidate.line)
            topics.formUnion(candidate.topics)
            if result.count == 3 { break }
        }
        return result
    }

    static func covered(_ known: [PointStat], within all: [PointStat]) -> Bool {
        !all.isEmpty && Double(known.count) / Double(all.count) >= 0.8
    }
    static func rate(_ points: [PointStat], focal: Player) -> Double {
        points.isEmpty ? 0 : Double(points.filter { $0.winner == focal }.count) / Double(points.count)
    }
    static func pct(_ value: Double) -> Int { Int((value * 100).rounded()) }
    static func firstIn(_ point: PointStat) -> Bool {
        !point.isSecondServe && point.outcome != .doubleFault
    }
    static func fraction(_ points: [PointStat], focal: Player) -> String {
        "\(pct(rate(points, focal: focal)))% (\(points.filter { $0.winner == focal }.count)/\(points.count))"
    }

    // MARK: - Double faults

    private static func doubleFaults(scoped: [PointStat], cat: [PointStat], focal: Player) -> Candidate? {
        let faults = cat.filter { $0.server == focal && $0.winner != focal && $0.outcome == .doubleFault }
        let count = faults.count
        let breaks = faults.filter { $0.isBreakPoint && $0.gameScoreAtStart?.isTiebreak != true }.count
        if breaks > 0 {
            let context = count == 1 ? "1 double fault on break point"
                : "\(count) double faults, including \(breaks) on break point\(breaks == 1 ? "" : "s")"
            return Candidate(id: "doubleFaults", score: 32 + Double(min(breaks, 5)),
                             topics: ["serveReliability", "errors", "pressureServe"],
                             line: "\(context) — practise your second-serve routine under pressure.")
        }
        let serving = cat.filter { $0.server == focal }
        guard covered(serving, within: scoped.filter { $0.server == focal }) else { return nil }
        let games = serviceGames(scoped, focal: focal)
        guard count >= 3, games >= 4, Double(count) / Double(games) >= 0.5 else { return nil }
        return Candidate(id: "doubleFaults", score: 18 + Double(min(count, 12)),
                         topics: ["serveReliability", "errors"],
                         line: "\(count) double faults in \(games) service games — practise a repeatable second-serve routine.")
    }

    private static func serviceGames(_ stats: [PointStat], focal: Player) -> Int {
        var games = 0
        var previous: PointStat?
        for point in stats.sorted(by: { $0.timestamp < $1.timestamp }) {
            defer { previous = point }
            guard point.server == focal, point.gameScoreAtStart?.isTiebreak != true else { continue }
            let startsGame = point.gameScoreAtStart.map { $0.server == 0 && $0.returner == 0 } ?? false
            if previous == nil || previous?.server != focal || previous?.setIndex != point.setIndex || startsGame {
                games += 1
            }
        }
        return games
    }

    // MARK: - First-serve consistency and second-serve effectiveness

    private static func firstServe(_ serves: [PointStat], focal: Player) -> Candidate? {
        guard serves.count >= 30 else { return nil }
        let landed = serves.filter(firstIn).count
        let inRate = Double(landed) / Double(serves.count)
        guard inRate < 0.5 else { return nil } // provisional product threshold, not a universal target
        let seconds = serves.filter { !firstIn($0) } // includes double faults
        let weakSecond = seconds.count >= 8 && rate(seconds, focal: focal) < 0.45
        let detail = weakSecond ? "; second-serve points won: \(fraction(seconds, focal: focal))" : ""
        let advice = weakSecond ? "try slightly less pace or a familiar spin serve."
            : "test a larger target and compare your service-point results."
        return Candidate(id: "firstServe", score: 10 + (0.5 - inRate) * Double(min(serves.count, 30)) + (weakSecond ? 14 : 0),
                         topics: weakSecond ? ["serveReliability", "secondServe"] : ["serveReliability"],
                         line: "First serves in: \(pct(inRate))% (\(landed)/\(serves.count))\(detail) — \(advice)")
    }

    private static func secondServe(_ serves: [PointStat], focal: Player) -> Candidate? {
        let first = serves.filter(firstIn)
        let second = serves.filter { $0.isSecondServe && $0.outcome != .doubleFault }
        let gap = rate(first, focal: focal) - rate(second, focal: focal)
        guard first.count >= 8, second.count >= 8, gap >= 0.2 else { return nil }
        return Candidate(id: "secondServe", score: 10 + gap * Double(min(first.count, second.count, 30)),
                         topics: ["secondServe"],
                         line: "Points won: \(fraction(first, focal: focal)) on first serve vs \(fraction(second, focal: focal)) on second serves in play — review spin, placement and next-shot preparation.")
    }

    // MARK: - Serve / return balance and return errors

    private static func serveReturn(serves: [PointStat], returns: [PointStat], focal: Player) -> Candidate? {
        let gap = rate(serves, focal: focal) - rate(returns, focal: focal)
        guard serves.count >= 20, returns.count >= 20, gap >= 0.25 else { return nil }
        return Candidate(id: "serveReturn", score: 8 + gap * Double(min(serves.count, returns.count, 30)),
                         topics: ["returnPlay"],
                         line: "Points won: \(fraction(serves, focal: focal)) serving vs \(fraction(returns, focal: focal)) receiving — review returns and following rallies; the gap alone does not explain why.")
    }

    private static func returnErrors(_ returns: [PointStat], focal: Player) -> [Candidate] {
        let known = returns.filter { $0.endingShot != nil }
        guard covered(known, within: returns) else { return [] }
        var result: [Candidate] = []
        // Aces and double faults are not return attempts. A missed return needs
        // both its ending phase and the receiver's unforced-error loss.
        let attempts = known.filter { $0.endingShot != .serve && $0.outcome != .doubleFault }
        let misses = attempts.filter { $0.winner != focal && $0.outcome == .unforcedError && $0.endingShot == .return }.count
        if attempts.count >= 10, misses >= 3, Double(misses) / Double(attempts.count) >= 0.25 {
            result.append(Candidate(id: "missedReturns", score: 18 + Double(min(misses, 15)),
                                    topics: ["returnPlay", "errors"],
                                    line: "\(misses)/\(attempts.count) tracked return attempts ended in an unforced error — review return position, split-step timing and preparation."))
        }
        let losses = known.filter { $0.winner != focal }
        let rallyErrors = losses.filter {
            $0.outcome == .unforcedError && ($0.endingShot == .servePlusOne || $0.endingShot == .rally)
        }.count
        if losses.count >= 10, Double(rallyErrors) / Double(losses.count) >= 0.4 {
            result.append(Candidate(id: "returnRallyErrors", score: 16 + Double(min(rallyErrors, 15)),
                                    topics: ["returnPlay", "errors", "rally"],
                                    line: "\(rallyErrors)/\(losses.count) tracked losses while receiving were unforced errors after the return — review recovery position, spacing and shot selection."))
        }
        return result
    }

    // MARK: - General errors, pressure and rally phases

    private static func ownErrors(scoped: [PointStat], cat: [PointStat], focal: Player) -> Candidate? {
        let lost = cat.filter { $0.winner != focal }
        let errors = lost.filter { $0.outcome == .unforcedError || ($0.outcome == .doubleFault && $0.server == focal) }.count
        guard cat.count >= 25, lost.count >= 15,
              covered(lost, within: scoped.filter { $0.winner != focal }),
              Double(errors) / Double(lost.count) >= 0.55 else { return nil }
        return Candidate(id: "ownErrors", score: 4 + Double(errors) / Double(lost.count) * 15,
                         topics: ["errors", "rally"],
                         line: "\(pct(Double(errors) / Double(lost.count)))% of classified losses were unforced errors or double faults (\(errors)/\(lost.count)) — review preparation, spacing and shot selection.")
    }

    private static func pressure(scoped: [PointStat], cat: [PointStat], focal: Player) -> [Candidate] {
        [true, false].compactMap { serving in
            let side = cat.filter { ($0.server == focal) == serving }
            let known = side.filter { $0.isBreakPoint || $0.gameScoreAtStart != nil }
            let allSide = scoped.filter { ($0.server == focal) == serving }
            guard covered(known, within: allSide) else { return nil }
            func isPressure(_ point: PointStat) -> Bool {
                point.isBreakPoint || point.gameScoreAtStart.map { $0.isTiebreak || ($0.server >= 3 && $0.returner >= 3) } == true
            }
            let big = known.filter(isPressure)
            let ordinary = known.filter { !isPressure($0) }
            let gap = rate(ordinary, focal: focal) - rate(big, focal: focal)
            guard big.count >= 8, ordinary.count >= 15, gap >= 0.2 else { return nil }
            return Candidate(id: serving ? "pressureServe" : "pressureReturn", score: 10 + gap * Double(min(big.count, ordinary.count, 30)),
                             topics: ["pressure", serving ? "pressureServe" : "returnPlay"],
                             line: "\(serving ? "Serving" : "Receiving"): \(fraction(big, focal: focal)) points won under pressure vs \(fraction(ordinary, focal: focal)) otherwise — use your usual routine and a clear target.")
        }
    }

    private static func rallies(scoped: [PointStat], cat: [PointStat], focal: Player) -> Candidate? {
        let serves = scoped.filter { $0.server == focal }
        let known = cat.filter { $0.server == focal && $0.endingShot != nil }
        guard covered(known, within: serves) else { return nil }
        let early = known.filter { $0.endingShot == .servePlusOne }
        let later = known.filter { $0.endingShot == .rally }
        let gap = rate(early, focal: focal) - rate(later, focal: focal)
        guard early.count >= 8, later.count >= 8, gap >= 0.15 else { return nil }
        return Candidate(id: "rallies", score: 6 + gap * Double(min(early.count, later.count, 25)),
                         topics: ["rally"],
                         line: "On serve, you won \(fraction(early, focal: focal)) points ending at Serve+1 vs \(fraction(later, focal: focal)) in the rally phase — review how rallies were lost before changing tactics.")
    }

    // MARK: - One observation per set transition, without a fatigue diagnosis

    private static func setChanges(_ stats: [PointStat], focal: Player, durations: [Int: TimeInterval], scope: SetScope) -> [Candidate] {
        let laterSets: [Int]
        switch scope {
        case .all: laterSets = Set(stats.map(\.setIndex)).filter { $0 > 0 }.sorted()
        case .set(let index): laterSets = index > 0 ? [index] : []
        }
        return laterSets.compactMap { later in
            let earlier = later - 1
            let firstAll = stats.filter { $0.setIndex == earlier }
            let secondAll = stats.filter { $0.setIndex == later }
            let first = firstAll.filter { $0.outcome != .uncategorized }
            let second = secondAll.filter { $0.outcome != .uncategorized }
            let firstLost = first.filter { $0.winner != focal }
            let secondLost = second.filter { $0.winner != focal }
            let r1 = firstLost.isEmpty ? 0 : Double(firstLost.filter { $0.outcome == .unforcedError }.count) / Double(firstLost.count)
            let r2 = secondLost.isEmpty ? 0 : Double(secondLost.filter { $0.outcome == .unforcedError }.count) / Double(secondLost.count)
            let errorRise = firstLost.count >= 12 && secondLost.count >= 12 && r2 - r1 >= 0.1 && r2 >= 0.25
                && covered(firstLost, within: firstAll.filter { $0.winner != focal })
                && covered(secondLost, within: secondAll.filter { $0.winner != focal })
            let winDrop = rate(firstAll, focal: focal) - rate(secondAll, focal: focal)
            let duration = durations[earlier] ?? 0
            let decline = duration >= 1800 && durations[later] != nil && firstAll.count >= 20 && secondAll.count >= 20 && winDrop >= 0.15
            guard errorRise || decline else { return nil }
            var facts: [String] = []
            if errorRise { facts.append("Unforced errors rose from \(pct(r1))% in set \(earlier + 1) to \(pct(r2))% in set \(later + 1) as a share of classified losses") }
            if decline {
                let prefix = errorRise ? "points won fell" : "After a \(Int(duration / 60))-minute set \(earlier + 1), points won fell"
                facts.append("\(prefix) from \(pct(rate(firstAll, focal: focal)))% to \(pct(rate(secondAll, focal: focal)))% in set \(later + 1)")
            }
            return Candidate(id: "setChange\(later)", score: 8 + max(errorRise ? r2 - r1 : 0, decline ? winDrop : 0) * 25,
                             topics: errorRise ? ["setChange", "errors"] : ["setChange"],
                             line: facts.joined(separator: "; ") + " — review preparation, positioning and shot selection.")
        }
    }
}
