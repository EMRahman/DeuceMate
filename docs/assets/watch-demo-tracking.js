/* ==========================================================================
   DeuceMate — pure point-outcome tracking logic for the browser demo.
   Mirrors:
     Packages/DeuceMateCore/Sources/DeuceMateCore/Models/PointStat.swift
     DeuceMate Watch App/ScoreViewModel.swift
       (toggleSecondServe / selectOutcome / commitPointStat / autoRecordPointStat)
     DeuceMate Watch App/PointCategorySheet.swift (button availability + pill routing)
   Pure functions over plain objects only — no DOM here. The controller in
   watch-demo.js consumes this. Exposed on window.DeuceMateTracking (mirrors
   window.DeuceMateScoring) so the owner can spot-check from the console.
   Loaded before watch-demo.js in try.html.
   ========================================================================== */
(function () {
  "use strict";

  /* ---- PointOutcome (PointStat.swift L5-27). Declaration order is
     doubleFault/winner/forcedError/unforcedError/uncategorized, but the sheet
     renders buttons in `userSelectable` order below — keep that order. ---- */
  var OUTCOME_LABELS = {
    doubleFault: "Double Fault",
    winner: "Winner",
    forcedError: "Forced Error",
    unforcedError: "Unforced Error",
    uncategorized: "—"
  };
  var USER_SELECTABLE_OUTCOMES = ["doubleFault", "unforcedError", "forcedError", "winner"];

  /* ---- EndingShot (PointStat.swift L30-46). "serve" reads as "Ace" for a
     Winner and "Serve" for a Forced Error in the sheet UI — same key. ---- */
  var ENDING_SHOT_LABELS = { serve: "Serve", "return": "Return", servePlusOne: "S+1", rally: "Rally" };

  function other(p) { return p === "me" ? "opponent" : "me"; }

  /* ---- Game score snapshot, from the server's perspective (mirrors
     GameScoreSnapshot + ScoreViewModel.gameScoreSnapshotAtPointStart()).
     `prevState` is the pre-reducer state (before the point is applied). ---- */
  function gameScoreSnapshot(prevState) {
    var server = prevState.currentServer;
    if (!server) return null;
    var set = prevState.sets[prevState.sets.length - 1];
    if (set && set.isTieBreak) {
      var tbMe = set.tieBreakPointsMe, tbOpp = set.tieBreakPointsOpponent;
      return { server: server === "me" ? tbMe : tbOpp, returner: server === "me" ? tbOpp : tbMe, isTiebreak: true };
    }
    var pMe = prevState.currentPointsMe, pOpp = prevState.currentPointsOpponent;
    return { server: server === "me" ? pMe : pOpp, returner: server === "me" ? pOpp : pMe, isTiebreak: false };
  }

  /* ---- PendingPointInfo (PointStat.swift L63-96). `prevState` must be the
     pre-reducer snapshot — the watch captures serverBefore/wasSecondServe
     before calling updateScore() in winPoint/losePoint; the demo's undo
     snapshot (taken before pointWon()) is the equivalent. Requires
     window.DeuceMateScoring (loaded first in try.html) for isBreakPoint. ---- */
  function buildPendingPoint(prevState, winner, isSecondServe) {
    return {
      server: prevState.currentServer,
      winner: winner,
      setIndex: Math.max(prevState.sets.length - 1, 0),
      isSecondServe: !!isSecondServe,
      isBreakPoint: window.DeuceMateScoring.isBreakPoint(prevState),
      gameScoreAtStart: gameScoreSnapshot(prevState)
    };
  }

  /* ---- PointStat (PointStat.swift L100-131) — demo subset: no id/timestamp
     (not meaningful without persistence) and no heartRateBPM/stepsCumulative
     (no HealthKit in a browser). ---- */
  function buildPointStat(pending, outcome, endingShot) {
    return {
      setIndex: pending.setIndex,
      server: pending.server,
      winner: pending.winner,
      outcome: outcome,
      isSecondServe: pending.isSecondServe,
      isBreakPoint: pending.isBreakPoint,
      endingShot: endingShot || null,
      gameScoreAtStart: pending.gameScoreAtStart
    };
  }

  /* Mirrors autoRecordPointStat: silent, always uncategorized, no ending shot. */
  function buildUncategorizedStat(pending) {
    return buildPointStat(pending, "uncategorized", null);
  }

  /* ---- Step 1 button availability (PointCategorySheet ~L51-57): Double
     Fault only shows when the point was lost on a second serve. ---- */
  function doubleFaultAvailable(pending) {
    return !!pending.isSecondServe && pending.winner !== pending.server;
  }

  /* ---- Step 2 pill routing (PointCategorySheet ~L173-191 / plan §B table).
     `outcome` is winner/forcedError/unforcedError — doubleFault auto-locks to
     endingShot "serve" and never reaches step 2. Returns an array of
     EndingShot keys in display order. */
  function endingShotOptions(outcome, pending) {
    // Who played the ending shot: for winner/forcedError that's the point's
    // winner; for unforcedError it's the loser.
    var actor = outcome === "unforcedError" ? other(pending.winner) : pending.winner;
    var actorIsServer = actor === pending.server;
    if (!actorIsServer) return ["return", "rally"];
    switch (outcome) {
      case "winner": return ["serve", "servePlusOne", "rally"]; // "serve" displays as "Ace"
      case "forcedError": return ["serve", "servePlusOne", "rally"]; // displays as "Serve"
      case "unforcedError": return ["servePlusOne", "rally"]; // a serve UFE is a double fault
      default: return [];
    }
  }

  /* ---- EndingShot.allCases order (PointStat.swift), drives Rally Depth Won
     row iteration order. ---- */
  var ENDING_SHOT_ORDER = ["serve", "return", "servePlusOne", "rally"];

  /* ---- Live/Match stats (mirrors MatchStatsSummary.swift), computed once per
     focal player. `stats` is a plain array of PointStat-shaped records (the
     controller's `stats` array, optionally pre-filtered by setIndex for the
     stats view's set filter); `focal` is "me"|"opponent". Returns one flat
     object — no formatting, that's formatPercentRow/countComparisonFracs. ---- */
  function matchStatsSummary(stats, focal) {
    var opp = other(focal);
    var categorized = stats.filter(function (s) { return s.outcome !== "uncategorized"; });

    function count(arr, pred) { return arr.filter(pred).length; }

    var pointsWon = count(stats, function (s) { return s.winner === focal; });
    var lostPoints = count(stats, function (s) { return s.winner === opp; });

    var myWinners = count(categorized, function (s) { return s.winner === focal && s.outcome === "winner"; });
    var myUnforcedErrors = count(categorized, function (s) { return s.winner === opp && s.outcome === "unforcedError"; });
    var myForcedErrors = count(categorized, function (s) { return s.winner === opp && s.outcome === "forcedError"; });
    var myDoubleFaults = count(categorized, function (s) { return s.server === focal && s.outcome === "doubleFault"; });
    var opponentWinners = count(categorized, function (s) { return s.winner === opp && s.outcome === "winner"; });
    var opponentUnforcedErrors = count(categorized, function (s) { return s.winner === focal && s.outcome === "unforcedError"; });
    var opponentForcedErrors = count(categorized, function (s) { return s.winner === focal && s.outcome === "forcedError"; });
    var opponentDoubleFaults = count(categorized, function (s) { return s.server === opp && s.outcome === "doubleFault"; });

    var focalServes = stats.filter(function (s) { return s.server === focal; });
    var firstServeTotal = focalServes.length;
    var firstServeIn = count(focalServes, function (s) { return !s.isSecondServe; });
    var firstServeWins = count(focalServes, function (s) { return !s.isSecondServe && s.winner === focal; });
    var secondServeTotal = count(focalServes, function (s) { return s.isSecondServe; });
    var secondServeIn = count(focalServes, function (s) { return s.isSecondServe && s.outcome !== "doubleFault"; });
    var secondServeWins = count(focalServes, function (s) { return s.isSecondServe && s.winner === focal; });
    var doubleFaults = myDoubleFaults;

    var returnOppsOnFirst = count(stats, function (s) { return s.server === opp && !s.isSecondServe; });
    var returnWinsOnFirst = count(stats, function (s) { return s.server === opp && !s.isSecondServe && s.winner === focal; });
    var returnOppsOnSecond = count(stats, function (s) { return s.server === opp && s.isSecondServe; });
    var returnWinsOnSecond = count(stats, function (s) { return s.server === opp && s.isSecondServe && s.winner === focal; });

    var breakPointOpps = count(stats, function (s) { return s.server === opp && s.isBreakPoint; });
    var breakPointWins = count(stats, function (s) { return s.server === opp && s.isBreakPoint && s.winner === focal; });
    var breakPointsFaced = count(stats, function (s) { return s.server === focal && s.isBreakPoint; });
    var breakPointsLost = count(stats, function (s) { return s.server === focal && s.isBreakPoint && s.winner === opp; });

    function isBig(s) {
      if (s.isBreakPoint) return true;
      var g = s.gameScoreAtStart;
      if (!g) return false;
      return g.isTiebreak || (g.server >= 3 && g.returner >= 3);
    }
    var bigPts = stats.filter(isBig);
    var normalPts = stats.filter(function (s) { return !isBig(s); });
    var bigPointTotal = bigPts.length;
    var bigPointWins = count(bigPts, function (s) { return s.winner === focal; });
    var normalPointTotal = normalPts.length;
    var normalPointWins = count(normalPts, function (s) { return s.winner === focal; });

    var shotPts = stats.filter(function (s) { return s.endingShot != null; });
    var rallyDepth = [];
    ENDING_SHOT_ORDER.forEach(function (shot) {
      var pts = shotPts.filter(function (s) { return s.endingShot === shot; });
      if (!pts.length) return;
      rallyDepth.push({ shot: shot, total: pts.length, wins: count(pts, function (s) { return s.winner === focal; }) });
    });

    var scorePts = stats.filter(function (s) { return s.gameScoreAtStart != null; });
    var scoreStates = [];
    var thirtyAll = scorePts.filter(function (s) { var g = s.gameScoreAtStart; return !g.isTiebreak && g.server === 2 && g.returner === 2; });
    if (thirtyAll.length) scoreStates.push({ label: "At 30-All", total: thirtyAll.length, wins: count(thirtyAll, function (s) { return s.winner === focal; }) });
    var deuceAd = scorePts.filter(function (s) { var g = s.gameScoreAtStart; return !g.isTiebreak && g.server >= 3 && g.returner >= 3; });
    if (deuceAd.length) scoreStates.push({ label: "At Deuce/Ad", total: deuceAd.length, wins: count(deuceAd, function (s) { return s.winner === focal; }) });
    var tbPts = scorePts.filter(function (s) { return s.gameScoreAtStart.isTiebreak === true; });
    if (tbPts.length) scoreStates.push({ label: "In Tiebreak", total: tbPts.length, wins: count(tbPts, function (s) { return s.winner === focal; }) });

    return {
      pointsWon: pointsWon, totalPoints: stats.length, lostPoints: lostPoints,
      myWinners: myWinners, myUnforcedErrors: myUnforcedErrors, myForcedErrors: myForcedErrors, myDoubleFaults: myDoubleFaults,
      opponentWinners: opponentWinners, opponentUnforcedErrors: opponentUnforcedErrors,
      opponentForcedErrors: opponentForcedErrors, opponentDoubleFaults: opponentDoubleFaults,
      firstServeTotal: firstServeTotal, firstServeIn: firstServeIn, firstServeWins: firstServeWins,
      secondServeTotal: secondServeTotal, secondServeIn: secondServeIn, secondServeWins: secondServeWins, doubleFaults: doubleFaults,
      returnOppsOnFirst: returnOppsOnFirst, returnWinsOnFirst: returnWinsOnFirst,
      returnOppsOnSecond: returnOppsOnSecond, returnWinsOnSecond: returnWinsOnSecond,
      breakPointOpps: breakPointOpps, breakPointWins: breakPointWins,
      breakPointsFaced: breakPointsFaced, breakPointsLost: breakPointsLost,
      bigPointTotal: bigPointTotal, bigPointWins: bigPointWins,
      normalPointTotal: normalPointTotal, normalPointWins: normalPointWins,
      rallyDepth: rallyDepth, scoreStates: scoreStates,
      categorizedCount: categorized.length, uncategorizedCount: stats.length - categorized.length
    };
  }

  /* ---- Percent-row formatting (mirrors MatchStatsView.comparisonRow —
     rounds, unlike MatchStatsSummary.pct which truncates but is never read
     directly by the view). den===0 -&gt; no sub-label, "—" text. ---- */
  function formatPercentRow(num, den) {
    var frac = den > 0 ? num / den : 0;
    return {
      text: den > 0 ? Math.round(frac * 100) + "%" : "—",
      sub: den > 0 ? num + "/" + den : null,
      frac: frac
    };
  }

  /* ---- Raw-count row bar fractions (mirrors countComparisonRow — scaled
     against the larger of the two counts, or 1 if both are zero). ---- */
  function countComparisonFracs(meCount, oppCount) {
    var maxVal = Math.max(meCount, oppCount, 1);
    return { meFrac: meCount / maxVal, oppFrac: oppCount / maxVal };
  }

  /* ---- Win:Unforced Error ratio text (Outcome Breakdown's "Win:Unforced
     Err" row). ---- */
  function winToUnforcedRatioText(winners, unforcedErrors) {
    if (winners === 0 && unforcedErrors === 0) return "—";
    if (unforcedErrors === 0) return "∞ : 1";
    return (winners / unforcedErrors).toFixed(1) + " : 1";
  }

  if (typeof window !== "undefined") {
    window.DeuceMateTracking = {
      OUTCOME_LABELS: OUTCOME_LABELS,
      USER_SELECTABLE_OUTCOMES: USER_SELECTABLE_OUTCOMES,
      ENDING_SHOT_LABELS: ENDING_SHOT_LABELS,
      ENDING_SHOT_ORDER: ENDING_SHOT_ORDER,
      gameScoreSnapshot: gameScoreSnapshot,
      buildPendingPoint: buildPendingPoint,
      buildPointStat: buildPointStat,
      buildUncategorizedStat: buildUncategorizedStat,
      doubleFaultAvailable: doubleFaultAvailable,
      endingShotOptions: endingShotOptions,
      matchStatsSummary: matchStatsSummary,
      formatPercentRow: formatPercentRow,
      countComparisonFracs: countComparisonFracs,
      winToUnforcedRatioText: winToUnforcedRatioText
    };
  }
})();
