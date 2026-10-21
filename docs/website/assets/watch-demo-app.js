/* ==========================================================================
   DeuceMate — the browser "Try it" as a replica of the whole Apple Watch app.

   watch-demo.js is the live match (ScoreViewModel + ContentView). This file is
   everything around it, mirroring the watch target's views one-to-one:

     HomeView            → home()            Start/Resume, setup row, tracking strip
     Match Setup sheet   → setupSheet()      Singles/Doubles + six formats
     Settings sheet      → settingsSheet()   toggles, themes, Pulse Coach, birth year
     Guide sheet         → guideSheet()      gestures, indicators, tricky rules
     RootModal           → matchSheet()      warm-up, who serves, court side, match
     (history + animated guide live in watch-demo-history.js / -guide.js)

   The only things invented are what a browser cannot sense: heart rate,
   calories, steps and the compass heading. Nothing is stored or sent anywhere;
   a reload resets the watch.
   ========================================================================== */
(function () {
  "use strict";

  var root = document.getElementById("watch-demo");
  if (!root || !root.hasAttribute("data-app")) return;
  var api = root.__deuceMateApi;
  var screenEl = root.querySelector("[data-screen]");
  var shellEl = root.querySelector("[data-shell]");
  var Scoring = window.DeuceMateScoring;
  if (!api || !shellEl || !Scoring) return;

  /* ---- DOM helper --------------------------------------------------------- */
  function h(tag, props) {
    var e = document.createElement(tag);
    props = props || {};
    Object.keys(props).forEach(function (k) {
      var v = props[k];
      if (v == null || v === false) return;
      if (k === "class") e.className = v;
      else if (k === "html") e.innerHTML = v;
      else if (k === "text") e.textContent = v;
      else if (k === "style") e.setAttribute("style", v);
      else if (k.slice(0, 2) === "on" && typeof v === "function") e.addEventListener(k.slice(2), v);
      else if (v === true) e.setAttribute(k, "");
      else e.setAttribute(k, v);
    });
    for (var i = 2; i < arguments.length; i++) append(e, arguments[i]);
    return e;
  }
  function append(e, c) {
    if (c == null || c === false) return;
    if (Array.isArray(c)) { c.forEach(function (x) { append(e, x); }); return; }
    e.appendChild(typeof c === "string" || typeof c === "number" ? document.createTextNode(String(c)) : c);
  }
  /* "**bold**" → <strong> (the watch renders these via LocalizedStringKey). */
  function md(text) {
    var f = document.createDocumentFragment();
    String(text).split("**").forEach(function (part, i) {
      if (!part) return;
      if (i % 2) f.appendChild(h("strong", { text: part })); else f.appendChild(document.createTextNode(part));
    });
    return f;
  }

  /* ---- SF-Symbol stand-ins ----------------------------------------------- */
  var ICONS = {
    play: "M8 5v14l11-7z",
    refresh: "M17.65 6.35A7.96 7.96 0 0 0 12 4a8 8 0 1 0 7.73 10h-2.08A6 6 0 1 1 12 6c1.66 0 3.14.69 4.22 1.78L13 11h7V4z",
    stop: "M6 6h12v12H6z",
    history: "M13 3a9 9 0 0 0-9 9H1l3.89 3.89.07.14L9 12H6a7 7 0 1 1 2.05 4.95l-1.42 1.42A9 9 0 1 0 13 3zm-1 5v5l4.28 2.54.72-1.21-3.5-2.08V8z",
    gear: "M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58a.49.49 0 0 0 .12-.61l-1.92-3.32a.488.488 0 0 0-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54a.484.484 0 0 0-.48-.41h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96c-.22-.08-.47 0-.59.22L2.74 8.87c-.12.21-.08.47.12.61l2.03 1.58c-.05.3-.09.63-.09.94s.02.64.07.94l-2.03 1.58a.49.49 0 0 0-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.47-.12-.61l-2.01-1.58zM12 15.6A3.6 3.6 0 1 1 12 8.4a3.6 3.6 0 0 1 0 7.2z",
    book: "M11.5 6.6C10.1 5.4 7.9 4.8 5.4 4.8 4.2 4.8 3.1 4.9 2 5.2v13.6c1.1-.3 2.2-.4 3.4-.4 2.5 0 4.7.6 6.1 1.8zM12.5 6.6c1.4-1.2 3.6-1.8 6.1-1.8 1.2 0 2.3.1 3.4.4v13.6c-1.1-.3-2.2-.4-3.4-.4-2.5 0-4.7.6-6.1 1.8z",
    down: "M7.41 8.59 12 13.17l4.59-4.58L18 10l-6 6-6-6z",
    up: "M7.41 15.41 12 10.83l4.59 4.58L18 14l-6-6-6 6z",
    right: "M8.59 16.59 13.17 12 8.59 7.41 10 6l6 6-6 6z",
    left: "M15.41 16.59 10.83 12l4.58-4.59L14 6l-6 6 6 6z",
    check: "M9 16.17 4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z",
    close: "M19 6.41 17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z",
    heart: "M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z",
    tap: "M9 11.24V7.5a2.5 2.5 0 0 1 5 0v3.74c1.21-.81 2-2.18 2-3.74C16 5.01 13.99 3 11.5 3S7 5.01 7 7.5c0 1.56.79 2.93 2 3.74zm9.84 4.63-4.54-2.26c-.17-.07-.35-.11-.54-.11H13v-6c0-.83-.67-1.5-1.5-1.5S10 6.67 10 7.5v10.74l-3.43-.72c-.08-.01-.15-.03-.24-.03-.31 0-.59.13-.79.33l-.79.8 4.94 4.94c.27.27.65.44 1.06.44h6.79c.75 0 1.33-.55 1.44-1.28l.75-5.27c.01-.07.02-.14.02-.2 0-.62-.38-1.16-.91-1.38z",
    trash: "M6 19c0 1.1.9 2 2 2h8c1.1 0 2-.9 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z",
    chart: "M5 9.2h3V19H5zM10.6 5h2.8v14h-2.8zm5.6 8H19v6h-2.8z",
    list: "M3 5h2v2H3zm4 0h14v2H7zM3 11h2v2H3zm4 0h14v2H7zM3 17h2v2H3zm4 0h14v2H7z",
    drive: "M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm-1 14H6v-2h12v2zm-9.5-1.5a1 1 0 1 1 0-2 1 1 0 0 1 0 2z",
    sync: "M12 4V1L8 5l4 4V6a6 6 0 0 1 6 6c0 1-.25 1.97-.7 2.8l1.46 1.46A7.93 7.93 0 0 0 20 12c0-4.42-3.58-8-8-8zm0 14a6 6 0 0 1-6-6c0-1 .25-1.97.7-2.8L5.24 7.74A7.93 7.93 0 0 0 4 12c0 4.42 3.58 8 8 8v3l4-4-4-4v3z",
    stopcircle: "M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm4 14H8V8h8v8z",
    playfill: "M8 5v14l11-7z"
  };
  function icon(name, size, cls) {
    var span = h("span", { class: "ic" + (cls ? " " + cls : ""), "aria-hidden": "true" });
    var px = size || 16;
    span.style.width = span.style.height = px + "px";
    if (name === "pulse") {
      span.innerHTML = '<svg viewBox="0 0 24 24" width="' + px + '" height="' + px + '" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12h4l2.5-6 4 12 2.5-6H22"/></svg>';
    } else {
      span.innerHTML = '<svg viewBox="0 0 24 24" width="' + px + '" height="' + px + '" fill="currentColor"><path d="' + ICONS[name] + '"/></svg>';
    }
    return span;
  }

  /* ---- Themes (AppTheme.swift, ThemeColors) -------------------------------- */
  function grad(a, b) { return "linear-gradient(135deg, rgb(" + a + "), rgb(" + b + "))"; }
  var THEMES = {
    "default": { name: "Classic", surface: "31,33,41", meRow: "33,71,46", oppRow: "36,46,71", me: "51,194,130", opp: "66,138,237", server: "245,212,61", meCourt: "41,112,71", oppCourt: "51,82,143", neuCourt: "43,97,59", meCourtS: "66,163,107", oppCourtS: "87,138,209", neuCourtS: "77,158,92", primary: ["64,204,181", "20,133,235"], serverMe: ["92,199,94", "51,153,61"], serverOpp: ["56,102,209", "36,66,153"] },
    clayCourt: { name: "Clay Court", surface: "31,20,15", meRow: "56,31,15", oppRow: "51,43,23", me: "245,138,56", opp: "230,209,148", server: "250,224,107", meCourt: "107,56,20", oppCourt: "92,77,31", neuCourt: "77,46,20", meCourtS: "184,97,41", oppCourtS: "184,163,92", neuCourtS: "148,82,36", primary: ["245,138,56", "199,92,26"], serverMe: ["245,138,56", "199,92,26"], serverOpp: ["184,163,97", "138,122,61"] },
    grassCourt: { name: "Grass Court", surface: "15,20,18", meRow: "46,20,61", oppRow: "20,51,31", me: "140,56,199", opp: "51,189,102", server: "247,245,214", meCourt: "71,31,102", oppCourt: "26,77,46", neuCourt: "26,46,31", meCourtS: "158,77,219", oppCourtS: "77,209,128", neuCourtS: "56,122,77", primary: ["140,56,199", "102,36,153"], serverMe: ["140,56,199", "102,36,153"], serverOpp: ["51,189,102", "31,143,71"] },
    hardCourtDay: { name: "Hard Court", surface: "15,20,36", meRow: "15,41,77", oppRow: "61,51,15", me: "36,148,240", opp: "250,194,31", server: "250,209,36", meCourt: "20,66,128", oppCourt: "97,77,15", neuCourt: "20,51,97", meCourtS: "56,148,235", oppCourtS: "250,194,36", neuCourtS: "46,112,194", primary: ["36,148,240", "20,97,189"], serverMe: ["36,148,240", "20,97,189"], serverOpp: ["214,168,26", "168,128,15"] },
    hardCourtNight: { name: "Hard Court (Night)", surface: "10,15,31", meRow: "20,31,77", oppRow: "46,56,10", me: "51,87,235", opp: "199,240,36", server: "250,245,235", meCourt: "31,46,117", oppCourt: "61,77,15", neuCourt: "20,36,87", meCourtS: "77,117,245", oppCourtS: "199,240,46", neuCourtS: "51,77,168", primary: ["51,87,235", "36,61,184"], serverMe: ["51,87,235", "36,61,184"], serverOpp: ["184,224,36", "143,179,20"] }
  };
  var THEME_ORDER = ["default", "clayCourt", "grassCourt", "hardCourtDay", "hardCourtNight"];
  var GUIDE_GRAD = grad("69,82,105", "36,46,64");       // ButtonGradients.guide
  var END_GRAD = grad("230,69,84", "191,43,56");        // ButtonGradients.end
  var SUPPORT_GRAD = grad("143,92,235", "107,71,179");  // ButtonGradients.support

  function applyTheme() {
    var t = THEMES[S.settings.theme] || THEMES["default"], st = screenEl.style;
    st.setProperty("--t-surface", t.surface); st.setProperty("--t-me-row", t.meRow); st.setProperty("--t-opp-row", t.oppRow);
    st.setProperty("--t-me", t.me); st.setProperty("--t-opp", t.opp); st.setProperty("--t-server", t.server);
    st.setProperty("--t-me-court", t.meCourt); st.setProperty("--t-opp-court", t.oppCourt); st.setProperty("--t-neu-court", t.neuCourt);
    st.setProperty("--t-me-court-s", t.meCourtS); st.setProperty("--t-opp-court-s", t.oppCourtS); st.setProperty("--t-neu-court-s", t.neuCourtS);
    st.setProperty("--t-btn-primary", grad(t.primary[0], t.primary[1]));
    st.setProperty("--t-btn-me", grad(t.serverMe[0], t.serverMe[1]));
    st.setProperty("--t-btn-opp", grad(t.serverOpp[0], t.serverOpp[1]));
  }

  /* ---- Copy (SettingsCopy.swift, MatchTrackingStatus.swift) ---------------- */
  var COPY = {
    trackPointOutcome: "After each point, tag the winner and shot to build detailed stats.",
    workoutSession: "Runs an Apple Watch workout to log heart rate and calories.",
    changeoverCompass: "Uses the watch compass to confirm your court end at changeovers.",
    appearanceTheme: "Sets the scoreboard color theme on both your iPhone and watch.",
    announceScores: "Speaks the score aloud through your iPhone speaker.",
    iPhoneInput: "Lets you swipe to score on the iPhone scoreboard.",
    birthYear: "Estimates your maximum heart rate from your age.",
    overrideMaxHR: "Sets your maximum heart rate manually instead of by age.",
    defaultMaxHRNote: "190 bpm default — set your birth year for accuracy"
  };

  var FORMATS = [
    { id: "standard", title: "Best of 3 Sets (Club / League)", details: "3 sets · Final set: Super Tiebreak to 10", short: "Best of 3 (Club/League)", label: "Best of 3", tone: "primary" },
    { id: "bestOf3FullFinalSet", title: "Best of 3 Sets (ATP)", details: "3 sets · Final set: Full set, tiebreak to 7", short: "Best of 3 (ATP)", label: "Best of 3 (Full Final Set)", tone: "primary" },
    { id: "quick4Games", title: "Quick 4 Games", details: "First to 3 games · Sudden death point at 2-2", short: "Quick 4 Games", label: "Quick 4 Games", tone: "support" },
    { id: "superTiebreak", title: "Super Tiebreak", details: "1 set · Single tiebreak to 10 pts", short: "Super Tiebreak", label: "Super Tiebreak", tone: "support" },
    { id: "perpetualSuperTiebreak", title: "Perpetual Tiebreak", details: "Continuous tiebreak until stopping", short: "Perpetual Tiebreak", label: "Perpetual Tiebreak", tone: "support" },
    { id: "perpetualPoints", title: "Perpetual Points", details: "Just count points · server alternates every point · no stats or changeovers", short: "Perpetual Points", label: "Perpetual Points", tone: "support" }
  ];
  function formatInfo(id) { for (var i = 0; i < FORMATS.length; i++) if (FORMATS[i].id === id) return FORMATS[i]; return FORMATS[0]; }

  /* ---- Watch state --------------------------------------------------------- */
  var S = window.DeuceMateShell = {
    settings: {
      track: false,            // statsTrackingEnabled defaults to OFF on the real watch
      compass: false, announce: false, name: "", iPhoneInput: false,
      theme: "default", birthYear: 0, override: false, overrideBpm: 180
    },
    setup: { type: "singles", format: "standard" },   // MatchSetupDefaults (remembered)
    history: [],            // newest first, capped like StatsStore.historyCap
    stack: [],              // presented sheets, top last
    alert: null,
    matchPhase: "warmup",   // warmup | server | court | play
    headingLocked: false,
    liveId: null,
    announceResult: null,
    health: "authorized",      // HealthAccess: notDetermined | denied | authorized — the demo starts authorised (owner call: skip the simulated permission prompt)
    healthPick: { write: true, read: true },
    guideOpen: { tennis: false, padel: false },
    screens: {},            // other files register their sheets here
    HISTORY_CAP: 25
  };
  api.configure({ health: true }); // keep the live match's HR/kcal/steps in step with the authorised state
  S.h = h; S.append = append; S.md = md; S.icon = icon; S.api = api; S.root = root; S.FORMATS = FORMATS;
  S.formatInfo = formatInfo; S.THEMES = THEMES; S.GUIDE_GRAD = GUIDE_GRAD; S.END_GRAD = END_GRAD; S.SUPPORT_GRAD = SUPPORT_GRAD;
  S.grad = grad;

  function uid() { return "r" + Date.now().toString(36) + Math.floor(Math.random() * 1e6).toString(36); }
  S.uid = uid;

  /* ---- Derived values ------------------------------------------------------ */
  function cfgOf(format) { return Scoring.cfgFor(format); }
  function matchInProgress() { return api.active(); }     // currentServer != nil || any score
  function resolvedMaxHR() {
    var nowY = new Date().getFullYear(), s = S.settings;
    if (s.override && s.overrideBpm >= 120 && s.overrideBpm <= 220) return s.overrideBpm;
    if (s.birthYear > 1900 && s.birthYear <= nowY) {
      var age = nowY - s.birthYear;
      if (age >= 5 && age <= 100) return 220 - age;
    }
    return 190;
  }
  function usableBirthYear() {
    var nowY = new Date().getFullYear(), by = S.settings.birthYear;
    return by > 1900 && by <= nowY && nowY - by >= 5 && nowY - by <= 100;
  }
  /* MatchTrackingStatus.all(...) — Health is always "authorized" here (the
     demo's invented workout), so the Pulse chip is never collapsed. */
  function trackingStatuses() {
    var cfg = cfgOf(S.setup.format), s = S.settings, out = [];
    if (cfg.disablesPointTracking) out.push({ facet: "points", title: "Point tracking", short: "Points", icon: "tap", readiness: "off", label: "—", detail: "Perpetual Points doesn't record point outcomes." });
    else out.push({ facet: "points", title: "Point tracking", short: "Points", icon: "tap", readiness: s.track ? "on" : "off", label: s.track ? "On" : "Off",
      detail: s.track ? COPY.trackPointOutcome : "No shot or outcome stats will be recorded for this match." });
    var HFIX = "Allow DeuceMate under Privacy → Health in the Watch app on iPhone.";
    if (S.health === "authorized") out.push({ facet: "health", title: "Health tracking", short: "Health", icon: "heart", readiness: "on", label: "On", detail: COPY.workoutSession });
    else if (S.health === "notDetermined") out.push({ facet: "health", title: "Health tracking", short: "Health", icon: "heart", readiness: "partial", label: "Ask", detail: "DeuceMate will ask for Health access when the match starts." });
    else out.push({ facet: "health", title: "Health tracking", short: "Health", icon: "heart", readiness: "off", label: "Off", detail: "No heart rate, steps, or calories. " + HFIX });
    var calibrated = (s.override && s.overrideBpm >= 120 && s.overrideBpm <= 220) || usableBirthYear();
    if (S.health === "denied") out.push({ facet: "pulse", title: "Pulse Coach", short: "Pulse", icon: "pulse", readiness: "off", label: "Off", detail: "Needs heart rate. " + HFIX });
    else out.push(calibrated
      ? { facet: "pulse", title: "Pulse Coach", short: "Pulse", icon: "pulse", readiness: "on", label: "On", detail: "Heart-rate zones use your " + resolvedMaxHR() + " bpm max HR." }
      : { facet: "pulse", title: "Pulse Coach", short: "Pulse", icon: "pulse", readiness: "partial", label: "Est.", detail: COPY.defaultMaxHRNote + ". **Past matches recompute if you set it later.**" });
    // collapsingPulseWhenHealthOff — the pre-match strip drops the redundant Pulse chip
    S.statusesAll = out;
    return out;
  }
  function stripStatuses() {
    var all = trackingStatuses();
    return S.health === "denied" ? all.filter(function (t) { return t.facet !== "pulse"; }) : all;
  }

  /* ---- Sheet stack ---------------------------------------------------------- */
  function push(entry) {
    var cur = S.top(), sc = shellEl.querySelector(".sheet-layer .app-scroll");
    if (cur && sc) cur.savedScroll = sc.scrollTop;
    entry.enter = true; S.stack.push(entry); render();
  }
  function pop() {
    var top = S.stack[S.stack.length - 1];
    if (!top) return;
    if (top.onClose) top.onClose();
    S.stack.pop();
    render();
  }
  function popTo(id) {
    while (S.stack.length && S.stack[S.stack.length - 1].id !== id) S.stack.pop();
    render();
  }
  function popAll() { S.stack.length = 0; render(); }
  S.push = push; S.pop = pop; S.popAll = popAll; S.popTo = popTo; S.render = function () { render(); };
  S.top = function () { return S.stack[S.stack.length - 1] || null; };

  function showAlert(a) { S.alert = a; render(); }
  function dismissAlert() { S.alert = null; render(); }
  S.showAlert = showAlert; S.dismissAlert = dismissAlert;

  /* ---- Shared widgets -------------------------------------------------------- */
  function homeButton(label, opts) {
    opts = opts || {};
    var b = h("button", { type: "button", class: "hb" + (opts.cls ? " " + opts.cls : ""), onclick: opts.onclick, disabled: opts.disabled || false,
      "aria-label": opts.aria || null, "aria-pressed": opts.pressed == null ? null : String(opts.pressed) },
      opts.icon ? icon(opts.icon, opts.iconSize || 16) : null, label ? h("span", { text: label }) : null);
    if (opts.bg) b.style.background = opts.bg;
    return b;
  }
  S.homeButton = homeButton;

  function toggleSwitch(on, onChange, disabled, label) {
    var b = h("button", { type: "button", class: "sw" + (on ? " on" : ""), role: "switch", "aria-checked": String(!!on), "aria-label": label || null, disabled: disabled || false,
      onclick: function () { if (!disabled) onChange(!on); } }, h("span", { class: "knob" }));
    return b;
  }
  function toggleRow(title, caption, on, onChange, disabled, titleExtra) {
    return h("div", { class: "trow" + (disabled ? " disabled" : "") },
      h("div", { class: "tcol" }, h("div", { class: "ttl" }, title, titleExtra || null), caption ? h("div", { class: "cap" }, caption) : null),
      toggleSwitch(on, onChange, disabled, title));
  }
  S.toggleRow = toggleRow;

  /* ==========================================================================
     HomeView
     ========================================================================== */
  function home() {
    var inProg = matchInProgress();
    var col = h("div", { class: "home-col" });
    col.appendChild(homeButton(inProg ? "Resume Match" : "Start Match", {
      icon: inProg ? "refresh" : "play", bg: "var(--t-btn-primary)", cls: "headline", onclick: openMatch
    }));

    if (!inProg) {
      // The remembered setup the next match will use — a PRE-match card.
      var f = formatInfo(S.setup.format);
      var summary = (S.setup.type === "doubles" ? "Doubles" : "Singles") + " · " + f.short;
      col.appendChild(h("button", { type: "button", class: "setup-row", "aria-label": "Match setup: " + summary, onclick: function () { push({ id: "setup" }); } },
        h("span", { class: "sr-text", text: summary }), icon("down", 14)));
      // What this match will actually record — taps through to Settings.
      var chips = h("button", { type: "button", class: "strip", "aria-label": stripStatuses().map(function (t) { return t.title + ": " + t.label; }).join(". ") + ". Opens Settings", onclick: function () { push({ id: "settings" }); } });
      stripStatuses().forEach(function (t) {
        chips.appendChild(h("span", { class: "chip " + t.readiness }, icon(t.icon, 12), h("span", { text: t.label })));
      });
      col.appendChild(chips);
    } else {
      col.appendChild(homeButton("End Match", { icon: "stop", bg: END_GRAD, cls: "headline",
        onclick: function () { showAlert({ title: "Finish? 🏁", buttons: [{ label: "Cancel", role: "cancel" }, { label: "End Match", role: "destructive", action: function () { resetMatch(); } }] }); } }));
    }

    var row = h("div", { class: "icon-row" });
    if (S.history.length) row.appendChild(homeButton("", { icon: "history", iconSize: 18, aria: "Past Matches", bg: "var(--t-btn-opp)", onclick: function () { push({ id: "history" }); } }));
    row.appendChild(homeButton("", { icon: "gear", iconSize: 18, aria: "Settings", bg: GUIDE_GRAD, onclick: function () { push({ id: "settings" }); } }));
    row.appendChild(homeButton("", { icon: "book", iconSize: 18, aria: "Guide", bg: GUIDE_GRAD, onclick: function () { push({ id: "guide" }); } }));
    col.appendChild(row);
    return h("div", { class: "app-layer home" }, col);
  }

  /* ==========================================================================
     Match Setup sheet
     ========================================================================== */
  function setupSheet() {
    var scroll = h("div", { class: "app-scroll pad" });
    scroll.appendChild(h("div", { class: "app-title", text: "Match Setup" }));
    var types = h("div", { class: "type-row" });
    [["singles", "Singles"], ["doubles", "Doubles"]].forEach(function (t) {
      var sel = S.setup.type === t[0];
      types.appendChild(homeButton(t[1], { cls: "sub", pressed: sel, bg: sel ? "var(--t-btn-primary)" : GUIDE_GRAD,
        onclick: function () { S.setup.type = t[0]; render(); } }));
    });
    scroll.appendChild(types);
    FORMATS.forEach(function (f) {
      var b = h("button", { type: "button", class: "hb fmt", onclick: function () { S.setup.format = f.id; S.stack.pop(); render(); } },
        h("span", { class: "fmt-title", text: f.title }), h("span", { class: "fmt-det", text: f.details }),
        S.setup.format === f.id ? h("span", { class: "fmt-check" }, icon("check", 13)) : null);
      b.style.background = f.tone === "primary" ? "var(--t-btn-primary)" : SUPPORT_GRAD;
      scroll.appendChild(b);
    });
    return scroll;
  }

  /* ==========================================================================
     Settings sheet (+ Birth Year picker)
     ========================================================================== */
  function settingsSheet() {
    var s = S.settings, inProg = matchInProgress();
    var scroll = h("div", { class: "app-scroll pad settings" });

    scroll.appendChild(h("div", { class: "caption", text: "What This Match Records" }));
    var rows = h("div", { class: "trk-rows" });
    trackingStatuses().forEach(function (t) {
      rows.appendChild(h("div", { class: "trk-row" },
        h("span", { class: "trk-ic " + t.readiness }, icon(t.icon, 13)),
        h("div", { class: "trk-body" },
          h("div", { class: "trk-head" }, h("span", { text: t.title }), h("span", { class: "trk-state " + t.readiness, text: t.label })),
          h("div", { class: "cap" }, md(t.detail)))));
    });
    scroll.appendChild(rows);
    scroll.appendChild(h("hr", { class: "hr" }));

    scroll.appendChild(toggleRow("Track point outcome", COPY.trackPointOutcome, s.track, function (v) { s.track = v; api.configure({ tracking: v }); render(); }, inProg));
    scroll.appendChild(toggleRow("Changeover Compass", COPY.changeoverCompass, s.compass, function (v) { s.compass = v; api.configure({ compass: v }); render(); }, false,
      h("span", { class: "exp", text: " · Experimental" })));
    scroll.appendChild(toggleRow("Announce scores aloud on iPhone", COPY.announceScores, s.announce, function (v) { s.announce = v; S.announceResult = null; render(); }));

    if (s.announce) {
      var input = h("input", { type: "text", class: "name-input", placeholder: "e.g. Federer", value: s.name, autocomplete: "off", spellcheck: "false", maxlength: "40", "aria-label": "Your name" });
      input.addEventListener("input", function () { s.name = input.value; });
      scroll.appendChild(h("div", { class: "namebox" }, h("div", { class: "caption", text: "Your name" }), input));
      scroll.appendChild(h("button", { type: "button", class: "bordered", onclick: function () {
        S.announceResult = null; render();
        setTimeout(function () { S.announceResult = { message: "iPhone reached ✓", success: true }; render(); }, 450);
      } }, "Test iPhone speaker"));
      if (S.announceResult) scroll.appendChild(h("div", { class: "result " + (S.announceResult.success ? "ok" : "bad"), text: S.announceResult.message }));
    }

    scroll.appendChild(toggleRow("iPhone Input", COPY.iPhoneInput, s.iPhoneInput, function (v) { s.iPhoneInput = v; render(); }));

    var appearance = h("div", { class: "appearance" },
      h("div", { class: "caption", text: "Appearance" }), h("div", { class: "cap", text: COPY.appearanceTheme }));
    THEME_ORDER.forEach(function (id) {
      var t = THEMES[id], sel = s.theme === id;
      appearance.appendChild(h("button", { type: "button", class: "theme-row" + (sel ? " sel" : ""), "aria-pressed": String(sel), onclick: function () { s.theme = id; applyTheme(); render(); } },
        h("span", { class: "swatches" },
          h("i", { style: "background:rgb(" + t.me + ")" }), h("i", { style: "background:rgb(" + t.opp + ")" }), h("i", { style: "background:rgb(" + t.server + ")" })),
        h("span", { class: "tn", text: t.name }), sel ? icon("check", 12, "blue") : null));
    });
    scroll.appendChild(appearance);
    scroll.appendChild(h("hr", { class: "hr" }));

    // Pulse Coach
    scroll.appendChild(h("div", { class: "caption", text: "Pulse Coach" }));
    var ov = s.override;
    scroll.appendChild(h("div", { class: "kv small" + (ov ? " dim" : "") }, h("span", { text: s.birthYear === 0 ? "Max HR (default)" : "Max HR (resolved)" }), h("span", { class: "v", text: resolvedMaxHR() + " bpm" })));
    if (s.birthYear === 0 && !ov) scroll.appendChild(h("div", { class: "cap", text: COPY.defaultMaxHRNote }));
    scroll.appendChild(h("button", { type: "button", class: "kv navlink" + (ov ? " dim" : ""), disabled: ov, onclick: function () { push({ id: "birthyear" }); } },
      h("span", { text: "Birth Year" }), h("span", { class: "v", text: s.birthYear === 0 ? "Skip" : String(s.birthYear) })));
    scroll.appendChild(h("div", { class: "cap" + (ov ? " dim" : ""), text: COPY.birthYear }));
    scroll.appendChild(toggleRow("Override Max HR", COPY.overrideMaxHR, ov, function (v) { s.override = v; s.overrideBpm = 180; render(); }));
    if (ov) {
      var step = function (d) { s.overrideBpm = Math.max(120, Math.min(220, s.overrideBpm + d)); render(); };
      scroll.appendChild(h("div", { class: "stepper" },
        h("div", { class: "kv small" }, h("span", { text: "Override" }), h("span", { class: "v", text: s.overrideBpm + " bpm" })),
        h("div", { class: "step-btns" },
          h("button", { type: "button", "aria-label": "Decrease", disabled: s.overrideBpm <= 120, onclick: function () { step(-1); }, text: "−" }),
          h("button", { type: "button", "aria-label": "Increase", disabled: s.overrideBpm >= 220, onclick: function () { step(1); }, text: "+" }))));
    }
    scroll.appendChild(h("div", { class: "cap", text: "When Override is on, birth year and resolved value are replaced by your manual entry. Heart-rate data syncs with your iPhone. DeuceMate's automatic iCloud Drive archive excludes it, but an iPhone export may include it." }));
    return scroll;
  }

  function birthYearSheet() {
    var nowY = new Date().getFullYear(), s = S.settings;
    var scroll = h("div", { class: "app-scroll pad list" });
    function row(label, year) {
      return h("button", { type: "button", class: "list-row", onclick: function () { s.birthYear = year; S.stack.pop(); render(); } },
        h("span", { text: label }), s.birthYear === year ? icon("check", 14, "blue") : null);
    }
    scroll.appendChild(row("Skip", 0));
    for (var y = nowY; y >= 1940; y--) scroll.appendChild(row(String(y), y));
    return scroll;
  }

  /* ==========================================================================
     Guide sheet
     ========================================================================== */
  function guideSheet() {
    var scroll = h("div", { class: "app-scroll pad guide" });
    var available = !matchInProgress();
    scroll.appendChild(h("button", { type: "button", class: "gray-pill left", disabled: !available, onclick: function () {
      if (!available) return;
      S.stack.pop();                       // sheet dismisses first, then the guide presents (onDismiss)
      push({ id: "walkthrough", offer: false });
    } }, "Animated guide"));
    if (!available) scroll.appendChild(h("div", { class: "foot", text: "The animated guide is available after the current match or setup has ended." }));
    scroll.appendChild(h("hr", { class: "hr" }));

    function line(sym, text) { return h("div", { class: "gline" }, h("span", { class: "gsym", text: sym }), h("span", {}, md(text))); }
    scroll.appendChild(h("div", { class: "gblock" },
      h("div", { text: "Swipe to Score:" }),
      line("☝️", "Swipe **up** to gain a point."),
      line("👇", "Swipe **down** to give opponent a point."),
      line("👈", "Swipe **left** to undo."),
      line("👉", "Swipe **right** for score stats — requires **Track point outcome** enabled before the match."),
      line("👆", "**Double-tap** the score to mark a 2nd serve (yellow **2** badge on the server).")));
    scroll.appendChild(h("hr", { class: "hr" }));
    scroll.appendChild(h("div", { class: "gblock tight" },
      h("div", { text: "Match Indicators:" }),
      h("div", {}, "🎾 Current server & which side to play."),
      h("div", {}, md("🟡 **2** — server is on a 2nd serve.")),
      h("div", {}, "🧭 Compass arrow points to your starting end at changeovers (when Changeover Compass is on)."),
      h("div", {}, "🔁 🎾 Balls swap ends"),
      h("div", {}, "🔁 👥 Players swap ends"),
      h("div", {}, "🔁 🎾 👥 Balls and players swap ends")));
    scroll.appendChild(h("hr", { class: "hr" }));

    function disclosure(key, titleBold, titleRest, paras) {
      var open = S.guideOpen[key];
      var wrap = h("div", { class: "gblock tight" },
        h("button", { type: "button", class: "disc", "aria-expanded": String(open), onclick: function () { S.guideOpen[key] = !open; render(); } },
          h("span", {}, h("strong", { text: titleBold }), " " + titleRest), icon(open ? "up" : "down", 14)));
      if (open) wrap.appendChild(h("div", { class: "gblock paras" }, paras.map(function (p) { return h("div", {}, md(p)); })));
      return wrap;
    }
    scroll.appendChild(disclosure("tennis", "Tricky", "Tennis Rules", [
      "**Sets**: Switch after 1 game in a set, then every odd game. If a set ends on odd total (6-3, 7-6), switch before next set.",
      "**Tiebreaks**: Player who would serve next starts with one point, alternate every two points, switch ends every six points. Receiver at start of tiebreak serves next set.",
      "**Serves**: Foot faults occur when stepping on the imaginary center line extension. Receiver can stand inside service box but must let ball bounce. "]));
    scroll.appendChild(h("hr", { class: "hr" }));
    scroll.appendChild(disclosure("padel", "Tricky", "Padel Rules", [
      "**Serve**: Must be underhand, below waist, and after one bounce. Serve can hit the back glass after the bounce, but may not hit the side glass first.",
      "**Return**: Receiver can let the ball bounce, hit the back wall, then play it back. Volleying before the bounce is allowed (except return of serve).",
      "**Double wall**: A ball that hits the back wall then side wall (or side then back) is still in play after the bounce; play it if it doesn’t hit the fence first."]));
    scroll.appendChild(h("hr", { class: "hr" }));
    var mail = homeButton("Email me here", { cls: "headline", bg: SUPPORT_GRAD, onclick: function () { window.location.href = "mailto:mail@ehsanrahman.com?subject=DeuceMate%20Feedback"; } });
    scroll.appendChild(h("div", { class: "gblock" }, h("div", { text: "Questions or issues?" }), mail));
    return scroll;
  }

  /* ==========================================================================
     Health permission (the system sheet DeuceMate triggers at launch via
     HKHealthStore.requestAuthorization): intro → write access → read access.
     ========================================================================== */
  function setHealth(v) { S.health = v; api.configure({ health: v === "authorized" }); }
  function healthSheet(entry) {
    var step = entry.step || 0, box = h("div", { class: "app-scroll pad health" });
    function pageBtn(label, fn) { return h("button", { type: "button", class: "gray-pill", onclick: fn, text: label }); }
    function toggleBlock(key, title, body, items, expl) {
      var on = S.healthPick[key];
      return [h("div", { class: "hl-title", text: title }), h("div", { class: "hl-body", text: body }),
        h("div", { class: "hl-toggle" }, h("span", { text: "All Requested Data Below" }), toggleSwitch(on, function (v) { S.healthPick[key] = v; render(); }, false, "All Requested Data Below")),
        h("div", { class: "hl-cat", text: "Activity" }), items.map(function (i) { return h("div", { class: "hl-item" }, h("span", { text: i }), toggleSwitch(on, function (v) { S.healthPick[key] = v; render(); }, false, i)); }),
        h("div", { class: "hl-expl", text: "APP EXPLANATION: " + expl })];
    }
    if (step === 0) {
      box.appendChild(h("div", { class: "hl-intro" },
        h("div", { class: "hl-icon", html: '<svg viewBox="0 0 24 24" width="22" height="22" fill="#ff2d55"><path d="' + ICONS.heart + '"/></svg>' }),
        h("div", { class: "hl-title", text: "Health Access" }),
        h("div", { class: "hl-body", text: "“DeuceMate” would like to access and update your Health data." }),
        pageBtn("Review", function () { entry.step = 1; S.stack[S.stack.length - 1] = entry; render(); })));
    } else if (step === 1) {
      toggleBlock("write", "Allow Write Access", "“DeuceMate” would like permission to write the following data to Health.", ["Active Energy", "Workouts", "Walking + Running Distance"],
        "DeuceMate records your tennis match as a workout.").forEach(function (n) { append(box, n); });
      box.appendChild(pageBtn("Next", function () { entry.step = 2; render(); }));
    } else {
      toggleBlock("read", "Allow Read Access", "“DeuceMate” would like permission to read the following data from Health.", ["Heart Rate", "Step Count", "Active Energy"],
        "DeuceMate shows your heart rate, steps and calories alongside each match.").forEach(function (n) { append(box, n); });
      box.appendChild(pageBtn("Allow", function () {
        setHealth(S.healthPick.write || S.healthPick.read ? "authorized" : "denied");
        S.stack = S.stack.filter(function (e) { return e.id !== "health"; });
        if (entry.thenStart) { render(); openMatch(); } else render();
      }));
    }
    return box;
  }
  S.screens.health = healthSheet;
  function requestHealth(thenStart) { S.healthPick = { write: true, read: true }; push({ id: "health", step: 0, thenStart: !!thenStart, nav: true }); }

  /* ==========================================================================
     RootModal — warm-up → who serves → court side → the match
     ========================================================================== */
  function openMatch() {
    if (S.health === "notDetermined" && !api.active()) { requestHealth(true); return; }
    var cfg = cfgOf(S.setup.format);
    if (api.active()) {
      S.matchPhase = (S.settings.compass && !cfg.fixedDeuceSide && !S.headingLocked) ? "court" : "play";
    } else {
      S.headingLocked = false;
      S.matchPhase = !cfg.playRegularSets ? "server" : "warmup";   // tiebreak-only formats skip the warm-up screen
    }
    push({ id: "match" });
  }

  function pickServer(who) {
    var cfg = { matchType: S.setup.type, format: S.setup.format, tracking: S.settings.track, compass: S.settings.compass };
    if (S.setup.type === "doubles") cfg.doublesServer = who; else cfg.server = who;
    api.start(cfg);
    S.liveId = uid();
    var fc = cfgOf(S.setup.format);
    S.matchPhase = (S.settings.compass && !fc.fixedDeuceSide) ? "court" : "play";
    S.headingReadyAt = Date.now() + 1800;
    render();
  }

  var headingTimer = null;
  function matchSheet() {
    var phase = S.matchPhase, box = h("div", { class: "app-center" });
    if (phase === "warmup") {
      box.appendChild(h("div", { class: "warm-ic", "aria-hidden": "true", html: '<svg viewBox="0 0 64 64" width="52" height="52" fill="none" stroke="#30d158" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round"><circle cx="38" cy="10" r="5.5" fill="#30d158" stroke="none"/><path d="M36 19 31 35M32 25 19 21M33 26 46 31M31 35 22 50M31 35 41 46 39 59M19 21 11 12"/><ellipse cx="8" cy="8" rx="5" ry="6" transform="rotate(-40 8 8)"/></svg>' }));
      box.appendChild(h("div", { class: "headline-t", text: "Warming Up" }));
      box.appendChild(homeButton("Warm Up Complete", { cls: "headline", bg: "var(--t-btn-primary)", onclick: function () { S.matchPhase = "server"; render(); } }));
    } else if (phase === "server") {
      if (S.setup.type === "doubles") {
        box.appendChild(h("div", { class: "headline-t", text: "Who serves first?" }));
        box.appendChild(h("div", { class: "two" },
          homeButton("Me", { cls: "sub", bg: "var(--t-btn-me)", onclick: function () { pickServer("me"); } }),
          homeButton("Partner", { cls: "sub", bg: "var(--t-btn-me)", onclick: function () { pickServer("partner"); } })));
        box.appendChild(homeButton("Opponent", { cls: "sub", bg: "var(--t-btn-opp)", onclick: function () { pickServer("opponentS1"); } }));
      } else {
        box.appendChild(h("div", { class: "headline-t", text: "Who is serving first?" }));
        box.appendChild(h("div", { class: "two" },
          homeButton("Me", { cls: "headline", bg: "var(--t-btn-me)", onclick: function () { pickServer("me"); } }),
          homeButton("Opponent", { cls: "headline", bg: "var(--t-btn-opp)", onclick: function () { pickServer("opponent"); } })));
      }
    } else if (phase === "court") {
      var ready = Date.now() >= (S.headingReadyAt || 0);
      box.appendChild(h("div", { class: "headline-t", text: "Correct court side?" }));
      box.appendChild(h("div", { class: "cap center", text: "Stand on your starting end." }));
      box.appendChild(h("div", { class: "cap center", text: ready ? "Accuracy: ±" + (8 + (S.headingReadyAt % 7)) + "°" : "Hold watch up… acquiring heading" }));
      box.appendChild(homeButton("✓ Confirmed", { cls: "headline", bg: "var(--t-btn-primary)", disabled: !ready, onclick: function () {
        S.headingLocked = true; S.matchPhase = "play"; render();
      } }));
      if (!ready) {
        clearTimeout(headingTimer);
        headingTimer = setTimeout(function () { if (S.matchPhase === "court") render(); }, Math.max(50, S.headingReadyAt - Date.now()));
      }
    }
    return h("div", { class: "app-scroll noscroll" }, box);
  }

  /* ---- Ending a match ------------------------------------------------------- */
  function saveLive(endAtCurrentScore) {
    var rec = api.snapshot(endAtCurrentScore);
    if (!rec) return;
    rec.id = S.liveId || rec.id;
    S.upsertRecord(rec);
  }
  S.upsertRecord = function (rec) {
    var i = -1;
    S.history.forEach(function (r, idx) { if (r.id === rec.id) i = idx; });
    if (i >= 0) S.history[i] = rec; else S.history.unshift(rec);
    if (S.history.length > S.HISTORY_CAP) S.history.length = S.HISTORY_CAP;
  };
  function resetMatch() {
    if (api.active()) {
      if (api.hasProgress()) saveLive(false);   // finalizeCurrentMatchToStore: only with real progress
      api.clear();
    }
    S.liveId = null; S.headingLocked = false;
    S.stack = S.stack.filter(function (e) { return e.id !== "match"; });
    S.alert = null;
    render();
  }
  S.resetMatch = resetMatch;
  S.saveLive = saveLive;
  S.liveRecordId = function () { return S.liveId; };

  api.hooks.endMatch = function () { resetMatch(); };
  api.hooks.change = function () { syncChrome(); };

  /* ==========================================================================
     Chrome + render loop
     ========================================================================== */
  var runIcon = h("span", { class: "app-run", "aria-label": "Workout in progress", role: "img" });
  runIcon.innerHTML = '<svg viewBox="0 0 24 24" width="13" height="13" fill="currentColor"><path d="M13.5 5.5a2 2 0 1 0 0-4 2 2 0 0 0 0 4zM9.8 8.9 7 23h2.1l1.8-8 2.1 2v6h2v-7.5l-2.1-2 .6-3A7.3 7.3 0 0 0 19 15v-2c-1.6 0-2.9-.9-3.6-2l-1-1.6c-.4-.6-1-1-1.7-1-.3 0-.5.1-.8.1L6 8.3V13h2V9.6l1.8-.7z"/></svg>';
  var clockEl = h("span", { class: "app-clock" });
  var navTitleEl = h("span", { class: "app-nav-title" });
  var closeBtn = h("button", { type: "button", class: "app-close", "aria-label": "Close", onclick: function () { if (api.modalKind() === "other") return; if (api.modalKind() === "stats") api.closeStats(); else if (S.top() && S.top().id === "walkthrough" && S.closeWalkthrough) S.closeWalkthrough(); else pop(); } }, icon("close", 13));
  var backBtn = h("button", { type: "button", class: "app-back", "aria-label": "Back", onclick: function () { var t = S.top(); if (t && t.id === "health" && t.step > 0) { t.step--; render(); } else pop(); } }, icon("left", 14), h("span", { class: "back-t", text: "" }));
  function tickClock() {
    var d = new Date(), parts;
    try { parts = new Intl.DateTimeFormat(undefined, { hour: "numeric", minute: "2-digit" }).format(d).replace(/\s?[AP]M/i, ""); }
    catch (e) { parts = d.getHours() + ":" + ("0" + d.getMinutes()).slice(-2); }
    clockEl.textContent = parts;
  }
  tickClock(); setInterval(tickClock, 15000);

  function syncChrome() {
    var top = S.top();
    var playing = !!top && top.id === "match" && S.matchPhase === "play";
    var kind = playing ? api.modalKind() : null;      // "stats" | "other" | null
    var wt = top && top.id === "walkthrough";
    clockEl.hidden = false;
    runIcon.hidden = !api.active();
    var isNav = top && (top.id === "birthyear" || (top.id === "health" && top.step > 0));
    var navTitle = top && top.id === "health" ? (top.step === 1 ? "Write Access" : "Read Access") : "Birth Year";
    navTitleEl.textContent = isNav ? navTitle : "";
    closeBtn.hidden = (!top && !kind) || isNav;
    closeBtn.classList.toggle("inert", kind === "other");
    closeBtn.setAttribute("data-closes-stats", kind === "stats" ? "1" : "");
    backBtn.hidden = !isNav;
  }

  var lastTopId = null;
  function render() {
    var top = S.top();
    var oldScroll = shellEl.querySelector(".sheet-layer .app-scroll");
    var keep = oldScroll && lastTopId === (top && top.id) ? oldScroll.scrollTop : ((top && top.savedScroll) || 0);

    shellEl.innerHTML = "";
    var playing = !!top && top.id === "match" && S.matchPhase === "play";
    if (!playing) shellEl.appendChild(home());

    if (top && !playing) {
      var content = null;
      if (top.id === "match") content = matchSheet();
      else if (top.id === "setup") content = setupSheet();
      else if (top.id === "settings") content = settingsSheet();
      else if (top.id === "birthyear") content = birthYearSheet();
      else if (top.id === "health") content = healthSheet(top);
      else if (top.id === "guide") content = guideSheet();
      else if (S.screens[top.id]) content = S.screens[top.id](top);
      var layer = h("div", { class: "app-layer sheet-layer" + (top.enter ? " enter" : "") + (top.id === "walkthrough" ? " wt" : "") + (top.id === "match" || top.id === "setup" ? " solid" : "") }, content);
      top.enter = false;
      shellEl.appendChild(layer);
      var sc = layer.querySelector(".app-scroll");
      if (sc && keep) sc.scrollTop = keep;
    }
    shellEl.appendChild(h("div", { class: "app-chrome" }, backBtn, closeBtn, runIcon, clockEl, navTitleEl));

    if (S.alert) shellEl.appendChild(alertEl(S.alert));

    lastTopId = top && top.id;
    var open = !playing;
    if (open) root.setAttribute("data-shell-open", ""); else root.removeAttribute("data-shell-open");
    screenEl.classList.toggle("playing", playing);
    shellEl.classList.toggle("is-playing", playing);
    syncChrome();
    api.refresh();
    if (!S.stack.length && !S.alert && S.afterRender) setTimeout(S.afterRender, 0);
  }
  function isNavTitle(top) { return !!top && top.id === "birthyear"; }

  function alertEl(a) {
    var card = h("div", { class: "alert-card", role: "alertdialog", "aria-modal": "true", "aria-label": a.title },
      h("div", { class: "alert-title", text: a.title }),
      a.message ? h("div", { class: "alert-msg", text: a.message }) : null);
    var order = (a.buttons || []).slice().sort(function (x, y) { var r = { destructive: 0, "": 1, cancel: 2 }; return (r[x.role || ""]) - (r[y.role || ""]); });
    order.forEach(function (b) {
      card.appendChild(h("button", { type: "button", class: "alert-btn " + (b.role || ""), onclick: function () {
        S.alert = null; if (b.action) b.action(); else render();
      } }, b.label));
    });
    return h("div", { class: "alert-scrim" }, card);
  }

  /* Escape closes the top sheet (the watch's X) unless a match modal owns it. */
  document.addEventListener("keydown", function (e) {
    if (e.key !== "Escape" || (!root.contains(document.activeElement) && document.activeElement !== document.body)) return;
    if (S.alert) { dismissAlert(); e.preventDefault(); return; }
    var top = S.top();
    if (top && !(top.id === "match" && S.matchPhase === "play" && api.modalOpen()) && top.id !== "walkthrough") { pop(); e.preventDefault(); }
  });

  /* Keep the shell from ever scoring through the engine's swipe handlers. */
  ["pointerdown", "pointerup", "click"].forEach(function (ev) {
    shellEl.addEventListener(ev, function (e) { e.stopPropagation(); });
  });

  /* 1 watch point = screen width / 184 (the 44 mm reference), so the replica scales with the frame. */
  function setPt() {
    var w = screenEl.getBoundingClientRect().width;
    if (w > 0) screenEl.style.setProperty("--pt", (w / 184) + "px");
  }
  window.addEventListener("resize", setPt);
  if (window.ResizeObserver) new ResizeObserver(setPt).observe(screenEl);

  S.boot = function () {
    setPt();
    applyTheme();
    if (S.seedHistory) S.seedHistory();
    render();
    // The demo starts with Health authorised, so the launch-time workoutManager.requestAuthorization sheet is skipped.
  };
})();
