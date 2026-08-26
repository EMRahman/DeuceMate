// TrendChart.swift — one TrendMetricGroup's chart on the Trends screen.
// Errors/Attack/Pressure share one multi-line chart shape plotting every
// metric in the group at once. Serve & Return uses the same chart shape but
// narrowed by a persisted Serves In/Serves Win/Returns Win filter to 2 of
// its 6 metrics at a time (owner request — 6 lines at once was cluttered).
// Rally Depth gets a distinct normalized-stack-vs-win-rate toggle since its
// axis is fundamentally different (phase share, not an error rate).
// See docs/features/PERFORMANCE_TRENDS_PLAN.md §6.3.
import SwiftUI
import Charts
import DeuceMateCore

/// Chart colour per metric. Mine and its opponent-framed counterpart share a
/// hue (so the legend reads as one pair) and are told apart by line style —
/// solid for mine, dashed for opponent-framed. Mirrors the outcome palette
/// PointsGraphView already uses (DF orange, winner yellow, UE red, FE
/// purple) so a trend line and a match's own chart agree on what a colour
/// means. Trends aren't exported, so this does not need to stay in step
/// with WebExportColors (CLAUDE.md's "keep WebExportColors in step" rule is
/// about the HTML export mirroring PointsGraphView specifically).
extension TrendMetric {
    /// One colour per metric. Within Errors/Attack, a metric and its
    /// opponent-framed counterpart deliberately SHARE a hue (told apart by
    /// solid-vs-dashed and by the opponent one starting hidden — §6.3).
    /// Every other group has no such pairing, so within Serve & Return,
    /// Pressure and each Rally Depth mode — where every metric is visible
    /// at once with no dash/hide to fall back on — colours must be
    /// genuinely distinct, not just different named `Color` cases that
    /// happen to render as near-identical hues (blue/indigo, teal/mint,
    /// and pink/pink were all indistinguishable on-device before this).
    var chartColor: Color {
        switch self {
        case .doubleFaults, .doubleFaultsConceded:            return .orange
        case .unforcedErrors, .unforcedErrorsDrawn:           return .red
        case .forcedErrorsConceded, .forcedErrorsCaused:      return .purple
        case .winners, .winnersConceded:                      return .yellow
        case .wueRatio:                                       return .green
        case .aggressionIndex:                                return .mint
        case .ownErrorShare:                                  return .pink
        case .depthShareServe, .depthWinServe:                return .teal
        case .depthShareReturn, .depthWinReturn:              return .indigo
        case .depthShareServePlusOne, .depthWinServePlusOne:  return .pink
        case .depthShareRally, .depthWinRally:                return .brown
        case .firstServeIn:                                   return .blue
        case .secondServeIn:                                  return .cyan
        case .firstServeWin:                                  return .green
        case .secondServeWin:                                 return .orange
        case .returnWinFirst:                                 return .purple
        case .returnWinSecond:                                return .pink
        case .breakPointsConverted:                           return .red
        case .breakPointsSaved:                               return .cyan
        case .bigPointWin:                                    return .orange
        case .pointsWon:                                      return .green
        }
    }

    /// The metric counts something that happened to/because of the
    /// OPPONENT (their double faults, unforced errors, winners, or errors
    /// the recorder caused them into) rather than the recorder's own shot.
    /// These default hidden (§6.3: "the opponent's own trend is one legend
    /// tap away") and render dashed when shown.
    var isOpponentFramed: Bool {
        switch self {
        case .doubleFaultsConceded, .unforcedErrorsDrawn, .forcedErrorsCaused, .winnersConceded:
            return true
        default:
            return false
        }
    }
}

struct TrendChart: View {
    let group: TrendMetricGroup
    /// Pre-scoped to `group` by the caller (PerformanceTrends.series(for:in:)).
    let series: [TrendSeries]
    let displayMode: TrendDisplayMode

    @State private var hiddenMetrics: Set<TrendMetric>
    @State private var rallyDepthMode: RallyDepthMode = .mix
    /// Persisted (unlike `rallyDepthMode`, which resets each time the
    /// screen opens) — the owner asked this filter to remember the last
    /// choice across launches. Phone-local, no wire key — see CLAUDE.md §0.
    @AppStorage("trendsServeReturnFilter") private var serveReturnFilterRaw: String = ServeReturnFilter.servesIn.rawValue

    init(group: TrendMetricGroup, series: [TrendSeries], displayMode: TrendDisplayMode) {
        self.group = group
        self.series = series
        self.displayMode = displayMode
        // Opponent-framed metrics start hidden; everything else starts shown.
        _hiddenMetrics = State(initialValue: Set(series.map(\.metric).filter(\.isOpponentFramed)))
    }

    private enum RallyDepthMode: String, CaseIterable, Identifiable {
        case mix, winRate
        var id: String { rawValue }
        var label: String { self == .mix ? "Mix" : "Win Rate" }
    }

