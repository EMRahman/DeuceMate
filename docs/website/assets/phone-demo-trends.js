/* Browser port of TrendMetric / MatchTrendSample / PerformanceTrends.
   Raw pairs are deliberately distinct from plotted ratios: zero-denominator
   matches still contribute their numerator to pooled rates. */
(function () {
  "use strict";
  var catalog = [], groups = ["Errors", "Serve & Return", "Attack", "Rally Depth", "Rally Depth — By Service", "Pressure", "Fatigue"];
  var headlineIDs = ["doubleFaults", "unforcedErrors", "forcedErrorsCaused", "winners"];
  function metric(id, label, group, pair, options) {
    catalog.push(Object.assign({ id: id, label: label, group: group, pair: pair, unit: "percent", direction: "higher", count: true, hidden: false, opponent: false }, options || {}));
  }
  function fieldPair(a, b) { return function (s) { return [s.summary[a], s.summary[b]]; }; }
  metric("doubleFaults", "Double Faults", "Errors", function (s) { return [s.summary.myDoubleFaults, s.categorizedServed]; }, { direction: "lower" });
  metric("doubleFaultsConceded", "Double Faults Conceded", "Errors", function (s) { return [s.summary.opponentDoubleFaults, s.categorizedReturned]; }, { hidden: true, opponent: true });
  metric("unforcedErrors", "Unforced Errors", "Errors", function (s) { return [s.summary.myUnforcedErrors, s.categorizedLost]; }, { direction: "lower" });
  metric("unforcedErrorsDrawn", "Unforced Errors Drawn", "Errors", function (s) { return [s.summary.opponentUnforcedErrors, s.categorizedWon]; }, { hidden: true, opponent: true });
  metric("forcedErrorsConceded", "Forced Errors Conceded", "Errors", function (s) { return [s.summary.myForcedErrors, s.categorizedLost]; }, { direction: "lower" });
  metric("forcedErrorsCaused", "Forced Errors Caused", "Errors", function (s) { return [s.summary.opponentForcedErrors, s.categorizedWon]; }, { opponent: true });
  metric("winners", "Winners", "Attack", function (s) { return [s.summary.myWinners, s.categorizedWon]; });
  metric("winnersConceded", "Winners Conceded", "Attack", function (s) { return [s.summary.opponentWinners, s.categorizedLost]; }, { direction: "lower", hidden: true, opponent: true });
  metric("wueRatio", "W:UE Ratio", "Attack", fieldPair("myWinners", "myUnforcedErrors"), { unit: "ratio", count: false });
  metric("aggressionIndex", "Aggression Index", "Attack", function (s) { return [s.summary.myWinners, s.summary.myWinners + s.summary.myUnforcedErrors]; }, { count: false });
  metric("ownErrorShare", "Own-Error Share", "Attack", function (s) { return [s.summary.myDoubleFaults + s.summary.myUnforcedErrors, s.categorizedLost]; }, { direction: "lower", count: false });
  [
    ["firstServeIn", "1st Serve In", "firstServeIn", "firstServeTotal"],
    ["secondServeIn", "2nd Serve In", "secondServeIn", "secondServeTotal"],
    ["firstServeWin", "1st Serve Win", "firstServeWins", "firstServeIn"],
    ["secondServeWin", "2nd Serve Win", "secondServeWins", "secondServeTotal"],
    ["returnWinFirst", "Return Win (1st)", "returnWinsOnFirst", "returnOppsOnFirst"],
    ["returnWinSecond", "Return Win (2nd)", "returnWinsOnSecond", "returnOppsOnSecond"]
  ].forEach(function (m) { metric(m[0], m[1], "Serve & Return", fieldPair(m[2], m[3])); });
  metric("breakPointsConverted", "Break Points Converted", "Pressure", fieldPair("breakPointWins", "breakPointOpps"));
  metric("breakPointsSaved", "Break Points Saved", "Pressure", function (s) { return [s.summary.breakPointsFaced - s.summary.breakPointsLost, s.summary.breakPointsFaced]; });
  metric("bigPointWin", "Big-Point Win %", "Pressure", fieldPair("bigPointWins", "bigPointTotal"));
  metric("pointsWon", "Points Won", "Pressure", fieldPair("pointsWon", "totalPoints"));
  var shots = [["Serve", "serve"], ["Return", "return"], ["ServePlusOne", "servePlusOne"], ["Rally", "rally"]];
  shots.forEach(function (shot) {
    var label = shot[0] === "ServePlusOne" ? "S+1" : shot[0];
    function pair(scope, win) { return function (s) {
      var rows = s[scope], total = rows.reduce(function (n, r) { return n + r.total; }, 0);
      var row = rows.find(function (r) { return r.shot === shot[1]; });
      if (!total || (win && !row)) return null;
      return win ? [row.wins, row.total] : [row ? row.total : 0, total];
    }; }
    metric("depthShare" + shot[0], (shot[0] === "Rally" ? "Ending in " : "Ending on ") + label, "Rally Depth", pair("depth", false), { direction: "neutral", count: false, family: "mix" });
    metric("depthWin" + shot[0], "Win Rate — " + label, "Rally Depth", pair("depth", true), { family: "winRate" });
    ["served", "returned"].forEach(function (side) {
      metric(side + "Share" + shot[0], (shot[0] === "Rally" ? "Ending in " : "Ending on ") + label, "Rally Depth — By Service", pair(side + "Depth", false), { direction: "neutral", count: false, family: side });
    });
  });
  [0, 1, 2, "tb"].forEach(function (index) {
    var suffix = index === "tb" ? "DecidingTiebreak" : "Set" + (index + 1);
    var label = index === "tb" ? "Set 3 (Super TB)" : "Set " + (index + 1);
    function slice(s) { return s.sets.find(function (x) { return index === "tb" ? x.decider : !x.decider && x.index === index; }); }
    metric("winRate" + suffix, label, "Fatigue", function (s) {
      var x = slice(s); return x && x.points >= (x.decider ? 10 : 20) ? [x.won, x.points] : null;
    });
    metric("stepsPerPoint" + suffix, label, "Fatigue", function (s) {
      var x = slice(s); return x && x.stepSamples >= 5 ? [x.stepLoad, x.stepSamples] : null;
    }, { unit: "steps", direction: "neutral" });
  });
  function depth(points) {
    return shots.map(function (s) {
      var p = points.filter(function (p) { return p.endingShot === s[1]; });
      return { shot: s[1], total: p.length, wins: p.filter(function (p) { return p.winner === "me"; }).length };
    }).filter(function (x) { return x.total > 0; });
  }
  function sample(record) {
    var points = record.stats || [], categorized = points.filter(function (p) { return p.outcome !== "uncategorized"; });
    if (record.format === "perpetualPoints" || categorized.length < 20) return null;
    var setCount = Math.max(record.sets.length, 1 + Math.max.apply(null, points.map(function (p) { return p.setIndex; })));
    var sets = [];
    if (setCount >= 2) record.sets.forEach(function (_, index) {
      if (!record.endTime && index === setCount - 1) return;
      var p = points.filter(function (p) { return p.setIndex === index; });
      if (!p.length) return;
      var previous = null, load = 0, samples = 0;
      p.forEach(function (x) {
        if (!Number.isFinite(x.stepsCumulative)) return;
        if (previous != null) { load += Math.max(0, x.stepsCumulative - previous); samples++; }
        previous = x.stepsCumulative;
      });
      sets.push({ index: index, points: p.length, won: p.filter(function (p) { return p.winner === "me"; }).length,
        stepSamples: samples, stepLoad: load, decider: window.DeuceMateScoring.isDecidingSuperTiebreak(window.DeuceMateScoring.cfgFor(record.format), index) });
    });
    return { record: record, summary: window.DeuceMateTracking.matchStatsSummary(points, "me"),
      categorizedWon: categorized.filter(function (p) { return p.winner === "me"; }).length,
      categorizedLost: categorized.filter(function (p) { return p.winner !== "me"; }).length,
      categorizedServed: categorized.filter(function (p) { return p.server === "me"; }).length,
      categorizedReturned: categorized.filter(function (p) { return p.server !== "me"; }).length,
      depth: depth(points), servedDepth: depth(points.filter(function (p) { return p.server === "me"; })),
      returnedDepth: depth(points.filter(function (p) { return p.server !== "me"; })), sets: sets };
  }
  function samples(records) { return records.map(sample).filter(Boolean).sort(function (a, b) { return a.record.startTime - b.record.startTime; }); }
  function scoped(records, filter) {
    var selected = samples(records).filter(function (s) {
      var r = s.record;
      return (filter.includeInProgress || r.endTime != null) &&
        (!filter.type || filter.type === "all" || r.matchType === filter.type) &&
        (!filter.format || filter.format === "all" || r.format === filter.format);
    });
    return !filter.window || filter.window === "all" ? selected : selected.slice(-Number(filter.window));
  }
  function pooled(m, samples) {
    var sums = samples.reduce(function (a, s) { var p = m.pair(s); return p ? [a[0] + p[0], a[1] + p[1]] : a; }, [0, 0]);
    return sums[1] > 0 ? { numerator: sums[0], denominator: sums[1], value: sums[0] / sums[1] } : null;
  }
  function series(id, samples) {
    var m = catalog.find(function (m) { return m.id === id; });
    if (!m) throw new Error("Unknown trend metric: " + id);
    var points = samples.map(function (s, index) {
      var p = m.pair(s); return p && p[1] > 0 ? { index: index, id: s.record.id, pair: p, value: p[0] / p[1] } : null;
    }).filter(Boolean), delta = null, mid = Math.floor(samples.length / 2);
    if (mid >= 2 && samples.length - mid >= 2) {
      var prior = pooled(m, samples.slice(0, mid)), recent = pooled(m, samples.slice(mid));
      if (prior && recent) {
        var change = (recent.value - prior.value) * (m.unit === "percent" ? 100 : 1);
        var threshold = m.unit === "percent" ? 1 : m.unit === "ratio" ? 0.1 : 0.5;
        delta = { change: change, direction: m.direction === "neutral" || Math.abs(change) < threshold ? "flat" :
          ((m.direction === "higher") === (change > 0) ? "improving" : "declining") };
      }
    }
    return { metric: m, points: points, pooled: pooled(m, samples), delta: delta };
  }
  function display(value, unit) { return unit === "percent" ? Math.round(value * 100) + "%" : value.toFixed(1) + (unit === "steps" ? " steps" : ""); }
  var filters = { window: "10", type: "all", format: "all", includeInProgress: false };
  var mode = "rate", serveMode = "servesIn", depthMode = "mix", depthSide = "served", visibility = {};
  try { Object.assign(filters, JSON.parse(localStorage.getItem("deucemate-demo-trend-filters") || "{}")); } catch (_) {}
  try { serveMode = localStorage.getItem("deucemate-demo-trends-serve-mode") || "servesIn"; } catch (_) {}
  function saveFilters() { try { localStorage.setItem("deucemate-demo-trend-filters", JSON.stringify(filters)); } catch (_) {} }
  // SwiftUI system colours are keyed by metric, never by its current position.
  function chartColor(metric) {
    var id = metric.id, hue = "green";
    if (/doubleFaults|secondServeWin|bigPointWin|Set2/.test(id)) hue = "orange";
    else if (/unforcedErrors|ownErrorShare|breakPointsConverted|Set3/.test(id)) hue = "red";
    else if (/forcedErrors|returnWinFirst|DecidingTiebreak/.test(id)) hue = "purple";
    else if (/winners/.test(id)) hue = "yellow";
    else if (id === "firstServeIn") hue = "blue";
    else if (/secondServeIn|breakPointsSaved/.test(id)) hue = "cyan";
    else if (id === "returnWinSecond" || /ServePlusOne$/.test(id)) hue = "pink";
    else if (/Return$/.test(id)) hue = "indigo";
    else if (/Rally$/.test(id)) hue = "brown";
    else if (/Serve$/.test(id)) hue = "teal";
    else if (id === "aggressionIndex") hue = "mint";
    return "var(--trend-" + hue + ")";
  }
  // Shape-preserving Hermite curves mirror Swift Charts' monotone interpolation.
  function curve(points) {
    if (!points.length) return "";
    var d = "M " + points[0].join(" "), slopes = [], tangents = [];
    for (var i = 1; i < points.length; i++) slopes.push((points[i][1] - points[i - 1][1]) / (points[i][0] - points[i - 1][0] || 1));
    tangents[0] = slopes[0] || 0; tangents[points.length - 1] = slopes[slopes.length - 1] || 0;
    for (var j = 1; j < points.length - 1; j++) tangents[j] = slopes[j - 1] * slopes[j] <= 0 ? 0 : 2 / (1 / slopes[j - 1] + 1 / slopes[j]);
    for (var k = 1; k < points.length; k++) {
      var a = points[k - 1], b = points[k], dx = (b[0] - a[0]) / 3;
      d += " C " + [a[0] + dx, a[1] + dx * tangents[k - 1], b[0] - dx, b[1] - dx * tangents[k], b[0], b[1]].join(" ");
    }
    return d;
  }
  function sparkline(s, count) {
    var ns = "http://www.w3.org/2000/svg", svg = document.createElementNS(ns, "svg");
    svg.setAttribute("viewBox", "0 0 60 22"); svg.setAttribute("aria-hidden", "true");
    if (s.points.length > 1) {
      var values = s.points.map(function (p) { return p.value; }), lo = Math.min.apply(null, values), hi = Math.max.apply(null, values), prior = -2, d = "";
      s.points.forEach(function (p) {
        d += (p.index === prior + 1 ? " L " : " M ") + (p.index / Math.max(1, count - 1) * 58 + 1) + " " + (20 - (p.value - lo) / (hi - lo || 1) * 18); prior = p.index;
      });
      var path = document.createElementNS(ns, "path"); path.setAttribute("d", d); path.setAttribute("fill", "none"); path.setAttribute("stroke", "currentColor"); path.setAttribute("stroke-width", "1.5"); svg.append(path);
    }
    return svg;
  }
  function trendRow(phone, s, count) {
    var h = phone.h, row = h("div", { class: "phone-trend-headline" });
    row.append(h("span", { class: "phone-trend-copy" }, h("span", {}, s.metric.label), h("small", {}, s.pooled ? display(s.pooled.value, s.metric.unit) : "—")), sparkline(s, count));
    var delta = s.delta, arrow = delta ? delta.direction === "flat" ? "−" : delta.change >= 0 ? "↗" : "↘" : "";
    row.append(h("span", { class: "phone-trend-delta " + (delta ? delta.direction : ""), "aria-label": delta ? delta.direction : "No trend" }, arrow));
    return row;
  }
  function headline(phone) {
    var h = phone.h, list = scoped(phone.records(), { window: "all" }), card = phone.card(), canOpen = list.length >= 3 || scoped(phone.records(), { window: "all", includeInProgress: true }).length >= 3;
    card.classList.add("phone-trends-card");
    if (list.length < 3) card.append(h("div", { class: "phone-trends-locked" }, phone.icon("lock"), phone.note(canOpen ? "Track " + (3 - list.length) + " more completed matches — or open Trends and include your in-progress match." : "Track " + (3 - list.length) + " more tracked " + (list.length === 2 ? "match" : "matches") + " to see performance trends.")));
    else headlineIDs.forEach(function (id) { card.append(trendRow(phone, series(id, list), list.length)); });
    if (canOpen) {
      card.setAttribute("role", "button"); card.tabIndex = 0; card.setAttribute("aria-label", "Performance Trends");
      card.append(h("span", { class: "phone-trends-chevron", "aria-hidden": "true" }, "›"));
      card.onclick = function () { phone.navigate("trends"); };
      card.onkeydown = function (event) { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); phone.navigate("trends"); } };
    }
    return h("div", { class: "phone-trends-section" }, phone.heading("Trends"), card);
  }
  function render(phone) {
    var h = phone.h, root = h("div", { class: "phone-report pr-trends" }), content = h("div", { class: "pr-scroll" }), controls = h("div", { class: "pr-trend-filters" }), selections = {};
    root.append(content); content.append(controls);
    function filter(key, value) { filters[key] = value; selections = {}; saveFilters(); paint(); }
    controls.append(phone.segment("Trend window", filters.window, [["5", "Last 5"], ["10", "Last 10"], ["20", "Last 20"], ["all", "All"]], function (v) { filter("window", v); }));
    var typeRow = h("div", { class: "pr-trend-type-row" });
    typeRow.append(phone.segment("Match type", filters.type, [["all", "All"], ["singles", "Singles"], ["doubles", "Doubles"]], function (v) { filter("type", v); }));
    var format = h("select", { "aria-label": "Match format", class: "pr-trend-format" });
    [["all", "All Formats"]].concat(window.DeuceMateShell.FORMATS.filter(function (f) { return f.id !== "perpetualPoints"; }).map(function (f) { return [f.id, f.label]; })).forEach(function (o) { format.append(h("option", { value: o[0] }, o[1])); });
    format.value = filters.format; format.onchange = function () { filter("format", format.value); };
    typeRow.append(h("label", { class: "pr-trend-format-label" }, phone.icon("filter"), format)); controls.append(typeRow);
    var include = h("input", { type: "checkbox", class: "phone-toggle", checked: filters.includeInProgress, onchange: function () { filter("includeInProgress", include.checked); } });
    controls.append(h("label", { class: "pr-live-toggle" }, h("span", {}, "Include In-Progress Matches"), include));
    controls.append(phone.segment("Display", mode, [["rate", "Rate"], ["count", "Count"]], function (v) { mode = v; paint(); }));
    var output = h("div", { class: "pr-trend-groups" }); content.append(output);
    function drawChart(card, group, metrics, list, unit) {
      var stacked = metrics.every(function (m) { return ["mix", "served", "returned"].indexOf(m.family) >= 0; }), useCount = mode === "count" && !stacked;
      var all = metrics.filter(function (m) { return !useCount || m.count; }).map(function (m) { return series(m.id, list); }).filter(function (s) { return s.points.length; });
      if (!all.length) return;
      var shown = all.filter(function (s) { return stacked || group === "Rally Depth" || (visibility[s.metric.id] == null ? !s.metric.hidden : visibility[s.metric.id]); });
      var values = shown.flatMap(function (s) { return s.points.map(function (p) { return useCount ? p.pair[0] : p.value * (unit === "percent" ? 100 : 1); }); });
      var rawMax = stacked ? 100 : Math.max.apply(null, values.concat([1])), rawStep = rawMax / 3, power = Math.pow(10, Math.floor(Math.log10(rawStep))), candidates = [1, 2, 2.5, 5, 10];
      var step = candidates.find(function (n) { return n * power >= rawStep; }) * power, max = stacked ? 100 : Math.ceil(rawMax / step) * step;
      if (stacked) step = 50;
      var ns = "http://www.w3.org/2000/svg", svg = document.createElementNS(ns, "svg"), w = 330, left = 1, right = 299, top = 5, bottom = 122;
      svg.setAttribute("viewBox", "0 0 330 145"); svg.setAttribute("role", "img"); svg.setAttribute("aria-label", group + " " + unit + " trends"); svg.classList.add("pr-trend-chart");
      function node(tag, attrs, text) { var n = document.createElementNS(ns, tag); Object.keys(attrs).forEach(function (k) { n.setAttribute(k, attrs[k]); }); if (text != null) n.textContent = text; svg.append(n); return n; }
      function xAt(index) { return left + (right - left) * index / Math.max(1, list.length - 1); }
      function yAt(value) { return bottom - value / max * (bottom - top); }
      for (var tick = 0; tick <= max + step / 2; tick += step) {
        var y = yAt(tick); node("line", { x1: left, x2: right, y1: y, y2: y, stroke: "var(--native-separator)" });
        node("text", { x: right + 4, y: y + 3, fill: "var(--native-secondary)", "font-size": 10 }, Number(tick.toFixed(1)) + (!useCount && unit === "percent" ? "%" : ""));
      }
      [0, Math.floor((list.length - 1) / 2)].filter(function (i, n, a) { return a.indexOf(i) === n; }).forEach(function (index) {
        var x = xAt(index); node("line", { x1: x, x2: x, y1: top, y2: bottom, stroke: "var(--native-separator)", "stroke-dasharray": "2 2" });
        node("text", { x: x + 2, y: 136, fill: "var(--native-secondary)", "font-size": 10 }, new Date(list[index].record.startTime).toLocaleDateString("en-US", { month: "short", day: "numeric" }));
      });
      if (stacked) shown.forEach(function (s, i) {
        var upper = [], lower = [], last = -2;
        function area() { if (upper.length) node("polygon", { points: upper.concat(lower.reverse()).map(function (p) { return p.join(","); }).join(" "), fill: chartColor(s.metric) }); upper = []; lower = []; }
        s.points.forEach(function (p) {
          if (p.index !== last + 1) area(); last = p.index;
          var base = shown.slice(0, i).reduce(function (sum, prior) { var q = prior.points.find(function (q) { return q.index === p.index; }); return sum + (q ? q.value : 0); }, 0);
          upper.push([xAt(p.index), yAt((base + p.value) * 100)]); lower.push([xAt(p.index), yAt(base * 100)]);
        }); area();
      });
      if (!stacked) shown.forEach(function (s) {
        var run = [], previous = -2, points = [];
        function flush() { if (run.length) node("path", { d: curve(run), fill: "none", stroke: chartColor(s.metric), "stroke-width": 1.8, "stroke-dasharray": s.metric.opponent ? "4 3" : "none" }); run = []; }
        s.points.forEach(function (p) { if (p.index !== previous + 1) flush(); previous = p.index; var coord = [xAt(p.index), yAt(useCount ? p.pair[0] : p.value * (unit === "percent" ? 100 : 1))]; run.push(coord); points.push(coord); }); flush();
        points.forEach(function (p) { node("circle", { cx: p[0], cy: p[1], r: 1.5, fill: "var(--native-card)", stroke: chartColor(s.metric), "stroke-width": 1.7 }); });
      });
      var rule = node("line", { x1: 0, x2: 0, y1: top, y2: bottom, stroke: "var(--native-secondary)", "stroke-dasharray": "3 3", visibility: "hidden" });
      var summary = h("div", { class: "pr-trend-selection", role: "status", hidden: true });
      function select(index) {
        index = Math.max(0, Math.min(list.length - 1, index)); selections[group] = index;
        rule.setAttribute("x1", xAt(index)); rule.setAttribute("x2", xAt(index)); rule.setAttribute("visibility", "visible");
        summary.hidden = false; summary.replaceChildren(h("strong", {}, new Date(list[index].record.startTime).toLocaleDateString("en-US", { month: "short", day: "numeric" })));
        shown.forEach(function (s) { var p = s.points.find(function (p) { return p.index === index; }); if (p) { var value = h("span", {}, h("i", {}), useCount ? p.pair.join("/") : display(p.value, unit)); value.style.setProperty("--metric-color", chartColor(s.metric)); value.title = s.metric.label; summary.append(value); } });
      }
      var tracking = false;
      function inspect(e) { var box = svg.getBoundingClientRect(), x = (e.clientX - box.left) / box.width * w; select(Math.round((x - left) / (right - left) * (list.length - 1))); }
      svg.style.touchAction = "pan-y"; svg.tabIndex = 0;
      svg.onpointerdown = function (e) { tracking = true; svg.setPointerCapture(e.pointerId); inspect(e); };
      svg.onpointermove = function (e) { if (tracking) inspect(e); };
      svg.onpointerup = svg.onpointercancel = function () { tracking = false; };
      svg.onkeydown = function (e) { if (["ArrowLeft", "ArrowRight", "Home", "End"].indexOf(e.key) < 0) return; e.preventDefault(); e.stopPropagation(); var prior = selections[group] == null ? 0 : selections[group]; select(e.key === "Home" ? 0 : e.key === "End" ? list.length - 1 : prior + (e.key === "ArrowRight" ? 1 : -1)); };
      if (group === "Fatigue") card.append(h("p", { class: "pr-trend-caption" }, unit === "percent" ? "Points Won" : useCount ? "Steps" : "Steps per Point"));
      card.append(svg, summary);
      var legend = h("div", { class: "pr-trend-legend" });
      all.forEach(function (s) {
        var on = shown.indexOf(s) >= 0, entry = stacked || group === "Rally Depth" ? h("span", { class: "pr-trend-legend-item" }, h("i", {}), s.metric.label) : phone.button("", function () { visibility[s.metric.id] = !on; paint(); }, "pr-trend-legend-item");
        if (entry.tagName === "BUTTON") { entry.append(h("i", {}), h("span", {}, s.metric.label)); entry.setAttribute("aria-pressed", String(on)); }
        entry.style.setProperty("--metric-color", chartColor(s.metric)); legend.append(entry);
      });
      card.append(legend); if (selections[group] != null) select(selections[group]);
    }
    function paint() {
      output.replaceChildren(); var list = scoped(phone.records(), filters);
      if (list.length < 3) {
        output.append(h("div", { class: "pr-trend-empty" }, h("span", { "aria-hidden": "true" }, "⌁"), h("h3", {}, "Not Enough Matches"), phone.note(!list.length ? "No tracked matches match these filters." : "Only " + list.length + " tracked " + (list.length === 1 ? "match" : "matches") + " found for these filters — Trends needs at least 3."))); return;
      }
      var partial = list.filter(function (s) { return s.summary.uncategorizedCount > 0; }).length;
      if (partial) output.append(h("div", { class: "pr-trend-coverage" }, phone.note(partial + " matches in this window had tracking off for part of the match — outcome rates below reflect only the tracked points.")));
      groups.forEach(function (group) {
        var metrics = catalog.filter(function (m) { return m.group === group; });
        if (!metrics.some(function (m) { return series(m.id, list).points.length > 0; })) return;
        var section = h("section", { class: "pr-trend-section", "data-group": group }), card = h("div", { class: "pr-trend-card" });
        section.append(h("h3", { class: "pr-trend-section-title" }, group), card);
        if (group === "Serve & Return") {
          card.append(phone.segment("Serve & Return View", serveMode, [["servesIn", "Serves In"], ["servesWin", "Serves Win"], ["returnsWin", "Returns Win"]], function (v) { serveMode = v; try { localStorage.setItem("deucemate-demo-trends-serve-mode", v); } catch (_) {} paint(); }));
          var ids = serveMode === "servesIn" ? ["firstServeIn", "secondServeIn"] : serveMode === "servesWin" ? ["firstServeWin", "secondServeWin"] : ["returnWinFirst", "returnWinSecond"];
          metrics = metrics.filter(function (m) { return ids.indexOf(m.id) >= 0; });
        } else if (group === "Rally Depth") {
          card.append(phone.segment("Rally Depth View", depthMode, [["mix", "Mix"], ["winRate", "Win Rate"]], function (v) { depthMode = v; paint(); })); metrics = metrics.filter(function (m) { return m.family === depthMode; });
        } else if (group === "Rally Depth — By Service") {
          card.append(phone.segment("Serving Side", depthSide, [["served", "On Serve"], ["returned", "On Returns"]], function (v) { depthSide = v; paint(); })); metrics = metrics.filter(function (m) { return m.family === depthSide; });
        }
        ["percent", "steps"].forEach(function (unit) { var subset = metrics.filter(function (m) { return m.unit === unit; }); if (subset.length) drawChart(card, group, subset, list, unit); });
        metrics.filter(function (m) { return m.unit === "ratio"; }).forEach(function (m) { var s = series(m.id, list); if (s.points.length) { var row = trendRow(phone, s, list.length); row.classList.add("pr-trend-ratio"); row.style.color = chartColor(m); row.querySelector("small").textContent = s.pooled ? s.pooled.value.toFixed(1) + " : 1" : "—"; card.append(row); } });
        if (!card.querySelector("svg")) card.append(phone.note("Not enough data for this group yet."));
        if (group === "Fatigue") { var covered = list.filter(function (s) { return s.sets.length; }).length; section.append(phone.note(covered + " of " + list.length + " matches in this window have more than one set.")); }
        output.append(section);
      });
    }
    paint(); return root;
  }
  window.DeuceMatePhoneTrends = { catalog: catalog, sample: sample, samples: samples, scoped: scoped, series: series, render: render, headline: headline };
})();
