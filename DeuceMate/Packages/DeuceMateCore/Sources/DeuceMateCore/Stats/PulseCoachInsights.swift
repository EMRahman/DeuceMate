// PulseCoachInsights.swift — deterministic rule engine that converts
// heart-rate-tagged points into ≤3 short coaching observations.
import Foundation

public enum PulseCoachInsights {

    /// Returns up to three short coaching sentences derived from heart-rate
    /// tagged points. Always returns an empty array when there is insufficient
    /// data so callers can safely treat empty as "hide the section."
    public static func generate(
        stats: [PointStat],
        focal: Player,
        maxHR: Int
    ) -> [String] {
        let hrPoints = stats.compactMap { pt -> (PointStat, Int)? in
            guard let bpm = pt.heartRateBPM, bpm > 0 else { return nil }
            return (pt, bpm)
        }
        guard hrPoints.count >= 10 else { return [] }

        var insights: [String] = []

        if let zoneInsight = zoneDeltaInsight(hrPoints: hrPoints, focal: focal, maxHR: maxHR) {
            insights.append(zoneInsight)
        }
        if let bpInsight = breakPointHRInsight(hrPoints: hrPoints, focal: focal) {
            insights.append(bpInsight)
        }
        if let declineInsight = lateMatchDeclineInsight(hrPoints: hrPoints, focal: focal) {
            insights.append(declineInsight)
        }
        return Array(insights.prefix(3))
    }

    // MARK: - Rule 1: zone delta

    private static func zoneDeltaInsight(
        hrPoints: [(PointStat, Int)],
        focal: Player,
        maxHR: Int
    ) -> String? {
        var byZone: [HRZone: (total: Int, wins: Int)] = [:]
        for (pt, bpm) in hrPoints {
            let z = HRZone.zone(forBPM: bpm, maxHR: maxHR)
            var entry = byZone[z] ?? (0, 0)
            entry.total += 1
            if pt.winner == focal { entry.wins += 1 }
            byZone[z] = entry
        }
        let qualified = byZone.compactMap { (z, e) -> (HRZone, Int, Double)? in
            guard e.total >= 5 else { return nil }
            return (z, e.total, Double(e.wins) / Double(e.total))
        }
        guard qualified.count >= 2,
              let best = qualified.max(by: { $0.2 < $1.2 }),
              let worst = qualified.min(by: { $0.2 < $1.2 }),
              best.0 != worst.0,
              best.2 - worst.2 >= 0.15 else {
            return nil
        }
        let bestPct = Int((best.2 * 100).rounded())
        let worstPct = Int((worst.2 * 100).rounded())
        return "You won \(bestPct)% of points in \(best.0.displayLabel) but only \(worstPct)% in \(worst.0.displayLabel)."
    }

    // MARK: - Rule 2: break-point HR

    private static func breakPointHRInsight(
        hrPoints: [(PointStat, Int)],
        focal: Player
    ) -> String? {
        let bps = hrPoints.filter { $0.0.isBreakPoint }
        guard bps.count >= 4 else { return nil }
        let median = medianBPM(bps.map(\.1))
        let above = bps.filter { $0.1 > median }
        guard above.count >= 2 else { return nil }
        let losses = above.filter { $0.0.winner != focal }.count
        let lossRate = Double(losses) / Double(above.count)
        guard lossRate >= 0.6 else { return nil }
        return "You lost \(losses) of \(above.count) break points after HR rose above \(median) bpm."
    }

    // MARK: - Rule 3: late-match decline

    private static func lateMatchDeclineInsight(
        hrPoints: [(PointStat, Int)],
        focal: Player
    ) -> String? {
        guard hrPoints.count >= 20 else { return nil }
        let sorted = hrPoints.sorted { $0.0.timestamp < $1.0.timestamp }
        let half = sorted.count / 2
        let firstHalf = Array(sorted.prefix(half))
        let secondHalf = Array(sorted.suffix(sorted.count - half))
        let firstWinRate = Double(firstHalf.filter { $0.0.winner == focal }.count) / Double(firstHalf.count)
        let secondWinRate = Double(secondHalf.filter { $0.0.winner == focal }.count) / Double(secondHalf.count)
        let firstAvgHR = avgBPM(firstHalf.map(\.1))
        let secondAvgHR = avgBPM(secondHalf.map(\.1))
        guard firstWinRate - secondWinRate >= 0.15,
              secondAvgHR - firstAvgHR >= 10 else {
            return nil
        }
        let firstPct = Int((firstWinRate * 100).rounded())
        let secondPct = Int((secondWinRate * 100).rounded())
        let drift = Int((secondAvgHR - firstAvgHR).rounded())
        return "Win rate dropped from \(firstPct)% to \(secondPct)% as average HR climbed by \(drift) bpm."
    }

    // MARK: - Helpers

    private static func medianBPM(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    private static func avgBPM(_ values: [Int]) -> Double {
        guard !values.isEmpty else { return 0 }
        return Double(values.reduce(0, +)) / Double(values.count)
    }
}