    /// Narrows the Serve & Return group's six metrics to one question at a
    /// time — no "All 6" option (confirmed with the owner). Defaults to
    /// `.servesIn`, the archive's most basic serve stat.
    private enum ServeReturnFilter: String, CaseIterable, Identifiable {
        case servesIn, servesWin, returnsWin
        var id: String { rawValue }
        var label: String {
            switch self {
            case .servesIn:   return "Serves In"
            case .servesWin:  return "Serves Win"
            case .returnsWin: return "Returns Win"
            }
        }
        var metrics: [TrendMetric] {
            switch self {
            case .servesIn:   return [.firstServeIn, .secondServeIn]
            case .servesWin:  return [.firstServeWin, .secondServeWin]
            case .returnsWin: return [.returnWinFirst, .returnWinSecond]
            }
        }
    }

    private var serveReturnFilter: ServeReturnFilter {
        ServeReturnFilter(rawValue: serveReturnFilterRaw) ?? .servesIn
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if group == .rallyDepth {
                rallyDepthBody
            } else if group == .serveReturn {
                serveReturnBody
            } else {
                standardBody
            }
        }
    }

    // MARK: - Standard groups (Errors, Attack, Pressure)

    /// Ratio-unit metrics (currently only W:UE) can't share a 0–1 percent
    /// axis with everything else in Attack, so they render as their own
    /// compact rows below the shared chart instead of distorting its scale.
    private var percentSeries: [TrendSeries] { series.filter { $0.metric.unit == .percent } }
    private var ratioSeries: [TrendSeries] { series.filter { $0.metric.unit == .ratio } }

    @ViewBuilder
    private var standardBody: some View {
        if series.isEmpty || series.allSatisfy({ $0.points.isEmpty }) {
            emptyState
        } else {
            if !percentSeries.isEmpty {
                lineChart(for: percentSeries)
                legend(for: percentSeries)
            }
            ForEach(ratioSeries) { s in
                TrendSparkline(series: s, displayMode: displayMode, color: s.metric.chartColor)
            }
        }
    }

    /// A point's Y value at the current display mode: the 0...1 rate, or —
    /// when Count mode is selected and the metric supports it — the raw
    /// numerator. Counts across metrics with different denominators are
    /// still meaningfully comparable as counts (e.g. "12 double faults" vs
    /// "8 unforced errors" over the same window), unlike mixing a fraction
    /// and a count on one axis.
    private func plottedValue(_ point: TrendPoint) -> Double {
        displayMode == .count ? Double(point.ratio.numerator) : point.value
    }

    /// Draws `series` as a multi-line chart, filtering out — in Count mode
    /// only — any metric with `supportsCountMode == false` (aggressionIndex,
    /// ownErrorShare): its 0...1 fraction plotted against a raw-count axis
    /// would read as pinned near zero, so it drops out of Count mode rather
    /// than misrepresenting it. Every metric is plottable in Rate mode.
    /// Takes an explicit list (not just `self.series`) so callers can narrow
    /// to a subset — e.g. Serve & Return's filter picks 2 of its 6 metrics.
    private func lineChart(for series: [TrendSeries]) -> some View {
        let plottable = displayMode == .count ? series.filter { $0.metric.supportsCountMode } : series
        return Chart {
            ForEach(plottable) { s in
                if !hiddenMetrics.contains(s.metric) {
                    ForEach(s.points) { point in
                        LineMark(
                            x: .value("Match", point.index),
                            y: .value("Value", plottedValue(point))
                        )
                        .foregroundStyle(by: .value("Metric", s.metric.displayLabel))
                        .lineStyle(s.metric.isOpponentFramed
                            ? StrokeStyle(lineWidth: 2, dash: [4, 3])
                            : StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)
                        .symbol(Circle())
                        .symbolSize(18)
                    }
                }
            }
        }
        .chartForegroundStyleScale(domain: colorScale(for: plottable).domain, range: colorScale(for: plottable).range)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(displayMode == .count ? "\(Int(v.rounded()))" : "\(Int((v * 100).rounded()))%")
                            .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 140)
    }

    /// Metric display label -> chart colour, as parallel arrays for
    /// `.chartForegroundStyleScale(domain:range:)`. That overload (not the
    /// KeyValuePairs-literal one) is what accepts a scale built at runtime;
    /// the `foregroundStyle(by:)` discriminator above is what actually
    /// splits marks into separate connected series, this just tells Charts
    /// which colour each discriminator value should get instead of an
    /// auto-assigned categorical one.
    private func colorScale(for series: [TrendSeries]) -> (domain: [String], range: [Color]) {
        (series.map { $0.metric.displayLabel }, series.map { $0.metric.chartColor })
    }

    // MARK: - Serve & Return

    /// The two metrics `serveReturnFilter` currently selects, in their
    /// declared order (1st before 2nd) — the group's `TrendMetric.allCases`
    /// order, unaffected by which two are picked.
    private var serveReturnSelectedSeries: [TrendSeries] {
        series.filter { serveReturnFilter.metrics.contains($0.metric) }
    }

    @ViewBuilder
    private var serveReturnBody: some View {
        Picker("Serve & Return View", selection: $serveReturnFilterRaw) {
            ForEach(ServeReturnFilter.allCases) { filter in
                Text(filter.label).tag(filter.rawValue)
            }
        }
        .pickerStyle(.segmented)

        let selected = serveReturnSelectedSeries
        if selected.isEmpty || selected.allSatisfy({ $0.points.isEmpty }) {
            emptyState
        } else {
            lineChart(for: selected)
            legend(for: selected)
        }
    }

    // MARK: - Rally depth

    private var depthShareSeries: [TrendSeries] {
        series.filter { [.depthShareServe, .depthShareReturn, .depthShareServePlusOne, .depthShareRally].contains($0.metric) }
    }
    private var depthWinSeries: [TrendSeries] {
        series.filter { [.depthWinServe, .depthWinReturn, .depthWinServePlusOne, .depthWinRally].contains($0.metric) }
    }

    @ViewBuilder
    private var rallyDepthBody: some View {
        Picker("Rally Depth View", selection: $rallyDepthMode) {
            ForEach(RallyDepthMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)

        if depthShareSeries.allSatisfy({ $0.points.isEmpty }) {
            emptyState
        } else {
            switch rallyDepthMode {
            case .mix:
                rallyDepthStackedChart
                staticLegend(for: depthShareSeries)
            case .winRate:
                rallyDepthWinRateChart
                staticLegend(for: depthWinSeries)
            }
        }
    }

    /// Every match index that appears in at least one depth-share series —
    /// the shared X domain for the stacked chart, since a match with no
    /// ending-shot data contributes to none of the four series.
    private var depthMatchIndices: [Int] {
        Array(Set(depthShareSeries.flatMap { $0.points.map(\.index) })).sorted()
    }

    private var rallyDepthStackedChart: some View {
        Chart {
            ForEach(depthShareSeries) { s in
                ForEach(s.points) { point in
                    AreaMark(
                        x: .value("Match", point.index),
                        y: .value("Share", point.value),
                        stacking: .normalized
                    )
                    .foregroundStyle(by: .value("Metric", s.metric.displayLabel))
                }
            }
        }
        .chartForegroundStyleScale(domain: colorScale(for: depthShareSeries).domain, range: colorScale(for: depthShareSeries).range)
        .chartYAxis {
            // .automatic, not an explicit [0.0, 0.5, 1.0]: normalized
            // AreaMark stacking reports its Y-axis values ALREADY in
            // percentage units (0...100), unlike every other chart here
            // where the raw value is a 0...1 fraction — multiplying by 100
            // again produced "10,000%" axis labels. This chart's label
            // closure must NOT rescale.
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v.rounded()))%").font(.caption2)
                    }
                }
            }
        }
        .chartXAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 140)
    }

    private var rallyDepthWinRateChart: some View {
        Chart {
            ForEach(depthWinSeries) { s in
                ForEach(s.points) { point in
                    LineMark(
                        x: .value("Match", point.index),
                        y: .value("Value", plottedValue(point))
                    )
                    .foregroundStyle(by: .value("Metric", s.metric.displayLabel))
                    .interpolationMethod(.monotone)
                    .symbol(Circle())
                    .symbolSize(18)
                }
            }
        }
        .chartForegroundStyleScale(domain: colorScale(for: depthWinSeries).domain, range: colorScale(for: depthWinSeries).range)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(displayMode == .count ? "\(Int(v.rounded()))" : "\(Int((v * 100).rounded()))%")
                            .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 140)
    }

    // MARK: - Shared controls

    /// Errors / Attack / Serve & Return / Pressure: each chip toggles that
    /// metric's line on and off (opponent-framed metrics start hidden;
    /// §6.3).
    /// Adaptive grid, not a single HStack: six chips squeezed into one row
    /// each get a sliver of width and wrap character-by-character. Letting
    /// chips flow onto as many rows as needed at a legible minimum width
    /// keeps every label on one line.
    private static let legendColumns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

    private func legend(for series: [TrendSeries]) -> some View {
        LazyVGrid(columns: Self.legendColumns, alignment: .leading, spacing: 6) {
            ForEach(series) { s in
                Button {
                    if hiddenMetrics.contains(s.metric) {
                        hiddenMetrics.remove(s.metric)
                    } else {
                        hiddenMetrics.insert(s.metric)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Rectangle()
                            .fill(s.metric.chartColor)
                            .frame(width: 12, height: 2)
                        Text(s.metric.displayLabel)
                            .font(.caption2)
                            .lineLimit(1)
                            .foregroundStyle(hiddenMetrics.contains(s.metric) ? .tertiary : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .opacity(hiddenMetrics.contains(s.metric) ? 0.5 : 1)
            }
        }
    }

    /// Rally Depth: a plain (non-toggleable) legend. Hiding one phase from a
    /// normalized stack would change what "100%" means for the rest, so
    /// unlike the standard legend these chips are not buttons.
    private func staticLegend(for series: [TrendSeries]) -> some View {
        LazyVGrid(columns: Self.legendColumns, alignment: .leading, spacing: 6) {
            ForEach(series) { s in
                HStack(spacing: 4) {
                    Rectangle()
                        .fill(s.metric.chartColor)
                        .frame(width: 12, height: 2)
                    Text(s.metric.displayLabel)
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var emptyState: some View {
        Text("Not enough data for this group yet.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 20)
    }
}
