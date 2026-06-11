// PulseCoachSection.swift — post-match heart-rate analysis surfaced in
// MatchDetailView when Pulse Coach is enabled and the match has HR data.
import SwiftUI
import Charts
import DeuceMateCore

struct PulseCoachSection: View {
    let summary: MatchStatsSummary
    let record: MatchRecord
    let filteredStats: [PointStat]

    var body: some View {
        if !summary.zoneWinRates.isEmpty {
            Section("Pulse Coach") {
                if !summary.autoInsights.isEmpty {
                    AutoInsightCard(insights: summary.autoInsights)
                }
                HRZoneWinRateChart(zoneStats: summary.zoneWinRates, maxHR: summary.resolvedMaxHR)
                HRTimelineChart(
                    maxHR: summary.resolvedMaxHR,
                    record: record,
                    filteredStats: filteredStats
                )

            }
        }
    }
}

private enum HRZoneStyle {
    static func color(for zone: HRZone) -> Color {
        switch zone {
        case .z1: return .blue
        case .z2: return .green
        case .z3: return .yellow
        case .z4: return .orange
        case .z5: return .red
        }
    }

    static func zone(fromLabel label: String) -> HRZone? {
        HRZone.allCases.first { $0.displayLabel == label }
    }

    /// Lower BPM bound for a zone given the player's max HR (inclusive).
    /// Derived from `HRZone.ceilingBPM` so the thresholds stay in sync with `DeuceMateCore`.
    static func lowerBPM(for zone: HRZone, maxHR: Int) -> Int {
        switch zone {
        case .z1: return 0
        case .z2: return HRZone.ceilingBPM(for: .z1, maxHR: maxHR) + 1
        case .z3: return HRZone.ceilingBPM(for: .z2, maxHR: maxHR) + 1
        case .z4: return HRZone.ceilingBPM(for: .z3, maxHR: maxHR) + 1
        case .z5: return HRZone.ceilingBPM(for: .z4, maxHR: maxHR) + 1
        }
    }

    /// Display "lo–hi" BPM range for a zone, e.g. "152–170".
    static func bpmRangeLabel(for zone: HRZone, maxHR: Int) -> String {
        let hi = HRZone.ceilingBPM(for: zone, maxHR: maxHR)
        switch zone {
        case .z1: return "≤\(hi)"
        case .z5: return "\(lowerBPM(for: zone, maxHR: maxHR))+"
        default:  return "\(lowerBPM(for: zone, maxHR: maxHR))–\(hi)"
        }
    }
}

