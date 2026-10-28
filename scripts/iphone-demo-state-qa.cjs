#!/usr/bin/env node
/*
 * Focused Playwright checks for iPhone demo archive, connectivity, and input
 * state transitions. Each scenario gets a fresh browser context so storage and
 * simulator state cannot leak between cases.
 *
 *   PLAYWRIGHT_MODULE=/path/to/playwright node scripts/iphone-demo-state-qa.cjs
 */
"use strict";

const assert = require("node:assert/strict");
const path = require("node:path");
const { pathToFileURL } = require("node:url");

const { chromium, webkit } = require(process.env.PLAYWRIGHT_MODULE || "playwright");
const DEMO_URL = process.env.PLAYWRIGHT_URL || pathToFileURL(path.resolve(__dirname, "../docs/website/try.html")).href;
const TIMEOUT = Number(process.env.PLAYWRIGHT_TIMEOUT || 4000);

function check(value, message) { assert.ok(value, message); }
function pass(message) { process.stdout.write(`[state QA] ${message}\n`); }

async function fresh(browser, options = {}) {
  const context = await browser.newContext({
    viewport: { width: 390, height: 844 }, deviceScaleFactor: 1,
    isMobile: true, hasTouch: true
  });
  if (options.corruptStorage != null) {
    await context.addInitScript(value => {
      if (sessionStorage.getItem("__deucemate_state_qa_seeded_corrupt_storage") !== "1") {
        localStorage.setItem("deucemate-browser-companion-v1", value);
        sessionStorage.setItem("__deucemate_state_qa_seeded_corrupt_storage", "1");
      }
    }, options.corruptStorage);
  }
  const page = await context.newPage();
  page.setDefaultTimeout(TIMEOUT);
  await page.goto(DEMO_URL, { waitUntil: "domcontentloaded", timeout: TIMEOUT });
  const root = page.locator("#iphone-demo");
  await root.waitFor({ state: "visible", timeout: TIMEOUT });
  await page.waitForFunction(() => !!window.DeuceMatePhone, null, { timeout: TIMEOUT });
  return { context, page, root };
}

async function close(caseContext) { await caseContext.context.close(); }
async function click(scope, name) {
  const target = scope.getByRole("button", { name, exact: typeof name === "string" }).first();
  await target.waitFor({ state: "visible", timeout: TIMEOUT });
  // Demo-only live controls are visually hidden (the native scoreboard has none) but keyboard-reachable.
  if (await target.evaluate(el => !!el.closest(".phone-live-extras"))) { await target.focus(); await target.press("Enter"); return; }
  await target.click();
}
async function expandControls(root) {
  const controls = root.locator(".phone-experiments");
  if (!(await controls.locator("summary").evaluate(el => el.parentElement.open))) {
    await controls.locator("summary").click();
  }
  return controls;
}
async function idState(page) {
  return page.evaluate(() => ({
    phone: window.DeuceMatePhone.records().map(record => record.id),
    watch: window.DeuceMateShell.history.map(record => record.id),
    connection: { ...window.DeuceMatePhone.connection }
  }));
}
async function swipeLeft(locator, amount) {
  await locator.scrollIntoViewIfNeeded();
  const box = await locator.boundingBox();
  check(box, "swipe row should have a visible bounding box");
  const x = box.x + Math.min(box.width - 30, Math.max(100, box.width * 0.72));
  const y = box.y + box.height / 2;
  const page = locator.page();
  await page.mouse.move(x, y);
  await page.mouse.down();
  await page.mouse.move(x - amount, y, { steps: 8 });
  await page.mouse.up();
}

async function testFullSwipeRetainsPhoneCopy(browser) {
  const c = await fresh(browser);
  try {
    const before = await idState(c.page);
    const swipeActions = c.root.locator(".phone-swipe-action");
    check(await swipeActions.count() > 0, "seeded archive must expose a both-device swipe action");
    const id = await swipeActions.first().evaluate(el => el.closest(".phone-match-wrap").dataset.matchId);
    check(id, "seeded archive must include a match stored on both devices");
    const row = c.root.locator(`.phone-match-wrap[data-match-id="${id}"]`);
    await swipeLeft(row, 260);
    await c.page.waitForTimeout(120);
    const after = await idState(c.page);
    check(after.phone.includes(id), "full swipe must retain the iPhone archive copy");
    check(!after.watch.includes(id), "full swipe must remove only the Watch copy");
    check(await row.isVisible(), "full swipe must stay on the archive instead of opening match details");
    pass("full swipe removes Watch copy, retains phone row, and does not navigate");
  } finally { await close(c); }
}

