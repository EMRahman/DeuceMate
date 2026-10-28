#!/usr/bin/env node
/*
 * Pure-logic QA for the browser iPhone demo. This uses Node's vm with no
 * browser and no synthetic DOM: the watch view controller is skipped by
 * document.querySelectorAll(), while the real scoring and history fixture
 * functions are loaded. It does not prove visual/browser interaction.
 */
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const root = path.resolve(__dirname, "..");
const website = path.join(root, "docs/website/assets");
const context = vm.createContext({
  console,
  document: { querySelectorAll: () => [] },
  window: {}
});

function load(file) {
  vm.runInContext(fs.readFileSync(path.join(website, file), "utf8"), context, {
    filename: file,
    timeout: 10000
  });
}

load("watch-demo.js");
load("watch-demo-tracking.js");

const shell = {
  history: [],
  settings: { track: false },
  screens: {},
  api: {}
};
context.window.DeuceMateShell = shell;
load("watch-demo-history.js");
assert.equal(typeof shell.seedHistory, "function", "history module should expose its deterministic fixture generator");
shell.seedHistory();

const records = shell.history;
assert.ok(records.length >= 8, `expected deterministic starter archive, got ${records.length}`);
const formats = new Set(records.map(record => record.format));
for (const format of ["standard", "bestOf3FullFinalSet", "quick4Games", "superTiebreak", "perpetualPoints"]) {
  assert.ok(formats.has(format), `starter archive should include ${format}`);
}
assert.ok(records.some(record => record.matchType === "doubles"), "fixtures should include doubles");
assert.ok(records.some(record => record.endTime == null), "fixtures should include in-progress matches");
assert.ok(records.some(record => record.endTime != null), "fixtures should include completed matches");
assert.ok(records.some(record => record.endTime != null && record.iWon != null &&
  context.window.DeuceMateScoring.isMatchComplete(record.resume.state)),
"completed fixtures should include a scoring-engine terminal match state");
assert.ok(records.some(record => record.endTime == null &&
  context.window.DeuceMateScoring.completedSets(record.resume.state).length < record.resume.state.sets.length),
"in-progress fixtures should retain an unfinished set");
for (const format of ["standard", "bestOf3FullFinalSet", "quick4Games", "superTiebreak", "perpetualSuperTiebreak", "perpetualPoints"]) {
  assert.equal(context.window.DeuceMateScoring.freshState(format, "me").format, format,
    `scoring engine should generate fresh state for ${format}`);
}

for (const record of records) {
  assert.ok(Array.isArray(record.sets) && record.sets.length > 0, `${record.id} should have set state`);
  if (record.format !== "perpetualPoints") {
    assert.equal(record.pointsPlayed, record.stats.length,
      `${record.id}: tracked/uncategorized point stream should agree with the point count`);
  }
  if (record.trackingOn) {
    assert.equal(record.stats.length, record.pointsPlayed, `${record.id}: tracked point count mismatch`);
    assert.ok(record.stats.every(point => ["me", "opponent"].includes(point.server) && ["me", "opponent"].includes(point.winner)),
      `${record.id}: each tracked stat should identify its server and winner`);
  }
}

const doubles = records.find(record => record.matchType === "doubles");
assert.ok(doubles.resume.state.doublesServiceOrder.length === 4, "doubles fixture should preserve four-player server rotation");
assert.ok(doubles.resume.state.doublesServiceIndex >= 0 && doubles.resume.state.doublesServiceIndex < 4,
  "doubles fixture should preserve a valid server rotation index");
assert.ok(doubles.stats.length > 0, "tracked doubles fixture should retain point stats");

load("phone-demo-native-export.js");
load("phone-demo-coaching.js");
load("phone-demo-export.js");
load("phone-demo-reports.js");
const reports = context.window.DeuceMatePhoneReports;
assert.ok(reports, "report module should expose pure helpers");
for (const name of ["standaloneHTML", "reportText", "scoreTimeline"]) {
  assert.equal(typeof reports[name], "function", `report module should export ${name}`);
}

