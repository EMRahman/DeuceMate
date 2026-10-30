#!/usr/bin/env node
/* In-phone presentation audit: every iPhone popup entry point, with native
   focus/scroll/dismissal behavior. Uses an external Playwright installation. */
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {pathToFileURL} = require("node:url");
const {chromium, webkit} = require(process.env.PLAYWRIGHT_MODULE || "playwright");
const engine = process.env.PLAYWRIGHT_BROWSER || "chromium";
const output = "/tmp/deucemate-iphone-qa";
async function main() {
  fs.mkdirSync(output, {recursive: true});
  const browser = await (engine === "webkit" ? webkit : chromium).launch({headless: true});
  const context = await browser.newContext({viewport: {width: 1280, height: 900}, deviceScaleFactor: 1, colorScheme: "light"});
  const page = await context.newPage(), errors = [], presentations = new Set();
  page.setDefaultTimeout(8000);
  page.on("pageerror", e => errors.push(e.message));
  page.on("dialog", async dialog => {errors.push(`Unexpected browser ${dialog.type()}: ${dialog.message()}`); await dialog.dismiss();});
  const root = page.locator("#iphone-demo"), frame = root.locator(".phone-frame"), dialog = root.locator(".phone-dialog");
  const click = (scope, name) => scope.getByRole("button", {name, exact: typeof name === "string"}).click();
  const nav = root.locator(".phone-nav");
  async function fits(title, kind) {
    await dialog.waitFor({state: "visible"});
    assert.equal(await dialog.getAttribute("aria-label"), title);
    if (title !== "Share match") await dialog.getByRole("heading", {name: title, exact: true}).waitFor({state: "visible"});
    await page.waitForFunction(() => {
      const frame = document.querySelector(".phone-frame").getBoundingClientRect(), dialog = document.querySelector(".phone-dialog").getBoundingClientRect(), viewport = window.visualViewport;
      const top = viewport ? viewport.offsetTop : 0, bottom = top + (viewport ? viewport.height : window.innerHeight);
      return dialog.left >= frame.left && dialog.top >= frame.top && dialog.right <= frame.right + 1 && dialog.bottom <= frame.bottom + 1 && dialog.top >= top && dialog.bottom <= bottom;
    });
    assert.equal(await dialog.getAttribute("data-presentation"), kind);
    presentations.add(title);
    const [device, popup] = await Promise.all([frame.boundingBox(), dialog.boundingBox()]);
    assert.ok(popup.width <= device.width && popup.height <= device.height, `${title} must be bounded by the phone`);
    assert.equal(await dialog.locator(".phone-sheet-content").evaluate(el => el.scrollWidth <= el.clientWidth + 1), true, `${title} must not overflow horizontally`);
    assert.equal(await dialog.evaluate(el => getComputedStyle(el, "::backdrop").backdropFilter), "none", "popup must not blur the surrounding browser page");
    const shade = root.locator(".phone-modal-dimmer");
    assert.equal(await shade.isVisible(), kind !== "cover" && kind !== "popover" && title !== "Share match", "dimming must stay local; native menus, covers and confirmation popovers leave their background visible");
    if (kind === "alert") assert.equal(await dialog.getAttribute("role"), "alertdialog");
  }
  const capture = name => frame.screenshot({path: path.join(output, `${engine}-popup-${name}.png`)});
  async function importArchive(payload) {
    const waiting = page.waitForEvent("filechooser"); await click(root, "Import Match Archive");
    const chooser = await waiting;
    await chooser.setFiles({name: "popup-audit.json", mimeType: "application/json", buffer: Buffer.from(JSON.stringify(payload))});
    await fits("Import Match Archive", "actions");
  }
  async function guideFits() {
    await fits("iCloud Drive Unavailable", "sheet");
    assert.equal(await dialog.getAttribute("data-detent"), "medium", "iCloud guide must use its native medium detent");
    await page.waitForFunction(() => {
      const frame = document.querySelector(".phone-frame"), device = frame.getBoundingClientRect(), popup = document.querySelector(".phone-dialog").getBoundingClientRect(), viewport = window.visualViewport;
      const bottom = Math.min(device.bottom - frame.clientLeft - 18, (viewport ? viewport.offsetTop + viewport.height : window.innerHeight) - 4);
      return popup.height >= 200 && popup.height <= frame.clientHeight / 2 + 1 && Math.abs(popup.bottom - bottom) <= 1;
    });
    const bounds = await page.evaluate(() => {
      const frame = document.querySelector(".phone-frame"), sheet = document.querySelector(".phone-dialog"), device = frame.getBoundingClientRect(), popup = sheet.getBoundingClientRect(), viewport = window.visualViewport;
      return {height: popup.height, maximum: frame.clientHeight / 2, bottom: popup.bottom, targetBottom: Math.min(device.bottom - frame.clientLeft - 18, (viewport ? viewport.offsetTop + viewport.height : window.innerHeight) - 4)};
    });
    assert.ok(bounds.height <= bounds.maximum + 1 && bounds.height >= 200, `medium guide must occupy half the phone while retaining readable content: ${JSON.stringify(bounds)}`);
    assert.ok(Math.abs(bounds.bottom - bounds.targetBottom) <= 1, `medium guide must stay anchored to the visible phone bottom: ${JSON.stringify(bounds)}`);
    assert.equal(await dialog.locator(".phone-sheet-content").evaluate(el => el.scrollHeight > el.clientHeight), true, "medium guide's full instructions must scroll independently");
  }
  async function deleteFits(matchID) {
    await fits("Delete permanently?", "popover");
    await page.waitForFunction(() => document.querySelector(".phone-dialog").getBoundingClientRect().height >= 150);
    assert.equal(await dialog.evaluate(el => el.classList.contains("phone-delete-popover")), true);
    assert.equal(await dialog.locator(".phone-sheet-head .phone-icon").getAttribute("aria-hidden"), "true", "warning icon must not alter the native confirmation name");
    const cancel = dialog.getByRole("button", {name: "Cancel", exact: true}), remove = dialog.getByRole("button", {name: "Delete Permanently", exact: true});
    assert.ok(await cancel.isVisible() && (await cancel.boundingBox()).width >= 100, "native delete popover needs a visible Cancel pill");
    assert.equal(await remove.evaluate(el => getComputedStyle(el).color), "rgb(255, 255, 255)");
    assert.equal(await remove.evaluate(el => getComputedStyle(el).backgroundColor), (await dialog.getAttribute("data-appearance")) === "light" ? "rgb(255, 59, 48)" : "rgb(255, 69, 58)", "permanent delete must use the native filled red pill");
    if (matchID) {
      await page.waitForFunction(id => {
        const row = document.querySelector(`.phone-match-wrap[data-match-id="${id}"]`).getBoundingClientRect(), popup = document.querySelector(".phone-dialog").getBoundingClientRect(), mid = (row.top + row.bottom) / 2;
        return Math.max(popup.top - mid, mid - popup.bottom, 0) <= 48 && popup.width <= 320;
      }, matchID);
      assert.ok(["top", "bottom"].includes(await dialog.getAttribute("data-arrow")), "row deletion must retain an arrow identifying its selected match");
      assert.equal(await dialog.evaluate(el => getComputedStyle(el, "::after").width), "20px");
    } else {
      assert.equal(await dialog.getAttribute("data-arrow"), null, "detail fallback must not retain an old archive-row arrow");
      await page.waitForFunction(() => {
        const frame = document.querySelector(".phone-frame"), device = frame.getBoundingClientRect(), popup = document.querySelector(".phone-dialog").getBoundingClientRect(), viewport = window.visualViewport;
        const top = Math.max(device.top + frame.clientLeft + document.querySelector(".phone-status").getBoundingClientRect().height, viewport ? viewport.offsetTop + 4 : 4);
        const bottom = Math.min(device.bottom - frame.clientLeft - 18, (viewport ? viewport.offsetTop + viewport.height : window.innerHeight) - 4);
        return Math.abs((popup.top + popup.bottom) / 2 - (top + bottom) / 2) <= 2;
      });
    }
  }
  try {
    await page.goto(process.env.PLAYWRIGHT_URL || pathToFileURL(path.resolve(__dirname, "../docs/website/try.html")).href);
    await click(root.locator(".phone-body"), "☁ iCloud unavailable — stored on iPhone ›");
    await guideFits();
    assert.equal(await dialog.locator("li").count(), 4, "cloud guide must retain all native setup steps");
    assert.ok((await dialog.innerText()).includes("but not recorded heart rate, steps, distance, or calories"), "guide must explain which measurements automatic restore excludes");
    for (const viewport of [{width: 320, height: 740}, {width: 390, height: 844}]) {
      await page.setViewportSize(viewport); await guideFits();
      await page.mouse.wheel(0, 240); await guideFits();
    }
    await dialog.locator(".phone-sheet-content").evaluate(el => {el.scrollTop = 0;});
    await capture("icloud-guide");
    const guidePages = context.pages().length, guideURL = page.url();
    await click(dialog, "Open Settings");
    assert.ok(await dialog.locator(".phone-sheet-content").evaluate(el => el.scrollTop > 0), "all guide content and its Settings action must remain reachable within the half-height sheet");
    await capture("icloud-guide-scrolled");
    assert.ok((await dialog.locator(".phone-sheet-notice").innerText()).includes("Would open iPhone Settings"), "device-settings handoff must stay visible inside the guide");
    assert.equal(context.pages().length, guidePages); assert.equal(page.url(), guideURL);
    await click(dialog, "Done");
    assert.equal(await root.locator(".phone-modal-dimmer").isVisible(), false, "closing cloud guide must release the phone dimmer");
    await page.setViewportSize({width: 1280, height: 900});
    const archiveDelete = root.locator(".phone-match-wrap").nth(2), archiveID = await archiveDelete.getAttribute("data-match-id");
    await root.locator(".phone-body").evaluate((el, id) => {
      const row = el.querySelector(`.phone-match-wrap[data-match-id="${id}"]`).getBoundingClientRect(), area = el.getBoundingClientRect();
      el.scrollTop += row.top - area.top - (el.clientHeight - row.height) / 2;
    }, archiveID);
    const beforeArchiveDelete = await page.evaluate(() => window.DeuceMatePhone.records());
    await archiveDelete.hover(); await archiveDelete.getByRole("button", {name: /Match actions/}).click();
    await click(dialog, "Delete Permanently"); await deleteFits(archiveID);
    for (const viewport of [{width: 320, height: 740}, {width: 390, height: 844}]) {
      await page.setViewportSize(viewport); await deleteFits(archiveID);
      await root.locator(".phone-body").evaluate(el => {el.scrollTop += 40;}); await deleteFits(archiveID);
    }
    for (const scheme of ["light", "dark", "light"]) {
      await page.emulateMedia({colorScheme: scheme});
      await page.waitForFunction(scheme => document.querySelector(".phone-dialog").dataset.appearance === scheme, scheme);
      await deleteFits(archiveID); await capture(`delete-row-${scheme}`);
    }
    await click(dialog, "Cancel");
    assert.deepEqual(await page.evaluate(() => window.DeuceMatePhone.records()), beforeArchiveDelete, "archive popover cancellation must preserve the selected match and all other rows");
    await root.locator(".phone-match-row").first().click();
    await click(nav, "Share match"); await fits("Share match", "menu"); await capture("export-menu-desktop");
    for (const viewport of [{width: 320, height: 740}, {width: 390, height: 844}]) {
      await page.setViewportSize(viewport); await fits("Share match", "menu");
    }
    assert.deepEqual(await dialog.locator(".pr-share-group-title").allTextContents(), ["Interactive", "My Stats", "Opponent's Stats"]);
    assert.equal(await dialog.getByRole("button", {name: "Share Summary", exact: true}).count(), 2);
    assert.equal(await dialog.getByRole("button", {name: "Share Summary + Raw Points", exact: true}).count(), 2);
    assert.equal(await dialog.getByRole("button", {name: "Done", exact: true}).count(), 0, "native export menu has no sheet toolbar");
    assert.equal(await dialog.locator(".pr-export-group").count(), 0, "browser-only formats must stay outside the native share menu");
    assert.ok((await dialog.boundingBox()).width <= 250, "native menu stays compact and anchored to the trailing toolbar");
    for (const scheme of ["light", "dark", "light"]) {
      await page.emulateMedia({colorScheme: scheme});
      await page.waitForFunction(scheme => document.querySelector(".phone-dialog").dataset.appearance === scheme, scheme);
      await fits("Share match", "menu"); await capture(`export-menu-${scheme}`);
    }
    await dialog.getByRole("button", {name: "Interactive Web Page", exact: true}).focus();
    await page.keyboard.press("ArrowRight");
    const perspectives = dialog.locator(".pr-share-submenu");
    assert.deepEqual(await perspectives.getByRole("button").allTextContents(), ["Interactive Web Page", "My Perspective", "Opponent's Perspective"]);
    assert.equal(await dialog.locator(".pr-share-sections").getAttribute("inert"), "", "covered parent menu must leave the keyboard and accessibility tree");
    await capture("export-perspectives");
    await page.keyboard.press("Escape");
    assert.equal(await perspectives.count(), 0, "Escape returns from perspectives to the parent menu");
    assert.ok(await dialog.getByRole("button", {name: "Interactive Web Page", exact: true}).evaluate(el => el === document.activeElement));
    await click(dialog, "Interactive Web Page"); await click(perspectives, "Opponent's Perspective");
    await fits("Share health data?", "alert"); await capture("health-alert");
    assert.ok((await dialog.innerText()).includes("heart rate, steps, and calories"));
    assert.equal((await dialog.innerText()).includes("heart-rate zones"), false, "opponent HTML must disclose raw heart rate without recorder-only zones");
    const cancelBox = await dialog.getByRole("button", {name: "Cancel", exact: true}).boundingBox(), shareBox = await dialog.getByRole("button", {name: "Share", exact: true}).boundingBox();
    assert.ok(Math.abs(cancelBox.y - shareBox.y) < 1 && shareBox.x > cancelBox.x, "native health alert uses side-by-side Cancel and Share pills");
    await click(dialog, "Cancel");
    assert.ok(await nav.getByRole("button", {name: "Share match", exact: true}).evaluate(el => el === document.activeElement), "health cancellation returns focus to the export button");
    await root.locator(".phone-experiments").evaluate(el => {el.open = true;});
    await click(root, "Browser export tools"); await fits("Browser export tools", "sheet");
    await click(dialog.locator(".pr-export-group").nth(1), "Preview report"); await fits("Share health data?", "alert");
    await click(dialog, "Share"); await fits("Interactive report preview", "cover");
    const preview = dialog.frameLocator('iframe[title="Interactive match report preview"]');
    await click(preview.locator("body"), "Points");
    assert.ok(await preview.locator(".pt-row").count() > 0, "report preview must remain interactive inside the phone");
    await capture("report-preview"); await click(dialog, "Done");
    await click(nav, "Open AI Coach"); await fits("Share health data?", "alert"); await click(dialog, "Cancel");
    assert.equal(await dialog.isVisible(), false, "Cancel must not open AI Coach");
    await click(nav, "Open AI Coach"); await click(dialog, "Continue"); await fits("AI Coach", "sheet");
    assert.equal(await dialog.locator(".pr-ai-app-row").count(), 7, "native AI sheet must show one row per supported demo app");
    assert.ok(await dialog.getByRole("heading", {name: "Other", exact: true}).count());
    const originalPrompt = await dialog.getByLabel("AI coaching prompt").inputValue();
    await click(dialog.getByRole("group", {name: "Perspective", exact: true}), "Opponent's");
    await fits("AI Coach", "sheet");
    assert.notEqual(await dialog.getByLabel("AI coaching prompt").inputValue(), originalPrompt, "perspective must change the prompt without presenting another health alert");
    await click(dialog.getByRole("group", {name: "Perspective", exact: true}), "My Stats"); await capture("ai-coach");
    const pagesBefore = context.pages().length, urlBefore = page.url();
    await click(dialog, "Open in ChatGPT");
    assert.ok((await dialog.locator(".pr-ai-handoff").innerText()).includes("No match data was sent"));
    assert.equal(context.pages().length, pagesBefore); assert.equal(page.url(), urlBefore);
    assert.equal(await dialog.locator(".phone-sheet-notice").isVisible(), true, "AI feedback must appear in the active phone sheet");
    await page.evaluate(() => Object.defineProperty(navigator, "clipboard", {configurable: true, value: {writeText: () => Promise.reject(new Error("Clipboard unavailable"))}}));
    await click(dialog, "Copy Prompt");
    await page.waitForFunction(() => {
      const field = document.querySelector(".phone-dialog textarea.pr-prompt");
      return field && document.activeElement === field && field.selectionEnd === field.value.length;
    });
    assert.equal(await dialog.locator(".pr-ai-prompt-preview").getAttribute("open"), "", "manual-copy fallback must reveal the prompt");
    await click(dialog, "More Share Options…"); await fits("Share AI Prompt", "actions");
    await click(dialog, "Back to AI Coach"); await fits("AI Coach", "sheet");
    for (let i = 0; i < 5; i++) { await page.keyboard.press("Tab"); assert.ok(await page.evaluate(() => !!document.activeElement.closest(".phone-dialog")), "Tab must stay inside the active phone popup"); }
    await page.keyboard.press("Escape"); assert.equal(await dialog.isVisible(), false);
    assert.ok(await nav.getByRole("button", {name: "Open AI Coach", exact: true}).evaluate(el => el === document.activeElement), "dismissal must return focus to its opener");
    await click(nav, "Open AI Coach"); await click(dialog, "Continue"); await fits("AI Coach", "sheet");
    const header = await dialog.locator(".phone-sheet-head h2").boundingBox();
    await page.mouse.move(header.x + header.width / 2, header.y + header.height / 2); await page.mouse.down();
    await page.mouse.move(header.x + header.width / 2, header.y + header.height / 2 + 90, {steps: 5}); await page.mouse.up();
    assert.equal(await dialog.isVisible(), false, "a native sheet must dismiss on a downward header swipe");
    await click(nav, "Share match"); await fits("Share match", "menu");
    await click(dialog, "Interactive Web Page"); await click(dialog.locator(".pr-share-submenu"), "My Perspective"); await fits("Share health data?", "alert");
    const downloadWait = page.waitForEvent("download"); await click(dialog, "Share");
    assert.ok((await downloadWait).suggestedFilename().endsWith(".html"), "export must still download the real report");
    assert.equal(await dialog.isVisible(), false);
    for (const side of ["My Stats", "Opponent's Stats"]) {
      for (const format of ["Share Summary", "Share Summary + Raw Points"]) {
        await click(nav, "Share match");
        await click(dialog.getByRole("group", {name: side, exact: true}), format);
        await fits("Share health data?", "alert");
        assert.equal((await dialog.innerText()).includes("heart-rate zones"), side === "My Stats", "text disclosure follows its selected perspective");
        const waiting = page.waitForEvent("download"); await click(dialog, "Share");
        const download = await waiting, stream = await download.createReadStream();
        let content = ""; for await (const chunk of stream) content += chunk.toString("utf8");
        assert.ok(content.includes("# DeuceMate Match Export"));
        assert.equal(content.includes("## Raw Point Data"), format === "Share Summary + Raw Points");
        assert.equal(download.suggestedFilename().includes("-opponent"), side === "Opponent's Stats");
      }
    }
    // Native detail has no actions button (delete lives on the archive row), so open the sheet through the demo hook.
    await page.evaluate(() => window.DeuceMatePhone.openSelectedActions()); await fits("Match actions", "actions");
    const beforeDetailDelete = await page.evaluate(() => window.DeuceMatePhone.records());
    await click(dialog, "Delete Permanently"); await deleteFits(null); await capture("delete-detail"); await click(dialog, "Cancel");
    assert.deepEqual(await page.evaluate(() => window.DeuceMatePhone.records()), beforeDetailDelete, "detail fallback cancellation must preserve the archive");
    const beforeEnd = await page.evaluate(() => window.DeuceMatePhone.records());
    assert.equal(await root.locator(".pr-end-match").evaluate(el => getComputedStyle(el).color), "rgb(255, 59, 48)", "light report end action must retain native destructive red");
    await click(root, "End at Current Score"); await fits("End at current score?", "popover");
    assert.equal(await dialog.getByRole("button", {name: "Done", exact: true}).count(), 0, "native end popover must not have a sheet toolbar");
    assert.equal(await dialog.locator(".phone-confirmation>.phone-danger").evaluate(el => getComputedStyle(el).borderRadius), "30px", "destructive confirmation must use the native inset pill");
    for (const scheme of ["light", "dark", "light"]) {
      await page.emulateMedia({colorScheme: scheme});
      await page.waitForFunction(scheme => document.querySelector(".phone-dialog").dataset.appearance === scheme, scheme);
      await fits("End at current score?", "popover"); await capture(`end-popover-${scheme}`);
    }
    const endBox = await dialog.boundingBox(), deviceBox = await frame.boundingBox();
    await page.mouse.click(deviceBox.x + 12, Math.max(deviceBox.y + 64, endBox.y - 12));
    assert.equal(await dialog.isVisible(), false, "tapping outside the native confirmation bubble must cancel");
    assert.deepEqual(await page.evaluate(() => window.DeuceMatePhone.records()), beforeEnd, "outside-tap cancellation must retain the in-progress record");
    await click(nav, "Back to Matches"); await click(nav, "Settings");
    // Native uses an inline DisclosureGroup, not a sheet: it expands in place and collapses again.
    await click(root, /Connection Details/); await root.getByText("Watch App Installed", {exact: true}).waitFor({state: "visible", timeout: 7000}); await capture("connection-details");
    await click(root, /Connection Details/); assert.equal(await root.getByText("Watch App Installed", {exact: true}).count(), 0, "Connection Details should collapse");
    await click(root, "Export Match Archive"); await fits("Export Match Archive", "alert"); await click(dialog, "Cancel");
    const before = await page.evaluate(() => window.DeuceMatePhone.records());
    const payload = {format: "deucemate-browser-demo-archive", version: 1, records: before};
    await importArchive(payload); await capture("archive-import"); await click(dialog, "Replace Archive"); await fits("Replace Match Archive?", "alert");
    assert.ok((await dialog.innerText()).includes(`Replace ${before.length} current matches with ${before.length} imported matches?`));
    await capture("archive-replace"); await click(dialog, "Cancel");
    assert.deepEqual(await page.evaluate(() => window.DeuceMatePhone.records().map(r => r.id)), before.map(r => r.id));
    const experiments = root.locator(".phone-experiments"); await experiments.evaluate(el => {el.open = true;});
    await click(experiments, "Simulate cloud backup"); await page.waitForFunction(() => window.DeuceMatePhone.cloudStatus().startsWith("Backed up"));
    await click(experiments, "Preview cloud restore"); await fits("Restore matches from iCloud?", "alert"); await click(dialog, "Not Now");
    await click(experiments, "Reset demo"); await fits("Reset this demo?", "alert"); await click(dialog, "Cancel");
    assert.equal(await root.locator(".phone-modal-dimmer").isVisible(), false, "dismissal must clear device dimming");
    await click(nav, "Back to Matches"); await root.locator(".phone-match-row").first().click(); await click(root, "Expand graph");
    await fits("Points Graph", "cover"); await capture("expanded-graph");
    const panel = dialog.locator(".pr-expanded-graph"), stage = panel.locator(".pr-expanded-stage");
    // Use this desktop browser context at both widths: mobile WebKit does not
    // support Playwright wheel input. Touch graph gestures live in visual QA.
    for (const viewport of [{width: 1280, height: 900}, {width: 390, height: 844}]) {
      await page.setViewportSize(viewport);
      const pageTop = await frame.evaluate(async el => {
        el.scrollIntoView({block: "nearest", behavior: "instant"});
        await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
        return window.scrollY;
      });
      const graphBeforeScroll = await stage.boundingBox();
      await page.mouse.move(12, viewport.height / 2);
      await page.mouse.wheel(0, 160);
      // A sheet resize must not start a smooth scroll back to the phone.
      await page.waitForTimeout(700);
      assert.ok(Math.abs(await page.evaluate(() => window.scrollY) - pageTop - 160) <= 2, "scrolling the webpage with the graph open must not snap back to the phone");
      const graphAfterScroll = await stage.boundingBox();
      assert.ok(Math.abs(graphAfterScroll.height - graphBeforeScroll.height) <= 1 && Math.abs(graphAfterScroll.width - graphBeforeScroll.width) <= 1, "scrolling the webpage must preserve the graph dimensions instead of squeezing the chart");
      assert.ok(Math.abs(graphAfterScroll.y - graphBeforeScroll.y + 160) <= 2, "the graph must move with the phone during webpage scrolling");
      await fits("Points Graph", "cover");
      await page.mouse.wheel(0, -160);
      await page.waitForTimeout(700);
      assert.ok(Math.abs(await page.evaluate(() => window.scrollY) - pageTop) <= 2, "scrolling back up with the graph open must preserve the requested page position");
      assert.deepEqual(await stage.boundingBox(), graphBeforeScroll, "scrolling the page back must return the graph to the same position and size");
      await fits("Points Graph", "cover");
      const controls = panel.locator(".pr-expanded-controls");
      await controls.evaluate(el => {el.scrollTop = 0;});
      const chartBefore = await stage.boundingBox(), controlBounds = await controls.boundingBox();
      await page.mouse.move(controlBounds.x + controlBounds.width / 2, controlBounds.y + controlBounds.height / 2);
      await page.mouse.wheel(0, 160);
      await page.waitForFunction(() => document.querySelector(".pr-expanded-controls").scrollTop > 0);
      assert.deepEqual(await stage.boundingBox(), chartBefore, "wheel scrolling the graph controls must keep the chart fixed");
      assert.ok(Math.abs(await page.evaluate(() => window.scrollY) - pageTop) <= 2, "wheel scrolling the graph controls must leave the webpage in place");
    }
    await click(dialog, "Done");
    await click(nav, "Back to Matches");
    const scoreOnlyID = await page.evaluate(() => window.DeuceMatePhone.records().find(r => !r.stats.length).id);
    await root.locator(`.phone-match-wrap[data-match-id="${scoreOnlyID}"] .phone-match-row`).click();
    await click(nav, "Share match"); await fits("Share match", "menu");
    assert.equal(await dialog.getByRole("button", {name: "Share Summary + Raw Points", exact: true}).count(), 0, "score-only matches must hide raw-point sharing");
    assert.equal(await dialog.getByRole("button", {name: "Share Summary", exact: true}).count(), 2, "both score-only summary perspectives remain available");
    await capture("export-menu-score-only");
    const scoreOnlyDownload = page.waitForEvent("download");
    await click(dialog.getByRole("group", {name: "My Stats", exact: true}), "Share Summary");
    assert.ok((await scoreOnlyDownload).suggestedFilename().endsWith("_summary.txt"), "health-free sharing must download directly without a disclosure");
    assert.equal(await dialog.isVisible(), false);
    assert.deepEqual(errors, [], "all app popups must avoid browser alerts/confirmations and runtime errors");
    process.stdout.write(`In-phone popup QA passed (${engine}): ${presentations.size} native presentations. Screenshots: ${output}\n`);
  } finally { await context.close(); await browser.close(); }
}
main().catch(error => {console.error(error); process.exitCode = 1;});
