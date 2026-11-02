#!/usr/bin/env node
/* Pure model QA for browser ports of Core RecCoachInsights and PulseCoachInsights. */
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const root = path.resolve(__dirname, "..");
const jsPath = path.join(root, "docs/website/assets/phone-demo-coaching.js");
const core = path.join(root, "DeuceMate/Packages/DeuceMateCore/Sources/DeuceMateCore/Stats");
const window = {};
vm.runInNewContext(fs.readFileSync(jsPath, "utf8"), { window, Date, Number, Math, Array, Object, String }, { filename: jsPath });
const coaching = window.DeuceMatePhoneCoaching;
assert.ok(coaching, "coaching module should expose pure functions");

const focal = "me", other = "opponent";
function point(index, options = {}) {
  return {
    timestamp: options.timestamp == null ? 1_700_000_000_000 + index * 30_000 : options.timestamp,
    setIndex: options.setIndex == null ? 0 : options.setIndex,
    server: options.server || focal,
    winner: options.winner || focal,
    outcome: options.outcome || "winner",
    isSecondServe: !!options.isSecondServe,
    isBreakPoint: !!options.isBreakPoint,
    endingShot: options.endingShot == null ? null : options.endingShot,
    gameScoreAtStart: options.gameScoreAtStart || null,
    heartRateBPM: options.heartRateBPM == null ? null : options.heartRateBPM
  };
}
function match(points, setElapsed = {}) { return { stats: points, setElapsed: setElapsed }; }
function rec(points, options = {}) {
  const record = options.record || match(points, options.setElapsed);
  const setFilter = options.setFilter == null ? "all" : options.setFilter;
  const scoped = options.scopedPoints || (setFilter === "all" ? points : points.filter(p => p.setIndex === Number(setFilter)));
  return coaching.rec(record, points, scoped, setFilter, options.focal || focal);
}

// Gating: uncategorized records count toward the archive but never satisfy the
// Core categorized-point gate; Pulse requires actual positive HR samples.
const untrackedInsights = rec(Array.from({ length: 40 }, (_, i) => point(i, { outcome: "uncategorized" })));
const healthFreeInsights = coaching.pulse({}, Array.from({ length: 20 }, (_, i) => point(i)), 190);
assert.ok(Array.isArray(untrackedInsights) && Array.isArray(healthFreeInsights), 'coaching results must be arrays');
assert.deepEqual(Array.from(untrackedInsights), []);
assert.deepEqual(Array.from(healthFreeInsights), []);

// Rule 1: 20/30 losses are self-inflicted; also verify reader-relative framing.
const selfLosses = [];
for (let i = 0; i < 20; i++) selfLosses.push(point(i, { winner: other, outcome: "unforcedError" }));
for (let i = 20; i < 30; i++) selfLosses.push(point(i, { winner: other, outcome: "forcedError" }));
for (let i = 30; i < 40; i++) selfLosses.push(point(i));
assert.ok(rec(selfLosses).some(line => line.includes("67% of classified losses") && line.includes("20/30")));
const opponentView = selfLosses.map((p, i) => point(i, {
  winner: p.winner === focal ? other : focal,
  outcome: p.outcome,
  server: p.server === focal ? other : focal
}));
assert.ok(rec(opponentView, { focal: other }).some(line => line.includes("67% of classified losses")),
  "focal opponent should read the same rule from their own perspective");

// Rule 2: adjacent-set UE drift and set scoping retarget the transition.
const drift = [];
for (let i = 0; i < 2; i++) drift.push(point(i, { setIndex: 0, winner: other, outcome: "unforcedError" }));
for (let i = 2; i < 15; i++) drift.push(point(i, { setIndex: 0, winner: other, outcome: "forcedError" }));
for (let i = 15; i < 20; i++) drift.push(point(i, { setIndex: 0 }));
for (let i = 20; i < 27; i++) drift.push(point(i, { setIndex: 1, winner: other, outcome: "unforcedError" }));
for (let i = 27; i < 35; i++) drift.push(point(i, { setIndex: 1, winner: other, outcome: "forcedError" }));
for (let i = 35; i < 40; i++) drift.push(point(i, { setIndex: 1 }));
const driftLine = rec(drift).find(line => line.includes("Unforced errors rose"));
assert.ok(driftLine && driftLine.includes("13% in set 1 to 47% in set 2"));
assert.ok(rec(drift, { setFilter: "0" }).every(line => !line.includes("Unforced errors rose")), "first-set view has no earlier set for cross-set rules");
assert.ok(rec(drift.slice(0, 20).concat(drift.slice(20)), { setFilter: "1" }).some(line => line.includes("set 1 to 47% in set 2")),
  "set 2 view should compare set 1 → set 2 while single-set rules stay scoped");

