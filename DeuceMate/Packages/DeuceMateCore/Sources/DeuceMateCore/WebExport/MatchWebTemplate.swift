// MatchWebTemplate.swift — the self-contained viewer (HTML skeleton + CSS +
// dependency-free SVG/JS) for the interactive HTML match export. Kept as Swift
// raw-string constants (`#"""…"""#`, which avoids all escaping) so the assembler
// is pure and unit-testable with no resource bundle: the only per-match input is
// the JSON literal injected by `MatchHTMLExporter`.
//
// The JS renders entirely from the global `DATA` object (a `MatchWebViewModel`).
// It hand-draws SVG — NO chart library, NO CDN, NO network — mirroring the
// SwiftUI `PointsGraphView`: momentum step lines, set bands, outcome/ending-shot
// scatter with toggle chips, recorder-only HR/steps overlays, point selection,
// a me⇄opponent perspective toggle, and the per-perspective stat cards.
import Foundation

public enum MatchWebTemplate {

    /// Assemble the complete, offline HTML page around an embedded JSON literal.
    public static func page(jsonLiteral: String) -> String {
        head + "\n<style>\n" + css + "\n</style>\n</head>\n<body>\n<div id=\"root\"></div>\n"
            + "<script>\nconst DATA = " + jsonLiteral + ";\n</script>\n"
            + "<script>\n" + js + "\n</script>\n</body>\n</html>\n"
    }