async function testRevealedActionAndPhoneOnly(browser) {
  const c = await fresh(browser);
  try {
    const before = await idState(c.page);
    const swipeActions = c.root.locator(".phone-swipe-action");
    check(await swipeActions.count() > 0, "seeded archive must expose a both-device swipe action");
    const id = await swipeActions.first().evaluate(el => el.closest(".phone-match-wrap").dataset.matchId);
    check(id, "seeded archive must include a both-device record");
    const row = c.root.locator(`.phone-match-wrap[data-match-id="${id}"]`);
    await swipeLeft(row, 85);
    const remove = row.getByRole("button", { name: "Remove from Watch; keep the iPhone copy", exact: true });
    await remove.waitFor({ state: "visible", timeout: TIMEOUT });
    const menu = row.getByRole("button", { name: /Match actions/ });
    await menu.focus();
    await c.page.keyboard.press("Shift+Tab");
    await c.page.keyboard.press("Shift+Tab");
    check(await remove.evaluate(el => document.activeElement === el), "revealed remove action must be keyboard reachable");
    await c.page.keyboard.press("Enter");
    await c.page.waitForFunction(matchID => !window.DeuceMateShell.history.some(record => record.id === matchID), id, { timeout: TIMEOUT });

    const phoneOnlyID = await c.page.evaluate(() => {
      const phone = window.DeuceMatePhone.records();
      const watch = window.DeuceMateShell.history;
      return phone.find(record => !watch.some(item => item.id === record.id))?.id || null;
    });
    check(phoneOnlyID, "a phone-only match should remain after removing the first Watch copy");
    const phoneOnly = c.root.locator(`.phone-match-wrap[data-match-id="${phoneOnlyID}"]`);
    check(await phoneOnly.locator(".phone-swipe-action").count() === 0, "phone-only row must not offer Remove from Watch swipe");
    await phoneOnly.getByRole("button", { name: /Match actions/ }).click();
    const dialog = c.root.locator(".phone-dialog");
    check(await dialog.getByRole("button", { name: "Remove from Watch", exact: true }).count() === 0,
      "phone-only action menu must not offer Remove from Watch");
    check(await dialog.getByRole("button", { name: "Sync to Watch", exact: true }).count() === 1,
      "phone-only action menu should offer Sync to Watch");
    pass("revealed Remove from Watch is keyboard reachable; phone-only rows offer Sync to Watch only");
  } finally { await close(c); }
}

async function testWatchOnlyDeferredUntilExplicitSync(browser) {
  const c = await fresh(browser);
  try {
    const controls = await expandControls(c.root);
    const before = await idState(c.page);
    await click(controls, "Show a Watch-only match");
    const chosen = await c.page.evaluate(() => {
      const phone = window.DeuceMatePhone.records();
      const watch = window.DeuceMateShell.history;
      return watch.find(record => !phone.some(item => item.id === record.id))?.id || null;
    });
    check(chosen, "demo control should create a Watch-only row");
    await c.page.evaluate(() => window.DeuceMatePhone.setSetting("track", !window.DeuceMatePhone.settings.track));
    await c.page.waitForTimeout(1700);
    let after = await idState(c.page);
    check(!after.phone.includes(chosen) && after.watch.includes(chosen),
      "automatic 750 ms refreshes must leave the Watch-only record on Watch");
    await click(c.root.locator(".phone-body"), /Sync Now/);
    after = await idState(c.page);
    check(after.phone.includes(chosen), "explicit Sync Now should copy the Watch-only record to iPhone");
    check(before.phone.length > 0, "fresh context should begin with a populated iPhone archive");
    pass("Watch-only sample persists across interval refresh and appears after explicit Sync Now");
  } finally { await close(c); }
}

async function testStorageAwareDeleteSwipe(browser) {
  const c = await fresh(browser);
  try {
    const id = await c.root.locator('.phone-swipe-action').first().evaluate(el => el.closest('.phone-match-wrap').dataset.matchId);
    const row = c.root.locator(`.phone-match-wrap[data-match-id="${id}"]`), dialog = c.root.locator('.phone-dialog');
    await swipeLeft(row, 85);
    await click(row, 'Delete match; confirmation required');
    check((await dialog.innerText()).includes('from iPhone and Apple Watch'), 'both-device delete must name both copies');
    await click(dialog, 'Cancel');
    check((await idState(c.page)).phone.includes(id) && (await idState(c.page)).watch.includes(id), 'cancelled swipe deletion must retain both copies');
    await row.getByRole('button', {name: /Match actions/}).click();
    await click(dialog, 'Remove from Watch');
    await swipeLeft(row, 260);
    check(!(await dialog.isVisible()) && (await idState(c.page)).phone.includes(id), 'phone-only full swipe must reveal Delete without executing it');
    await click(row, 'Delete match; confirmation required');
    check((await dialog.innerText()).includes('from iPhone for good') && !(await dialog.innerText()).includes('Apple Watch'), 'phone-only deletion must identify its actual storage');
    await click(dialog, 'Cancel');
    check((await idState(c.page)).phone.includes(id), 'cancel must retain the phone-only copy');

    const controls = await expandControls(c.root);
    await click(controls, 'Show a Watch-only match');
    const watchID = await c.page.evaluate(() => window.DeuceMateShell.history.find(r => !window.DeuceMatePhone.records().some(p => p.id === r.id)).id);
    const watchRow = c.root.locator(`.phone-match-wrap[data-match-id="${watchID}"]`);
    await swipeLeft(watchRow, 260);
    check(!(await dialog.isVisible()) && (await idState(c.page)).watch.includes(watchID), 'Watch-only full swipe must never permanently delete');
    await click(watchRow, 'Delete match; confirmation required');
    await click(dialog, 'Delete Permanently');
    check(!(await idState(c.page)).watch.includes(watchID), 'confirmed Watch-only deletion must remove its Watch copy');
    await click(c.root.locator('.phone-body'), /Sync Now/);
    check(!(await idState(c.page)).phone.includes(watchID), 'deleted Watch-only record must not return during sync');
    pass('all storage types expose confirmed Delete swipe; only recoverable Watch removal permits full-swipe execution');
  } finally { await close(c); }
}

