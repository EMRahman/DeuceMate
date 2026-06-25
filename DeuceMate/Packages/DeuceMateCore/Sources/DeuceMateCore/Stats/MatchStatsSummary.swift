// MatchStatsSummary.swift — pure derivation of all statistics shown in the
// match stats views. Platform-neutral: no SwiftUI, no UIKit, no WatchKit.
import Foundation

/// All statistics derived from a collection of `PointStat`s for one focal
/// player. Computed once and consumed by both the watchOS and iOS stats views,
/// guaranteeing metric parity by construction.
public struct MatchStatsSummary: Sendable {

    // MARK: - Points

    public let totalPoints: Int
    public let pointsWon: Int

    // MARK: - Service

    public let firstServeTotal: Int
    public let firstServeIn: Int
    public let firstServeWins: Int
    public let secondServeTotal: Int
    public let secondServeIn: Int
    public let secondServeWins: Int
    public let doubleFaults: Int

    // MARK: - Return

    public let returnOppsOnFirst: Int
    public let returnWinsOnFirst: Int
    public let returnOppsOnSecond: Int
    public let returnWinsOnSecond: Int

    // MARK: - Break Points

    public let breakPointOpps: Int       // as returner
    public let breakPointWins: Int       // as returner
    public let breakPointsFaced: Int     // as server
    public let breakPointsLost: Int      // as server

    // MARK: - Outcome breakdown

    public let lostPoints: Int
    public let myDoubleFaults: Int
    public let myUnforcedErrors: Int
    public let myForcedErrors: Int
    public let opponentWinners: Int

    public let wonPoints: Int
    public let opponentDoubleFaults: Int
    public let opponentUnforcedErrors: Int
    public let opponentForcedErrors: Int
    public let myWinners: Int

    public let uncategorizedCount: Int

    // MARK: - Derived coaching metrics

    /// Winners-to-unforced-errors ratio as a formatted string.
    public let wueRatio: String
    /// Of all aggressive outcomes (W + UE), what fraction were winners.
    public let aggressionIndex: String
    /// Fraction of lost points that were self-inflicted (DF + UE).
    public let ownErrorsPct: String

    // MARK: - Pressure / normal

    public let bigPointTotal: Int
    public let bigPointWins: Int
    public let normalPointTotal: Int
    public let normalPointWins: Int

    // MARK: - Rally depth (optional — nil if no endingShot data)

    public struct RallyDepthStat: Sendable {
        public let shot: EndingShot
        public let total: Int
        public let wins: Int
    }
    public let rallyDepth: [RallyDepthStat]

    // MARK: - Score-state win rates (optional — nil if no gameScoreAtStart data)

    public struct ScoreStateStat: Sendable {
        public let label: String
        public let total: Int
        public let wins: Int
    }
    public let scoreStates: [ScoreStateStat]

    // MARK: - Set durations

    public let setElapsedSeconds: [Int: TimeInterval]

    // MARK: - Heart rate (optional — empty if no heartRateBPM data on points)

    public struct ZoneWinRate: Sendable {
        public let zone: HRZone
        public let total: Int
        public let wins: Int
    }

    public struct HRPoint: Sendable {
        public let pointIndex: Int
        public let bpm: Int
        public let setIndex: Int
        public let wonByFocal: Bool
    }

    public let zoneWinRates: [ZoneWinRate]
    public let hrTimeline: [HRPoint]
    public let resolvedMaxHR: Int
    public let autoInsights: [String]

    // MARK: - Steps / movement (optional — empty if no stepsCumulative data)

    /// One sample per point that carried a `stepsCumulative` reading, ordered
    /// chronologically. `perPointSteps` is that point's movement load (steps
    /// taken during the point); `cumulative` is the match-start running total.
    public struct StepPoint: Sendable {
        public let pointIndex: Int
        public let perPointSteps: Int
        public let cumulative: Int
        public let setIndex: Int
        public let wonByFocal: Bool
    }

