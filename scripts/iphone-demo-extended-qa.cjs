#!/usr/bin/env node
/*
 * Extended Playwright coverage for the browser iPhone companion in
 * docs/website/try.html. This is intentionally independent of the base QA
 * script so scenarios can use clean browser contexts and storage.
 *
 *   PLAYWRIGHT_MODULE=/path/to/playwright node scripts/iphone-demo-extended-qa.cjs
 */
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { pathToFileURL } = require("node:url");

const { chromium, webkit } = require(process.env.PLAYWRIGHT_MODULE || "playwright");
const DEMO_URL = process.env.PLAYWRIGHT_URL || pathToFileURL(path.resolve(__dirname, "../docs/website/try.html")).href;
const TIMEOUT = Number(process.env.PLAYWRIGHT_TIMEOUT || 7000);
const SCREENSHOT_DIR = process.env.PLAYWRIGHT_SCREENSHOT_DIR || "/tmp/deucemate-iphone-qa";

function check(value, message) { assert.ok(value, message); }
function progress(message) { process.stdout.write(`[extended QA] ${message}\n`); }

// The demo-only live controls are visually hidden but keyboard-reachable, so activate them like a keyboard user.
async function activate(locator) { await locator.focus(); await locator.press("Enter"); }
async function button(scope, name) {
  const target = scope.getByRole("button", { name, exact: typeof name === "string" }).first();
  await target.waitFor({ state: "visible", timeout: TIMEOUT });
  return target;
}

function observeErrors(page, errors, label) {
  page.on("pageerror", error => errors.push(`${label} pageerror: ${error.message}`));
  page.on("console", message => {
    if (message.type() === "error") errors.push(`${label} console: ${message.text()}`);
  });
}

async function openDemo(page) {
  await page.goto(DEMO_URL, { waitUntil: "domcontentloaded", timeout: TIMEOUT });
  await page.locator("#iphone-demo").waitFor({ state: "visible", timeout: TIMEOUT });
  await page.waitForFunction(() => !!window.DeuceMatePhone, null, { timeout: TIMEOUT });
  return page.locator("#iphone-demo");
}

async function state(page) {
  return page.evaluate(() => ({
    records: window.DeuceMatePhone.records(),
    settings: { ...window.DeuceMatePhone.settings },
    route: window.DeuceMatePhone.route || window.DeuceMatePhone.currentRoute || null
  }));
}

async function saveDownload(page, trigger, prefix) {
  const downloadWait = page.waitForEvent("download", { timeout: TIMEOUT });
  await trigger();
  const download = await downloadWait;
  const target = path.join(os.tmpdir(), `${prefix}-${Date.now()}-${download.suggestedFilename()}`);
  await download.saveAs(target);
  const content = fs.readFileSync(target, "utf8");
  fs.rmSync(target, { force: true });
  return { name: download.suggestedFilename(), content };
}

async function importPayload(page, payload, filename) {
  const fileWait = page.waitForEvent("filechooser", { timeout: TIMEOUT });
  await (await button(page, "Import Match Archive")).click();
  const chooser = await fileWait;
  await chooser.setFiles({ name: filename, mimeType: "application/json", buffer: Buffer.from(JSON.stringify(payload)) });
  await page.getByRole("heading", { name: "Import Match Archive", exact: true }).waitFor({ state: "visible", timeout: TIMEOUT });
}

async function clickReplaceAndHandleDialog(page, replaceButton, accept) {
  await replaceButton.click();
  const dialog = page.locator("#iphone-demo .phone-dialog");
  await dialog.getByRole("heading", {name: "Replace Match Archive?", exact: true}).waitFor({state: "visible", timeout: TIMEOUT});
  check(await dialog.getAttribute("role") === "alertdialog", "archive replacement must use an in-phone alert");
  check(/Replace \d+ current matches with \d+ imported matches\?/.test(await dialog.innerText()),
    "Replace Archive confirmation should describe the archive counts");
  await (await button(dialog, accept ? "Replace Archive" : "Cancel")).click();
}

async function changeNumber(card, label, value) {
  const field = card.getByRole("spinbutton", {name: label, exact: true});
  await field.evaluate((el, next) => {
    el.value = String(next);
    el.dispatchEvent(new Event("change", { bubbles: true }));
  }, value);
}