async function testConnectivityAndFailureRetainCache(browser) {
  const c = await fresh(browser);
  try {
    const controls = await expandControls(c.root);
    const before = await idState(c.page);
    check(before.phone.length > 0, "fresh context should have cached iPhone matches");
    const activation = controls.getByLabel("Watch activation state");
    await activation.selectOption("connecting");
    await c.root.getByText("Your iPhone archive stays available while Watch connectivity starts.").waitFor({ state: "visible", timeout: TIMEOUT });
    await activation.selectOption("unavailable");
    await c.root.getByText("Watch connectivity couldn't be started.").first().waitFor({ state: "visible", timeout: TIMEOUT });

    await controls.getByLabel("Sync pending").check();
    await c.root.getByText("Syncing with Apple Watch… Your saved iPhone matches remain available.").waitFor({ state: "visible", timeout: TIMEOUT });
    await click(c.root.locator(".phone-body"), /Sync Now/);
    await c.root.getByText("Sync pending. The iPhone archive remains available.").waitFor({ state: "visible", timeout: TIMEOUT });
    await controls.getByLabel("Sync pending").uncheck();
    await controls.getByLabel("Simulate sync failure").check();
    await c.root.getByText("The latest Watch sync failed. Matches already saved on this iPhone are still available.").waitFor({ state: "visible", timeout: TIMEOUT });
    await click(c.root.locator(".phone-body"), /Sync Now/);
    await c.root.getByText("Sync unavailable. The iPhone archive is retained.").waitFor({ state: "visible", timeout: TIMEOUT });
    await controls.getByLabel("Simulate saved archive read failure").check();
    await c.root.getByText("Any cached iPhone matches remain visible and have not been overwritten.").waitFor({ state: "visible", timeout: TIMEOUT });
    const after = await idState(c.page);
    check(after.phone.length === before.phone.length && before.phone.every(id => after.phone.includes(id)),
      "connecting, activation failure, pending/failing sync, and archive-read failure must retain phone matches");
    check(await c.root.locator(".phone-match-wrap").count() > 0, "cached archive rows should stay visible during failures");
    await controls.getByLabel("Watch paired", {exact: true}).uncheck();
    check(await c.root.locator(".phone-match-wrap").count() > 0, "unpaired badge check needs a populated iPhone archive");
    check(await c.root.locator(".phone-storage-badge").count() === 0, "native archive hides device-storage badges while no Watch is paired");
    await controls.getByLabel("Watch paired", {exact: true}).check();
    check(await c.root.locator(".phone-storage-badge").count() > 0, "pairing restores device-storage indicators on saved rows");
    pass("connecting, unavailable, pending/failing sync, and unreadable archive retain cached records");
  } finally { await close(c); }
}

async function testSettingsSyncAndCloudGuide(browser) {
  const c = await fresh(browser);
  try {
    await click(c.root.locator('.phone-body'), '☁ iCloud unavailable — stored on iPhone ›');
    const dialog = c.root.locator('.phone-dialog');
    await dialog.getByRole('heading', {name: 'iCloud Drive Unavailable', exact: true}).waitFor();
    check(await dialog.locator('li').count() === 4, 'iCloud guide must retain all four native setup steps');
    check((await dialog.innerText()).includes('but not recorded heart rate, steps, distance, or calories'), 'guide must explain automatic restore Health exclusions');
    const pages = c.context.pages().length;
    await click(dialog, 'Open Settings');
    check((await dialog.innerText()).includes('Would open iPhone Settings'), 'device-settings handoff must be visibly simulated');
    check(c.context.pages().length === pages, 'iCloud guide must not navigate to an external service');
    await click(dialog, 'Done');

    const controls = await expandControls(c.root);
    await click(controls, 'Show a Watch-only match');
    const watchOnlyID = await c.page.evaluate(() => window.DeuceMateShell.history.find(r => !window.DeuceMatePhone.records().some(p => p.id === r.id)).id);
    await click(c.root.locator('.phone-nav'), 'Settings');
    await click(c.root.locator('.phone-body'), 'Sync Now');
    check((await idState(c.page)).phone.includes(watchOnlyID), 'Settings Sync Now must actually copy Watch-only data to iPhone');
    check((await c.root.locator('.phone-notice').innerText()).includes('Synced with'), 'successful sync should report completion');

    await click(controls, 'Show a Watch-only match');
    await controls.getByLabel('Simulate sync failure').check();
    const before = await idState(c.page);
    await click(c.root.locator('.phone-nav'), 'Settings');
    await click(c.root.locator('.phone-body'), 'Sync Now');
    check((await c.root.locator('.phone-notice').innerText()).includes('Sync unavailable'), 'Settings sync must never claim success after failure');
    check(JSON.stringify((await idState(c.page)).phone) === JSON.stringify(before.phone), 'failed settings sync must preserve the archive');
    await controls.getByLabel('Watch activation state').selectOption('unavailable');
    check(await c.root.locator('.phone-body').getByRole('button', {name: 'Sync Now', exact: true}).isDisabled(), 'settings sync must be disabled until Watch activation succeeds');
    await controls.getByLabel('Watch activation state').selectOption('ready');
    await controls.getByLabel('Sync pending').check();
    check(await c.root.locator('.phone-body').getByRole('button', {name: 'Syncing…', exact: true}).isDisabled(), 'pending settings sync must be disabled');
    await controls.getByLabel('Sync pending').uncheck();

    await c.root.getByLabel('Override Max HR', {exact: true}).check();
    check(await c.root.getByLabel('Birth Year', {exact: true}).isDisabled(), 'manual max HR must disable the native age-derived control');
    check(await c.root.getByText(/^Max HR \(default\):/).evaluate(el => getComputedStyle(el).opacity === '0.45'), 'age-derived max HR must dim while overridden');
    await c.root.getByLabel('Override Max HR', {exact: true}).uncheck();
    check(await c.root.getByLabel('Birth Year', {exact: true}).isEnabled(), 'turning off max HR override restores Birth Year');
    pass('Settings sync copies data, rejects failures, respects activation/pending; iCloud guide and override controls match native');
  } finally { await close(c); }
}