// Rule 3: four focal service-game runs and three DFs hit the per-game threshold.
const dfs = [];
for (let game = 0; game < 4; game++) {
  dfs.push(point(dfs.length, { server: focal, winner: other, outcome: game < 3 ? "doubleFault" : "winner" }));
  dfs.push(point(dfs.length, { server: other, winner: focal }));
}
while (dfs.length < 20) dfs.push(point(dfs.length, { server: other }));
assert.ok(rec(dfs).some(line => line.includes("3 double faults in 4 service games")));

// Break-point double faults report the actual event, even below the frequency gate.
assert.ok(rec(dfs).includes("3 double faults in 4 service games — practise a repeatable second-serve routine."));
assert.ok(rec(dfs).every(line => !line.includes("worst time") && !line.includes("break point")));
for (const reader of [focal, other]) {
  const opponent = reader === focal ? other : focal;
  const single = Array.from({ length: 19 }, (_, i) => point(i, { server: opponent, winner: reader }));
  single.push(point(19, {
    server: reader, winner: opponent, outcome: "doubleFault", isSecondServe: true, isBreakPoint: true,
    gameScoreAtStart: { server: 1, returner: 3, isTiebreak: false }
  }));
  assert.deepEqual(Array.from(rec(single, { focal: reader })), [
    "1 double fault on break point — practise your second-serve routine under pressure."
  ]);
  assert.ok(rec(single, { focal: opponent }).every(line => !line.includes("double fault")));
  assert.equal(rec(single.slice(1), { focal: reader }).length, 0, "minimum data gate still applies");
}
const breakFaults = Array.from({ length: 18 }, (_, i) => point(i));
breakFaults.push(point(18, { winner: other, outcome: "doubleFault", isSecondServe: true }));
breakFaults.push(point(19, { winner: other, outcome: "doubleFault", isSecondServe: true, isBreakPoint: true }));
assert.deepEqual(Array.from(rec(breakFaults)), [
  "2 double faults, including 1 on break point — practise your second-serve routine under pressure."
]);
breakFaults.push(point(20, { winner: other, outcome: "doubleFault", isSecondServe: true, isBreakPoint: true }));
assert.deepEqual(Array.from(rec(breakFaults)), [
  "3 double faults, including 2 on break points — practise your second-serve routine under pressure."
]);
const laterSet = Array.from({ length: 20 }, (_, i) => point(21 + i, { setIndex: 1 }));
assert.equal(rec(breakFaults.concat(laterSet), { setFilter: "1" }).length, 0);
assert.deepEqual(Array.from(rec(breakFaults.concat(laterSet), { setFilter: "0" })), Array.from(rec(breakFaults)));
const ordinaryPoints = Array.from({ length: 19 }, (_, i) => point(i));
for (const options of [
  {},
  { gameScoreAtStart: { server: 3, returner: 3, isTiebreak: false } },
  { isBreakPoint: true, gameScoreAtStart: { server: 5, returner: 6, isTiebreak: true } },
  { isBreakPoint: true, winner: focal }
]) {
  const df = point(19, { winner: other, outcome: "doubleFault", isSecondServe: true, ...options });
  assert.equal(rec(ordinaryPoints.concat(df)).length, 0, "do not infer a service break without recorded evidence");
}

