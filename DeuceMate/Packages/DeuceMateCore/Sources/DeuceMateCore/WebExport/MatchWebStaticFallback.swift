// MatchWebStaticFallback.swift — the no-JavaScript view of the export. The
// interactive viewer draws everything into `#root` with JS; this renders a real,
// styled summary INTO `#root` so environments that don't run scripts — notably
// the iOS Quick Look file preview and many local `file://` opens — show a
// near-complete report instead of a blank page. When the viewer JS runs it does
// `root.innerHTML = ""` and rebuilds the full interactive UI, replacing this.
//
// Pure string rendering, reusing the viewer's own CSS classes so it stays styled
// with no JS. The momentum charts are server-rendered SVGs that mirror the JS
// `buildSVG`/`stepPath`/`symbol` geometry in `MatchWebTemplate`, so the static
// and interactive charts look identical. Because the static page can't toggle,
// it renders the chart once per preset selection (Points Won/Lost, Ending Shots
// All Won/Lost), each with its scatter overlay + pills — mirroring the
// interactive quick-selects.
import Foundation

/// The preset scatter overlays the static charts draw (mirror the viewer's
/// quick-selects). `nil`/absent renders the plain momentum chart.
enum StaticChartScatter { case pointsWon, pointsLost, allWon, allLost }

extension MatchHTMLExporter {

    /// A real, styled HTML summary placed inside `#root`: banner, header, the
    /// momentum charts (one per preset selection), and the TV-style Me/Opp
    /// split-bar comparison — whole match, plus a per-set breakdown.
    static func staticFallback(_ vm: MatchWebViewModel) -> String {
        let me = vm.perspectives.me
        let resultLabel = ["won": "Won", "lost": "Lost", "draw": "Draw", "inProgress": "In Progress"][me.result] ?? ""

        var html = """
        <div class="card" style="border-color:var(--accent)">\
        <strong>Open in a web browser for the full interactive report</strong>\
        <div class="sub" style="margin-top:4px">This is a static summary, shown when a file preview can't run scripts. \
        Open this file in a web browser (Safari, Chrome, …) — on a computer, or by saving it and opening it in a browser app — \
        to explore the interactive momentum chart, the Stats/Points tabs, set filters, and AI coaching.</div></div>
        """

        var sets = ""
        if !vm.meta.sets.isEmpty {
            let lines = vm.meta.sets.map { s -> String in
                "Set \(s.setNumber) " + esc(s.scoreMe) + (s.durationDisplay.map { " (" + esc($0) + ")" } ?? "")
            }.joined(separator: "   ·   ")
            sets = "<div class=\"setline\">\(lines)</div>"
        }
        html += """
        <div class="card">\
        <div class="spread"><div><h1>DeuceMate Match</h1>\
        <div class="sub">\(esc(vm.meta.dateDisplay)) · \(esc(vm.meta.formatLabel))</div></div>\
        <span class="badge \(me.result)">\(esc(resultLabel))</span></div>\
        <div class="spread" style="margin-top:10px"><div class="score">\(esc(me.scoreDisplay))</div>\
        <div class="sub">Points \(me.pointsWon)–\(me.pointsLost) · \(esc(vm.meta.durationDisplay))</div></div>\
        \(sets)</div>
        """

        // Momentum charts (server-rendered SVG) — one per preset selection, each
        // with its scatter overlay + pills, mirroring the interactive quick-selects.
        if !vm.points.isEmpty {
            var rendered = false
            if me.hasOutcomes {
                html += momentumCard(vm, "Points Momentum — Points Won",  .pointsWon, outcomePills(vm, won: true))
                html += momentumCard(vm, "Points Momentum — Points Lost", .pointsLost, outcomePills(vm, won: false))
                rendered = true
            }
            if !me.presentEndingPhases.isEmpty {
                html += momentumCard(vm, "Points Momentum — Ending Shots: All Won",  .allWon, phasePills(vm, won: true))
                html += momentumCard(vm, "Points Momentum — Ending Shots: All Lost", .allLost, phasePills(vm, won: false))
                rendered = true
            }
            if !rendered {   // score-only: no categorised data → plain momentum chart
                html += "<div class=\"card\"><h2>Points Momentum</h2>" + staticChartSVG(vm) + lineLegend(vm) + "</div>"
            }
        }

        // Me/Opp stats as TV-style split bars (mirrors MatchDetailView and the
        // interactive viewer). Always show the whole match; add a per-set
        // breakdown when the match has more than one set — the viewer hides its
        // set picker at ≤ 2 filters, and the static page can't toggle, so it
        // simply stacks each scope under a labelled divider.
        let scopes: [MatchWebViewModel.FilterVM]
        if vm.filters.count > 2 {
            scopes = vm.filters                                              // All + each set
        } else if let all = vm.filters.first(where: { $0.key == "all" }) {
            scopes = [all]                                                   // whole match only
        } else {
            scopes = []
        }
        if !scopes.isEmpty {
            html += "<h2 style=\"margin:18px 4px 8px\">Match Statistics</h2>"
        }
        let labelScopes = scopes.count > 1
        for f in scopes {
            if labelScopes {
                html += "<div style=\"font-size:16px;font-weight:700;color:var(--text);margin:22px 4px 4px\">\(esc(f.label))</div>"
            }
            html += pointsWonBar(f.pointsWon, vm)
            for sec in f.comparison.sections {
                html += comparisonCard(sec, vm)
            }
            if let note = f.comparison.note {
                html += "<p class=\"note\" style=\"padding:0 4px\">\(esc(note))</p>"
            }
        }
        return html
    }