async function testCorruptStorageNotOverwritten(browser) {
  const corrupt = "{ this saved archive is deliberately invalid";
  const c = await fresh(browser, { corruptStorage: corrupt });
  try {
    await c.root.getByText("The saved browser archive could not be read.").waitFor({ state: "visible", timeout: TIMEOUT });
    const afterBoot = await c.page.evaluate(() => localStorage.getItem("deucemate-browser-companion-v1"));
    check(afterBoot === corrupt, "corrupt localStorage payload must survive the initial archive read unchanged");
    await c.page.reload({ waitUntil: "domcontentloaded", timeout: TIMEOUT });
    await c.page.waitForFunction(() => !!window.DeuceMatePhone, null, { timeout: TIMEOUT });
    await c.root.getByText("The saved browser archive could not be read.").waitFor({ state: "visible", timeout: TIMEOUT });
    const afterReload = await c.page.evaluate(() => localStorage.getItem("deucemate-browser-companion-v1"));
    check(afterReload === corrupt, "corrupt localStorage payload must survive reload unchanged");
    await click(c.root.locator(".phone-body"), /Sync Now/);
    const afterSync = await c.page.evaluate(() => localStorage.getItem("deucemate-browser-companion-v1"));
    check(afterSync === corrupt, "sync after a corrupt read must not overwrite the saved payload");
    pass("genuinely corrupt localStorage remains untouched after reload and Sync Now");
  } finally { await close(c); }
}

async function testLiveDisconnectedInputAndPendingControls(browser) {
  const c = await fresh(browser);
  try {
    await c.page.evaluate(() => {
      const shell = window.DeuceMateShell, phone = window.DeuceMatePhone;
      phone.setSetting("track", false);
      phone.setSetting("iPhoneInput", true);
      shell.liveId = "state-qa-live";
      shell.matchPhase = "play";
      shell.api.start({ format: "standard", server: "me", tracking: false });
      shell.push({ id: "match" });
      phone.navigate("live");
    });
    const scoreboard = c.root.locator(".phone-scoreboard");
    await scoreboard.waitFor({ state: "visible", timeout: TIMEOUT });
    const controls = await expandControls(c.root);
    await scoreboard.focus();
    const pointsBeforeKeyboard = await c.page.evaluate(() => window.DeuceMateShell.api.stateRef().currentPointsMe);
    await c.page.keyboard.press("ArrowUp");
    await c.page.waitForFunction(previous => window.DeuceMateShell.api.stateRef().currentPointsMe === previous + 1,
      pointsBeforeKeyboard, { timeout: TIMEOUT });
    check(await scoreboard.evaluate(el => document.activeElement === el), "scoreboard keyboard focus should survive its score refresh");
    await c.page.keyboard.press("ArrowUp");
    await c.page.waitForFunction(previous => window.DeuceMateShell.api.stateRef().currentPointsMe === previous + 2,
      pointsBeforeKeyboard, { timeout: TIMEOUT });
    pass("consecutive ArrowUp presses each score exactly one point");
    await scoreboard.scrollIntoViewIfNeeded();
    const courtBox = await scoreboard.boundingBox();
    const x = courtBox.x + courtBox.width / 2, y = courtBox.y + courtBox.height / 2;
    await c.page.mouse.move(x, y);
    await c.page.mouse.down();
    await c.page.evaluate(() => window.DeuceMatePhone.render());
    await c.page.mouse.move(x, y - 70, {steps: 4});
    await c.page.mouse.up();
    await c.page.waitForFunction(previous => window.DeuceMateShell.api.stateRef().currentPointsMe === previous + 3,
      pointsBeforeKeyboard, {timeout: TIMEOUT});
    pass('score swipe survives a Watch-driven redraw between press and release');

    await controls.getByLabel("Watch reachable").uncheck();
    await scoreboard.focus();
    const before = await c.page.evaluate(() => JSON.stringify(window.DeuceMateShell.api.stateRef()));
    await c.page.keyboard.press("ArrowUp");
    await c.page.waitForTimeout(100);
    const afterBlocked = await c.page.evaluate(() => ({
      state: JSON.stringify(window.DeuceMateShell.api.stateRef()),
      phone: JSON.stringify(window.DeuceMatePhone.liveRecord().resume.state),
      disabled: Array.from(document.querySelectorAll(".phone-live-controls button")).every(button => button.disabled)
    }));
    check(afterBlocked.state === before, "keyboard score command must not change the Watch scorer while unreachable");
    check(afterBlocked.state === afterBlocked.phone, "phone snapshot and Watch scorer must remain the same authoritative state");
    check(afterBlocked.disabled, "live command controls must be disabled while unreachable");

    await controls.getByLabel("Watch reachable").check();
    await c.page.evaluate(() => window.DeuceMatePhone.setSetting("track", true));
    await click(c.root.locator(".phone-live-controls"), "↑ Me");
    await c.page.waitForFunction(() => !!window.DeuceMateShell.api.phoneState().pending, null, { timeout: TIMEOUT });
    await controls.getByLabel("Watch reachable").uncheck();
    const pending = c.root.locator(".phone-live");
    const outcome = pending.getByRole("button", { name: "Winner", exact: true });
    check(await outcome.isDisabled(), "pending outcome selection must disable while Watch is unreachable");
    const state = await c.page.evaluate(() => ({
      watch: JSON.stringify(window.DeuceMateShell.api.stateRef()),
      phone: JSON.stringify(window.DeuceMatePhone.liveRecord().resume.state),
      hasPending: !!window.DeuceMateShell.api.phoneState().pending
    }));
    check(state.watch === state.phone && state.hasPending, "pending categorization must still reflect the same Watch-owned match");
    pass("disconnected live input is inert; phone/watch snapshots agree and pending choices disable");
  } finally { await close(c); }
}