    public let stepsTimeline: [StepPoint]
    public let stepsInsights: [String]

    // MARK: - Recreational-player coaching (HR-independent)

    public let recCoachInsights: [String]

    // MARK: - Init

    public init(
        stats: [PointStat],
        focal: Player,
        setElapsedSeconds: [Int: TimeInterval] = [:],
        maxHR: Int = 190
    ) {
        let other: Player = focal == .me ? .opponent : .me

        let categorized = stats.filter { $0.outcome != .uncategorized }
        let uncatCount  = stats.count - categorized.count

        // Points
        let pWon  = stats.filter { $0.winner == focal }.count
        let pLost = stats.filter { $0.winner == other }.count

        // Service
        // A PointStat with `isSecondServe == true` represents a point where the
        // first serve missed and the rally was played on the second serve. So
        // every service point is one first-serve attempt; the ones decided with
        // `!isSecondServe` are the first serves that landed in.
        let focalServes  = stats.filter { $0.server == focal }
        let firstSvcIn   = focalServes.filter { !$0.isSecondServe }
        let firstSvcWins = firstSvcIn.filter { $0.winner == focal }.count
        let secondSvcPts = focalServes.filter { $0.isSecondServe }
        let secondSvcIn  = secondSvcPts.filter { $0.outcome != .doubleFault }.count
        let secondSvcWins = secondSvcPts.filter { $0.winner == focal }.count
        let df = categorized.filter { $0.server == focal && $0.outcome == .doubleFault }.count

        // Return
        let otherFirst      = stats.filter { $0.server == other && !$0.isSecondServe }
        let retWinFirst     = otherFirst.filter { $0.winner == focal }.count
        let otherSecond     = stats.filter { $0.server == other && $0.isSecondServe }
        let retWinSecond    = otherSecond.filter { $0.winner == focal }.count

        // Break points
        let bpAsReturner    = stats.filter { $0.server == other && $0.isBreakPoint }
        let bpWon           = bpAsReturner.filter { $0.winner == focal }.count
        let bpAsServer      = stats.filter { $0.server == focal && $0.isBreakPoint }
        let bpLost          = bpAsServer.filter { $0.winner == other }.count

        // Outcome breakdown
        let myUE   = categorized.filter { $0.winner == other && $0.outcome == .unforcedError }.count
        let myFE   = categorized.filter { $0.winner == other && $0.outcome == .forcedError }.count
        let oppW   = categorized.filter { $0.winner == other && $0.outcome == .winner }.count
        let oppDF  = categorized.filter { $0.server == other && $0.outcome == .doubleFault }.count
        let oppUE  = categorized.filter { $0.winner == focal && $0.outcome == .unforcedError }.count
        let oppFE  = categorized.filter { $0.winner == focal && $0.outcome == .forcedError }.count
        let myW    = categorized.filter { $0.winner == focal && $0.outcome == .winner }.count

        // Coaching metrics
        let wueStr: String = {
            if myW == 0 && myUE == 0 { return "—" }
            guard myUE > 0 else { return "∞ : 1" }
            return String(format: "%.1f : 1", Double(myW) / Double(myUE))
        }()
        let aggrStr = Self.pct(num: myW, den: myW + myUE)
        let ownErrStr = Self.pct(num: df + myUE, den: pLost)

        // Pressure
        let isBig: (PointStat) -> Bool = { pt in
            if pt.isBreakPoint { return true }
            guard let g = pt.gameScoreAtStart else { return false }
            return g.isTiebreak || (g.server >= 3 && g.returner >= 3)
        }
        let bigPts    = stats.filter(isBig)
        let bigWins   = bigPts.filter { $0.winner == focal }.count
        let normalPts = stats.filter { !isBig($0) }
        let normalWins = normalPts.filter { $0.winner == focal }.count

        // Rally depth
        let shotPts = stats.filter { $0.endingShot != nil }
        let rallyStats: [RallyDepthStat] = EndingShot.allCases.compactMap { shot in
            let pts = shotPts.filter { $0.endingShot == shot }
            guard !pts.isEmpty else { return nil }
            return RallyDepthStat(
                shot: shot,
                total: pts.count,
                wins: pts.filter { $0.winner == focal }.count
            )
        }

        // Score states
        let scorePts = stats.filter { $0.gameScoreAtStart != nil }
        var scoreStateStats: [ScoreStateStat] = []
        let thirtyAll = scorePts.filter {
            guard let g = $0.gameScoreAtStart else { return false }
            return !g.isTiebreak && g.server == 2 && g.returner == 2
        }
        if !thirtyAll.isEmpty {
            scoreStateStats.append(ScoreStateStat(
                label: "At 30-All",
                total: thirtyAll.count,
                wins: thirtyAll.filter { $0.winner == focal }.count
            ))
        }
        let deuceAd = scorePts.filter {
            guard let g = $0.gameScoreAtStart else { return false }
            return !g.isTiebreak && g.server >= 3 && g.returner >= 3
        }
        if !deuceAd.isEmpty {
            scoreStateStats.append(ScoreStateStat(
                label: "At Deuce/Ad",
                total: deuceAd.count,
                wins: deuceAd.filter { $0.winner == focal }.count
            ))
        }
        let tbPts = scorePts.filter { $0.gameScoreAtStart?.isTiebreak == true }
        if !tbPts.isEmpty {
            scoreStateStats.append(ScoreStateStat(
                label: "In Tiebreak",
                total: tbPts.count,
                wins: tbPts.filter { $0.winner == focal }.count
            ))
        }

        // Assign
        totalPoints = stats.count
        pointsWon = pWon
        firstServeTotal = focalServes.count
        firstServeIn = firstSvcIn.count
        firstServeWins = firstSvcWins
        secondServeTotal = secondSvcPts.count
        secondServeIn = secondSvcIn
        secondServeWins = secondSvcWins
        doubleFaults = df
        returnOppsOnFirst = otherFirst.count
        returnWinsOnFirst = retWinFirst
        returnOppsOnSecond = otherSecond.count
        returnWinsOnSecond = retWinSecond
        breakPointOpps = bpAsReturner.count
        breakPointWins = bpWon
        breakPointsFaced = bpAsServer.count
        breakPointsLost = bpLost
        lostPoints = pLost
        myDoubleFaults = df
        myUnforcedErrors = myUE
        myForcedErrors = myFE
        opponentWinners = oppW
        wonPoints = pWon
        opponentDoubleFaults = oppDF
        opponentUnforcedErrors = oppUE
        opponentForcedErrors = oppFE
        myWinners = myW
        uncategorizedCount = uncatCount
        wueRatio = wueStr
        aggressionIndex = aggrStr
        ownErrorsPct = ownErrStr
        bigPointTotal = bigPts.count
        bigPointWins = bigWins
        normalPointTotal = normalPts.count
        normalPointWins = normalWins
        rallyDepth = rallyStats
        scoreStates = scoreStateStats
        self.setElapsedSeconds = setElapsedSeconds

        // Heart rate aggregations
        let hrStats = stats.compactMap { pt -> (PointStat, Int)? in
            guard let bpm = pt.heartRateBPM, bpm > 0 else { return nil }
            return (pt, bpm)
        }
        if hrStats.isEmpty {
            zoneWinRates = []
            hrTimeline = []
        } else {
            // Win rate per zone
            var byZone: [HRZone: (total: Int, wins: Int)] = [:]
            for (pt, bpm) in hrStats {
                let z = HRZone.zone(forBPM: bpm, maxHR: maxHR)
                var entry = byZone[z] ?? (0, 0)
                entry.total += 1
                if pt.winner == focal { entry.wins += 1 }
                byZone[z] = entry
            }
            zoneWinRates = HRZone.allCases.compactMap { z in
                guard let e = byZone[z] else { return nil }
                return ZoneWinRate(zone: z, total: e.total, wins: e.wins)
            }

            // Timeline (point-indexed, sorted by timestamp)
            let sorted = hrStats.sorted { $0.0.timestamp < $1.0.timestamp }
            hrTimeline = sorted.enumerated().map { idx, pair in
                HRPoint(
                    pointIndex: idx,
                    bpm: pair.1,
                    setIndex: pair.0.setIndex,
                    wonByFocal: pair.0.winner == focal
                )
            }
        }
        resolvedMaxHR = maxHR
        autoInsights = PulseCoachInsights.generate(
            stats: stats,
            focal: focal,
            maxHR: maxHR
        )

        // Step (movement) aggregations — one sampled-and-sorted pass produces
        // the per-point loads; feed the timeline straight to the rule engine.
        let stepLoads = Self.sampledStepLoads(stats)
        stepsTimeline = stepLoads.enumerated().map { idx, entry in
            StepPoint(
                pointIndex: idx,
                perPointSteps: entry.perPointSteps,
                cumulative: entry.point.stepsCumulative ?? 0,
                setIndex: entry.point.setIndex,
                wonByFocal: entry.point.winner == focal
            )
        }
        stepsInsights = StepsCoachInsights.generate(timeline: stepsTimeline)

        recCoachInsights = RecCoachInsights.generate(
            stats: stats,
            focal: focal,
            setElapsedSeconds: setElapsedSeconds
        )
    }

