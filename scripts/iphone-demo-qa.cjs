#!/usr/bin/env node
/*
 * Browser QA for the simulated iPhone companion in docs/website/try.html.
 * No project dependency is added: set PLAYWRIGHT_MODULE to the installed
 * Playwright package entry point. Example:
 *   PLAYWRIGHT_MODULE=/path/to/playwright node scripts/iphone-demo-qa.cjs
 *
 * The script intentionally exercises user-visible behavior first and uses
 * window.DeuceMatePhone only for deterministic state assertions.
 */
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { pathToFileURL } = require("node:url");

const { chromium, webkit } = require(process.env.PLAYWRIGHT_MODULE || "playwright");
const URL = process.env.PLAYWRIGHT_URL || pathToFileURL(path.resolve(__dirname, "../docs/website/try.html")).href;
const TIMEOUT = Number(process.env.PLAYWRIGHT_TIMEOUT || 8000);

function check(condition, message) {
  assert.ok(condition, message);
}

async function clickButton(page, label, options = {}) {
  const button = page.getByRole("button", {
    name: label,
    exact: options.exact ?? (typeof label === "string")
  }).first();
  await button.waitFor({ state: "visible", timeout: TIMEOUT });
  // Demo-only live controls are visually hidden (the native scoreboard has none) but keyboard-reachable.
  if (await button.evaluate(el => !!el.closest(".phone-live-extras"))) { await button.focus(); await button.press("Enter"); return; }
  await button.click();
}

async function phoneState(page) {
  return page.evaluate(() => {
    const phone = window.DeuceMatePhone;
    if (!phone) throw new Error("window.DeuceMatePhone is unavailable");
    return {
      route: phone.route || phone.currentRoute || null,
      records: typeof phone.records === "function" ? phone.records() : null,
      settings: phone.settings || null,
      live: typeof phone.liveRecord === "function" ? phone.liveRecord() : null,
      pending: typeof phone.pendingPoint === "function" ? phone.pendingPoint() : null,
      api: Object.keys(phone).sort()
    };
  });
}

async function openPhoneDemo(page) {
  await page.goto(URL, { waitUntil: "domcontentloaded" });
  const root = page.locator("#iphone-demo");
  await root.waitFor({ state: "visible", timeout: TIMEOUT });
  await page.waitForFunction(() => !!window.DeuceMatePhone, null, { timeout: TIMEOUT });
  return root;
}

async function downloadReport(page, perspective) {
  await page.locator("#iphone-demo .phone-nav").getByRole("button", { name: "Share match", exact: true }).click();
  await clickButton(page.locator(".phone-dialog"), "Interactive Web Page");
  const downloadPromise = page.waitForEvent("download", { timeout: TIMEOUT });
  await clickButton(page.locator(".pr-share-submenu"), perspective);
  const disclosure = page.locator(".phone-dialog");
  if (await disclosure.isVisible()) {
    await disclosure.getByRole("button", { name: "Share", exact: true }).click();
  }
  const download = await downloadPromise;
  const filename = download.suggestedFilename();
  check(filename.endsWith(".html"), `Interactive report should download HTML, got ${filename}`);
  const target = path.join(os.tmpdir(), `deucemate-qa-${Date.now()}-${filename}`);
  await download.saveAs(target);
  const html = fs.readFileSync(target, "utf8");
  fs.rmSync(target, { force: true });
  check(html.includes("DeuceMate Match"), "downloaded report should contain report content");
  check(html.includes("function setFilterToggle("), "download should contain an interactive set filter");
  return { filename, html };
}

async function swipe(locator, dx, dy) {
  await locator.scrollIntoViewIfNeeded();
  const box = await locator.boundingBox();
  check(box, "swipe target should be visible");
  const page = locator.page();
  const x = box.x + box.width / 2;
  const y = box.y + box.height / 2;
  await page.mouse.move(x, y);
  await page.mouse.down();
  await page.mouse.move(x + dx, y + dy, { steps: 4 });
  await page.mouse.up();
}