async function testBlankManualDate(browser) {
  const c = await fresh(browser);
  try {
    await click(c.root.locator(".phone-nav"), "Manual match entry");
    const manual = c.root.locator(".phone-manual");
    await manual.waitFor({ state: "visible", timeout: TIMEOUT });
    const date = manual.locator('input[type="date"]');
    await date.fill("");
    const save = manual.getByRole("button", { name: "Save Match", exact: true });
    check(await save.isDisabled(), "blank Started date must disable Save Match");
    pass("blank manual-entry date cannot save an invalid timestamp");
  } finally { await close(c); }
}

async function testManualLeavingTiebreak(browser) {
  const c = await fresh(browser);
  try {
    await click(c.root.locator('.phone-nav'), 'Manual match entry');
    const manual = c.root.locator('.phone-manual');
    await manual.getByRole('spinbutton', {name: 'Games — Me', exact: true}).fill('6');
    await manual.getByRole('spinbutton', {name: 'Games — Me', exact: true}).press('Tab');
    await manual.getByRole('spinbutton', {name: 'Games — Opp', exact: true}).fill('6');
    await manual.getByRole('spinbutton', {name: 'Games — Opp', exact: true}).press('Tab');
    await manual.getByLabel('In set tiebreak', {exact: true}).check();
    check(await manual.getByText('Current Game', {exact: true}).count() === 0, 'tiebreak must replace regular game controls');
    await manual.getByRole('spinbutton', {name: 'Games — Me', exact: true}).fill('5');
    await manual.getByRole('spinbutton', {name: 'Games — Me', exact: true}).press('Tab');
    check(await manual.getByLabel('In set tiebreak', {exact: true}).count() === 0, 'leaving 6–6 must remove tiebreak option');
    check(await manual.getByText('Current Game', {exact: true}).count() === 1, 'leaving 6–6 must restore regular game controls');
    await click(manual, 'Save Match');
    const saved = await c.page.evaluate(() => window.DeuceMatePhone.records()[0]);
    check(saved.sets[0].gamesMe === 5 && saved.sets[0].gamesOpponent === 6 && !saved.sets[0].isTieBreak, 'saved manual score must remain the visible 5–6 regular set');
    pass('manual tiebreak clears when leaving 6–6 and saves the visible regular score');
  } finally { await close(c); }
}

async function testEmptyArchiveAndPermanentDelete(browser) {
  const c = await fresh(browser);
  try {
    const id = await c.root.locator('.phone-match-wrap').first().getAttribute('data-match-id');
    await click(c.root.locator(`.phone-match-wrap[data-match-id="${id}"]`), /Match actions/);
    await click(c.root.locator('.phone-dialog'), 'Delete Permanently');
    await click(c.root.locator('.phone-dialog'), 'Delete Permanently');
    await c.page.reload();
    await c.page.waitForFunction(() => !!window.DeuceMatePhone);
    await click(c.root.locator('.phone-body'), /Sync Now/);
    const deleted = await idState(c.page);
    check(!deleted.phone.includes(id) && !deleted.watch.includes(id), 'permanent deletion must survive reload and sync on both devices');
    await c.page.evaluate(() => {
      window.DeuceMateShell.history = [];
      window.DeuceMatePhone.connection.paired = false;
      window.DeuceMatePhone.replaceRecords([]);
    });
    await c.root.getByRole('heading', {name: 'No Apple Watch Paired'}).waitFor();
    await click(c.root, 'Enter a match manually');
    check(await c.root.locator('.phone-manual').isVisible(), 'empty unpaired archive must still offer manual entry');
    await click(c.root.locator('.phone-nav'), 'Cancel');
    await c.page.evaluate(() => {
      window.DeuceMatePhone.connection.paired = true;
      window.DeuceMatePhone.render();
    });
    await c.root.getByRole('heading', {name: 'No Matches Yet'}).waitFor();
    check(await c.root.getByRole('button', {name: 'Enter a match manually'}).isVisible(), 'paired empty archive must still offer manual entry');
    const controls = await expandControls(c.root);
    await click(controls, 'Reset demo');
    await Promise.all([
      c.page.waitForEvent('load'),
      click(c.root.locator('.phone-dialog'), 'Reset demo')
    ]);
    await c.page.waitForFunction(() => !!window.DeuceMatePhone);
    const reset = await idState(c.page);
    check(reset.phone.includes(id) && reset.watch.includes(id), 'Reset must restore sample records rather than repersisting the deleted/empty archive on pagehide');
    pass('permanent delete survives reload/sync; empty archives retain manual entry; Reset restores seed data');
  } finally { await close(c); }
}

