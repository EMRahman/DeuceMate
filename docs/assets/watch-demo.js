/* ==========================================================================
   DeuceMate — browser playground for the Apple Watch scorer.

   The scoring rules below are a faithful, dependency-free JavaScript port of
   the app's shared Swift engine:
     Packages/DeuceMateCore/Sources/DeuceMateCore/Scoring/ScoringEngine.swift
     Packages/DeuceMateCore/Sources/DeuceMateCore/Models/ScoreTypes.swift
   The demo plays SINGLES only (the watch also handles doubles four-player
   service rotation); everything else — points, games, sets, tiebreaks, super
   tiebreaks, server rotation, side-changes and all six formats — mirrors the
   real engine so the experience matches the app.
   ========================================================================== */
(function () {
  "use strict";

  /* ---- Format configs (mirror MatchFormat.config in ScoreTypes.swift) ---- */
  function cfgFor(format) {
    switch (format) {
      case "standard":
        return base({ setsToWin: 2, playRegularSets: true, regularSetTiebreakPoints: 7, finalSetStyle: "superTiebreak", finalSetTiebreakPoints: 10, isEndless: false });
      case "bestOf3FullFinalSet":
        return base({ setsToWin: 2, playRegularSets: true, regularSetTiebreakPoints: 7, finalSetStyle: "fullSetWithTiebreak", finalSetTiebreakPoints: 7, isEndless: false });
      case "superTiebreak":
        return base({ setsToWin: 1, playRegularSets: false, regularSetTiebreakPoints: 10, finalSetStyle: "superTiebreak", finalSetTiebreakPoints: 10, isEndless: false });
      case "perpetualSuperTiebreak":
        return base({ setsToWin: 1, playRegularSets: false, regularSetTiebreakPoints: 10, finalSetStyle: "superTiebreak", finalSetTiebreakPoints: 10, isEndless: true });
      case "quick4Games":
        return base({ setsToWin: 1, playRegularSets: true, regularSetWinAtGames: 3, regularSetTiebreakAtGames: 2, regularSetTiebreakPoints: 1, finalSetStyle: "fullSetWithTiebreak", finalSetTiebreakPoints: 1, tiebreakRequiresTwoPointLead: false, isEndless: false });
      case "perpetualPoints":
        return base({ setsToWin: 1, playRegularSets: false, regularSetTiebreakPoints: 10, finalSetStyle: "superTiebreak", finalSetTiebreakPoints: 10, isEndless: true, disablesPointTracking: true, fixedDeuceSide: true });
      default:
        return cfgFor("standard");
    }
  }
  function base(o) {
    return {
      setsToWin: o.setsToWin,
      playRegularSets: o.playRegularSets,
      regularSetWinAtGames: o.regularSetWinAtGames != null ? o.regularSetWinAtGames : 6,
      regularSetTiebreakAtGames: o.regularSetTiebreakAtGames != null ? o.regularSetTiebreakAtGames : 6,
      regularSetTiebreakPoints: o.regularSetTiebreakPoints,
      finalSetStyle: o.finalSetStyle,
      finalSetTiebreakPoints: o.finalSetTiebreakPoints,
      tiebreakRequiresTwoPointLead: o.tiebreakRequiresTwoPointLead != null ? o.tiebreakRequiresTwoPointLead : true,
      isEndless: o.isEndless,
      disablesPointTracking: !!o.disablesPointTracking,
      fixedDeuceSide: !!o.fixedDeuceSide,
      get regularSetTiebreakWinAtGames() { return this.regularSetTiebreakAtGames + 1; }
    };
  }

  function newSet(isTieBreak) {
    return { gamesMe: 0, gamesOpponent: 0, isTieBreak: !!isTieBreak, tieBreakPointsMe: 0, tieBreakPointsOpponent: 0 };
  }
  function lastSet(state) { return state.sets[state.sets.length - 1]; }
  function other(p) { return p === "me" ? "opponent" : "me"; }
  function clone(state) { return JSON.parse(JSON.stringify(state)); }

  /* ---- Pure helpers (mirror ScoringEngine static functions) ---- */
  function isNormalSetComplete(cfg, gm, go) {
    var diff = Math.abs(gm - go);
    var tbWin = cfg.regularSetTiebreakWinAtGames;
    return ((gm >= cfg.regularSetWinAtGames || go >= cfg.regularSetWinAtGames) && diff >= 2) || gm === tbWin || go === tbWin;
  }
  function tiebreakTargetPoints(index, setScores, cfg) {
    if (!cfg.playRegularSets) return cfg.finalSetTiebreakPoints;
    var completedBefore = 0;
    for (var i = 0; i < index && i < setScores.length; i++) {
      var s = setScores[i];
      if (isNormalSetComplete(cfg, s.gamesMe, s.gamesOpponent)) completedBefore++;
    }
    var isDeciding = completedBefore >= cfg.setsToWin * 2 - 2;
    return isDeciding ? cfg.finalSetTiebreakPoints : cfg.regularSetTiebreakPoints;
  }
  function isTiebreakComplete(me, opp, target, cfg) {
    var reached = me >= target || opp >= target;
    if (!cfg.tiebreakRequiresTwoPointLead) return reached;
    return reached && Math.abs(me - opp) >= 2;
  }
  function completedSets(state) {
    var cfg = state.cfg, out = [];
    for (var i = 0; i < state.sets.length; i++) {
      var s = state.sets[i];
      if (s.isTieBreak) {
        var target = tiebreakTargetPoints(i, state.sets, cfg);
        if (isTiebreakComplete(s.tieBreakPointsMe, s.tieBreakPointsOpponent, target, cfg)) out.push(s);
      } else if (isNormalSetComplete(cfg, s.gamesMe, s.gamesOpponent)) {
        out.push(s);
      }
    }
    return out;
  }
  function setsWon(state, who) {
    return completedSets(state).filter(function (s) {
      return who === "me" ? s.gamesMe > s.gamesOpponent : s.gamesOpponent > s.gamesMe;
    }).length;
  }
  function isMatchComplete(state) {
    var cfg = state.cfg;
    if (cfg.isEndless) return false;
    var done = completedSets(state);
    if (!cfg.playRegularSets) return done.length > 0;
    return setsWon(state, "me") >= cfg.setsToWin || setsWon(state, "opponent") >= cfg.setsToWin;
  }
  function matchWinner(state) {
    var cfg = state.cfg, done = completedSets(state);
    if (!done.length || cfg.isEndless) return null;
    if (!cfg.playRegularSets) {
      var tb = done[done.length - 1];
      return tb.tieBreakPointsMe > tb.tieBreakPointsOpponent ? "me" : "opponent";
    }
    if (setsWon(state, "me") >= cfg.setsToWin) return "me";
    if (setsWon(state, "opponent") >= cfg.setsToWin) return "opponent";
    return null;
  }
  function isBreakPoint(state) {
    if (!state.currentServer) return false;
    if (lastSet(state) && lastSet(state).isTieBreak) return false;
    var sp = state.currentServer === "me" ? state.currentPointsMe : state.currentPointsOpponent;
    var rp = state.currentServer === "me" ? state.currentPointsOpponent : state.currentPointsMe;
    return rp >= 3 && rp > sp;
  }

  /* ---- The reducer (mirrors ScoringEngine.Engine.updateScore) ---- */
  function pointWon(prev, player) {
    if (!prev.currentServer || !prev.sets.length) return { state: prev, events: [] };
    var state = clone(prev);
    state.cfg = prev.cfg; // cfg is stateless; reattach after JSON clone
    var events = [];
    updateScore(state, player, events);
    return { state: state, events: events };
  }

  function updateScore(state, player, events) {
    var set = state.sets.pop();
    if (set.isTieBreak) { updateTiebreak(state, set, player, events); return; }

    var pm = state.currentPointsMe, po = state.currentPointsOpponent;
    if (player === "me") pm++; else po++;

    if (pm >= 4 && pm - po >= 2) { gameWon(state, "me", set, events); }
    else if (po >= 4 && po - pm >= 2) { gameWon(state, "opponent", set, events); }
    else {
      state.currentPointsMe = pm; state.currentPointsOpponent = po;
      state.sets.push(set);
      events.push({ t: "point" });
    }
  }

  function gameWon(state, player, set, events) {
    if (player === "me") set.gamesMe++; else set.gamesOpponent++;
    var totalGames = set.gamesMe + set.gamesOpponent;
    state.gameCount++;
    state.currentServer = other(state.currentServer);

    var cfg = state.cfg, tbAt = cfg.regularSetTiebreakAtGames;
    if (set.gamesMe === tbAt && set.gamesOpponent === tbAt) {
      set.isTieBreak = true; set.tieBreakPointsMe = 0; set.tieBreakPointsOpponent = 0;
      state.pointCountInTiebreak = 0;
      state.tiebreakStartServer = state.currentServer;
      state.tiebreakFirstPointReceiver = other(state.currentServer);
      events.push({ t: "tiebreakStarted" });
      events.push({ t: "changeover", text: cfg.tiebreakRequiresTwoPointLead ? "Tiebreak!" : "Sudden death!" });
      state.sets.push(set);
      return;
    } else if (isNormalSetComplete(cfg, set.gamesMe, set.gamesOpponent)) {
      completeSet(state, player, set, events);
      sideChangeAfterSet(totalGames, events);
      if (lastSet(state) && lastSet(state).isTieBreak) {
        state.tiebreakStartServer = state.currentServer;
        state.tiebreakFirstPointReceiver = other(state.currentServer);
      }
      return;
    }

    state.currentPointsMe = 0; state.currentPointsOpponent = 0;
    events.push({ t: "gameWon", winner: player });
    if (totalGames > 0) events.push({ t: "changeover", text: totalGames % 2 === 1 ? "Change ends" : "New balls soon" });
    state.sets.push(set);
  }

  function updateTiebreak(state, set, player, events) {
    if (player === "me") set.tieBreakPointsMe++; else set.tieBreakPointsOpponent++;
    state.pointCountInTiebreak++;

    if (state.tiebreakStartServer) {
      var start = state.tiebreakStartServer, oth = other(start), pn = state.pointCountInTiebreak, s;
      if (pn === 1) s = start;
      else if (state.cfg.fixedDeuceSide) s = pn % 2 === 1 ? start : oth;
      else { var pair = Math.floor((pn - 2) / 2); s = pair % 2 === 0 ? oth : start; }
      state.lastTiebreakPointServer = s;
    }

    var me = set.tieBreakPointsMe, opp = set.tieBreakPointsOpponent;
    var cfg = state.cfg;
    var target = tiebreakTargetPoints(state.sets.length, state.sets.concat([set]), cfg);

    if (!cfg.isEndless && isTiebreakComplete(me, opp, target, cfg)) {
      if (cfg.playRegularSets) {
        if (me > opp) set.gamesMe = cfg.regularSetTiebreakWinAtGames;
        else set.gamesOpponent = cfg.regularSetTiebreakWinAtGames;
      }
      completeSet(state, me > opp ? "me" : "opponent", set, events);
      events.push({ t: "changeover", text: "Change ends" });
      if (state.tiebreakFirstPointReceiver) state.currentServer = state.tiebreakFirstPointReceiver;
      state.tiebreakStartServer = null; state.tiebreakFirstPointReceiver = null;
      if (lastSet(state) && lastSet(state).isTieBreak) {
        state.tiebreakStartServer = state.currentServer;
        state.tiebreakFirstPointReceiver = other(state.currentServer);
      }
      return;
    }

    events.push({ t: "tiebreakPoint" });
    if (!cfg.fixedDeuceSide && state.pointCountInTiebreak % 6 === 0) events.push({ t: "changeover", text: "Change ends" });
    advanceTiebreakServer(state);
    state.sets.push(set);
  }

  function advanceTiebreakServer(state) {
    var start = state.tiebreakStartServer; if (!start) return;
    var oth = other(start), np = state.pointCountInTiebreak + 1;
    if (np === 1) state.currentServer = start;
    else if (state.cfg.fixedDeuceSide) state.currentServer = np % 2 === 1 ? start : oth;
    else { var pair = Math.floor((np - 2) / 2); state.currentServer = pair % 2 === 0 ? oth : start; }
  }

  function completeSet(state, winner, finishedSet, events) {
    state.sets.push(finishedSet);
    var cfg = state.cfg;
    if (!cfg.playRegularSets && !cfg.isEndless) {
      events.push({ t: "matchWon", winner: winner });
      state.currentPointsMe = 0; state.currentPointsOpponent = 0;
      return;
    }
    var won = setsWon(state, "me"), lost = setsWon(state, "opponent");
    var matchOver = won >= cfg.setsToWin || lost >= cfg.setsToWin;
    if (matchOver) {
      events.push({ t: "matchWon", winner: won >= cfg.setsToWin ? "me" : "opponent" });
    } else {
      events.push({ t: "setWon", winner: winner });
      var bothNeedOne = won === cfg.setsToWin - 1 && lost === cfg.setsToWin - 1;
      if (bothNeedOne && cfg.finalSetStyle === "superTiebreak") {
        state.pointCountInTiebreak = 0;
        state.sets.push(newSet(true));
      } else {
        state.sets.push(newSet(false));
      }
    }
    state.currentPointsMe = 0; state.currentPointsOpponent = 0;
  }

  function sideChangeAfterSet(totalGames, events) {
    events.push({ t: "changeover", text: totalGames % 2 === 1 ? "Change ends" : "New balls soon" });
  }

  /* ---- Initial state for a chosen format + first server ---- */
  function freshState(format, firstServer) {
    var cfg = cfgFor(format);
    var state = {
      cfg: cfg,
      format: format,
      sets: [],
      currentPointsMe: 0,
      currentPointsOpponent: 0,
      currentServer: firstServer,
      gameCount: 0,
      pointCountInTiebreak: 0,
      tiebreakStartServer: null,
      tiebreakFirstPointReceiver: null,
      lastTiebreakPointServer: null
    };
    if (!cfg.playRegularSets) {
      state.sets.push(newSet(true));
      state.tiebreakStartServer = firstServer;
      state.tiebreakFirstPointReceiver = other(firstServer);
    } else {
      state.sets.push(newSet(false));
    }
    return state;
  }

  /* ---- Display helpers ---- */
  var POINT_LABELS = ["0", "15", "30", "40"];
  function regularPointStrings(me, opp) {
    if (me >= 3 && opp >= 3) {
      if (me === opp) return ["40", "40"];
      return me > opp ? ["Ad", "40"] : ["40", "Ad"];
    }
    return [POINT_LABELS[Math.min(me, 3)], POINT_LABELS[Math.min(opp, 3)]];
  }

  var FORMAT_LABELS = {
    standard: "Best of 3",
    bestOf3FullFinalSet: "Best of 3 · full final set",
    superTiebreak: "10-point tiebreak",
    perpetualSuperTiebreak: "Perpetual tiebreak",
    quick4Games: "Quick 4 games",
    perpetualPoints: "Perpetual points"
  };

  /* Expose the pure engine (handy for debugging and tests). */
  if (typeof window !== "undefined") {
    window.DeuceMateScoring = {
      freshState: freshState, pointWon: pointWon, isMatchComplete: isMatchComplete,
      matchWinner: matchWinner, completedSets: completedSets, isBreakPoint: isBreakPoint,
      regularPointStrings: regularPointStrings, lastSet: lastSet
    };
  }

  /* ====================================================================
     Controller / view
     ==================================================================== */
  var root = document.getElementById("watch-demo");
  if (!root) return;

  var el = {
    setup: root.querySelector("[data-setup]"),
    play: root.querySelector("[data-play]"),
    formatBtns: root.querySelectorAll("[data-format]"),
    serverBtns: root.querySelectorAll("[data-server]"),
    start: root.querySelector("[data-start]"),
    screen: root.querySelector("[data-screen]"),
    toast: root.querySelector("[data-toast]"),
    meSets: root.querySelector("[data-me-sets]"),
    oppSets: root.querySelector("[data-opp-sets]"),
    mePts: root.querySelector("[data-me-pts]"),
    oppPts: root.querySelector("[data-opp-pts]"),
    meDot: root.querySelector("[data-me-dot]"),
    oppDot: root.querySelector("[data-opp-dot]"),
    meRow: root.querySelector("[data-me-row]"),
    oppRow: root.querySelector("[data-opp-row]"),
    bp: root.querySelector("[data-bp]"),
    momentum: root.querySelector("[data-momentum]"),
    foot: root.querySelector("[data-foot]"),
    banner: root.querySelector("[data-banner]"),
    bannerText: root.querySelector("[data-banner-text]"),
    undo: root.querySelector("[data-undo]"),
    reset: root.querySelector("[data-reset]"),
    again: root.querySelector("[data-again]"),
    ptMe: root.querySelector("[data-pt-me]"),
    ptOpp: root.querySelector("[data-pt-opp]")
  };

  var chosenFormat = "standard";
  var chosenServer = "me";
  var state = null;
  var history = [];   // undo stack of prior states
  var momentum = [];  // last point winners
  var toastTimer = null;

  function select(btns, attr, value) {
    btns.forEach(function (b) { b.setAttribute("aria-pressed", b.getAttribute(attr) === value ? "true" : "false"); });
  }

  el.formatBtns.forEach(function (b) {
    b.addEventListener("click", function () { chosenFormat = b.getAttribute("data-format"); select(el.formatBtns, "data-format", chosenFormat); });
  });
  el.serverBtns.forEach(function (b) {
    b.addEventListener("click", function () { chosenServer = b.getAttribute("data-server"); select(el.serverBtns, "data-server", chosenServer); });
  });
  select(el.formatBtns, "data-format", chosenFormat);
  select(el.serverBtns, "data-server", chosenServer);

  el.start.addEventListener("click", startMatch);
  el.again.addEventListener("click", function () { el.banner.hidden = true; el.play.hidden = true; el.setup.hidden = false; });
  el.undo.addEventListener("click", undo);
  el.reset.addEventListener("click", function () { startMatch(); });
  if (el.ptMe) el.ptMe.addEventListener("click", function () { award("me"); });
  if (el.ptOpp) el.ptOpp.addEventListener("click", function () { award("opponent"); });

  /* Tap zones on the watch face: top half = you, bottom half = opponent. */
  el.screen.addEventListener("click", function (e) {
    if (el.banner && !el.banner.hidden) return;
    var rect = el.screen.getBoundingClientRect();
    award((e.clientY - rect.top) < rect.height / 2 ? "me" : "opponent");
  });

  /* Swipe support (up = you, down = opponent, left = undo). */
  var touch = null;
  el.screen.addEventListener("touchstart", function (e) { touch = e.changedTouches[0]; }, { passive: true });
  el.screen.addEventListener("touchend", function (e) {
    if (!touch) return;
    var t = e.changedTouches[0], dx = t.clientX - touch.clientX, dy = t.clientY - touch.clientY;
    if (Math.abs(dx) > 40 && Math.abs(dx) > Math.abs(dy)) { if (dx < 0) undo(); touch = null; e.preventDefault(); return; }
    if (Math.abs(dy) > 40) { award(dy < 0 ? "me" : "opponent"); touch = null; e.preventDefault(); return; }
    touch = null;
  }, { passive: false });

  /* Keyboard shortcuts while the demo is on screen. */
  document.addEventListener("keydown", function (e) {
    if (el.play.hidden) return;
    if (e.key === "ArrowUp") { award("me"); e.preventDefault(); }
    else if (e.key === "ArrowDown") { award("opponent"); e.preventDefault(); }
    else if (e.key === "Backspace" || e.key.toLowerCase() === "u") { undo(); e.preventDefault(); }
    else if (e.key.toLowerCase() === "r") { startMatch(); e.preventDefault(); }
  });

  function startMatch() {
    state = freshState(chosenFormat, chosenServer);
    history = [];
    momentum = [];
    el.banner.hidden = true;
    el.setup.hidden = true;
    el.play.hidden = false;
    showToast(null);
    render();
  }

  function award(player) {
    if (!state || isMatchComplete(state)) return;
    history.push({ snapshot: clone(state), momentum: momentum.slice() });
    if (history.length > 200) history.shift();
    var res = pointWon(state, player);
    state = res.state;
    momentum.push(player);
    if (momentum.length > 8) momentum.shift();
    applyEvents(res.events);
    render();
  }

  function undo() {
    if (!history.length) return;
    var prev = history.pop();
    prev.snapshot.cfg = state.cfg;
    state = prev.snapshot;
    momentum = prev.momentum;
    el.banner.hidden = true;
    showToast("Undo");
    render();
  }

  function applyEvents(events) {
    var winner = matchWinner(state);
    var matchEvt = events.filter(function (e) { return e.t === "matchWon"; })[0];
    if (matchEvt || (winner && isMatchComplete(state))) {
      var w = matchEvt ? matchEvt.winner : winner;
      el.bannerText.textContent = (w === "me" ? "You win! 🎾" : "Opponent wins");
      el.banner.hidden = false;
      return;
    }
    // Pick the most significant transient toast.
    var setEvt = events.filter(function (e) { return e.t === "setWon"; })[0];
    var tb = events.filter(function (e) { return e.t === "tiebreakStarted"; })[0];
    var game = events.filter(function (e) { return e.t === "gameWon"; })[0];
    var change = events.filter(function (e) { return e.t === "changeover"; })[0];
    if (setEvt) showToast(setEvt.winner === "me" ? "Set — you" : "Set — opponent");
    else if (tb) showToast(change ? change.text : "Tiebreak!");
    else if (game) showToast(game.winner === "me" ? "Game — you" : "Game — opponent");
    else if (change) showToast(change.text);
    else showToast(null);
  }

  function showToast(text) {
    if (toastTimer) { clearTimeout(toastTimer); toastTimer = null; }
    if (!text) { el.toast.hidden = true; el.toast.textContent = ""; return; }
    el.toast.textContent = text;
    el.toast.hidden = false;
    toastTimer = setTimeout(function () { el.toast.hidden = true; }, 1900);
  }

  function render() {
    var cfg = state.cfg;
    var last = lastSet(state);
    var inTiebreak = last && last.isTieBreak;

    // Set columns (games) — only for formats that play games.
    el.meSets.innerHTML = "";
    el.oppSets.innerHTML = "";
    if (cfg.playRegularSets) {
      state.sets.forEach(function (s, i) {
        el.meSets.appendChild(setCell(s.gamesMe, s.isTieBreak ? s.tieBreakPointsMe : null, i === state.sets.length - 1));
        el.oppSets.appendChild(setCell(s.gamesOpponent, s.isTieBreak ? s.tieBreakPointsOpponent : null, i === state.sets.length - 1));
      });
      el.meSets.hidden = false; el.oppSets.hidden = false;
    } else {
      el.meSets.hidden = true; el.oppSets.hidden = true;
    }

    // Big current points.
    if (inTiebreak) {
      el.mePts.textContent = String(last.tieBreakPointsMe);
      el.oppPts.textContent = String(last.tieBreakPointsOpponent);
    } else {
      var strs = regularPointStrings(state.currentPointsMe, state.currentPointsOpponent);
      el.mePts.textContent = strs[0];
      el.oppPts.textContent = strs[1];
    }

    // Server dots.
    el.meDot.style.visibility = state.currentServer === "me" ? "visible" : "hidden";
    el.oppDot.style.visibility = state.currentServer === "opponent" ? "visible" : "hidden";

    // Break point flag.
    el.bp.hidden = !isBreakPoint(state);

    // Momentum strip.
    el.momentum.innerHTML = "";
    for (var i = 0; i < 8; i++) {
      var pip = document.createElement("span");
      pip.className = "pip";
      var idx = momentum.length - 8 + i;
      if (idx >= 0) pip.classList.add(momentum[idx] === "me" ? "pip-me" : "pip-opp");
      el.momentum.appendChild(pip);
    }

    // Footer.
    el.foot.textContent = FORMAT_LABELS[state.format] + " · Singles";

    var over = isMatchComplete(state);
    el.undo.disabled = !history.length;
    if (el.ptMe) el.ptMe.disabled = over;
    if (el.ptOpp) el.ptOpp.disabled = over;
  }

  function setCell(games, tbPts, isCurrent) {
    var span = document.createElement("span");
    span.className = "setcell" + (isCurrent ? " setcell-cur" : "");
    span.textContent = String(games);
    if (tbPts != null) {
      var sup = document.createElement("sup");
      sup.textContent = String(tbPts);
      span.appendChild(sup);
    }
    return span;
  }
})();
