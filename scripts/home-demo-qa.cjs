#!/usr/bin/env node
/*
 * Browser QA for the demo embedded in the home page (docs/website/index.html).
 *   PLAYWRIGHT_MODULE=/path/to/playwright node scripts/home-demo-qa.cjs
 * PLAYWRIGHT_BROWSER=webkit runs it on the Safari engine. No project dependency
 * is added. It serves the site itself: the page reads try.html over HTTP.
 */
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const http = require("node:http");
const path = require("node:path");

const playwright = require(process.env.PLAYWRIGHT_MODULE || "playwright");
const browserType = playwright[process.env.PLAYWRIGHT_BROWSER || "chromium"];
const ROOT = path.resolve(__dirname, "../docs/website");
const TYPES = { ".html": "text/html", ".css": "text/css", ".js": "text/javascript", ".png": "image/png", ".jpg": "image/jpeg" };
const DEMO_ASSET = /assets\/(watch-demo|watch-app|phone-demo)/;

function serve() {
  const server = http.createServer((req, res) => {
    const file = path.join(ROOT, decodeURIComponent(req.url.split("?")[0]));
    if (!file.startsWith(ROOT) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { "Content-Type": TYPES[path.extname(file)] || "application/octet-stream" });
    fs.createReadStream(file).pipe(res);
  });
  return new Promise(resolve => server.listen(0, "127.0.0.1", () => resolve(server)));
}

/* Every element's size and key styles outside the Try section. Class names are
   left out because the nav and scroll reveals change theirs as the page moves. */
const layoutSnapshot = () => [...document.querySelectorAll("header.nav, header.nav *, main > section:not(#try), main > section:not(#try) *, footer.footer, footer.footer *")].map(node => {
  const style = getComputedStyle(node);
  return [node.tagName, node.offsetWidth, node.offsetHeight, style.fontSize, style.color, style.padding, style.margin, style.display, style.position].join("|");
});

async function start(browser, options = {}) {
  const context = await browser.newContext({ reducedMotion: "reduce", viewport: { width: 1280, height: 900 }, ...options });
  const page = await context.newPage();
  const errors = [], demoRequests = [];
  // WebKit reports this harmless layout notice as a page error.
  page.on("pageerror", error => { if (!/^ResizeObserver loop/.test(error.message)) errors.push(error.message); });
  page.on("request", request => { if (DEMO_ASSET.test(request.url())) demoRequests.push(request.url()); });
  return { context, page, errors, demoRequests };
}

const score = page => page.evaluate(() => document.querySelector("#watch-demo").__deuceMateDebug.state().currentPointsMe);

