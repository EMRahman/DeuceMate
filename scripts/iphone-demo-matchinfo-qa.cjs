#!/usr/bin/env node
/* Browser QA for the demo Match Info block, conversion, exports and Watch replica.
   PLAYWRIGHT_MODULE=/path/to/playwright node scripts/iphone-demo-matchinfo-qa.cjs */
"use strict";
const pw = require(process.env.PLAYWRIGHT_MODULE || "playwright"), chromium = pw[process.env.PLAYWRIGHT_BROWSER || "chromium"];
const path = require("path"), { pathToFileURL } = require("url"), assert = require("assert");
(async () => {
  const b = await chromium.launch(); const page = await b.newPage({ viewport: { width: 1200, height: 1000 } });
  const errors = []; page.on("pageerror", e => errors.push(e.message)); page.on("console", m => m.type() === "error" && errors.push(m.text()));
  await page.goto(pathToFileURL(path.resolve("docs/website/try.html")).href);
  await page.waitForFunction(() => window.DeuceMatePhone && window.DeuceMatePhone.records().length);
  const rec = await page.evaluate(() => { const r = window.DeuceMatePhone.records().filter(r => r.endTime && r.matchType === "doubles")[0] || window.DeuceMatePhone.records().filter(r=>r.endTime)[0]; return { id: r.id, type: r.matchType }; });
  console.log("record", rec);
  // Seed data ships with players on most matches; assert that, then start this flow from a clean record.
  const seeded = await page.evaluate(() => { const rs = window.DeuceMatePhone.records(); const by = {}; rs.forEach(r => ((r.tags && r.tags.opponents) || []).forEach(p => { by[p.name] = (by[p.name] || 0) + 1; })); return by; });
  console.log("seeded opponents", JSON.stringify(seeded));
  assert(seeded["Alice Morgan"] === 4 && seeded["Ben Carter"] === 2 && Object.values(seeded).every(n => n >= 1 && n <= 4), "seed cast: each player plays 1-4 matches");
  await page.evaluate(id => window.DeuceMatePhone.updateRecord(id, r => { r.tags = undefined; }), rec.id);
  await page.evaluate(id => { window.DeuceMatePhone.navigate("detail", window.DeuceMatePhone.records().find(r => r.id === id)); }, rec.id);
  const ph = page.locator("#iphone-demo");
  await ph.getByRole("button", { name: /Match Info/ }).first().click();
  await ph.getByRole("button", { name: /Add (opponent|players)/ }).click();
  await page.screenshot({ path: "/tmp/mi-editor-empty.png" }); const dbl = (await ph.locator(".mi-prow").count()) > 2;
  const addPlayer = async (slotLabel, name) => {
    await ph.getByRole("button", { name: new RegExp("^" + slotLabel) }).click();
    await ph.locator("input.mi-search-input").fill(name); if (name === "Jo") await page.screenshot({ path: "/tmp/mi-picker.png" });
    await ph.getByRole("button", { name: new RegExp("Add .*" + name + ".* as new player") }).click();
  };
  console.log("doubles editor", dbl);
  if (dbl) { await addPlayer("Partner", "Sam"); await addPlayer("Opponent 1", "Alex"); await addPlayer("Opponent 2", "Jo"); } else await addPlayer("Opponent", "Alex");
  await ph.getByRole("button", { name: /^League/ }).click();
  await page.screenshot({ path: "/tmp/mi-editor.png" }); await ph.getByRole("button", { name: "Save", exact: true }).click();
  let tags = await page.evaluate(id => window.DeuceMatePhone.records().find(r => r.id === id).tags, rec.id);
  console.log("tags", JSON.stringify(tags)); assert(tags && tags.opponents[0].name === "Alex" && tags.competition === "league");
  await ph.getByRole("button", { name: /Match Info, .*Alex/ }).waitFor();
  // note
  await ph.getByRole("button", { name: /Add private note/ }).click();
  await ph.locator("textarea.mi-note-area").fill("tired legs"); await page.screenshot({ path: "/tmp/mi-note.png" }); await ph.locator(".phone-sheet-head button", { hasText: "Done" }).click();
  assert.equal(await page.evaluate(id => window.DeuceMatePhoneMatchInfo.getNote(id), rec.id), "tired legs");
  // compare
  await ph.getByRole("button", { name: /Compare with Previous/ }).click();
  await ph.getByText(/Previous match|No earlier/).first().waitFor(); await ph.getByText("Rates").waitFor(); await page.screenshot({ path: "/tmp/mi-compare.png" }); await page.keyboard.press("Escape");
  await page.screenshot({ path: "/tmp/mi-detail.png" });
  // convert
  const target = rec.type === "doubles" ? "Singles" : "Doubles";
  await ph.getByRole("button", { name: "Change to " + target }).first().click();
  await ph.getByRole("button", { name: "Change to " + target }).last().click();
  const after = await page.evaluate(id => { const r = window.DeuceMatePhone.records().find(r => r.id === id); return { t: r.matchType, tags: r.tags }; }, rec.id);
  console.log("after", JSON.stringify(after)); assert.equal(after.t, target.toLowerCase());
  if (target === "Singles") assert(!after.tags.partner && after.tags.opponents.length === 1);
  // export
  const ex = await page.evaluate(id => { const r = window.DeuceMatePhone.records().find(r => r.id === id); const m = window.DeuceMatePhoneReports.exportModel(r, r.stats || [], "me"); return { v: m.schemaVersion, meta: m.meta.readerSideNames, comp: m.meta.competitionTypeLabel, note: m.meta.privateNote, text: window.DeuceMatePhoneReports.reportText(r, r.stats || [], "me", "full").split("## Match Context")[1].slice(0, 120) }; }, rec.id);
  console.log("export", JSON.stringify(ex)); assert.equal(ex.v, 13);
  // share menu switches
  await ph.getByRole("button", { name: "Share match" }).click();
  await ph.getByText("Include player names").waitFor(); await ph.getByText("Include private note").waitFor();
  await ph.getByText("Include private note").click(); await ph.getByText("This exact text will be included").waitFor(); await ph.getByRole("button", { name: "Include Note" }).click();
  assert.equal(await page.evaluate(() => window.DeuceMatePhoneMatchInfo.exportOptions.note), true);
  // interactive page renders the details (schema 13 viewer), names + note opted in
  const html = await page.evaluate(id => { const r = window.DeuceMatePhone.records().find(r => r.id === id); return window.DeuceMatePhoneReports.standaloneHTML(r, r.stats || [], "me"); }, rec.id);
  const viewer = await b.newPage(); await viewer.setContent(html);
  const viewerText = await viewer.locator("body").innerText();
  console.log("viewer shows details", /League/.test(viewerText), /Alex/.test(viewerText), /tired legs/.test(viewerText));
  assert(/League/.test(viewerText) && /Alex/.test(viewerText) && /tired legs/.test(viewerText), "HTML export must show details + opted-in note");
  await viewer.close();
  // row caption + opponents directory
  await page.evaluate(() => window.DeuceMatePhone.navigate("matches"));
  await ph.getByRole("button", { name: /Head-to-head records/ }).click();
  await ph.locator("button.mi-row", { hasText: "Alex" }).click();
  await ph.getByText("Head to Head · Singles").waitFor(); await page.screenshot({ path: "/tmp/mi-opponent.png" }); await page.keyboard.press("Escape");
  console.log("caption", await ph.locator(".phone-row-caption").count());
  // players settings
  await page.evaluate(() => window.DeuceMatePhone.navigate("settings"));
  await ph.getByRole("button", { name: /Players/ }).click(); await ph.getByText("Players come from your matches").waitFor(); await page.screenshot({ path: "/tmp/mi-players-list.png" }); await ph.locator("button.mi-row", { hasText: "Alex" }).first().click(); await ph.getByText("Saves automatically and updates all").waitFor(); await ph.locator("button.mi-row", { hasText: "Forget Player" }).waitFor();
  await page.screenshot({ path: "/tmp/mi-players.png" });
  console.log("errors", errors);
  assert.equal(errors.length, 0); await b.close(); console.log("MI QA PASS");
  await watchQA();
})().catch(e => { console.error("FAIL", e.message); process.exit(1); });

