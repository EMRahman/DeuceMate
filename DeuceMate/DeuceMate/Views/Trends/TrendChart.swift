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
        case .avgHeartRate:                                   return .red
        case .hardZoneShare:                                  return .orange
        case .hardZoneWinRate:                                return .green
        case .stepsPerPoint:                                  return .blue
        case .stepsPerPointWon:                               return .teal
        case .metresPerPoint:                                 return .indigo
        case .minutesPerMatch:                                return .brown
        // Fatigue pairs: first set vs final set, distinct enough to read
        // apart at a glance since the gap between them IS the metric.
        case .winRateFirstSet:                                return .green
        case .winRateFinalSet:                                return .orange
        case .avgHeartRateFirstSet:                           return .pink
        case .avgHeartRateFinalSet:                           return .red
        case .stepsPerPointFirstSet:                          return .cyan
        case .stepsPerPointFinalSet:                          return .blue
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
    /// Total matches in the caller's scoped window — passed through to
    /// `TrendSparkline` for `ratioSeries` rows (currently just W:UE) so its
    /// sparkline's X-domain reflects the whole window, not just whichever
    /// indices this one metric happens to have values for (Codex review,
    /// PR #121).
    let sampleCount: Int
    /// index -> match date for EVERY sample in the caller's scoped window,
    /// not just indices this group happens to have plottable values for —
    /// passed in from `TrendsView` rather than derived from `series` here,
    /// since a group where every metric gaps the same match (all four
    /// Rally Depth share metrics on a match with no ending-shot data, say)
    /// would otherwise leave that index dateless even though `chartXDomain`
    /// still spans it (Codex review, PR #121).
    let dateByIndex: [Int: Date]

    @State private var hiddenMetrics: Set<TrendMetric>
    @State private var rallyDepthMode: RallyDepthMode = .mix
    /// Tap/drag-selected match index, shared across whichever chart shape
    /// this group currently shows — `PERFORMANCE_TRENDS_PLAN.md` §6.3
    /// specified "the date appears in the axis label and in the selection
    /// readout" from the start, but neither was ever wired up; the axis was
    /// unconditionally `.chartXAxis(.hidden)` with no selection at all
    /// (Codex review, PR #121).
    @State private var selectedIndex: Int?
    /// Persisted (unlike `rallyDepthMode`, which resets each time the
    /// screen opens) — the owner asked this filter to remember the last
    /// choice across launches. Phone-local, no wire key — see CLAUDE.md §0.
    @AppStorage("trendsServeReturnFilter") private var serveReturnFilterRaw: String = ServeReturnFilter.servesIn.rawValue

    init(group: TrendMetricGroup, series: [TrendSeries], displayMode: TrendDisplayMode, sampleCount: Int, dateByIndex: [Int: Date]) {
        self.group = group
        self.series = series
        self.displayMode = displayMode
        self.sampleCount = sampleCount
        self.dateByIndex = dateByIndex
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

    /// A metric's unit IS the axis it belongs on. Percentages, bpm, steps per
    /// point, metres and minutes cannot share one Y scale — plotted together,
    /// Swift Charts infers a single domain and the small-magnitude series
    /// flatten against the bottom. So a group renders one chart per unit
    /// present, in this order. Ratio-unit metrics (only W:UE today) stay the
    /// exception they always were: a single unbounded value per match reads
    /// better as a sparkline row than as a chart one match can blow out.
    private static let unitOrder: [TrendMetric.Unit] = [.percent, .bpm, .steps, .metres, .minutes]

    private func bucket(_ unit: TrendMetric.Unit) -> [TrendSeries] {
        series.filter { $0.metric.unit == unit }
    }
    private var ratioSeries: [TrendSeries] { series.filter { $0.metric.unit == .ratio } }

    @ViewBuilder
    private var standardBody: some View {
        if series.isEmpty || series.allSatisfy({ $0.points.isEmpty }) {
            emptyState
        } else {
            ForEach(Self.unitOrder, id: \.self) { unit in
                let shown = plottable(bucket(unit))
                // A bucket can be empty for two different reasons — no metric
                // of that unit in this group, or every one of them lacking
                // coverage in this window (a Health-free archive's bpm bucket).
                // Both mean "draw nothing here", not "draw an empty axis".
                if !shown.isEmpty && !shown.allSatisfy({ $0.points.isEmpty }) {
                    // Count mode plots raw numerators (whole-match step or
                    // metre totals), not the per-point rate the caption names,
                    // so the caption is suppressed rather than left lying.
                    if displayMode != .count, let caption = unit.axisCaption {
                        Text(caption)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    lineChart(for: shown, unit: unit)
                    selectionSummary(for: shown)
                    legend(for: shown)
                }
            }
            ForEach(ratioSeries) { s in
                TrendSparkline(series: s, displayMode: displayMode, color: s.metric.chartColor, sampleCount: sampleCount)
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

    /// `series`, filtering out — in Count mode only — any metric with
    /// `supportsCountMode == false` (aggressionIndex, ownErrorShare): its
    /// 0...1 fraction plotted against a raw-count axis would read as
    /// pinned near zero, so it drops out of Count mode rather than
    /// misrepresenting it. Every metric is plottable in Rate mode. Callers
    /// must route BOTH `lineChart(for:)` and `legend(for:)` through this
    /// same filtered list — passing the chart a filtered list and the
    /// legend the unfiltered one left a legend chip toggleable with no
    /// corresponding line to toggle (Codex review, PR #121).
    private func plottable(_ series: [TrendSeries]) -> [TrendSeries] {
        displayMode == .count ? series.filter { $0.metric.supportsCountMode } : series
    }

    /// `points` split into runs of consecutive `TrendPoint.index` values —
    /// the unit Swift Charts actually connects into one line. Charts groups
    /// `LineMark`s into a path by their `foregroundStyle(by:)` discriminator
    /// value alone, connecting every mark sharing that value in x-order
    /// regardless of any gap between them; simply omitting a missing index
    /// (as this used to do) does NOT produce a visual break (Codex review,
    /// PR #121) — a zero-UE match's `wueRatio` or a legacy match's
    /// rally-depth data with no ending-shot record would read as
    /// interpolated instead of genuinely missing. `lineMarks(for:)` gives
    /// each run its own discriminator value to force the break; the value
    /// itself is never shown to the user, since the legend is custom-built
    /// from `series` directly (`legend(for:)`/`staticLegend(for:)`), not
    /// from Chart's own style domain, which stays hidden via
    /// `.chartLegend(.hidden)`.
    private func runs(of points: [TrendPoint]) -> [[TrendPoint]] {
        var result: [[TrendPoint]] = []
        for point in points {
            if let lastIndex = result.last?.last?.index, point.index == lastIndex + 1 {
                result[result.count - 1].append(point)
            } else {
                result.append([point])
            }
        }
        return result
    }

    /// The internal, never-displayed discriminator `lineMarks(for:)` tags
    /// one run's marks with — must match `runColorScale(for:)`'s domain
    /// exactly, since that's what maps each run back to its metric's colour.
    private func runKey(_ metric: TrendMetric, _ runIndex: Int) -> String {
        "\(metric.rawValue)#\(runIndex)"
    }

    /// One discriminator-domain entry per RUN (not per metric, unlike
    /// `colorScale(for:)`), each mapped to its metric's single colour —
    /// what `lineChart(for:)`/`rallyDepthWinRateChart` need since
    /// `runKey(_:_:)` fragments one metric into several Chart-visible
    /// "series". `max(_, 1)` covers a metric with zero points: it still
    /// needs one domain entry so `.chartForegroundStyleScale` never sees an
    /// empty domain for a metric present in `series`.
    private func runColorScale(for series: [TrendSeries]) -> (domain: [String], range: [Color]) {
        var domain: [String] = []
        var range: [Color] = []
        for s in series {
            let runCount = max(runs(of: s.points).count, 1)
            for runIndex in 0..<runCount {
                domain.append(runKey(s.metric, runIndex))
                range.append(s.metric.chartColor)
            }
        }
        return (domain, range)
    }

    @ChartContentBuilder
    private func lineMarks(for s: TrendSeries) -> some ChartContent {
        ForEach(Array(runs(of: s.points).enumerated()), id: \.offset) { runIndex, run in
            ForEach(run) { point in
                LineMark(
                    x: .value("Match", point.index),
                    y: .value("Value", plottedValue(point))
                )
                .foregroundStyle(by: .value("Series", runKey(s.metric, runIndex)))
                .lineStyle(s.metric.isOpponentFramed
                    ? StrokeStyle(lineWidth: 2, dash: [4, 3])
                    : StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
                .symbol(Circle())
                .symbolSize(18)
            }
        }
    }

    /// The full scoped window's X domain — fixed to `0...sampleCount-1`
    /// independent of which indices the marks a chart actually draws cover.
    /// Swift Charts otherwise infers a `Chart`'s X-axis domain from the
    /// marks it's given, so a match at either EDGE of the window with no
    /// data for any currently-visible series (the newest match having only
    /// return points while Serve & Return shows "Serves In," say, or
    /// lacking ending-shot data entirely in Rally Depth) would silently
    /// shrink the inferred domain and stretch the nearest real match out to
    /// that edge — the same bug `TrendSparkline`'s `sampleCount` fixes for
    /// sparklines, recurring here at the chart level because the run-
    /// splitting fix (`lineMarks(for:)`/`areaMarks(for:)`) only stops
    /// Charts from CONNECTING across a gap, it doesn't pin the axis itself
    /// (Codex review, PR #121).
    private var chartXDomain: ClosedRange<Int> {
        0...max(sampleCount - 1, 0)
    }

    /// `chartXSelection`'s raw binding can publish an index outside
    /// `chartXDomain` when a drag continues past either plot edge — Swift
    /// Charts doesn't clamp this itself, which is exactly why
    /// `PointsGraphView.applyXSelection` already wraps its own binding the
    /// same way. Left unclamped, an out-of-range value fails both
    /// `chartXDomain.contains` (the `RuleMark` disappears) and
    /// `dateByIndex` (the readout disappears) while staying STORED, so the
    /// selection reads as lost but silently blocks the next gesture from
    /// registering as a change until it lands on a genuinely different
    /// value (Codex review, PR #121).
    private var clampedSelection: Binding<Int?> {
        Binding(
            get: { selectedIndex },
            set: { newValue in
                if let v = newValue {
                    selectedIndex = min(max(v, chartXDomain.lowerBound), chartXDomain.upperBound)
                } else {
                    selectedIndex = nil
                }
            }
        )
    }

    private static let axisDateFormat = Date.FormatStyle.dateTime.month(.abbreviated).day()

    /// The tap/drag-selected point's date plus each currently-visible
    /// metric's value at that match — the "selection readout" the plan
    /// always specified. `series` is whatever the calling chart body is
    /// showing (already display-mode- and hidden-metric-filtered where
    /// relevant), so this reads the same set of values the chart itself
    /// draws, never a wider or narrower one.
    @ViewBuilder
    private func selectionSummary(for series: [TrendSeries]) -> some View {
        if let selectedIndex, let date = dateByIndex[selectedIndex] {
            HStack(spacing: 10) {
                Text(date, format: Self.axisDateFormat)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(series) { s in
                    if !hiddenMetrics.contains(s.metric),
                       let point = s.points.first(where: { $0.index == selectedIndex }) {
                        HStack(spacing: 3) {
                            Circle().fill(s.metric.chartColor).frame(width: 6, height: 6)
                            Text(displayMode == .count && s.metric.supportsCountMode
                                ? s.metric.formatCount(point.ratio)
                                : s.metric.format(point.ratio))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)
        }
    }

    /// Draws `series` as a multi-line chart. Takes an explicit list (not
    /// just `self.series`) so callers can narrow to a subset — e.g. Serve &
    /// Return's filter picks 2 of its 6 metrics — and must already be
    /// display-mode-filtered via `plottable(_:)` before calling.
    private func lineChart(for series: [TrendSeries], unit: TrendMetric.Unit) -> some View {
        // Bound once: `runColorScale` walks every series' runs, and reading it
        // twice in the modifier below doubled that on every body pass — now
        // multiplied by however many unit buckets a group renders.
        let scale = runColorScale(for: series)
        return Chart {
            ForEach(series) { s in
                if !hiddenMetrics.contains(s.metric) {
                    lineMarks(for: s)
                }
            }
            if let selectedIndex, chartXDomain.contains(selectedIndex) {
                RuleMark(x: .value("Selected", selectedIndex))
                    .foregroundStyle(Color.secondary.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartForegroundStyleScale(domain: scale.domain, range: scale.range)
        .chartXScale(domain: chartXDomain)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(displayMode == .count ? "\(Int(v.rounded()))" : unit.axisText(v))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                if let idx = value.as(Int.self), let date = dateByIndex[idx] {
                    AxisGridLine()
                    AxisValueLabel { Text(date, format: Self.axisDateFormat).font(.caption2) }
                }
            }
        }
        .chartLegend(.hidden)
        .chartXSelection(value: clampedSelection)
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
            // All 6 Serve & Return metrics support Count mode today, so this
            // is a no-op filter in practice — routed through the same
            // helper as standardBody for a single source of truth, not two
            // copies of the same predicate to keep in sync.
            let shown = plottable(selected)
            // All six Serve & Return metrics are percentages; `unit` is passed
            // explicitly (rather than defaulted) so adding a bpm- or steps-unit
            // metric to this group fails to compile instead of quietly
            // rendering against a percentage axis.
            lineChart(for: shown, unit: .percent)
            selectionSummary(for: shown)
            legend(for: shown)
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
                selectionSummary(for: depthShareSeries)
                staticLegend(for: depthShareSeries)
            case .winRate:
                rallyDepthWinRateChart
                selectionSummary(for: depthWinSeries)
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

    /// Same run-splitting as `lineMarks(for:)` (see its doc comment),
    /// applied to `AreaMark`: normalized stacking groups whatever marks
    /// share an X value regardless of which run's discriminator they carry,
    /// so a match present for the other three depth-share metrics still
    /// stacks correctly — only a fully-absent index (a match with no
    /// ending-shot data at all, so all four series omit it) is affected,
    /// and that's exactly the case that must NOT be bridged over (Codex
    /// review, PR #121).
    @ChartContentBuilder
    private func areaMarks(for s: TrendSeries) -> some ChartContent {
        ForEach(Array(runs(of: s.points).enumerated()), id: \.offset) { runIndex, run in
            ForEach(run) { point in
                AreaMark(
                    x: .value("Match", point.index),
                    y: .value("Share", point.value),
                    stacking: .normalized
                )
                .foregroundStyle(by: .value("Series", runKey(s.metric, runIndex)))
            }
        }
    }

    private var rallyDepthStackedChart: some View {
        let scale = runColorScale(for: depthShareSeries)
        return Chart {
            ForEach(depthShareSeries) { s in
                areaMarks(for: s)
            }
            if let selectedIndex, chartXDomain.contains(selectedIndex) {
                RuleMark(x: .value("Selected", selectedIndex))
                    .foregroundStyle(Color.secondary.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartForegroundStyleScale(domain: scale.domain, range: scale.range)
        .chartXScale(domain: chartXDomain)
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
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                if let idx = value.as(Int.self), let date = dateByIndex[idx] {
                    AxisGridLine()
                    AxisValueLabel { Text(date, format: Self.axisDateFormat).font(.caption2) }
                }
            }
        }
        .chartLegend(.hidden)
        .chartXSelection(value: clampedSelection)
        .frame(height: 140)
    }

    private var rallyDepthWinRateChart: some View {
        let scale = runColorScale(for: depthWinSeries)
        return Chart {
            ForEach(depthWinSeries) { s in
                lineMarks(for: s)
            }
            if let selectedIndex, chartXDomain.contains(selectedIndex) {
                RuleMark(x: .value("Selected", selectedIndex))
                    .foregroundStyle(Color.secondary.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartForegroundStyleScale(domain: scale.domain, range: scale.range)
        .chartXScale(domain: chartXDomain)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(displayMode == .count
                             ? "\(Int(v.rounded()))"
                             : TrendMetric.Unit.percent.axisText(v))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                if let idx = value.as(Int.self), let date = dateByIndex[idx] {
                    AxisGridLine()
                    AxisValueLabel { Text(date, format: Self.axisDateFormat).font(.caption2) }
                }
            }
        }
        .chartLegend(.hidden)
        .chartXSelection(value: clampedSelection)
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