async function main() {
  const browserType = process.env.PLAYWRIGHT_BROWSER === "webkit" ? webkit : chromium;
  const browser = await browserType.launch({ headless: true });
  const context = await browser.newContext({
    viewport: { width: 390, height: 844 },
    deviceScaleFactor: 1,
    isMobile: true,
    hasTouch: true
  });
  const page = await context.newPage();
  const failures = [];
  page.on("pageerror", error => failures.push(`pageerror: ${error.message}`));
  page.on("console", message => {
    if (message.type() === "error") failures.push(`console: ${message.text()}`);
  });

  try {
    const root = await openPhoneDemo(page);

    // Seeded archive and first detail report. Stats/Points and set/chart
    // controls must alter visible content rather than merely exist.
    let state = await phoneState(page);
    check(Array.isArray(state.records) && state.records.length >= 3,
      `expected a useful seeded archive; got ${state.records && state.records.length}`);
    const watchIDsBeforeSync = await page.evaluate(() => window.DeuceMateShell.history.map(record => record.id));
    await clickButton(page, /Sync Now/);
    state = await phoneState(page);
    check(watchIDsBeforeSync.every(id => state.records.some(record => record.id === id)),
      "Sync Now should merge simulated Watch records into the phone archive");
    const firstMatch = root.locator(".phone-match-row, [data-match-row]").first();
    await firstMatch.waitFor({ state: "visible", timeout: TIMEOUT });
    await firstMatch.click();
    const selectedMatchTitle = await root.locator(".pr-title").innerText();
    const selectedMatchScore = await root.locator(".pr-score").innerText();
    const inlineGraph = root.locator(".pr-native-graph .pr-chart-svg").first();
    const inlineMarksBeforeExpand = await inlineGraph.locator("circle").count();
    check(await root.locator(".pr-native-graph .pr-chip").count() === 0,
      "inline graph should keep the compact, filter-free presentation");
    await clickButton(root, "Expand graph");
    const graphDialog = root.locator(".phone-dialog");
    await graphDialog.getByRole("heading", { name: "Points Graph", exact: true }).waitFor({ state: "visible", timeout: TIMEOUT });
    const expandedGraph = graphDialog.locator(".pr-expanded-graph");
    const pointsBeforeFilter = await expandedGraph.locator(".pr-chart-svg circle").count();
    const outcomePill = graphDialog.locator(".pr-chip").filter({ hasText: /W [1-9]/ }).first();
    await outcomePill.click();
    const pointsAfterFilter = await expandedGraph.locator(".pr-chart-svg circle").count();
    check(pointsAfterFilter !== pointsBeforeFilter,
      "selecting an expanded graph outcome pill should change its visible chart marks");
    check(await root.locator(".pr-native-graph .pr-chart-svg circle").count() === inlineMarksBeforeExpand,
      "expanded graph filtering should leave the compact inline chart clean");

    await graphDialog.getByRole('checkbox', {name: 'Heart Rate', exact: true}).check();
    const hrLine = expandedGraph.locator('polyline[stroke="#ff3b30b3"]');
    const rawHR = await hrLine.getAttribute('points');
    await graphDialog.getByRole('group', {name: 'Heart-rate mode', exact: true}).getByRole('button', {name: 'Smoothed', exact: true}).click();
    check(await hrLine.getAttribute('points') !== rawHR, 'Smoothed HR must change the plotted samples');
    await graphDialog.getByRole('group', {name: 'Heart-rate mode', exact: true}).getByRole('button', {name: 'Per-point avg', exact: true}).click();
    check((await expandedGraph.innerText()).includes('does not fetch Health data'), 'averaged HR must disclose its simulated Health source');
    await graphDialog.getByRole('checkbox', {name: 'Steps', exact: true}).check();
    check(await graphDialog.getByRole('group', {name: 'Steps mode', exact: true}).getByRole('button', {name: 'Cumulative', exact: true}).getAttribute('aria-pressed') === 'true', 'Steps must default to the native cumulative view');
    const stepsLine = expandedGraph.locator('polyline[stroke="#34c759bf"]');
    const cumulativeSteps = await stepsLine.getAttribute('points');
    await graphDialog.getByRole('group', {name: 'Steps mode', exact: true}).getByRole('button', {name: 'Per point', exact: true}).click();
    check(await stepsLine.getAttribute('points') !== cumulativeSteps, 'per-point Steps must change the plotted series');

    check(await graphDialog.locator(".pr-graph-accessibility").count() === 0, "the native graph has no separate Graph controls section");
    const visiblePoints = async () => Number(await graphDialog.locator(".pr-expanded-graph").getAttribute("data-visible-points"));
    const fullRange = await visiblePoints(), stageBox = await graphDialog.locator(".pr-expanded-stage").boundingBox();
    await page.mouse.move(stageBox.x + stageBox.width * .3, stageBox.y + stageBox.height / 2);
    await page.mouse.down(); await page.mouse.move(stageBox.x + stageBox.width * .6, stageBox.y + stageBox.height / 2, { steps: 6 }); await page.mouse.up();
    check(await visiblePoints() < fullRange, "dragging across the expanded graph should select a range and zoom to it");
    await clickButton(graphDialog, "Reset Zoom");
    check(await visiblePoints() === fullRange, "Reset Zoom should restore the full match range");
    await clickButton(graphDialog, "Done");
    await graphDialog.waitFor({ state: "hidden", timeout: TIMEOUT });
    check(await root.locator(".pr-native-graph .pr-chart-svg circle").count() === inlineMarksBeforeExpand &&
      await root.locator(".pr-native-graph .pr-chip").count() === 0,
      "closing expanded graph should return to the clean inline chart");
    await page.getByRole("button", { name: "Points", exact: true }).click();
    const pointRows = root.locator(".pr-point-list .pr-point-row");
    const pointCountAll = await pointRows.count();
    check(pointCountAll > 0, "Points tab should show tracked point rows");
    const firstPointContent = await pointRows.first().innerText();
    check(/Serving|Receiving/.test(firstPointContent) &&
      /Winner|Forced error|Unforced error|Double fault|Uncategorised/.test(firstPointContent),
      "Points tab should show a point's serving perspective and categorized result");
    const pointSections = root.locator(".pr-points .pr-native-section");
    check(await pointSections.count() === new Set(state.records[0].stats.map(p => p.setIndex)).size,
      "Points must group the full match by set, as the native Points tab does");
    await page.getByRole("button", { name: "Stats", exact: true }).click();
    const statsContent = root.locator(".pr-stats");
    await statsContent.waitFor({ state: "visible", timeout: TIMEOUT });
    const statsSummary = await statsContent.innerText();
    check(/Winners|Unforced Errors/.test(statsSummary) && await statsContent.locator(".pr-comparisons .pr-split-bar").count() > 0,
      "Stats tab should show native grouped comparisons and split bars");
    check(await root.locator(".pr-title").innerText() === selectedMatchTitle &&
      await root.locator(".pr-score").innerText() === selectedMatchScore,
      "switching report tabs should preserve the selected match title and score");
    process.stdout.write("[base QA] report tabs and expanded graph checks passed\n");

    // Download both interactive report perspectives and open each actual
    // local file in a second page to verify it is standalone and interactive.
    await clickButton(root.locator(".phone-nav"), "Share match");
    check(await root.locator(".pr-share-group").count() === 3, "native export menu should group Interactive, My Stats and Opponent's Stats");
    await clickButton(root.locator(".phone-dialog"), "Interactive Web Page");
    await clickButton(root.locator(".pr-share-submenu"), "My Perspective");
    const consent = page.locator(".phone-dialog");
    await consent.getByRole("heading", { name: "Share health data?" }).waitFor({ state: "visible", timeout: TIMEOUT });
    await consent.getByRole("button", { name: "Cancel", exact: true }).click();
    const mine = await downloadReport(page, "My Perspective");
    const opponent = await downloadReport(page, "Opponent's Perspective");
    check(mine.html !== opponent.html, "perspective exports should frame point results differently");
    check(mine.html.includes("My Perspective") && opponent.html.includes("Opponent’s Perspective"),
      "each exported report should name its reader perspective");
    for (const report of [mine, opponent]) {
      const p = await context.newPage();
      const localPath = path.join(os.tmpdir(), `deucemate-open-${Date.now()}-${report.filename}`);
      fs.writeFileSync(localPath, report.html);
      await p.goto(`file://${localPath}`);
      p.on("pageerror", error => failures.push(`export: ${error.message}`));
      await p.getByRole("button", { name: "Points", exact: true }).click();
      check(await p.locator(".pt-row").count() === await p.evaluate(() => DATA.points.length), "native Points history includes every saved rally");
      check(await p.locator("svg").count(), "downloaded report should include an interactive chart");
      check(await p.locator(".pt-row").count() > 0, "downloaded report should include its point data table");
      await p.close();
      fs.rmSync(localPath, { force: true });
    }
    process.stdout.write("[base QA] both perspective exports passed\n");

    // Trends filters should affect sample/chart state and return a clear empty
    // state for restrictive combinations.
    await clickButton(page, "Back to Matches");
    await clickButton(page, /Performance Trends/);
    const trendRoot = root.locator(".pr-trends");
    await trendRoot.waitFor({ state: "visible", timeout: TIMEOUT });
    check(await trendRoot.getByRole("group", { name: "Trend window", exact: true }).count() === 1 &&
      await trendRoot.getByRole("group", { name: "Match type", exact: true }).count() === 1 &&
      await trendRoot.getByLabel("Match format", { exact: true }).count() === 1,
      "Trends should provide native window, type and format filters");
    const trendBefore = await trendRoot.innerText();
    await trendRoot.getByRole("group", { name: "Match type", exact: true }).getByRole("button", { name: "Doubles", exact: true }).click();
    check((await trendRoot.innerText()) !== trendBefore, "changing Trends filters should update the view");
    process.stdout.write("[base QA] Trends filter checks passed\n");

    // Start one live match through the shared watch scorer, then verify phone
    // input gating and watch/phone state identity against that same instance.
    await page.evaluate(() => {
      const shell = window.DeuceMateShell;
      const phone = window.DeuceMatePhone;
      phone.setSetting("track", true);
      phone.setSetting("iPhoneInput", false);
      shell.liveId = "qa-live-match";
      shell.matchPhase = "play";
      shell.api.start({ format: "standard", server: "me", tracking: true });
      shell.push({ id: "match" });
      phone.navigate("live");
    });
    await page.waitForTimeout(150);
    await page.getByRole("button", { name: "Back to Matches" }).click();
    await root.getByRole("button", { name: "Settings" }).click();
    const inputToggle = root.getByRole("checkbox", { name: "iPhone Input" });
    await inputToggle.waitFor({ state: "visible", timeout: TIMEOUT });
    await inputToggle.uncheck();
    state = await phoneState(page);
    check(state.settings && state.settings.iPhoneInput === false, "iPhone Input toggle should update shared settings");
    await page.getByRole("button", { name: "Back to Matches" }).click();
    await page.getByRole("button", { name: /Live Scoreboard/ }).click();
    const beforeGatedSwipe = await page.evaluate(() => window.DeuceMateShell.api.stateRef());
    await swipe(root.locator(".phone-scoreboard"), 0, -70);
    await page.waitForTimeout(120);
    check(JSON.stringify(await page.evaluate(() => window.DeuceMateShell.api.stateRef())) === JSON.stringify(beforeGatedSwipe),
      "score swipe should do nothing while iPhone Input is off");
    await clickButton(page, "Enable iPhone Input");
    state = await phoneState(page);
    check(state.settings.iPhoneInput, "Enable Input should switch scoring on");
    const liveBefore = await page.evaluate(() => window.DeuceMateShell.api.snapshot(false));
    await swipe(root.locator(".phone-scoreboard"), 0, -70);
    await page.waitForTimeout(150);
    const afterScore = await page.evaluate(() => window.DeuceMateShell.api.snapshot(false));
    check(JSON.stringify(afterScore.resume.state) !== JSON.stringify(liveBefore.resume.state),
      "phone swipe should update the shared watch-owned score");
    check(await root.locator(".phone-point-number").first().innerText() !== "0",
      "phone scoreboard should render the accepted point");
    check(JSON.stringify(await page.evaluate(() => document.querySelector("#watch-demo").__deuceMateDebug.state())) === JSON.stringify(afterScore.resume.state),
      "watch scorer and phone match snapshot should be the same live state");
    process.stdout.write("[base QA] shared live scorer and input gate checks passed\n");

    // Categorize one point through outcome + ending shot. A legal second-serve
    // lost point exposes Double Fault and commits without an ending-shot step.
    await root.getByRole("button", { name: "Winner", exact: true }).click();
    await root.getByRole("button", { name: "Rally", exact: true }).click();
    await page.waitForFunction(() => !window.DeuceMateShell.api.phoneState().pending, null, { timeout: TIMEOUT });
    await clickButton(page, "2nd serve");
    await clickButton(page, "↓ Opp");
    const doubleFault = root.getByRole("button", { name: "Double Fault", exact: true });
    await doubleFault.waitFor({ state: "visible", timeout: TIMEOUT });
    await doubleFault.click();
    await page.waitForFunction(() => !window.DeuceMateShell.api.phoneState().pending, null, { timeout: TIMEOUT });
    check(!(await page.evaluate(() => window.DeuceMateShell.api.phoneState())).pending,
      "double fault should commit immediately without a shot-selection step");
    const beforeUndo = await page.evaluate(() => window.DeuceMateShell.api.stateRef());
    await clickButton(page, "← Undo");
    await page.waitForTimeout(100);
    check(JSON.stringify(await page.evaluate(() => window.DeuceMateShell.api.stateRef())) !== JSON.stringify(beforeUndo),
      "Undo should restore the prior point state");
    process.stdout.write("[base QA] live point categorization and undo passed\n");

    // End checkpoint confirmation: cancel preserves the live record, confirm
    // completes it and clears the active scorer.
    await page.evaluate(() => window.DeuceMatePhone.navigate("detail", window.DeuceMatePhone.liveRecord()));
    await clickButton(page, "End at Current Score");
    await page.keyboard.press("Escape");
    check(!!(await phoneState(page)).live, "cancel should preserve the in-progress match");
    await clickButton(page, "End at Current Score");
    await page.locator(".phone-dialog").getByRole("button", { name: "End at Current Score" }).click();
    await page.waitForTimeout(100);
    check(!(await phoneState(page)).live, "confirmed end should clear active scoring state");
    check(await root.locator('.phone-nav strong').innerText() === 'Matches',
      "confirmed end should dismiss match detail, matching the iPhone app");

    // Manual entry creates a browsable in-progress record. A malformed archive
    // import must be rejected and leave the existing archive unchanged.
    await page.getByRole("button", { name: "Manual match entry" }).click();
    await page.getByRole("button", { name: "Save Match" }).click();
    state = await phoneState(page);
    const manualRecord = state.records.find(record => record.iWon == null && !record.endTime);
    check(manualRecord,
      "valid manual match should appear as an in-progress archive record");
    const watchHasManual = await page.evaluate(id => window.DeuceMateShell.history.some(record => record.id === id), manualRecord.id);
    check(watchHasManual, "manual entry should sync to Watch so it can be resumed");

    const manualRow = root.locator(".phone-match-wrap").filter({ hasText: "In Progress" }).first();
    await manualRow.getByRole("button", { name: /Match actions/ }).click();
    await clickButton(page, "Remove from Watch");
    check((await phoneState(page)).records.some(record => record.id === manualRecord.id),
      "Remove from Watch should retain the phone archive copy");
    check(!(await page.evaluate(id => window.DeuceMateShell.history.some(record => record.id === id), manualRecord.id)),
      "Remove from Watch should remove only the simulated Watch copy");
    await manualRow.getByRole("button", { name: /Match actions/ }).click();
    await clickButton(page, "Sync to Watch");
    check(await page.evaluate(id => window.DeuceMateShell.history.some(record => record.id === id), manualRecord.id),
      "Sync to Watch should restore the watch copy");

    // Resume the manually entered checkpoint through the simulated Watch
    // history/detail UI and verify it becomes the active scorer.
    await page.evaluate(() => {
      const shell = window.DeuceMateShell;
      shell.popAll(); shell.push({ id: "history" }); shell.render();
    });
    await page.locator("#watch-demo .hist-row").first().click();
    await page.getByRole("button", { name: "Resume this match" }).click();
    await page.waitForFunction(id => window.DeuceMateShell.liveId === id && window.DeuceMateShell.api.active(), manualRecord.id, { timeout: TIMEOUT });

    await page.evaluate(() => window.DeuceMatePhone.navigate("matches"));
    await root.getByRole("button", { name: "Settings" }).click();
    const beforeImport = (await phoneState(page)).records.length;
    const fileChoice = page.waitForEvent("filechooser");
    await clickButton(page, "Import Match Archive");
    const chooser = await fileChoice;
    await chooser.setFiles({ name: "malicious.json", mimeType: "application/json", buffer: Buffer.from('{"__proto__":{"polluted":true},"matches":[{"id":"x"}]}') });
    await page.waitForTimeout(200);
    check((await phoneState(page)).records.length === beforeImport,
      "invalid/malicious archive must not replace or mutate the current archive");
    process.stdout.write("[base QA] manual entry, Watch history, and invalid import checks passed\n");

    // Browser layout should stay inside the device frame without horizontal
    // scrolling; an enlarged viewport is checked separately for responsive
    // desktop presentation.
    await page.goto(URL, { waitUntil: "domcontentloaded" });
    await page.waitForSelector("#iphone-demo", { timeout: TIMEOUT });
    const overflow = await root.evaluate(el => ({ client: el.clientWidth, scroll: el.scrollWidth }));
    check(overflow.scroll <= overflow.client + 1, `iPhone demo overflows horizontally: ${JSON.stringify(overflow)}`);
    check(failures.length === 0, `browser errors: ${failures.join("; ")}`);
    process.stdout.write("iPhone demo browser QA passed.\n");
  } finally {
    await context.close();
    await browser.close();
  }
}

main().catch(error => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
