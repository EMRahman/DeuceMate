#!/usr/bin/env node
/* Native report, complete clipboard prompt, manual form and rotation checks. */
"use strict";
const assert = require("node:assert/strict"), fs = require("node:fs"), path = require("node:path");
const {pathToFileURL} = require("node:url");
const {chromium,webkit} = require(process.env.PLAYWRIGHT_MODULE || "playwright");
const engine = process.env.PLAYWRIGHT_BROWSER || "chromium", output = "/tmp/deucemate-iphone-qa";
async function main() {
  fs.mkdirSync(output,{recursive:true});
  const browser=await (engine==="webkit"?webkit:chromium).launch({headless:true});
  const context=await browser.newContext({viewport:{width:1280,height:1000},colorScheme:"light"}),page=await context.newPage(),errors=[];
  page.setDefaultTimeout(8000);page.on("pageerror",e=>errors.push(e.message));
  const root=page.locator("#iphone-demo"),frame=root.locator(".phone-frame"),nav=root.locator(".phone-nav"),dialog=root.locator(".phone-dialog");
  const click=(scope,name)=>scope.getByRole("button",{name,exact:typeof name==="string"}).click();
  const capture=name=>frame.screenshot({path:path.join(output,`${engine}-${name}.png`)});
  async function change(scope,label,value){const field=scope.getByRole("spinbutton",{name:label,exact:true});await field.fill(String(value));await field.dispatchEvent("change");}
  async function download(action){const waiting=page.waitForEvent("download");await action();const item=await waiting,stream=await item.createReadStream();let content="";for await(const chunk of stream)content+=chunk.toString("utf8");return {content,name:item.suggestedFilename()};}
  function rawRows(prompt){return prompt.split("\n").filter(line=>/^\| \d+ \|/.test(line));}
  try {
    await page.goto(process.env.PLAYWRIGHT_URL||pathToFileURL(path.resolve(__dirname,"../docs/website/try.html")).href);
    await click(nav,"Manual match entry");
    const manual=root.locator(".phone-manual");
    assert.equal(await nav.getByRole("button",{name:"Cancel",exact:true}).count(),1);
    assert.equal(await manual.getByRole("button",{name:"Cancel",exact:true}).count(),0);
    assert.equal(await manual.locator('input[type="date"]').count(),1);assert.equal(await manual.locator('input[type="time"]').count(),1);
    assert.equal(await manual.getByRole("button",{name:"Increase Games — Me",exact:true}).count(),1);
    await capture("manual-native-light");await page.emulateMedia({colorScheme:"dark"});await capture("manual-native-dark");await page.emulateMedia({colorScheme:"light"});
    await click(manual,/^Increase Completed sets:/);
    const set=manual.locator(".phone-manual-section").filter({hasText:"Set 1 (final)"});
    await change(set,"Me",7);await change(set,"Opponent",6);
    assert.equal(await set.getByRole("spinbutton",{name:"Tiebreak — Me",exact:true}).count(),1);
    await change(set,"Tiebreak — Me",7);await change(set,"Tiebreak — Opp",5);
    assert.equal(await manual.getByRole("button",{name:"Save Match",exact:true}).isEnabled(),true);
    await capture("manual-native-completed-set");
    // The native app is portrait-locked outside the live scoreboard, so the replica must not rotate here.
    assert.equal(await root.locator(".phone-device-rotate").isDisabled(),true,"manual entry cannot rotate");
    let box=await frame.boundingBox();assert.ok(box.height>box.width,"manual entry stays portrait");
    await click(nav,"Cancel");await click(nav,"Manual match entry");
    assert.equal(await manual.getByRole("button",{name:/^Increase Completed sets: 0$/}).count(),1,"Cancel discards form state");await click(nav,"Cancel");
    const record=await page.evaluate(()=>window.DeuceMatePhone.records().find(r=>r.endTime&&r.stats.some(p=>p.heartRateBPM!=null)));
    await root.locator(`.phone-match-wrap[data-match-id="${record.id}"] .phone-match-row`).click();
    await page.evaluate(()=>Object.defineProperty(navigator,"clipboard",{configurable:true,value:{writeText:text=>{window.capturedPrompt=text;return Promise.resolve();}}}));
    await click(nav,"Open AI Coach");await click(dialog,"Continue");await click(dialog,"Copy Prompt");
    const prompt=await page.evaluate(()=>window.capturedPrompt);
    assert.equal(rawRows(prompt).length,record.stats.length,"clipboard includes all match points");
    assert.ok(rawRows(prompt).at(-1).startsWith(`| ${record.stats.length} |`));
    assert.ok(prompt.includes("Biggest Weakness")&&prompt.includes("## Serve Performance")&&prompt.includes("## Heart Rate Analysis"));
    assert.equal(await dialog.getByLabel("AI coaching prompt").inputValue(),prompt,"preview and clipboard use the identical prompt");
    await page.evaluate(()=>{window.capturedPrompt=null;});await click(dialog,"Open in ChatGPT");
    assert.equal(await page.evaluate(()=>window.capturedPrompt),prompt,"AI app hand-off also copies every point before its simulated launch");
    await click(dialog.getByRole("group",{name:"Perspective",exact:true}),"Opponent's");await click(dialog,"Copy Prompt");
    const opponentPrompt=await page.evaluate(()=>window.capturedPrompt);
    assert.equal(rawRows(opponentPrompt).length,record.stats.length);assert.ok(opponentPrompt.includes('"Me" = your opponent (the recorder)'));
    assert.equal(opponentPrompt.includes("## Heart Rate Analysis"),false);
    await click(dialog,"More Share Options…");const shared=await download(()=>click(dialog,"Download Prompt"));assert.equal(shared.content,opponentPrompt,"shared prompt preserves every clipboard byte");
    const files=[];
    for(const perspective of ["My Perspective","Opponent's Perspective"]){
      await click(nav,"Share match");await click(dialog,"Interactive Web Page");await click(dialog.locator(".pr-share-submenu"),perspective);
      const report=await download(()=>click(dialog,"Share"));const file=path.join(output,`${engine}-${perspective==="My Perspective"?"my":"opponent"}-native-report.html`);fs.writeFileSync(file,report.content);files.push(file);
    }
    for(let index=0;index<files.length;index++) {
      const report=await context.newPage();report.on("pageerror",e=>errors.push(e.message));await report.goto(pathToFileURL(files[index]).href);
      const reportRoot=report.locator("#root");assert.equal(await reportRoot.locator(".promo").count(),1);
      assert.ok(await reportRoot.locator(".splitbar").count()>0,"export uses native split-bar stats");
      assert.equal(await report.evaluate(()=>DATA.points.length),record.stats.length);
      await click(reportRoot,"Points");assert.equal(await reportRoot.locator(".pt-row").count(),record.stats.length,"Points contains every saved rally, grouped by set");
      await click(reportRoot,"Stats");await click(reportRoot,"Set 1");assert.ok(await reportRoot.locator(".pw-card").innerText());
      await report.evaluate(()=>Object.defineProperty(navigator,"clipboard",{configurable:true,value:{writeText:text=>{window.capturedPrompt=text;return Promise.resolve();}}}));
      await click(reportRoot,"Copy Prompt");assert.equal(await report.evaluate(()=>window.capturedPrompt),index===0?prompt:opponentPrompt,"web and in-app clipboard prompts agree");
      assert.equal(await report.locator(".ai-app").count(),7);
      await report.locator(".ai-app").first().click();assert.equal(report.url(),pathToFileURL(files[index]).href,"AI demo does not navigate externally");
      await report.screenshot({path:path.join(output,`${engine}-native-report-${index}.png`),fullPage:true});await report.close();
      const noJS=await browser.newContext({javaScriptEnabled:false}),preview=await noJS.newPage();await preview.goto(pathToFileURL(files[index]).href);
      assert.ok(await preview.locator("#root svg").count()>=4,"static native-style report includes all four scatter presets");
      assert.ok(await preview.locator(".splitbar").count()>0,"static preview retains the native comparison bars");await noJS.close();
    }
    await click(nav,"Back to Matches");
    await page.evaluate(()=>{const s=window.DeuceMateShell;s.api.start({format:"standard",server:"me",tracking:false});s.liveId="export-qa-live";window.DeuceMatePhone.setSetting("iPhoneInput",true);window.DeuceMatePhone.setSetting("track",false);window.DeuceMatePhone.navigate("live");});
    // Existing Watch api owns scoring; the phone never creates another engine.
    await click(root.locator(".phone-device-controls"),"Rotate iPhone to landscape");
    const court=root.locator(".phone-scoreboard");
    await court.focus();await court.press("ArrowUp");
    await page.waitForFunction(()=>window.DeuceMateShell.api.stateRef().currentPointsMe===1);
    await page.setViewportSize({width:844,height:390});
    const gesture=await court.boundingBox();
    await page.mouse.move(gesture.x+gesture.width/2,gesture.y+gesture.height*.7);await page.mouse.down();
    await page.mouse.move(gesture.x+gesture.width/2,gesture.y+gesture.height*.7-55,{steps:8});await page.mouse.up();
    await page.waitForFunction(()=>window.DeuceMateShell.api.stateRef().currentPointsMe===2);
    await court.focus();await court.press("ArrowLeft");
    await page.waitForFunction(()=>window.DeuceMateShell.api.stateRef().currentPointsMe===1);
    for(const viewport of [{width:1280,height:1000},{width:844,height:390},{width:390,height:844}]) {
      await page.setViewportSize(viewport);box=await frame.boundingBox();assert.ok(box.width>box.height*1.6,"landscape is wide even in a portrait browser");
      const geometry=await root.locator(".phone-scoreboard").evaluate(el=>{const court=el.getBoundingClientRect();return [...el.children].map(row=>{const r=row.getBoundingClientRect();return r.top>=court.top&&r.bottom<=court.bottom+1&&row.scrollWidth<=row.clientWidth+1;});});assert.deepEqual(geometry,[true,true]);
      await capture(`live-landscape-${viewport.width}`);
    }
    assert.deepEqual(errors,[]);process.stdout.write(`Native export/prompt/manual/rotation QA passed (${engine}).\n`);
  } finally {await context.close();await browser.close();}
}
main().catch(error=>{console.error(error);process.exitCode=1;});
