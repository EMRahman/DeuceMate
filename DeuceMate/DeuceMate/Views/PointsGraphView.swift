// PointsGraphView.swift — Cumulative points chart for a match.
import SwiftUI
import Charts
import UIKit
import DeuceMateCore

private struct GraphEntry: Identifiable {
    let id: String    // "<pointIndex>-<player>" — unique per series and point
    let pointIndex: Int
    let player: String
    let count: Int
}

private struct HREntry: Identifiable {
    let id: Int       // 1-based point index
    let pointIndex: Int
    let bpm: Int
}

private struct StepEntry: Identifiable {
    let id: Int       // point index (0-based seed + 1-based points)
    let pointIndex: Int
    let cumulativeSteps: Int
    let perPointSteps: Int  // steps during this point (cumulative − previous cumulative)
}

/// Which steps series to render in the chart. Mirrors `HRSeriesMode`'s small
/// mode picker: cumulative running total (default) vs steps taken per point.
private enum StepsSeriesMode: String, CaseIterable, Identifiable {
    case cumulative
    case perPoint

    var id: String { rawValue }
    var label: String {
        switch self {
        case .cumulative: return String(localized: "Cumulative")
        case .perPoint:   return String(localized: "Per point")
        }
    }
}

// MARK: - Scatter overlay categories

private enum OutcomeCategory: String, CaseIterable, Identifiable {
    case doubleFault, winner, unforcedError, forcedError
    var id: String { rawValue }
    var label: String {
        switch self {
        case .doubleFault:    return "DF"
        case .winner:         return "W"
        case .unforcedError:  return "UE"
        case .forcedError:    return "FE"
        }
    }
    var color: Color {
        switch self {
        case .doubleFault:    return .orange
        case .winner:         return .yellow
        case .unforcedError:  return .red
        case .forcedError:    return .purple
        }
    }
    var symbol: BasicChartSymbolShape {
        switch self {
        case .doubleFault:    return .square
        case .winner:         return .circle
        case .unforcedError:  return .cross
        case .forcedError:    return .triangle
        }
    }
}

/// Scatter styling for the core `EndingShot` phases (Serve / Return / S+1 / Rally).
/// `displayLabel` already lives on the model; only chart color + symbol are view
/// concerns, so they hang off this file-private extension.
private extension EndingShot {
    var color: Color {
        switch self {
        case .serve:        return .teal
        case .return:       return .indigo
        case .servePlusOne: return .mint
        case .rally:        return .brown
        }
    }
    var symbol: BasicChartSymbolShape {
        switch self {
        case .serve:        return .pentagon
        case .return:       return .asterisk
        case .servePlusOne: return .plus
        case .rally:        return .triangle
        }
    }
}

private struct ScatterEntry: Identifiable {
    let id: String
    let pointIndex: Int
    let y: Int
    let color: Color
    let symbol: BasicChartSymbolShape
    let label: String
}

private struct SetBand: Identifiable {
    let id: String
    let setNumber: Int
    let isTiebreak: Bool
    let startX: Int
    let endX: Int

    var label: String { isTiebreak ? "TB" : "Set \(setNumber)" }

    /// Subtle but distinct fill so set 1 / set 2 / set 3 and tiebreak segments
    /// are visually obvious without overwhelming the line marks.
    var fill: Color {
        if isTiebreak { return Color.yellow.opacity(0.22) }
        switch setNumber {
        case 1:  return Color.blue.opacity(0.10)
        case 2:  return Color.orange.opacity(0.10)
        case 3:  return Color.purple.opacity(0.10)
        default: return Color.gray.opacity(0.10)
        }
    }
}

// MARK: - Data computation

/// Pure-value bundle of derived chart series for a given filter selection.
/// A single pass over `stats` at init time produces every series the chart
/// needs, so render frames during pinch/pan don't pay an O(N) cost per
/// computed property — and rebuilding the struct on filter change is cheap.
private struct PointsGraphData {
    let lineEntries: [GraphEntry]
    let scatterEntries: [ScatterEntry]
    let hrEntries: [HREntry]
    let stepEntries: [StepEntry]
    let setBands: [SetBand]
    let hrDomain: ClosedRange<Int>
    let xDomain: ClosedRange<Int>
    let hasOutcomeData: Bool
    /// Points the focal player (Me) won / lost, bucketed by the phase the point
    /// ended on. Tallied in the same single pass over `stats`; consumed by the
    /// Ending Shots chips to annotate each phase with its won–lost split and to
    /// hide phases (and the whole section) that have no ending-shot data.
    let endingWonByPhase: [EndingShot: Int]
    let endingLostByPhase: [EndingShot: Int]
    /// Total outcome counts for the focal player (Me) across the whole match.
    let myOutcomeCounts: [OutcomeCategory: Int]
    /// Total outcome counts attributed to the opponent across the whole match.
    let oppOutcomeCounts: [OutcomeCategory: Int]
    /// (me, opp) cumulative score at each pointIndex from 0…stats.count.
    /// Pre-computed so the selection summary can look up totals in O(1) per
    /// touch frame without re-walking the line series.
    let cumulativeByIndex: [(me: Int, opp: Int)]
    /// Scatter entries grouped by pointIndex. Drag gestures fire selection
    /// updates many times per second; this dictionary lets the summary view
    /// look up the dots at a touched point in O(1) without re-filtering the
    /// flat array each frame.
    let scatterByPoint: [Int: [ScatterEntry]]
    /// Full pre-point match-score snapshots, shared with the Points tab.
    let matchScoreByID: [PointStat.ID: PointMatchScore.Snapshot]
    /// The chart's x-axis is 1-based after each point; bridge that index back
    /// to the stable point id used by `PointMatchScore`.
    let idByIndex: [Int: PointStat.ID]
    /// Point numbering restarts within each set in the Points tab. Keep the
    /// same number here so a highlighted graph point can be cross-checked.
    let setPointNumberByIndex: [Int: Int]

    var hasHeartRateData: Bool { !hrEntries.isEmpty }
    var hasStepsData: Bool { !stepEntries.isEmpty }