async function checkClubFormats(browser, url) {
  const { context, page, errors } = await start(browser, { viewport: { width: 360, height: 800 }, hasTouch: true });
  const games = side => page.locator(`[data-side=${side}] [data-games]`).textContent();
  const points = side => page.locator(`[data-side=${side}] [data-points]`).textContent();
  const next = () => page.locator("#club-next").textContent();
  const result = () => page.locator("#club-result").textContent();
  const click = name => page.getByRole("button", { name, exact: true }).click();
  try {
    await page.goto(url);
    await page.getByRole("link", { name: "Practise FAST4, Short Sets and Perpetual Tiebreak" }).click();
    await page.getByRole("heading", { name: "Doubles tournament formats" }).waitFor();
    assert.equal(await page.getByRole("button", { name: "Doubles", exact: true }).getAttribute("aria-pressed"), "true");
    assert.match(await next(), /receiver chooses the side/i);
    await click("You win the point");
    assert.equal(await games("me"), "1", "one point wins a no-ad game");
    await click("Undo point");
    assert.equal(await points("me"), "40");
    await click("4–4 in tiebreak");
    await click("Opponent wins");
    assert.equal(await games("opponent"), "4", "FAST4 finishes on the point after 4–4");
    assert.match(await next(), /Match complete/);
    assert.ok(await page.getByRole("button", { name: "You win the point" }).isDisabled());
    await click("Reset scenario");
    assert.equal(await points("opponent"), "4");

    await click("Short Sets");
    await click("6–5 match point");
    await click("Opponent wins");
    await click("You win the point");
    assert.equal(await points("me"), "7");
    assert.equal(await points("opponent"), "6");
    assert.ok(await page.getByRole("button", { name: "You win the point" }).isEnabled(), "7–6 needs one more point");
    await click("You win the point");
    assert.equal(await games("me"), "5");
    assert.match(await next(), /Match complete/);

    await click("Perpetual Tiebreak");
    await click("1–0 serve rotation");
    assert.match(await next(), /Opponent 1 serves from the ad/);
    await click("You win the point");
    assert.match(await next(), /Opponent 1 serves from the deuce/);
    await click("You win the point");
    assert.match(await next(), /Your partner serves from the ad/);
    await click("3–2 change ends next");
    await click("You win the point");
    assert.match(await result(), /players & balls change ends/, "4–2 is also six total points");
    await click("10–10 plays on");
    await click("You win the point");
    await click("You win the point");
    assert.equal(await points("me"), "12");
    assert.ok(await page.getByRole("button", { name: "Opponent wins", exact: true }).isEnabled(), "perpetual play continues past a two-point lead after ten");
    assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), "practice page fits a mobile viewport");
    assert.match(await page.getByRole("link", { name: "Download on the App Store", exact: true }).getAttribute("href"), /id6757105622/);

    for (const [path, format] of [["fast4", "fast4"], ["shortset", "shortSets"], ["perpetual", "perpetualSuperTiebreak"], ["tiebreak", "perpetualSuperTiebreak"]]) {
      await page.goto(new URL(`${path}.html?scene=tiebreak`, url).href);
      await page.waitForURL(destination => destination.pathname.endsWith("/doubles-tournaments-formats.html") && destination.searchParams.get("format") === format);
      assert.equal(await page.getByRole("button", { name: "Doubles", exact: true }).getAttribute("aria-pressed"), "true");
      assert.equal(await page.locator('[data-scene="tiebreak"]').getAttribute("aria-pressed"), "true");
    }
    await page.goto(new URL("fast4.html?type=singles", url).href);
    await page.waitForURL("**/doubles-tournaments-formats.html?*");
    assert.equal(await page.getByRole("button", { name: "Singles", exact: true }).getAttribute("aria-pressed"), "true");

    await page.goto(new URL("try.html?fast4&scene=decider", url).href);
    const watchScore = await page.evaluate(() => {
      const state = window.DeuceMateShell.api.stateRef();
      return [state.format, state.matchType, state.sets[0].tieBreakPointsMe, state.sets[0].tieBreakPointsOpponent];
    });
    assert.deepEqual(watchScore, ["fast4", "doubles", 4, 4], "existing Watch deep links keep their presets");
    assert.deepEqual(errors, []);
  } finally { await context.close(); }
}