    // MARK: - Momentum chart cards

    /// Preset-total pill colours — system green/red, mirroring the SwiftUI
    /// quick-select chips (`PointsGraphView`) and the viewer JS `GREEN`/`RED`.
    private static let presetWonColor = "#34C759"
    private static let presetLostColor = "#FF3B30"

    private static func momentumCard(_ vm: MatchWebViewModel, _ title: String,
                                     _ scatter: StaticChartScatter,
                                     _ pills: [(label: String, count: Int, color: String)]) -> String {
        // A leading pill for the preset's own total, mirroring the interactive
        // quick-select chips ("Points Won 14") which the static page can't show
        // as an interactive control — the sum of this chart's own pills IS the
        // preset total, since each chart's pills are exactly its category split.
        let total = pills.reduce(0) { $0 + $1.count }
        let (presetLabel, presetColor): (String, String)
        switch scatter {
        case .pointsWon:  (presetLabel, presetColor) = ("Points Won", presetWonColor)
        case .pointsLost: (presetLabel, presetColor) = ("Points Lost", presetLostColor)
        case .allWon:     (presetLabel, presetColor) = ("All Won", presetWonColor)
        case .allLost:    (presetLabel, presetColor) = ("All Lost", presetLostColor)
        }
        let allPills = [(label: presetLabel, count: total, color: presetColor)] + pills
        return "<div class=\"card\"><h2>\(esc(title))</h2>"
            + staticChartSVG(vm, scatter: scatter)
            + lineLegend(vm)
            + pillsHTML(allPills)
            + "</div>"
    }

    private static func lineLegend(_ vm: MatchWebViewModel) -> String {
        "<div class=\"legendline\">"
            + "<span class=\"li\"><span class=\"ln\" style=\"background:\(vm.palette.meLineHex)\"></span>Me</span>"
            + "<span class=\"li\"><span class=\"ln\" style=\"background:\(vm.palette.opponentLineHex)\"></span>Opponent</span>"
            + "</div>"
    }

    private static func pillsHTML(_ pills: [(label: String, count: Int, color: String)]) -> String {
        guard !pills.isEmpty else { return "" }
        var s = "<div class=\"chips\">"
        for p in pills {
            s += "<span class=\"schip\" style=\"color:\(p.color);border-color:\(tint(p.color, 0.45));background:\(tint(p.color, 0.15))\">"
                + "<span class=\"dot\" style=\"background:\(p.color)\"></span>\(esc(p.label)) \(p.count)</span>"
        }
        return s + "</div>"
    }