    init(record: MatchRecord,
         selectedMyOutcomes: Set<OutcomeCategory>,
         selectedOpponentOutcomes: Set<OutcomeCategory>,
         selectedWonEndingShots: Set<EndingShot>,
         selectedLostEndingShots: Set<EndingShot>) {
        let stats = record.stats
        let totalSteps = record.totalSteps
        self.xDomain = 0...max(stats.count, 1)
        self.matchScoreByID = PointMatchScore.atStart(of: stats, record: record)

        let hasAnySelection = !selectedMyOutcomes.isEmpty
            || !selectedOpponentOutcomes.isEmpty
            || !selectedWonEndingShots.isEmpty
            || !selectedLostEndingShots.isEmpty
        let scatterEnabled = !stats.isEmpty && hasAnySelection

        var line: [GraphEntry] = []
        line.reserveCapacity((stats.count + 1) * 2)
        line.append(GraphEntry(id: "0-Me",       pointIndex: 0, player: "Me",       count: 0))
        line.append(GraphEntry(id: "0-Opponent", pointIndex: 0, player: "Opponent", count: 0))

        var scatter: [ScatterEntry] = []
        var hr: [HREntry] = []
        var hrMin = Int.max, hrMax = Int.min

        var m = 0, o = 0
        var hasOutcome = false
        var endWon: [EndingShot: Int] = [:]
        var endLost: [EndingShot: Int] = [:]
        var myOutcomes: [OutcomeCategory: Int] = [:]
        var oppOutcomes: [OutcomeCategory: Int] = [:]

        var bands: [SetBand] = []
        var bandStart: Int = 0
        var bandSetIndex: Int? = nil
        var bandTiebreak: Bool = false

        var cumulative: [(me: Int, opp: Int)] = [(0, 0)]
        cumulative.reserveCapacity(stats.count + 1)
        var idsByIndex: [Int: PointStat.ID] = [:]
        var pointNumbersByIndex: [Int: Int] = [:]
        var pointCountBySet: [Int: Int] = [:]

        // Single pass: cumulative line series, scatter overlay, HR overlay,
        // hasOutcomeData, HR min/max and per-point step samples derived in
        // one walk over stats.
        for (i, stat) in stats.enumerated() {
            if stat.winner == .me { m += 1 } else { o += 1 }
            cumulative.append((m, o))
            if !hasOutcome && stat.outcome != .uncategorized { hasOutcome = true }

            if let es = stat.endingShot {
                if stat.winner == .me { endWon[es, default: 0] += 1 }
                else                  { endLost[es, default: 0] += 1 }
            }

            for category in OutcomeCategory.allCases {
                if Self.matchesOutcome(category, stat: stat, focal: .me) {
                    myOutcomes[category, default: 0] += 1
                }
                if Self.matchesOutcome(category, stat: stat, focal: .opponent) {
                    oppOutcomes[category, default: 0] += 1
                }
            }

            let x = i + 1
            idsByIndex[x] = stat.id
            pointCountBySet[stat.setIndex, default: 0] += 1
            pointNumbersByIndex[x] = pointCountBySet[stat.setIndex]
            let pointTiebreak = stat.gameScoreAtStart?.isTiebreak ?? false

            if let current = bandSetIndex {
                // Close the current band on set change OR on tiebreak toggle within the same set.
                if current != stat.setIndex || bandTiebreak != pointTiebreak {
                    bands.append(SetBand(
                        id: "\(current)-\(bandStart)-\(bandTiebreak)",
                        setNumber: current + 1,
                        isTiebreak: bandTiebreak,
                        startX: bandStart,
                        endX: x - 1
                    ))
                    bandStart = x - 1
                    bandTiebreak = pointTiebreak
                }
            } else {
                bandTiebreak = pointTiebreak
            }
            bandSetIndex = stat.setIndex

            line.append(GraphEntry(id: "\(x)-Me",       pointIndex: x, player: "Me",       count: m))
            line.append(GraphEntry(id: "\(x)-Opponent", pointIndex: x, player: "Opponent", count: o))

            if let bpm = stat.heartRateBPM {
                hr.append(HREntry(id: x, pointIndex: x, bpm: bpm))
                if bpm < hrMin { hrMin = bpm }
                if bpm > hrMax { hrMax = bpm }
            }

            if scatterEnabled {
                // Me outcomes — plotted on the Me line
                for category in selectedMyOutcomes
                where Self.matchesOutcome(category, stat: stat, focal: .me) {
                    scatter.append(ScatterEntry(
                        id: "\(x)-me-\(category.rawValue)",
                        pointIndex: x,
                        y: m,
                        color: category.color,
                        symbol: category.symbol,
                        label: "My \(category.label)"
                    ))
                }
                // Opponent outcomes — plotted on the Opponent line
                for category in selectedOpponentOutcomes
                where Self.matchesOutcome(category, stat: stat, focal: .opponent) {
                    scatter.append(ScatterEntry(
                        id: "\(x)-opp-\(category.rawValue)",
                        pointIndex: x,
                        y: o,
                        color: category.color,
                        symbol: category.symbol,
                        label: "Opp \(category.label)"
                    ))
                }
                // Ending shots framed as won / lost by phase. A point the focal
                // player won is plotted on the Me line; a lost point on the
                // Opponent line — so won-vs-lost reads off the marker's line,
                // while the phase colour/symbol says where the point was decided.
                if let es = stat.endingShot {
                    if stat.winner == .me, selectedWonEndingShots.contains(es) {
                        scatter.append(ScatterEntry(
                            id: "\(x)-won-end-\(es.rawValue)",
                            pointIndex: x,
                            y: m,
                            color: es.color,
                            symbol: es.symbol,
                            label: "Won @ \(es.displayLabel)"
                        ))
                    }
                    if stat.winner == .opponent, selectedLostEndingShots.contains(es) {
                        scatter.append(ScatterEntry(
                            id: "\(x)-lost-end-\(es.rawValue)",
                            pointIndex: x,
                            y: o,
                            color: es.color,
                            symbol: es.symbol,
                            label: "Lost @ \(es.displayLabel)"
                        ))
                    }
                }
            }
        }

        if let current = bandSetIndex {
            bands.append(SetBand(
                id: "\(current)-\(bandStart)-\(bandTiebreak)",
                setNumber: current + 1,
                isTiebreak: bandTiebreak,
                startX: bandStart,
                endX: stats.count
            ))
        }
        self.cumulativeByIndex = cumulative
        self.scatterByPoint = Dictionary(grouping: scatter, by: \.pointIndex)
        self.idByIndex = idsByIndex
        self.setPointNumberByIndex = pointNumbersByIndex

        self.lineEntries = line
        self.scatterEntries = scatter
        self.hrEntries = hr
        self.setBands = bands
        self.hasOutcomeData = hasOutcome
        self.endingWonByPhase = endWon
        self.endingLostByPhase = endLost
        self.myOutcomeCounts = myOutcomes
        self.oppOutcomeCounts = oppOutcomes

        if hr.isEmpty {
            self.hrDomain = 50...200
        } else {
            let lo = max(40, hrMin - 10)
            let hi = hrMax + 10
            self.hrDomain = lo...max(hi, lo + 20)
        }

        // Steps series derivation is shared with the HTML export via Core's
        // StepsSeries (single source of truth). Core uses 0-based point indices;
        // map them onto the graph's 1-based x-axis and prepend a seed at x=0 so
        // the line starts at the chart origin.
        let coreSteps = StepsSeries.make(stats: stats, totalSteps: totalSteps)
        if coreSteps.isEmpty {
            self.stepEntries = []
        } else {
            var out: [StepEntry] = [StepEntry(id: 0, pointIndex: 0, cumulativeSteps: 0, perPointSteps: 0)]
            out.reserveCapacity(coreSteps.count + 1)
            for p in coreSteps {
                let x = p.pointIndex + 1
                out.append(StepEntry(id: x, pointIndex: x,
                                     cumulativeSteps: p.cumulative,
                                     perPointSteps: p.perPoint))
            }
            self.stepEntries = out
        }
    }