    static let head = #"""
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="color-scheme" content="dark light">
    <title>DeuceMate Match</title>
    """#

    static let css = #"""
    :root {
      --bg: #0f1115; --surface: #181b22; --surface2: #1f232c; --line: #2a2f3a;
      --text: #e8eaed; --muted: #9aa0aa; --accent: #33C282; --opp: #428AED;
    }
    @media (prefers-color-scheme: light) {
      :root { --bg:#f5f6f8; --surface:#fff; --surface2:#eef0f3; --line:#dfe2e7; --text:#1c1f24; --muted:#5b616b; }
    }
    * { box-sizing: border-box; }
    body {
      margin: 0; background: var(--bg); color: var(--text);
      font: 15px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      -webkit-text-size-adjust: 100%;
    }
    #root { max-width: 960px; margin: 0 auto; padding: 20px 16px 48px; }
    h1 { font-size: 20px; margin: 0 0 2px; letter-spacing: .2px; }
    h2 { font-size: 14px; margin: 0 0 8px; color: var(--muted); text-transform: uppercase; letter-spacing: .6px; }
    .sub { color: var(--muted); font-size: 13px; }
    .card { background: var(--surface); border: 1px solid var(--line); border-radius: 14px; padding: 16px; margin: 14px 0; }
    .row { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
    .spread { display: flex; justify-content: space-between; align-items: baseline; gap: 12px; flex-wrap: wrap; }
    .score { font-size: 30px; font-weight: 700; font-variant-numeric: tabular-nums; letter-spacing: 1px; }
    .badge { display: inline-block; padding: 3px 10px; border-radius: 999px; font-size: 13px; font-weight: 600; }
    .badge.won { background: rgba(52,199,89,.16); color: #34C759; }
    .badge.lost { background: rgba(255,59,48,.16); color: #FF453A; }
    .badge.draw { background: rgba(255,149,0,.16); color: #FF9F0A; }
    .badge.inProgress { background: rgba(142,142,147,.16); color: #aeb2ba; }
    .setline { color: var(--muted); font-size: 14px; font-variant-numeric: tabular-nums; margin-top: 4px; }
    .toggle { display: inline-flex; background: var(--surface2); border-radius: 10px; padding: 3px; gap: 2px; }
    .toggle button { border: 0; background: transparent; color: var(--muted); font: inherit; font-weight: 600;
      padding: 6px 16px; border-radius: 8px; cursor: pointer; }
    .toggle button.on { background: var(--accent); color: #06210f; }
    .chips { display: flex; flex-wrap: wrap; gap: 8px; margin: 4px 0 12px; }
    .chip { display: inline-flex; align-items: center; gap: 6px; border: 1px solid var(--line);
      background: var(--surface2); color: var(--muted); border-radius: 999px; padding: 5px 11px; font-size: 13px;
      cursor: pointer; user-select: none; }
    .chip.on { color: var(--text); border-color: transparent; }
    .chip .dot { width: 10px; height: 10px; border-radius: 50%; display: inline-block; }
    svg { width: 100%; height: auto; display: block; touch-action: manipulation; }
    .axislabel { fill: var(--muted); font-size: 11px; }
    .gridline { stroke: var(--line); stroke-width: 1; }
    .popup { margin-top: 12px; background: var(--surface2); border: 1px solid var(--line); border-radius: 10px;
      padding: 10px 12px; font-size: 13px; min-height: 20px; }
    .popup .k { color: var(--muted); }
    .popup b { font-variant-numeric: tabular-nums; }
    .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(260px, 1fr)); gap: 14px; }
    table { width: 100%; border-collapse: collapse; }
    td { padding: 5px 0; border-bottom: 1px solid var(--line); vertical-align: baseline; }
    tr:last-child td { border-bottom: 0; }
    td.l { color: var(--muted); }
    td.v { text-align: right; font-weight: 600; font-variant-numeric: tabular-nums; white-space: nowrap; }
    td .hint { display: block; color: var(--muted); font-weight: 400; font-size: 11px; }
    .note { color: var(--muted); font-size: 13px; margin: 0 0 6px; }
    ul.bul { margin: 2px 0 0; padding-left: 18px; }
    ul.bul li { margin: 3px 0; }
    .totals { display: flex; gap: 22px; flex-wrap: wrap; }
    .totals .t { font-size: 18px; font-weight: 700; }
    .totals .tl { color: var(--muted); font-size: 12px; text-transform: uppercase; letter-spacing: .5px; }
    .foot { color: var(--muted); font-size: 12px; text-align: center; margin-top: 24px; }
    """#

    static let js = #"""
    "use strict";
    (function () {
      const NS = "http://www.w3.org/2000/svg";
      const root = document.getElementById("root");
      const P = DATA.palette;
      const state = {
        focal: "me",
        layers: { outcome: true, shot: false, hr: false, steps: false },
        selected: null
      };

      // ---- tiny DOM helpers ----
      function el(tag, attrs, kids) {
        const n = document.createElement(tag);
        if (attrs) for (const k in attrs) {
          if (k === "class") n.className = attrs[k];
          else if (k === "text") n.textContent = attrs[k];
          else if (k === "html") n.innerHTML = attrs[k];
          else if (k.slice(0, 2) === "on") n.addEventListener(k.slice(2), attrs[k]);
          else n.setAttribute(k, attrs[k]);
        }
        (kids || []).forEach(c => c != null && n.appendChild(typeof c === "string" ? document.createTextNode(c) : c));
        return n;
      }
      function s(tag, attrs) {
        const n = document.createElementNS(NS, tag);
        if (attrs) for (const k in attrs) n.setAttribute(k, attrs[k]);
        return n;
      }
      const focalP = () => DATA.perspectives[state.focal];
      const isMe = () => state.focal === "me";

      // ---- header ----
      function header() {
        const p = focalP();
        const resultLabel = { won: "Won", lost: "Lost", draw: "Draw", inProgress: "In Progress" }[p.result] || "";
        const c = el("div", { class: "card" }, [
          el("div", { class: "spread" }, [
            el("div", null, [
              el("h1", { text: "DeuceMate Match" }),
              el("div", { class: "sub", text: DATA.meta.dateDisplay + " · " + DATA.meta.formatLabel })
            ]),
            el("span", { class: "badge " + p.result, text: resultLabel })
          ]),
          el("div", { class: "spread", style: "margin-top:10px" }, [
            el("div", { class: "score", text: p.scoreDisplay }),
            el("div", { class: "sub", text: "Points " + p.pointsWon + "–" + p.pointsLost + " · " + DATA.meta.durationDisplay })
          ]),
          setLines()
        ]);
        return c;
      }
      function setLines() {
        if (!DATA.meta.sets.length) return null;
        const parts = DATA.meta.sets.map(st =>
          "Set " + st.setNumber + " " + (isMe() ? st.scoreMe : st.scoreOpponent) +
          (st.durationDisplay ? " (" + st.durationDisplay + ")" : ""));
        return el("div", { class: "setline", text: parts.join("   ·   ") });
      }

      // ---- perspective toggle ----
      function perspectiveToggle() {
        function btn(key, label) {
          return el("button", {
            class: state.focal === key ? "on" : "",
            text: label,
            onclick: () => { if (state.focal !== key) { state.focal = key; if (!isMe()) { state.layers.hr = false; state.layers.steps = false; } render(); } }
          });
        }
        return el("div", { class: "row", style: "margin:4px 0 0" }, [
          el("h2", { text: "Viewing", style: "margin:0 8px 0 0" }),
          el("div", { class: "toggle" }, [btn("me", "My Stats"), btn("opponent", "Opponent")])
        ]);
      }

      // ---- chart card ----
      function chartCard() {
        const card = el("div", { class: "card" }, [el("h2", { text: "Points Momentum" })]);
        card.appendChild(chips());
        const svg = buildSVG();
        card.appendChild(svg);
        card.appendChild(legend());
        const pop = el("div", { class: "popup" });
        card.appendChild(pop);
        renderPopup(pop);
        return card;
      }

      function chip(label, color, on, toggle) {
        const c = el("div", { class: "chip" + (on ? " on" : ""), onclick: toggle }, [
          el("span", { class: "dot", style: "background:" + color }), label
        ]);
        return c;
      }
      function chips() {
        const wrap = el("div", { class: "chips" });
        wrap.appendChild(chip("Outcomes", "#FFCC00", state.layers.outcome,
          () => { state.layers.outcome = !state.layers.outcome; render(); }));
        wrap.appendChild(chip("Shot Phase", "#30B0C7", state.layers.shot,
          () => { state.layers.shot = !state.layers.shot; render(); }));
        if (isMe() && DATA.points.some(p => p.heartRateBPM != null))
          wrap.appendChild(chip("Heart Rate", P.hrLineHex, state.layers.hr,
            () => { state.layers.hr = !state.layers.hr; render(); }));
        if (isMe() && DATA.steps)
          wrap.appendChild(chip("Steps", P.stepsLineHex, state.layers.steps,
            () => { state.layers.steps = !state.layers.steps; render(); }));
        return wrap;
      }

      // ---- the SVG chart ----
      const W = 920, H = 380, M = { t: 16, r: 52, b: 30, l: 40 };
      const plotW = W - M.l - M.r, plotH = H - M.t - M.b;
      const pts = DATA.points;
      const n = pts.length;

      function xAt(i) { return M.l + (n > 1 ? i / (n - 1) : 0.5) * plotW; }
      const step = n > 1 ? plotW / (n - 1) : plotW;

      function focalCum(p) { return isMe() ? p.cumulativeMe : p.cumulativeOpp; }
      function otherCum(p) { return isMe() ? p.cumulativeOpp : p.cumulativeMe; }
      // Which player a scatter mark belongs to (mirrors PointsGraphView): a double
      // fault is the server's, a winner is the striker's, and an unforced/forced
      // error belongs to the player who erred — i.e. the one who lost the point.
      function outcomeOwner(p) {
        if (p.outcome === "doubleFault") return p.server;
        if (p.outcome === "winner") return p.winner;
        return p.winner === "me" ? "opp" : "me";
      }

      function buildSVG() {
        const svg = s("svg", { viewBox: "0 0 " + W + " " + H, role: "img" });
        if (!n) { svg.appendChild(s("rect", { x: 0, y: 0, width: W, height: H, fill: "transparent" })); return svg; }

        const yMax = Math.max(pts[n - 1].cumulativeMe, pts[n - 1].cumulativeOpp, 1);
        const yP = v => M.t + plotH - (v / yMax) * plotH;

        // set bands
        DATA.setBands.forEach(b => {
          const left = Math.max(M.l, xAt(b.startIndex) - step / 2);
          const right = Math.min(M.l + plotW, xAt(b.endIndex) + step / 2);
          svg.appendChild(s("rect", { x: left, y: M.t, width: Math.max(0, right - left), height: plotH,
            fill: b.colorHex, "fill-opacity": b.opacity }));
          svg.appendChild(text((left + right) / 2, M.t + 12, b.label, "middle"));
        });

        // gridlines + y labels
        [0, 0.5, 1].forEach(f => {
          const y = M.t + plotH - f * plotH, v = Math.round(f * yMax);
          svg.appendChild(s("line", { class: "gridline", x1: M.l, y1: y, x2: M.l + plotW, y2: y }));
          svg.appendChild(text(M.l - 6, y + 3, String(v), "end"));
        });

        // momentum step lines (focal + other)
        svg.appendChild(stepPath(pts.map(p => [xAt(p.index), yP(otherCum(p))]), P.opponentLineHex, 2, false));
        svg.appendChild(stepPath(pts.map(p => [xAt(p.index), yP(focalCum(p))]), P.meLineHex, 2.5, false));

        // overlays (recorder-only)
        if (isMe() && state.layers.hr) overlay(svg, pts.filter(p => p.heartRateBPM != null),
          p => p.heartRateBPM, P.hrLineHex, false, "HR");
        if (isMe() && state.layers.steps && DATA.steps) overlay(svg, DATA.steps.timeline,
          p => p.cumulative, P.stepsLineHex, true, "Steps", true);

        // scatter — each mark sits on the line of the player it belongs to, so the
        // marker's line tells you who (mirrors PointsGraphView): an outcome on its
        // owner's line, a shot-phase mark on the point winner's line. Absolute
        // (me/opp) cumulative, so placement is stable across the perspective toggle.
        const lineY = (who) => p => yP(who(p) === "me" ? p.cumulativeMe : p.cumulativeOpp);
        const yOwner = lineY(outcomeOwner);
        const yWinner = lineY(p => p.winner);
        pts.forEach(p => {
          if (state.layers.outcome && p.outcome !== "uncategorized")
            svg.appendChild(symbol(p.outcomeSymbol, xAt(p.index), yOwner(p), p.outcomeColorHex));
          if (state.layers.shot && p.endingShot)
            svg.appendChild(symbol(p.endingShotSymbol, xAt(p.index), yWinner(p), p.endingShotColorHex));
        });

        // selection rule
        if (state.selected != null && pts[state.selected]) {
          const x = xAt(pts[state.selected].index);
          svg.appendChild(s("line", { x1: x, y1: M.t, x2: x, y2: M.t + plotH, stroke: "var(--text)",
            "stroke-opacity": .5, "stroke-width": 1, "stroke-dasharray": "3 3" }));
        }

        // invisible per-point hit columns for selection
        pts.forEach(p => {
          const r = s("rect", { x: xAt(p.index) - step / 2, y: M.t, width: step, height: plotH, fill: "transparent", style: "cursor:pointer" });
          r.addEventListener("click", () => { state.selected = p.index; render(); });
          svg.appendChild(r);
        });

        return svg;
      }

      function overlay(svg, arr, valFn, color, dashed, label, fromZero) {
        if (!arr.length) return;
        let mn = Infinity, mx = -Infinity;
        arr.forEach(p => { const v = valFn(p); if (v < mn) mn = v; if (v > mx) mx = v; });
        if (fromZero) mn = 0;
        const span = (mx - mn) || 1;
        const y = v => M.t + plotH - ((v - mn) / span) * plotH;
        const d = arr.map((p, i) => (i ? "L" : "M") + xAt(p.pointIndex != null ? p.pointIndex : p.index) + " " + y(valFn(p))).join(" ");
        const path = s("path", { d: d, fill: "none", stroke: color, "stroke-width": 2, "stroke-opacity": .8 });
        if (dashed) path.setAttribute("stroke-dasharray", "5 4");
        svg.appendChild(path);
        svg.appendChild(text(M.l + plotW + 6, y(mx) + 3, fmtAxis(mx), "start", color));
        svg.appendChild(text(M.l + plotW + 6, y(mn) + 3, fmtAxis(mn), "start", color));
        svg.appendChild(text(M.l + plotW + 6, M.t - 4, label, "start", color));
      }
      function fmtAxis(v) { return v >= 1000 ? (v / 1000).toFixed(1) + "k" : String(Math.round(v)); }

      function stepPath(v, color, width) {
        let d = "M " + v[0][0] + " " + v[0][1];
        for (let i = 1; i < v.length; i++) d += " L " + v[i][0] + " " + v[i - 1][1] + " L " + v[i][0] + " " + v[i][1];
        return s("path", { d: d, fill: "none", stroke: color, "stroke-width": width, "stroke-linejoin": "round" });
      }

      function text(x, y, str, anchor, fill) {
        const t = s("text", { x: x, y: y, class: "axislabel", "text-anchor": anchor || "start" });
        if (fill) t.setAttribute("fill", fill);
        t.textContent = str;
        return t;
      }

      // scatter symbol generators (mirror PointsGraphView marks)
      function symbol(kind, x, y, color) {
        const g = s("g", {});
        const stroke = { stroke: color, "stroke-width": 2, fill: "none", "stroke-linecap": "round" };
        const fill = { fill: color };
        const r = 4.5;
        if (kind === "circle") g.appendChild(s("circle", Object.assign({ cx: x, cy: y, r: r }, fill)));
        else if (kind === "square") g.appendChild(s("rect", Object.assign({ x: x - r, y: y - r, width: 2 * r, height: 2 * r }, fill)));
        else if (kind === "triangle") g.appendChild(s("polygon", Object.assign({ points: poly([[x, y - r - 1], [x - r - 1, y + r], [x + r + 1, y + r]]) }, fill)));
        else if (kind === "pentagon") g.appendChild(s("polygon", Object.assign({ points: pentagon(x, y, r + 1) }, fill)));
        else if (kind === "cross") { g.appendChild(s("line", Object.assign({ x1: x - r, y1: y - r, x2: x + r, y2: y + r }, stroke)));
          g.appendChild(s("line", Object.assign({ x1: x - r, y1: y + r, x2: x + r, y2: y - r }, stroke))); }
        else if (kind === "plus") { g.appendChild(s("line", Object.assign({ x1: x - r, y1: y, x2: x + r, y2: y }, stroke)));
          g.appendChild(s("line", Object.assign({ x1: x, y1: y - r, x2: x, y2: y + r }, stroke))); }
        else if (kind === "asterisk") { for (let a = 0; a < 3; a++) { const ang = a * Math.PI / 3;
          g.appendChild(s("line", Object.assign({ x1: x - r * Math.cos(ang), y1: y - r * Math.sin(ang), x2: x + r * Math.cos(ang), y2: y + r * Math.sin(ang) }, stroke))); } }
        else g.appendChild(s("circle", Object.assign({ cx: x, cy: y, r: r }, fill)));
        return g;
      }
      function poly(arr) { return arr.map(p => p[0] + "," + p[1]).join(" "); }
      function pentagon(cx, cy, r) {
        let p = [];
        for (let i = 0; i < 5; i++) { const a = -Math.PI / 2 + i * 2 * Math.PI / 5; p.push([cx + r * Math.cos(a), cy + r * Math.sin(a)]); }
        return poly(p);
      }

      function legend() {
        const wrap = el("div", { class: "chips", style: "margin-top:10px" });
        wrap.appendChild(legItem(P.meLineHex, isMe() ? "You" : "You (opponent)"));
        wrap.appendChild(legItem(P.opponentLineHex, "Opponent"));
        // Outcome legend pills carry the focal player's per-outcome frequency
        // count (e.g. "W 8", "UE 5") — mirrors PointsGraphView's outcome pills.
        const counts = focalP().outcomeCounts || {};
        if (state.layers.outcome) P.outcomes.forEach(o =>
          wrap.appendChild(legItem(o.colorHex, o.label + " " + (counts[o.key] || 0))));
        if (state.layers.shot) P.endingShots.forEach(o => wrap.appendChild(legItem(o.colorHex, o.label)));
        return wrap;
      }
      function legItem(color, label) {
        return el("span", { class: "chip on", style: "cursor:default" }, [
          el("span", { class: "dot", style: "background:" + color }), label
        ]);
      }

      function renderPopup(pop) {
        if (!pop) return;
        pop.innerHTML = "";
        if (state.selected == null || !pts[state.selected]) {
          pop.appendChild(el("span", { class: "k", text: n ? "Tap the chart to inspect any point." : "No point-by-point data for this match." }));
          return;
        }
        const p = pts[state.selected];
        const lbl = who => who === "me" ? (isMe() ? "You" : "Opponent") : (isMe() ? "Opponent" : "You");
        const bits = [
          ["Point", "#" + (p.index + 1) + " · Set " + (p.setIndex + 1)],
          ["Game", p.gameScoreLabel + (p.isBreakPoint ? "  · break pt" : "")],
          ["Server", lbl(p.server) + (p.isSecondServe ? " (2nd serve)" : "")],
          ["Winner", lbl(p.winner)],
          ["Outcome", p.outcome === "uncategorized" ? "—" : p.outcomeLabel],
          ["Shot", p.endingShotLabel || "—"]
        ];
        if (isMe() && p.heartRateBPM != null) bits.push(["Heart rate", p.heartRateBPM + " bpm"]);
        bits.forEach(b => pop.appendChild(el("div", null, [
          el("span", { class: "k", text: b[0] + ": " }), el("b", { text: b[1] })
        ])));
      }

      // ---- stats cards ----
      function statsSection() {
        const wrap = el("div", null, [el("h2", { text: "Match Statistics", style: "margin:18px 0 8px" })]);
        const grid = el("div", { class: "grid" });
        focalP().sections.forEach(sec => grid.appendChild(card(sec)));
        if (isMe() && focalP().pulseInsights && focalP().pulseInsights.length)
          grid.appendChild(card({ title: "PulseCoach Insights", bullets: focalP().pulseInsights, rows: [], note: null }));
        wrap.appendChild(grid);
        return wrap;
      }
      function card(sec) {
        const c = el("div", { class: "card" }, [el("h2", { text: sec.title })]);
        if (sec.note) c.appendChild(el("p", { class: "note", text: sec.note }));
        if (sec.bullets && sec.bullets.length) {
          c.appendChild(el("ul", { class: "bul" }, sec.bullets.map(b => el("li", { text: b }))));
        }
        if (sec.rows && sec.rows.length) {
          const tbl = el("table");
          sec.rows.forEach(r => tbl.appendChild(el("tr", null, [
            el("td", { class: "l", text: r.label }),
            el("td", { class: "v" }, [r.value, r.hint ? el("span", { class: "hint", text: r.hint }) : null])
          ])));
          c.appendChild(tbl);
        }
        return c;
      }

      function totalsSection() {
        if (!isMe() || !DATA.meta.totals) return null;
        const t = DATA.meta.totals, items = [];
        if (t.stepsDisplay) items.push(["Steps", t.stepsDisplay]);
        if (t.distanceDisplay) items.push(["Distance", t.distanceDisplay]);
        if (t.caloriesDisplay) items.push(["Calories", t.caloriesDisplay]);
        if (!items.length) return null;
        return el("div", { class: "card" }, [
          el("h2", { text: "Activity (recorder only)" }),
          el("div", { class: "totals" }, items.map(i => el("div", null, [
            el("div", { class: "t", text: i[1] }), el("div", { class: "tl", text: i[0] })
          ])))
        ]);
      }

      function hrZonesSection() {
        if (!isMe() || !DATA.hr || !DATA.hr.zones.length) return null;
        return card({ title: "Heart Rate Win Rate by Zone", rows: DATA.hr.zones.map(z => ({
          label: z.label + " · " + z.descriptiveLabel, value: z.winPct, hint: null
        })), note: null, bullets: null });
      }

      // ---- render ----
      function render() {
        root.innerHTML = "";
        root.appendChild(header());
        root.appendChild(perspectiveToggle());
        root.appendChild(chartCard());
        const totals = totalsSection(); if (totals) root.appendChild(totals);
        const stats = statsSection();
        const hz = hrZonesSection(); if (hz) stats.querySelector(".grid").appendChild(hz);
        root.appendChild(stats);
        root.appendChild(el("div", { class: "foot", text: "Generated by DeuceMate · open offline in any browser" }));
      }

      render();
    })();
    """#
}
