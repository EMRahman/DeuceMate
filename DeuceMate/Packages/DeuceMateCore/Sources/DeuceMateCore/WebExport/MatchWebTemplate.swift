// MatchWebTemplate.swift — the self-contained viewer (HTML skeleton + CSS +
// dependency-free SVG/JS) for the interactive HTML match export. Kept as Swift
// raw-string constants (`#"""…"""#`, which avoids all escaping) so the assembler
// is pure and unit-testable with no resource bundle: the only per-match input is
// the JSON literal injected by `MatchHTMLExporter`.
//
// The JS renders entirely from the global `DATA` object (a `MatchWebViewModel`).
// It hand-draws SVG — NO chart library, NO CDN, NO network — mirroring the
// SwiftUI archive detail: momentum step lines, set bands, `PointsGraphView`-style
// outcome/ending-shot scatter pills, recorder-only HR/steps overlays, point
// selection, and `MatchDetailView`'s TV-style Me-vs-Opp split-bar comparison.
// The page is recorder-framed throughout — no perspective toggle.
import Foundation

public enum MatchWebTemplate {

    /// Assemble the complete, offline HTML page around an embedded JSON literal.
    /// `fallbackHTML` is pre-rendered, static match content placed inside `#root`
    /// so previews that don't run JavaScript (e.g. iOS Quick Look) still show the
    /// match; the viewer JS clears `#root` and rebuilds the interactive UI on load.
    public static func page(jsonLiteral: String, fallbackHTML: String = "") -> String {
        head + "\n<style>\n" + css + "\n</style>\n</head>\n<body>\n"
            + "<div id=\"root\">" + fallbackHTML + "</div>\n"
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
    .spread { display: flex; justify-content: space-between; align-items: baseline; gap: 12px; flex-wrap: wrap; }
    .score { font-size: 30px; font-weight: 700; font-variant-numeric: tabular-nums; letter-spacing: 1px; }
    .badge { display: inline-block; padding: 3px 10px; border-radius: 999px; font-size: 13px; font-weight: 600; }
    .badge.won { background: rgba(52,199,89,.16); color: #34C759; }
    .badge.lost { background: rgba(255,59,48,.16); color: #FF453A; }
    .badge.draw { background: rgba(255,149,0,.16); color: #FF9F0A; }
    .badge.inProgress { background: rgba(142,142,147,.16); color: #aeb2ba; }
    .setline { color: var(--muted); font-size: 14px; font-variant-numeric: tabular-nums; margin-top: 4px; }
    .chips { display: flex; flex-wrap: wrap; gap: 8px; margin: 4px 0 12px; }
    .chip { display: inline-flex; align-items: center; gap: 6px; border: 1px solid var(--line);
      background: var(--surface2); color: var(--muted); border-radius: 999px; padding: 5px 11px; font-size: 13px;
      cursor: pointer; user-select: none; }
    .chip.on { color: var(--text); border-color: transparent; }
    .chip .dot { width: 10px; height: 10px; border-radius: 50%; display: inline-block; }
    /* iOS-style scatter controls (mirrors PointsGraphScatterControls). */
    .legendline { display: flex; justify-content: center; flex-wrap: wrap; gap: 16px; margin-top: 12px; }
    .legendline .li { display: inline-flex; align-items: center; gap: 6px; color: var(--muted); font-size: 12px; }
    .legendline .ln { width: 14px; height: 2px; border-radius: 1px; display: inline-block; }
    .legendline .dash { width: 14px; display: inline-flex; gap: 3px; }
    .legendline .dash i { width: 5px; height: 2px; border-radius: 1px; display: inline-block; }
    .controls { display: flex; flex-direction: column; gap: 14px; margin-top: 14px; }
    .ctrl-sec { display: flex; flex-direction: column; gap: 6px; }
    .ctrl-title { color: var(--muted); font-size: 11px; font-weight: 600; text-transform: uppercase;
      letter-spacing: .6px; padding: 0 2px; }
    .ctrl-row { display: flex; align-items: center; gap: 8px; }
    .ctrl-row .rl { color: var(--muted); font-size: 12px; font-weight: 500; min-width: 30px; }
    .ctrl-row .rc { display: flex; flex-wrap: wrap; gap: 6px; }
    .qrow { display: flex; gap: 6px; flex-wrap: wrap; padding: 0 2px; }
    .schip { display: inline-flex; align-items: center; gap: 5px; border: 1px solid transparent;
      background: var(--surface2); color: var(--muted); border-radius: 999px; padding: 4px 10px;
      font-size: 12px; font-weight: 500; cursor: pointer; user-select: none; }
    .schip .dot { width: 8px; height: 8px; border-radius: 50%; display: inline-block; }
    .qchip { border: 1px solid transparent; background: var(--surface2); color: var(--muted);
      border-radius: 999px; padding: 4px 12px; font-size: 12px; font-weight: 600;
      cursor: pointer; user-select: none; }
    /* TV-style Me-vs-Opp comparison (mirrors MatchDetailView's split bars). */
    .cmp-head { display: flex; align-items: center; gap: 8px; margin-bottom: 10px; }
    .cmp-head .cmp-title { flex: 1; text-align: center; color: var(--muted); font-size: 13px; font-weight: 600; }
    .cmp-head .cap { font-size: 12px; font-weight: 600; padding: 2px 9px; border-radius: 999px; }
    .cmp-row { padding: 7px 0; border-bottom: 1px solid var(--line); }
    .cmp-row:last-child { border-bottom: 0; }
    .cmp-rl { text-align: center; color: var(--muted); font-size: 12px; }
    .cmp-rs { text-align: center; color: var(--muted); opacity: .7; font-size: 11px; }
    .cmp-body { display: flex; align-items: center; gap: 6px; margin-top: 4px; }
    .cmp-body .mev, .cmp-body .oppv { width: 46px; font-weight: 600; font-size: 13px; font-variant-numeric: tabular-nums; }
    .cmp-body .mev { text-align: right; }
    .cmp-body .oppv { text-align: left; }
    .splitbar { flex: 1; display: flex; height: 18px; border-radius: 5px; overflow: hidden; }
    .cmp-half { position: relative; flex: 1; height: 100%; }
    .cmp-sep { width: 1px; background: var(--line); }
    .cmp-blab { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center;
      font-size: 11px; font-weight: 600; color: var(--text); font-variant-numeric: tabular-nums; }
    .cmp-ratio { display: flex; align-items: center; justify-content: center; gap: 8px; margin-top: 4px;
      font-weight: 600; font-variant-numeric: tabular-nums; }
    .cmp-ratio .sep { color: var(--muted); }
    /* Stats/Points + set-filter segmented controls (mirror MatchDetailView). */
    .seg { display: flex; background: var(--surface2); border: 1px solid var(--line); border-radius: 9px; padding: 2px; gap: 2px; }
    .seg .segb { flex: 1; border: 0; background: transparent; color: var(--muted); font: inherit; font-weight: 600;
      font-size: 13px; padding: 6px 12px; border-radius: 7px; cursor: pointer; }
    .seg .segb.on { background: var(--surface); color: var(--text); box-shadow: 0 1px 2px rgba(0,0,0,.18); }
    /* Points-won header bar. */
    .pw-card { margin-top: 0; }
    .pw-head { display: flex; align-items: flex-start; justify-content: space-between; gap: 10px; }
    .pw-side { display: flex; flex-direction: column; gap: 1px; }
    .pw-side.r { align-items: flex-end; }
    .pw-mid { text-align: center; }
    .pw-lbl { font-size: 11px; font-weight: 600; }
    .pw-val { font-size: 13px; font-variant-numeric: tabular-nums; }
    .pw-t { font-size: 11px; color: var(--muted); }
    .pw-tt { font-size: 11px; color: var(--muted); opacity: .7; font-variant-numeric: tabular-nums; }
    .pw-bar { display: flex; gap: 3px; height: 16px; margin-top: 8px; }
    .pw-bar div { border-radius: 5px; }
    /* Point-by-point list. */
    .pt-row { display: flex; align-items: flex-start; gap: 8px; padding: 7px 0; border-bottom: 1px solid var(--line); }
    .pt-row:last-child { border-bottom: 0; }
    .pt-num { min-width: 22px; text-align: right; color: var(--muted); opacity: .7; font-size: 12px;
      font-variant-numeric: tabular-nums; padding-top: 2px; }
    .pt-body { flex: 1; display: flex; flex-direction: column; gap: 3px; }
    .pt-meta { display: flex; align-items: center; gap: 6px; flex-wrap: wrap; }
    .pt-score { color: var(--muted); font-size: 12px; font-variant-numeric: tabular-nums; }
    .pt-bp { color: #FF9F0A; font-size: 11px; font-weight: 700; }
    .pt-2nd { color: var(--muted); font-size: 11px; }
    .pt-outcome { display: flex; align-items: center; gap: 6px; }
    .pt-otext { font-size: 14px; }
    .pt-chip { font-size: 11px; font-weight: 700; padding: 1px 7px; border-radius: 999px; font-variant-numeric: tabular-nums; }
    .pt-right { display: flex; flex-direction: column; align-items: flex-end; gap: 2px; text-align: right; white-space: nowrap; }
    .pt-shot { color: var(--muted); opacity: .85; font-size: 11px; }
    .pt-hr { color: var(--muted); font-size: 11px; font-variant-numeric: tabular-nums; }
    /* AI Coach card (mirrors the iOS AICoachSheet). */
    .ai-head { display: flex; align-items: center; gap: 8px; }
    .ai-spark { font-size: 18px; }
    .ai-title { font-size: 16px; font-weight: 700; }
    .ai-intro { color: var(--muted); font-size: 13px; margin: 4px 0 10px; }
    .ai-sub { color: var(--muted); font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: .5px; margin: 12px 0 6px; }
    .ai-apps { display: flex; flex-wrap: wrap; gap: 8px; }
    .ai-app { display: inline-flex; align-items: center; gap: 6px; text-decoration: none; border: 1px solid transparent;
      border-radius: 999px; padding: 7px 13px; font-size: 13px; font-weight: 600; }
    .ai-app .dot { width: 9px; height: 9px; border-radius: 50%; display: inline-block; }
    .ai-controls { display: flex; gap: 8px; flex-wrap: wrap; margin-top: 12px; }
    .ai-btn { border: 1px solid var(--line); background: var(--surface2); color: var(--text); border-radius: 9px;
      padding: 8px 14px; font: inherit; font-weight: 600; font-size: 13px; cursor: pointer; }
    .ai-btn.ghost { background: transparent; color: var(--muted); }
    .ai-pre { white-space: pre-wrap; word-break: break-word; background: var(--bg); border: 1px solid var(--line);
      border-radius: 9px; padding: 10px; font: 12px/1.45 ui-monospace, SFMono-Regular, Menlo, monospace;
      max-height: 320px; overflow: auto; margin-top: 10px; color: var(--text); }
    .ai-foot { color: var(--muted); font-size: 12px; margin-top: 10px; }
    .ai-toast { position: fixed; left: 50%; bottom: 28px; transform: translateX(-50%); background: var(--surface2);
      border: 1px solid var(--line); color: var(--text); border-radius: 999px; padding: 9px 16px; font-size: 13px;
      font-weight: 600; opacity: 0; transition: opacity .2s; pointer-events: none; box-shadow: 0 4px 16px rgba(0,0,0,.3); }
    svg { width: 100%; height: auto; display: block; touch-action: manipulation; }
    .axislabel { fill: var(--muted); font-size: 11px; }
    .gridline { stroke: var(--line); stroke-width: 1; }
    .popup { margin-top: 12px; background: var(--surface2); border: 1px solid var(--line); border-radius: 10px;
      padding: 10px 12px; font-size: 13px; min-height: 20px; }
    .popup .k { color: var(--muted); }
    .popup b { font-variant-numeric: tabular-nums; }
    table { width: 100%; border-collapse: collapse; }
    td { padding: 5px 0; border-bottom: 1px solid var(--line); vertical-align: baseline; }
    tr:last-child td { border-bottom: 0; }
    td.l { color: var(--muted); }
    td.v { text-align: right; font-weight: 600; font-variant-numeric: tabular-nums; white-space: nowrap; }
    td .hint { display: block; color: var(--muted); font-weight: 400; font-size: 11px; }
    .statbar { position: relative; display: inline-block; width: 130px; max-width: 100%; height: 18px;
      background: var(--surface2); border: 1px solid var(--line); border-radius: 5px; overflow: hidden;
      vertical-align: middle; }
    .statbar .fill { position: absolute; left: 0; top: 0; bottom: 0; background: var(--accent); opacity: .55; }
    .statbar .txt { position: relative; z-index: 1; display: block; text-align: center; line-height: 18px;
      font-size: 11px; font-weight: 600; color: var(--text); font-variant-numeric: tabular-nums; }
    .note { color: var(--muted); font-size: 13px; margin: 0 0 6px; }
    ul.bul { margin: 2px 0 0; padding-left: 18px; }
    ul.bul li { margin: 3px 0; }
    .foot { color: var(--muted); font-size: 12px; text-align: center; margin-top: 24px; }
    """#

    static let js = #"""
    "use strict";
    (function () {
      const NS = "http://www.w3.org/2000/svg";
      const root = document.getElementById("root");
      const P = DATA.palette;
      // Selection model mirrors PointsGraphView's expanded controls: four
      // independent sets of toggled scatter categories, plus the HR/Steps
      // overlay flags. All four start empty (clean chart) exactly like the app.
      const state = {
        focal: "me",
        sel: { myOut: new Set(), oppOut: new Set(), wonShot: new Set(), lostShot: new Set() },
        hr: false, steps: false,
        stepsMode: "cumulative",  // "cumulative" | "perPoint" — mirrors iOS StepsSeriesMode
        selected: null,
        tab: "stats",     // "stats" | "points" (mirrors MatchDetailView's tabs)
        filter: "all",    // FilterVM key — the selected set filter
        aiPersp: "me",    // AI Coach perspective: "me" | "opponent"
        aiShow: false     // AI Coach: prompt preview expanded?
      };
      const curFilter = () => DATA.filters.find(f => f.key === state.filter) || DATA.filters[0];

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

      // ---- chart card ----
      function chartCard() {
        const card = el("div", { class: "card" }, [el("h2", { text: "Points Momentum" })]);
        card.appendChild(buildSVG());
        const pop = el("div", { class: "popup" });
        card.appendChild(pop);
        renderPopup(pop);
        card.appendChild(legend());
        card.appendChild(controls());
        return card;
      }

      // ---- iOS-style scatter controls (mirror PointsGraphScatterControls) ----
      // Per-outcome chip metadata keyed by PointOutcome raw value, and the iOS
      // chip order (DF · W · UE · FE) so the rows read exactly like the app.
      const OUT_META = {}; P.outcomes.forEach(o => OUT_META[o.key] = o);
      const SHOT_META = {}; P.endingShots.forEach(o => SHOT_META[o.key] = o);
      const OUTCOME_ORDER = ["doubleFault", "winner", "unforcedError", "forcedError"];
      const LOSS_OUTCOMES = ["unforcedError", "forcedError", "doubleFault"];
      const GREEN = "#34C759", RED = "#FF3B30";

      function tint(hex, a) {
        const h = hex.replace("#", "");
        return "rgba(" + parseInt(h.substr(0, 2), 16) + "," + parseInt(h.substr(2, 2), 16)
          + "," + parseInt(h.substr(4, 2), 16) + "," + a + ")";
      }
      function eqSet(set, arr) {
        if (set.size !== arr.length) return false;
        return arr.every(v => set.has(v));
      }
      function presentPhases() { return focalP().presentEndingPhases || []; }

      // A point matches outcome category `cat` for the absolute player `who`
      // (mirrors PointsGraphData.matchesOutcome): DF = who served it, W = who
      // struck it, UE/FE = who erred (i.e. the player who lost the point).
      function matchesOutcome(cat, p, who) {
        const other = who === "me" ? "opp" : "me";
        if (cat === "doubleFault")   return p.server === who && p.outcome === "doubleFault";
        if (cat === "winner")        return p.winner === who && p.outcome === "winner";
        if (cat === "unforcedError") return p.winner === other && p.outcome === "unforcedError";
        if (cat === "forcedError")   return p.winner === other && p.outcome === "forcedError";
        return false;
      }

      function scatterChip(meta, count, on, toggle) {
        const c = el("div", { class: "schip", onclick: toggle }, [
          el("span", { class: "dot", style: "background:" + meta.colorHex }),
          meta.label + " " + count
        ]);
        if (on) { c.style.color = meta.colorHex; c.style.borderColor = tint(meta.colorHex, .45);
          c.style.background = tint(meta.colorHex, .15); }
        return c;
      }
      function quickChip(label, color, on, toggle) {
        const c = el("div", { class: "qchip", text: label, onclick: toggle });
        if (on) { c.style.color = color; c.style.borderColor = tint(color, .45);
          c.style.background = tint(color, .15); }
        return c;
      }
      function chipRow(label, content) {
        return el("div", { class: "ctrl-row" }, [
          el("span", { class: "rl", text: label }), el("div", { class: "rc" }, content)
        ]);
      }

      function sumCounts(counts, keys) { return keys.reduce((s, k) => s + (counts[k] || 0), 0); }

      function outcomesSection() {
        const c = focalP().outcomeCounts || {}, co = focalP().outcomeCountsOpponent || {};
        const pointsWonOn = eqSet(state.sel.myOut, ["winner"]) && eqSet(state.sel.oppOut, LOSS_OUTCOMES);
        const pointsLostOn = eqSet(state.sel.myOut, LOSS_OUTCOMES) && eqSet(state.sel.oppOut, ["winner"]);
        const pointsWonTotal = (c["winner"] || 0) + sumCounts(co, LOSS_OUTCOMES);
        const pointsLostTotal = (co["winner"] || 0) + sumCounts(c, LOSS_OUTCOMES);
        const quick = el("div", { class: "qrow" }, [
          quickChip("Points Won " + pointsWonTotal, GREEN, pointsWonOn, () => {
            if (pointsWonOn) { state.sel.myOut = new Set(); state.sel.oppOut = new Set(); }
            else { state.sel.myOut = new Set(["winner"]); state.sel.oppOut = new Set(LOSS_OUTCOMES); }
            render();
          }),
          quickChip("Points Lost " + pointsLostTotal, RED, pointsLostOn, () => {
            if (pointsLostOn) { state.sel.myOut = new Set(); state.sel.oppOut = new Set(); }
            else { state.sel.myOut = new Set(LOSS_OUTCOMES); state.sel.oppOut = new Set(["winner"]); }
            render();
          })
        ]);
        const meRow = chipRow("Me", OUTCOME_ORDER.map(k =>
          scatterChip(OUT_META[k], c[k] || 0, state.sel.myOut.has(k), () => { toggleIn(state.sel.myOut, k); render(); })));
        const oppRow = chipRow("Opp", OUTCOME_ORDER.map(k =>
          scatterChip(OUT_META[k], co[k] || 0, state.sel.oppOut.has(k), () => { toggleIn(state.sel.oppOut, k); render(); })));
        return el("div", { class: "ctrl-sec" }, [el("div", { class: "ctrl-title", text: "Outcomes" }), quick, meRow, oppRow]);
      }

      function endingShotsSection() {
        const present = presentPhases();
        if (!present.length) return null;
        const won = focalP().endingWonByPhase || {}, lost = focalP().endingLostByPhase || {};
        const allWonOn = eqSet(state.sel.wonShot, present);
        const allLostOn = eqSet(state.sel.lostShot, present);
        const allWonTotal = sumCounts(won, present);
        const allLostTotal = sumCounts(lost, present);
        const quick = el("div", { class: "qrow" }, [
          quickChip("All Won " + allWonTotal, GREEN, allWonOn, () => {
            if (allWonOn) { state.sel.wonShot = new Set(); }
            else { state.sel.wonShot = new Set(present); state.sel.lostShot = new Set(); }
            render();
          }),
          quickChip("All Lost " + allLostTotal, RED, allLostOn, () => {
            if (allLostOn) { state.sel.lostShot = new Set(); }
            else { state.sel.lostShot = new Set(present); state.sel.wonShot = new Set(); }
            render();
          })
        ]);
        const wonRow = chipRow("Won", present.map(k =>
          scatterChip(SHOT_META[k], won[k] || 0, state.sel.wonShot.has(k), () => { toggleIn(state.sel.wonShot, k); render(); })));
        const lostRow = chipRow("Lost", present.map(k =>
          scatterChip(SHOT_META[k], lost[k] || 0, state.sel.lostShot.has(k), () => { toggleIn(state.sel.lostShot, k); render(); })));
        return el("div", { class: "ctrl-sec" }, [el("div", { class: "ctrl-title", text: "Ending Shots" }), quick, wonRow, lostRow]);
      }

      function overlayToggles() {
        const hasHR = isMe() && DATA.points.some(p => p.heartRateBPM != null);
        const hasSteps = isMe() && !!DATA.steps;
        if (!hasHR && !hasSteps) return null;
        const wrap = el("div", { class: "chips", style: "margin:0" });
        if (hasHR) wrap.appendChild(toggleChip("Heart Rate", P.hrLineHex, state.hr,
          () => { state.hr = !state.hr; render(); }));
        if (hasSteps) wrap.appendChild(toggleChip("Steps", P.stepsLineHex, state.steps,
          () => { state.steps = !state.steps; render(); }));
        // Steps mode picker (Cumulative / Per point) — mirrors the iOS StepsSeriesMode
        // sub-control shown beneath the Steps toggle. Only when Steps is on.
        if (hasSteps && state.steps) {
          wrap.appendChild(stepsModeChip("Cumulative", "cumulative"));
          wrap.appendChild(stepsModeChip("Per point", "perPoint"));
        }
        return wrap;
      }
      function stepsModeChip(label, mode) {
        const on = state.stepsMode === mode;
        return el("div", { class: "chip" + (on ? " on" : ""),
          onclick: () => { state.stepsMode = mode; render(); } }, [
          el("span", { class: "dot", style: "background:" + (on ? P.stepsLineHex : "transparent") + ";border:1px solid " + P.stepsLineHex }), label
        ]);
      }
      function toggleChip(label, color, on, toggle) {
        return el("div", { class: "chip" + (on ? " on" : ""), onclick: toggle }, [
          el("span", { class: "dot", style: "background:" + color }), label
        ]);
      }

      function toggleIn(set, k) { set.has(k) ? set.delete(k) : set.add(k); }

      function controls() {
        const wrap = el("div", { class: "controls" });
        // Outcome controls need categorised points; ending-shot controls only
        // need ending-shot data (which can exist on uncategorised points), so
        // they're gated independently — matching the static fallback + view model.
        if (focalP().hasOutcomes) wrap.appendChild(outcomesSection());
        const es = endingShotsSection(); if (es) wrap.appendChild(es);
        const ov = overlayToggles(); if (ov) wrap.appendChild(ov);
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
      // Absolute (recorder-frame) identity of the focal / other player, so the
      // perspective toggle relabels the "Me"/"Opp" rows without moving the marks.
      function meAbs() { return isMe() ? "me" : "opp"; }
      function oppAbs() { return isMe() ? "opp" : "me"; }
      function cumOf(p, who) { return who === "me" ? p.cumulativeMe : p.cumulativeOpp; }

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
        if (isMe() && state.hr) overlay(svg, pts.filter(p => p.heartRateBPM != null),
          p => p.heartRateBPM, P.hrLineHex, false, "HR");
        if (isMe() && state.steps && DATA.steps) {
          // Core ships both cumulative + perPoint per sample (StepsSeries); the
          // viewer only paints whichever mode is toggled.
          const valFn = state.stepsMode === "perPoint" ? (p => p.perPoint) : (p => p.cumulative);
          overlay(svg, DATA.steps.timeline, valFn, P.stepsLineHex, true,
            state.stepsMode === "perPoint" ? "Steps/pt" : "Steps", true);
        }

        // scatter — driven by the toggled control pills (mirrors PointsGraphView).
        // Each mark sits on the absolute line of the player it belongs to, so a
        // "Me" outcome / a "Won" shot rides the focal line and an "Opp" outcome /
        // a "Lost" shot rides the other line. Absolute cumulative keeps placement
        // stable across the perspective toggle; only the row labels relabel.
        const me = meAbs(), opp = oppAbs();
        pts.forEach(p => {
          if (p.outcome !== "uncategorized") {
            state.sel.myOut.forEach(cat => { if (matchesOutcome(cat, p, me))
              svg.appendChild(symbol(OUT_META[cat].symbol, xAt(p.index), yP(cumOf(p, me)), OUT_META[cat].colorHex)); });
            state.sel.oppOut.forEach(cat => { if (matchesOutcome(cat, p, opp))
              svg.appendChild(symbol(OUT_META[cat].symbol, xAt(p.index), yP(cumOf(p, opp)), OUT_META[cat].colorHex)); });
          }
          if (p.endingShot) {
            if (p.winner === me && state.sel.wonShot.has(p.endingShot))
              svg.appendChild(symbol(p.endingShotSymbol, xAt(p.index), yP(cumOf(p, me)), p.endingShotColorHex));
            if (p.winner === opp && state.sel.lostShot.has(p.endingShot))
              svg.appendChild(symbol(p.endingShotSymbol, xAt(p.index), yP(cumOf(p, opp)), p.endingShotColorHex));
          }
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

      // Line legend only (Me / Opponent + active overlays) — the outcome and
      // ending-shot frequency counts now live on the control pills below, exactly
      // like PointsGraphView's split between its legend and scatter controls.
      function legend() {
        const wrap = el("div", { class: "legendline" });
        wrap.appendChild(lineItem(P.meLineHex, "Me", false));
        wrap.appendChild(lineItem(P.opponentLineHex, "Opponent", false));
        if (isMe() && state.hr && DATA.points.some(p => p.heartRateBPM != null))
          wrap.appendChild(lineItem(P.hrLineHex, "Heart Rate", false));
        if (isMe() && state.steps && DATA.steps)
          wrap.appendChild(lineItem(P.stepsLineHex, state.stepsMode === "perPoint" ? "Steps (per point)" : "Steps", true));
        return wrap;
      }
      function lineItem(color, label, dashed) {
        const swatch = dashed
          ? el("span", { class: "dash" }, [el("i", { style: "background:" + color }), el("i", { style: "background:" + color })])
          : el("span", { class: "ln", style: "background:" + color });
        return el("span", { class: "li" }, [swatch, label]);
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

      // ---- Stats / Points tab toggle (mirrors MatchDetailView's segmented picker) ----
      function segBtn(label, on, onclick) {
        return el("button", { class: "segb" + (on ? " on" : ""), text: label, onclick: onclick });
      }
      function tabToggle() {
        return el("div", { class: "seg", style: "margin-top:14px" }, [
          segBtn("Stats",  state.tab === "stats",  () => { state.tab = "stats";  render(); }),
          segBtn("Points", state.tab === "points", () => { state.tab = "points"; render(); })
        ]);
      }
      // Set filter (All / Set 1 / Set 2 …) — shown only with more than one set.
      function setFilterToggle() {
        return el("div", { class: "seg", style: "margin-top:14px" },
          DATA.filters.map(f => segBtn(f.label, state.filter === f.key, () => { state.filter = f.key; render(); })));
      }

      // ---- Stats tab: per-filter Me-vs-Opp comparison (mirrors MatchDetailView) ----
      function statsTab() {
        const f = curFilter();
        const wrap = el("div");
        if (DATA.filters.length > 2) wrap.appendChild(setFilterToggle());
        wrap.appendChild(el("h2", { text: "Match Statistics", style: "margin:18px 0 8px" }));
        const pw = pointsWonBar(f.pointsWon); if (pw) wrap.appendChild(pw);
        if (f.durationRows && f.durationRows.length) wrap.appendChild(durationCard(f.durationRows));
        f.comparison.sections.forEach(sec => wrap.appendChild(comparisonCard(sec)));
        if (f.comparison.note)
          wrap.appendChild(el("p", { class: "note", style: "padding:0 4px", text: f.comparison.note }));
        // Whole-match recorder coaching / PulseCoach / HR-zone cards (not set-filtered).
        (focalP().sections || []).filter(s => s.bullets && s.bullets.length)
          .forEach(sec => wrap.appendChild(card(sec)));
        const pulse = focalP().pulseInsights;
        if (pulse && pulse.length)
          wrap.appendChild(card({ title: "PulseCoach Insights", bullets: pulse, rows: [], note: null }));
        const hz = hrZonesSection(); if (hz) wrap.appendChild(hz);
        return wrap;
      }

      // Me/Opp points-won header bar (mirrors MatchDetailView.pointsWonHeader).
      function pointsWonBar(pw) {
        if (!pw || pw.total <= 0) return null;
        const head = el("div", { class: "pw-head" }, [
          el("div", { class: "pw-side" }, [
            el("div", { class: "pw-lbl", text: "Me", style: "color:" + P.meLineHex }),
            el("div", { class: "pw-val", text: pw.meWon + " pts · " + pw.mePct + "%", style: "color:" + P.meLineHex })
          ]),
          el("div", { class: "pw-mid" }, [
            el("div", { class: "pw-t", text: "Points Won" }),
            el("div", { class: "pw-tt", text: pw.total + " total" })
          ]),
          el("div", { class: "pw-side r" }, [
            el("div", { class: "pw-lbl", text: "Opp", style: "color:" + P.opponentLineHex }),
            el("div", { class: "pw-val", text: pw.oppWon + " pts · " + pw.oppPct + "%", style: "color:" + P.opponentLineHex })
          ])
        ]);
        const bar = el("div", { class: "pw-bar" }, [
          el("div", { style: "width:" + (pw.meWon / pw.total * 100) + "%;background:" + P.meLineHex }),
          el("div", { style: "width:" + (pw.oppWon / pw.total * 100) + "%;background:" + P.opponentLineHex })
        ]);
        return el("div", { class: "card pw-card" }, [head, bar]);
      }

      function durationCard(rows) {
        const tbl = el("table");
        rows.forEach(r => tbl.appendChild(el("tr", null, [
          el("td", { class: "l", text: r.label }), el("td", { class: "v", text: r.value })
        ])));
        return el("div", { class: "card" }, [el("h2", { text: "Duration" }), tbl]);
      }

      // ---- Points tab: point-by-point list grouped by set ----
      function pointsTab() {
        const wrap = el("div", null, [el("h2", { text: "Points", style: "margin:18px 0 8px" })]);
        let cur = null;
        const groups = [];
        DATA.points.forEach(p => {
          if (!cur || cur.setIndex !== p.setIndex) { cur = { setIndex: p.setIndex, pts: [] }; groups.push(cur); }
          cur.pts.push(p);
        });
        groups.forEach(g => {
          const c = el("div", { class: "card" }, [
            el("h2", { text: DATA.setLabels[g.setIndex] || ("Set " + (g.setIndex + 1)) })
          ]);
          g.pts.forEach((p, i) => c.appendChild(pointRow(i + 1, p)));
          wrap.appendChild(c);
        });
        return wrap;
      }
      function chipPill(text, color) {
        return el("span", { class: "pt-chip", text: text, style: "color:" + color + ";background:" + tint(color, .15) });
      }
      function pointRow(number, p) {
        const meta = el("div", { class: "pt-meta" });
        if (p.pointScoreLabel) meta.appendChild(el("span", { class: "pt-score", text: p.pointScoreLabel }));
        if (p.isBreakPoint) meta.appendChild(el("span", { class: "pt-bp", text: "BP" }));
        if (p.isSecondServe) meta.appendChild(el("span", { class: "pt-2nd", text: "2nd" }));
        const body = el("div", { class: "pt-body" }, [
          meta,
          el("div", { class: "pt-outcome" }, [chipPill(p.chipText, p.chipColorHex), el("span", { class: "pt-otext", text: p.outcomeText })])
        ]);
        const right = el("div", { class: "pt-right" });
        if (p.endingShotLabel) right.appendChild(el("span", { class: "pt-shot", text: p.endingShotLabel }));
        if (p.heartRateBPM != null) right.appendChild(el("span", { class: "pt-hr", text: "My HR: " + p.heartRateBPM + " bpm" }));
        return el("div", { class: "pt-row" }, [el("div", { class: "pt-num", text: String(number) }), body, right]);
      }

      function cmpCap(label, color) {
        return el("span", { class: "cap", text: label, style: "color:" + color + ";background:" + tint(color, .15) });
      }
      function comparisonCard(sec) {
        const c = el("div", { class: "card" }, [
          el("div", { class: "cmp-head" }, [
            cmpCap("Me", P.meLineHex),
            el("span", { class: "cmp-title", text: sec.title }),
            cmpCap("Opp", P.opponentLineHex)
          ])
        ]);
        if (sec.placeholder) { c.appendChild(el("p", { class: "note", text: sec.placeholder })); return c; }
        sec.rows.forEach(r => c.appendChild(comparisonRow(r)));
        return c;
      }
      function comparisonRow(r) {
        const kids = [el("div", { class: "cmp-rl", text: r.label })];
        if (r.subtitle) kids.push(el("div", { class: "cmp-rs", text: r.subtitle }));
        if (r.kind === "ratio") {
          kids.push(el("div", { class: "cmp-ratio" }, [
            el("span", { text: r.meValue, style: "color:" + P.meLineHex }),
            el("span", { class: "sep", text: "/" }),
            el("span", { text: r.oppValue, style: "color:" + P.opponentLineHex })
          ]));
        } else {
          kids.push(el("div", { class: "cmp-body" }, [
            el("span", { class: "mev", text: r.meValue, style: "color:" + P.meLineHex }),
            splitBar(r),
            el("span", { class: "oppv", text: r.oppValue, style: "color:" + P.opponentLineHex })
          ]));
        }
        return el("div", { class: "cmp-row" }, kids);
      }
      // Centre-anchored split bar: the Me half fills from the centre leftward,
      // the Opp half from the centre rightward; the raw count rides each half.
      function splitBar(r) {
        return el("div", { class: "splitbar" }, [
          cmpHalf("right", r.meFraction, r.meBarLabel, P.meLineHex),
          el("div", { class: "cmp-sep" }),
          cmpHalf("left", r.oppFraction, r.oppBarLabel, P.opponentLineHex)
        ]);
      }
      function cmpHalf(side, frac, label, color) {
        const pct = Math.max(0, Math.min(1, frac || 0)) * 100;
        const fill = el("div", { style: "position:absolute;top:0;bottom:0;" + side + ":0;width:" + pct + "%;background:" + color });
        return el("div", { class: "cmp-half", style: "background:" + tint(color, .15) },
          [fill, label ? el("span", { class: "cmp-blab", text: label }) : null]);
      }

      function card(sec) {
        const c = el("div", { class: "card" }, [el("h2", { text: sec.title })]);
        if (sec.note) c.appendChild(el("p", { class: "note", text: sec.note }));
        if (sec.bullets && sec.bullets.length) {
          c.appendChild(el("ul", { class: "bul" }, sec.bullets.map(b => el("li", { text: b }))));
        }
        if (sec.rows && sec.rows.length) {
          const tbl = el("table");
          sec.rows.forEach(r => {
            let valCell;
            if (typeof r.fraction === "number") {
              const pct = Math.max(0, Math.min(100, r.fraction * 100));
              const fill = el("div", { class: "fill" });
              fill.style.width = pct + "%";
              const bar = el("div", { class: "statbar" }, [
                fill,
                el("span", { class: "txt", text: r.value })
              ]);
              valCell = el("td", { class: "v" }, [bar, r.hint ? el("span", { class: "hint", text: r.hint }) : null]);
            } else {
              valCell = el("td", { class: "v" }, [r.value, r.hint ? el("span", { class: "hint", text: r.hint }) : null]);
            }
            tbl.appendChild(el("tr", null, [el("td", { class: "l", text: r.label }), valCell]));
          });
          c.appendChild(tbl);
        }
        return c;
      }

      function hrZonesSection() {
        if (!isMe() || !DATA.hr || !DATA.hr.zones.length) return null;
        return card({ title: "Heart Rate Win Rate by Zone", rows: DATA.hr.zones.map(z => ({
          label: z.label + " · " + z.descriptiveLabel, value: z.winPct, hint: null
        })), note: null, bullets: null });
      }

      // ---- AI Coach card (mirrors the iOS AICoachSheet) ----
      function aiActivePrompt() {
        const ai = DATA.aiCoach;
        return (state.aiPersp === "opponent" && ai.opponentPrompt) ? ai.opponentPrompt : ai.mePrompt;
      }
      function aiAppLink(a, prompt) {
        const href = a.supportsPromptParam ? (a.url + "?q=" + encodeURIComponent(prompt.slice(0, 1500))) : a.url;
        const link = el("a", { class: "ai-app", href: href, target: "_blank", rel: "noopener",
          onclick: () => copyText(prompt) }, [el("span", { class: "dot", style: "background:" + a.colorHex }), a.name]);
        link.style.color = a.colorHex;
        link.style.borderColor = tint(a.colorHex, .5);
        link.style.background = tint(a.colorHex, .12);
        return link;
      }
      function aiCoachCard() {
        const ai = DATA.aiCoach;
        const c = el("div", { class: "card" }, [
          el("div", { class: "ai-head" }, [el("span", { class: "ai-spark", text: "✨" }), el("span", { class: "ai-title", text: ai.title })]),
          el("div", { class: "ai-intro", text: ai.intro })
        ]);
        if (ai.opponentPrompt) {
          c.appendChild(el("div", { class: "seg", style: "max-width:300px" }, [
            segBtn("My Stats", state.aiPersp === "me", () => { state.aiPersp = "me"; render(); }),
            segBtn("Opponent", state.aiPersp === "opponent", () => { state.aiPersp = "opponent"; render(); })
          ]));
        }
        const prompt = aiActivePrompt();
        c.appendChild(el("div", { class: "ai-sub", text: "Open in AI app" }));
        c.appendChild(el("div", { class: "ai-apps" }, ai.apps.map(a => aiAppLink(a, prompt))));
        c.appendChild(el("div", { class: "ai-controls" }, [
          el("button", { class: "ai-btn", text: "Copy Prompt", onclick: () => copyText(prompt) }),
          el("button", { class: "ai-btn ghost", text: state.aiShow ? "Hide prompt" : "Show prompt",
            onclick: () => { state.aiShow = !state.aiShow; render(); } })
        ]));
        if (state.aiShow) c.appendChild(el("pre", { class: "ai-pre", text: prompt }));
        c.appendChild(el("div", { class: "ai-foot",
          text: "Copies the prompt to your clipboard and opens the app — paste it into a new chat." }));
        return c;
      }

      // Clipboard + ephemeral toast (offline-safe: no external calls).
      function copyText(t) {
        try {
          if (typeof navigator !== "undefined" && navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(t).then(() => toast("Prompt copied to clipboard"), () => fallbackCopy(t));
            return;
          }
        } catch (e) {}
        fallbackCopy(t);
      }
      function fallbackCopy(t) {
        try {
          const ta = el("textarea", { style: "position:fixed;top:-1000px;opacity:0" });
          ta.value = t; root.appendChild(ta);
          if (ta.select) ta.select();
          if (typeof document.execCommand === "function") document.execCommand("copy");
          if (ta.remove) ta.remove();
          toast("Prompt copied to clipboard");
        } catch (e) {}
      }
      let toastEl = null, toastTimer = null;
      function toast(msg) {
        if (!toastEl) { toastEl = el("div", { class: "ai-toast" }); root.appendChild(toastEl); }
        toastEl.textContent = msg; toastEl.style.opacity = "1";
        clearTimeout(toastTimer);
        toastTimer = setTimeout(() => { if (toastEl) toastEl.style.opacity = "0"; }, 2000);
      }

      // ---- render ----
      // Recorder-framed throughout (no perspective toggle), exactly like the iOS
      // archive detail: header, Me/Opp momentum chart, a Stats/Points tab toggle,
      // then either the set-filtered Me-vs-Opp comparison or the point-by-point
      // list, and finally the AI Coach card.
      function render() {
        root.innerHTML = "";
        toastEl = null;
        root.appendChild(header());
        const hasPoints = DATA.points.length > 0;
        if (hasPoints) root.appendChild(chartCard());
        if (hasPoints) root.appendChild(tabToggle());
        root.appendChild(hasPoints && state.tab === "points" ? pointsTab() : statsTab());
        if (DATA.aiCoach) root.appendChild(aiCoachCard());
        root.appendChild(el("div", { class: "foot", text: "Generated by DeuceMate · open offline in any browser" }));
      }

      render();
    })();
    """#
}