    // MARK: - TV-style Me-vs-Opp comparison bars (mirror MatchWebTemplate's JS)

    /// Points-won header bar (mirrors the viewer's `pointsWonBar`): Me / "Points
    /// Won" + total / Opp, over a two-segment proportional bar. Empty string
    /// when this filter scope has no points.
    private static func pointsWonBar(_ pw: MatchWebViewModel.PointsWonVM, _ vm: MatchWebViewModel) -> String {
        guard pw.total > 0 else { return "" }
        let me = vm.palette.meLineHex, opp = vm.palette.opponentLineHex
        let meW = Double(pw.meWon) / Double(pw.total) * 100
        let oppW = Double(pw.oppWon) / Double(pw.total) * 100
        return "<div class=\"card pw-card\"><div class=\"pw-head\">"
            + "<div class=\"pw-side\"><div class=\"pw-lbl\" style=\"color:\(me)\">Me</div>"
            + "<div class=\"pw-val\" style=\"color:\(me)\">\(pw.meWon) pts · \(pw.mePct)%</div></div>"
            + "<div class=\"pw-mid\"><div class=\"pw-t\">Points Won</div>"
            + "<div class=\"pw-tt\">\(pw.total) total</div></div>"
            + "<div class=\"pw-side r\"><div class=\"pw-lbl\" style=\"color:\(opp)\">Opp</div>"
            + "<div class=\"pw-val\" style=\"color:\(opp)\">\(pw.oppWon) pts · \(pw.oppPct)%</div></div></div>"
            + "<div class=\"pw-bar\"><div style=\"width:\(fmt(meW))%;background:\(me)\"></div>"
            + "<div style=\"width:\(fmt(oppW))%;background:\(opp)\"></div></div></div>"
    }

    /// One comparison section card (mirrors the viewer's `comparisonCard`): a
    /// Me/Opp-capped header, then either the placeholder note or the stat rows.
    private static func comparisonCard(_ sec: MatchWebViewModel.CmpSection, _ vm: MatchWebViewModel) -> String {
        var s = "<div class=\"card\"><div class=\"cmp-head\">"
            + cmpCap("Me", vm.palette.meLineHex)
            + "<span class=\"cmp-title\">\(esc(sec.title))</span>"
            + cmpCap("Opp", vm.palette.opponentLineHex)
            + "</div>"
        if let placeholder = sec.placeholder {
            s += "<p class=\"note\">\(esc(placeholder))</p>"
        } else {
            for row in sec.rows { s += comparisonRow(row, vm) }
        }
        return s + "</div>"
    }

    private static func cmpCap(_ label: String, _ color: String) -> String {
        "<span class=\"cap\" style=\"color:\(color);background:\(tint(color, 0.15))\">\(esc(label))</span>"
    }

    /// One comparison row (mirrors the viewer's `comparisonRow`): a centred label
    /// (+ optional subtitle), then either a bare me/opp ratio or the split bar
    /// flanked by the me/opp values.
    private static func comparisonRow(_ r: MatchWebViewModel.CmpRow, _ vm: MatchWebViewModel) -> String {
        let me = vm.palette.meLineHex, opp = vm.palette.opponentLineHex
        var s = "<div class=\"cmp-row\"><div class=\"cmp-rl\">\(esc(r.label))</div>"
        if let sub = r.subtitle { s += "<div class=\"cmp-rs\">\(esc(sub))</div>" }
        if r.kind == .ratio {
            s += "<div class=\"cmp-ratio\">"
                + "<span style=\"color:\(me)\">\(esc(r.meValue))</span>"
                + "<span class=\"sep\">/</span>"
                + "<span style=\"color:\(opp)\">\(esc(r.oppValue))</span></div>"
        } else {
            s += "<div class=\"cmp-body\">"
                + "<span class=\"mev\" style=\"color:\(me)\">\(esc(r.meValue))</span>"
                + splitBar(r, vm)
                + "<span class=\"oppv\" style=\"color:\(opp)\">\(esc(r.oppValue))</span></div>"
        }
        return s + "</div>"
    }