// Tiebreak double faults must not be attributed to regular service games.
function withTiebreakFaults(regularFaults) {
  const points = [];
  for (let game = 0; game < 12; game++) {
    const server = game % 2 === 0 ? focal : other, hasFault = server === focal && game / 2 < regularFaults;
    let serverScore = 0, returnerScore = 0;
    for (let j = 0; j < (hasFault ? 5 : 4); j++) {
      const fault = hasFault && j === 0;
      points.push(point(points.length, {server, winner: fault ? other : server,
        isSecondServe: fault, outcome: fault ? "doubleFault" : "winner",
        gameScoreAtStart: {server: serverScore, returner: returnerScore, isTiebreak: false}}));
      if (fault) returnerScore++; else serverScore++;
    }
  }
  for (let j = 0; j < 3; j++) points.push(point(points.length, {winner: other, outcome: "doubleFault", isSecondServe: true,
    gameScoreAtStart: {server: 0, returner: j, isTiebreak: true}}));
  return points;
}
assert.ok(rec(withTiebreakFaults(0)).every(line => !line.includes("double faults in")));
assert.ok(rec(withTiebreakFaults(3)).includes("3 double faults in 6 service games — practise a repeatable second-serve routine."));

// Rule 4: normal-point win rate leads pressure-point rate by 100pp.
const pressure = [];
for (let i = 0; i < 15; i++) pressure.push(point(i, { gameScoreAtStart: { server: 0, returner: 0, isTiebreak: false } }));
for (let i = 15; i < 23; i++) pressure.push(point(i, { winner: other, isBreakPoint: true }));
assert.ok(rec(pressure).some(line => line.includes("Serving: 0% (0/8) points won under pressure vs 100% (15/15) otherwise")));

// Rule 5: Serve+1 advantage over long rallies; uncategorized points do not pad the gate.
const rallies = [];
for (let i = 0; i < 8; i++) rallies.push(point(i, { endingShot: "servePlusOne" }));
for (let i = 8; i < 16; i++) rallies.push(point(i, { winner: other, endingShot: "rally" }));
for (let i = 16; i < 20; i++) rallies.push(point(i, { endingShot: "serve" }));
assert.ok(rec(rallies).some(line => line.includes("100% (8/8) points ending at Serve+1 vs 0% (0/8) in the rally phase")));

// Rule 6: second-serve denominator excludes double faults; first serve remains 8+.
const secondServe = [];
for (let i = 0; i < 8; i++) secondServe.push(point(i));
for (let i = 8; i < 16; i++) secondServe.push(point(i, { winner: other, isSecondServe: true }));
for (let i = 16; i < 20; i++) secondServe.push(point(i, { server: other }));
secondServe.push(point(20, { winner: other, isSecondServe: true, outcome: "doubleFault" }));
const secondLine = rec(secondServe).find(line => line.includes("on first serve"));
assert.ok(secondLine && secondLine.includes("100% (8/8) on first serve vs 0% (0/8) on second serves in play"));

// Rule 7: return UE share uses points lost while returning, not all UE points.
const returnUE = [];
for (let i = 0; i < 10; i++) returnUE.push(point(i, { server: other, winner: other, outcome: "unforcedError", endingShot: "return" }));
for (let i = 10; i < 20; i++) returnUE.push(point(i));
assert.ok(rec(returnUE).some(line => line.includes("10/10 tracked return attempts")));

// Rule 8: 35-minute earlier set, ≥20 points per set, ≥15pp win-rate drop.
const duration = [];
for (let i = 0; i < 20; i++) duration.push(point(i, { setIndex: 0, winner: i < 16 ? focal : other }));
for (let i = 20; i < 40; i++) duration.push(point(i, { setIndex: 1, winner: i < 28 ? focal : other }));
assert.ok(rec(duration, { setElapsed: { 0: 2100, 1: 1500 } }).some(line => line.includes("After a 35-minute set 1") && line.includes("80% to 40%")));
assert.ok(rec(duration, { setElapsed: { 0: 1799, 1: 1500 } }).every(line => !line.includes("minute set")),
  "duration rule must wait until the earlier set reaches 30 minutes");

// Pulse rule 1: at least five points in two different HR zones, ≥15pp delta.
const zonePoints = [];
for (let i = 0; i < 6; i++) zonePoints.push(point(i, { heartRateBPM: 130 }));
for (let i = 6; i < 11; i++) zonePoints.push(point(i, { winner: other, heartRateBPM: 175 }));
assert.ok(coaching.pulse({}, zonePoints, 190).some(line => line === "You won 100% of points in Z2 but only 0% in Z5."));
assert.ok(coaching.pulse({}, zonePoints, 190, other).some(line => line === "You won 100% of points in Z5 but only 0% in Z2."),
  "Pulse Coach must honor focal-player framing");

