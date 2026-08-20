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
  function clone(state) { var copy = JSON.parse(JSON.stringify(state)); copy.cfg = state.cfg; return copy; }

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
  /* ---- Mirrors ScoreTypes.swift's isDecidingSuperTiebreak(setIndex:): true
     only for the single deciding tiebreak-only set of a regular multi-set
     match whose final set is a super tiebreak (e.g. "standard" format's set
     index 2). Always false for formats where every set is already a
     tiebreak (playRegularSets: false) — those stay "S1"/"S2" in the stats
     view's set filter, "TB" is reserved for the deciding-set case. ---- */
  function isDecidingSuperTiebreak(cfg, setIndex) {
    return !!cfg.playRegularSets && cfg.finalSetStyle === "superTiebreak" && setIndex === cfg.setsToWin * 2 - 2;
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
    var state = clone(prev); // clone() re-attaches the (stateless) cfg
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

  /* Current-game point label for one player — mirrors ScoreViewModel.displayedScore
     (note the watch uses uppercase "AD"). */
  var POINT_DISPLAY = ["0", "15", "30", "40", "AD"];
  function watchPointLabel(state, player) {
    var last = lastSet(state);
    if (last && last.isTieBreak) {
      return String(player === "me" ? last.tieBreakPointsMe : last.tieBreakPointsOpponent);
    }
    var pm = state.currentPointsMe, po = state.currentPointsOpponent;
    if (pm >= 3 && po >= 3) {
      if (pm === po) return "40";
      if (pm > po) return player === "me" ? "AD" : "40";
      return player === "opponent" ? "AD" : "40";
    }
    return POINT_DISPLAY[Math.min(player === "me" ? pm : po, 4)];
  }

  /* Which set columns the scoreboard shows — mirrors ContentView.scoreboardSets:
     hide the deciding super-tiebreak set until the match is complete (its live
     points show in the point badge instead), and cap perpetual tiebreaks at 3. */
  function visibleSetIndices(state) {
    var cfg = state.cfg, n = state.sets.length, out = [];
    for (var i = 0; i < n; i++) {
      var set = state.sets[i];
      if (state.format === "perpetualSuperTiebreak") { if (i >= n - 3) out.push(i); continue; }
      var isThird = n === 3 && i === 2;
      var hideSuperTBBeforeComplete = isThird && set.isTieBreak && !isMatchComplete(state);
      var hideRegularThird = isThird && !set.isTieBreak && cfg.finalSetStyle === "superTiebreak";
      if (hideSuperTBBeforeComplete || hideRegularThird) continue;
      out.push(i);
    }
    return out;
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
      regularPointStrings: regularPointStrings, lastSet: lastSet,
      isDecidingSuperTiebreak: isDecidingSuperTiebreak
    };
  }

  /* ====================================================================
     Controller / view  (supports multiple instances + compact/hero mode)
     ==================================================================== */
  function initWatchDemo(root) {
  var compact = root.hasAttribute("data-compact");
  var useKeyboard = root.hasAttribute("data-keyboard");

  var el = {
    setup: root.querySelector("[data-setup]"),
    play: root.querySelector("[data-play]"),
    formatBtns: root.querySelectorAll("[data-format]"),
    serverBtns: root.querySelectorAll("[data-server]"),
    start: root.querySelector("[data-start]"),
    screen: root.querySelector("[data-screen]"),
    toast: root.querySelector("[data-toast]"),
    meCells: root.querySelector("[data-me-cells]"),
    oppCells: root.querySelector("[data-opp-cells]"),
    mePts: root.querySelector("[data-me-pts]"),
    oppPts: root.querySelector("[data-opp-pts]"),
    meServer: root.querySelector("[data-me-server]"),
    oppServer: root.querySelector("[data-opp-server]"),
    meRow: root.querySelector("[data-me-row]"),
    oppRow: root.querySelector("[data-opp-row]"),
    card: root.querySelector(".w-card"),
    momentum: root.querySelector("[data-momentum]"),
    foot: root.querySelector("[data-foot]"),
    banner: root.querySelector("[data-banner]"),
    bannerText: root.querySelector("[data-banner-text]"),
    undo: root.querySelector("[data-undo]"),
    reset: root.querySelector("[data-reset]"),
    again: root.querySelector("[data-again]"),
    ptMe: root.querySelector("[data-pt-me]"),
    ptOpp: root.querySelector("[data-pt-opp]"),
    trackToggle: root.querySelector("[data-track-toggle]"),
    secondServe: root.querySelector("[data-secondserve]"),
    sheet: root.querySelector("[data-sheet]"),
    stats: root.querySelector("[data-stats]"),
    statsClose: root.querySelector("[data-stats-close]"),
    statsToggle: root.querySelector("[data-stats-toggle]"),
    statsTitle: root.querySelector("[data-stats-title]"),
    statsFormat: root.querySelector("[data-stats-format]"),
    statsSetFilter: root.querySelector("[data-stats-setfilter]"),
    statsBody: root.querySelector("[data-stats-body]")
  };

  var chosenFormat = root.getAttribute("data-format") || "standard";
  var chosenServer = root.getAttribute("data-server") || "me";
  var state = null;
  var history = [];   // undo stack of prior states: {snapshot, momentum, secondServe, statsLen}
  var momentum = [];  // last point winners
  var toastTimer = null;
  // Point-outcome tracking (plan §A/§C). Default ON — the demo exists to show
  // this feature off, deliberately differing from the watch's off-default.
  var trackingEnabled = true;
  var isOnSecondServe = false;
  var stats = [];     // PointStat-shaped records (see watch-demo-tracking.js)
  var lastCardTapAt = 0;

  // Live stats overlay (plan §D, mirrors MatchStatsView.swift).
  var statsOpen = false;
  var statsSetFilter = null; // null = "All", else a set index

  // Categorisation sheet (plan §B/§C, mirrors PointCategorySheet.swift).
  // sheetStep is 1|2|null; null means the sheet is closed and all normal
  // scoring input is live again.
  var pendingStat = null;      // PendingPointInfo-shaped, from buildPendingPoint()
  var sheetStep = null;
  var sheetOutcome = null;     // stashed step-1 choice, carried into step 2
  var sheetBusy = false;       // true during the 0.4s commit beat (ignore taps)
  var sheetCommitTimer = null; // the commit-beat timeout, cancellable by New match
  var deferredEvents = null;   // pointWon() events, applied 0.4s after the sheet commits
  var deferredToastTimer = null;
  var deferredToastEvents = null; // events captured for deferredToastTimer (deferredEvents is already cleared by closeSheet() by the time the timer fires)

  function select(btns, attr, value) {
    btns.forEach(function (b) { b.setAttribute("aria-pressed", b.getAttribute(attr) === value ? "true" : "false"); });
  }

  if (el.formatBtns.length) {
    el.formatBtns.forEach(function (b) {
      b.addEventListener("click", function () { chosenFormat = b.getAttribute("data-format"); select(el.formatBtns, "data-format", chosenFormat); });
    });
    select(el.formatBtns, "data-format", chosenFormat);
  }
  if (el.serverBtns.length) {
    el.serverBtns.forEach(function (b) {
      b.addEventListener("click", function () { chosenServer = b.getAttribute("data-server"); select(el.serverBtns, "data-server", chosenServer); });
    });
    select(el.serverBtns, "data-server", chosenServer);
  }

  if (el.start) el.start.addEventListener("click", startMatch);
  if (el.again) el.again.addEventListener("click", function (e) {
    // Without this, the click bubbles to el.screen's tap-to-score listener
    // *after* banner.hidden is already true (set below), so its guard no
    // longer blocks and the same click also scores a point.
    e.stopPropagation();
    el.banner.hidden = true;
    if (compact || !el.setup) { startMatch(); return; }
    el.play.hidden = true; el.setup.hidden = false;
  });
  if (el.undo) el.undo.addEventListener("click", undo);
  if (el.reset) el.reset.addEventListener("click", function () { startMatch(); });
  if (el.ptMe) el.ptMe.addEventListener("click", function () { award("me"); });
  if (el.ptOpp) el.ptOpp.addEventListener("click", function () { award("opponent"); });

  if (el.trackToggle) {
    el.trackToggle.setAttribute("aria-pressed", "true");
    el.trackToggle.addEventListener("click", function () {
      trackingEnabled = !trackingEnabled;
      el.trackToggle.setAttribute("aria-pressed", trackingEnabled ? "true" : "false");
      render();
    });
  }
  if (el.secondServe) el.secondServe.addEventListener("click", toggleSecondServe);
  if (el.statsToggle) el.statsToggle.addEventListener("click", toggleStatsButton);
  if (el.statsClose) el.statsClose.addEventListener("click", closeStats);

  /* Second-serve gesture (plan §A, mirrors toggleSecondServe/ContentView
     ~L163-169): scoped to the scoreboard card, not the whole watch face, so
     the tap-to-score zone stays the screen area outside it. A manual
     double-tap window (rather than the native `dblclick` event) matches
     mouse and touch identically. */
  if (el.card) {
    el.card.addEventListener("click", function (e) {
      e.stopPropagation();
      var now = Date.now();
      if (now - lastCardTapAt < 350) { lastCardTapAt = 0; toggleSecondServe(); }
      else { lastCardTapAt = now; }
    });
  }

  /* The sheet's own buttons (Undo point, outcome/ending-shot choices, back)
     clear sheetStep synchronously before the click finishes bubbling, so
     without this el.screen's guard below would miss it and also score a
     point on the same click — same class of bug as el.card above. */
  if (el.sheet) el.sheet.addEventListener("click", function (e) { e.stopPropagation(); });

  /* Same reasoning as el.sheet above: closing the overlay clears statsOpen
     synchronously before the click bubbles to el.screen's tap-to-score
     listener, which would otherwise misfire on the same click. */
  if (el.stats) el.stats.addEventListener("click", function (e) { e.stopPropagation(); });

  if (el.screen) {
    /* Tap zones on the watch face: top half = you, bottom half = opponent.
       Taps inside the scoreboard card are handled above and never score. */
    el.screen.addEventListener("click", function (e) {
      if ((el.banner && !el.banner.hidden) || sheetStep || statsOpen) return;
      var rect = el.screen.getBoundingClientRect();
      award((e.clientY - rect.top) < rect.height / 2 ? "me" : "opponent");
    });

    /* Swipe support (up = you, down = opponent, left = undo, right = stats). */
    var touch = null;
    el.screen.addEventListener("touchstart", function (e) { touch = e.changedTouches[0]; }, { passive: true });
    el.screen.addEventListener("touchend", function (e) {
      if (!touch) return;
      var t = e.changedTouches[0], dx = t.clientX - touch.clientX, dy = t.clientY - touch.clientY;
      if (Math.abs(dx) > 40 && Math.abs(dx) > Math.abs(dy)) { if (dx < 0) undo(); else toggleStatsGesture(); touch = null; e.preventDefault(); return; }
      if (Math.abs(dy) > 40) { award(dy < 0 ? "me" : "opponent"); touch = null; e.preventDefault(); return; }
      touch = null;
    }, { passive: false });
  }

  /* Keyboard shortcuts (only on instances that opt in via data-keyboard).
     "R" (new match) is the sheet's one bypass — plan's Undo model: "'New
     match' / R likewise clears sheet + pending + stats." Everything else is
     blocked while a sheet is open (plan §UI state machine). */
  if (useKeyboard) document.addEventListener("keydown", function (e) {
    if (!el.play || el.play.hidden) return;
    if (e.key.toLowerCase() === "r") { startMatch(); e.preventDefault(); return; }
    if (statsOpen) {
      if (e.key === "Escape" || e.key.toLowerCase() === "s") { closeStats(); e.preventDefault(); }
      return;
    }
    if (sheetStep) return;
    if (e.key === "ArrowUp") { award("me"); e.preventDefault(); }
    else if (e.key === "ArrowDown") { award("opponent"); e.preventDefault(); }
    else if (e.key === "Backspace" || e.key.toLowerCase() === "u") { undo(); e.preventDefault(); }
    else if (e.key === "2") { toggleSecondServe(); e.preventDefault(); }
    else if (e.key.toLowerCase() === "s") { toggleStatsGesture(); e.preventDefault(); }
  });

  /* Guards mirror ScoreViewModel.toggleSecondServe: no-op when tracking is
     off, in Perpetual Points (disablesPointTracking), while the
     categorisation sheet or stats overlay is open, or once the match is
     complete. */
  function canToggleSecondServe() {
    return !!state && !isMatchComplete(state) && trackingEnabled && !state.cfg.disablesPointTracking && !sheetStep && !statsOpen;
  }
  function toggleSecondServe() {
    if (!canToggleSecondServe()) return;
    isOnSecondServe = !isOnSecondServe;
    render();
  }

  function startMatch() {
    state = freshState(chosenFormat, chosenServer);
    history = [];
    momentum = [];
    isOnSecondServe = false;
    stats = [];
    statsOpen = false;
    statsSetFilter = null;
    pendingStat = null;
    sheetStep = null;
    sheetOutcome = null;
    sheetBusy = false;
    deferredEvents = null;
    if (sheetCommitTimer) { clearTimeout(sheetCommitTimer); sheetCommitTimer = null; }
    if (deferredToastTimer) { clearTimeout(deferredToastTimer); deferredToastTimer = null; }
    deferredToastEvents = null;
    if (el.banner) el.banner.hidden = true;
    if (el.setup) el.setup.hidden = true;
    el.play.hidden = false;
    showToast(null);
    render();
  }

  function award(player) {
    if (!state || isMatchComplete(state) || sheetStep || statsOpen) return;

    // Resolve any still-pending deferred toast from the previous point's
    // sheet commit before this point's sheet can open — otherwise it could
    // fire mid-flight over this new, unrelated sheet (Gemini review on #49).
    if (deferredToastTimer) {
      clearTimeout(deferredToastTimer);
      deferredToastTimer = null;
      var flushEvents = deferredToastEvents;
      deferredToastEvents = null;
      if (flushEvents) applyEvents(flushEvents);
    }

    var prevState = state;
    history.push({ snapshot: clone(prevState), momentum: momentum.slice(), secondServe: isOnSecondServe, statsLen: stats.length });
    if (history.length > 200) history.shift();

    // `prevState` is the pre-reducer snapshot the pending point is built
    // from (plan §data model) — perpetualPoints never builds one (§C).
    var pending = prevState.cfg.disablesPointTracking ? null
      : window.DeuceMateTracking.buildPendingPoint(prevState, player, isOnSecondServe);

    var res = pointWon(prevState, player);
    state = res.state;
    isOnSecondServe = false;
    momentum.push(player);
    if (momentum.length > 8) momentum.shift();
    flashPoint(player);

    if (pending && trackingEnabled) {
      // Open the categorisation sheet (plan §B). Toasts/changeover/banner
      // for this point are deferred until the sheet commits.
      pendingStat = pending;
      deferredEvents = res.events;
      sheetStep = 1;
      sheetOutcome = null;
      sheetBusy = false;
      render();
      return;
    }

    if (pending) {
      // Tracking off: silent uncategorized record, mirrors autoRecordPointStat.
      stats.push(window.DeuceMateTracking.buildUncategorizedStat(pending));
    }
    applyEvents(res.events);
    render();
  }

  function flashPoint(player) {
    var pts = player === "me" ? el.mePts : el.oppPts;
    if (!pts || pts.hidden) return;
    pts.classList.add("flash");
    setTimeout(function () { pts.classList.remove("flash"); }, 260);
  }

  // Shared by the main Undo button and the sheet's own "Undo point" button.
  function rollbackLastPoint() {
    if (!history.length) return false;
    var prev = history.pop();
    prev.snapshot.cfg = state.cfg;
    state = prev.snapshot;
    momentum = prev.momentum;
    isOnSecondServe = prev.secondServe;
    stats = stats.slice(0, prev.statsLen);
    return true;
  }

  function undo() {
    // Blocked while a sheet is open (plan §UI state machine) — use the
    // sheet's own "Undo point" button instead. Also blocked while the stats
    // overlay is open (a left-swipe there should do nothing, not undo a
    // point the viewer can't currently see change).
    if (!history.length || sheetStep || statsOpen) return;
    rollbackLastPoint();
    if (deferredToastTimer) { clearTimeout(deferredToastTimer); deferredToastTimer = null; }
    deferredToastEvents = null;
    if (el.banner) el.banner.hidden = true;
    showToast("Undo");
    render();
  }

  // "Undo point" inside the sheet: rolls back the whole point (score +
  // pending categorisation) and closes the sheet. Disabled during the
  // 0.4s commit beat (plan §B).
  function undoPoint() {
    if (sheetBusy) return;
    if (sheetCommitTimer) { clearTimeout(sheetCommitTimer); sheetCommitTimer = null; }
    rollbackLastPoint();
    closeSheet();
    showToast("Undo");
    render();
  }

  function closeSheet() {
    pendingStat = null;
    sheetStep = null;
    sheetOutcome = null;
    sheetBusy = false;
    deferredEvents = null;
  }

  // Applying the selection (mirrors selectOutcome, ScoreViewModel ~L1165):
  // Double Fault commits immediately with endingShot "serve"; everything
  // else stashes the outcome and advances to step 2.
  function chooseOutcome(outcome, btns, index) {
    beginCommitBeat(btns, index, function () {
      if (outcome === "doubleFault") {
        commitSheetStat("doubleFault", "serve");
      } else {
        sheetOutcome = outcome;
        sheetStep = 2;
        render();
      }
    });
  }

  function chooseEndingShot(shot, btns, index) {
    beginCommitBeat(btns, index, function () {
      commitSheetStat(sheetOutcome, shot);
    });
  }

  // Back chevron on step 2 (mirrors cancelOutcomeSelection): clears only the
  // stashed outcome, score stays applied, sheet re-renders step 1.
  function sheetBack() {
    if (sheetBusy) return;
    sheetOutcome = null;
    sheetStep = 1;
    render();
  }

  // Commit beat (plan §B): chosen button gets a check badge, siblings dim to
  // 35% opacity, further taps are ignored, then after 0.4s `onApply` runs.
  // Mutates the live sheet DOM directly rather than going through render() —
  // a full re-render would rebuild the button list from state and lose this
  // transient visual (sheetStep/sheetOutcome haven't changed yet).
  function beginCommitBeat(btns, chosenIndex, onApply) {
    if (sheetBusy) return;
    sheetBusy = true;
    btns.forEach(function (b, i) {
      b.disabled = true;
      if (i === chosenIndex) {
        var check = document.createElement("span");
        check.className = "check";
        check.textContent = "✓";
        b.appendChild(check);
      } else {
        b.classList.add("dimmed");
      }
    });
    if (el.sheetUndo) el.sheetUndo.disabled = true;
    sheetCommitTimer = setTimeout(function () {
      sheetCommitTimer = null;
      sheetBusy = false;
      onApply();
    }, 400);
  }

  function commitSheetStat(outcome, endingShot) {
    stats.push(window.DeuceMateTracking.buildPointStat(pendingStat, outcome, endingShot));
    var events = deferredEvents;
    closeSheet();
    render();
    // Toasts/changeovers queued during categorisation appear 0.4s past
    // commit (mirrors commitPointStat's DispatchQueue delay, ScoreViewModel
    // ~L1231). Stashed in deferredToastEvents (not the `events` closure
    // alone) so award() can flush it early if another point is scored
    // before this timer fires.
    deferredToastEvents = events;
    deferredToastTimer = setTimeout(function () {
      deferredToastTimer = null;
      var e = deferredToastEvents;
      deferredToastEvents = null;
      applyEvents(e);
    }, 400);
  }

  var STEP2_QUESTIONS = {
    winner: "Winning shot?",
    forcedError: "Shot that forced it?",
    unforcedError: "Shot of the error?"
  };
  // Outcome tints as r,g,b (MatchStats.swift ~L34-37) — step 2's header uses
  // these at 30% opacity (plan §B).
  var OUTCOME_TINT_RGB = {
    winner: "77,199,128",
    forcedError: "235,179,77",
    unforcedError: "168,128,235"
  };

  function shotLabel(outcome, shot) {
    if (shot === "serve") return outcome === "winner" ? "Ace" : "Serve";
    return window.DeuceMateTracking.ENDING_SHOT_LABELS[shot];
  }

  // Two-per-row grid; a trailing odd item spans the full width (plan §B).
  function buildSheetButtonsGrid(items, renderBtn) {
    var grid = document.createElement("div");
    grid.className = "sheet-buttons";
    var btns = items.map(function (item, i) {
      var b = document.createElement("button");
      b.type = "button";
      renderBtn(b, item, i);
      if (i === items.length - 1 && items.length % 2 === 1) b.classList.add("full");
      grid.appendChild(b);
      return b;
    });
    el.sheet.appendChild(grid);
    return btns;
  }

  function buildSheetUndo() {
    var btn = document.createElement("button");
    btn.type = "button";
    btn.className = "sheet-undo";
    btn.textContent = "↶ Undo point";
    btn.addEventListener("click", undoPoint);
    el.sheet.appendChild(btn);
    return btn;
  }

  function buildSheetStep1() {
    var pending = pendingStat;
    var won = pending.winner === "me";
    var yourServe = pending.server === "me";

    var header = document.createElement("div");
    header.className = "sheet-header";
    header.style.background = won ? "#21472E" : "#52242E";
    var title = document.createElement("div");
    title.className = "sheet-title";
    title.textContent = (won ? "Won" : "Lost") + " — " + (yourServe ? "Your" : "Their") + " serve";
    if (pending.isSecondServe) {
      var cap = document.createElement("span");
      cap.className = "sheet-2nd";
      cap.textContent = "2nd";
      title.appendChild(cap);
    }
    header.appendChild(title);
    el.sheet.appendChild(header);

    // PointOutcome.userSelectable order (PointStat.swift L24-26); Double
    // Fault only shows on a lost second-serve point (PointCategorySheet ~L51-57).
    var outcomes = window.DeuceMateTracking.USER_SELECTABLE_OUTCOMES.filter(function (o) {
      return o !== "doubleFault" || window.DeuceMateTracking.doubleFaultAvailable(pending);
    });
    var btns = buildSheetButtonsGrid(outcomes, function (b, outcome) {
      b.className = "sheet-btn sheet-outcome-" + outcome;
      b.textContent = window.DeuceMateTracking.OUTCOME_LABELS[outcome];
    });
    outcomes.forEach(function (outcome, i) {
      btns[i].addEventListener("click", function () { chooseOutcome(outcome, btns, i); });
    });

    el.sheetUndo = buildSheetUndo();
  }

  function buildSheetStep2() {
    var pending = pendingStat, outcome = sheetOutcome;

    var header = document.createElement("div");
    header.className = "sheet-header";
    header.style.background = "rgba(" + OUTCOME_TINT_RGB[outcome] + ",.3)";

    var back = document.createElement("button");
    back.type = "button";
    back.className = "sheet-back";
    back.textContent = "‹";
    back.setAttribute("aria-label", "Back");
    back.addEventListener("click", sheetBack);
    header.appendChild(back);

    var title = document.createElement("div");
    title.className = "sheet-title";
    title.textContent = window.DeuceMateTracking.OUTCOME_LABELS[outcome];
    var sub = document.createElement("span");
    sub.className = "sub";
    sub.textContent = STEP2_QUESTIONS[outcome];
    title.appendChild(sub);
    header.appendChild(title);
    el.sheet.appendChild(header);

    var shots = window.DeuceMateTracking.endingShotOptions(outcome, pending);
    var btns = buildSheetButtonsGrid(shots, function (b, shot) {
      b.className = "sheet-btn sheet-shot";
      b.textContent = shotLabel(outcome, shot);
    });
    shots.forEach(function (shot, i) {
      btns[i].addEventListener("click", function () { chooseEndingShot(shot, btns, i); });
    });

    el.sheetUndo = buildSheetUndo();
  }

  function renderSheet() {
    if (!el.sheet) return;
    if (!sheetStep) { el.sheet.hidden = true; el.sheet.innerHTML = ""; return; }
    el.sheet.hidden = false;
    el.sheet.innerHTML = "";
    if (sheetStep === 1) buildSheetStep1(); else buildSheetStep2();
  }

  /* ====================================================================
     Live stats overlay (plan §D, mirrors MatchStatsView.swift +
     MatchStatsSummary.swift via window.DeuceMateTracking.matchStatsSummary).
     ==================================================================== */

  // Mirrors ScoreViewModel's statsTrackingEnabled: folds the setup toggle
  // together with the format's disablesPointTracking flag, since the setup
  // toggle itself has no format-awareness — without this, Perpetual Points
  // would show the misleading "No tracked points yet." instead of "tracking
  // was off for this match."
  function statsTrackingEnabled() {
    return !!state && trackingEnabled && !state.cfg.disablesPointTracking;
  }
  function canOpenStats() {
    return !!state && !sheetStep;
  }
  function openStats() {
    if (!canOpenStats()) return;
    statsOpen = true;
    statsSetFilter = null;
    render();
  }
  function closeStats() {
    statsOpen = false;
    render();
  }
  function toggleStatsButton() {
    if (statsOpen) { closeStats(); return; }
    openStats();
  }
  function toggleStatsGesture() {
    if (statsOpen) { closeStats(); return; }
    if (!statsTrackingEnabled()) return;
    openStats();
  }

  function statsFilteredPoints() {
    if (statsSetFilter === null) return stats;
    return stats.filter(function (s) { return s.setIndex === statsSetFilter; });
  }

  function buildStatsSetFilter() {
    if (!el.statsSetFilter) return;
    el.statsSetFilter.innerHTML = "";
    var count = state.sets.length;
    el.statsSetFilter.hidden = count <= 1;
    if (count <= 1) return;
    // Defensive clamp: statsSetFilter can only reference an out-of-range set
    // if state.sets shrank while the overlay was open, which can't currently
    // happen (scoring/undo are blocked while statsOpen) — kept for safety.
    if (statsSetFilter !== null && statsSetFilter >= count) statsSetFilter = null;
    var options = [null];
    for (var i = 0; i < count; i++) options.push(i);
    options.forEach(function (i) {
      var btn = document.createElement("button");
      btn.type = "button";
      btn.className = "stats-setbtn";
      var isActive = statsSetFilter === i;
      btn.setAttribute("aria-pressed", isActive ? "true" : "false");
      btn.textContent = i === null ? "All" : (isDecidingSuperTiebreak(state.cfg, i) ? "TB" : "S" + (i + 1));
      btn.addEventListener("click", function () { statsSetFilter = i; render(); });
      el.statsSetFilter.appendChild(btn);
    });
  }

  function statsDivider() {
    var d = document.createElement("div");
    d.className = "stats-divider";
    return d;
  }
  function statsSectionEl(title) {
    var sec = document.createElement("div");
    sec.className = "stats-section";
    if (title) {
      var h = document.createElement("div");
      h.className = "stats-section-title";
      h.textContent = title;
      sec.appendChild(h);
    }
    return sec;
  }
  function statsEmptyEl(text) {
    var div = document.createElement("div");
    div.className = "stats-empty";
    div.textContent = text;
    return div;
  }
  function statsSmallNote(text) {
    var p = document.createElement("div");
    p.className = "stats-note";
    p.textContent = text;
    return p;
  }

  // Percent rows (Serve/Return/Break Points/Pressure/Rally/Score States/
  // Aggression Index/Own Errors %) and raw-count rows (Winners/UE/FE/DF)
  // share the same centre-split-bar DOM shape; only the value text and the
  // fill fractions differ.
  function comparisonRowEl(label, meText, meSub, meFrac, oppText, oppSub, oppFrac) {
    var row = document.createElement("div");
    row.className = "cmp-row";
    var lab = document.createElement("div");
    lab.className = "cmp-label";
    lab.textContent = label;
    row.appendChild(lab);

    var body = document.createElement("div");
    body.className = "cmp-body";
    var mev = document.createElement("span");
    mev.className = "cmp-val mev";
    mev.textContent = meText;
    var bar = document.createElement("div");
    bar.className = "splitbar";
    var meHalf = document.createElement("div");
    meHalf.className = "cmp-half me";
    var meFill = document.createElement("div");
    meFill.className = "fill";
    meFill.style.width = Math.round(meFrac * 100) + "%";
    meHalf.appendChild(meFill);
    var sep = document.createElement("div");
    sep.className = "cmp-sep";
    var oppHalf = document.createElement("div");
    oppHalf.className = "cmp-half opp";
    var oppFill = document.createElement("div");
    oppFill.className = "fill";
    oppFill.style.width = Math.round(oppFrac * 100) + "%";
    oppHalf.appendChild(oppFill);
    bar.appendChild(meHalf); bar.appendChild(sep); bar.appendChild(oppHalf);
    var oppv = document.createElement("span");
    oppv.className = "cmp-val oppv";
    oppv.textContent = oppText;
    body.appendChild(mev); body.appendChild(bar); body.appendChild(oppv);
    row.appendChild(body);

    if (meSub || oppSub) {
      var sub = document.createElement("div");
      sub.className = "cmp-subrow";
      var meSubEl = document.createElement("span");
      meSubEl.textContent = meSub || "";
      var oppSubEl = document.createElement("span");
      oppSubEl.textContent = oppSub || "";
      sub.appendChild(meSubEl); sub.appendChild(oppSubEl);
      row.appendChild(sub);
    }
    return row;
  }

  function comparisonRow(label, meNum, meDen, oppNum, oppDen) {
    var T = window.DeuceMateTracking;
    var m = T.formatPercentRow(meNum, meDen), o = T.formatPercentRow(oppNum, oppDen);
    return comparisonRowEl(label, m.text, m.sub, m.frac, o.text, o.sub, o.frac);
  }
  function countComparisonRow(label, meCount, oppCount) {
    var fr = window.DeuceMateTracking.countComparisonFracs(meCount, oppCount);
    return comparisonRowEl(label, String(meCount), null, fr.meFrac, String(oppCount), null, fr.oppFrac);
  }
  function ratioRowEl(caption, winners, unforcedErrors) {
    var div = document.createElement("div");
    div.className = "stats-ratio";
    var val = document.createElement("div");
    val.className = "val";
    val.textContent = window.DeuceMateTracking.winToUnforcedRatioText(winners, unforcedErrors);
    var cap = document.createElement("div");
    cap.className = "cap";
    cap.textContent = caption;
    div.appendChild(val); div.appendChild(cap);
    return div;
  }

  function pointsWonSection(me) {
    var sec = statsSectionEl(null);
    var total = me.totalPoints, meWon = me.pointsWon, oppWon = total - meWon;
    var meFrac = total > 0 ? meWon / total : 0;

    var heads = document.createElement("div");
    heads.className = "pw-heads";
    var meSide = document.createElement("span"); meSide.className = "pw-side"; meSide.textContent = "Me";
    var title = document.createElement("span"); title.className = "pw-title"; title.textContent = "Points Won";
    var oppSide = document.createElement("span"); oppSide.className = "pw-side"; oppSide.textContent = "Opp";
    heads.appendChild(meSide); heads.appendChild(title); heads.appendChild(oppSide);

    var bar = document.createElement("div");
    bar.className = "pw-bar";
    var meSeg = document.createElement("div"); meSeg.className = "pw-seg me"; meSeg.style.width = (meFrac * 100) + "%";
    var oppSeg = document.createElement("div"); oppSeg.className = "pw-seg opp"; oppSeg.style.width = ((1 - meFrac) * 100) + "%";
    bar.appendChild(meSeg); bar.appendChild(oppSeg);

    var foot = document.createElement("div");
    foot.className = "pw-foot";
    var meFoot = document.createElement("span"); meFoot.className = "pw-side"; meFoot.textContent = meWon + " pts";
    var totalFoot = document.createElement("span"); totalFoot.className = "pw-total"; totalFoot.textContent = total + " total";
    var oppFoot = document.createElement("span"); oppFoot.className = "pw-side"; oppFoot.textContent = oppWon + " pts";
    foot.appendChild(meFoot); foot.appendChild(totalFoot); foot.appendChild(oppFoot);

    sec.appendChild(heads); sec.appendChild(bar); sec.appendChild(foot);
    return sec;
  }

  function outcomeBreakdownSection(me) {
    var sec = statsSectionEl("Outcome Breakdown");
    if (me.totalPoints <= me.uncategorizedCount) {
      sec.appendChild(statsEmptyEl("Outcome tracking not collected for this match."));
      return sec;
    }
    sec.appendChild(ratioRowEl("Win:Unforced Err · aim for > 1.0", me.myWinners, me.myUnforcedErrors));
    sec.appendChild(countComparisonRow("Winners", me.myWinners, me.opponentWinners));
    sec.appendChild(countComparisonRow("Unforced Errors", me.myUnforcedErrors, me.opponentUnforcedErrors));
    sec.appendChild(countComparisonRow("Forced Errors", me.myForcedErrors, me.opponentForcedErrors));
    sec.appendChild(countComparisonRow("Double Faults", me.myDoubleFaults, me.opponentDoubleFaults));
    sec.appendChild(comparisonRow("Aggression Index (W ÷ (W + UE))",
      me.myWinners, me.myWinners + me.myUnforcedErrors,
      me.opponentWinners, me.opponentWinners + me.opponentUnforcedErrors));
    sec.appendChild(comparisonRow("Own Errors %",
      me.myDoubleFaults + me.myUnforcedErrors, me.lostPoints,
      me.opponentDoubleFaults + me.opponentUnforcedErrors, me.pointsWon));
    if (me.uncategorizedCount > 0) sec.appendChild(statsSmallNote("(" + me.uncategorizedCount + " uncategorized)"));
    return sec;
  }

  function percentSection(title, rows) {
    var sec = statsSectionEl(title);
    rows.forEach(function (r) { sec.appendChild(comparisonRow(r[0], r[1], r[2], r[3], r[4])); });
    return sec;
  }

  function buildStatsBody() {
    if (!el.statsBody) return;
    el.statsBody.innerHTML = "";

    if (!statsTrackingEnabled()) {
      el.statsBody.appendChild(statsEmptyEl("Point outcome tracking was off for this match."));
      return;
    }
    var filtered = statsFilteredPoints();
    if (!filtered.length) {
      el.statsBody.appendChild(statsEmptyEl("No tracked points yet."));
      return;
    }

    var T = window.DeuceMateTracking;
    var me = T.matchStatsSummary(filtered, "me");
    var opp = T.matchStatsSummary(filtered, "opponent");

    if (me.totalPoints > 0) el.statsBody.appendChild(pointsWonSection(me));
    el.statsBody.appendChild(outcomeBreakdownSection(me));

    el.statsBody.appendChild(statsDivider());
    el.statsBody.appendChild(percentSection("Serve", [
      ["1st Serve In", me.firstServeIn, me.firstServeTotal, opp.firstServeIn, opp.firstServeTotal],
      ["2nd Serve In", me.secondServeIn, me.secondServeTotal, opp.secondServeIn, opp.secondServeTotal],
      ["1st Serve Win", me.firstServeWins, me.firstServeIn, opp.firstServeWins, opp.firstServeIn],
      ["2nd Serve Win", me.secondServeWins, me.secondServeIn, opp.secondServeWins, opp.secondServeIn],
      ["DF Rate (2nd)", me.doubleFaults, me.secondServeTotal, opp.doubleFaults, opp.secondServeTotal]
    ]));

    el.statsBody.appendChild(statsDivider());
    el.statsBody.appendChild(percentSection("Return", [
      ["vs 1st Serve", me.returnWinsOnFirst, me.returnOppsOnFirst, opp.returnWinsOnFirst, opp.returnOppsOnFirst],
      ["vs 2nd Serve", me.returnWinsOnSecond, me.returnOppsOnSecond, opp.returnWinsOnSecond, opp.returnOppsOnSecond]
    ]));

    el.statsBody.appendChild(statsDivider());
    el.statsBody.appendChild(percentSection("Break Points", [
      ["BPs Won (Returner)", me.breakPointWins, me.breakPointOpps, opp.breakPointWins, opp.breakPointOpps],
      ["BPs Saved (Server)", me.breakPointsFaced - me.breakPointsLost, me.breakPointsFaced,
                              opp.breakPointsFaced - opp.breakPointsLost, opp.breakPointsFaced]
    ]));

    if (me.bigPointTotal > 0 && me.normalPointTotal > 0) {
      el.statsBody.appendChild(statsDivider());
      el.statsBody.appendChild(percentSection("Pressure vs Normal", [
        ["Big Points", me.bigPointWins, me.bigPointTotal, opp.bigPointWins, opp.bigPointTotal],
        ["Normal Points", me.normalPointWins, me.normalPointTotal, opp.normalPointWins, opp.normalPointTotal]
      ]));
    }

    if (me.rallyDepth.length) {
      el.statsBody.appendChild(statsDivider());
      el.statsBody.appendChild(percentSection("Rally Depth Won", me.rallyDepth.map(function (m, i) {
        var o = opp.rallyDepth[i];
        return ["@ " + T.ENDING_SHOT_LABELS[m.shot], m.wins, m.total, o.wins, o.total];
      })));
    }

    if (me.scoreStates.length) {
      el.statsBody.appendChild(statsDivider());
      el.statsBody.appendChild(percentSection("Score States", me.scoreStates.map(function (m, i) {
        var o = opp.scoreStates[i];
        return [m.label, m.wins, m.total, o.wins, o.total];
      })));
    }
  }

  function renderStats() {
    if (!el.stats) return;
    el.stats.hidden = !statsOpen;
    if (!statsOpen) return;
    if (el.statsTitle) el.statsTitle.textContent = isMatchComplete(state) ? "Match Stats" : "Live Stats";
    if (el.statsFormat) el.statsFormat.textContent = FORMAT_LABELS[state.format] + " · Singles";
    buildStatsSetFilter();
    buildStatsBody();
  }

  function applyEvents(events) {
    var winner = matchWinner(state);
    var matchEvt = events.filter(function (e) { return e.t === "matchWon"; })[0];
    if (matchEvt || (winner && isMatchComplete(state))) {
      var w = matchEvt ? matchEvt.winner : winner;
      var msg = w === "me" ? "You win! 🎾" : "Opponent wins";
      if (el.bannerText) el.bannerText.textContent = msg;
      if (el.banner) el.banner.hidden = false; else showToast(msg);
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
    if (!el.toast) return;
    if (!text) { el.toast.hidden = true; el.toast.textContent = ""; return; }
    el.toast.textContent = text;
    el.toast.hidden = false;
    toastTimer = setTimeout(function () { if (el.toast) el.toast.hidden = true; }, 1900);
  }

  function render() {
    // Guards the setup-card toggle, which can call render() before any
    // match has started (state is only set by startMatch()).
    if (!state) return;
    var cfg = state.cfg;

    // Server: a tennis ball on the serving row, a faint circle otherwise.
    // A yellow "2" badge overlays the ball while isOnSecondServe is set
    // (plan §A, mirrors ContentView.serverIndicator ~L470-479).
    setServerIcon(el.meServer, state.currentServer === "me", state.currentServer === "me" && isOnSecondServe);
    setServerIcon(el.oppServer, state.currentServer === "opponent", state.currentServer === "opponent" && isOnSecondServe);

    // Per-player score cells (completed sets neutral, current set highlighted).
    buildCells(el.meCells, state, "me");
    buildCells(el.oppCells, state, "opponent");

    // Compact current-game point badge — hidden for tiebreak-only formats and
    // once the match is complete, exactly like the watch.
    var showBadge = !isMatchComplete(state) && cfg.playRegularSets;
    if (el.mePts) el.mePts.hidden = !showBadge;
    if (el.oppPts) el.oppPts.hidden = !showBadge;
    if (showBadge) {
      if (el.mePts) el.mePts.textContent = watchPointLabel(state, "me");
      if (el.oppPts) el.oppPts.textContent = watchPointLabel(state, "opponent");
    }

    // Momentum strip (last 8 points, oldest first).
    if (el.momentum) {
      el.momentum.innerHTML = "";
      for (var i = 0; i < 8; i++) {
        var pip = document.createElement("span");
        pip.className = "w-pip";
        var idx = momentum.length - 8 + i;
        if (idx >= 0) pip.classList.add(momentum[idx] === "me" ? "me" : "opp");
        el.momentum.appendChild(pip);
      }
    }

    if (el.foot) el.foot.textContent = FORMAT_LABELS[state.format] + " · Singles";

    renderSheet();
    renderStats();

    // All scoring input is blocked while the categorisation sheet or the
    // stats overlay is open (plan §UI state machine) — "New match" is the
    // one exception (unguarded). The stats toggle itself stays enabled while
    // open so it can still close the overlay.
    var over = isMatchComplete(state);
    var blocked = !!sheetStep || statsOpen;
    if (el.undo) el.undo.disabled = !history.length || blocked;
    if (el.ptMe) el.ptMe.disabled = over || blocked;
    if (el.ptOpp) el.ptOpp.disabled = over || blocked;
    if (el.secondServe) {
      el.secondServe.disabled = !canToggleSecondServe();
      el.secondServe.classList.toggle("active", isOnSecondServe);
    }
    if (el.statsToggle) el.statsToggle.disabled = !canOpenStats();
  }

  function setServerIcon(node, isServer, showSecondBadge) {
    if (!node) return;
    node.innerHTML = "";
    if (isServer) {
      node.appendChild(document.createTextNode("🎾"));
      node.setAttribute("aria-label", showSecondBadge ? "Serving, second serve" : "Serving");
      node.removeAttribute("aria-hidden");
      node.classList.remove("idle");
      if (showSecondBadge) {
        var badge = document.createElement("span");
        badge.className = "w-2nd-badge";
        badge.textContent = "2";
        badge.setAttribute("aria-hidden", "true");
        node.appendChild(badge);
      }
    } else {
      node.setAttribute("aria-hidden", "true");
      node.removeAttribute("aria-label");
      node.classList.add("idle");
    }
  }

  function buildCells(container, st, player) {
    if (!container) return;
    container.innerHTML = "";
    var cfg = st.cfg, tbOnly = !cfg.playRegularSets, n = st.sets.length;
    visibleSetIndices(st).forEach(function (i) {
      var set = st.sets[i];
      var isActive = i === n - 1;
      var games = player === "me" ? set.gamesMe : set.gamesOpponent;
      var tbPts = player === "me" ? set.tieBreakPointsMe : set.tieBreakPointsOpponent;
      // Standard's deciding super-tiebreak shows its POINTS (e.g. 10), not games.
      var isSuperTB = !tbOnly && set.isTieBreak && n === 3 && i === 2;
      var cell = document.createElement("span");
      cell.className = "w-cell" + (isActive ? " active" : "");
      if (tbOnly || isSuperTB) {
        cell.textContent = String(tbPts);
      } else {
        cell.textContent = String(games);
        // A finished regular tiebreak set shows its points as a superscript (e.g. 7⁴).
        if (set.isTieBreak && tbPts > 0 && !isActive) {
          var sup = document.createElement("sup");
          sup.textContent = String(tbPts);
          cell.appendChild(sup);
        }
      }
      container.appendChild(cell);
    });
  }

  // Debug handle for console spot-checks (plan's Owner Verification
  // Playbook): neither DeuceMateScoring nor DeuceMateTracking expose a live
  // instance's data, only pure functions — this closes that gap.
  root.__deuceMateDebug = { state: function () { return state; }, stats: function () { return stats; } };

  if (compact) { if (el.setup) el.setup.hidden = true; startMatch(); }
  } /* end initWatchDemo */

  var demos = document.querySelectorAll("#watch-demo, .watch-demo");
  for (var di = 0; di < demos.length; di++) initWatchDemo(demos[di]);
})();
