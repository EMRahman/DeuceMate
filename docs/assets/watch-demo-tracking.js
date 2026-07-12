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

  if (typeof window !== "undefined") {
    window.DeuceMateTracking = {
      OUTCOME_LABELS: OUTCOME_LABELS,
      USER_SELECTABLE_OUTCOMES: USER_SELECTABLE_OUTCOMES,
      ENDING_SHOT_LABELS: ENDING_SHOT_LABELS,
      gameScoreSnapshot: gameScoreSnapshot,
      buildPendingPoint: buildPendingPoint,
      buildPointStat: buildPointStat,
      buildUncategorizedStat: buildUncategorizedStat,
      doubleFaultAvailable: doubleFaultAvailable,
      endingShotOptions: endingShotOptions
    };
  }
})();