    /// Outcome attribution rules (from MatchStatsSummary):
    /// - DF: focal was the server and outcome is doubleFault.
    /// - Winner: focal won the point with a winner.
    /// - UE / FE: focal lost the point (opponent won) and the outcome was UE/FE.
    private static func matchesOutcome(_ category: OutcomeCategory,
                                       stat: PointStat,
                                       focal: Player) -> Bool {
        let other: Player = focal == .me ? .opponent : .me
        switch category {
        case .doubleFault:
            return stat.server == focal && stat.outcome == .doubleFault
        case .winner:
            return stat.winner == focal && stat.outcome == .winner
        case .unforcedError:
            return stat.winner == other && stat.outcome == .unforcedError
        case .forcedError:
            return stat.winner == other && stat.outcome == .forcedError
        }
    }
}

// MARK: - HR series helpers (shared by inline & expanded views)

/// Centered moving average of window 5 over the snapshot HREntry series.
private func smoothedHREntries(_ entries: [HREntry]) -> [HREntry] {
    guard entries.count >= 2 else { return entries }
    let half = 2
    return entries.enumerated().map { i, e in
        let lo = max(0, i - half)
        let hi = min(entries.count - 1, i + half)
        let slice = entries[lo...hi]
        let avg = Int((Double(slice.reduce(0) { $0 + $1.bpm }) / Double(slice.count)).rounded())
        return HREntry(id: e.id, pointIndex: e.pointIndex, bpm: avg)
    }
}

/// Converts averaged [HRChartPoint] (0-based, timestamp-sorted from the fetcher)
/// into [HREntry] using the 1-based indices that PointsGraphData assigned.
/// Fast path when stats are already in timestamp order (the common case) avoids
/// an O(N log N) sort and dictionary allocation on every render frame during
/// pan/zoom. Falls back to the ID-based mapping for unsorted arrays.
private func averagedHREntries(from pts: [HRChartPoint], stats: [PointStat]) -> [HREntry] {
    let isSorted = zip(stats, stats.dropFirst()).allSatisfy { $0.timestamp <= $1.timestamp }
    if isSorted {
        return pts.compactMap { hp -> HREntry? in
            let graphIdx = hp.pointIndex + 1
            guard graphIdx <= stats.count else { return nil }
            return HREntry(id: graphIdx, pointIndex: graphIdx, bpm: hp.bpm)
        }
    }
    let sorted = stats.sorted { $0.timestamp < $1.timestamp }
    var idxByID: [UUID: Int] = [:]
    idxByID.reserveCapacity(stats.count)
    for (i, stat) in stats.enumerated() { idxByID[stat.id] = i + 1 }
    // Sort by pointIndex so LineMark connects left-to-right; the slow path
    // emits entries in timestamp order which may not match graph order.
    return pts.compactMap { hp -> HREntry? in
        guard hp.pointIndex < sorted.count else { return nil }
        guard let graphIdx = idxByID[sorted[hp.pointIndex].id] else { return nil }
        return HREntry(id: graphIdx, pointIndex: graphIdx, bpm: hp.bpm)
    }.sorted { $0.pointIndex < $1.pointIndex }
}

/// `loadedAveraged` is the already-extracted `.loaded` payload from the
/// fetcher's state, or nil when idle/loading/failed. Callers extract it on
/// the main actor before passing it here so these pure functions stay actor-free.
private func activeHREntries(
    mode: HRSeriesMode,
    data: PointsGraphData,
    loadedAveraged: [HRChartPoint]?,
    stats: [PointStat]
) -> [HREntry] {
    switch mode {
    case .snapshot: return data.hrEntries
    case .smoothed: return smoothedHREntries(data.hrEntries)
    case .averaged:
        guard let pts = loadedAveraged else { return [] }
        return averagedHREntries(from: pts, stats: stats)
    }
}

// MARK: - Chart core (shared by inline & expanded views)

/// Renders the primary cumulative-points line chart and its optional HR /
/// steps overlays. Pan / zoom is opt-in via the scrollable parameters — the
/// inline view leaves them `nil`; the expanded view supplies them to enable
/// native horizontal scrolling synced across all three charts.
private struct PointsChartCore: View {
    let data: PointsGraphData
    let meColor: Color
    let oppColor: Color
    let height: CGFloat
    /// When non-nil, applies `chartScrollableAxes(.horizontal)` +
    /// `chartXVisibleDomain(length:)` + `chartScrollPosition(x:)` so all three
    /// charts pan/zoom in lockstep with the binding owner.
    let visibleDomainLength: Int?
    let scrollPositionX: Binding<Int>?
    let showHeartRate: Bool
    let showSteps: Bool
    /// Active steps series to render (cumulative total / per-point).
    let stepsSeriesMode: StepsSeriesMode
    let showXAxis: Bool
    /// Currently selected x value driven by touch / drag on the chart. The
    /// parent renders a summary view next to the chart using this index.
    let selectedX: Binding<Int?>?
    /// Active HR series to render (snapshot / smoothed / averaged). The caller
    /// computes the correct series; the chart just plots what it receives.
    let activeHREntries: [HREntry]

    private var activeHRDomain: ClosedRange<Int> {
        let bpms = activeHREntries.map { $0.bpm }
        guard let minBPM = bpms.min(), let maxBPM = bpms.max() else { return data.hrDomain }
        let lo = max(40, minBPM - 10)
        let hi = maxBPM + 10
        return lo...max(hi, lo + 20)
    }

    /// Steps value to plot for the active mode.
    private func stepsValue(_ e: StepEntry) -> Int {
        stepsSeriesMode == .cumulative ? e.cumulativeSteps : e.perPointSteps
    }

    /// Upper bound for the steps Y-axis, derived from the active series.
    private var activeStepsYMax: Int {
        max(data.stepEntries.map(stepsValue).max() ?? 1, 1)
    }

    var body: some View {
        primaryChart
            .frame(height: height)
            .overlay {
                if showHeartRate && data.hasHeartRateData {
                    hrOverlayChart
                }
            }
            .overlay {
                if showSteps && data.hasStepsData {
                    stepsOverlayChart
                }
            }
    }