private struct AutoInsightCard: View {
    let insights: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(insights, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.tint)
                        .font(.footnote)
                    Text(line)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct HRZoneWinRateChart: View {
    let zoneStats: [MatchStatsSummary.ZoneWinRate]
    let maxHR: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Win Rate by HR Zone")
                .font(.caption)
                .foregroundStyle(.secondary)
            Chart(zoneStats, id: \.zone) { stat in
                BarMark(
                    x: .value("Zone", stat.zone.displayLabel),
                    y: .value("Win %", winPct(stat))
                )
                .foregroundStyle(HRZoneStyle.color(for: stat.zone))
                .annotation(position: .top, alignment: .center) {
                    Text("\(stat.wins)/\(stat.total)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let n = value.as(Int.self) {
                            Text("\(n)%").font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
                    AxisValueLabel {
                        if let label = value.as(String.self),
                           let zone = HRZoneStyle.zone(fromLabel: label) {
                            VStack(spacing: 1) {
                                Text(zone.displayLabel)
                                    .font(.caption2.weight(.semibold))
                                Text(HRZoneStyle.bpmRangeLabel(for: zone, maxHR: maxHR))
                                    .font(.system(size: 9).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .chartPlotStyle { $0.padding(.top, 16) }
            .frame(height: 170)
        }
        .padding(.vertical, 4)
    }

    private func winPct(_ stat: MatchStatsSummary.ZoneWinRate) -> Double {
        guard stat.total > 0 else { return 0 }
        return Double(stat.wins) / Double(stat.total) * 100.0
    }
}

private struct HRTimelineChart: View {
    let maxHR: Int
    let record: MatchRecord
    let filteredStats: [PointStat]

    /// `filteredStats` sorted by timestamp. The x-axis indexes into this array
    /// so all three series (raw / averaged / smoothed) share point positions.
    private var orderedStats: [PointStat] {
        filteredStats.sorted { $0.timestamp < $1.timestamp }
    }

    @State private var mode: HRSeriesMode = .snapshot
    @StateObject private var fetcher = HealthKitHRFetcher()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Heart Rate Through Match")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Picker("Series", selection: $mode) {
                ForEach(HRSeriesMode.allCases) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _, newValue in
                guard newValue == .averaged else { return }
                // Re-fetch on every switch into averaged unless data is
                // already loaded — that retries transient failures and picks
                // up any change to the set filter the user made meanwhile.
                if case .loaded = fetcher.state { return }
                fetchAveraged()
            }
            .onChange(of: filteredStats) { _, _ in
                // Observe the array (not just .count) so switching between two
                // sets that happen to have the same number of points still
                // triggers a re-fetch.
                if mode == .averaged { fetchAveraged() }
            }
            chartBody
            if mode == .averaged {
                averagedStatusLine
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var chartBody: some View {
        let series = activeSeries
        Chart {
            ForEach(zoneBands(domain: yDomain(series: series)), id: \.zone) { band in
                RectangleMark(
                    xStart: .value("Start", xRange.lowerBound),
                    xEnd: .value("End", xRange.upperBound),
                    yStart: .value("Low", band.low),
                    yEnd: .value("High", band.high)
                )
                .foregroundStyle(HRZoneStyle.color(for: band.zone).opacity(0.18))
            }
            ForEach(downsample(series), id: \.pointIndex) { hp in
                LineMark(
                    x: .value("Point", hp.pointIndex),
                    y: .value("BPM", hp.bpm)
                )
                .foregroundStyle(.primary)
                .interpolationMethod(.monotone)
            }
            ForEach(setBoundaries, id: \.self) { x in
                RuleMark(x: .value("Set boundary", x))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
        }
        .chartYScale(domain: yDomain(series: series))
        .chartXAxis(.hidden)
        .chartXScale(domain: xRange)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let n = value.as(Int.self) {
                        Text("\(n)").font(.caption2.monospacedDigit())
                    }
                }
            }
            AxisMarks(position: .trailing, values: zoneLabelTicks(domain: yDomain(series: series)).map(\.bpm)) { value in
                AxisValueLabel {
                    if let bpm = value.as(Int.self),
                       let tick = zoneLabelTicks(domain: yDomain(series: series)).first(where: { $0.bpm == bpm }) {
                        Text(tick.zone.displayLabel)
                            .font(.system(size: 10).weight(.semibold))
                            .foregroundStyle(HRZoneStyle.color(for: tick.zone))
                    }
                }
            }
        }
        .frame(height: 160)
    }

    @ViewBuilder
    private var averagedStatusLine: some View {
        switch fetcher.state {
        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Loading samples from Health…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .unavailable:
            Text("Health data isn't available on this device.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .denied:
            Text("Allow heart-rate access in Settings › Health to see the per-point average.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .empty:
            Text("No heart-rate samples were recorded during this match.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .failed(let msg):
            Text("Couldn't load Health data: \(msg)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .loaded, .idle:
            EmptyView()
        }
    }

    private func fetchAveraged() {
        fetcher.load(
            for: record,
            filteredStats: filteredStats,
            firstWindowStart: firstWindowStart
        )
    }

    /// Lower bound of the first bucket — timestamp of the point in
    /// `record.stats` that immediately precedes the first filtered stat, or
    /// `record.startTime` when the filter starts from the beginning.
    private var firstWindowStart: Date {
        guard let firstFiltered = orderedStats.first else { return record.startTime }
        let ordered = record.stats.sorted { $0.timestamp < $1.timestamp }
        var prior: Date?
        for s in ordered {
            if s.id == firstFiltered.id { break }
            prior = s.timestamp
        }
        return prior ?? record.startTime
    }

    // MARK: - Series selection

    private var snapshotSeries: [HRChartPoint] {
        orderedStats.enumerated().compactMap { i, stat in
            guard let bpm = stat.heartRateBPM, bpm > 0 else { return nil }
            return HRChartPoint(pointIndex: i, bpm: bpm, setIndex: stat.setIndex)
        }
    }

    /// Centered moving average of width 5 over the snapshot series. Operates
    /// on the entries the snapshot has (not on absolute point indices), so
    /// gaps where HR wasn't captured stay gaps. Edge points use the available
    /// window (truncated).
    private var smoothedSeries: [HRChartPoint] {
        let raw = snapshotSeries
        guard raw.count >= 2 else { return raw }
        let half = 2
        return raw.enumerated().map { i, hp in
            let lo = max(0, i - half)
            let hi = min(raw.count - 1, i + half)
            let slice = raw[lo...hi]
            let avg = Int((Double(slice.reduce(0) { $0 + $1.bpm }) / Double(slice.count)).rounded())
            return HRChartPoint(pointIndex: hp.pointIndex, bpm: avg, setIndex: hp.setIndex)
        }
    }

    private var averagedSeries: [HRChartPoint] {
        if case .loaded(let pts) = fetcher.state { return pts }
        return []
    }

    private var activeSeries: [HRChartPoint] {
        switch mode {
        case .snapshot: return snapshotSeries
        case .smoothed: return smoothedSeries
        case .averaged: return averagedSeries
        }
    }

    // MARK: - Chart geometry

    private struct ZoneBand {
        let zone: HRZone
        let low: Int
        let high: Int
    }

    private func zoneBands(domain: ClosedRange<Int>) -> [ZoneBand] {
        guard maxHR > 0 else { return [] }
        let zones = HRZone.allCases
        var bands: [ZoneBand] = []
        for (idx, zone) in zones.enumerated() {
            let lo = HRZoneStyle.lowerBPM(for: zone, maxHR: maxHR)
            let hi = idx + 1 < zones.count
                ? HRZoneStyle.lowerBPM(for: zones[idx + 1], maxHR: maxHR)
                : maxHR
            let visibleLo = max(lo, domain.lowerBound)
            let visibleHi = min(hi, domain.upperBound)
            if visibleHi > visibleLo {
                bands.append(ZoneBand(zone: zone, low: visibleLo, high: visibleHi))
            }
        }
        return bands
    }

    private func zoneLabelTicks(domain: ClosedRange<Int>) -> [(zone: HRZone, bpm: Int)] {
        zoneBands(domain: domain).map { ($0.zone, ($0.low + $0.high) / 2) }
    }

    private var xRange: ClosedRange<Int> {
        // Anchor the x-axis to filteredStats so all three series share the
        // same horizontal scale (one tick per played point).
        let lo = 0
        let hi = max(orderedStats.count - 1, 1)
        return lo...hi
    }

    private func downsample(_ series: [HRChartPoint]) -> [HRChartPoint] {
        guard series.count > 120 else { return series }
        let stride = max(1, series.count / 100)
        var result: [HRChartPoint] = []
        result.reserveCapacity(series.count / stride + 1)
        for i in Swift.stride(from: 0, to: series.count, by: stride) {
            result.append(series[i])
        }
        if result.last?.pointIndex != series.last?.pointIndex, let last = series.last {
            result.append(last)
        }
        return result
    }

    private var setBoundaries: [Int] {
        var boundaries: [Int] = []
        let stats = orderedStats
        guard let firstSet = stats.first?.setIndex else { return [] }
        var lastSet = firstSet
        for (i, stat) in stats.enumerated() {
            if stat.setIndex != lastSet {
                boundaries.append(i)
                lastSet = stat.setIndex
            }
        }
        return boundaries
    }

    private func yDomain(series: [HRChartPoint]) -> ClosedRange<Int> {
        let pool = series.isEmpty ? snapshotSeries.map(\.bpm) : series.map(\.bpm)
        let minB = pool.min() ?? 60
        let topCandidate = max(maxHR, pool.max() ?? maxHR)
        let lower = max(40, minB - 10)
        // Guard against pathological inputs (maxHR == 0 and empty pool) where
        // topCandidate could fall below `lower` and yield a crashing range.
        let upper = max(lower + 15, topCandidate + 5)
        return lower...upper
    }
}