// Per-set report activity follows Core SetActivitySplit: sampled steps when
// every played set is covered, otherwise duration/point weights; calories use time.
const activityFixture = {
  sets: [{}, {}], setElapsed: {0: 60, 1: 180}, steps: 1000, kcal: 400,
  stats: [{setIndex: 0, timestamp: 1, stepsCumulative: 400}, {setIndex: 1, timestamp: 2, stepsCumulative: 1000}]
};
let activity = reports.activitySplit(activityFixture);
assert.equal(activity.steps[0], 400);
assert.equal(activity.steps[1], 600);
assert.equal(activity.calories[0], 100);
assert.equal(activity.calories[1], 300);
activity = reports.activitySplit({...activityFixture, stats: [{setIndex: 0, stepsCumulative: 400}, {setIndex: 1}]});
assert.equal(activity.steps[0], 250, "missing samples in a played set must use duration weights for both sets");
assert.equal(activity.steps[1], 750);
activity = reports.activitySplit({...activityFixture, setElapsed: {}, stats: [{setIndex: 0}, {setIndex: 0}, {setIndex: 1}]});
assert.equal(activity.steps[0], 667, "point counts are the fallback when set durations are missing");
assert.equal(activity.steps[1], 333);
assert.equal(Object.keys(reports.activitySplit({...activityFixture, steps: 0, kcal: 0}).steps).length, 0, "missing activity stays missing");

