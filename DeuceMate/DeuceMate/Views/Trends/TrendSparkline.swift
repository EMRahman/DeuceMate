// TrendSparkline.swift — a compact per-metric row: label, pooled figure,
// tiny line chart, and a delta chip. Used inline in TrendsSection
// (PastMatchesView's headline row) and, at slightly larger size, inside
// TrendsView's group charts don't reuse this — TrendChart draws the full
// multi-series chart there. This view is deliberately dumb: it renders
// whatever TrendSeries it's given and does no filtering/windowing itself.
import SwiftUI
import DeuceMateCore

/// Display-string formatting for a pooled/plotted ratio, shared by every
/// Trends view. Mirrors the shapes `RatioStat.formatted` already uses
/// elsewhere in the app (MatchStatsSummary.swift) so a trend figure reads
/// the same way the match-detail screen's numbers do.
extension TrendMetric {
    func format(_ ratio: Ratio?) -> String {
        guard let ratio else { return "—" }
        switch unit {
        case .percent:
            return "\(Int((ratio.value * 100).rounded()))%"
        case .ratio:
            guard ratio.denominator > 0 else { return ratio.numerator > 0 ? "∞ : 1" : "—" }
            return String(format: "%.1f : 1", ratio.value)
        case .bpm:
            return "\(Int(ratio.value.rounded())) bpm"
        case .steps:
            return String(format: "%.1f steps", ratio.value)
        case .metres:
            return String(format: "%.1f m", ratio.value)
        case .minutes:
            return "\(Int(ratio.value.rounded())) min"
        }
    }

    /// "12/38" style count, for the Count display mode.
    func formatCount(_ ratio: Ratio?) -> String {
        guard let ratio else { return "—" }
        return "\(ratio.numerator)/\(ratio.denominator)"
    }
}

extension TrendMetric.Unit {
    /// Y-axis tick text for a raw value in this unit. Charts group their series
    /// by unit and hand the bucket's unit here, so a bpm axis can never be
    /// labelled as a percentage — which is what happened when the formatting
    /// was hard-coded to `value * 100` for every chart.
    func axisText(_ value: Double) -> String {
        switch self {
        case .percent: return "\(Int((value * 100).rounded()))%"
        case .ratio:   return String(format: "%.1f", value)
        case .bpm:     return "\(Int(value.rounded()))"
        case .steps:   return String(format: "%.0f", value)
        case .metres:  return String(format: "%.0f", value)
        case .minutes: return "\(Int(value.rounded()))"
        }
    }

    /// Short suffix naming the unit, for a chart's section caption.
    var axisCaption: String? {
        switch self {
        case .percent, .ratio: return nil
        case .bpm:     return "bpm"
        case .steps:   return "steps per point"
        case .metres:  return "metres per point"
        case .minutes: return "minutes"
        }
    }
}

/// Whether the screen is showing rates or raw counts. A metric that doesn't
/// `supportsCountMode` (a ratio or a share) ignores this and always shows
/// its rate — there is no meaningful "count" for W:UE or an aggression share.
enum TrendDisplayMode: String, CaseIterable, Identifiable {
    case rate, count
    var id: String { rawValue }
    var label: String { self == .rate ? "Rate" : "Count" }
}

struct TrendSparkline: View {
    let series: TrendSeries
    let displayMode: TrendDisplayMode
    let color: Color
    /// Total matches in the caller's scoped window — NOT derived from
    /// `series.points.count`, which already omits any match this metric
    /// has no value for. Fixes the shape's X-domain to `0..<sampleCount`
    /// (`TrendPoint.index`'s own range) rather than to the min/max index
    /// actually present, so a missing match at either EDGE of the window
    /// (the newest match having zero UE, say) leaves visible empty space
    /// there instead of the nearest real point being stretched to the
    /// frame's edge as if it were the newest/oldest observation (Codex
    /// review, PR #121 — a boundary case the mid-window gap fix missed).
    let sampleCount: Int