async function run() {
  const server = await serve();
  const url = `http://127.0.0.1:${server.address().port}/index.html`;
  const browser = await browserType.launch();
  try {
    {
      const { context, page, errors, demoRequests } = await start(browser);
      await page.goto(url, { waitUntil: "networkidle" });
      assert.equal(demoRequests.length, 0, "the demo must not download until asked for");
      assert.equal(await page.locator(".hero-actions a[href='#try']").count(), 1, "hero button goes to the Try section");
      assert.equal(await page.locator("#nav-links a[href='#try']").count(), 1, "nav goes to the Try section");
      assert.deepEqual(await page.locator("[data-home-try]").evaluateAll(links => links.map(l => l.getAttribute("href"))), ["try.html", "try.html"], "without JS the links open try.html");

      // A lazy image can settle at a slightly different height once it arrives,
      // which would otherwise read as the demo's styles moving the page.
      await page.evaluate(() => Promise.all([...document.images].map(image => { image.loading = "eager"; return image.decode().catch(() => {}); })));
      const before = await page.evaluate(layoutSnapshot);
      await page.getByRole("link", { name: "See sample coaching" }).click();
      const title = page.locator("#iphone-demo .pr-native-section-title", { hasText: "Coaching Insights" });
      await title.waitFor({ state: "visible", timeout: 15000 });
      assert.ok(await page.locator("#iphone-demo .pr-coach-line").count() > 0, "the sample match shows insights");
      assert.equal(await page.locator("[data-home-try-launch]").isVisible(), false, "the launch card gives way to the demo");

      const inFrame = await title.evaluate(node => {
        const box = node.getBoundingClientRect(), frame = node.closest(".phone-body").getBoundingClientRect();
        return box.top >= frame.top && box.bottom <= frame.bottom;
      });
      assert.ok(inFrame, "the insights are scrolled into view inside the phone");
      const panelTop = await page.locator("#panel-iphone").evaluate(node => node.getBoundingClientRect().top);
      assert.ok(panelTop >= 0 && panelTop < 200, `the page lands on the iPhone (top ${panelTop})`);
      assert.ok(await page.locator("#try .about-demo").isVisible(), "the replica disclosure comes with the demo");

      const after = await page.evaluate(layoutSnapshot);
      const changed = before.map((row, i) => row === after[i] ? null : `${row}  =>  ${after[i]}`).filter(Boolean);
      assert.deepEqual(changed.slice(0, 10), [], "the demo's styles must not change the rest of the page");
      assert.deepEqual(errors, [], "no page errors");
      await context.close();
    }

    {
      const { context, page, errors } = await start(browser);
      await page.goto(url, { waitUntil: "networkidle" });
      await page.getByRole("link", { name: "Score on the Watch" }).click();
      // The Watch draws before the iPhone's scripts finish, so wait for the load itself.
      await page.locator("[data-home-try-launch]").waitFor({ state: "hidden", timeout: 15000 });
      const watchTop = await page.locator("#panel-watch").evaluate(node => node.getBoundingClientRect().top);
      assert.ok(watchTop >= 0 && watchTop < 200, `the page lands on the Watch (top ${watchTop})`);

      const watch = page.locator("#watch-demo");
      await watch.getByRole("button", { name: /Start Match/ }).first().click();
      await watch.getByRole("button", { name: "Warm Up Complete", exact: true }).first().click();
      await watch.getByRole("button", { name: "Me", exact: true }).first().click();
      await watch.locator("[data-me-row]").waitFor({ state: "visible" });
      const scoreBefore = await score(page);
      await page.keyboard.press("ArrowUp");
      assert.notEqual(await score(page), scoreBefore, "arrow keys score once the Watch is in use");

      await page.locator("footer").scrollIntoViewIfNeeded();
      await page.waitForTimeout(100);
      const scoreOff = await score(page);
      await page.mouse.click(5, 5);
      await page.keyboard.press("ArrowUp");
      assert.equal(await score(page), scoreOff, "arrow keys leave the score alone once the visitor has moved on");
      assert.deepEqual(errors, [], "no page errors");
      await context.close();
    }

    {
      const { context, page } = await start(browser);
      await page.route("**/try.html", route => route.request().resourceType() === "fetch" ? route.abort() : route.continue());
      await page.goto(url, { waitUntil: "networkidle" });
      await Promise.all([page.waitForURL("**/try.html", { timeout: 10000 }), page.getByRole("link", { name: "See sample coaching" }).click()]);
      await context.close();
    }

    {
      const { context, page, errors, demoRequests } = await start(browser, { viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true });
      await page.goto(url, { waitUntil: "networkidle" });
      assert.equal(demoRequests.length, 0, "phones don't download the demo up front either");
      await page.getByRole("link", { name: "See sample coaching" }).tap();
      await page.locator("#iphone-demo .pr-native-section-title", { hasText: "Coaching Insights" }).waitFor({ state: "visible", timeout: 15000 });
      const widths = await page.evaluate(() => [document.documentElement.scrollWidth, innerWidth]);
      assert.ok(widths[0] <= widths[1], `no sideways scroll on a phone (${widths})`);
      assert.equal(await page.locator("#iphone-demo .phone-body").evaluate(node => getComputedStyle(node).overscrollBehaviorY), "auto", "scrolling can leave the simulated phone");
      assert.deepEqual(errors, [], "no page errors");
      await context.close();
    }
    await checkClubFormats(browser, url);
    console.log("home and club-format demo QA passed");
  } finally {
    await browser.close();
    server.close();
  }
}

run().catch(error => { console.error(error); process.exit(1); });