    /// Centre-anchored split bar (mirrors the viewer's `splitBar`/`cmpHalf`): the
    /// Me half fills from the centre leftward, the Opp half from the centre
    /// rightward, each carrying its raw count.
    private static func splitBar(_ r: MatchWebViewModel.CmpRow, _ vm: MatchWebViewModel) -> String {
        "<div class=\"splitbar\">"
            + cmpHalf("right", r.meFraction, r.meBarLabel, vm.palette.meLineHex)
            + "<div class=\"cmp-sep\"></div>"
            + cmpHalf("left", r.oppFraction, r.oppBarLabel, vm.palette.opponentLineHex)
            + "</div>"
    }

    private static func cmpHalf(_ side: String, _ frac: Double, _ label: String?, _ color: String) -> String {
        let pct = max(0, min(1, frac)) * 100
        var s = "<div class=\"cmp-half\" style=\"background:\(tint(color, 0.15))\">"
            + "<div style=\"position:absolute;top:0;bottom:0;\(side):0;width:\(fmt(pct))%;background:\(color)\"></div>"
        if let label = label { s += "<span class=\"cmp-blab\">\(esc(label))</span>" }
        return s + "</div>"
    }

    // MARK: - Pills (colour · label · count) for each preset

    /// Outcome pills for the Points Won / Points Lost charts. In "won", winners
    /// are mine and the errors are the opponent's; in "lost" it flips — matching
    /// what each chart's scatter plots.
    private static func outcomePills(_ vm: MatchWebViewModel, won: Bool) -> [(label: String, count: Int, color: String)] {
        let me = vm.perspectives.me
        let meta = legendMeta(vm.palette.outcomes)
        return ["winner", "unforcedError", "forcedError", "doubleFault"].map { key -> (String, Int, String) in
            let count: Int
            if won {
                count = key == "winner" ? (me.outcomeCounts[key] ?? 0) : (me.outcomeCountsOpponent[key] ?? 0)
            } else {
                count = key == "winner" ? (me.outcomeCountsOpponent[key] ?? 0) : (me.outcomeCounts[key] ?? 0)
            }
            let m = meta[key]
            return (m?.label ?? key, count, m?.color ?? "#8E8E93")
        }
    }

    /// Phase pills for the Ending Shots All Won / All Lost charts.
    private static func phasePills(_ vm: MatchWebViewModel, won: Bool) -> [(label: String, count: Int, color: String)] {
        let me = vm.perspectives.me
        let counts = won ? me.endingWonByPhase : me.endingLostByPhase
        let meta = legendMeta(vm.palette.endingShots)
        return me.presentEndingPhases.map { key -> (String, Int, String) in
            let m = meta[key]
            return (m?.label ?? key, counts[key] ?? 0, m?.color ?? "#8E8E93")
        }
    }

    private static func legendMeta(_ legends: [MatchWebViewModel.Palette.Legend]) -> [String: (label: String, color: String)] {
        var d: [String: (label: String, color: String)] = [:]
        for l in legends { d[l.key] = (l.label, l.colorHex) }
        return d
    }

    // MARK: - Static momentum chart (mirrors MatchWebTemplate's JS buildSVG)