const completed = records.find(record => record.endTime != null && record.stats.length > 0);
assert.ok(completed, "fixture archive needs a completed tracked match");
const perPointHealth = {stats: [{heartRateBPM: 130, stepsCumulative: 10}]};
assert.deepEqual(Array.from(reports.exportFields(perPointHealth, "me", false)), ["heart rate", "heart-rate zones", "steps"], "recorder summaries disclose their health analysis");
assert.deepEqual(Array.from(reports.exportFields(perPointHealth, "opponent", false)), [], "opponent summaries omit recorder-only per-point health");
assert.deepEqual(Array.from(reports.exportFields(perPointHealth, "opponent", true)), ["heart rate", "steps"], "opponent raw-point and web exports disclose the recorder's measurements");
assert.deepEqual(Array.from(reports.exportFields({...perPointHealth, steps: 300, kcal: 20, distance: 50}, "opponent", false)), ["steps", "calories", "distance"], "match activity totals remain present in an opponent summary");
assert.deepEqual(Array.from(reports.exportFields({stats: [], steps: 0, kcal: 0, distance: 0}, "me", true)), [], "health-free exports skip disclosure");
const htmlMe = reports.standaloneHTML(completed, completed.stats, "me");
const htmlOpponent = reports.standaloneHTML(completed, completed.stats, "opponent");
assert.notEqual(htmlMe, htmlOpponent, "perspective exports should reframe the match data");
assert.match(htmlMe, /My Perspective/);
assert.match(htmlOpponent, /Opponent’s Perspective/);
const webModel = reports.exportModel(completed, completed.stats, "me");
assert.equal(webModel.filters.length, completed.sets.length + 1, "native set segments include All and one per set");
assert.deepEqual(Array.from(webModel.filters, f => f.key), ["all", ...completed.sets.map((_, i) => `set-${i}`)]);
assert.ok(htmlMe.includes(context.window.DeuceMateNativeExport.css), "download embeds the exact native viewer stylesheet");
assert.match(htmlMe, /function setFilterToggle\(/, "native viewer includes segmented set controls");
assert.match(htmlMe, /function tabToggle\(/, "native viewer includes Stats and Points segments");

const textMe = reports.reportText(completed, completed.stats, "me");
const textOpponent = reports.reportText(completed, completed.stats, "opponent");
assert.notEqual(textMe, textOpponent, "text exports should use the selected reader perspective");
assert.match(textMe, /## Raw Point Data/);
for (const focal of ["me", "opponent"]) {
  const prompt = reports.reportText(completed, completed.stats, focal, "ai", "3.5–4.5");
  const rows = prompt.split("\n").filter(line => /^\| \d+ \|/.test(line));
  assert.equal(rows.length, completed.stats.length, "AI prompt includes every saved point exactly once");
  assert.ok(rows.at(-1).startsWith(`| ${completed.stats.length} |`), "the final rally survives prompt generation");
  assert.match(prompt, /Biggest Weakness/); assert.match(prompt, /One Practice Drill/); assert.match(prompt, /NTRP 3.5–4.5/);
  assert.match(prompt, /## Serve Performance/); assert.match(prompt, /## Set-by-Set Scores/);
  assert.equal(prompt.includes("## Heart Rate Analysis"), focal === "me" && completed.stats.some(p => p.heartRateBPM != null), "recorder HR zones never become opponent physiology");
  assert.equal(reports.exportModel(completed, completed.stats, focal).aiCoach.mePrompt, reports.reportText(completed, completed.stats, focal, "ai"), "web and in-app prompt builders use the same complete data");
}

const timelineMe = reports.scoreTimeline(completed, completed.stats, "me");
assert.ok(Array.isArray(timelineMe), "score timeline should return the full point sequence");
assert.equal(timelineMe.length, completed.stats.length, "full tracked history should preserve terminal points");

// MatchDetailView titles depend on format and collected outcomes, not simply
// whether a points array exists. Uncategorized histories are score-only.
for (const [format, title] of [["superTiebreak", "Super Tiebreak"], ["perpetualSuperTiebreak", "Perpetual Tiebreak"], ["quick4Games", "Quick 4 Games"], ["perpetualPoints", "Perpetual Points"]]) {
  assert.equal(reports.detailTitle({...completed, format}), title);
}
assert.equal(reports.detailTitle({...completed, format: "standard", stats: []}), "Score Only Match");
assert.equal(reports.detailTitle({...completed, format: "bestOf3FullFinalSet", stats: [{outcome: "uncategorized"}]}), "Score Only Match");
assert.equal(reports.detailTitle({...completed, format: "standard", stats: [{outcome: "winner"}]}), "Match Stats");
assert.match(reports.detailTitle({...completed, endTime: null}), /\d/, "in-progress title is its start date");

// Native scatter symbols encode categories independently of colour. These
// pin PointsGraphView's outcome / serving / ending-shot symbol mappings.
for (const [family, categories] of Object.entries({
  outcome: {winner: "circle", doubleFault: "square", unforcedError: "cross", forcedError: "triangle"},
  serving: {firstServe: "circle", secondServe: "asterisk", doubleFault: "square", ace: "pentagon", serveForcedError: "triangle"},
  shot: {serve: "pentagon", return: "asterisk", servePlusOne: "plus", rally: "triangle"}
})) for (const [category, expected] of Object.entries(categories)) {
  const symbol = reports.graphSymbol(family, category, 4);
  assert.equal(symbol.shape, expected, `${family} ${category} must use its native symbol`);
  assert.ok(["circle", "rect", "path", "polygon"].includes(symbol.tag));
  assert.ok(Object.keys(symbol.attrs).length > 0, "a symbol must include standalone SVG geometry");
}
assert.match(htmlMe, /function symbol\(/, "offline graph embeds the native viewer's symbol renderer");

const selectionIndex = completed.stats.findIndex(point => point.setIndex === 1);
assert.ok(selectionIndex > 0, "fixture should cover the second set inspector");
const selection = reports.graphSelection(completed, completed.stats, selectionIndex, timelineMe);
assert.equal(selection.set, 2);
assert.equal(selection.point, 1, "inspector point numbers reset per set");
assert.equal(selection.me + selection.opponent, selectionIndex + 1, "inspector totals include the selected rally");
assert.equal(selection.matchAfter, timelineMe[selectionIndex].matchAfter);
assert.equal(selection.gameAfter, timelineMe[selectionIndex].gameAfter);
const suffixInspector = reports.graphSelection({...completed, sets: [{}]}, [{setIndex: 0, server: "me", winner: "me", gameScoreAtStart: {server: 3, returner: 0, isTiebreak: false}}], 0, null);
assert.equal(suffixInspector.gameAfter, "0–0", "a game-winning suffix rally resets game points through the reducer");
assert.equal(suffixInspector.matchAfter, null, "a known suffix game never invents an unknown games offset");
const terminalTB = reports.graphSelection({...completed, sets: [{}]}, [{setIndex: 0, server: "opponent", winner: "me", gameScoreAtStart: {server: 8, returner: 9, isTiebreak: true}}], 0, null);
assert.equal(terminalTB.gameAfter, "TB 10–8", "terminal tiebreak points stay visible and recorder-oriented");
const sparseSteps = [{setIndex: 0, winner: "me", stepsCumulative: 500}, {setIndex: 0, winner: "opponent"}, {setIndex: 0, winner: "me", stepsCumulative: 580}];
assert.deepEqual(Array.from(reports.graphSteps(sparseSteps, 1000), sample => [sample.pointIndex, sample.cumulative, sample.perPoint]), [[0, 0, 0], [2, 80, 80]], "graph steps use sampled deltas across gaps and normalize the first observation");
assert.equal(reports.graphSelection({...completed, steps: 1000}, sparseSteps, 2, null).steps, 80, "inspector and overlay share sparse step derivation");
assert.equal(reports.graphSelection({...completed, steps: 1000}, sparseSteps, 1, null).steps, null, "unsampled graph points keep a gap");
assert.deepEqual(Array.from(reports.graphSteps([{}, {}, {}], 100), sample => sample.perPoint), [33, 33, 34], "legacy match totals distribute exactly over all points");
assert.equal(JSON.stringify(webModel.steps ? webModel.steps.timeline : []), JSON.stringify(reports.graphSteps(completed.stats, completed.steps)), "native viewer receives the same sparse and legacy step derivation");

// A point suffix with impossible/manual set indexes must not be silently
// grafted onto the real scoring timeline as if it completed a known game.
const suffixPoint = Object.assign({}, completed.stats[completed.stats.length - 1], {
  setIndex: completed.sets.length + 4,
  gameScoreAtStart: { server: 3, returner: 3, isTiebreak: false }
});
const suffixRecord = Object.assign({}, completed, { stats: completed.stats.concat([suffixPoint]) });
const suffixTimeline = reports.scoreTimeline(suffixRecord, suffixRecord.stats, "me");
assert.equal(suffixTimeline, null,
  "suffix-only manual point outside stored sets must reject the replay instead of fabricating a terminal score");

// The generated page embeds JSON inside its own script. Check a malicious
// payload cannot terminate that script and parse each emitted inline program.
const maliciousRecord = JSON.parse(JSON.stringify(completed));
maliciousRecord.id = "<script>globalThis.pwned=true</script>";
maliciousRecord.stats[0].attackerText = "</script><script>globalThis.pwned=true</script>";
const escapedHTML = reports.standaloneHTML(maliciousRecord, maliciousRecord.stats, "me");
assert.ok(!escapedHTML.includes("</script><script>globalThis.pwned=true"), "embedded report data must escape script-breaking input");
const inlineScripts = Array.from(escapedHTML.matchAll(/<script>([\s\S]*?)<\/script>/g));
assert.ok(inlineScripts.length > 0, "interactive report should embed its viewer script");
for (const [, source] of inlineScripts) new vm.Script(source, { filename: "interactive-match-report.js" });

load("phone-demo-settings.js");
const validRecord = context.window.DeuceMatePhoneSettings.validRecord;
records.forEach(record => assert.ok(validRecord(record), `${record.id}: fixtures must round-trip through archive validation`));
const invalidHealth = JSON.parse(JSON.stringify(completed));
invalidHealth.stats[0].heartRateBPM = '<img src=x onerror="alert(1)">';
assert.equal(validRecord(invalidHealth), false, "non-numeric health data must be rejected before importing");
const invalidLive = JSON.parse(JSON.stringify(records.find(record => !record.endTime)));
invalidLive.resume.state.sets = [];
assert.equal(validRecord(invalidLive), false, "a resume snapshot must agree with the visible saved score");

load("phone-demo-trends.js");
const trends = context.window.DeuceMatePhoneTrends;
// Compare identifiers to Swift itself, rather than relying on a hand-counted
// catalogue size (which cannot detect a substituted or misspelled metric).
const nativeTrendSource = fs.readFileSync(path.join(root, "DeuceMate/Packages/DeuceMateCore/Sources/DeuceMateCore/Stats/TrendMetric.swift"), "utf8");
const nativeTrendCases = nativeTrendSource.split("public enum TrendMetric:")[1].split("public var id:")[0];
const expectedMetricIDs = Array.from(nativeTrendCases.matchAll(/^    case (.+)$/gm)).flatMap(match => match[1].split(",").map(id => id.trim()));
assert.deepEqual(Array.from(trends.catalog, metric => metric.id).sort(), expectedMetricIDs.sort(), "browser catalogue must exactly match every native trend metric identifier");
const eligible = trends.samples(records);
assert.ok(eligible.length >= 5, "fixtures should exercise the completed trends view");
const lastSingles = trends.scoped(records, { type: "singles", window: 3 });
assert.equal(lastSingles.length, 3);
assert.ok(lastSingles.every(s => s.record.matchType === "singles" && s.record.endTime), "filter before windowing");
assert.equal(trends.sample(Object.assign({}, completed, { format: "perpetualPoints" })), null);
assert.equal(trends.sample(Object.assign({}, completed, { stats: completed.stats.slice(0, 19) })), null, "thin tracking coverage is ineligible");

function syntheticSummary(id, winners, errors) {
  return { record: { id }, summary: { myWinners: winners, myUnforcedErrors: errors } };
}
const wue = trends.series("wueRatio", [syntheticSummary("a", 10, 0), syntheticSummary("b", 5, 5)]);
assert.equal(wue.points.length, 1, "zero denominator should leave a plot gap");
assert.equal(wue.points[0].index, 1, "gaps retain their original match index");
assert.equal(wue.pooled.value, 3, "pool includes the numerator of a zero-error match");
assert.equal(wue.metric.unit, "ratio", "W:UE is not a percentage");
const dfSamples = [8, 8, 2, 2].map((df, i) => ({ record: { id: String(i) }, summary: { myDoubleFaults: df }, categorizedServed: 20 }));
assert.equal(trends.series("doubleFaults", dfSamples).delta.direction, "improving", "falling double-fault rates improve");
assert.equal(trends.series("doubleFaults", dfSamples.slice(0, 3)).delta, null, "both delta blocks need two matches");

const partial = JSON.parse(JSON.stringify(completed));
partial.stats.push(...Array.from({ length: 30 }, () => Object.assign({}, partial.stats[0], { outcome: "uncategorized", endingShot: null, winner: "opponent" })));
const originalUE = trends.series("unforcedErrors", [trends.sample(completed)]).pooled;
const partialUE = trends.series("unforcedErrors", [trends.sample(partial)]).pooled;
assert.equal(partialUE.value, originalUE.value, "untracked losses cannot improve outcome rates");

const setFixture = JSON.parse(JSON.stringify(completed));
setFixture.format = "standard";
setFixture.sets = [{}, {}, { isTieBreak: true }];
setFixture.stats = [0, 1, 2].flatMap((setIndex) => Array.from({ length: setIndex === 2 ? 12 : 24 }, (_, i) => ({
  setIndex, server: "me", winner: i % 2 ? "me" : "opponent", outcome: "winner", endingShot: "rally", isSecondServe: false, isBreakPoint: false,
  stepsCumulative: setIndex * 1000 + i * 4
})));
const setSample = trends.sample(setFixture);
assert.equal(trends.series("stepsPerPointSet1", [setSample]).pooled.value, 4);
assert.equal(trends.series("stepsPerPointSet2", [setSample]).pooled.value, 4, "set changeover steps are excluded");
assert.equal(trends.series("winRateSet3", [setSample]).points.length, 0, "deciding TB must not be treated as a full third set");
assert.equal(trends.series("winRateDecidingTiebreak", [setSample]).points.length, 1);
setFixture.endTime = null;
assert.equal(trends.series("winRateDecidingTiebreak", [trends.sample(setFixture)]).points.length, 0, "current set never enters fatigue trends");
assert.equal(trends.series("winRateSet1", [trends.sample(setFixture)]).points.length, 1, "completed sets remain eligible in a live match");

process.stdout.write("iPhone demo model QA passed.\n");