async function testTrendsControls(browser) {
  const c = await fresh(browser);
  try {
    await click(c.root, /Performance Trends/);
    const trends = c.root.locator('.pr-trends');
    const errors = trends.locator('[data-group="Errors"]');
    const rateChart = await errors.locator('svg').innerHTML();
    await click(trends, 'Count');
    check(await errors.locator('svg').innerHTML() !== rateChart, 'Rate/Count must change plotted values');
    await click(trends, 'Rate');
    const serving = trends.locator('[data-group="Serve & Return"]');
    const serveIn = await serving.locator('svg').innerHTML();
    await click(serving, 'Serves Win');
    check(await serving.locator('svg').innerHTML() !== serveIn, 'Serves Win must plot different data from Serves In');
    await click(serving, 'Returns Win');
    check((await serving.innerText()).includes('Return Win'), 'Returns Win must show return metrics');
    const depth = trends.locator('[data-group="Rally Depth"]');
    check(await depth.locator('svg polygon').count() > 0, 'Rally Mix should render stacked coverage');
    await click(depth, 'Win Rate');
    check(await depth.locator('svg polygon').count() === 0 && await depth.locator('svg circle').count() > 0,
      'Rally Win Rate should render win-rate points instead of a mix');
    const side = trends.locator('[data-group="Rally Depth — By Service"]');
    const onServe = await side.locator('svg').innerHTML();
    await click(side, 'On Returns');
    check(await side.locator('svg').innerHTML() !== onServe, 'On Return must change service-side rally data');
    await trends.getByRole('group', {name: 'Match type', exact: true}).getByRole('button', {name: 'Doubles', exact: true}).click();
    check((await trends.innerText()).includes('Trends needs at least 3'), 'restrictive filters must show the minimum-match state');
    check(await trends.locator('.pr-trend-chart').count() === 0, 'insufficient matches must not produce misleading charts');
    await click(c.root, 'Back to Matches');
    await click(c.root.locator('.phone-nav'), 'Settings');
    await c.root.getByRole('checkbox', {name: 'Track point outcome', exact: true}).check();
    await click(c.root, 'Back to Matches');
    await click(c.root, /Performance Trends/);
    check(await trends.getByRole('group', {name: 'Match type', exact: true}).getByRole('button', {name: 'Doubles', exact: true}).getAttribute('aria-pressed') === 'true', 'Trends filters must survive independent shared-setting changes');
    pass('Trends Rate/Count, serving/rally controls, minimum coverage and independent filter persistence');
  } finally { await close(c); }
}

async function testTextExportsAndAIStub(browser) {
  const c = await fresh(browser);
  try {
    await c.root.locator('.phone-match-row').first().click();
    const groups = c.root.locator('.pr-export-group');
    async function exports() {
      if (await groups.first().isVisible()) return;
      await c.root.locator('.phone-experiments').evaluate(el => {el.open = true;});
      await click(c.root, 'Browser export tools');
    }
    const reports = [[], []];
    for (let side = 0; side < 2; side++) {
      for (const label of ['Summary Text', 'Full Match Text', 'AI Coaching Prompt']) {
        const waiting = c.page.waitForEvent('download');
        await exports();
        await click(groups.nth(side), label);
        if (await c.root.locator('.phone-dialog').isVisible()) await click(c.root.locator('.phone-dialog'), 'Share');
        const downloaded = await waiting;
        const stream = await downloaded.createReadStream();
        let content = '';
        for await (const chunk of stream) content += chunk.toString('utf8');
        check(content.includes('# DeuceMate Match Export'), `${label} must contain the match report`);
        check(content.includes('## Raw Point Data') === (label !== 'Summary Text'), `${label} must include the intended point-data scope`);
        if (label === 'AI Coaching Prompt') check(content.includes('You are an experienced recreational tennis coach'), 'AI export must contain a coaching prompt');
        check(downloaded.suggestedFilename().includes('-opponent') === (side === 1), 'text export filenames must identify the reader perspective');
        reports[side].push(content);
      }
    }
    reports[0].forEach((content, index) => check(content !== reports[1][index], 'each text export must reframe the selected perspective'));
    for (let side = 0; side < 2; side++) {
      const csvWaiting = c.page.waitForEvent('download');
      await exports();
      await click(groups.nth(side), 'CSV points');
      await click(c.root.locator('.phone-dialog'), 'Share');
      const csv = await csvWaiting;
      const stream = await csv.createReadStream();
      let csvText = '';
      for await (const chunk of stream) csvText += chunk.toString('utf8');
      check(csv.suggestedFilename().endsWith('.csv') && csvText.includes('Recorder HR BPM') && csvText.split('\r\n').length > 2,
        'CSV export must contain point rows and measurement columns');
      await exports();
      await click(groups.nth(side), 'Preview report');
      await click(c.root.locator('.phone-dialog'), 'Share');
      const preview = c.root.frameLocator('iframe[title="Interactive match report preview"]');
      await preview.getByRole('button', {name: 'Points', exact: true}).click();
      check(await preview.locator('.pt-row').count() > 0, 'in-app report preview must support interactive point history');
      await click(c.root.locator('.phone-dialog'), 'Done');
    }
    let canceledDownloads = 0;
    const observeDownload = () => canceledDownloads++;
    c.page.on('download', observeDownload);
    await exports();
    await click(groups.first(), 'Interactive HTML');
    await click(c.root.locator('.phone-dialog'), 'Cancel');
    await c.page.waitForTimeout(100);
    c.page.off('download', observeDownload);
    check(canceledDownloads === 0, 'Cancel on health disclosure must prevent the download');
    await click(c.root, 'Open AI Coach');
    await click(c.root.locator('.phone-dialog'), 'Continue');
    const before = {url: c.page.url(), pages: c.context.pages().length};
    await click(c.root.locator('.phone-dialog'), 'Open in ChatGPT');
    check((await c.root.locator('.phone-notice').innerText()).includes('Demo stub'), 'AI launch must clearly report a simulated hand-off');
    check(await c.root.locator('.phone-dialog .pr-ai-handoff').isVisible() &&
      (await c.root.locator('.phone-dialog .pr-ai-handoff').innerText()).includes('Would open ChatGPT here'),
      'AI hand-off feedback must be visible inside the open sheet');
    check(c.page.url() === before.url && c.context.pages().length === before.pages, 'AI stub must not open an external page');
    await c.page.evaluate(() => Object.defineProperty(navigator, 'clipboard', {
      configurable: true, value: {writeText: () => Promise.reject(new Error('QA clipboard unavailable'))}
    }));
    await click(c.root.locator('.phone-dialog'), 'Copy Prompt');
    const prompt = c.root.locator('textarea.pr-prompt');
    await c.page.waitForFunction(() => {
      const p = document.querySelector('textarea.pr-prompt');
      return p && document.activeElement === p && p.selectionEnd === p.value.length;
    });
    check((await prompt.inputValue()).includes('## Raw Point Data'), 'clipboard failure must leave the match prompt available for manual copying');
    await click(c.root.locator('.phone-dialog'), 'Done');
    const beforeFailure = await idState(c.page);
    await c.page.evaluate(() => { URL.createObjectURL = () => { throw new Error('Demo download unavailable'); }; });
    await exports();
    await click(groups.first(), 'Interactive HTML');
    await click(c.root.locator('.phone-dialog'), 'Share');
    check((await c.root.locator('.phone-notice').innerText()).includes('Export failed'), 'report download failure must be surfaced');
    await click(c.root, 'Back to Matches');
    await click(c.root.locator('.phone-nav'), 'Settings');
    await click(c.root, 'Export Match Archive');
    await click(c.root.locator('.phone-dialog'), 'Export');
    check((await c.root.locator('.phone-notice').innerText()).includes('Export failed'), 'archive export failure must not report success');
    check(JSON.stringify((await idState(c.page)).phone) === JSON.stringify(beforeFailure.phone), 'failed exports must retain every archive record');
    pass('both perspectives of all text exports, consent cancellation, AI stub and clipboard fallback');
  } finally { await close(c); }
}