// Pulse rule 2: strict-above-median HR losses on break points.
const breakPoints = [];
for (let i = 0; i < 8; i++) breakPoints.push(point(i, { heartRateBPM: 130 }));
[[130, focal], [132, focal], [170, other], [175, other], [178, other]].forEach(([bpm, winner], i) => {
  breakPoints.push(point(8 + i, { heartRateBPM: bpm, winner, isBreakPoint: true }));
});
assert.ok(coaching.pulse({}, breakPoints, 190).some(line => line === "You lost 2 of 2 break points after HR rose above 170 bpm."));

// Pulse rule 3: ≥20 samples, ≥15pp win-rate decline, and ≥10 bpm average rise.
const late = [];
for (let i = 0; i < 10; i++) late.push(point(i, { winner: focal, heartRateBPM: 120 }));
for (let i = 10; i < 20; i++) late.push(point(i, { winner: other, heartRateBPM: 160 }));
const lateLines = coaching.pulse({}, late, 190);
assert.ok(lateLines.some(line => line === "Win rate dropped from 100% to 0% as average HR climbed by 40 bpm."));
assert.ok(lateLines.length <= 3, "Pulse Coach output remains capped at three insights");

// A few high-risk thresholds are pinned against the Core source so the browser
// port cannot silently drift if a native rule is deliberately revised.
const recSource = fs.readFileSync(path.join(core, "RecCoachInsights.swift"), "utf8");
const pulseSource = fs.readFileSync(path.join(core, "PulseCoachInsights.swift"), "utf8");
for (const label of ["General errors", "set transition", "Double faults", "pressure", "rally phases", "second-serve effectiveness", "return errors", "First-serve consistency"]) {
  assert.ok(recSource.includes("// MARK:") && recSource.toLowerCase().includes(label.toLowerCase()), `Core should retain Rec Coach rule ${label}`);
}
for (const label of ["zone delta", "break-point HR", "late-match decline"]) {
  assert.ok(pulseSource.toLowerCase().includes(label.toLowerCase()), `Core should retain Pulse Coach rule ${label}`);
}
for (const threshold of ["cat.count >= 20", "cat.count >= 25", "lost.count >= 15", "firstLost.count >= 12", "secondLost.count >= 12", "regularFaults >= 3", "games >= 4", "big.count >= 8", "ordinary.count >= 15", "early.count >= 8", "later.count >= 8", "first.count >= 8", "second.count >= 8", "losses.count >= 10", "duration >= 1800", "serves.count >= 30", "inRate < 0.5"]) {
  assert.ok(recSource.includes(threshold), `Core Rec Coach threshold should remain explicit: ${threshold}`);
}
for (const threshold of ["hrPoints.count >= 10", "e.total >= 5", "bps.count >= 4", "above.count >= 2", "lossRate >= 0.6", "hrPoints.count >= 20", "secondAvgHR - firstAvgHR >= 10"]) {
  assert.ok(pulseSource.includes(threshold), `Core Pulse Coach threshold should remain explicit: ${threshold}`);
}

// Optional parity oracle generated by RecCoachRedesignTests with fictional data.
if (process.env.COACHING_PARITY_OUTPUT) {
  const fixtures = JSON.parse(fs.readFileSync(process.env.COACHING_PARITY_OUTPUT, "utf8"));
  fixtures.forEach(fixture => {
    const points = fixture.stats.map(p => ({ ...p, timestamp: (p.timestamp + 978307200) * 1000 }));
    const actual = rec(points, { focal: fixture.focal, setFilter: fixture.setFilter == null ? "all" : fixture.setFilter,
      record: { stats: points, matchType: fixture.matchType } });
    assert.deepEqual(Array.from(actual), fixture.expected, fixture.name + " / " + fixture.matchType + " / " + fixture.focal + " / " + fixture.setFilter);
  });
  process.stdout.write("Swift/browser coaching parity passed: " + fixtures.length + " scenarios.\n");
}
process.stdout.write("iPhone demo coaching model QA passed (ranked Rec Coach and 3 Pulse Coach rules).\n");