    private var primaryChart: some View {
        Chart {
            ForEach(data.setBands) { band in
                RectangleMark(
                    xStart: .value("Set Start", band.startX),
                    xEnd:   .value("Set End",   band.endX)
                )
                .foregroundStyle(band.fill)
                .annotation(position: .top, alignment: .center, spacing: 1) {
                    Text(band.label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(band.isTiebreak ? .orange : .secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(Color(.systemBackground).opacity(0.75))
                        )
                }
            }
            ForEach(data.lineEntries) { e in
                LineMark(
                    x: .value("Point", e.pointIndex),
                    y: .value("Points Won", e.count)
                )
                .foregroundStyle(by: .value("Player", e.player))
                .interpolationMethod(.stepEnd)
            }
            ForEach(data.scatterEntries) { s in
                PointMark(
                    x: .value("Point", s.pointIndex),
                    y: .value("Points Won", s.y)
                )
                .foregroundStyle(s.color)
                .symbol(s.symbol)
                .symbolSize(70)
            }
            if let x = selectedX?.wrappedValue, x >= 0, x <= max(data.cumulativeByIndex.count - 1, 0) {
                RuleMark(x: .value("Selected", x))
                    .foregroundStyle(Color.secondary.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartForegroundStyleScale(["Me": meColor, "Opponent": oppColor])
        .chartXScale(domain: data.xDomain)
        .applyChartXAxisVisible(showXAxis)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine()
                AxisValueLabel()
            }
            // Invisible trailing placeholder reserves the same horizontal margin as the
            // secondary overlay axes, ensuring all three chart plot areas align on X.
            AxisMarks(position: .trailing, values: [0]) { _ in
                AxisValueLabel { Text("000").font(.caption2).opacity(0) }
            }
        }
        .chartLegend(.hidden)
        .applyScrollable(visibleDomainLength: visibleDomainLength,
                         scrollPositionX: scrollPositionX)
        .applyXSelection(selectedX, maxX: data.cumulativeByIndex.count - 1)
    }

    // MARK: - Heart rate overlay (scatter, secondary Y-axis on right)

    private var hrOverlayChart: some View {
        Chart {
            ForEach(activeHREntries) { hr in
                LineMark(
                    x: .value("Point", hr.pointIndex),
                    y: .value("BPM", hr.bpm)
                )
                .foregroundStyle(Color.red.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.monotone)
            }
        }
        .chartXScale(domain: data.xDomain)
        .applyOverlayXAxis(showXAxis)
        .chartYScale(domain: activeHRDomain)
        .chartYAxis {
            // Invisible leading placeholder matches primary chart's leading axis width.
            AxisMarks(position: .leading, values: [activeHRDomain.upperBound]) { _ in
                AxisValueLabel { Text("000").font(.caption2).opacity(0) }
            }
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text("\(v)")
                            .font(.caption2)
                            .foregroundStyle(Color.red.opacity(0.85))
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .background(.clear)
        .allowsHitTesting(false)
        .applyScrollable(visibleDomainLength: visibleDomainLength,
                         scrollPositionX: scrollPositionX)
    }

    // MARK: - Steps overlay (line, secondary Y-axis on right)

    private var stepsOverlayChart: some View {
        let yMax = activeStepsYMax
        return Chart {
            ForEach(data.stepEntries) { s in
                LineMark(
                    x: .value("Point", s.pointIndex),
                    y: .value("Steps", stepsValue(s))
                )
                .foregroundStyle(Color.green.opacity(0.75))
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
            }
        }
        .chartXScale(domain: data.xDomain)
        .applyOverlayXAxis(showXAxis)
        .chartYScale(domain: 0...yMax)
        .chartYAxis {
            // Invisible leading placeholder matches primary chart's leading axis width.
            AxisMarks(position: .leading, values: [yMax]) { _ in
                AxisValueLabel { Text("000").font(.caption2).opacity(0) }
            }
            // Always render a trailing label so the steps plot area reserves the
            // same right-axis width as the primary/HR charts (otherwise an empty
            // label collapses the axis and the line spills over the x-axis
            // baseline and into the label gutter). When the HR overlay owns the
            // visible right axis, render the same fixed-width invisible "000"
            // placeholder used on the leading edge (and the primary chart) so the
            // reserved width is constant regardless of the formatted step values.
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if showHeartRate {
                        Text("000").font(.caption2).opacity(0)
                    } else if let v = value.as(Int.self) {
                        Text(v >= 1000 ? "\(v / 1000)k" : "\(v)")
                            .font(.caption2)
                            .foregroundStyle(Color.green.opacity(0.85))
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .background(.clear)
        .allowsHitTesting(false)
        .applyScrollable(visibleDomainLength: visibleDomainLength,
                         scrollPositionX: scrollPositionX)
    }
}

private extension View {
    @ViewBuilder
    func applyChartXAxisVisible(_ visible: Bool) -> some View {
        if visible {
            self
        } else {
            self.chartXAxis(.hidden)
        }
    }

    @ViewBuilder
    func applyOverlayXAxis(_ showPrimary: Bool) -> some View {
        if showPrimary {
            // Phantom x-axis: reserves the same bottom inset as the primary
            // chart's real x-axis so all three plot areas align vertically.
            self.chartXAxis {
                AxisMarks(values: [0]) { _ in
                    AxisValueLabel { Text("0").opacity(0) }
                }
            }
        } else {
            self.chartXAxis(.hidden)
        }
    }

    @ViewBuilder
    func applyScrollable(visibleDomainLength: Int?,
                         scrollPositionX: Binding<Int>?) -> some View {
        if let length = visibleDomainLength, let scroll = scrollPositionX {
            self
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: length)
                .chartScrollPosition(x: scroll)
        } else {
            self
        }
    }

    /// Wires up tap / drag x-selection. Swift Charts reports the raw value
    /// under the touch (which can fall outside the valid point range during
    /// drag-past-the-edge); we clamp here so the summary always references a
    /// real point index.
    @ViewBuilder
    func applyXSelection(_ binding: Binding<Int?>?, maxX: Int) -> some View {
        if let binding {
            let clamped = Binding<Int?>(
                get: { binding.wrappedValue },
                set: { newValue in
                    if let v = newValue {
                        binding.wrappedValue = max(0, min(maxX, v))
                    } else {
                        binding.wrappedValue = nil
                    }
                }
            )
            self.chartXSelection(value: clamped)
        } else {
            self
        }
    }
}

// MARK: - Shared controls (legend, scatter chips, toggles)

private struct PointsGraphLegend: View {
    let meColor: Color
    let oppColor: Color
    let showHeartRate: Bool
    let hasHeartRateData: Bool
    let showSteps: Bool
    let hasStepsData: Bool

    var body: some View {
        HStack(spacing: 14) {
            legendItem(color: meColor,  label: "Me",       style: .line)
            legendItem(color: oppColor, label: "Opponent", style: .line)
            if showHeartRate && hasHeartRateData {
                legendItem(color: .red.opacity(0.75),  label: "Heart Rate", style: .line)
            }
            if showSteps && hasStepsData {
                legendItem(color: .green.opacity(0.8), label: "Steps",      style: .dash)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private enum LegendStyle { case line, dash, dot }

    @ViewBuilder
    private func legendItem(color: Color, label: String, style: LegendStyle) -> some View {
        HStack(spacing: 4) {
            switch style {
            case .line:
                Rectangle().fill(color).frame(width: 12, height: 2)
            case .dash:
                HStack(spacing: 2) {
                    Rectangle().fill(color).frame(width: 5, height: 2)
                    Rectangle().fill(color).frame(width: 5, height: 2)
                }
            case .dot:
                Circle().fill(color).frame(width: 6, height: 6)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PointsGraphScatterControls: View {
    @Binding var selectedMyOutcomes: Set<OutcomeCategory>
    @Binding var selectedOpponentOutcomes: Set<OutcomeCategory>
    @Binding var selectedWonEndingShots: Set<EndingShot>
    @Binding var selectedLostEndingShots: Set<EndingShot>
    let wonByPhase: [EndingShot: Int]
    let lostByPhase: [EndingShot: Int]
    let myOutcomeCounts: [OutcomeCategory: Int]
    let oppOutcomeCounts: [OutcomeCategory: Int]

    private var isPointsWonActive: Bool {
        selectedMyOutcomes == [.winner] &&
        selectedOpponentOutcomes == [.unforcedError, .forcedError, .doubleFault]
    }

    private var isPointsLostActive: Bool {
        selectedMyOutcomes == [.unforcedError, .forcedError, .doubleFault] &&
        selectedOpponentOutcomes == [.winner]
    }

    /// Phases that actually occurred this match (won + lost > 0), in rally order.
    /// Drives the chips and lets the whole Ending Shots section hide when the
    /// match has no ending-shot data (e.g. detailed shot tracking was off).
    private var presentEndingPhases: [EndingShot] {
        EndingShot.allCases.filter { (wonByPhase[$0] ?? 0) + (lostByPhase[$0] ?? 0) > 0 }
    }

    private var isAllWonPhasesActive: Bool {
        !presentEndingPhases.isEmpty && selectedWonEndingShots == Set(presentEndingPhases)
    }
    private var isAllLostPhasesActive: Bool {
        !presentEndingPhases.isEmpty && selectedLostEndingShots == Set(presentEndingPhases)
    }

    /// Total points I won: my winners + the opponent's errors. Mirrors the
    /// selection `isPointsWonActive` toggles on.
    private var pointsWonCount: Int {
        (myOutcomeCounts[.winner] ?? 0)
            + (oppOutcomeCounts[.unforcedError] ?? 0)
            + (oppOutcomeCounts[.forcedError] ?? 0)
            + (oppOutcomeCounts[.doubleFault] ?? 0)
    }
    /// Total points I lost: the opponent's winners + my own errors.
    private var pointsLostCount: Int {
        (oppOutcomeCounts[.winner] ?? 0)
            + (myOutcomeCounts[.unforcedError] ?? 0)
            + (myOutcomeCounts[.forcedError] ?? 0)
            + (myOutcomeCounts[.doubleFault] ?? 0)
    }
    private var allWonPhasesCount: Int {
        presentEndingPhases.reduce(0) { $0 + (wonByPhase[$1] ?? 0) }
    }
    private var allLostPhasesCount: Int {
        presentEndingPhases.reduce(0) { $0 + (lostByPhase[$1] ?? 0) }
    }

    private var endingQuickSelectRow: some View {
        // Mirrors the Points Won/Lost radio: the two quick-selects are mutually
        // exclusive, so activating one clears the other. Individual Won/Lost
        // pills can still be toggled manually to show both sides at once.
        HStack(spacing: 6) {
            quickSelectChip(label: "All Won \(allWonPhasesCount)", color: .green, isOn: isAllWonPhasesActive) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isAllWonPhasesActive {
                        selectedWonEndingShots = []
                    } else {
                        selectedWonEndingShots = Set(presentEndingPhases)
                        selectedLostEndingShots = []
                    }
                }
            }
            quickSelectChip(label: "All Lost \(allLostPhasesCount)", color: .red, isOn: isAllLostPhasesActive) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isAllLostPhasesActive {
                        selectedLostEndingShots = []
                    } else {
                        selectedLostEndingShots = Set(presentEndingPhases)
                        selectedWonEndingShots = []
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var quickSelectRow: some View {
        HStack(spacing: 6) {
            quickSelectChip(label: "Points Won \(pointsWonCount)", color: .green, isOn: isPointsWonActive) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isPointsWonActive {
                        selectedMyOutcomes = []
                        selectedOpponentOutcomes = []
                    } else {
                        selectedMyOutcomes = [.winner]
                        selectedOpponentOutcomes = [.unforcedError, .forcedError, .doubleFault]
                    }
                }
            }
            quickSelectChip(label: "Points Lost \(pointsLostCount)", color: .red, isOn: isPointsLostActive) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isPointsLostActive {
                        selectedMyOutcomes = []
                        selectedOpponentOutcomes = []
                    } else {
                        selectedMyOutcomes = [.unforcedError, .forcedError, .doubleFault]
                        selectedOpponentOutcomes = [.winner]
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    var body: some View {
        VStack(spacing: 12) {
            section(title: "Outcomes") {
                quickSelectRow
                chipRow(
                    title: "Me",
                    items: OutcomeCategory.allCases,
                    isSelected: { selectedMyOutcomes.contains($0) },
                    toggle: { selectedMyOutcomes.formSymmetricDifference([$0]) },
                    label: { "\($0.label) \(myOutcomeCounts[$0] ?? 0)" },
                    color: { $0.color }
                )
                chipRow(
                    title: "Opp",
                    items: OutcomeCategory.allCases,
                    isSelected: { selectedOpponentOutcomes.contains($0) },
                    toggle: { selectedOpponentOutcomes.formSymmetricDifference([$0]) },
                    label: { "\($0.label) \(oppOutcomeCounts[$0] ?? 0)" },
                    color: { $0.color }
                )
            }

            if !presentEndingPhases.isEmpty {
                section(title: "Ending Shots") {
                    endingQuickSelectRow
                    chipRow(
                        title: "Won",
                        items: presentEndingPhases,
                        isSelected: { selectedWonEndingShots.contains($0) },
                        toggle: { selectedWonEndingShots.formSymmetricDifference([$0]) },
                        label: { "\($0.displayLabel) \(wonByPhase[$0] ?? 0)" },
                        color: { $0.color }
                    )
                    chipRow(
                        title: "Lost",
                        items: presentEndingPhases,
                        isSelected: { selectedLostEndingShots.contains($0) },
                        toggle: { selectedLostEndingShots.formSymmetricDifference([$0]) },
                        label: { "\($0.displayLabel) \(lostByPhase[$0] ?? 0)" },
                        color: { $0.color }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 4)
            content()
        }
    }

    @ViewBuilder
    private func chipRow<T: Hashable>(
        title: String,
        items: [T],
        isSelected: @escaping (T) -> Bool,
        toggle: @escaping (T) -> Void,
        label: @escaping (T) -> String,
        color: @escaping (T) -> Color
    ) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(minWidth: 32, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(items, id: \.self) { item in
                        scatterChip(
                            label: label(item),
                            color: color(item),
                            isOn: isSelected(item)
                        ) {
                            withAnimation(.easeInOut(duration: 0.15)) { toggle(item) }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 4)
    }

    private func quickSelectChip(
        label: String,
        color: Color,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isOn ? color : .secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(isOn ? color.opacity(0.15) : Color(.systemFill)))
                .overlay(Capsule().strokeBorder(isOn ? color.opacity(0.45) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func scatterChip(
        label: String,
        color: Color,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(label).font(.caption2.weight(.medium))
            }
            .foregroundStyle(isOn ? color : .secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(isOn ? color.opacity(0.15) : Color(.systemFill)))
            .overlay(Capsule().strokeBorder(isOn ? color.opacity(0.45) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Compact summary rendered above the chart while the user touches it.
/// Shows cumulative points won plus the selected point's serving side,
/// pre-point game/match score, set-relative number, and any scatter chips.
private struct PointsGraphSelectionSummary: View {
    let pointIndex: Int
    let setPointNumber: Int?
    let point: PointStat?
    let matchScore: PointMatchScore.Snapshot?
    let me: Int
    let opp: Int
    let scatter: [ScatterEntry]
    let meColor: Color
    let oppColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(pointLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                scoreBadge(label: "Me",  count: me,  color: meColor)
                scoreBadge(label: "Opp", count: opp, color: oppColor)

                if !scatter.isEmpty {
                    Divider().frame(height: 12)
                    HStack(spacing: 4) {
                        ForEach(scatter) { s in
                            Text(s.label)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(s.color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(s.color.opacity(0.15)))
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            if let point {
                HStack(spacing: 5) {
                    Text("🎾")
                        .accessibilityHidden(true)
                    Text(point.server == .me ? "Me serving" : "Opp serving")
                    if let gameScore = point.gameScoreAtStart {
                        Text("·")
                        Text(GameScoreLabel.string(for: gameScore, server: point.server))
                            .monospacedDigit()
                    }
                    if let matchScore, !matchScore.label.isEmpty {
                        Text("·")
                        Text(matchScore.label)
                            .monospacedDigit()
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 0.5)
                )
        )
        .frame(maxWidth: .infinity)
        .transition(.opacity)
    }

    private var pointLabel: String {
        guard let point else { return "Start" }
        return "Set \(point.setIndex + 1) · Pt \(setPointNumber ?? pointIndex)"
    }

    private func scoreBadge(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(label) \(count)")
                .font(.caption.weight(.medium))
                .monospacedDigit()
        }
    }
}

private struct PointsGraphToggleRow: View {
    let hasHeartRateData: Bool
    let hasStepsData: Bool
    @Binding var showHeartRate: Bool
    @Binding var showSteps: Bool
    @Binding var hrSeriesMode: HRSeriesMode
    @Binding var stepsSeriesMode: StepsSeriesMode
    @ObservedObject var fetcher: HealthKitHRFetcher

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            if hasStepsData {
                VStack(alignment: .center, spacing: 4) {
                    toggleChip(label: "Steps", systemImage: "figure.walk", color: .green, isOn: $showSteps)
                    if showSteps {
                        stepsModePicker
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            if hasHeartRateData {
                VStack(alignment: .center, spacing: 4) {
                    toggleChip(label: "Heart Rate", systemImage: "heart.fill", color: .red, isOn: $showHeartRate)
                    if showHeartRate {
                        hrModePicker
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        if hrSeriesMode == .averaged {
                            averagedStatus
                                .transition(.opacity)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .animation(.easeInOut(duration: 0.2), value: showHeartRate)
        .animation(.easeInOut(duration: 0.15), value: hrSeriesMode)
        .animation(.easeInOut(duration: 0.2), value: showSteps)
        .animation(.easeInOut(duration: 0.15), value: stepsSeriesMode)
    }

    private var stepsModePicker: some View {
        HStack(spacing: 6) {
            ForEach(StepsSeriesMode.allCases) { mode in
                Button {
                    stepsSeriesMode = mode
                } label: {
                    Text(mode.label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(stepsSeriesMode == mode ? Color.green : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(stepsSeriesMode == mode ? Color.green.opacity(0.12) : Color(.systemFill)))
                        .overlay(Capsule().strokeBorder(stepsSeriesMode == mode ? Color.green.opacity(0.35) : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var hrModePicker: some View {
        HStack(spacing: 6) {
            ForEach(HRSeriesMode.allCases) { mode in
                Button {
                    hrSeriesMode = mode
                } label: {
                    Text(mode.label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(hrSeriesMode == mode ? Color.red : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(hrSeriesMode == mode ? Color.red.opacity(0.12) : Color(.systemFill)))
                        .overlay(Capsule().strokeBorder(hrSeriesMode == mode ? Color.red.opacity(0.35) : Color.clear, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var averagedStatus: some View {
        switch fetcher.state {
        case .loading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Loading samples from Health…")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        case .unavailable:
            Text("Health data isn't available on this device.")
                .font(.caption2).foregroundStyle(.secondary)
        case .denied:
            Text("Allow heart-rate access in Settings › Health to see the per-point average.")
                .font(.caption2).foregroundStyle(.secondary)
        case .empty:
            Text("No heart-rate samples were recorded during this match.")
                .font(.caption2).foregroundStyle(.secondary)
        case .failed(let msg):
            Text("Couldn't load Health data: \(msg)")
                .font(.caption2).foregroundStyle(.secondary)
        case .loaded, .idle:
            EmptyView()
        }
    }

    private func toggleChip(
        label: String,
        systemImage: String,
        color: Color,
        isOn: Binding<Bool>
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { isOn.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.caption2)
                Text(label).font(.caption2.weight(.medium))
            }
            .foregroundStyle(isOn.wrappedValue ? color : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(isOn.wrappedValue ? color.opacity(0.15) : Color(.systemFill)))
            .overlay(Capsule().strokeBorder(isOn.wrappedValue ? color.opacity(0.4) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Inline points graph (embedded in MatchDetailView's list)

struct PointsGraphView: View {
    let record: MatchRecord
    private var stats: [PointStat] { record.stats }

    @Environment(\.appTheme) private var theme
    private var meColor:  Color { theme.colors.me }
    private var oppColor: Color { theme.colors.opponent }

    /// Owns the HR fetcher so loaded Health samples survive open/close of the
    /// full-screen cover (the expanded view observes it). The inline chart has
    /// no HR UI of its own — overlay and filter controls all live full-screen.
    @StateObject private var fetcher = HealthKitHRFetcher()

    // Full-screen graph configuration. Held here — not in the expanded view — so
    // a user's filter / overlay choices persist across opens of the cover. The
    // inline chart deliberately ignores these and always renders clean; only the
    // expanded view binds to and mutates them.
    @State private var selectedMyOutcomes: Set<OutcomeCategory> = []
    @State private var selectedOpponentOutcomes: Set<OutcomeCategory> = []
    @State private var selectedWonEndingShots: Set<EndingShot> = []
    @State private var selectedLostEndingShots: Set<EndingShot> = []
    @State private var showHeartRate = false
    @State private var showSteps = false
    @State private var hrSeriesMode: HRSeriesMode = .snapshot
    @State private var stepsSeriesMode: StepsSeriesMode = .cumulative

    @State private var isExpanded = false
    @State private var selectedX: Int?

    private static let chartHeight: CGFloat = 220

    var body: some View {
        // Inline chart is intentionally read-only: no outcome filters and no
        // HR/Steps overlays, so it builds with empty selections and the overlays
        // off. Tap-to-select still surfaces the running score.
        let data = PointsGraphData(
            record: record,
            selectedMyOutcomes: [],
            selectedOpponentOutcomes: [],
            selectedWonEndingShots: [],
            selectedLostEndingShots: []
        )

        return Group {
            if stats.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No Points to Graph")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    selectionSummary(data: data)

                    PointsChartCore(
                        data: data,
                        meColor: meColor,
                        oppColor: oppColor,
                        height: Self.chartHeight,
                        visibleDomainLength: nil,
                        scrollPositionX: nil,
                        showHeartRate: false,
                        showSteps: false,
                        stepsSeriesMode: .cumulative,
                        showXAxis: false,
                        selectedX: $selectedX,
                        activeHREntries: []
                    )
                    .overlay(alignment: .topTrailing) {
                        expandButton
                    }

                    PointsGraphLegend(
                        meColor: meColor,
                        oppColor: oppColor,
                        showHeartRate: false,
                        hasHeartRateData: data.hasHeartRateData,
                        showSteps: false,
                        hasStepsData: data.hasStepsData
                    )
                    .padding(.top, 8)

                    // Outcome / ending-shot filters and the HR/Steps overlay toggles now
                    // live only in the full-screen view, where there's room to interact
                    // with them alongside pinch-to-zoom. This hint keeps them discoverable
                    // and doubles as a second tap target for expanding.
                    if let hint = expandHintText(data: data) {
                        Button { isExpanded = true } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                Text(hint)
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                        .accessibilityHint("Opens the full-screen Points Graph")
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .fullScreenCover(isPresented: $isExpanded) {
            ExpandedPointsGraphView(
                record: record,
                selectedMyOutcomes: $selectedMyOutcomes,
                selectedOpponentOutcomes: $selectedOpponentOutcomes,
                selectedWonEndingShots: $selectedWonEndingShots,
                selectedLostEndingShots: $selectedLostEndingShots,
                showHeartRate: $showHeartRate,
                showSteps: $showSteps,
                hrSeriesMode: $hrSeriesMode,
                stepsSeriesMode: $stepsSeriesMode,
                fetcher: fetcher
            )
        }
    }

    private var expandButton: some View {
        Button {
            isExpanded = true
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(7)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(6)
        .accessibilityLabel("Expand Points Graph")
    }

    /// Caption under the inline chart naming what the full-screen view adds.
    /// Returns nil when the match has neither categorized outcomes nor HR/Steps
    /// data, so we never advertise controls that wouldn't appear there.
    private func expandHintText(data: PointsGraphData) -> String? {
        let canFilter = data.hasOutcomeData
        let canOverlay = data.hasHeartRateData || data.hasStepsData
        switch (canFilter, canOverlay) {
        case (true, true):   return String(localized: "Expand to filter outcomes & add overlays")
        case (true, false):  return String(localized: "Expand to filter outcomes")
        case (false, true):  return String(localized: "Expand to add heart rate & steps")
        case (false, false): return nil
        }
    }

    @ViewBuilder
    private func selectionSummary(data: PointsGraphData) -> some View {
        if let x = selectedX,
           x >= 0,
           x < data.cumulativeByIndex.count {
            let totals = data.cumulativeByIndex[x]
            let scatter = data.scatterByPoint[x] ?? []
            let point = x > 0 && x <= stats.count ? stats[x - 1] : nil
            let matchScore = data.idByIndex[x].flatMap { data.matchScoreByID[$0] }
            PointsGraphSelectionSummary(
                pointIndex: x,
                setPointNumber: data.setPointNumberByIndex[x],
                point: point,
                matchScore: matchScore,
                me: totals.me,
                opp: totals.opp,
                scatter: scatter,
                meColor: meColor,
                oppColor: oppColor
            )
            .padding(.horizontal, 4)
            .padding(.bottom, 6)
        }
    }
}

// MARK: - Expanded fullscreen view with pinch-to-zoom + pan

struct ExpandedPointsGraphView: View {
    let record: MatchRecord
    private var stats: [PointStat] { record.stats }

    @ObservedObject var fetcher: HealthKitHRFetcher

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    private var meColor:  Color { theme.colors.me }
    private var oppColor: Color { theme.colors.opponent }

    // Bound to the inline view's persisted config so a user's filter / overlay
    // selections survive closing and reopening the full-screen cover.
    @Binding private var selectedMyOutcomes: Set<OutcomeCategory>
    @Binding private var selectedOpponentOutcomes: Set<OutcomeCategory>
    @Binding private var selectedWonEndingShots: Set<EndingShot>
    @Binding private var selectedLostEndingShots: Set<EndingShot>
    @Binding private var showHeartRate: Bool
    @Binding private var showSteps: Bool
    @Binding private var hrSeriesMode: HRSeriesMode
    @Binding private var stepsSeriesMode: StepsSeriesMode

    @State private var visibleDomainLength: Int
    @State private var scrollPositionX: Int = 0
    @State private var zoomBaseline: Int?
    @State private var scrollBaseline: Int?
    @State private var selectedX: Int?

    /// Cached chart series. Pinch/pan updates `visibleDomainLength` and
    /// `scrollPositionX` many times per second; storing `data` in @State
    /// keeps those frames allocation-free by recomputing only when a filter
    /// input changes (see `.onChange` handlers below).
    @State private var data: PointsGraphData

    fileprivate init(record: MatchRecord,
                     selectedMyOutcomes: Binding<Set<OutcomeCategory>>,
                     selectedOpponentOutcomes: Binding<Set<OutcomeCategory>>,
                     selectedWonEndingShots: Binding<Set<EndingShot>>,
                     selectedLostEndingShots: Binding<Set<EndingShot>>,
                     showHeartRate: Binding<Bool>,
                     showSteps: Binding<Bool>,
                     hrSeriesMode: Binding<HRSeriesMode>,
                     stepsSeriesMode: Binding<StepsSeriesMode>,
                     fetcher: HealthKitHRFetcher) {
        self.record = record
        _fetcher                  = ObservedObject(wrappedValue: fetcher)
        _selectedMyOutcomes       = selectedMyOutcomes
        _selectedOpponentOutcomes = selectedOpponentOutcomes
        _selectedWonEndingShots   = selectedWonEndingShots
        _selectedLostEndingShots  = selectedLostEndingShots
        _showHeartRate            = showHeartRate
        _showSteps                = showSteps
        _hrSeriesMode             = hrSeriesMode
        _stepsSeriesMode          = stepsSeriesMode
        let stats = record.stats
        _visibleDomainLength      = State(initialValue: max(stats.count, 1))
        _data = State(initialValue: PointsGraphData(
            record: record,
            selectedMyOutcomes: selectedMyOutcomes.wrappedValue,
            selectedOpponentOutcomes: selectedOpponentOutcomes.wrappedValue,
            selectedWonEndingShots: selectedWonEndingShots.wrappedValue,
            selectedLostEndingShots: selectedLostEndingShots.wrappedValue
        ))
    }

    private func rebuildData() {
        data = PointsGraphData(
            record: record,
            selectedMyOutcomes: selectedMyOutcomes,
            selectedOpponentOutcomes: selectedOpponentOutcomes,
            selectedWonEndingShots: selectedWonEndingShots,
            selectedLostEndingShots: selectedLostEndingShots
        )
    }

    private var totalRange: Int { max(stats.count, 1) }
    private var minVisibleLength: Int { min(max(stats.count, 1), 5) }
    private var zoomEnabled: Bool { stats.count > 5 }

    var body: some View {
        NavigationStack {
            Group {
                if stats.isEmpty {
                    ContentUnavailableView(
                        "No Points",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("This match has no point data to graph.")
                    )
                } else {
                    chartScreen
                }
            }
            .navigationTitle("Points Graph")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                if zoomEnabled {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            resetZoom(animated: true)
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right.circle")
                        }
                        .accessibilityLabel("Reset Zoom")
                        .disabled(visibleDomainLength >= totalRange && scrollPositionX == 0)
                    }
                }
            }
            .onChange(of: selectedMyOutcomes)       { rebuildData() }
            .onChange(of: selectedOpponentOutcomes) { rebuildData() }
            .onChange(of: selectedWonEndingShots)   { rebuildData() }
            .onChange(of: selectedLostEndingShots)  { rebuildData() }
            .onChange(of: hrSeriesMode) { _, newMode in
                guard newMode == .averaged else { return }
                if case .loaded = fetcher.state { return }
                fetcher.load(for: record, filteredStats: record.stats, firstWindowStart: record.startTime)
            }
        }
    }

    private var chartScreen: some View {
        VStack(spacing: 8) {
            selectionSummary
            chartArea
            controlsPanel
        }
        .padding(.top, 8)
    }

    private var chartArea: some View {
        let lp: [HRChartPoint]? = { if case .loaded(let pts) = fetcher.state { return pts }; return nil }()
        let activeHR = activeHREntries(mode: hrSeriesMode, data: data, loadedAveraged: lp, stats: record.stats)
        return GeometryReader { proxy in
            PointsChartCore(
                data: data,
                meColor: meColor,
                oppColor: oppColor,
                height: proxy.size.height,
                visibleDomainLength: zoomEnabled ? visibleDomainLength : nil,
                scrollPositionX: zoomEnabled ? $scrollPositionX : nil,
                showHeartRate: showHeartRate,
                showSteps: showSteps,
                stepsSeriesMode: stepsSeriesMode,
                showXAxis: true,
                selectedX: $selectedX,
                activeHREntries: activeHR
            )
            .simultaneousGesture(pinchGesture)
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    if zoomEnabled { resetZoom(animated: true) }
                }
            )
        }
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 4)
    }

    private var controlsPanel: some View {
        ScrollView {
            VStack(spacing: 12) {
                PointsGraphLegend(
                    meColor: meColor,
                    oppColor: oppColor,
                    showHeartRate: showHeartRate,
                    hasHeartRateData: data.hasHeartRateData,
                    showSteps: showSteps,
                    hasStepsData: data.hasStepsData
                )

                if data.hasOutcomeData {
                    PointsGraphScatterControls(
                        selectedMyOutcomes: $selectedMyOutcomes,
                        selectedOpponentOutcomes: $selectedOpponentOutcomes,
                        selectedWonEndingShots: $selectedWonEndingShots,
                        selectedLostEndingShots: $selectedLostEndingShots,
                        wonByPhase: data.endingWonByPhase,
                        lostByPhase: data.endingLostByPhase,
                        myOutcomeCounts: data.myOutcomeCounts,
                        oppOutcomeCounts: data.oppOutcomeCounts
                    )
                }

                if data.hasHeartRateData || data.hasStepsData {
                    PointsGraphToggleRow(
                        hasHeartRateData: data.hasHeartRateData,
                        hasStepsData: data.hasStepsData,
                        showHeartRate: $showHeartRate,
                        showSteps: $showSteps,
                        hrSeriesMode: $hrSeriesMode,
                        stepsSeriesMode: $stepsSeriesMode,
                        fetcher: fetcher
                    )
                }

                if zoomEnabled {
                    Text("Pinch to zoom · Drag to pan · Double-tap to reset")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private var selectionSummary: some View {
        if let x = selectedX,
           x >= 0,
           x < data.cumulativeByIndex.count {
            let totals = data.cumulativeByIndex[x]
            let scatter = data.scatterByPoint[x] ?? []
            let point = x > 0 && x <= stats.count ? stats[x - 1] : nil
            let matchScore = data.idByIndex[x].flatMap { data.matchScoreByID[$0] }
            PointsGraphSelectionSummary(
                pointIndex: x,
                setPointNumber: data.setPointNumberByIndex[x],
                point: point,
                matchScore: matchScore,
                me: totals.me,
                opp: totals.opp,
                scatter: scatter,
                meColor: meColor,
                oppColor: oppColor
            )
            .padding(.horizontal, 12)
        }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                guard zoomEnabled else { return }
                if zoomBaseline == nil {
                    zoomBaseline = visibleDomainLength
                    scrollBaseline = scrollPositionX
                }
                guard let zBase = zoomBaseline, let sBase = scrollBaseline else { return }
                let raw = Double(zBase) / max(0.1, value.magnification)
                let newLen = max(minVisibleLength, min(totalRange, Int(raw.rounded())))
                // Keep the centre of the visible window stable as we zoom.
                let oldCenter = Double(sBase) + Double(zBase) / 2.0
                let newScrollRaw = oldCenter - Double(newLen) / 2.0
                let maxScroll = max(0, totalRange - newLen)
                visibleDomainLength = newLen
                scrollPositionX = min(maxScroll, max(0, Int(newScrollRaw.rounded())))
            }
            .onEnded { _ in
                zoomBaseline = nil
                scrollBaseline = nil
            }
    }

    private func resetZoom(animated: Bool) {
        let apply = {
            visibleDomainLength = totalRange
            scrollPositionX = 0
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.3)) { apply() }
        } else {
            apply()
        }
    }
}
