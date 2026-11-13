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
  await ph.locator("textarea.mi-note-area").fill("tired legs"); await page.screenshot({ path: "/tmp/mi-note.png" }); await ph.locator(".phone-sheet-head button", { hasText: "Save" }).click();
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
  console.log("export", JSON.stringify(ex)); assert.equal(ex.v, 14);
  // share menu switches
  await ph.getByRole("button", { name: "Share match" }).click();
  await ph.getByText("Include player names").waitFor(); await ph.getByText("Include private note").waitFor();
  await ph.getByText("Include private note").click(); await ph.getByText("This exact text will be included").waitFor(); await ph.getByRole("button", { name: "Include Note" }).click();
  assert.equal(await page.evaluate(() => window.DeuceMatePhoneMatchInfo.exportOptions.noteMatchId), rec.id);
  // interactive page renders the details (schema 14 viewer), names + note opted in
  const html = await page.evaluate(id => { const r = window.DeuceMatePhone.records().find(r => r.id === id); return window.DeuceMatePhoneReports.standaloneHTML(r, r.stats || [], "me"); }, rec.id);
  const viewer = await b.newPage(); await viewer.setContent(html);
  const viewerText = await viewer.locator("body").innerText();
  console.log("viewer shows details", /League/.test(viewerText), /Alex/.test(viewerText), /tired legs/.test(viewerText));
  assert(/League/.test(viewerText) && /Alex/.test(viewerText) && /tired legs/.test(viewerText), "HTML export must show details + opted-in note");
  await viewer.close();
  // row caption + opponents directory
  // A long history must not bury the summary or player-management action.
  await page.evaluate(id => {
    const phone = window.DeuceMatePhone, records = phone.records(), original = records.find(r => r.id === id);
    for (let i = 0; i < 30; i++) records.push({ ...structuredClone(original), id: "opponent-long-history-" + i, startTime: original.startTime - (i + 1) * 86400000 });
    phone.replaceRecords(records);
  }, rec.id);
  await page.evaluate(() => window.DeuceMatePhone.navigate("matches"));
  await ph.getByRole("button", { name: /Head-to-head records/ }).click();
  await ph.locator("button.mi-row", { hasText: "Alex" }).click();
  await ph.getByText("Head to Head · Singles").waitFor();
  const headings = await ph.locator(".phone-sheet-content .pr-native-section-title").allTextContents();
  assert.equal(headings[0], "Head to Head · Singles", "Head to head comes first");
  assert.equal(headings[headings.length - 1], "Past Matches", "Past Matches is the final section");
  const summary = await ph.getByText("Head to Head · Singles").boundingBox();
  const sheetViewport = await ph.locator(".phone-sheet-content").boundingBox();
  assert(summary.y >= sheetViewport.y && summary.y + summary.height <= sheetViewport.y + sheetViewport.height, "Head to head is visible without scrolling through matches");
  await page.screenshot({ path: "/tmp/mi-opponent.png" });
  await ph.locator(".phone-sheet-content").evaluate(el => { el.scrollTop = el.scrollHeight; });
  const manage = ph.locator(".phone-sheet-head").getByRole("button", { name: "Rename or Manage Player" });
  await manage.click();
  assert.equal(await ph.getByRole("textbox", { name: "Player name", exact: true }).inputValue(), "Alex", "Manage opens this opponent directly");
  await ph.locator(".phone-sheet-head").getByRole("button", { name: "Back", exact: true }).click();
  await ph.getByText("Head to Head · Singles").waitFor();
  await page.keyboard.press("Escape");
  console.log("caption", await ph.locator(".phone-row-caption").count());
  // players settings
  await page.evaluate(() => window.DeuceMatePhone.navigate("settings"));
  await ph.getByRole("button", { name: /Players/ }).click(); await ph.getByText("Players come from your matches").waitFor(); await page.screenshot({ path: "/tmp/mi-players-list.png" }); await ph.locator("button.mi-row", { hasText: "Alex" }).first().click(); await ph.getByText(/^Updates all \d+ matches with this player/).waitFor(); await ph.locator("button.mi-row", { hasText: "Forget Player" }).waitFor();
  await page.screenshot({ path: "/tmp/mi-players.png" });
  // Review findings: consent is per match, picker->profile is not dismissal, identity is the player id.
  await page.evaluate(() => window.DeuceMatePhone.closeSheet());
  const other = await page.evaluate((id) => { const r = window.DeuceMatePhone.records().find(x => x.id !== id && x.endTime && x.tags); window.DeuceMatePhoneMatchInfo.setNote(r.id, "other private note"); return r.id; }, rec.id);
  const leak = await page.evaluate((o) => { const r = window.DeuceMatePhone.records().find(x => x.id === o); return { text: window.DeuceMatePhoneMatchInfo.contextText(r, "me") || "", meta: window.DeuceMatePhoneMatchInfo.webMeta(r, "me").privateNote }; }, other);
  assert(!/other private note/.test(leak.text) && !leak.meta, "reviewing one match's note must not authorize another's");
  const twins = await page.evaluate(() => {
    const P = window.DeuceMatePhone, M = window.DeuceMatePhoneMatchInfo, done = P.records().filter(r => r.endTime && r.matchType === "singles");
    P.updateRecord(done[0].id, r => { r.tags = { competition: "friendly", opponents: [{ id: "twin-1", name: "Sam Twin" }] }; });
    P.updateRecord(done[1].id, r => { r.tags = { competition: "friendly", opponents: [{ id: "twin-2", name: "Sam Twin" }] }; });
    const a = P.records().find(r => r.id === done[0].id), c = P.records().find(r => r.id === done[1].id);
    return { sameKey: M.key(a) === M.key(c), roster: M.roster(P).filter(p => p.name === "Sam Twin").length, h2h: M.headToHead(P, a) };
  });
  assert.equal(twins.sameKey, false, "same-name players with different ids are different matchups");
  assert.equal(twins.roster, 2, "roster keeps both same-name players");
  assert.equal(twins.h2h, null, "no head-to-head is shared between different people with one name");
  // Picker -> player info opens the profile and stays there (not replaced by the editor).
  await page.evaluate(() => { const P = window.DeuceMatePhone; P.navigate("detail", P.records().find(r => r.endTime && r.matchType === "singles" && r.tags)); });
  await ph.locator("button.mi-row").first().click().catch(() => {});
  if (!(await ph.getByText("Competition Type").count())) { const d = ph.locator("button.mi-disclosure"); if ((await d.getAttribute("aria-expanded")) !== "true") await d.click(); await ph.locator("button.mi-row").first().click(); }
  await ph.getByRole("button", { name: /^Opponent/ }).click();
  await ph.locator('button.mi-info[aria-label^="Manage"]').first().click();
  await ph.getByText("Playing Style").waitFor(); await page.waitForTimeout(300);
  assert.equal(await ph.getByText("Competition Type").count(), 0, "opening a profile from the picker must not reopen the editor");
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
