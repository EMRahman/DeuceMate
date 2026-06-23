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
    /// momentum charts (one per preset selection), and the Me/Opp stat tables.
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

        // Whole-match (All filter) stats as plain Me / Opp tables.
        if let all = vm.filters.first(where: { $0.key == "all" }) {
            let pw = all.pointsWon
            if pw.total > 0 {
                html += """
                <div class="card"><h2>Points Won</h2><table>\
                <tr><td class="l">Me</td><td class="v">\(pw.meWon) (\(pw.mePct)%)</td></tr>\
                <tr><td class="l">Opponent</td><td class="v">\(pw.oppWon) (\(pw.oppPct)%)</td></tr></table></div>
                """
            }
            for sec in all.comparison.sections {
                html += "<div class=\"card\"><h2>\(esc(sec.title)) <span class=\"sub\">(Me / Opp)</span></h2>"
                if let placeholder = sec.placeholder {
                    html += "<p class=\"note\">\(esc(placeholder))</p>"
                } else {
                    html += "<table>"
                    for row in sec.rows {
                        html += "<tr><td class=\"l\">\(esc(row.label))</td><td class=\"v\">\(esc(row.meValue)) / \(esc(row.oppValue))</td></tr>"
                    }
                    html += "</table>"
                }
                html += "</div>"
            }
        }
        return html
    }

    // MARK: - Momentum chart cards

    private static func momentumCard(_ vm: MatchWebViewModel, _ title: String,
                                     _ scatter: StaticChartScatter,
                                     _ pills: [(label: String, count: Int, color: String)]) -> String {
        "<div class=\"card\"><h2>\(esc(title))</h2>"
            + staticChartSVG(vm, scatter: scatter)
            + lineLegend(vm)
            + pillsHTML(pills)
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

    /// Minimal HTML-text escaping for values placed in element content.
    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }
}