async function testManualCancelDrawAndRestoreDecline(browser) {
  const c = await fresh(browser);
  try {
    await click(c.root.locator('.phone-nav'), 'Manual match entry');
    check(await c.root.locator('.phone-nav strong').innerText() === 'Manual Entry', 'manual toolbar must match native title');
    await c.root.locator('.phone-manual').getByLabel(/^Type/).selectOption('doubles');
    await click(c.root.locator('.phone-nav'), 'Cancel');
    await click(c.root.locator('.phone-nav'), 'Manual match entry');
    check(await c.root.locator('.phone-manual').getByLabel(/^Type/).inputValue() === 'singles', 'Cancel must discard manual-entry changes');
    await click(c.root.locator('.phone-manual'), 'Save Match');
    const id = await c.root.locator('.phone-match-wrap').first().getAttribute('data-match-id');
    await c.root.locator('.phone-match-row').first().click();
    check((await c.root.innerText()).includes('No Points to Graph'), 'manual score-only records must show the native empty graph');
    check((await c.root.innerText()).includes('No point-by-point statistics were recorded'), 'manual score-only records must explain missing tracking');
    check(await c.root.locator('.pr-tabs').count() === 0, 'manual records without points must not expose an empty Points tab');
    await click(c.root, 'End at Current Score');
    await click(c.root.locator('.phone-dialog'), 'End at Current Score');
    const ended = await c.page.evaluate(id => window.DeuceMatePhone.records().find(r => r.id === id), id);
    check(ended.endTime != null && ended.iWon === null, 'ending a tied manual score must save a completed draw');
    check(await c.root.locator('.phone-nav strong').innerText() === 'Matches', 'confirmed completion must dismiss native detail back to Matches');
    await c.root.locator(`.phone-match-wrap[data-match-id="${id}"] .phone-match-row`).click();
    check(await c.root.locator('.phone-nav strong').innerText() === 'Score Only Match', 'completed manual toolbar must use native score-only title');
    check(await c.root.getByRole('button', {name: 'End at Current Score', exact: true}).count() === 0, 'completed draw must no longer offer completion');
    await click(c.root, 'Back to Matches');
    const controls = await expandControls(c.root);
    await click(controls, 'Simulate cloud backup');
    await c.page.waitForFunction(() => JSON.parse(localStorage.getItem('deucemate-browser-companion-v1')).cloudState === 'uploaded');
    const backup = await c.page.evaluate(() => JSON.parse(localStorage.getItem('deucemate-browser-companion-v1')).cloudBackup);
    check(backup.every(r => !r.steps && !r.kcal && !r.distanceMeters && !r.distance && r.stats.every(p => p.heartRateBPM == null && p.stepsCumulative == null)),
      'automatic backup must exclude all simulated Health measurements');
    await c.page.evaluate(() => { window.DeuceMatePhone.connection.reachable = false; window.DeuceMatePhone.replaceRecords([]); });
    await click(controls, 'Preview cloud restore');
    await click(c.root.locator('.phone-dialog'), 'Not Now');
    check((await idState(c.page)).phone.length === 0, 'Not Now must leave the current archive untouched');
    await click(controls, 'Preview cloud restore');
    await click(c.root.locator('.phone-dialog'), 'Restore');
    check((await idState(c.page)).phone.length === backup.length, 'explicit Restore must recover the saved backup');
    pass('manual Cancel, score-only detail, tied completion, health-free backup and Restore/Not Now');
  } finally { await close(c); }
}

