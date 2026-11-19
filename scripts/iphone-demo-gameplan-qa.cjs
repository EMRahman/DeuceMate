#!/usr/bin/env node
/* Browser QA for the demo's Prepare Game Plan and playing style notes (phone-demo-gameplan.js).
   PLAYWRIGHT_MODULE=/path/to/playwright node scripts/iphone-demo-gameplan-qa.cjs
   Screenshots: /tmp/deucemate-iphone-qa/gameplan-*.png */
"use strict";
const pw = require(process.env.PLAYWRIGHT_MODULE || "playwright"), browser = pw[process.env.PLAYWRIGHT_BROWSER || "chromium"];
const path = require("path"), fs = require("fs"), { pathToFileURL } = require("url"), assert = require("assert");
const OUT = "/tmp/deucemate-iphone-qa";
(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const b = await browser.launch(); const page = await b.newPage({ viewport: { width: 1200, height: 1000 } });
  const errors = []; page.on("pageerror", e => errors.push(e.message)); page.on("console", m => m.type() === "error" && errors.push(m.text()));
  try {
    await page.goto(pathToFileURL(path.resolve("docs/website/try.html")).href);
    await page.waitForFunction(() => window.DeuceMatePhone && window.DeuceMatePhone.records().length && window.DeuceMatePhoneGamePlan);
    const ph = page.locator("#iphone-demo"), head = ph.locator(".phone-sheet-head"), content = ph.locator(".phone-sheet-content");
    const pack = () => page.evaluate(() => {
      const M = window.DeuceMatePhoneMatchInfo, e = M.opponentEntries(window.DeuceMatePhone).find(p => p.name === "Alice Morgan");
      return document.querySelector("#iphone-demo textarea.gp-preview") ? document.querySelector("#iphone-demo textarea.gp-preview").value : null;
    });
    const openAlice = async () => {
      await page.evaluate(() => { window.DeuceMatePhone.closeSheet(); window.DeuceMatePhone.navigate("matches"); });
      await ph.getByRole("button", { name: /Head-to-head records/ }).click();
      await ph.locator("button.mi-row", { hasText: "Alice Morgan" }).click();
      await ph.getByText("Head to Head · Singles").waitFor();
    };

    // Opponent page: the playing style card carries the seeded notes, clamped until tapped.
    await openAlice();
    const notes = ph.locator('[data-testid="opponent-playing-notes"]');
    assert(/Big first serve/.test(await notes.textContent()), "seeded playing notes appear on the opponent page");
    assert.equal(await notes.getAttribute("aria-expanded"), "false");
    await notes.click(); assert.equal(await notes.getAttribute("aria-expanded"), "true", "notes expand on tap");
    const headings = await content.locator(".pr-native-section-title").allTextContents();
    assert.equal(headings[0], "Head to Head · Singles"); assert.equal(headings[headings.length - 1], "Past Matches");
    await page.screenshot({ path: OUT + "/gameplan-opponent.png" });

    // Ready on arrival, pre-filled from the latest match against Alice (league, Best of 3).
    await ph.locator('[data-testid="opponent-prepare-game-plan"]').click();
    await head.getByText("Prepare Game Plan").waitFor();
    const expected = await page.evaluate(() => window.DeuceMatePhone.records().filter(r => r.matchType !== "doubles" && r.tags && (r.tags.opponents || []).some(p => p.name === "Alice Morgan")).length);
    assert(/League · Best of 3/.test(await ph.locator('[data-testid="game-plan-upcoming"]').textContent()), "upcoming pre-filled from the latest match");
    assert(new RegExp("Last 5 · " + Math.min(5, expected) + " of " + expected).test(await ph.locator('[data-testid="game-plan-evidence"]').textContent()), "matches summary");
    assert(/Names · Style/.test(await ph.locator('[data-testid="game-plan-includes"]').textContent()), "names and style on by default");
    assert(/Estimated input: ~[\d,]+ tokens/.test(await content.textContent()), "estimate shown");
    await page.screenshot({ path: OUT + "/gameplan-main.png" });

    // Preview: every native section, quoted scouting notes, never Health data.
    await ph.getByRole("button", { name: /Preview Evidence Pack/ }).click();
    let text = await pack();
    ["## 1. Preparation Brief", "## 2. Manifest", "## 3. Cross-Match Evidence", "## 4. Match Dossiers", "## 5. Private Observations", "## 6. Full Point Appendix", "## 7. Coaching Request"].forEach(s => assert(text.includes(s), "pack has " + s));
    assert(text.includes('Opponent: "Alice Morgan"') && text.includes("> Big first serve"), "names and scouting notes included");
    assert(/Never included: heart rate/.test(text) && !/bpm|kcal|calories:/i.test(text.replace(/Never included:.*\n/, "")), "no Health data");
    await page.screenshot({ path: OUT + "/gameplan-preview.png" });
    await head.getByRole("button", { name: "Back", exact: true }).click();

    // Names off is remembered and shared with the share menu; style notes off is remembered too.
    await ph.locator('[data-testid="game-plan-includes"]').click();
    await ph.locator('[data-testid="game-plan-include-names"]').uncheck();
    await ph.locator('[data-testid="game-plan-include-playing-notes"]').uncheck();
    assert.equal(await page.evaluate(() => window.DeuceMatePhoneMatchInfo.exportOptions.names), false, "one names choice");
    assert.equal(await page.evaluate(() => localStorage.getItem("deucemate-gameplan-include-playing-notes")), "0");
    await head.getByRole("button", { name: "Back", exact: true }).click();
    assert(/Figures only/.test(await ph.locator('[data-testid="game-plan-includes"]').textContent()));
    await ph.getByRole("button", { name: /Preview Evidence Pack/ }).click();
    text = await pack();
    assert(!text.includes("Alice Morgan") && text.includes("name withheld") && text.includes("scouting notes on the opponent's game: not included"), "names and notes withheld");
    await head.getByRole("button", { name: "Back", exact: true }).click();
    await ph.locator('[data-testid="game-plan-includes"]').click();
    await ph.locator('[data-testid="game-plan-include-names"]').check();
    await ph.locator('[data-testid="game-plan-include-playing-notes"]').check();

    // Private notes: off by default, included only after the exact-text review, never remembered.
    const noted = await page.evaluate(() => { const r = window.DeuceMatePhone.records().find(r => r.endTime && r.matchType !== "doubles" && r.tags && r.tags.opponents.some(p => p.name === "Alice Morgan")); window.DeuceMatePhoneMatchInfo.setNote(r.id, "Felt flat after the long drive"); return r.id; });
    await head.getByRole("button", { name: "Back", exact: true }).click();
    await ph.locator('[data-testid="game-plan-includes"]').click();
    await ph.locator('[data-testid="game-plan-include-notes"]').click();
    await head.getByText("Choose Notes").waitFor();
    assert(/> Felt flat after the long drive/.test(await content.textContent()), "review shows the exact text");
    await page.screenshot({ path: OUT + "/gameplan-notes-review.png" });
    await head.getByRole("button", { name: "Done", exact: true }).click();
    assert(await ph.locator('[data-testid="game-plan-include-notes"]').isChecked(), "notes on after Done");
    await head.getByRole("button", { name: "Back", exact: true }).click();
    await ph.getByRole("button", { name: /Preview Evidence Pack/ }).click();
    assert((await pack()).includes("> Felt flat after the long drive"), "included note is quoted");
    await openAlice();
    await ph.locator('[data-testid="opponent-prepare-game-plan"]').click();
    assert(!/Notes/.test(await ph.locator('[data-testid="game-plan-includes"]').textContent()), "private notes reset on the next visit");

    // Unfinished latest match: the plan is for finishing it, and it is always evidence.
    await page.evaluate(() => {
      const phone = window.DeuceMatePhone, rs = phone.records(), src = rs.find(r => r.endTime && r.tags && r.tags.opponents.some(p => p.name === "Alice Morgan"));
      rs.push(Object.assign(structuredClone(src), { id: "gp-unfinished", startTime: Date.now() - 3600000, endTime: null, iWon: null })); phone.replaceRecords(rs);
    });
    await openAlice();
    await ph.locator('[data-testid="opponent-prepare-game-plan"]').click();
    assert(/Finish match/.test(await ph.locator('[data-testid="game-plan-upcoming"]').textContent()), "finishing an unfinished match");
    await ph.getByRole("button", { name: /Preview Evidence Pack/ }).click();
    assert(/finishing the unfinished match M\d{3}/.test(await pack()), "brief says finishing");

    // Manage Player: notes save only with Save, with a live 4,000-character counter.
    await openAlice();
    await head.getByRole("button", { name: "Rename or Manage Player" }).click();
    const area = ph.getByRole("textbox", { name: "Playing style notes" });
    await area.fill("Moonballs on big points");
    assert(/23 \/ 4,000/.test(await content.textContent()), "live counter");
    await page.screenshot({ path: OUT + "/gameplan-manage-notes.png" });
    await head.getByRole("button", { name: "Save", exact: true }).click();
    const stored = await page.evaluate(() => window.DeuceMatePhone.records().filter(r => r.tags && r.tags.opponents.some(p => p.name === "Alice Morgan")).map(r => r.tags.opponents[0].notes));
    assert(stored.every(n => n === "Moonballs on big points"), "notes saved on every match with the player");
    await area.fill("");
    await head.getByRole("button", { name: "Save", exact: true }).click();
    await ph.getByText("Delete playing style notes?").waitFor();
    await ph.getByRole("button", { name: "Keep Notes", exact: true }).click();
    assert.equal(await ph.getByRole("textbox", { name: "Playing style notes" }).inputValue(), "Moonballs on big points", "Keep Notes keeps them");

    void noted;
    assert.deepEqual(errors, [], "no page errors");
    console.log("Game Plan demo QA passed (" + (process.env.PLAYWRIGHT_BROWSER || "chromium") + "). Screenshots: " + OUT);
  } finally { await b.close(); }
})().catch(e => { console.error(e); process.exit(1); });