    // MARK: - Steps helpers

    /// Sampled points (those carrying a `stepsCumulative` reading), ordered
    /// chronologically, each paired with its per-point step load — the steps
    /// taken since the previous sample. The first sample is the **baseline**
    /// and carries a load of 0: we measure movement *since the previous
    /// sample*, and the first has no predecessor, so its accumulated steps are
    /// never dumped onto a single point (which would skew the table, averages,
    /// and insights when step sampling starts a few points into the match).
    /// Later deltas are clamped non-negative so sample jitter can't go below 0.
    /// Single source of the per-point figure, reused by `perPointStepDeltas`
    /// (id-keyed, for the exporter table) and `stepsTimeline` (ordered).
    private static func sampledStepLoads(_ stats: [PointStat]) -> [(point: PointStat, perPointSteps: Int)] {
        let sampled = stats
            .filter { $0.stepsCumulative != nil }
            .sorted { $0.timestamp < $1.timestamp }
        var prev: Int?
        return sampled.map { pt in
            let cum = pt.stepsCumulative ?? 0
            let load = prev.map { max(0, cum - $0) } ?? 0
            prev = max(prev ?? cum, cum)
            return (pt, load)
        }
    }

    /// Per-point movement load keyed by `PointStat.id` so the text exporter's
    /// raw point table can show a per-point figure on each row in match order;
    /// `stepsTimeline` carries the same values in chronological order for the
    /// stats/insights path.
    public static func perPointStepDeltas(_ stats: [PointStat]) -> [UUID: Int] {
        Dictionary(uniqueKeysWithValues: sampledStepLoads(stats).map { ($0.point.id, $0.perPointSteps) })
    }

    /// Mean per-point step load over a slice of the step timeline, rounded to
    /// the nearest whole step. Lives in Core so every surface (text export, and
    /// any future view) reports the same figure. Returns 0 for an empty slice.
    public static func averageSteps(_ points: [StepPoint]) -> Int {
        guard !points.isEmpty else { return 0 }
        let total = points.reduce(0) { $0 + $1.perPointSteps }
        return Int((Double(total) / Double(points.count)).rounded())
    }

    // MARK: - Formatting helpers

    public static func pct(num: Int, den: Int) -> String {
        guard den > 0 else { return "—" }
        let p = Int((Double(num) / Double(den)) * 100.0)
        return "\(p)% (\(num)/\(den))"
    }
}