    /// An inline `<svg>` momentum chart: set bands, gridlines + Y labels, the two
    /// cumulative step lines, and (optionally) a preset scatter overlay. Recorder-
    /// framed; empty string when there are no points. Geometry matches the JS.
    static func staticChartSVG(_ vm: MatchWebViewModel, scatter: StaticChartScatter? = nil) -> String {
        let pts = vm.points
        let n = pts.count
        guard n > 0 else { return "" }

        let w = 920.0, h = 380.0
        let mt = 16.0, mr = 52.0, mb = 30.0, ml = 40.0
        let plotW = w - ml - mr
        let plotH = h - mt - mb

        func xAt(_ i: Int) -> Double { ml + (n > 1 ? Double(i) / Double(n - 1) : 0.5) * plotW }
        let step = n > 1 ? plotW / Double(n - 1) : plotW

        let last = pts[n - 1]
        let yMax = Double(max(last.cumulativeMe, last.cumulativeOpp, 1))
        func yP(_ v: Int) -> Double { mt + plotH - (Double(v) / yMax) * plotH }

        var svg = "<svg viewBox=\"0 0 \(Int(w)) \(Int(h))\" role=\"img\">"

        // Set bands.
        for b in vm.setBands {
            let left = max(ml, xAt(b.startIndex) - step / 2)
            let right = min(ml + plotW, xAt(b.endIndex) + step / 2)
            let width = max(0, right - left)
            svg += "<rect x=\"\(fmt(left))\" y=\"\(fmt(mt))\" width=\"\(fmt(width))\" height=\"\(fmt(plotH))\""
                + " fill=\"\(b.colorHex)\" fill-opacity=\"\(b.opacity)\"/>"
            svg += textTag((left + right) / 2, mt + 12, b.label, "middle")
        }

        // Gridlines + Y labels at 0 / 50% / 100%.
        for f in [0.0, 0.5, 1.0] {
            let y = mt + plotH - f * plotH
            let v = Int((f * yMax).rounded())
            svg += "<line class=\"gridline\" x1=\"\(fmt(ml))\" y1=\"\(fmt(y))\" x2=\"\(fmt(ml + plotW))\" y2=\"\(fmt(y))\"/>"
            svg += textTag(ml - 6, y + 3, "\(v)", "end")
        }

        // Momentum step lines — opponent under, me over.
        svg += stepPath(pts.map { (xAt($0.index), yP($0.cumulativeOpp)) }, vm.palette.opponentLineHex, "2")
        svg += stepPath(pts.map { (xAt($0.index), yP($0.cumulativeMe)) }, vm.palette.meLineHex, "2.5")

        // Scatter overlay for the preset — each mark sits on its owner's line,
        // mirroring the interactive scatter.
        if let sel = scatter {
            for p in pts {
                switch sel {
                case .pointsWon, .pointsLost:
                    guard p.outcome != "uncategorized" else { continue }
                    guard p.winner == (sel == .pointsWon ? "me" : "opp") else { continue }
                    let owner = outcomeOwner(p)
                    let cum = owner == "me" ? p.cumulativeMe : p.cumulativeOpp
                    svg += symbolSVG(p.outcomeSymbol, xAt(p.index), yP(cum), p.outcomeColorHex)
                case .allWon, .allLost:
                    guard p.endingShot != nil, let color = p.endingShotColorHex, let sym = p.endingShotSymbol else { continue }
                    guard p.winner == (sel == .allWon ? "me" : "opp") else { continue }
                    let cum = sel == .allWon ? p.cumulativeMe : p.cumulativeOpp
                    svg += symbolSVG(sym, xAt(p.index), yP(cum), color)
                }
            }
        }

        return svg + "</svg>"
    }

    /// Which player an outcome belongs to (mirrors the interactive owner rule): a
    /// double fault is the server's, a winner is the striker's, an unforced/forced
    /// error is the loser's.
    private static func outcomeOwner(_ p: MatchWebViewModel.PointVM) -> String {
        if p.outcome == "winner" { return p.winner }
        if p.outcome == "doubleFault" { return p.server }
        return p.winner == "me" ? "opp" : "me"
    }

    // MARK: - SVG primitives (mirror MatchWebTemplate's JS)

