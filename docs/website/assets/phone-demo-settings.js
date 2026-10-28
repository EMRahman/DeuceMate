/* Phone settings and manual archive entry for the browser replica.
   All device services shown here are explicitly simulated; this module never
   touches Apple Watch, HealthKit, iCloud, or the native app. */
(function () {
  "use strict";

  var COPY = {
    track: "After each point, tag the winner and shot to build detailed stats.",
    compass: "Uses the watch compass to confirm your court end at changeovers.",
    theme: "Sets the scoreboard color theme on both your iPhone and watch.",
    announce: "Speaks the score aloud through your iPhone speaker.",
    input: "Lets you swipe to score on the iPhone scoreboard.",
    birth: "Estimates your maximum heart rate from your age.",
    override: "Sets your maximum heart rate manually instead of by age.",
    level: "Your skill level, used to tailor AI coaching advice."
  };
  var THEMES = [["default", "Classic"], ["clayCourt", "Clay Court"], ["grassCourt", "Grass Court"], ["hardCourtDay", "Hard Court"], ["hardCourtNight", "Hard Court (Night)"]];
  var LEVELS = [["2.5–3.0", "Beginner (2.5–3.0)"], ["3.0–3.5", "Intermediate (3.0–3.5)"], ["3.5–4.5", "Club player (3.5–4.5)"]];
  var POINTS = ["0", "15", "30", "40", "AD"];
  var manualState = { format: "standard", type: "singles", started: localDateTime(), completed: 0,
    sets: [{ me: 0, opp: 0, tbMe: 0, tbOpp: 0 }, { me: 0, opp: 0, tbMe: 0, tbOpp: 0 }],
    gamesMe: 0, gamesOpp: 0, tieBreak: false, tbMe: 0, tbOpp: 0,
    pointsMe: 0, pointsOpp: 0, server: "me", doublesServer: "me", secondServe: false };
  var manualActive = false;

  function localDateTime() {
    var d = new Date(), pad = function (n) { return String(n).padStart(2, "0"); };
    return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) + "T" + pad(d.getHours()) + ":" + pad(d.getMinutes());
  }
  function node(tag, attrs, text) {
    var el = document.createElement(tag);
    Object.keys(attrs || {}).forEach(function (key) {
      if (key === "class") el.className = attrs[key];
      else if (key === "text") el.textContent = attrs[key];
      else if (key.slice(0, 2) === "on") el.addEventListener(key.slice(2), attrs[key]);
      else if (key === "value" || key === "type" || key === "min" || key === "max" || key === "step" || key === "name" || key === "accept") el[key] = attrs[key];
      else el.setAttribute(key, attrs[key]);
    });
    if (text != null) el.textContent = text;
    return el;
  }
  function label(text, child) { var l = node("label", { class: "phone-field" }); l.appendChild(node("span", {}, text)); l.appendChild(child); return l; }
  function textInput(value, onChange, placeholder) {
    var e = node("input", { type: "text", class: "phone-input", value: value || "", placeholder: placeholder || "" });
    e.addEventListener("change", function () { onChange(e.value); }); return e;
  }
  function numberInput(value, onChange, min, max) {
    var e = node("input", { type: "number", class: "phone-input", value: value, min: min, max: max, step: 1 });
    e.addEventListener("change", function () { var v = Number(e.value); if (Number.isFinite(v)) onChange(Math.max(min, Math.min(max, Math.round(v)))); }); return e;
  }
  function selectInput(value, choices, onChange) {
    var e = node("select", { class: "phone-input" });
    choices.forEach(function (c) { var o = node("option", { value: c[0] }, c[1]); if (c[0] === value) o.selected = true; e.appendChild(o); });
    e.addEventListener("change", function () { onChange(e.value); }); return e;
  }
  function toggle(title, detail, value, update) {
    var wrap = node("div", { class: "phone-setting-row" }), copy = node("div", { class: "phone-setting-copy" });
    copy.appendChild(node("strong", {}, title)); copy.appendChild(node("span", { class: "phone-muted" }, detail));
    var input = node("input", { type: "checkbox", class: "phone-toggle" }); input.checked = !!value;
    input.setAttribute("aria-label", title); input.addEventListener("change", function () { update(input.checked); });
    wrap.append(copy, input); return wrap;
  }
  // Grouped-list rows (iOS LabeledContent / Link / Button): label left, value or chevron right.
  var syncDetailsOpen = false, pingMessage = null;
  function statusIcon(phone, ok) {
    var wrap = node("span", { class: "phone-list-status " + (ok === true ? "ok" : ok === false ? "bad" : ok === "warn" ? "warn" : "neutral") });
    wrap.appendChild(phone.icon(ok === true ? "checkCircle" : ok === false ? "xCircle" : ok === "warn" ? "exclaimCircle" : "minusCircle")); return wrap;
  }
  function statusRow(phone, title, value, ok) {
    var row = node("div", { class: "phone-list-row" }), trailing = node("span", { class: "phone-list-value" });
    trailing.append(node("span", {}, value), statusIcon(phone, ok));
    row.append(node("span", {}, title), trailing); return row;
  }
  function valueRow(title, value) {
    var row = node("div", { class: "phone-list-row" });
    row.append(node("span", {}, title), node("span", { class: "phone-list-value" }, value)); return row;
  }
  function rowBody(row, phone, iconName, title, chevron) {
    var icon = node("span", { class: "phone-list-icon" });
    icon.appendChild(phone.icon(iconName)); row.append(icon, node("span", { class: "phone-list-title" }, title));
    if (chevron) { var mark = node("span", { class: "phone-list-value" }); mark.appendChild(phone.icon("chevron")); row.appendChild(mark); }
    return row;
  }
  function linkRow(phone, iconName, title, href) {
    return rowBody(node("a", { class: "phone-list-row phone-list-link", href: href }), phone, iconName, title, true);
  }
  function buttonRow(phone, iconName, title, onClick, chevron) {
    var b = rowBody(node("button", { type: "button", class: "phone-list-row phone-list-link" }), phone, iconName, title, chevron);
    b.addEventListener("click", onClick); return b;
  }
  function section(title, children, foot) {
    var c = window.DeuceMatePhone.card(node("h3", { class: "phone-section-title" }, title));
    children.forEach(function (x) { c.appendChild(x); });
    if (foot) { var footer = window.DeuceMatePhone.note(foot); footer.classList.add("phone-section-footer"); c.appendChild(footer); } return c;
  }
  function update(phone, key, value) { phone.setSetting(key, value); phone.render(); }
  function setRow(phone, key, value) { update(phone, key, value); }
  function inform(phone, title, content) { phone.showSheet(title, content); }
  function settings(phone) {
    var s = phone.settings;
    var out = node("div", { class: "phone-settings" });
    out.appendChild(section("Apple Watch", [
      toggle("Track point outcome", COPY.track, s.track, function (v) { setRow(phone, "track", v); }),
      toggle("Changeover Compass · Experimental", COPY.compass, s.compass, function (v) { setRow(phone, "compass", v); })
    ], "These settings apply to your Apple Watch. Changes on either device are synced in this demo; the last update wins."));

    var skins = node("div", { class: "phone-theme-grid", role: "group", "aria-label": "Theme" });
    THEMES.forEach(function (choice) {
      var palette = window.DeuceMateShell.THEMES[choice[0]], selected = (s.theme || "default") === choice[0];
      var tile = phone.button("", function () { setRow(phone, "theme", choice[0]); }, "phone-theme-tile");
      tile.setAttribute("aria-label", choice[1]); tile.setAttribute("aria-pressed", String(selected));
      tile.style.setProperty("--skin-me", "rgb(" + palette.me + ")");
      tile.style.background = "rgb(" + palette.surface + ")";
      var dots = node("span", { class: "phone-theme-dots", "aria-hidden": "true" });
      [palette.me, palette.opp, palette.server].forEach(function (color) { var dot = node("i"); dot.style.background = "rgb(" + color + ")"; dots.appendChild(dot); });
      if (selected) dots.appendChild(node("b", {}, "✓"));
      tile.append(dots, node("span", {}, choice[1])); skins.appendChild(tile);
    });
    var shared = [skins];
    shared.push(node("p", { class: "phone-muted" }, COPY.theme));
    shared.push(toggle("Announce scores aloud on iPhone", COPY.announce, s.announce, function (v) { setRow(phone, "announce", v); }));
    if (s.announce) {
      shared.push(label("Your name", textInput(s.name, function (v) { setRow(phone, "name", v); }, "e.g. Federer")));
      shared.push(phone.button("Test name on iPhone speaker", function () {
        var phrase = "Hello" + ((s.name || "").trim() ? " " + s.name.trim() : "");
        if ("speechSynthesis" in window && "SpeechSynthesisUtterance" in window) window.speechSynthesis.speak(new SpeechSynthesisUtterance(phrase));
        else phone.notify("Speech playback is unavailable in this browser.");
      }, "phone-secondary"));
      shared.push(phone.note("In the native app, keep DeuceMate open during the match. Announcements pause when the phone is locked or another app is open."));
    }
    shared.push(toggle("iPhone Input", COPY.input, s.iPhoneInput, function (v) { setRow(phone, "iPhoneInput", v); }));
    if (s.iPhoneInput) shared.push(phone.note("On the live scoreboard, swipe up to award yourself a point, down for the opponent, and left to undo. The watch remains the source of truth."));
    out.appendChild(section("Shared Configurations", shared, "These settings apply to both iPhone and Apple Watch. The last value set on either device wins in the demo."));

    var now = new Date().getFullYear(), years = [["0", "Skip"]];
    for (var y = now; y >= 1940; y--) years.push([String(y), String(y)]);
    var birthAge = s.birthYear ? now - Number(s.birthYear) : 0;
    var overrideOn = !!s.override && Number(s.overrideBpm) >= 120 && Number(s.overrideBpm) <= 220;
    var bpm = overrideOn ? Number(s.overrideBpm) : (birthAge >= 5 && birthAge <= 100 ? 220 - birthAge : 190);
    var resolved = node("p", { class: "phone-muted" }, (s.birthYear ? "Max HR (resolved): " : "Max HR (default): ") + bpm + " bpm");
    resolved.classList.toggle("phone-setting-inactive", overrideOn);
    var pulse = [resolved];
    if (!s.birthYear && !s.override) pulse.push(phone.note("190 bpm default — set your birth year for accuracy."));
    var birthPicker = selectInput(String(s.birthYear || 0), years, function (v) { setRow(phone, "birthYear", Number(v)); });
    birthPicker.setAttribute("aria-label", "Birth Year");
    birthPicker.disabled = overrideOn;
    var birthRow = label("Birth Year", birthPicker), birthCopy = node("p", { class: "phone-muted" }, COPY.birth);
    birthRow.classList.toggle("phone-setting-inactive", overrideOn); birthCopy.classList.toggle("phone-setting-inactive", overrideOn);
    pulse.push(birthRow, birthCopy);
    pulse.push(toggle("Override Max HR", COPY.override, overrideOn, function (v) {
      phone.setSetting("override", v); if (v && !(s.overrideBpm >= 120 && s.overrideBpm <= 220)) phone.setSetting("overrideBpm", 180); phone.render();
    }));
    if (overrideOn) pulse.push(label("Override value (bpm)", numberInput(s.overrideBpm || 180, function (v) { setRow(phone, "overrideBpm", v); }, 120, 220)));
    out.appendChild(section("Pulse Coach (Shared)", pulse, "These settings apply to both iPhone and Apple Watch. Health data and device services are simulated in this browser demo."));
    var ntrp = LEVELS.some(function (x) { return x[0] === s.playerNTRP; }) ? s.playerNTRP : LEVELS[1][0];
    out.appendChild(section("AI Coaching", [label("Player Level (NTRP)", selectInput(ntrp, LEVELS, function (v) { setRow(phone, "playerNTRP", v); }))], COPY.level));

    var connection = phone.connection || { paired: false, reachable: false, syncing: false, lastSync: null };
    var ready = connection.activation === "ready", lastSync = "Never";
    if (connection.lastSync) { var d = new Date(connection.lastSync); lastSync = d.toDateString() === new Date().toDateString() ? d.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }) : d.toLocaleString([], { dateStyle: "medium", timeStyle: "short" }); }
    var healthy = ready && connection.paired && !connection.syncFailure;
    var syncRows = [valueRow("Last Synced", lastSync)];
    var syncNowRow = buttonRow(phone, "refresh", connection.syncing ? "Syncing…" : "Sync Now", phone.syncNow);
    syncNowRow.disabled = !!connection.syncing || !ready; syncRows.push(syncNowRow);
    if (connection.syncing) syncRows.push(node("p", { class: "phone-list-footnote" }, "Syncing…"));
    var summary = node("button", { type: "button", class: "phone-list-row phone-list-disclosure", "aria-expanded": String(syncDetailsOpen), "aria-label": "Connection Details, " + (healthy ? "healthy" : "needs attention") });
    var arrow = node("span", { class: "phone-list-value phone-list-disclosure-arrow" }); arrow.appendChild(phone.icon("chevron"));
    summary.append(node("span", { class: "phone-list-title" }, "Connection Details"), statusIcon(phone, healthy ? true : "warn"), arrow);
    summary.addEventListener("click", function () { syncDetailsOpen = !syncDetailsOpen; phone.render(); });
    syncRows.push(summary);
    if (syncDetailsOpen) {
      var details = [
        statusRow(phone, "Session", ready ? "Activated" : connection.activation === "connecting" ? "Activating" : "Not activated", ready),
        statusRow(phone, "Watch Paired", connection.paired ? "Yes" : "No", !!connection.paired),
        statusRow(phone, "Watch App Installed", connection.paired ? "Yes" : "No", !!connection.paired),
        statusRow(phone, "Watch Reachable", connection.reachable ? "Yes" : "No (normal)", connection.reachable ? true : null),
        statusRow(phone, "Pending Transfers", connection.syncing ? "1" : "0", !connection.syncing)
      ];
      var ping = buttonRow(phone, "antenna", "Ping Watch", function () {
        pingMessage = connection.paired && connection.reachable ? { ok: true, text: "Simulated Watch responded." } : { ok: false, text: "Apple Watch is unavailable." };
        phone.render();
      });
      ping.disabled = !ready; details.push(ping);
      if (pingMessage) details.push(node("p", { class: "phone-list-footnote " + (pingMessage.ok ? "ok" : "bad") }, pingMessage.text));
      var group = node("div", { class: "phone-list-nested" }); details.forEach(function (x) { group.appendChild(x); }); syncRows.push(group);
    }
    out.appendChild(section("Watch Sync", syncRows, "Match data is synced between your iPhone and Apple Watch using Apple's WatchConnectivity framework. This browser demo simulates the connection; it does not report a real Apple Watch."));

    var transfer = [buttonRow(phone, "share", "Export Match Archive", function () { exportArchive(phone); }), buttonRow(phone, "import", "Import Match Archive", function () { importArchive(phone); })];
    out.appendChild(section("Backup & Transfer", transfer, "Automatic iCloud and device restores keep scores and non-health stats, but not recorded heart rate, steps, distance, or calories. Before moving to a new iPhone, Export Match Archive here, then Import it on the new phone. Manual archive files are full-fidelity and may include those HealthKit-derived values. Browser exports are local JSON files; no cloud service is connected."));
    out.appendChild(section("About", [
      valueRow("Version", "Browser demo"),
      valueRow("Build", "Web"),
      linkRow(phone, "hand", "Privacy Policy", "privacy.html"),
      linkRow(phone, "help", "Support & FAQ", "support.html"),
      linkRow(phone, "mail", "Contact Support", "mailto:mail@ehsanrahman.com?subject=DeuceMate%20Support")
    ], "No developer backend, analytics, or tracking. This browser replica keeps matches in local browser storage; the native app stores them on your Apple devices with an automatic copy, minus HealthKit measurements, in your personal iCloud Drive. Exports or shares may send data to a recipient or service you choose."));
    // Form headers and explanatory footers sit outside the rounded list rows.
    out.querySelectorAll(".phone-card").forEach(function (group) {
      var title = group.querySelector(".phone-section-title"), footer = group.querySelector(".phone-section-footer");
      if (title) group.before(title);
      if (footer) group.after(footer);
    });
    return out;
  }

  function exportArchive(phone) {
    var recs = phone.records();
    var health = archiveHealthFields(recs);
    if (health.length) {
      var disclosure = node("div", { class: "phone-demo-disclosure" });
      disclosure.appendChild(phone.note("This export includes your recorded " + joinWords(health) + ". DeuceMate has no server and never receives it, but the Files app or iCloud Drive location you choose will receive it."));
      disclosure.appendChild(phone.button("Export", function () { phone.closeSheet(); downloadArchive(phone, recs); }, "phone-primary"));
      disclosure.appendChild(phone.button("Cancel", function () { phone.closeSheet(); }, "phone-secondary"));
      phone.showSheet("Export Match Archive", disclosure, { presentation: "alert" }); return;
    }
    downloadArchive(phone, recs);
  }
  function joinWords(words) {
    if (words.length < 2) return words[0] || "";
    if (words.length === 2) return words[0] + " and " + words[1];
    return words.slice(0, -1).join(", ") + ", and " + words[words.length - 1];
  }
  function archiveHealthFields(records) {
    var fields = [];
    function add(key) { if (fields.indexOf(key) < 0) fields.push(key); }
    records.forEach(function (r) {
      if (r.stats.some(function (p) { return p.heartRateBPM != null; })) add("heart rate");
      if (r.stats.some(function (p) { return p.stepsCumulative != null; }) || Number(r.steps) > 0) add("steps");
      if (Number(r.kcal) > 0) add("calories");
      if (r.distanceMeters != null && Number(r.distanceMeters) > 0) add("distance");
    });
    return fields;
  }
  function downloadArchive(phone, recs) {
    var payload = { format: "deucemate-browser-demo-archive", version: 1, exportedAt: new Date().toISOString(), records: recs };
    if (phone.download("deucemate_archive_" + new Date().toISOString().slice(0, 10) + ".json", "application/json", JSON.stringify(payload, null, 2))) {
      phone.notify("Archive exported to a local JSON file (" + recs.length + " matches).");
    }
  }
  function validRecord(r) {
    if (!r || typeof r !== "object" || typeof r.id !== "string" || !r.id || !Number.isFinite(r.startTime) ||
        !(r.endTime == null || Number.isFinite(r.endTime)) ||
        ["standard", "bestOf3FullFinalSet", "quick4Games", "superTiebreak", "perpetualSuperTiebreak", "perpetualPoints"].indexOf(r.format) < 0 ||
        ["singles", "doubles"].indexOf(r.matchType) < 0 || !Array.isArray(r.sets) || !Array.isArray(r.stats) ||
        !(r.iWon == null || typeof r.iWon === "boolean") || !Number.isFinite(r.currentPointsMe) || !Number.isFinite(r.currentPointsOpponent) ||
        !Number.isFinite(r.elapsed) || !r.setElapsed || typeof r.setElapsed !== "object" || !Number.isFinite(r.steps) || !Number.isFinite(r.kcal) || !Number.isFinite(r.pointsPlayed) ||
        !r.sets.every(function (x) { return x && Number.isInteger(x.gamesMe) && x.gamesMe >= 0 && Number.isInteger(x.gamesOpponent) && x.gamesOpponent >= 0 && typeof x.isTieBreak === "boolean" && Number.isInteger(x.tieBreakPointsMe) && x.tieBreakPointsMe >= 0 && Number.isInteger(x.tieBreakPointsOpponent) && x.tieBreakPointsOpponent >= 0; }) ||
        !r.stats.every(function (x) { return x && Number.isInteger(x.setIndex) && x.setIndex >= 0 && ["me", "opponent"].indexOf(x.server) >= 0 && ["me", "opponent"].indexOf(x.winner) >= 0 && ["doubleFault", "winner", "forcedError", "unforcedError", "uncategorized"].indexOf(x.outcome) >= 0 && typeof x.isSecondServe === "boolean" && typeof x.isBreakPoint === "boolean" && (x.endingShot == null || ["serve", "return", "servePlusOne", "rally"].indexOf(x.endingShot) >= 0); })) return false;
    if (!r.sets.length || !r.stats.every(function (p) {
      return p.setIndex < r.sets.length &&
        (p.heartRateBPM == null || (Number.isFinite(p.heartRateBPM) && p.heartRateBPM >= 0)) &&
        (p.stepsCumulative == null || (Number.isFinite(p.stepsCumulative) && p.stepsCumulative >= 0)) &&
        (p.gameScoreAtStart == null || (typeof p.gameScoreAtStart.isTiebreak === "boolean" &&
          Number.isInteger(p.gameScoreAtStart.server) && p.gameScoreAtStart.server >= 0 &&
          Number.isInteger(p.gameScoreAtStart.returner) && p.gameScoreAtStart.returner >= 0));
    })) return false;
    if (r.endTime != null) return true;
    var resume = r.resume, state = resume && resume.state;
    return !!(state && state.format === r.format && ["me", "opponent"].indexOf(state.currentServer) >= 0 && Array.isArray(state.sets) &&
      Number.isFinite(state.currentPointsMe) && Number.isFinite(state.currentPointsOpponent) && Number.isFinite(state.gameCount) &&
      Number.isFinite(state.pointCountInTiebreak) && Array.isArray(resume.momentum) && typeof resume.trackingEnabled === "boolean" &&
      state.matchType === r.matchType && JSON.stringify(state.sets) === JSON.stringify(r.sets) &&
      state.currentPointsMe === r.currentPointsMe && state.currentPointsOpponent === r.currentPointsOpponent &&
      Array.isArray(state.doublesServiceOrder) &&
      state.doublesServiceOrder.every(function (s) { return ["me", "partner", "opponentS1", "opponentS2"].indexOf(s) >= 0; }) &&
      (r.matchType !== "doubles" || (state.doublesServiceOrder.length === 4 &&
        Number.isInteger(state.doublesServiceIndex) && state.doublesServiceIndex >= 0 && state.doublesServiceIndex < 4)));
  }
  function importArchive(phone) {
    var file = node("input", { type: "file", accept: "application/json", class: "phone-file-input" });
    file.addEventListener("change", function () {
      if (!file.files || !file.files[0]) return;
      var reader = new FileReader();
      reader.onload = function () {
        try {
          var data = JSON.parse(String(reader.result)), incoming = data && data.records;
          if (!data || data.format !== "deucemate-browser-demo-archive" || data.version !== 1 || !Array.isArray(incoming) || !incoming.every(validRecord)) throw new Error("This file is not a valid DeuceMate browser demo archive.");
          phone.showSheet("Import Match Archive", archiveImportChoices(phone, incoming), { presentation: "actions" });
        } catch (e) { phone.notify("Import failed: " + e.message); }
      };
      reader.onerror = function () { phone.notify("Import failed: could not read the selected file."); };
      reader.readAsText(file.files[0]);
    });
    file.click();
  }
  function archiveImportChoices(phone, incoming) {
    var wrap = node("div", { class: "phone-demo-disclosure" });
    wrap.appendChild(node("p", {}, "Found " + incoming.length + " matches. Choose how to apply this archive to the browser demo."));
    wrap.appendChild(phone.button("Merge", function () {
      var map = Object.create(null); phone.records().concat(incoming).forEach(function (r) { map[r.id] = r; });
      phone.replaceRecords(Object.keys(map).map(function (id) { return map[id]; })); phone.closeSheet(); phone.notify("Archive merged.");
    }, "phone-primary"));
    wrap.appendChild(phone.button("Replace Archive", function () {
      phone.confirm("Replace Match Archive?", "Replace " + phone.records().length + " current matches with " + incoming.length + " imported matches?", "Replace Archive", function () {
        phone.replaceRecords(incoming); phone.notify("Archive replaced.");
      });
    }, "phone-secondary"));
    wrap.appendChild(phone.button("Cancel", function () { phone.closeSheet(); }, "phone-secondary"));
    return wrap;
  }

  function setIsTB(x) { return x.me + x.opp === 13; }
  function completedValid(x) {
    var high = Math.max(x.me, x.opp), low = Math.min(x.me, x.opp);
    if (!((high >= 6 && high - low >= 2) || x.me === 7 || x.opp === 7)) return false;
    return !setIsTB(x) || x.tbMe + x.tbOpp > 0;
  }
  function manualValid() {
    if (!Number.isFinite(new Date(manualState.started).getTime())) return false;
    if (manualState.pointsMe === 4 && (manualState.pointsOpp === 4 || manualState.pointsOpp < 3)) return false;
    if (manualState.pointsOpp === 4 && manualState.pointsMe < 3) return false;
    for (var i = 0; i < manualState.completed; i++) if (!completedValid(manualState.sets[i])) return false;
    var currentSetIsPureTiebreak = manualState.completed === 2 && manualState.format === "standard";
    if (!manualState.tieBreak && !currentSetIsPureTiebreak &&
      ((Math.max(manualState.gamesMe, manualState.gamesOpp) >= 6 && Math.abs(manualState.gamesMe - manualState.gamesOpp) >= 2) || manualState.gamesMe === 7 || manualState.gamesOpp === 7)) return false;
    return true;
  }
  function resetManual() {
    manualState = { format: "standard", type: "singles", started: localDateTime(), completed: 0,
      sets: [{ me: 0, opp: 0, tbMe: 0, tbOpp: 0 }, { me: 0, opp: 0, tbMe: 0, tbOpp: 0 }],
      gamesMe: 0, gamesOpp: 0, tieBreak: false, tbMe: 0, tbOpp: 0,
      pointsMe: 0, pointsOpp: 0, server: "me", doublesServer: "me", secondServe: false };
  }
  function group(title, children, footer) {
    var wrap = node("div", {class: "phone-manual-section"}), card = window.DeuceMatePhone.card();
    if (title) wrap.append(node("h3", {class: "phone-section-title"}, title));
    children.forEach(function(child){card.append(child);});wrap.append(card);
    if (footer) wrap.append(node("p", {class: "phone-note phone-section-footer"}, footer));return wrap;
  }
  function stepper(title, value, min, max, change, key) {
    var row = node("div", {class: "phone-manual-stepper", role: "group", "aria-label": title});
    var number = numberInput(value, change, min, max); number.setAttribute("aria-label", title);
    if (key === "completed") {number.classList.add("phone-visually-hidden");number.setAttribute("aria-hidden", "true");number.tabIndex = -1;}
    var controls = node("div", {class: "phone-stepper-buttons"});
    [["−", -1, "Decrease"], ["+", 1, "Increase"]].forEach(function (item) {
      var button = window.DeuceMatePhone.button(item[0], function () {change(Math.max(min, Math.min(max, value + item[1])));}, "phone-stepper-button");
      button.setAttribute("aria-label", item[2] + " " + title); button.disabled = item[1] < 0 ? value <= min : value >= max;
      button.dataset.focusKey = "manual-" + (key || title) + "-" + item[1]; controls.append(button);
    });
    row.append(node("span", {class: "phone-manual-label"}, title), number, controls); return row;
  }
  function manualServerInputs(phone) {
    var out = [label("Server", selectInput(manualState.server, [["me", "Me"], ["opponent", "Opponent"]], function (v) { manualState.server = v; phone.render(); }))];
    if (manualState.type === "doubles") out.push(label("Serving player", selectInput(manualState.doublesServer, [["me", "Me"], ["partner", "Partner"], ["opponentS1", "Opponent 1"], ["opponentS2", "Opponent 2"]], function (v) {
      manualState.doublesServer = v; manualState.server = v.indexOf("opponent") === 0 ? "opponent" : "me"; phone.render();
    })));
    return out;
  }
  function scoreInputRow(phone, title, key, min, max) {
    return stepper(title, manualState[key], min, max, function (v) {
      manualState[key] = v;
      if ((key === "gamesMe" || key === "gamesOpp") && !(manualState.gamesMe === 6 && manualState.gamesOpp === 6)) manualState.tieBreak = false;
      phone.render();
    }, key);
  }
  function manualToggle(title, checked, update) {
    var input = node("input", {type: "checkbox", class: "phone-toggle", "aria-label": title}); input.checked = checked;
    input.addEventListener("change", function () {update(input.checked);}); return label(title, input);
  }
  function manual(phone) {
    if (!manualActive) { resetManual(); manualActive = true; }
    var out = node("div", { class: "phone-manual" });
    var start = manualState.started.split("T"), date = node("input", {type: "date", value: start[0], "aria-label": "Start date"}), time = node("input", {type: "time", value: start[1] || "00:00", "aria-label": "Start time"});
    var started = node("div", {class: "phone-field phone-manual-started"}), dateControls = node("div", {class: "phone-manual-date"});
    dateControls.append(date, time); started.append(node("span", {}, "Started"), dateControls);
    function updateStarted() {manualState.started = date.value && time.value ? date.value + "T" + time.value : ""; save.disabled = !manualValid();}
    [date, time].forEach(function (field) {field.addEventListener("input", updateStarted);field.addEventListener("change", updateStarted);});
    out.appendChild(group("Match", [
      label("Format", selectInput(manualState.format, [["standard", "Best of 3 (Super TB Decider)"], ["bestOf3FullFinalSet", "Best of 3 (Full Final Set)"]], function (v) { manualState.format = v; phone.render(); })),
      label("Type", selectInput(manualState.type, [["singles", "Singles"], ["doubles", "Doubles"]], function (v) { manualState.type = v; phone.render(); })), started
    ]));
    out.appendChild(group("", [stepper("Completed sets: " + manualState.completed, manualState.completed, 0, 2, function (v) {manualState.completed = v; phone.render();}, "completed")], "How many sets are finished. The next set is the one currently in play."));
    for (var i = 0; i < manualState.completed; i++) {
      (function (idx) {
        var set = manualState.sets[idx];
        function scoreRow(title, key, max) {return stepper(title, set[key], 0, max, function(v){set[key] = v;phone.render();}, "set-" + idx + "-" + key);}
        out.appendChild(group("Set " + (idx + 1) + " (final)", [scoreRow("Me", "me", 7), scoreRow("Opponent", "opp", 7),
          setIsTB(set) ? scoreRow("Tiebreak — Me", "tbMe", 30) : null, setIsTB(set) ? scoreRow("Tiebreak — Opp", "tbOpp", 30) : null].filter(Boolean)));
      })(i);
    }
    var pure = manualState.completed === 2 && manualState.format === "standard", cur = [];
    if (pure) cur.push(scoreInputRow(phone, "Super TB — Me", "tbMe", 0, 30), scoreInputRow(phone, "Super TB — Opp", "tbOpp", 0, 30));
    else {
      cur.push(scoreInputRow(phone, "Games — Me", "gamesMe", 0, 6), scoreInputRow(phone, "Games — Opp", "gamesOpp", 0, 6));
      if (manualState.gamesMe === 6 && manualState.gamesOpp === 6) {
        cur.push(manualToggle("In set tiebreak", manualState.tieBreak, function(v){manualState.tieBreak = v;phone.render();}));
        if (manualState.tieBreak) cur.push(scoreInputRow(phone, "TB — Me", "tbMe", 0, 30), scoreInputRow(phone, "TB — Opp", "tbOpp", 0, 30));
      }
    }
    if (pure || manualState.tieBreak) cur = cur.concat(manualServerInputs(phone));
    out.appendChild(group("Current Set (Set " + (manualState.completed + 1) + " — in progress)", cur));
    if (!pure && !manualState.tieBreak) {
      var game = manualServerInputs(phone);
      game.push(label("Me points", selectInput(String(manualState.pointsMe), POINTS.map(function (x, j) { return [String(j), x]; }), function (v) { manualState.pointsMe = Number(v); phone.render(); })));
      game.push(label("Opp points", selectInput(String(manualState.pointsOpp), POINTS.map(function (x, j) { return [String(j), x]; }), function (v) { manualState.pointsOpp = Number(v); phone.render(); })));
      game.push(manualToggle("Second serve", manualState.secondServe, function(v){manualState.secondServe=v;})); out.appendChild(group("Current Game", game));
    }
    var save = phone.button("Save Match", function () {
      if (!manualValid()) return;
      phone.addRecord(buildManualRecord()); phone.navigate("matches"); phone.notify("In-progress match saved. It can be resumed in the watch simulator.");
    }, "phone-manual-save");
    save.disabled = !manualValid();
    out.appendChild(group("", [save], phone.connection.paired ? "The match will be added as in progress and sent to your Apple Watch so you can resume scoring there." : "The match will be saved as in progress on this iPhone. You can review and export it here without an Apple Watch."));
    return out;
  }
  function buildManualRecord() {
    var sets = [];
    for (var i = 0; i < manualState.completed; i++) {
      var x = manualState.sets[i]; sets.push({ gamesMe: x.me, gamesOpponent: x.opp, isTieBreak: setIsTB(x), tieBreakPointsMe: setIsTB(x) ? x.tbMe : 0, tieBreakPointsOpponent: setIsTB(x) ? x.tbOpp : 0 });
    }
    var pure = manualState.completed === 2 && manualState.format === "standard", tie = pure || manualState.tieBreak;
    sets.push({ gamesMe: pure ? 0 : (tie ? 6 : manualState.gamesMe), gamesOpponent: pure ? 0 : (tie ? 6 : manualState.gamesOpp), isTieBreak: tie, tieBreakPointsMe: tie ? manualState.tbMe : 0, tieBreakPointsOpponent: tie ? manualState.tbOpp : 0 });
    var points = tie ? 0 : manualState.pointsMe, pointsOpp = tie ? 0 : manualState.pointsOpp;
    var scoring = window.DeuceMateScoring;
    var state = scoring.freshState(manualState.format, manualState.server);
    state.sets = sets;
    state.matchType = manualState.type;
    state.currentServer = manualState.server;
    state.currentPointsMe = points;
    state.currentPointsOpponent = pointsOpp;
    state.gameCount = sets.reduce(function (sum, x) { return sum + x.gamesMe + x.gamesOpponent; }, 0);
    state.pointCountInTiebreak = tie ? manualState.tbMe + manualState.tbOpp : 0;
    state.tiebreakStartServer = tie ? derivedTiebreakStartServer(manualState.server, state.pointCountInTiebreak) : null;
    state.tiebreakFirstPointReceiver = tie ? (state.tiebreakStartServer === "me" ? "opponent" : "me") : null;
    state.lastTiebreakPointServer = null;
    state.needsDoublesTeamServerDecision = false;
    state.doublesServiceOrder = manualState.type === "doubles" ? doublesRotation(manualState.doublesServer) : [];
    state.doublesServiceIndex = 0;
    state.doublesServer = manualState.type === "doubles" ? manualState.doublesServer : null;
    state.doublesTiebreakStartIndex = manualState.type === "doubles" && tie ? tiebreakStartDoublesIndex(state.pointCountInTiebreak) : 0;
    var tracking = !!(window.DeuceMateShell && window.DeuceMateShell.settings.track) && manualState.format !== "perpetualPoints";
    return { id: "manual-" + Date.now().toString(36), startTime: new Date(manualState.started).getTime(), endTime: null,
      iWon: null, format: manualState.format, matchType: manualState.type, sets: sets, currentPointsMe: points, currentPointsOpponent: pointsOpp,
      stats: [], trackingOn: tracking, elapsed: 0, setElapsed: {}, steps: 0, kcal: 0, pointsPlayed: 0,
      resume: { state: state, momentum: [], secondServe: tie ? false : manualState.secondServe, trackingEnabled: tracking } };
  }

  function derivedTiebreakStartServer(upcomingServer, pointsPlayed) {
    var nextPointNumber = pointsPlayed + 1, nextIsStart;
    if (nextPointNumber === 1) nextIsStart = true;
    else nextIsStart = Math.floor((nextPointNumber - 2) / 2) % 2 === 1;
    return nextIsStart ? upcomingServer : (upcomingServer === "me" ? "opponent" : "me");
  }
  function doublesRotation(server) {
    switch (server) {
      case "me": return ["me", "opponentS1", "partner", "opponentS2"];
      case "partner": return ["partner", "opponentS1", "me", "opponentS2"];
      case "opponentS1": return ["opponentS1", "me", "opponentS2", "partner"];
      default: return ["opponentS2", "me", "opponentS1", "partner"];
    }
  }
  function tiebreakStartDoublesIndex(pointsPlayed) {
    var nextPointNumber = pointsPlayed + 1;
    var offset = nextPointNumber === 1 ? 0 : Math.floor((nextPointNumber - 2) / 2) + 1;
    return (4 - (offset % 4)) % 4;
  }

  window.DeuceMatePhoneSettings = { settings: settings, manual: manual, validRecord: validRecord,
    resetManual: function () { resetManual(); manualActive = false; } };
}());