    private var valueText: String {
        if displayMode == .count && series.metric.supportsCountMode {
            return series.metric.formatCount(series.pooled)
        }
        return series.metric.format(series.pooled)
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(series.metric.displayLabel)
                    .font(.subheadline)
                Text(valueText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            chart
                .frame(width: 60, height: 22)
            deltaChip
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    @ViewBuilder
    private var chart: some View {
        if series.points.count >= 2 {
            SparklineShape(
                points: series.points.map { (index: $0.index, value: $0.value) },
                indexRange: 0...max(sampleCount - 1, 1)
            )
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var deltaChip: some View {
        if let delta = series.delta {
            HStack(spacing: 2) {
                Image(systemName: deltaIcon(delta))
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(deltaColor(delta.direction))
            .frame(width: 16)
        } else {
            Color.clear.frame(width: 16)
        }
    }

    /// Points the way the number actually moved — down when the rate fell,
    /// up when it rose — independent of whether that movement is good or
    /// bad for this metric. `deltaColor` carries the good/bad judgement
    /// separately, so a falling Unforced Errors rate reads as a down arrow
    /// in green, not an "up and to the right" arrow that contradicts the
    /// number it sits next to. `.flat` always shows a plain dash regardless
    /// of `change`'s sign — a below-threshold wobble isn't a real trend in
    /// either direction.
    private func deltaIcon(_ delta: TrendDelta) -> String {
        switch delta.direction {
        case .flat: return "minus"
        case .improving, .declining:
            return delta.change >= 0 ? "arrow.up.right" : "arrow.down.right"
        }
    }

    /// Whether the movement `deltaIcon` points to is good news for THIS
    /// metric — oriented by `TrendDelta.direction`, already metric-aware
    /// (e.g. a falling Unforced Errors rate is `.improving`; a falling
    /// Winners rate would be `.declining`). Deliberately independent of the
    /// icon's raw up/down.
    private func deltaColor(_ direction: TrendDelta.Direction) -> Color {
        switch direction {
        case .improving: return .green
        case .declining: return .red
        case .flat:       return .secondary
        }
    }

    private var accessibilityLabel: String {
        var parts = ["\(series.metric.displayLabel): \(valueText) \(series.metric.denominatorLabel)"]
        if let delta = series.delta {
            let magnitude = deltaMagnitudeText(delta)
            switch delta.direction {
            case .improving: parts.append("improving\(magnitude)")
            case .declining: parts.append("declining\(magnitude)")
            case .flat:       parts.append("little change")
            }
        }
        return parts.joined(separator: ", ")
    }

    /// " down 4 percentage points" / " up 0.3" — the same movement the
    /// arrow icon shows, spelled out for VoiceOver, which can't see the
    /// arrow's direction. Empty string for `.flat`, where there's no
    /// meaningful movement to report.
    private func deltaMagnitudeText(_ delta: TrendDelta) -> String {
        let verb = delta.change >= 0 ? "up" : "down"
        let magnitude = abs(delta.change)
        switch series.metric.unit {
        case .percent:
            return " \(verb) \(Int(magnitude.rounded())) percentage points"
        case .ratio:
            return " \(verb) \(String(format: "%.1f", magnitude))"
        case .bpm:
            return " \(verb) \(Int(magnitude.rounded())) bpm"
        case .steps:
            return " \(verb) \(String(format: "%.1f", magnitude)) steps"
        case .metres:
            return " \(verb) \(String(format: "%.1f", magnitude)) metres"
        case .minutes:
            return " \(verb) \(Int(magnitude.rounded())) minutes"
        }
    }
}

/// A minimal normalized line through a series of values, drawn top-to-bottom
/// within its own frame — no axes, no ticks, deliberately illegible as a
/// precise readout (the pooled figure text carries that). Used only at
/// sparkline size (~60×22).
private struct SparklineShape: Shape {
    /// (index, value) pairs, oldest-first — `index` is the point's true
    /// position in the scoped series (`TrendPoint.index`), not just its
    /// position in this array. A prior version took plain `[Double]`
    /// values, so a metric missing an observation for one match (a zero-UE
    /// match's W:UE) had its remaining points silently re-spaced evenly as
    /// if that match had never existed, connecting straight through the
    /// gap. Positioning by real index, and breaking the path (instead of
    /// connecting) wherever two consecutive points aren't adjacent indices,
    /// is what actually shows the gap (Codex review, PR #121).
    let points: [(index: Int, value: Double)]
    /// The FULL scoped window's index range (0...sampleCount-1), fixed
    /// independent of which indices `points` actually has values for. A
    /// version that derived its X-domain from `points.first`/`.last`
    /// instead handled a gap in the MIDDLE of the window but not at either
    /// EDGE: a missing newest/oldest match just meant the nearest real
    /// point silently became the new edge, stretched to fill the frame as
    /// if it were that boundary observation (Codex review, PR #121).
    let indexRange: ClosedRange<Int>

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count >= 2 else { return path }
        let minV = points.map(\.value).min() ?? 0
        let maxV = points.map(\.value).max() ?? 1
        let span = max(maxV - minV, 0.0001)
        let indexSpan = max(indexRange.upperBound - indexRange.lowerBound, 1)

        func location(_ p: (index: Int, value: Double)) -> CGPoint {
            let x = rect.minX + CGFloat(p.index - indexRange.lowerBound) / CGFloat(indexSpan) * rect.width
            let normalized = (p.value - minV) / span
            let y = rect.maxY - CGFloat(normalized) * rect.height
            return CGPoint(x: x, y: y)
        }

        path.move(to: location(points[0]))
        for i in 1..<points.count {
            if points[i].index == points[i - 1].index + 1 {
                path.addLine(to: location(points[i]))
            } else {
                path.move(to: location(points[i]))
            }
        }
        return path
    }
}