async function testAnnouncementSettings(browser) {
  const c = await fresh(browser);
  try {
    await c.page.evaluate(() => {
      window.__demoSpoken = [];
      Object.defineProperty(window, 'speechSynthesis', {configurable: true, value: {
        cancel() {}, speak(utterance) { window.__demoSpoken.push(utterance.text); }
      }});
    });
    await click(c.root.locator('.phone-nav'), 'Settings');
    await c.root.getByRole('checkbox', {name: 'Announce scores aloud on iPhone', exact: true}).check();
    const name = c.root.getByLabel('Your name', {exact: true});
    await name.fill('Alex');
    await name.dispatchEvent('change');
    await click(c.root, 'Test name on iPhone speaker');
    check((await c.page.evaluate(() => window.__demoSpoken)).includes('Hello Alex'), 'announcement test must use the entered player name');
    pass('announcement toggle, player name and spoken test route through browser speech');
  } finally { await close(c); }
}

async function testWatchToPhoneJourney(browser) {
  const c = await fresh(browser);
  try {
    const watch = c.page.locator('#watch-demo');
    await click(watch, /Start Match/);
    await click(watch, 'Warm Up Complete');
    await click(watch, 'Me');
    await click(c.root, /Live Scoreboard/);
    await watch.locator('[data-pt-me]').click();
    await c.page.waitForFunction(() => document.querySelector('#iphone-demo .phone-point-number').textContent === '15');
    const score = await c.page.evaluate(() => ({
      watch: JSON.stringify(window.DeuceMateShell.api.stateRef()),
      phone: JSON.stringify(window.DeuceMatePhone.liveRecord().resume.state)
    }));
    check(score.watch === score.phone, 'starting and scoring via the existing Watch UI must update the same match on iPhone');
    pass('Watch Start → warm-up → server → score updates the iPhone through visible UI');
  } finally { await close(c); }
}

async function testNarrowAndLandscapeScoreboard(browser) {
  const c = await fresh(browser);
  try {
    await c.page.setViewportSize({width: 320, height: 800});
    await c.page.evaluate(() => {
      const shell = window.DeuceMateShell;
      shell.liveId = 'state-qa-three-sets';
      shell.matchPhase = 'play';
      shell.api.start({format: 'bestOf3FullFinalSet', server: 'opponent', tracking: false});
      const s = shell.api.stateRef();
      s.sets = [
        {gamesMe: 6, gamesOpponent: 4, isTieBreak: false, tieBreakPointsMe: 0, tieBreakPointsOpponent: 0},
        {gamesMe: 4, gamesOpponent: 6, isTieBreak: false, tieBreakPointsMe: 0, tieBreakPointsOpponent: 0},
        {gamesMe: 5, gamesOpponent: 6, isTieBreak: false, tieBreakPointsMe: 0, tieBreakPointsOpponent: 0}
      ];
      s.currentPointsMe = 3; s.currentPointsOpponent = 3;
      shell.push({id: 'match'});
      window.DeuceMatePhone.navigate('live');
    });
    const rowBounds = await c.root.locator('.phone-score-row').evaluateAll(rows => rows.map(row => ({width: row.clientWidth, scroll: row.scrollWidth})));
    check(rowBounds.every(row => row.scroll <= row.width + 1), `three-set scoreboard must fit a 320px screen: ${JSON.stringify(rowBounds)}`);
    const frame = c.root.locator('.phone-frame');
    await frame.screenshot({path: '/tmp/deucemate-iphone-qa/iphone-narrow-live.png'});
    // Turning a touch device sideways enters the landscape scoreboard (the portrait Rotate button is hidden there).
    await c.page.setViewportSize({width: 844, height: 390});
    await c.page.waitForTimeout(200);
    check(await frame.evaluate(el => el.classList.contains('phone-landscape')), 'turning the device must enter the expanded scoreboard');
    const wideBounds = await c.root.locator('.phone-scoreboard').evaluate(el => ({width: el.clientWidth, scroll: el.scrollWidth}));
    check(wideBounds.scroll <= wideBounds.width + 1, 'landscape scoreboard must fit all three sets');
    const visibleRows = await frame.evaluate(el => {
      const outer = el.getBoundingClientRect();
      return Array.from(el.querySelectorAll('.phone-score-row')).every(row => {
        const r = row.getBoundingClientRect();
        return r.top >= outer.top && r.bottom <= outer.bottom;
      });
    });
    check(visibleRows, 'both landscape player rows must fit vertically in the visible frame');
    await frame.screenshot({path: '/tmp/deucemate-iphone-qa/iphone-landscape-live.png'});
    await click(c.root, 'Back to Matches');
    check(!(await frame.evaluate(el => el.classList.contains('phone-landscape'))), 'closing the live scoreboard must restore the portrait frame');
    pass('narrow three-set scoreboard, landscape mode and close-to-portrait behavior');
  } finally { await close(c); }
}

async function main() {
  const browserType = process.env.PLAYWRIGHT_BROWSER === "webkit" ? webkit : chromium;
  const browser = await browserType.launch({ headless: true });
  try {
    await testFullSwipeRetainsPhoneCopy(browser);
    await testRevealedActionAndPhoneOnly(browser);
    await testWatchOnlyDeferredUntilExplicitSync(browser);
    await testStorageAwareDeleteSwipe(browser);
    await testConnectivityAndFailureRetainCache(browser);
    await testSettingsSyncAndCloudGuide(browser);
    await testCorruptStorageNotOverwritten(browser);
    await testLiveDisconnectedInputAndPendingControls(browser);
    await testBlankManualDate(browser);
    await testManualLeavingTiebreak(browser);
    await testEmptyArchiveAndPermanentDelete(browser);
    await testTrendsControls(browser);
    await testTextExportsAndAIStub(browser);
    await testNarrowAndLandscapeScoreboard(browser);
    await testManualCancelDrawAndRestoreDecline(browser);
    await testAnnouncementSettings(browser);
    await testWatchToPhoneJourney(browser);
    pass("all state scenarios passed");
  } finally { await browser.close(); }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