async function watchQA() {
  const b = await chromium.launch(); const page = await b.newPage({ viewport: { width: 1200, height: 1000 } });
  const errors = []; page.on("pageerror", e => errors.push(e.message));
  await page.goto(pathToFileURL(path.resolve("docs/website/try.html")).href);
  await page.waitForFunction(() => window.DeuceMatePhone && window.DeuceMatePhone.records().length);
  await page.evaluate(() => window.DeuceMatePhone.updateRecord("seed6041", r => { r.tags = { competition: "league", partner: { name: "Sam" }, opponents: [{ name: "Alex" }, { name: "Jo" }] }; }));
  const w = page.locator(".watch-frame, #watch-demo, [data-app]").first();
  await page.locator("button[aria-label='Past Matches']").first().click();
  const caption = await page.locator(".hist-row .h-fmt", { hasText: "With Sam" }).count(); console.log("watch caption rows", caption); assert(caption >= 1);
  await page.locator(".hist-row", { hasText: "With Sam" }).first().click();
  await page.locator("[data-testid=watch-convert-match-type]").click();
  await page.getByText("Removes Sam & Jo from match details.").waitFor();
  await page.getByRole("button", { name: "Change to Singles" }).last().click();
  const t = await page.evaluate(() => { const r = window.DeuceMatePhone.records().find(r => r.id === "seed6041"); return [r.matchType, JSON.stringify(r.tags)]; });
  console.log(t); assert.equal(t[0], "singles"); console.log("errors", errors); assert(!errors.length); await b.close(); console.log("WATCH QA PASS");
}