async function liveScoreSnapshot(page) {
  return page.evaluate(() => {
    const state = window.DeuceMateShell.api.stateRef();
    return {
      currentPointsMe: state.currentPointsMe,
      currentPointsOpponent: state.currentPointsOpponent,
      gameCount: state.gameCount,
      pointCountInTiebreak: state.pointCountInTiebreak,
      sets: state.sets.map(set => ({ gamesMe: set.gamesMe, gamesOpponent: set.gamesOpponent,
        tieBreakPointsMe: set.tieBreakPointsMe, tieBreakPointsOpponent: set.tieBreakPointsOpponent }))
    };
  });
}

async function fresh(browser, options = {}) {
  const context = await browser.newContext({
    viewport: options.viewport || { width: 390, height: 844 },
    deviceScaleFactor: 1,
    isMobile: !!options.mobile,
    hasTouch: !!options.mobile,
    reducedMotion: options.reducedMotion || "no-preference"
  });
  const page = await context.newPage();
  page.setDefaultTimeout(TIMEOUT);
  return { context, page };
}

async function main() {
  fs.mkdirSync(SCREENSHOT_DIR, { recursive: true });
  const browserType = process.env.PLAYWRIGHT_BROWSER === "webkit" ? webkit : chromium;
  const browser = await browserType.launch({ headless: true });
  const errors = [];
  const contexts = [];
  const remember = async options => {
    const result = await fresh(browser, options);
    contexts.push(result.context);
    observeErrors(result.page, errors, `context-${contexts.length}`);
    return result;
  };

  try {
    // Capture the phone-sized archive and details view, and prove the report
    // tabs switch between distinct, populated content sections.
    const mobile = await remember({ mobile: true, reducedMotion: "reduce" });
    const root = await openDemo(mobile.page);
    check(await mobile.page.evaluate(() => matchMedia("(prefers-reduced-motion: reduce)").matches),
      "mobile context should expose the reduced-motion preference");
    const initial = await state(mobile.page);
    check(await root.locator('.phone-match-row').first().evaluate(el => getComputedStyle(el).transitionDuration === '0s'),
      'reduced motion must disable archive swipe animations');
    check(initial.records.length >= 3, `expected seeded archive rows, got ${initial.records.length}`);
    await root.locator(".phone-body").evaluate(el => { el.scrollTop = 0; });
    await root.locator(".phone-frame").screenshot({ path: path.join(SCREENSHOT_DIR, "iphone-mobile-matches.png") });
    progress("mobile archive screenshot and seed data passed");

    const firstRow = root.locator(".phone-match-row").first();
    await firstRow.click();
    const statsTab = await button(root, "Stats");
    const pointsTab = await button(root, "Points");
    await statsTab.click();
    const statsText = await root.locator(".phone-body").innerText();
    check(/Points Won|Winners|Unforced Errors/.test(statsText), "Stats tab should render match metrics");
    check(await root.locator(".pr-comparisons .pr-split-bar").count() > 0, "Stats tab should have native grouped comparison bars");
    await root.locator(".phone-body").evaluate(el => { el.scrollTop = 0; });
    await root.locator(".pr-scroll").evaluate(el => { el.scrollTop = 0; });
    await root.locator(".phone-frame").screenshot({ path: path.join(SCREENSHOT_DIR, "iphone-mobile-match-stats.png") });
    await pointsTab.click();
    const pointsText = await root.locator(".phone-body").innerText();
    check(await root.locator('.pr-points[aria-label="Point by point"] .pr-native-section').count() > 0, "Points tab should render set-grouped point history sections");
    const pointRows = root.locator(".pr-point-list .pr-point-row");
    check(await pointRows.count() > 0, "Points tab should show actual tracked points");
    check(pointsText !== statsText, "Stats and Points tabs should show different section content");

    // Touch interaction: tap a real graph mark and verify it selects a point.
    await statsTab.click();
    const graph = root.locator(".pr-native-graph .pr-chart-svg").first();
    await graph.waitFor({ state: "visible", timeout: TIMEOUT });
    await graph.scrollIntoViewIfNeeded();
    const graphMark = graph.locator("circle[role=button]").first();
    await graphMark.waitFor({ state: "visible", timeout: TIMEOUT });
    const markBox = await graphMark.boundingBox();
    check(markBox && markBox.width > 0 && markBox.height > 0, "graph point should have tappable bounds");
    await mobile.page.touchscreen.tap(markBox.x + markBox.width / 2, markBox.y + markBox.height / 2);
    await root.locator(".pr-inspector").waitFor({ state: "visible", timeout: TIMEOUT });
    check(/Set \d+ · Pt \d+/.test(await root.locator(".pr-inspector").innerText()), "touching a graph point should inspect its native set-relative point number");
    progress("Stats/Points content switch and touch graph inspection passed");

    // Both report files are real, distinct reader perspectives. Open each
    // downloaded document with scripting disabled and check its static report.
    await pointsTab.click();
    await (await button(root.locator(".phone-nav"), "Share match")).click();
    const groups = root.locator(".pr-share-group");
    check(await groups.count() === 3, "native report menu should offer Interactive plus both text perspectives");
    const reports = [];
    for (let i = 0; i < 2; i++) {
      if (!(await groups.first().isVisible())) await (await button(root.locator(".phone-nav"), "Share match")).click();
      const report = await saveDownload(mobile.page, async () => {
        await (await button(root.locator(".phone-dialog"), "Interactive Web Page")).click();
        await (await button(root.locator(".pr-share-submenu"), i === 0 ? "My Perspective" : "Opponent's Perspective")).click();
        const consent = root.locator(".phone-dialog");
        if (await consent.isVisible()) await (await button(consent, "Share")).click();
      }, `deucemate-extended-${i}`);
      check(report.name.endsWith(".html"), `report should download HTML, got ${report.name}`);
      check(report.content.includes("DeuceMate Match"), "download should contain report title");
      check(report.content.includes("<svg") && /My Perspective|Opponent’s Perspective/.test(report.content),
        "download should contain static chart content and perspective label");
      reports.push(report);
    }
    check(reports[0].content !== reports[1].content, "reader perspectives should produce different reports");
    check(reports[0].content.includes("My Perspective") && reports[1].content.includes("Opponent’s Perspective"),
      "each downloaded report should identify its perspective");
    for (let i = 0; i < reports.length; i++) {
      const noJSContext = await browser.newContext({ javaScriptEnabled: false, viewport: { width: 1024, height: 768 } });
      contexts.push(noJSContext);
      const noJSPage = await noJSContext.newPage();
      noJSPage.setDefaultTimeout(TIMEOUT);
      observeErrors(noJSPage, errors, `no-js-${i}`);
      const localPath = path.join(os.tmpdir(), `deucemate-extended-nojs-${Date.now()}-${i}.html`);
      fs.writeFileSync(localPath, reports[i].content);
      try {
        await noJSPage.goto(pathToFileURL(localPath).href, { waitUntil: "domcontentloaded", timeout: TIMEOUT });
        const staticRoot = noJSPage.locator("#root");
        await staticRoot.waitFor({ state: "visible", timeout: TIMEOUT });
        const bodyText = await staticRoot.innerText();
        check(bodyText.length > 100 && /Match|Points|Perspective/.test(bodyText), "no-JS report should provide meaningful static text");
        check(await staticRoot.locator("svg").count() > 0, "no-JS report should include its static SVG charts");
      } finally { fs.rmSync(localPath, { force: true }); }

      // The same downloaded artifact must also hydrate the actual controls
      // when scripts are enabled, and tab/set choices must alter real rows.
      const interactiveContext = await browser.newContext({ viewport: { width: 1024, height: 768 } });
      contexts.push(interactiveContext);
      const interactivePage = await interactiveContext.newPage();
      interactivePage.setDefaultTimeout(TIMEOUT);
      observeErrors(interactivePage, errors, `interactive-export-${i}`);
      const interactivePath = path.join(os.tmpdir(), `deucemate-extended-js-${Date.now()}-${i}.html`);
      fs.writeFileSync(interactivePath, reports[i].content);
      try {
        await interactivePage.goto(pathToFileURL(interactivePath).href, { waitUntil: "domcontentloaded", timeout: TIMEOUT });
        const reportRoot = interactivePage.locator("#root");
        await reportRoot.getByRole("button", {name:"Stats", exact:true}).waitFor({state:"visible"});
        check(await reportRoot.locator("svg").count() > 0, "interactive report draws the native graph");
        const hitFill = await reportRoot.locator('svg rect[fill="transparent"]').last().evaluate(el => getComputedStyle(el).fill.replace(/\s/g, ''));
        check(hitFill === 'transparent' || hitFill === 'rgba(0,0,0,0)', 'offline hit surface stays transparent');
        await reportRoot.locator('.chip').filter({hasText: /Heart Rate/}).click();
        check(await reportRoot.locator('svg path[stroke="#FF3B30"]').count() > 0, "native HR overlay draws recorded samples");
        await reportRoot.locator('.chip').filter({hasText: /Steps/}).click();
        const cumulative = await reportRoot.locator('svg path[stroke="#34C759"]').getAttribute('d');
        await reportRoot.locator('.chip').filter({hasText: 'Per point'}).click();
        check(await reportRoot.locator('svg path[stroke="#34C759"]').getAttribute('d') !== cumulative, 'native per-point Steps changes the overlay');
        const expected = await interactivePage.evaluate(() => DATA.points.length);
        await reportRoot.getByRole('button', {name:'Points',exact:true}).click();
        check(await reportRoot.locator('.pt-row').count() === expected, 'native Points history includes every rally');
        await reportRoot.getByRole('button', {name:'Stats',exact:true}).click();
        if (await reportRoot.getByRole('button', {name:'Set 1',exact:true}).count()) {
          const all = await reportRoot.locator('.pw-card').innerText();
          await reportRoot.getByRole('button', {name:'Set 1',exact:true}).click();
          check(await reportRoot.locator('.pw-card').innerText() !== all, 'native set segments scope the stats');
        }
      } finally { fs.rmSync(interactivePath, { force: true }); }
    }
    progress("both perspective downloads passed no-JS and interactive report checks");

    // Stats AI prompt is local and explicit: advance through the health-data
    // disclosure if shown, then verify a prompt can be inspected without an
    // external navigation.
    await statsTab.click();
    await (await button(root, "Open AI Coach")).click();
    const consent = root.locator(".phone-dialog");
    if (await consent.isVisible()) {
      check((await consent.innerText()).includes("health data"), "AI coach disclosure should describe included health data");
      await (await button(consent, "Continue")).click();
    }
    const promptDialog = root.locator(".phone-dialog");
    await promptDialog.getByRole("heading", { name: "AI Coach", exact: true }).waitFor({ state: "visible", timeout: TIMEOUT });
    const prompt = await promptDialog.locator("textarea.pr-prompt").inputValue();
    check(prompt.includes("tennis coach") && prompt.includes("## Raw Point Data"), "AI Coach should show a match-specific prompt");
    await (await button(promptDialog, "Done")).click();
    progress("AI Coach consent and local prompt passed");

    // Keyboard scoring follows the same watch-owned scorer instance as the
    // touch controls. This also verifies the scoreboard can receive focus.
    await mobile.page.evaluate(() => {
      const shell = window.DeuceMateShell;
      window.DeuceMatePhone.setSetting("iPhoneInput", true);
      shell.liveId = "extended-keyboard-match";
      shell.matchPhase = "play";
      shell.api.start({ format: "standard", server: "me", tracking: true });
      shell.push({ id: "match" });
      window.DeuceMatePhone.navigate("live");
    });
    const scoreboard = root.locator(".phone-scoreboard");
    await scoreboard.waitFor({ state: "visible", timeout: TIMEOUT });
    const beforeKeyboardScore = await mobile.page.evaluate(() => JSON.stringify(window.DeuceMateShell.api.stateRef()));
    await scoreboard.focus();
    await mobile.page.keyboard.press("ArrowUp");
    await mobile.page.waitForFunction(previous => JSON.stringify(window.DeuceMateShell.api.stateRef()) !== previous,
      beforeKeyboardScore, { timeout: TIMEOUT });
    await mobile.page.waitForTimeout(50);
    check(await root.locator(".phone-scoreboard").evaluate(el => document.activeElement === el),
      "keyboard scoring should preserve focus on the refreshed scoreboard");

    const pending = await mobile.page.evaluate(() => window.DeuceMateShell.api.phoneState().pending);
    check(pending && pending.winner === "me", "ArrowUp should create a pending point for the player's side");
    await (await button(root, "Winner")).click();
    await (await button(root, "Rally")).click();
    await mobile.page.waitForFunction(() => !window.DeuceMateShell.api.phoneState().pending, null, { timeout: TIMEOUT });
    let scoredStats = await mobile.page.evaluate(() => window.DeuceMatePhone.liveRecord().stats);
    check(scoredStats.some(point => point.outcome === "winner" && point.endingShot === "rally"),
      "outcome plus ending-shot selection should commit a categorized point");

    await mobile.page.evaluate(() => window.DeuceMatePhone.setSetting("track", false));
    await root.locator(".phone-scoreboard").focus();
    for (let step = 0; step < 2; step++) {
      const beforeRepeatedArrow = await liveScoreSnapshot(mobile.page);
      const beforeSerialized = JSON.stringify(await mobile.page.evaluate(() => window.DeuceMateShell.api.stateRef()));
      await mobile.page.keyboard.press("ArrowUp");
      await mobile.page.waitForFunction(previous => JSON.stringify(window.DeuceMateShell.api.stateRef()) !== previous,
        beforeSerialized, { timeout: TIMEOUT });
      await mobile.page.waitForTimeout(50);
      const afterRepeatedArrow = await liveScoreSnapshot(mobile.page);
      check(afterRepeatedArrow.currentPointsMe === beforeRepeatedArrow.currentPointsMe + 1 &&
        afterRepeatedArrow.currentPointsOpponent === beforeRepeatedArrow.currentPointsOpponent &&
        afterRepeatedArrow.gameCount === beforeRepeatedArrow.gameCount &&
        afterRepeatedArrow.pointCountInTiebreak === beforeRepeatedArrow.pointCountInTiebreak &&
        JSON.stringify(afterRepeatedArrow.sets) === JSON.stringify(beforeRepeatedArrow.sets),
        `ArrowUp ${step + 1} should add exactly one current-game point: before=${JSON.stringify(beforeRepeatedArrow)} after=${JSON.stringify(afterRepeatedArrow)}`);
      check(await root.locator(".phone-scoreboard").evaluate(el => document.activeElement === el),
        `repeated ArrowUp ${step + 1} should score and keep focus on the refreshed scoreboard`);
    }

    await mobile.page.evaluate(() => window.DeuceMatePhone.setSetting("track", true));
    await activate(await button(root, "2nd serve"));
    await activate(await button(root, "↓ Opp"));
    check(!!(await mobile.page.evaluate(() => window.DeuceMateShell.api.phoneState().pending)),
      "a lost second serve should expose pending point categorization");
    await (await button(root, "Double Fault")).click();
    await mobile.page.waitForFunction(() => !window.DeuceMateShell.api.phoneState().pending, null, { timeout: TIMEOUT });
    scoredStats = await mobile.page.evaluate(() => window.DeuceMatePhone.liveRecord().stats);
    check(scoredStats.some(point => point.outcome === "doubleFault"), "Double Fault should commit directly from the pending point");
    const committedCount = scoredStats.length;
    await activate(await button(root, "← Undo"));
    await mobile.page.waitForFunction(count => window.DeuceMatePhone.liveRecord().stats.length < count,
      committedCount, { timeout: TIMEOUT });
    const afterUndo = await mobile.page.evaluate(() => window.DeuceMatePhone.liveRecord().stats);
    check(!afterUndo.some(point => point.outcome === "doubleFault"), "Undo should remove the committed double fault");
    progress("keyboard scoring, point categorization, double-fault commit, and undo passed");

    // Settings: changing the theme and a bounded numeric value updates the
    // actual settings model; browser number validation/clamping is observable.
    await (await button(root, "Back to Matches")).click();
    await (await button(root, "Settings")).click();
    const settings = root.locator(".phone-settings");
    await settings.getByRole("group", { name: "Theme", exact: true }).getByRole("button", { name: "Clay Court", exact: true }).click();
    await settings.getByLabel("Override Max HR").check();
    const bpm = settings.getByLabel("Override value (bpm)");
    await bpm.evaluate(el => {
      el.value = "999";
      el.dispatchEvent(new Event("change", { bubbles: true }));
    });
    const settingState = await state(mobile.page);
    check(settingState.settings.theme === "clayCourt", "theme selection should update the phone setting");
    check(settingState.settings.overrideBpm === 220, `max HR should clamp to 220, got ${settingState.settings.overrideBpm}`);
    await root.locator(".phone-body").evaluate(el => { el.scrollTop = 0; });
    await root.locator(".phone-frame").screenshot({ path: path.join(SCREENSHOT_DIR, "iphone-mobile-settings.png") });
    progress("settings validation and screenshot passed");

    // Manual entry validation: an impossible completed set disables Save;
    // correcting the score enables it and saving adds an in-progress record.
    // Native puts manual entry on the Matches toolbar, not in Settings.
    await (await button(root, "Back to Matches")).click();
    await (await button(root, "Manual match entry")).click();
    const manual = root.locator(".phone-manual");
    await (await button(manual, /^Increase Completed sets:/)).click();
    const firstSet = manual.locator(".phone-manual-section").filter({ hasText: "Set 1 (final)" });
    await changeNumber(firstSet, "Me", 5);
    await changeNumber(firstSet, "Opponent", 4);
    check(await (await button(manual, "Save Match")).isDisabled(), "invalid completed set should disable saving");
    await changeNumber(firstSet, "Me", 6);
    check(!(await (await button(manual, "Save Match")).isDisabled()), "valid completed set should enable saving");

    // Full-final-set regression: with two completed sets, a third regular set
    // that already has a winner is a completed match, not a resumable record.
    await manual.getByLabel("Format").selectOption("bestOf3FullFinalSet");
    await (await button(manual, /^Increase Completed sets:/)).click();
    await changeNumber(manual.locator(".phone-manual-section").filter({ hasText: "Set 1 (final)" }), "Me", 6);
    await changeNumber(manual.locator(".phone-manual-section").filter({ hasText: "Set 1 (final)" }), "Opponent", 4);
    await changeNumber(manual.locator(".phone-manual-section").filter({ hasText: "Set 2 (final)" }), "Me", 4);
    await changeNumber(manual.locator(".phone-manual-section").filter({ hasText: "Set 2 (final)" }), "Opponent", 6);
    const currentSet = manual.locator(".phone-manual-section").filter({ hasText: "Current Set (Set 3 — in progress)" });
    await changeNumber(currentSet, "Games — Me", 6);
    await changeNumber(currentSet, "Games — Opp", 4);
    check(await (await button(manual, "Save Match")).isDisabled(),
      "a completed third regular set in full-final-set format must not be saved as in progress");
    await (await button(root.locator(".phone-nav"), "Cancel")).click();
    await (await button(root, "Manual match entry")).click();
    const validManual = root.locator(".phone-manual");
    await (await button(validManual, /^Increase Completed sets:/)).click();
    const validFirstSet = validManual.locator(".phone-manual-section").filter({ hasText: "Set 1 (final)" });
    await changeNumber(validFirstSet, "Me", 6);
    await changeNumber(validFirstSet, "Opponent", 4);
    await (await button(validManual, "Save Match")).click();
    const manualRecord = (await state(mobile.page)).records.find(record => !record.endTime && record.sets.some(set => set.gamesMe === 6));
    check(manualRecord, "valid manual entry should create an in-progress archive record");
    progress("manual score validation and full-final-set regression passed");

    // Archive action menu and delete cancellation preserve both archive
    // contents and row visibility.
    const beforeDelete = await state(mobile.page);
    const row = root.locator(".phone-match-wrap").filter({ hasText: /In Progress|Score|Stats/ }).first();
    await row.getByRole("button", { name: /Match actions/ }).click();
    const actionsDialog = root.locator(".phone-dialog");
    await (await button(actionsDialog, "Delete Permanently")).click();
    const confirmDialog = root.locator(".phone-dialog");
    await confirmDialog.getByRole("heading", { name: "Delete permanently?", exact: true }).waitFor({ state: "visible", timeout: TIMEOUT });
    await (await button(confirmDialog, "Cancel")).click();
    const afterDeleteCancel = await state(mobile.page);
    check(afterDeleteCancel.records.length === beforeDelete.records.length && afterDeleteCancel.records.some(r => r.id === manualRecord.id),
      "canceling permanent deletion should preserve archive records");

    // Cloud restore is simulated in the demo controls. Removing local archive
    // copies before restoring proves the restore action repopulates records.
    const experiments = root.locator(".phone-experiments");
    await experiments.locator("summary").click();
    await (await button(experiments, "Simulate cloud backup")).click();
    await mobile.page.waitForTimeout(750);
    const backedUpCount = (await state(mobile.page)).records.length;
    check(backedUpCount > 0, "simulated cloud backup should preserve archive data");
    await mobile.page.evaluate(() => window.DeuceMatePhone.replaceRecords([]));
    await (await button(experiments, "Preview cloud restore")).click();
    const restoreDialog = root.locator(".phone-dialog");
    await restoreDialog.getByRole("heading", { name: "Restore matches from iCloud?", exact: true }).waitFor({ state: "visible", timeout: TIMEOUT });
    await (await button(restoreDialog, "Restore")).click();
    check((await state(mobile.page)).records.length >= backedUpCount, "confirming cloud restore should restore backed-up matches");
    progress("archive delete cancellation and simulated cloud restore passed");

    // Use a valid exported-shaped record for merge/replace. Merge retains
    // current IDs and adds the import; dismissing the native replacement
    // confirmation leaves it untouched; accepting replacement installs only
    // the supplied record.
    const current = await state(mobile.page);
    const imported = JSON.parse(JSON.stringify(current.records[0]));
    imported.id = "extended-import-record";
    imported.startTime = Date.now() - 1234;
    const payload = { format: "deucemate-browser-demo-archive", version: 1, exportedAt: new Date().toISOString(), records: [imported] };
    await (await button(root, "Settings")).click();
    await importPayload(mobile.page, payload, "extended-archive.json");
    await (await button(root.locator(".phone-dialog"), "Merge")).click();
    check((await state(mobile.page)).records.some(record => record.id === imported.id), "merge import should add the incoming record");
    const beforeReplaceCancel = (await state(mobile.page)).records.length;
    await importPayload(mobile.page, payload, "extended-archive.json");
    await clickReplaceAndHandleDialog(mobile.page,
      await button(root.locator(".phone-dialog"), "Replace Archive"), false);
    check((await state(mobile.page)).records.length === beforeReplaceCancel, "canceling replace confirmation should preserve existing archive");
    check(!(await root.locator(".phone-dialog").isVisible()), "canceling archive replacement should dismiss the in-phone alert");
    await importPayload(mobile.page, payload, "extended-archive.json");
    await clickReplaceAndHandleDialog(mobile.page,
      await button(root.locator(".phone-dialog"), "Replace Archive"), true);
    const replaced = await state(mobile.page);
    check(replaced.records.length === 1 && replaced.records[0].id === imported.id, "confirmed replacement should install only imported records");
    progress("manual archive merge, replace cancellation, and replacement passed");

    // Export the manual archive and verify its versioned demo format.
    const archiveDownloadWait = mobile.page.waitForEvent("download", { timeout: TIMEOUT });
    await (await button(root, "Export Match Archive")).click();
    const archiveConsent = root.locator(".phone-dialog");
    if (await archiveConsent.isVisible()) {
      await (await button(archiveConsent, "Export")).click();
    }
    const archiveFile = await archiveDownloadWait;
    const archivePath = path.join(os.tmpdir(), `deucemate-extended-archive-${Date.now()}.json`);
    await archiveFile.saveAs(archivePath);
    const archive = JSON.parse(fs.readFileSync(archivePath, "utf8"));
    fs.rmSync(archivePath, { force: true });
    check(archive && archive.format === "deucemate-browser-demo-archive" && archive.records.length === 1,
      "manual archive export should produce the versioned browser-demo JSON format");
    progress("manual archive export passed");

    // Desktop responsive view screenshot and overflow assertion.
    const desktop = await remember({ viewport: { width: 1440, height: 1000 } });
    const desktopRoot = await openDemo(desktop.page);
    await desktop.page.screenshot({ path: path.join(SCREENSHOT_DIR, "iphone-demo-desktop.png"), fullPage: true });
    const bounds = await desktopRoot.evaluate(el => ({ client: el.clientWidth, scroll: el.scrollWidth }));
    check(bounds.scroll <= bounds.client + 1, `desktop demo should not overflow horizontally: ${JSON.stringify(bounds)}`);
    progress("desktop screenshot and overflow check passed");

    check(errors.length === 0, `browser errors: ${errors.join("; ")}`);
    process.stdout.write(`Extended iPhone demo browser QA passed. Screenshots: ${SCREENSHOT_DIR}\n`);
  } finally {
    for (const context of contexts) await context.close();
    await browser.close();
  }
}

main().catch(error => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
