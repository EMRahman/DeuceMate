#!/usr/bin/env node
/* Browser QA for the 1.3.1 demo additions: swipe-vibration confirmation, the live
 * scoreboard's "Not confirmed by the Watch" message and its unreachable copy.
 *   PLAYWRIGHT_MODULE=/path/to/playwright [PLAYWRIGHT_BROWSER=webkit] node scripts/iphone-demo-131-qa.cjs */
"use strict";
const assert = require("node:assert/strict");
const path = require("node:path");
const { pathToFileURL } = require("node:url");
const pw = require(process.env.PLAYWRIGHT_MODULE || "playwright");
const URL = pathToFileURL(path.resolve(__dirname, "../docs/website/try.html")).href;

async function startLive(page) {
  await page.evaluate(() => {
    const sh = window.DeuceMateShell, P = window.DeuceMatePhone;
    P.setSetting("iPhoneInput", true); sh.liveId = "qa131"; sh.matchPhase = "play";
    sh.api.start({ format: "standard", server: "me", tracking: false }); sh.push({ id: "match" });
  });
}
(async () => {
  const browser = await pw[process.env.PLAYWRIGHT_BROWSER || "chromium"].launch();
  const page = await browser.newPage({ viewport: { width: 1300, height: 1000 } });
  const errors = []; page.on("pageerror", (e) => errors.push(String(e)));
  await page.addInitScript(() => { window.__vib = []; navigator.vibrate = (p) => { window.__vib.push(p); return true; }; });
  await page.goto(URL); await page.waitForTimeout(800);
  await startLive(page);

  // Swipe vibration: silent when off; win / lose / undo patterns when on, only for applied inputs.
  const screen = page.locator(".app-mode").first(); await screen.scrollIntoViewIfNeeded();
  const box = await screen.boundingBox();
  const swipe = async (dx, dy) => { const x = box.x + box.width / 2, y = box.y + box.height / 2; await page.mouse.move(x, y); await page.mouse.down(); await page.mouse.move(x + dx / 2, y + dy / 2); await page.mouse.move(x + dx, y + dy); await page.mouse.up(); await page.waitForTimeout(400); };
  await page.evaluate(() => { window.DeuceMateShell.settings.swipeVibration = false; });
  await swipe(0, -90);
  assert.deepEqual(await page.evaluate(() => window.__vib), [], "no vibration while the setting is off");
  await page.evaluate(() => { window.DeuceMateShell.settings.swipeVibration = true; });
  await swipe(0, -90); await swipe(0, 90); await swipe(-90, 0);
  assert.deepEqual(await page.evaluate(() => window.__vib), [[30], [20, 40, 20], [12]], "win / lose / undo haptic patterns");
  process.stdout.write("[1.3.1 QA] swipe vibration passed\n");

  // Live scoreboard messages.
  await page.evaluate(() => window.DeuceMatePhone.navigate("live")); await page.waitForTimeout(400);
  const status = () => page.evaluate(() => document.querySelector(".phone-live-status").innerText);
  await page.locator(".phone-scoreboard").first().focus(); await page.keyboard.press("ArrowUp"); await page.waitForTimeout(300);
  assert.equal(await status(), "", "a delivered command shows no message");
  await page.evaluate(() => { window.DeuceMatePhone.connection.activation = "connecting"; window.DeuceMatePhone.render(); });
  await page.locator(".phone-scoreboard").first().focus(); await page.keyboard.press("ArrowUp"); await page.waitForTimeout(300);
  assert.equal(await status(), "Not confirmed by the Watch. Check the score before retrying.");
  await page.waitForTimeout(5400);
  assert.match(await status(), /^Connecting/, "failure message times out after 5 seconds");
  await page.evaluate(() => { const c = window.DeuceMatePhone.connection; c.activation = "ready"; c.reachable = false; window.DeuceMatePhone.render(); });
  await page.waitForTimeout(300);
  assert.equal(await status(), "Last score shown. Open DeuceMate on the Watch to score here.");
  await page.evaluate(() => { window.DeuceMatePhone.setSetting("iPhoneInput", false); window.DeuceMatePhone.render(); });
  await page.waitForTimeout(300);
  assert.equal(await status(), "Last score shown. Updates resume when the Watch reconnects.");
  assert.deepEqual(errors, [], "no page errors");
  process.stdout.write("[1.3.1 QA] live scoreboard messages passed\n1.3.1 demo QA passed.\n");
  await browser.close();
})().catch((e) => { console.error(e); process.exit(1); });
