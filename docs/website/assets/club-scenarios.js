/* Opening point sequences shared by the club practice page and Watch demo. */
(function () {
  "use strict";

  function alternatingHolds(count) {
    var out = [];
    for (var g = 0; g < count; g++) {
      var side = g % 2 === 0 ? "me" : "opponent";
      out.push(side, side, side, side);
    }
    return out;
  }
  function alternatingPoints(count) {
    var out = [];
    for (var i = 0; i < count; i++) out.push(i % 2 === 0 ? "me" : "opponent");
    return out;
  }
  var FAST4_TIEBREAK_ENTRY = alternatingHolds(6);
  var SHORTSET_TIEBREAK_ENTRY = alternatingHolds(8);
  var formats = {
    fast4: {
      title: "FAST4 Simulator",
      defaultScene: "deuce",
      rules: "Win four games. At 3–3, play a tiebreak to five points. At 40–40, one point wins the game.",
      scenes: {
        start: {
          label: "Start at 0–0",
          points: [],
          caption: "FAST4: First to 4 games wins. No-Ad deciding point at 40–40; 5-point tiebreak at 3–3."
        },
        deuce: {
          label: "40–40 no-ad",
          points: ["me", "opponent", "me", "opponent", "me", "opponent"],
          caption: "40–40 (No-Ad deuce): Sudden-death point — the receiver chooses the side and the next point wins the game."
        },
        tiebreak: {
          label: "3–3 in games",
          points: FAST4_TIEBREAK_ENTRY,
          caption: "3–3 in games: First to 5 points (sudden death at 4–4). Server rotates after point 1, then every 2 points."
        },
        decider: {
          label: "4–4 in tiebreak",
          points: FAST4_TIEBREAK_ENTRY.concat(["me", "opponent", "me", "opponent", "me", "opponent", "me", "opponent"]),
          caption: "At 4–4 in the tiebreak, either side can win the match on the next point. The set finishes 4–3."
        }
      }
    },
    shortSets: {
      title: "Short Sets Simulator",
      defaultScene: "deuce",
      rules: "Win four games by two. At 4–4, play a tiebreak to seven, win by two. At 40–40, one point wins the game.",
      scenes: {
        start: {
          label: "Start at 0–0",
          points: [],
          caption: "Short Sets: First to 4 games by 2 (up to 5–3). No-Ad deciding point at 40–40; 7-point tiebreak at 4–4."
        },
        deuce: {
          label: "40–40 no-ad",
          points: ["me", "opponent", "me", "opponent", "me", "opponent"],
          caption: "40–40 (No-Ad deuce): Sudden-death point — the receiver chooses the side and the next point wins the game."
        },
        tiebreak: {
          label: "4–4 in games",
          points: SHORTSET_TIEBREAK_ENTRY,
          caption: "4–4 in games: At 4–4 (4–3 plays on to 5–3 or 4–4), play a 7-point tiebreak (win by 2). Server rotates after point 1, then every 2 points."
        },
        decider: {
          label: "6–5 match point",
          points: SHORTSET_TIEBREAK_ENTRY.concat(["me", "opponent", "me", "opponent", "me", "opponent", "me", "opponent", "me", "opponent", "me"]),
          caption: "Win the next point to take the tiebreak 7–5 and the set 5–4. If it goes to 6–6, play on until one side leads by two."
        }
      }
    },
    perpetualSuperTiebreak: {
      title: "Perpetual Tiebreak Simulator",
      defaultScene: "start",
      rules: "Count points until the round ends. The first server serves once, then servers take two points each. Change ends every six points.",
      scenes: {
        start: {
          label: "Start at 0–0",
          points: [],
          caption: "Perpetual Tiebreak: Continuous tiebreak scoring until your round or timer ends. First server serves 1 point from Deuce; then servers rotate every 2 points (Ad first, then Deuce)."
        },
        deuce: {
          label: "1–0 serve rotation",
          points: ["me"],
          caption: "1–0 (After Point 1): Balls change after the opening point — the next server now serves 2 points, starting from the Ad (left) court, then the Deuce (right) court."
        },
        tiebreak: {
          label: "3–2 change ends next",
          points: alternatingPoints(5),
          caption: "3–2 (6th Point Next): After every 6 total points, the watch prompts players and balls to change ends. Play one point to see the changeover."
        },
        decider: {
          label: "10–10 plays on",
          points: alternatingPoints(20),
          caption: "10–10 (Continuous): Unlike a single 10-point tiebreak, Perpetual Tiebreak keeps running past 10 with 2-point serve rotation and 6-point end switches until you end the match."
        }
      }
    }
  };
  var sceneOrder = ["start", "deuce", "tiebreak", "decider"];

  function formatFromQuery(params) {
    if (params.has("fast4")) return "fast4";
    if (params.has("shortset") || params.has("shortsets")) return "shortSets";
    if (params.has("perpetual") || params.has("perpetualtiebreak") || params.has("tiebreak")) return "perpetualSuperTiebreak";
    var name = (params.get("format") || "").toLowerCase();
    if (name === "fast4") return "fast4";
    if (name === "shortset" || name === "shortsets") return "shortSets";
    if (["perpetual", "perpetualtiebreak", "perpetualsupertiebreak"].includes(name)) return "perpetualSuperTiebreak";
    return null;
  }

  window.DeuceMateClubScenarios = { formats: formats, sceneOrder: sceneOrder, formatFromQuery: formatFromQuery };
})();
