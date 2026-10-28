#!/usr/bin/env node
/* Build a native manual archive from the browser's exact deterministic matches.
 * This writes a JSON file only; seed a disposable simulator via ArchiveTool.
 * Usage: node scripts/iphone-demo-native-fixtures.cjs /tmp/native-parity.json
 */
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const crypto = require("node:crypto");
const assets = path.resolve(__dirname, "../docs/website/assets");
const context = vm.createContext({ console, document: { querySelectorAll: () => [] }, window: {} });
function load(name) { vm.runInContext(fs.readFileSync(path.join(assets, name), "utf8"), context); }
load("watch-demo.js");
load("watch-demo-tracking.js");
const shell = { history: [], settings: { track: false }, screens: {}, api: {} };
context.window.DeuceMateShell = shell;
load("watch-demo-history.js");
shell.seedHistory();
function uuid(value) {
  const hex = crypto.createHash("sha256").update(value).digest("hex").slice(0, 32);
  return [hex.slice(0, 8), hex.slice(8, 12), hex.slice(12, 16), hex.slice(16, 20), hex.slice(20)].join("-").toUpperCase();
}
const swiftDate = milliseconds => milliseconds == null ? null : milliseconds / 1000 - 978307200;
const records = shell.history.map(record => {
  const state = record.resume.state;
  const perSetCounts = {};
  record.stats.forEach(point => { perSetCounts[point.setIndex] = (perSetCounts[point.setIndex] || 0) + 1; });
  const seen = {};
  return {
    id: uuid(record.id), startTime: swiftDate(record.startTime), endTime: swiftDate(record.endTime),
    setScores: record.sets.map((set, i) => ({ id: uuid(record.id + ":set:" + i), ...set })),
    stats: record.stats.map((point, i) => {
      const setStart = Object.entries(record.setElapsed || {}).reduce((sum, [key, value]) => sum + (+key < point.setIndex ? value : 0), 0);
      const setElapsed = record.setElapsed[point.setIndex] || record.elapsed / record.sets.length;
      seen[point.setIndex] = (seen[point.setIndex] || 0) + 1;
      const health = (record.steps || 0) > 0 && record.id !== "seed7152";
      return {
        ...point, id: uuid(record.id + ":point:" + i),
        timestamp: swiftDate(record.startTime) + setStart + setElapsed * seen[point.setIndex] / perSetCounts[point.setIndex],
        ...(health ? {
          heartRateBPM: Math.round(140 + Math.sin(i / 8) * 18 + Math.min(17, i / 20)),
          stepsCumulative: Math.round(record.steps * (i + 1) / record.stats.length)
        } : {})
      };
    }),
    iWon: record.iWon, currentPointsMe: record.currentPointsMe, currentPointsOpponent: record.currentPointsOpponent,
    currentServer: state.currentServer, gameCount: state.gameCount,
    pointCountInTiebreak: state.pointCountInTiebreak, tiebreakStartServer: state.tiebreakStartServer,
    tiebreakFirstPointReceiver: state.tiebreakFirstPointReceiver, lastTiebreakPointServer: state.lastTiebreakPointServer,
    isOnSecondServe: record.resume.secondServe, matchType: record.matchType, matchFormat: record.format,
    doublesServer: state.doublesServer, doublesServiceOrder: state.doublesServiceOrder,
    doublesServiceIndex: state.doublesServiceIndex, tiebreakStartDoublesIndex: state.doublesTiebreakStartIndex,
    matchElapsedSeconds: record.elapsed, setElapsedSeconds: record.setElapsed,
    totalSteps: record.steps || null, totalCaloriesKcal: record.kcal || null,
    recentPoints: record.resume.momentum, momentumEnabled: true
  };
});
const output = process.argv[2];
if (!output) throw new Error("Provide a destination JSON path; this script never writes into a simulator itself.");
fs.writeFileSync(output, JSON.stringify({ format: "deucemate.matchArchive", schemaVersion: 1,
  exportedAt: swiftDate(Date.now()), includesHealthData: true, records }, null, 2));
console.log(JSON.stringify(shell.history.map((record, i) => ({ browserID: record.id, nativeID: records[i].id,
  points: records[i].stats.length, inProgress: record.endTime == null })), null, 2));
