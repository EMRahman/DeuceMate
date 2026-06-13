/* ==========================================================================
   DeuceMate — browser demo of the iPhone companion app.

   Generates a realistic mock singles match by playing the shared scoring
   engine (window.DeuceMateScoring, defined in watch-demo.js) point by point,
   tagging each point with a serve/outcome model, then derives the same kind
   of statistics the real companion app shows and renders them in an iPhone
   frame with Stats / Momentum / AI-Coach tabs.

   Dependency-free; the numbers are self-consistent because every stat is
   computed from the generated point log.
   ========================================================================== */
(function () {
  "use strict";

  var root = document.getElementById("companion-demo");
  if (!root || !window.DeuceMateScoring) return;
  var E = window.DeuceMateScoring;

  var OPP_NAME = "Alex";

  /* ---- Seeded RNG so a given match is stable across re-renders ---- */
  function mulberry32(a) {
    return function () {
      a |= 0; a = a + 0x6D2B79F5 | 0;
      var t = Math.imul(a ^ a >>> 15, 1 | a);
      t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
      return ((t ^ t >>> 14) >>> 0) / 4294967296;
    };
  }
  function sd(a, b) { return b ? a / b : 0; }
  function pct(x) { return Math.round(x * 100) + "%"; }

  /* ---- Generate a mock match ---- */
  function generateMatch(seed) {
    var rnd = mulberry32(seed);
    var state = E.freshState("standard", "me");
    var points = [];
    var guard = 0;
    while (!E.isMatchComplete(state) && guard < 2000) {
      guard++;
      var server = state.currentServer;
      var inTb = E.lastSet(state).isTieBreak;
      var bp = E.isBreakPoint(state);

      var firstIn = rnd() < 0.61;
      var doubleFault = false;
      var serverWinProb;
      if (firstIn) {
        serverWinProb = server === "me" ? 0.74 : 0.69;
      } else {
        if (rnd() < 0.07) doubleFault = true;
        serverWinProb = server === "me" ? 0.55 : 0.51;
      }

      var winner;
      if (doubleFault) winner = server === "me" ? "opponent" : "me";
      else winner = rnd() < serverWinProb ? server : (server === "me" ? "opponent" : "me");

      var outcome, endingPlayer, stage;
      if (doubleFault) { outcome = "doubleFault"; endingPlayer = server; stage = 1; }
      else {
        var loser = winner === "me" ? "opponent" : "me";
        var sr = rnd();
        if (firstIn && sr < 0.10) stage = 1;
        else if (sr < 0.32) stage = 2;
        else if (sr < 0.55) stage = 3;
        else stage = 4;
        var r = rnd();
        if (stage === 1 && winner === server) { outcome = "winner"; endingPlayer = winner; }
        else if (r < 0.42) { outcome = "winner"; endingPlayer = winner; }
        else if (r < 0.80) { outcome = "unforcedError"; endingPlayer = loser; }
        else { outcome = "forcedError"; endingPlayer = loser; }
      }

      points.push({
        server: server, winner: winner, firstIn: firstIn, doubleFault: doubleFault,
        outcome: outcome, endingPlayer: endingPlayer, stage: stage, isTb: inTb, bp: bp
      });
      state = E.pointWon(state, winner).state;
    }
    return { state: state, points: points };
  }

  /* ---- Derive stats for one player from the point log ---- */
  function sideStats(p, who) {
    var oppWho = who === "me" ? "opponent" : "me";
    var serve = p.filter(function (x) { return x.server === who; });
    var firstInArr = serve.filter(function (x) { return x.firstIn && !x.doubleFault; });
    var firstWon = firstInArr.filter(function (x) { return x.winner === who; });
    var secondArr = serve.filter(function (x) { return !x.firstIn; });
    var secondWon = secondArr.filter(function (x) { return x.winner === who && !x.doubleFault; });
    var ret = p.filter(function (x) { return x.server === oppWho; });
    var retWon = ret.filter(function (x) { return x.winner === who; });
    var bpChances = p.filter(function (x) { return x.server === oppWho && x.bp; });
    var bpConv = bpChances.filter(function (x) { return x.winner === who; });
    var bpFaced = p.filter(function (x) { return x.server === who && x.bp; });
    var bpSaved = bpFaced.filter(function (x) { return x.winner === who; });
    var big = p.filter(function (x) { return x.bp || x.isTb; });
    var bigWon = big.filter(function (x) { return x.winner === who; });
    return {
      pointsWon: p.filter(function (x) { return x.winner === who; }).length,
      winners: p.filter(function (x) { return x.outcome === "winner" && x.endingPlayer === who; }).length,
      ue: p.filter(function (x) { return x.outcome === "unforcedError" && x.endingPlayer === who; }).length,
      fe: p.filter(function (x) { return x.outcome === "forcedError" && x.endingPlayer === who; }).length,
      df: serve.filter(function (x) { return x.doubleFault; }).length,
      firstInPct: sd(firstInArr.length, serve.length),
      firstWinPct: sd(firstWon.length, firstInArr.length),
      secondWinPct: sd(secondWon.length, secondArr.length),
      returnWinPct: sd(retWon.length, ret.length),
      bpConv: bpConv.length, bpChances: bpChances.length,
      bpSaved: bpSaved.length, bpFaced: bpFaced.length,
      bigWinPct: sd(bigWon.length, big.length)
    };
  }

  function scoreString(state) {
    return state.sets.map(function (s) {
      if (s.isTieBreak && s.gamesMe === 0 && s.gamesOpponent === 0) {
        return s.tieBreakPointsMe + "–" + s.tieBreakPointsOpponent;
      }
      return s.gamesMe + "–" + s.gamesOpponent;
    }).join(", ");
  }

  /* ---- AI coaching prompt (mirrors the app's structure) ---- */
  function coachPrompt(me, total, score, won) {
    return [
      "You are an experienced recreational tennis coach. I'm a club-level player",
      "(NTRP roughly 3.5–4.5). Analyse my singles match below and be blunt,",
      "specific and practical.",
      "",
      "RESULT: " + (won ? "Win" : "Loss") + " " + score + "  (vs " + OPP_NAME + ")",
      "",
      "MY STATS",
      "• Points won: " + me.pointsWon + " of " + total + " (" + pct(me.pointsWon / total) + ")",
      "• 1st serve in: " + pct(me.firstInPct) + "  ·  won behind it: " + pct(me.firstWinPct),
      "• 2nd serve points won: " + pct(me.secondWinPct) + "  ·  double faults: " + me.df,
      "• Return points won: " + pct(me.returnWinPct),
      "• Break points: " + me.bpConv + "/" + me.bpChances + " converted, " +
        me.bpSaved + "/" + me.bpFaced + " saved",
      "• Winners: " + me.winners + "  ·  unforced errors: " + me.ue +
        "  ·  forced errors: " + me.fe,
      "• Win rate on big points (break/tiebreak): " + pct(me.bigWinPct),
      "",
      "Tell me:",
      "1) My single biggest weakness, with the stat that proves it.",
      "2) One hidden strength I should lean on.",
      "3) Two tactical adjustments for my next match — no extra practice needed.",
      "4) One drill I can do on a public court without a coach."
    ].join("\n");
  }

  /* ---- Rendering ---- */
  var elMeta = root.querySelector("[data-c-meta]");
  var elBody = root.querySelector("[data-c-body]");
  var tabBtns = root.querySelectorAll("[data-c-tab]");
  var regen = root.querySelector("[data-c-regen]");

  var current = null; // { match, stats, score, won }
  var activeTab = "stats";

  function build(seed) {
    var match = generateMatch(seed);
    var stats = { me: sideStats(match.points, "me"), opp: sideStats(match.points, "opponent"), total: match.points.length };
    var won = E.matchWinner(match.state) === "me";
    current = { match: match, stats: stats, score: scoreString(match.state), won: won };
    elMeta.textContent = (won ? "Win" : "Loss") + " · " + current.score + " · vs " + OPP_NAME + " · Today";
    renderTab();
  }

  function row(label, meVal, oppVal, meMag, oppMag) {
    var total = meMag + oppMag;
    var mePct = total ? (meMag / total) * 100 : 50;
    var d = document.createElement("div");
    d.className = "stat-row";
    d.innerHTML =
      '<div class="stat-top"><span class="v me">' + meVal + '</span>' +
      '<span class="stat-label">' + label + '</span>' +
      '<span class="v opp">' + oppVal + '</span></div>' +
      '<div class="bar"><span class="bar-me" style="width:' + mePct.toFixed(1) + '%"></span>' +
      '<span class="bar-opp" style="width:' + (100 - mePct).toFixed(1) + '%"></span></div>';
    return d;
  }

  function renderStats() {
    var m = current.stats.me, o = current.stats.opp, t = current.stats.total;
    var frag = document.createDocumentFragment();
    var head = document.createElement("div");
    head.className = "stat-legend";
    head.innerHTML = '<span class="me">You</span><span>Outcome breakdown</span><span class="opp">' + OPP_NAME + '</span>';
    frag.appendChild(head);
    frag.appendChild(row("Points won", m.pointsWon, o.pointsWon, m.pointsWon, o.pointsWon));
    frag.appendChild(row("Winners", m.winners, o.winners, m.winners, o.winners));
    frag.appendChild(row("Unforced errors", m.ue, o.ue, m.ue, o.ue));
    frag.appendChild(row("Forced errors", m.fe, o.fe, m.fe, o.fe));
    frag.appendChild(row("Double faults", m.df, o.df, m.df, o.df));
    frag.appendChild(row("1st serve in", pct(m.firstInPct), pct(o.firstInPct), m.firstInPct, o.firstInPct));
    frag.appendChild(row("1st serve points won", pct(m.firstWinPct), pct(o.firstWinPct), m.firstWinPct, o.firstWinPct));
    frag.appendChild(row("2nd serve points won", pct(m.secondWinPct), pct(o.secondWinPct), m.secondWinPct, o.secondWinPct));
    frag.appendChild(row("Return points won", pct(m.returnWinPct), pct(o.returnWinPct), m.returnWinPct, o.returnWinPct));
    frag.appendChild(row("Break points won", m.bpConv + "/" + m.bpChances, o.bpConv + "/" + o.bpChances,
      m.bpConv + 0.1, o.bpConv + 0.1));
    frag.appendChild(row("Big-point win rate", pct(m.bigWinPct), pct(o.bigWinPct), m.bigWinPct, o.bigWinPct));
    elBody.innerHTML = "";
    elBody.appendChild(frag);
  }

  function renderMomentum() {
    var p = current.match.points, n = p.length;
    var w = 320, h = 150, diff = 0, vals = [], max = 1;
    p.forEach(function (x) { diff += x.winner === "me" ? 1 : -1; vals.push(diff); if (Math.abs(diff) > max) max = Math.abs(diff); });
    var coords = vals.map(function (d, i) {
      var x = n > 1 ? (i / (n - 1)) * w : 0;
      var y = h / 2 - (d / max) * (h / 2 - 10);
      return x.toFixed(1) + "," + y.toFixed(1);
    });
    var area = "0," + (h / 2) + " " + coords.join(" ") + " " + w + "," + (h / 2);
    elBody.innerHTML =
      '<p class="c-note">Cumulative points momentum — above the line you were ahead on the run of play.</p>' +
      '<svg class="momentum-svg" viewBox="0 0 ' + w + ' ' + h + '" preserveAspectRatio="none" role="img" aria-label="Match momentum chart">' +
        '<defs><linearGradient id="mg" x1="0" y1="0" x2="0" y2="1">' +
          '<stop offset="0" stop-color="rgba(47,208,138,.45)"/><stop offset="1" stop-color="rgba(47,208,138,0)"/>' +
        '</linearGradient></defs>' +
        '<line x1="0" y1="' + (h / 2) + '" x2="' + w + '" y2="' + (h / 2) + '" stroke="rgba(255,255,255,.18)" stroke-dasharray="4 4"/>' +
        '<polygon points="' + area + '" fill="url(#mg)"/>' +
        '<polyline points="' + coords.join(" ") + '" fill="none" stroke="#2fd08a" stroke-width="2.5" stroke-linejoin="round"/>' +
      '</svg>' +
      '<div class="c-momentum-foot"><span>Start</span><span>' + current.score + '</span><span>Final</span></div>';
  }

  function renderCoach() {
    var prompt = coachPrompt(current.stats.me, current.stats.total, current.score, current.won);
    var box = document.createElement("div");
    box.innerHTML =
      '<p class="c-note">One tap sends this prompt to your AI of choice. Here it is verbatim:</p>' +
      '<pre class="coach-pre"></pre>' +
      '<div class="apps-row" style="margin-top:14px;">' +
        '<button class="chip" data-ai="https://chat.openai.com/">Open in ChatGPT</button>' +
        '<button class="chip" data-ai="https://claude.ai/new">Open in Claude</button>' +
        '<button class="chip" data-ai="https://gemini.google.com/app">Open in Gemini</button>' +
      '</div>' +
      '<p class="c-copied" data-c-copied hidden>Prompt copied — paste it into the chat ✦</p>';
    box.querySelector(".coach-pre").textContent = prompt;
    elBody.innerHTML = "";
    elBody.appendChild(box);
    var copied = box.querySelector("[data-c-copied]");
    box.querySelectorAll("[data-ai]").forEach(function (b) {
      b.addEventListener("click", function () {
        var url = b.getAttribute("data-ai");
        function go() { window.open(url, "_blank", "noopener"); }
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(prompt).then(function () {
            copied.hidden = false; setTimeout(function () { copied.hidden = true; }, 2600); go();
          }, go);
        } else { go(); }
      });
    });
  }

  function renderTab() {
    if (activeTab === "stats") renderStats();
    else if (activeTab === "momentum") renderMomentum();
    else renderCoach();
    elBody.scrollTop = 0;
  }

  tabBtns.forEach(function (b) {
    b.addEventListener("click", function () {
      activeTab = b.getAttribute("data-c-tab");
      tabBtns.forEach(function (x) { x.setAttribute("aria-pressed", x === b ? "true" : "false"); });
      renderTab();
    });
  });
  if (regen) regen.addEventListener("click", function () { build((Math.random() * 1e9) | 0); });

  if (typeof window !== "undefined") {
    window.DeuceMateCompanion = {
      generateMatch: generateMatch, sideStats: sideStats,
      scoreString: scoreString, coachPrompt: coachPrompt
    };
  }

  build(20240613); // a stable, competitive opening match
})();