    /// Scatter mark — circle / square / triangle / pentagon / cross / plus /
    /// asterisk, radius 4.5, matching the JS `symbol`.
    private static func symbolSVG(_ kind: String, _ x: Double, _ y: Double, _ color: String) -> String {
        let r = 4.5
        switch kind {
        case "square":
            return "<rect x=\"\(fmt(x - r))\" y=\"\(fmt(y - r))\" width=\"\(fmt(2 * r))\" height=\"\(fmt(2 * r))\" fill=\"\(color)\"/>"
        case "triangle":
            let pts = "\(fmt(x)),\(fmt(y - r - 1)) \(fmt(x - r - 1)),\(fmt(y + r)) \(fmt(x + r + 1)),\(fmt(y + r))"
            return "<polygon points=\"\(pts)\" fill=\"\(color)\"/>"
        case "pentagon":
            return "<polygon points=\"\(pentagonPoints(x, y, r + 1))\" fill=\"\(color)\"/>"
        case "cross":
            return lineSVG(x - r, y - r, x + r, y + r, color) + lineSVG(x - r, y + r, x + r, y - r, color)
        case "plus":
            return lineSVG(x - r, y, x + r, y, color) + lineSVG(x, y - r, x, y + r, color)
        case "asterisk":
            var s = ""
            for a in 0..<3 {
                let ang = Double(a) * Double.pi / 3
                s += lineSVG(x - r * cos(ang), y - r * sin(ang), x + r * cos(ang), y + r * sin(ang), color)
            }
            return s
        default:   // "circle" + fallback
            return "<circle cx=\"\(fmt(x))\" cy=\"\(fmt(y))\" r=\"\(fmt(r))\" fill=\"\(color)\"/>"
        }
    }

    private static func lineSVG(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ color: String) -> String {
        "<line x1=\"\(fmt(x1))\" y1=\"\(fmt(y1))\" x2=\"\(fmt(x2))\" y2=\"\(fmt(y2))\""
            + " stroke=\"\(color)\" stroke-width=\"2\" fill=\"none\" stroke-linecap=\"round\"/>"
    }

    private static func pentagonPoints(_ cx: Double, _ cy: Double, _ r: Double) -> String {
        (0..<5).map { i -> String in
            let a = -Double.pi / 2 + Double(i) * 2 * Double.pi / 5
            return "\(fmt(cx + r * cos(a))),\(fmt(cy + r * sin(a)))"
        }.joined(separator: " ")
    }

    /// Step path: horizontal to the new x at the old y, then vertical to the new
    /// y — the same shape the JS `stepPath` draws.
    private static func stepPath(_ v: [(Double, Double)], _ color: String, _ width: String) -> String {
        guard let first = v.first else { return "" }
        var d = "M \(fmt(first.0)) \(fmt(first.1))"
        for i in 1..<v.count {
            d += " L \(fmt(v[i].0)) \(fmt(v[i - 1].1)) L \(fmt(v[i].0)) \(fmt(v[i].1))"
        }
        return "<path d=\"\(d)\" fill=\"none\" stroke=\"\(color)\" stroke-width=\"\(width)\" stroke-linejoin=\"round\"/>"
    }

    private static func textTag(_ x: Double, _ y: Double, _ str: String, _ anchor: String) -> String {
        "<text x=\"\(fmt(x))\" y=\"\(fmt(y))\" class=\"axislabel\" text-anchor=\"\(anchor)\">\(esc(str))</text>"
    }

    private static func tint(_ hex: String, _ a: Double) -> String {
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count >= 6 else { return hex }
        let chars = Array(h)
        func comp(_ i: Int) -> Int { Int(String(chars[i...(i + 1)]), radix: 16) ?? 0 }
        return "rgba(\(comp(0)),\(comp(2)),\(comp(4)),\(a))"
    }

    private static func fmt(_ d: Double) -> String { String(format: "%.1f", d) }

    /// HTML escaping for interpolated values. Callers place these in element
    /// content today; the quote escapes keep the helper safe if a value is ever
    /// interpolated into a quoted attribute instead.
    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&#39;")
    }
}
