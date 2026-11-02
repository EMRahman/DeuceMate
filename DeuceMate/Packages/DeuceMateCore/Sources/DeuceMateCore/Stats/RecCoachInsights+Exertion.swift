// Association between PRECEDING effort and the NEXT service point. Recorded
// steps include between-point movement; neither steps nor HR measures rally
// duration or proves fatigue. Caller permits only the recorder in singles.
import Foundation

extension RecCoachInsights {
    private struct EffortSample {
        let next: PointStat
        let load: Int
    }

    static func exertion(_ stats: [PointStat]) -> [Candidate] {
        let ordered = stats.sorted { $0.timestamp < $1.timestamp }
        guard ordered.count >= 3 else { return [] }
        var movement: [EffortSample] = []
        var heartRate: [EffortSample] = []
        // Do not filter missing records out before forming pairs/triples: that
        // would attribute multiple rallies' load to one point across a gap.
        for index in 1..<ordered.count {
            let previous = ordered[index - 1]
            let next = ordered[index]
            guard consecutive(previous, next), previous.outcome != .uncategorized,
                  next.outcome != .uncategorized else { continue }
            if let bpm = previous.heartRateBPM, bpm > 0 {
                heartRate.append(EffortSample(next: next, load: bpm))
            }
            if index >= 2 {
                let before = ordered[index - 2]
                if consecutive(before, previous), before.outcome != .uncategorized,
                   let start = before.stepsCumulative, let end = previous.stepsCumulative,
                   start >= 0, end >= start {
                    movement.append(EffortSample(next: next, load: end - start))
                }
            }
        }
        return effortCandidates(movement, label: "higher-movement points", id: "movement", minimumSeparation: 5)
            + effortCandidates(heartRate, label: "points with higher recorded heart rate", id: "heartRate", minimumSeparation: 10)
    }

    /// Exact score succession proves adjacency within a regular service game;
    /// rejects restarts, missing rallies, set/game changes, tiebreaks and pauses.
    private static func consecutive(_ previous: PointStat, _ next: PointStat) -> Bool {
        guard previous.server == .me, next.server == .me,
              previous.setIndex == next.setIndex,
              let a = previous.gameScoreAtStart, let b = next.gameScoreAtStart,
              !a.isTiebreak, !b.isTiebreak,
              next.timestamp.timeIntervalSince(previous.timestamp) > 0,
              next.timestamp.timeIntervalSince(previous.timestamp) <= 90 else { return false }
        let server = a.server + (previous.winner == .me ? 1 : 0)
        let returner = a.returner + (previous.winner == .me ? 0 : 1)
        guard !ScoringEngine.isRegularGameComplete(playerOnePoints: server, playerTwoPoints: returner) else { return false }
        return b.server == server && b.returner == returner
    }

    private static func effortCandidates(_ samples: [EffortSample], label: String, id: String, minimumSeparation: Int) -> [Candidate] {
        guard samples.count >= 20 else { return [] }
        let sorted = samples.map(\.load).sorted()
        let middle = sorted.count / 2
        let median = sorted.count.isMultiple(of: 2) ? (Double(sorted[middle - 1]) + Double(sorted[middle])) / 2 : Double(sorted[middle])
        let high = samples.filter { Double($0.load) > median }
        let low = samples.filter { Double($0.load) <= median }
        guard high.count >= 10, low.count >= 10 else { return [] }
        let highMean = high.reduce(0.0) { $0 + Double($1.load) } / Double(high.count)
        let lowMean = low.reduce(0.0) { $0 + Double($1.load) } / Double(low.count)
        guard highMean - lowMean >= Double(minimumSeparation) else { return [] }
        let highPoints = high.map(\.next), lowPoints = low.map(\.next)
        let highIn = Double(highPoints.filter(firstIn).count) / Double(high.count)
        let lowIn = Double(lowPoints.filter(firstIn).count) / Double(low.count)
        let highDF = highPoints.filter { $0.outcome == .doubleFault && $0.winner != .me }.count
        let lowDF = lowPoints.filter { $0.outcome == .doubleFault && $0.winner != .me }.count
        let dfRise = Double(highDF) / Double(high.count) - Double(lowDF) / Double(low.count)
        let winDrop = rate(lowPoints, focal: .me) - rate(highPoints, focal: .me)
        let sampleWeight = Double(min(high.count, low.count, 30))
        let advice = " — practise resetting your breathing and serve routine between points."
        var result: [Candidate] = []
        if lowIn - highIn >= 0.15 {
            result.append(Candidate(id: "\(id)FirstServe", score: 20 + (lowIn - highIn) * sampleWeight,
                                    topics: ["exertion", "serveReliability"],
                                    line: "First serves in after \(label): \(pct(highIn))% (\(highPoints.filter(firstIn).count)/\(high.count)) vs \(pct(lowIn))% (\(lowPoints.filter(firstIn).count)/\(low.count)) otherwise" + advice))
        }
        if highDF >= 3, dfRise >= 0.1 {
            result.append(Candidate(id: "\(id)DoubleFaults", score: 20 + dfRise * sampleWeight,
                                    topics: ["exertion", "serveReliability", "errors"],
                                    line: "Double faults after \(label): \(highDF)/\(high.count) service points vs \(lowDF)/\(low.count) otherwise" + advice))
        }
        if winDrop >= 0.2 {
            result.append(Candidate(id: "\(id)ServicePoints", score: 12 + winDrop * sampleWeight,
                                    topics: ["exertion", "serveResults"],
                                    line: "Service points won after \(label): \(fraction(highPoints, focal: .me)) vs \(fraction(lowPoints, focal: .me)) otherwise" + advice))
        }
        return result
    }
}
