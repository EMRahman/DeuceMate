/* iPhone companion for the browser watch. The watch remains the scorer;
   this archive keeps its own copies, as PhoneStatsStore does on iOS. */
(function () {
  "use strict";
  var host = document.getElementById("iphone-demo"), S = window.DeuceMateShell;
  if (!host || !S) return;
  var api = S.api, E = window.DeuceMateScoring, T = window.DeuceMateTracking;
  var archive = [], tombstones = new Set(), watchOnlyIDs = new Set(), screen = "matches", selected = null;
  var storageKey = "deucemate-browser-companion-v1", persistenceError = false, storageReadFailed = false, resetting = false;
  var connection = { paired: true, reachable: true, activation: "ready", syncing: false, syncFailure: false, archiveReadFailure: false, lastSync: null };
  var cloudBackup = null, cloudState = "unavailable";
  var lastSignature = "", announceSignature = "", syncing = false, renderQueued = false;
  var displayedLiveId = null, lastPhoneSwipe = -Infinity;
  var settings = S.settings;
  settings.health = S.health;
  settings.playerNTRP = "3.0–3.5";
  var frame = h("div", { class: "phone-frame" });
  var status = h("div", { class: "phone-status", "aria-hidden": "true" }, "9:41", h("span", { class: "phone-island" }), h("span", { class: "phone-status-icons" }, icon("signal"), icon("wifi"), icon("battery")));
  var nav = h("nav", { class: "phone-nav", "aria-label": "iPhone navigation" });
  var body = h("div", { class: "phone-body", tabindex: "0" });
  var notice = h("div", { class: "phone-notice", role: "status", hidden: true });
  var dimmer = h("div", { class: "phone-modal-dimmer", "aria-hidden": "true", hidden: true });
  var dialog = h("dialog", { class: "phone-dialog", "aria-label": "iPhone sheet" });
  frame.append(status, nav, body, notice, dimmer, h("div", { class: "phone-home-indicator", "aria-hidden": "true" }));
  var rotateDevice = button("Rotate iPhone", function () { setOrientation(!frame.classList.contains("phone-landscape")); }, "phone-device-rotate");
  rotateDevice.setAttribute("aria-pressed", "false");
  rotateDevice.setAttribute("aria-label", "Rotate iPhone to landscape");
  var orientationLabel = h("span", { class: "phone-orientation-label" }, "Portrait");
  // Landscape lifts the frame over the page. These give an unmissable way back that does not depend on
  // the floating page-level button: a click-away backdrop and an exit control inside the frame itself.
  var landscapeBackdrop = h("div", { class: "phone-landscape-backdrop", "aria-hidden": "true", hidden: true });
  landscapeBackdrop.addEventListener("click", function () { setOrientation(false); });
  var exitLandscape = button("Exit landscape", function () { setOrientation(false); rotateDevice.focus({ preventScroll: true }); }, "phone-exit-landscape");
  exitLandscape.hidden = true; exitLandscape.setAttribute("aria-label", "Rotate iPhone back to portrait");
  frame.append(exitLandscape);
  host.append(h("div", { class: "phone-device-controls" }, orientationLabel, rotateDevice), landscapeBackdrop, frame, dialog);
  frame.dataset.orientation = "portrait";
  var noticeTimer, oldFocus;
  // The native app is portrait-locked everywhere except the live scoreboard (AppDelegate.orientationLock),
  // so the replica only rotates there and returns to portrait when you leave it.
  function setOrientation(landscape) {
    if (landscape && screen !== "live") return;
    frame.classList.toggle("phone-landscape", landscape); frame.dataset.orientation = landscape ? "landscape" : "portrait";
    host.classList.toggle("phone-is-landscape", landscape);
    landscapeBackdrop.hidden = !landscape; exitLandscape.hidden = !landscape;
    document.documentElement.classList.toggle("phone-landscape-lock", landscape);
    rotateDevice.setAttribute("aria-pressed", String(landscape)); rotateDevice.setAttribute("aria-label", "Rotate iPhone to " + (landscape ? "portrait" : "landscape"));
    orientationLabel.textContent = landscape ? "Landscape" : "Portrait";
    var inApp = frame.querySelector(".phone-rotate"); if (inApp) inApp.setAttribute("aria-label", "Rotate iPhone to " + (landscape ? "portrait" : "landscape"));
    if (presentation) revealSheet();
  }
  // On a real phone the device itself rotates: turning it sideways on the live scoreboard enters landscape,
  // turning it back returns to portrait (the native scoreboard is landscape-locked).
  var turned = window.matchMedia("(pointer: coarse) and (orientation: landscape) and (max-height: 520px)"), renderedScreen = null;
  function onDeviceTurn() {
    if (!turned.matches) { if (frame.classList.contains("phone-landscape")) setOrientation(false); }
    else if (screen === "live") setOrientation(true);
  }
  if (turned.addEventListener) turned.addEventListener("change", onDeviceTurn);
  document.addEventListener("keydown", function (event) { if (event.key === "Escape" && !dialog.open && frame.classList.contains("phone-landscape")) {event.preventDefault();setOrientation(false);rotateDevice.focus();} });

  function h(tag, attrs) {
    var el = document.createElement(tag);
    Object.keys(attrs || {}).forEach(function (k) {
      var v = attrs[k];
      if (k === "class") el.className = v;
      else if (k === "text") el.textContent = v;
      else if (k.slice(0, 2) === "on" && typeof v === "function") el.addEventListener(k.slice(2), v);
      else if (k === "checked" || k === "disabled" || k === "hidden") el[k] = !!v;
      else if (v != null) el.setAttribute(k, v);
    });
    Array.prototype.slice.call(arguments, 2).flat(Infinity).forEach(function (child) {
      if (child != null) el.append(child.nodeType ? child : document.createTextNode(String(child)));
    });
    return el;
  }
  function button(label, fn, cls) { return h("button", { type: "button", tabindex: "0", class: "phone-button " + (cls || ""), onclick: fn }, label); }
  function segment(label, value, choices, update) {
    var group = h("div", { class: "phone-segment", role: "group", "aria-label": label });
    choices.forEach(function (choice, index) {
      var b = button(choice[1], function () { select(choice[0]); });
      b.dataset.value = choice[0]; b.setAttribute("aria-pressed", String(choice[0] === value));
      b.addEventListener("keydown", function (event) {
        if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
        event.preventDefault(); event.stopPropagation();
        var next = (index + (event.key === "ArrowRight" ? 1 : -1) + choices.length) % choices.length;
        select(choices[next][0]);
        if (group.isConnected) group.children[next].focus();
      });
      group.append(b);
    });
    function select(next) {
      Array.from(group.children).forEach(function (b) { b.setAttribute("aria-pressed", String(b.dataset.value === next)); });
      update(next);
    }
    return group;
  }
  // Small code-native symbols keep the replica independent of fonts and emoji.
  function icon(name) {
    var paths = {
      edit: '<path d="M14 4H5a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h13a2 2 0 0 0 2-2v-9M13 13l-4 1 1-4L19 1l3 3-9 9Z"/>',
      gear: '<path d="m10 2-.6 3-2 .8-2.5-1.6-2 3.4L5 9.5v2.9l-2.1 1.9 2 3.4 2.5-1.6 2 .9.6 3h4l.6-3 2-.9 2.5 1.6 2-3.4-2.1-1.9V9.5l2.1-1.9-2-3.4L16.6 6l-2-.8L14 2h-4Z"/><circle cx="12" cy="11" r="4"/>',
      phone: '<rect x="7" y="2" width="10" height="20" rx="2"/><path d="M10 5h4m-3 14h2"/>',
      watch: '<path d="M9 6V2h6v4m-6 12v4h6v-4"/><rect x="6" y="6" width="12" height="12" rx="3"/>',
      pause: '<circle cx="12" cy="12" r="9"/><path d="M10 8v8m4-8v8"/>',
      lock: '<rect x="5" y="10" width="14" height="12" rx="2"/><path d="M8 10V6a4 4 0 0 1 8 0v4"/>',
      back: '<path d="m15 4-8 8 8 8"/>',
      filter: '<circle cx="12" cy="12" r="10"/><path d="M6 8h12m-10 4h8m-6 4h4"/>',
      tennis: '<circle cx="14" cy="3" r="2"/><path d="m11 8 5 2 3-4m-8 2-4 5-3-3m7-2 2 7 4 5m-4-5-6 2-2 5"/><ellipse cx="3" cy="7" rx="2" ry="3" transform="rotate(-30 3 7)"/>',
      stats: '<path d="M4 20V12h3v8m4 0V4h3v16m4 0V8h3v12"/>',
      chart: '<path d="M4 3v17h17M7 15l5-5 4 3 5-7"/>',
      score: '<path d="M9 6h12M9 12h12M9 18h12M3 5h1v3m-1 3h2l-2 3h2m-2 3h2v3H3"/>',
      sparkles: '<path d="m9 3 2 6 6 2-6 2-2 7-2-7-6-2 6-2 2-6Zm10-2 1 3 3 1-3 1-1 3-1-3-3-1 3-1 1-3Zm0 13 1 3 3 1-3 1-1 3-1-3-3-1 3-1 1-3Z"/>',
      copy: '<rect x="8" y="7" width="12" height="15" rx="2"/><path d="M16 7V3a1 1 0 0 0-1-1H4a1 1 0 0 0-1 1v13a1 1 0 0 0 1 1h4"/>',
      share: '<path d="M8 5l4-4 4 4m-4-4v14M7 9H5a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-9a2 2 0 0 0-2-2h-2"/>',
      safari: '<circle cx="12" cy="12" r="9"/><path d="m16 8-2.5 5.5L8 16l2.5-5.5L16 8Z"/>',
      summary: '<rect x="4" y="2" width="16" height="20" rx="2"/><path d="M8 7h8M8 11h8M8 15h3m-3 3h3m4-3h1m-1 3h1"/>',
      table: '<rect x="2" y="4" width="20" height="16" rx="2"/><path d="M2 9h20M2 15h20M9 4v16m6-16v16"/>',
      chevron: '<path d="m9 5 7 7-7 7"/>',
      expand: '<path d="M9 3H3v6m0-6 7 7m5 11h6v-6m0 6-7-7"/>',
      signal: '<path d="M3 20v-4m6 4v-8m6 8V8m6 12V4" stroke-width="3"/>',
      wifi: '<path d="M2 8a16 16 0 0 1 20 0M5 12a11 11 0 0 1 14 0m-11 4a6 6 0 0 1 8 0m-4 4h0" stroke-width="2.5"/>',
      battery: '<rect x="1" y="5" width="19" height="14" rx="4"/><path d="M23 10v4M5 9h11v6H5Z"/>',
      cloudWarning: '<path d="M7 19H6a4 4 0 0 1-1-7.9A7 7 0 0 1 18.6 9a5 5 0 0 1-.6 10h-1M12 10v5m0 3h0"/>',
      refresh: '<path d="M20 11a8 8 0 0 0-14-4L4 9m0-6v6h6M4 13a8 8 0 0 0 14 4l2-2m0 6v-6h-6"/>',
      antenna: '<circle cx="12" cy="12" r="2"/><path d="M8 8a5.7 5.7 0 0 0 0 8m8-8a5.7 5.7 0 0 1 0 8M5 5a10 10 0 0 0 0 14m14-14a10 10 0 0 1 0 14"/>',
      import: '<path d="M8 11l4 4 4-4m-4 4V1M7 9H5a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-9a2 2 0 0 0-2-2h-2"/>',
      checkCircle: '<circle cx="12" cy="12" r="10"/><path d="m7.5 12.5 3 3 6-6.5"/>',
      xCircle: '<circle cx="12" cy="12" r="10"/><path d="m8.5 8.5 7 7m0-7-7 7"/>',
      minusCircle: '<circle cx="12" cy="12" r="10"/><path d="M7.5 12h9"/>',
      exclaimCircle: '<circle cx="12" cy="12" r="10"/><path d="M12 7v6m0 3h0"/>',
      closeCircle: '<circle cx="12" cy="12" r="10" fill="currentColor" stroke="none"/><path d="m8.5 8.5 7 7m0-7-7 7" stroke="#000" stroke-width="2.2"/>',
      hand: '<path d="M12 2 4 5v6c0 5 3.5 9 8 11 4.5-2 8-6 8-11V5l-8-3Z"/>',
      help: '<circle cx="12" cy="12" r="9"/><path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.7.4-1 .9-1 1.7m0 3h0"/>',
      mail: '<rect x="2" y="5" width="20" height="14" rx="2"/><path d="m2 7 10 7 10-7"/>',
      warning: '<path d="m12 2 11 20H1L12 2Z"/><path d="M12 9v6m0 3h0"/>'
    };
    var svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("viewBox", "0 0 24 24"); svg.setAttribute("fill", "none");
    svg.setAttribute("stroke", "currentColor"); svg.setAttribute("stroke-width", "1.7");
    svg.setAttribute("stroke-linecap", "round"); svg.setAttribute("stroke-linejoin", "round");
    svg.setAttribute("aria-hidden", "true"); svg.classList.add("phone-icon");
    svg.innerHTML = paths[name] || paths.score;
    return svg;
  }
  function card() { return h("section", { class: "phone-card" }, Array.from(arguments)); }
  function note(text) { return h("p", { class: "phone-note" }, text); }
  function heading(text) { return h("h3", { class: "phone-section-title" }, text); }
  function copy(r) { return JSON.parse(JSON.stringify(r)); }
  function sortRecords(a) { return a.sort(function (a, b) { return b.startTime - a.startTime; }); }
  function upsert(r) {
    if (!r || tombstones.has(r.id)) return;
    var i = archive.findIndex(function (a) { return a.id === r.id; });
    if (i < 0) archive.unshift(copy(r)); else archive[i] = copy(r);
    sortRecords(archive);
  }
  function withDemoHealth(record) {
    var r = copy(record);
    // Repeatable fictional measurements, never inferred as real Health data.
    if ((r.steps || 0) > 0 && r.id !== "seed7152") {
      (r.stats || []).forEach(function (p, i) {
        if (p.heartRateBPM == null) p.heartRateBPM = Math.round(140 + Math.sin(i / 8) * 18 + Math.min(17, i / 20));
        if (p.stepsCumulative == null) p.stepsCumulative = Math.round(r.steps * (i + 1) / Math.max(1, r.stats.length));
      });
    }
    return r;
  }
  function liveRecord() {
    if (!api.active() || !S.liveId) return null;
    var r = api.snapshot(false); r.id = S.liveId; return withDemoHealth(r);
  }
  function persist() {
    if (storageReadFailed || resetting) return;
    try {
      localStorage.setItem(storageKey, JSON.stringify({ archive: archive, watch: S.history, settings: settings,
        connection: connection, watchOnlyIDs: Array.from(watchOnlyIDs), tombstones: Array.from(tombstones),
        live: liveRecord(), cloudBackup: cloudBackup, cloudState: cloudState }));
    } catch (_) { persistenceError = true; }
  }
  function sync() {
    if (syncing) return;
    if (!connection.paired || !connection.reachable || connection.activation !== "ready" || connection.syncing || connection.syncFailure) return;
    syncing = true;
    S.history.forEach(function (r) {
      if (watchOnlyIDs.has(r.id)) return;
      upsert(withDemoHealth(r));
    });
    var live = liveRecord(); if (live) upsert(live);
    syncing = false; connection.lastSync = Date.now(); persist();
  }
  function syncNow() {
    if (connection.activation === "connecting" || connection.syncing) {
      notify("Sync pending. The iPhone archive remains available."); return;
    }
    if (connection.activation !== "ready" || !connection.paired || !connection.reachable || connection.syncFailure) {
      notify("Sync unavailable. The iPhone archive is retained."); return;
    }
    watchOnlyIDs.clear(); sync(); render(); notify("Synced with the simulated Watch.");
  }
  function notify(text) {
    clearTimeout(noticeTimer); notice.textContent = text; notice.hidden = false;
    var local = dialog.querySelector(".phone-sheet-notice");
    if (dialog.open) {
      if (!local) { local = h("div", { class: "phone-sheet-notice", role: "status" }); dialog.append(local); }
      local.textContent = text; local.hidden = false;
    }
    noticeTimer = setTimeout(function () { notice.hidden = true; if (local) local.hidden = true; }, 5000);
  }
  // All native presentations share the device's coordinate space, including
  // alerts and menus. The HTML top layer supplies focus trapping, not sizing.
  var presentation = null, sheetObserver = null, sheetCleanup = null;
  var systemAppearance = window.matchMedia("(prefers-color-scheme: dark)");
  function positionSheet() {
    if (!presentation) return;
    var rect = frame.getBoundingClientRect(), border = frame.clientLeft, statusHeight = status.getBoundingClientRect().height;
    var innerTop = rect.top + border, innerLeft = rect.left + border, width = frame.clientWidth, height = frame.clientHeight;
    var viewport = window.visualViewport, viewportTop = viewport ? viewport.offsetTop : 0, viewportBottom = viewportTop + (viewport ? viewport.height : window.innerHeight);
    var safeTop = Math.max(innerTop + statusHeight, viewportTop + 4), safeBottom = Math.min(innerTop + height - 18, viewportBottom - 4);
    var available = Math.max(0, safeBottom - safeTop), kind = presentation.kind;
    var sheetWidth = width, inset = 0, top = safeTop;
    dialog.style.maxHeight = available + "px";
    if (kind === "alert" || kind === "popover") { sheetWidth = Math.min(presentation.width || (kind === "popover" ? 240 : 280), Math.max(0, width - (kind === "popover" && presentation.anchor ? 24 : 40))); inset = (width - sheetWidth) / 2; dialog.style.height = "auto"; }
    else if (kind === "actions") { sheetWidth = Math.max(0, width - 16); inset = 8; dialog.style.height = "auto"; }
    else if (kind === "menu") {
      sheetWidth = Math.min(presentation.width || width - 24, Math.max(0, width - 24)); inset = width - sheetWidth - 12;
      var menuAnchor = presentation.anchor && presentation.anchor();
      top = Math.max(safeTop, menuAnchor ? menuAnchor.top : safeTop + 60);
      top = Math.min(top, safeBottom); dialog.style.height = "auto"; dialog.style.maxHeight = Math.max(0, safeBottom - top) + "px";
    }
    else if (presentation.detent === "medium") { var mediumHeight = Math.min(available, Math.round(height / 2)); top = safeBottom - mediumHeight; dialog.style.height = mediumHeight + "px"; }
    else { var gap = kind === "cover" ? 0 : 12; top += gap; dialog.style.height = Math.max(0, available - gap) + "px"; }
    dialog.style.width = sheetWidth + "px";
    dialog.style.left = (innerLeft + inset) + "px";
    if (kind === "alert" || kind === "popover") top = safeTop + Math.max(0, (available - dialog.getBoundingClientRect().height) / 2);
    if (kind === "popover" && presentation.anchor) {
      var anchor = presentation.anchor(), popupHeight = dialog.getBoundingClientRect().height;
      if (anchor) {
        var anchorY = (anchor.top + anchor.bottom) / 2, above = anchorY - popupHeight - 12, below = anchorY + 12;
        top = Math.max(safeTop, Math.min(safeBottom - popupHeight, above >= safeTop ? above : below + popupHeight <= safeBottom ? below : anchorY - popupHeight / 2));
        dialog.dataset.arrow = top + popupHeight / 2 < anchorY ? "bottom" : "top";
      }
    }
    else if (kind === "actions") top = safeBottom - dialog.getBoundingClientRect().height;
    dialog.style.top = top + "px";
    dialog.style.setProperty("--phone-me", frame.style.getPropertyValue("--phone-me"));
    dialog.style.setProperty("--phone-opp", frame.style.getPropertyValue("--phone-opp"));
    dialog.dataset.appearance = getComputedStyle(frame).color === "rgb(0, 0, 0)" ? "light" : "dark";
  }
  function revealSheet() {
    if (!presentation) return;
    frame.scrollIntoView({ block: "nearest" }); positionSheet();
  }
  function clearSheet() {
    window.removeEventListener("resize", revealSheet);
    document.removeEventListener("scroll", positionSheet, true);
    systemAppearance.removeEventListener("change", positionSheet);
    if (window.visualViewport) { window.visualViewport.removeEventListener("resize", revealSheet); window.visualViewport.removeEventListener("scroll", positionSheet); }
    if (sheetObserver) { sheetObserver.disconnect(); sheetObserver = null; }
    if (sheetCleanup) { var cleanup = sheetCleanup; sheetCleanup = null; cleanup(); }
    presentation = null; dimmer.hidden = true; delete frame.dataset.modal;
    dialog.className = "phone-dialog"; dialog.removeAttribute("style"); delete dialog.dataset.presentation; delete dialog.dataset.detent; delete dialog.dataset.arrow;
  }
  dialog.addEventListener("close", function () {
    // A button can close one presentation and open another in the same turn.
    // Its queued close event must never dispose the new presentation.
    if (!dialog.open) clearSheet();
  });
  dialog.addEventListener("cancel", function (event) { event.preventDefault(); closeSheet(); });
  dialog.addEventListener("keydown", function (event) {
    if (event.key !== "Escape") return;
    event.preventDefault(); event.stopPropagation(); closeSheet();
  });
  dialog.addEventListener("pointerdown", function (event) {
    if (event.target !== dialog || !presentation || presentation.kind === "alert" || presentation.kind === "cover") return;
    var bounds = dialog.getBoundingClientRect(), device = frame.getBoundingClientRect();
    var inDialog = event.clientX >= bounds.left && event.clientX <= bounds.right && event.clientY >= bounds.top && event.clientY <= bounds.bottom;
    var inPhone = event.clientX >= device.left && event.clientX <= device.right && event.clientY >= device.top && event.clientY <= device.bottom;
    if (!inDialog && inPhone) closeSheet();
  });
  function showSheet(title, content, options) {
    options = options || {};
    var alreadyOpen = dialog.open;
    clearSheet();
    if (!alreadyOpen) oldFocus = document.activeElement;
    var kind = options.graph ? "cover" : options.presentation || "sheet";
    presentation = { kind: kind, detent: options.detent, width: options.width, anchor: options.anchor };
    dialog.dataset.presentation = kind;
    if (options.detent) dialog.dataset.detent = options.detent;
    dialog.classList.add("phone-device-dialog");
    if (options.variant === "delete") dialog.classList.add("phone-delete-popover");
    if (options.variant === "share") dialog.classList.add("phone-share-menu");
    if (options.variant === "health") dialog.classList.add("phone-health-disclosure");
    if (options.graph) dialog.classList.add("phone-graph-dialog");
    var header = h("div", { class: "phone-sheet-head" }, options.leading || h("span", { class: "phone-sheet-spacer", "aria-hidden": "true" }), h("h2", {}, title));
    if (options.variant === "delete") header.querySelector("h2").prepend(icon("warning"));
    if (kind !== "alert" && kind !== "actions" && kind !== "popover" && options.variant !== "share") header.append(button("Done", closeSheet));
    if (kind === "sheet" || kind === "actions") {
      var origin = null, activePresentation = presentation;
      header.style.touchAction = "none";
      header.addEventListener("pointerdown", function (event) {
        if (event.button !== 0 || event.target.closest("button")) return;
        origin = { x: event.clientX, y: event.clientY }; header.setPointerCapture(event.pointerId);
      });
      header.addEventListener("pointerup", function (event) {
        if (!origin) return;
        var dx = event.clientX - origin.x, dy = event.clientY - origin.y; origin = null;
        if (presentation === activePresentation && dy > 60 && dy > Math.abs(dx) * 1.5) closeSheet();
      });
      header.addEventListener("pointercancel", function () { origin = null; });
    }
    var viewport = h("div", { class: "phone-sheet-content" }, content);
    if (kind === "actions") {
      var cancel = Array.from(content.querySelectorAll("button")).find(function (b) { return b.textContent === "Cancel"; });
      if (cancel) cancel.classList.add("phone-sheet-cancel");
      else viewport.append(button("Cancel", closeSheet, "phone-sheet-cancel"));
    }
    dialog.replaceChildren(header, viewport);
    dialog.setAttribute("aria-label", title); dialog.setAttribute("role", kind === "alert" ? "alertdialog" : "dialog");
    frame.scrollIntoView({ block: "nearest" });
    dimmer.hidden = kind === "cover" || kind === "popover" || options.variant === "share"; frame.dataset.modal = kind;
    sheetCleanup = options.cleanup || null;
    positionSheet();
    window.addEventListener("resize", revealSheet);
    document.addEventListener("scroll", positionSheet, true);
    systemAppearance.addEventListener("change", positionSheet);
    if (window.visualViewport) { window.visualViewport.addEventListener("resize", revealSheet); window.visualViewport.addEventListener("scroll", positionSheet); }
    if (!dialog.open) dialog.showModal();
    positionSheet();
    if (window.ResizeObserver) { sheetObserver = new ResizeObserver(revealSheet); sheetObserver.observe(frame); sheetObserver.observe(dialog); }
    return dialog;
  }
  function closeSheet() {
    if (dialog.open) dialog.close();
    clearSheet();
    if (oldFocus && oldFocus.isConnected) oldFocus.focus({ preventScroll: true });
  }
  function confirm(title, message, actionLabel, action, options) {
    var content = h("div", { class: "phone-confirmation" }, note(message), button(actionLabel, function () { closeSheet(); action(); }, "phone-danger"));
    var cancel = button("Cancel", closeSheet);
    if (options && options.presentation === "popover" && !options.visibleCancel) cancel.classList.add("phone-visually-hidden");
    content.append(cancel);
    showSheet(title, content, options || { presentation: "alert" });
  }
  function download(name, type, text) {
    var url, a;
    try {
      url = URL.createObjectURL(new Blob([text], { type: type }));
      a = h("a", { href: url, download: name }); document.body.append(a); a.click();
      setTimeout(function () { URL.revokeObjectURL(url); }, 30000);
      return true;
    } catch (error) {
      if (url) URL.revokeObjectURL(url);
      notify("Export failed: " + error.message + ". Your archive is unchanged.");
      return false;
    } finally { if (a) a.remove(); }
  }
  function navigate(next, rec) {
    if (next !== screen) {clearTimeout(noticeTimer);notice.hidden = true;}
    if (next !== screen && (next === "manual" || screen === "manual")) window.DeuceMatePhoneSettings.resetManual();
    screen = next; selected = rec ? rec.id : selected; render(); body.scrollTop = 0;
  }
  function setSetting(key, value) {
    settings[key] = value;
    if (key === "health") S.health = value;
    api.configure({ tracking: settings.track, compass: settings.compass, health: S.health === "authorized" });
    S.applyTheme(); S.render(); persist();
  }
  function addRecord(rec) {
    tombstones.delete(rec.id); watchOnlyIDs.delete(rec.id); upsert(rec); if (connection.paired) S.upsertRecord(copy(rec)); persist(); S.render(); render();
  }
  function replaceRecords(records) {
    // An explicitly imported match is wanted back, so it must not stay deleted (as addRecord does).
    records.forEach(function (r) { tombstones.delete(r.id); });
    archive = sortRecords(copy(records)); persist(); render();
  }
  function storedOnWatch(id) { return S.history.some(function (r) { return r.id === id; }); }
  function storageLabel(rec) {
    var onPhone = archive.some(function (r) { return r.id === rec.id; });
    if (!onPhone) return "On Apple Watch only";
    return connection.paired && (storedOnWatch(rec.id) || rec.id === S.liveId) ? "⌚ + iPhone" : "iPhone only";
  }
  function result(rec) { return S.records.resultLabel(rec); }
  function format(rec) { return S.formatInfo(rec.format).label + " · " + (rec.matchType === "doubles" ? "Doubles" : "Singles"); }

  function row(rec) {
    var b = button("", function () { navigate("detail", rec); }, "phone-match-row");
    b.dataset.focusKey = "phone-match-" + rec.id;
    var statusText = rec.id === S.liveId ? "Live" : !rec.endTime ? "In Progress" : (rec.stats || []).length ? "Stats" : "Score";
    var badge = h("span", { class: "phone-row-badge" }, icon(statusText === "In Progress" ? "pause" : statusText === "Stats" ? "stats" : "score"), statusText);
    var location = h("span", { class: "phone-row-badge phone-storage-badge", "aria-label": storageLabel(rec), title: storageLabel(rec) });
    if (storageLabel(rec) !== "iPhone only") location.append(icon("watch"));
    if (storageLabel(rec) !== "On Apple Watch only") location.append(icon("phone"));
    b.append(h("span", { class: "phone-row-top" }, h("span", { class: "phone-row-date" }, new Date(rec.startTime).toLocaleString([], { dateStyle: "medium", timeStyle: "short" })), h("span", { class: "phone-row-badges" }, badge, connection.paired ? location : null)),
      h("strong", { class: "phone-row-score" }, window.DeuceMatePhoneReports.score(rec, "me")),
      h("span", { class: "phone-row-format" }, rec.endTime ? h("span", { class: "phone-result-badge " + (rec.iWon === true ? "won" : rec.iWon === false ? "lost" : "draw") }, rec.iWon === true ? "Won" : rec.iWon === false ? "Lost" : "Draw") : null, format(rec)));
    var actions = button("•••", function () { recordActions(rec); }, "phone-row-menu");
    actions.dataset.focusKey = "phone-actions-" + rec.id;
    actions.setAttribute("aria-label", "Match actions: " + result(rec));
    var wrap = h("div", { class: "phone-match-wrap", "data-match-id": rec.id });
    var onPhone = archive.some(function (a) { return a.id === rec.id; });
    var canRemoveFromWatch = onPhone && connection.paired && storedOnWatch(rec.id);
    if (rec.id !== S.liveId) {
      var swipeWidth = canRemoveFromWatch ? 190 : 90;
      var swipeActions = h("div", { class: "phone-swipe-actions" });
      swipeActions.style.width = swipeWidth + "px";
      var deleteAction = button("Delete", function () { requestPermanentDelete(rec); }, "phone-swipe-delete");
      deleteAction.dataset.focusKey = "phone-delete-" + rec.id;
      deleteAction.setAttribute("aria-label", "Delete match; confirmation required");
      swipeActions.append(deleteAction);
      if (canRemoveFromWatch) {
        var swipeAction = button("Remove from Watch", function () { removeFromWatch(rec); }, "phone-swipe-action");
        swipeAction.dataset.focusKey = "phone-remove-" + rec.id;
        swipeAction.setAttribute("aria-label", "Remove from Watch; keep the iPhone copy");
        swipeActions.append(swipeAction);
      }
      wrap.append(swipeActions);
      var start = null, moved = false;
      function onSwipeMove(event) {
        if (!start || start.id !== event.pointerId) return;
        var dx = event.clientX - start.x, dy = event.clientY - start.y;
        if (Math.abs(dx) > 8 && Math.abs(dx) > Math.abs(dy)) {
          moved = true;
          if (dx < 0) wrap.classList.add("phone-swipe-open");
          b.style.transform = "translateX(" + (wrap.classList.contains("phone-swipe-open") ? Math.max(-swipeWidth, Math.min(0, (dx < 0 ? dx : -swipeWidth + dx))) : 0) + "px)";
          event.preventDefault();
        }
      }
      function onSwipeEnd(event) {
        if (!start || start.id !== event.pointerId) return;
        var dx = event.clientX - start.x, width = wrap.getBoundingClientRect().width;
        start = null;
        document.removeEventListener("pointermove", onSwipeMove);
        document.removeEventListener("pointerup", onSwipeEnd);
        document.removeEventListener("pointercancel", onSwipeCancel);
        if (moved) {
          b.dataset.ignoreClickUntil = String(Date.now() + 500);
          if (canRemoveFromWatch && dx <= -Math.min(210, width * 0.62)) {
            removeFromWatch(rec);
            return;
          }
          if (dx > 55) { b.style.transform = ""; wrap.classList.remove("phone-swipe-open"); }
          else if (dx < -20) { wrap.classList.add("phone-swipe-open"); b.style.transform = "translateX(-" + swipeWidth + "px)"; }
        }
      }
      function onSwipeCancel() {
        start = null; b.style.transform = "";
        wrap.classList.remove("phone-swipe-open");
        document.removeEventListener("pointermove", onSwipeMove);
        document.removeEventListener("pointerup", onSwipeEnd);
        document.removeEventListener("pointercancel", onSwipeCancel);
      }
      wrap.addEventListener("pointerdown", function (event) {
        if (event.button !== 0 || event.target.closest(".phone-row-menu,.phone-swipe-actions")) return;
        start = { x: event.clientX, y: event.clientY, id: event.pointerId };
        moved = false;
        document.addEventListener("pointermove", onSwipeMove);
        document.addEventListener("pointerup", onSwipeEnd);
        document.addEventListener("pointercancel", onSwipeCancel);
      });
      b.addEventListener("click", function (event) {
        if (Number(b.dataset.ignoreClickUntil || 0) > Date.now()) {
          event.preventDefault(); event.stopImmediatePropagation();
          b.dataset.ignoreClickUntil = "0";
        }
      }, true);
      swipeActions.addEventListener("click", function () { b.style.transform = ""; wrap.classList.remove("phone-swipe-open"); });
    }
    wrap.append(b, actions);
    return wrap;
  }
  function removeFromWatch(rec) {
    S.history = S.history.filter(function (r) { return r.id !== rec.id; });
    persist(); S.render(); render(); notify("Removed from Watch. The iPhone copy is retained.");
  }
  function syncToWatch(rec) {
    watchOnlyIDs.delete(rec.id); S.upsertRecord(copy(rec)); persist(); S.render(); render(); notify("Match copied to the simulated Watch.");
  }
  function recordActions(rec) {
    var actions = h("div", { class: "phone-action-list" });
    var onPhone = archive.some(function (r) { return r.id === rec.id; });
    if (!onPhone) actions.append(button("Sync to iPhone", function () { watchOnlyIDs.delete(rec.id); upsert(withDemoHealth(rec)); closeSheet(); persist(); render(); }));
    else if (connection.paired && storedOnWatch(rec.id)) actions.append(button("Remove from Watch", function () {
      closeSheet(); removeFromWatch(rec);
    }));
    else if (connection.paired) actions.append(button("Sync to Watch", function () { closeSheet(); syncToWatch(rec); }));
    if (!rec.endTime) actions.append(button("End at Current Score", function () { closeSheet(); endRecord(rec); }));
    actions.append(button("Delete Permanently", function () {
      requestPermanentDelete(rec);
    }, "phone-danger"));
    showSheet("Match actions", actions, { presentation: "actions" });
  }
  function requestPermanentDelete(rec) {
    var onWatch = connection.paired && (storedOnWatch(rec.id) || rec.id === S.liveId);
    var row = Array.from(body.querySelectorAll(".phone-match-wrap")).find(function (element) { return element.dataset.matchId === rec.id; });
    var rowOffset = row ? row.getBoundingClientRect().top - frame.getBoundingClientRect().top : null, rowHeight = row ? row.getBoundingClientRect().height : 0;
    function deleteAnchor() {
      var current = Array.from(body.querySelectorAll(".phone-match-wrap")).find(function (element) { return element.dataset.matchId === rec.id; });
      if (current) return current.getBoundingClientRect();
      if (rowOffset == null) return null;
      var top = frame.getBoundingClientRect().top + rowOffset; return { top: top, bottom: top + rowHeight };
    }
    confirm("Delete permanently?", "This deletes the match from " + (onWatch ? "iPhone and Apple Watch" : "iPhone") + " for good — this can't be undone.", "Delete Permanently", function () {
      tombstones.add(rec.id); archive = archive.filter(function (r) { return r.id !== rec.id; });
      if (onWatch) {
        S.history = S.history.filter(function (r) { return r.id !== rec.id; });
        if (rec.id === S.liveId) { api.clear(); S.liveId = null; S.popAll(); }
      }
      persist(); S.render(); navigate("matches");
    }, { presentation: "popover", width: 320, anchor: row ? deleteAnchor : null, variant: "delete", visibleCancel: true });
  }
  function endRecord(rec) {
    confirm("End at current score?", "This marks the match completed and it can no longer be resumed. A tied score is saved as a draw.", "End at Current Score", function () {
      var finished, wasLive = api.active() && S.liveId === rec.id;
      if (wasLive) {
        finished = api.snapshot(true); finished.id = rec.id;
        api.clear(); S.liveId = null; S.popAll();
      } else {
        finished = copy(rec);
        var leader = E.leaderWhenStopped({ cfg: E.cfgFor(rec.format), sets: rec.sets, currentPointsMe: rec.currentPointsMe, currentPointsOpponent: rec.currentPointsOpponent });
        finished.iWon = leader ? leader === "me" : null; finished.endTime = Date.now();
      }
      upsert(finished); if (wasLive || storedOnWatch(rec.id)) S.upsertRecord(copy(finished));
      persist(); S.render(); navigate("matches");
    }, { presentation: "popover" });
  }
  function cloudGuide() {
    var content = h("div", { class: "phone-cloud-guide" },
      icon("cloudWarning"),
      note("Your matches are stored on this iPhone only. To keep DeuceMate's app-managed archive in iCloud Drive, follow these steps:"),
      h("ol", {},
        h("li", {}, "Tap Open Settings below."),
        h("li", {}, "Return to the main Settings screen, then tap your Apple Account."),
        h("li", {}, "Tap iCloud → Drive, then turn on Sync this iPhone."),
        h("li", {}, "Under Saved to iCloud, tap See All and turn on DeuceMate.")),
      note("Automatic restores keep matches, scores, and non-health stats, but not recorded heart rate, steps, distance, or calories. To move those fitness metrics to a new iPhone, use Settings → Backup & Transfer → Export before switching, then Import on the new phone."),
      button("Open Settings", function () { notify("Would open iPhone Settings here — device settings are simulated in this browser demo."); }, "phone-primary"));
    showSheet("iCloud Drive Unavailable", content, { detent: "medium" });
  }
  function cloudStatusRow() {
    if (cloudState === "uploaded") return note("☁ Backed up to iCloud (simulated)");
    if (cloudState === "pending") return note("☁ Waiting to upload to iCloud (simulated)");
    return button("☁ iCloud unavailable — stored on iPhone ›", cloudGuide, "phone-cloud-status");
  }
  function matches() {
    var out = h("div", {});
    out.append(window.DeuceMatePhoneTrends.headline(phone));
    if (connection.activation === "connecting") out.append(card(heading("Connecting to Apple Watch…"), note("Your iPhone archive stays available while Watch connectivity starts.")));
    else if (connection.activation === "unavailable") out.append(card(heading("Apple Watch Unavailable"), note("Watch connectivity couldn't be started. You can still create, review, and export matches on this iPhone.")));
    if (connection.syncing) out.append(card(note("Syncing with Apple Watch… Your saved iPhone matches remain available.")));
    if (connection.syncFailure) out.append(card(heading("Watch sync unavailable"), note("The latest Watch sync failed. Matches already saved on this iPhone are still available.")));
    if (connection.archiveReadFailure || storageReadFailed) out.append(card(heading("Saved archive unavailable"), note("The saved browser archive could not be read. Any cached iPhone matches remain visible and have not been overwritten.")));
    var live = connection.paired && connection.activation === "ready" ? liveRecord() : null;
    if (live) out.append(heading("Live Match"), card(row(live), button("▣ Live Scoreboard", function () { navigate("live"); }, "phone-primary")));
    var all = archive.slice();
    if (connection.paired) S.history.forEach(function (r) {
      if (!tombstones.has(r.id) && !all.some(function (a) { return a.id === r.id; })) all.push(r);
    });
    var past = sortRecords(all).filter(function (r) { return !live || r.id !== live.id; });
    out.append(heading("Past Matches"));
    if (past.length) out.append(card(past.map(row)));
    else {
      var emptyTitle = connection.activation === "connecting" ? "Connecting to Apple Watch…" : connection.activation === "unavailable" ? "Apple Watch Unavailable" : connection.paired ? "No Matches Yet" : "No Apple Watch Paired";
      var emptyCopy = connection.activation === "connecting" ? "Watch history will appear after connectivity is ready. You can enter matches manually meanwhile." : connection.activation === "unavailable" ? "Watch connectivity couldn't be started. You can still create, review, and export matches on this iPhone." : connection.paired ? "Open DeuceMate on your Apple Watch — your match history will sync automatically." : "Pair an Apple Watch with DeuceMate installed to sync your match history here.";
      out.append(card(heading(emptyTitle), note(emptyCopy), button("Enter a match manually", function () { navigate("manual"); })));
    }
    out.append(note(archive.length + " " + (archive.length === 1 ? "match" : "matches") + " kept on iPhone — your full history stays here. Apple Watch holds the most recent 25."),
      cloudStatusRow(),
      button("↻ Sync Now", syncNow));
    if (persistenceError) out.append(note("Browser storage is unavailable. This session still works; export your demo archive to keep it."));
    return out;
  }
  function send(command, value) {
    if (!settings.iPhoneInput || !connection.paired || !connection.reachable || connection.activation !== "ready") return;
    api.phoneCommand(command, value, displayedLiveId);
    queueRender();
  }
  function liveBoard() {
    var rec = liveRecord(), out = h("div", { class: "phone-live" });
    displayedLiveId = rec ? rec.id : null;
    if (!rec || !connection.paired) return card(heading("Waiting for Apple Watch"), note("Start a match on the watch simulator to see the live scoreboard here."));
    var state = api.stateRef(), pending = api.phoneState(), cur = E.lastSet(state);
    // Mirrors LiveScoreboardView: LIVE badge + close in the chrome, ME/OPP rows, then momentum + format label.
    var theme = S.THEMES[settings.theme] || S.THEMES.default, complete = api.complete();
    var closeLive = button("", function () { setOrientation(false); navigate("matches"); }, "phone-live-close");
    closeLive.append(icon("closeCircle")); closeLive.setAttribute("aria-label", "Back to Matches");
    var badge = h("span", { class: "phone-live-badge" }, h("i", {}), h("b", {}, complete ? "MATCH COMPLETE" : "LIVE"));
    out.append(h("div", { class: "phone-live-top" }, badge, closeLive));
    var court = h("div", { class: "phone-scoreboard", tabindex: "0", "aria-label": "Live scoreboard. Swipe up for Me, down for Opponent, left to undo." });
    court.dataset.focusKey = "phone-live-scoreboard";
    var points = E.regularPointStrings(state.currentPointsMe, state.currentPointsOpponent), lastIndex = state.sets.length - 1;
    ["me", "opponent"].forEach(function (side, index) {
      var isMe = side === "me", server = state.currentServer === side, color = "rgb(" + (isMe ? theme.me : theme.opp) + ")";
      var r = h("div", { class: "phone-score-row phone-live-row " + (isMe ? "me" : "opp") });
      r.style.setProperty("--row-color", color); r.style.setProperty("--server-color", "rgb(" + theme.server + ")");
      var name = h("span", { class: "phone-live-name" }, h("b", {}, isMe ? "ME" : "OPP"), h("span", { class: "phone-server" }, server ? h("i", {}) : ""));
      if (server && rec.resume.secondServe) name.querySelector(".phone-server").append(h("em", {}, "2"));
      r.append(name);
      state.sets.forEach(function (set, i) {
        var games = isMe ? set.gamesMe : set.gamesOpponent, tb = isMe ? set.tieBreakPointsMe : set.tieBreakPointsOpponent, cell = h("span", { class: "phone-set-number" + (i === lastIndex ? " current" : "") }, String(games));
        if (i < lastIndex && set.isTieBreak && tb > 0) cell.append(h("sup", {}, String(tb)));
        r.append(cell);
      });
      var tbNow = cur.isTieBreak, tbScore = isMe ? cur.tieBreakPointsMe : cur.tieBreakPointsOpponent;
      var deuce = !tbNow && state.currentPointsMe >= 3 && state.currentPointsMe === state.currentPointsOpponent;
      r.append(h("b", { class: "phone-point-number" + (deuce ? " deuce" : "") }, tbNow ? String(tbScore) : points[index]));
      court.append(r);
    });
    var start;
    function finishSwipe(e) {
      if (!start || start.pointerId !== e.pointerId) return;
      var gesture = start; start = null;
      document.removeEventListener("pointerup", finishSwipe);
      document.removeEventListener("pointercancel", finishSwipe);
      if (e.type === "pointercancel" || screen !== "live" || gesture.matchID !== displayedLiveId || !settings.iPhoneInput || !connection.reachable) return;
      var dx = e.clientX - gesture.x, dy = e.clientY - gesture.y, now = performance.now();
      if (now - lastPhoneSwipe < 250) return;
      if (Math.abs(dy) > 20 && Math.abs(dy) > Math.abs(dx)) { lastPhoneSwipe = now; send("point", dy < 0 ? "me" : "opponent"); }
      else if (dx < -20 && Math.abs(dx) > Math.abs(dy)) { lastPhoneSwipe = now; send("undo"); }
    }
    court.addEventListener("pointerdown", function (e) {
      if (e.button !== 0 || start) return;
      start = { x: e.clientX, y: e.clientY, pointerId: e.pointerId, matchID: displayedLiveId };
      // Keep the release listener alive if a Watch echo redraws the court.
      document.addEventListener("pointerup", finishSwipe);
      document.addEventListener("pointercancel", finishSwipe);
    });
    court.addEventListener("dblclick", function () { send("secondServe"); });
    court.addEventListener("keydown", function (e) {
      if (["ArrowUp", "ArrowDown", "ArrowLeft", "2"].indexOf(e.key) < 0) return;
      e.preventDefault(); e.stopPropagation();
      if (e.key === "2") send("secondServe"); else if (e.key === "ArrowLeft") send("undo"); else send("point", e.key === "ArrowUp" ? "me" : "opponent");
    });
    var recent = rec.resume.momentum.slice(-8), slots = h("div", { class: "phone-momentum" + (recent.length ? "" : " empty") });
    for (var slot = 0; slot < 8; slot++) { var who = recent[slot - (8 - recent.length)]; slots.append(h("i", { class: who === "me" ? "me" : who ? "opp" : "" })); }
    var bottom = h("div", { class: "phone-live-bottom" }, recent.length ? slots : "", h("span", { class: "phone-live-format" }, format(rec)));
    if (settings.iPhoneInput) bottom.append(h("span", { class: "phone-live-hint" }, "↑ Me   ↓ Opp   ← Undo"));
    out.append(court, bottom);
    if (pending.pending && settings.iPhoneInput) {
      var commandsAvailable = connection.paired && connection.reachable && connection.activation === "ready";
      var p = pending.pending, panel = card(heading((p.winner === "me" ? "Won" : "Lost") + " — " + (p.server === "me" ? "Your" : "Their") + " serve" + (p.isSecondServe ? " · 2nd" : "")));
      if (pending.outcome) {
        var back = button("‹ Back", function () { send("back"); }); back.disabled = pending.busy || !commandsAvailable;
        panel.append(back, note(T.OUTCOME_LABELS[pending.outcome]));
        T.endingShotOptions(pending.outcome, p).forEach(function (shot) {
          var b = button(shot === "serve" && pending.outcome === "winner" ? "Ace" : T.ENDING_SHOT_LABELS[shot], function () { send("shot", shot); }); b.disabled = pending.busy || !commandsAvailable; panel.append(b);
        });
      } else T.USER_SELECTABLE_OUTCOMES.filter(function (o) { return o !== "doubleFault" || T.doubleFaultAvailable(p); }).forEach(function (o) {
        var b = button(T.OUTCOME_LABELS[o], function () { send("outcome", o); }, "phone-outcome " + o); b.disabled = pending.busy || !commandsAvailable; panel.append(b);
      });
      var undo = button("Undo point", function () { send("undo"); }); undo.disabled = pending.busy || !commandsAvailable; panel.append(undo); out.append(panel);
    }
    var extras = h("div", { class: "phone-live-extras" });
    if (settings.iPhoneInput) {
      var controls = h("div", { class: "phone-live-controls" });
      [["↑ Me", "point", "me", pending.canScore], ["↓ Opp", "point", "opponent", pending.canScore], ["← Undo", "undo", null, pending.canUndo], ["2nd serve", "secondServe", null, pending.canSecondServe]].forEach(function (a) {
        var b = button(a[0], function () { send(a[1], a[2]); }); b.disabled = !a[3] || !connection.paired || !connection.reachable || connection.activation !== "ready"; controls.append(b);
        b.dataset.focusKey = "phone-live-command-" + a[1] + (a[2] ? "-" + a[2] : "");
      }); extras.append(controls, note("Double-tap the scoreboard for second serve."));
    } else extras.append(note("Watching live. Enable iPhone Input in Settings to score here."), button("Enable iPhone Input", function () { setSetting("iPhoneInput", true); render(); }));
    var status = h("div", { class: "phone-live-status", role: "status" });
    if (pending.changeover || pending.doublesDecision) status.append(note("Continue on the Watch to dismiss its open screen before scoring."));
    if (settings.announce) status.append(note("🔊 Score announcements enabled"));
    if (connection.activation === "connecting") status.append(note("Connecting to Apple Watch… Commands are unavailable until connected."));
    else if (connection.activation === "unavailable" || !connection.paired) status.append(note("Apple Watch unavailable. Commands are unavailable; the saved iPhone match is retained."));
    else if (!connection.reachable) status.append(note("Watch disconnected. Commands are unavailable until it reconnects."));
    extras.append(button("View Match Stats", function () { navigate("detail", rec); }));
    out.append(status, extras);
    return out;
  }
  function render() {
    var focusedKey = body.contains(document.activeElement) ? document.activeElement.dataset.focusKey : null;
    var theme = S.THEMES[settings.theme] || S.THEMES.default;
    frame.style.setProperty("--phone-me", "rgb(" + theme.me + ")"); frame.style.setProperty("--phone-opp", "rgb(" + theme.opp + ")");
    frame.style.setProperty("--phone-surface", "rgb(" + theme.surface + ")");
    var keep = body.scrollTop;
    frame.dataset.screen = screen;
    var canRotate = screen === "live";
    if (!canRotate && frame.classList.contains("phone-landscape")) setOrientation(false);
    else if (canRotate && renderedScreen !== "live" && turned.matches) setOrientation(true);
    renderedScreen = screen;
    rotateDevice.disabled = !canRotate;
    rotateDevice.title = canRotate ? "" : "Only the live scoreboard rotates; the rest of the app stays in portrait.";
    if (!frame.classList.contains("phone-landscape")) orientationLabel.textContent = canRotate ? "Portrait" : "Portrait only on this screen";
    nav.replaceChildren();
    if (screen === "matches") {
      var entry = button("", function () { navigate("manual"); }); entry.append(icon("edit"));
      var config = button("", function () { navigate("settings"); }); config.append(icon("gear"));
      nav.append(entry, h("strong", {}, "Matches"), config);
    } else {
      var back = button(screen === "trends" ? "" : screen === "manual" ? "Cancel" : "Done", function () { if (screen === "live") setOrientation(false); navigate("matches"); });
      if (screen === "trends") back.append(icon("back"));
      nav.append(back, h("strong", {}, { settings: "Settings", manual: "Manual Entry", detail: "Match Stats", live: "Live Scoreboard", trends: "Trends" }[screen] || "Matches"));
      if (screen === "trends") nav.append(h("span", { class: "phone-nav-spacer", "aria-hidden": "true" }));
    }
    nav.firstChild.setAttribute("aria-label", screen === "matches" ? "Manual match entry" : screen === "manual" ? "Cancel" : "Back to Matches");
    if (screen === "matches") nav.lastChild.setAttribute("aria-label", "Settings");
    var content;
    if (screen === "settings") content = window.DeuceMatePhoneSettings.settings(phone);
    else if (screen === "manual") content = window.DeuceMatePhoneSettings.manual(phone);
    else if (screen === "live") content = liveBoard();
    else if (screen === "trends") content = window.DeuceMatePhoneReports.trends(phone);
    else if (screen === "detail") {
      var rec = archive.find(function (r) { return r.id === selected; }) || S.history.find(function (r) { return r.id === selected; });
      if (S.liveId === selected) rec = liveRecord() || rec;
      content = rec ? window.DeuceMatePhoneReports.detail(phone, rec) : card(note("This match is no longer in the archive."));
      if (rec) {
        nav.querySelector("strong").textContent = !rec.endTime ? new Date(rec.startTime).toLocaleString([], { dateStyle: "medium", timeStyle: "short" }) : window.DeuceMatePhoneReports.detailTitle(rec);
        var tools = h("div", { class: "phone-nav-tools" });
        var ai = button("", function () { window.DeuceMatePhoneReports.openAI(phone, rec, rec.stats || [], "me"); });
        ai.setAttribute("aria-label", "Open AI Coach"); ai.append(icon("sparkles"));
        var share = button("", function () { content.openShare(); });
        share.setAttribute("aria-label", "Share match"); share.append(icon("share"));
        tools.append(ai, share); nav.append(tools);
      }
    } else content = matches();
    body.replaceChildren(content); body.scrollTop = keep;
    lastSignature = viewSignature();
    if (focusedKey) {
      var restore = Array.from(body.querySelectorAll("[data-focus-key]")).find(function (el) { return el.dataset.focusKey === focusedKey; });
      if (restore) restore.focus({ preventScroll: true });
    }
  }
  function viewSignature() {
    return JSON.stringify([S.liveId, api.stateRef(), api.phoneState(), S.history, settings,
      connection.paired, connection.reachable, connection.activation, connection.syncing,
      connection.syncFailure, connection.archiveReadFailure, Array.from(watchOnlyIDs)]);
  }
  function queueRender() {
    if (renderQueued) return;
    renderQueued = true;
    queueMicrotask(function () {
      renderQueued = false; if (viewSignature() === lastSignature) return;
      sync(); if (screen === "matches" || screen === "live") render();
    });
  }
  function announce() {
    var state = api.stateRef();
    if (!settings.announce || !state || api.phoneState().pending) return;
    var signature = JSON.stringify([state.sets, state.currentPointsMe, state.currentPointsOpponent]);
    if (signature === announceSignature) return; announceSignature = signature;
    if (!window.speechSynthesis) return;
    var p = E.regularPointStrings(state.currentPointsMe, state.currentPointsOpponent), cur = E.lastSet(state);
    var text = cur.isTieBreak ? cur.tieBreakPointsMe + " " + cur.tieBreakPointsOpponent : p[0] + " " + p[1];
    speechSynthesis.cancel(); speechSynthesis.speak(new SpeechSynthesisUtterance((settings.name || "Me") + " " + text));
  }
  var phone = window.DeuceMatePhone = { h: h, button: button, card: card, note: note, heading: heading,
    icon: icon, segment: segment, endRecord: endRecord, storageLabel: storageLabel, recordActions: recordActions, removeFromWatch: removeFromWatch, syncToWatch: syncToWatch, storedOnWatch: storedOnWatch,
    cloudStatus: function () { return cloudState === "uploaded" ? "Backed up to iCloud (simulated)" : cloudState === "pending" ? "iCloud upload pending (simulated)" : "iCloud unavailable — stored on iPhone"; },
    records: function () { return copy(archive); }, openSelectedActions: function () { var r = archive.find(function (x) { return x.id === selected; }); if (r) recordActions(r); }, liveRecord: liveRecord, settings: settings,
    navigate: navigate, render: render, showSheet: showSheet, closeSheet: closeSheet, confirm: confirm, notify: notify,
    setSetting: setSetting, addRecord: addRecord, replaceRecords: replaceRecords, sync: sync, syncNow: syncNow, download: download,
    connection: connection };

  // Guide boot runs before this deferred script, so starter history exists.
  try {
    var saved = JSON.parse(localStorage.getItem(storageKey) || "null");
    if (saved && (!Array.isArray(saved.archive) || !Array.isArray(saved.watch) ||
        !saved.archive.concat(saved.watch).every(window.DeuceMatePhoneSettings.validRecord) ||
        (saved.live && !window.DeuceMatePhoneSettings.validRecord(saved.live)))) throw new Error("Invalid saved demo archive");
    if (saved && Array.isArray(saved.archive) && Array.isArray(saved.watch)) {
      archive = saved.archive; S.history = saved.watch; tombstones = new Set(saved.tombstones || []);
      watchOnlyIDs = new Set(saved.watchOnlyIDs || []);
      if (saved.connection && ["ready", "connecting", "unavailable"].indexOf(saved.connection.activation) >= 0) Object.assign(connection, saved.connection);
      Object.assign(settings, saved.settings || {}); S.health = settings.health || "authorized";
      cloudBackup = saved.cloudBackup || null; cloudState = saved.cloudState || "unavailable";
      api.configure({ tracking: settings.track, compass: settings.compass, health: S.health === "authorized" });
      S.applyTheme();
      if (saved.live && saved.live.resume && !saved.live.endTime) {
        api.restore(saved.live); S.liveId = saved.live.id; S.matchPhase = "play"; S.push({ id: "match" });
      }
    }
  } catch (_) { storageReadFailed = true; }
  sync();
  var oldChange = api.hooks.change, oldRender = S.onRender;
  api.hooks.phoneInputEnabled = function () { return !!settings.iPhoneInput && connection.paired && connection.reachable && connection.activation === "ready"; };
  api.hooks.phoneMatchID = function () { return S.liveId; };
  api.hooks.change = function () { if (oldChange) oldChange(); queueRender(); announce(); };
  S.onRender = function () { if (oldRender) oldRender(); settings.health = S.health; queueRender(); };
  render();
  // Details refresh only when the point stream actually changes, preserving
  // graph filters during ordinary watch timer ticks.
  setInterval(function () {
    var signature = viewSignature();
    if (signature === lastSignature) return; lastSignature = signature;
    sync(); if (screen === "matches" || screen === "live" || (screen === "detail" && selected === S.liveId)) render();
  }, 750);
  window.addEventListener("pagehide", persist);

  // Explicit demo controls stay outside the replica's native screens.
  var experiments = h("details", { class: "phone-experiments" }, h("summary", {}, "Demo controls"), note("These affect only the browser simulation."));
  function demoToggle(label, key) {
    var input = h("input", { type: "checkbox", checked: connection[key], onchange: function () {
      connection[key] = input.checked; if (connection.paired && connection.reachable) sync(); persist(); render();
    } });
    return h("label", { class: "phone-field" }, label, input);
  }
  var activation = h("select", { "aria-label": "Watch activation state" });
  [["ready", "Ready"], ["connecting", "Connecting"], ["unavailable", "Unavailable"]].forEach(function (choice) {
    activation.append(h("option", { value: choice[0] }, choice[1]));
  });
  activation.value = connection.activation;
  activation.addEventListener("change", function () { connection.activation = activation.value; if (connection.activation === "ready") sync(); persist(); render(); });
  experiments.append(demoToggle("Watch paired", "paired"), demoToggle("Watch reachable", "reachable"),
    h("label", { class: "phone-field" }, "Watch activation", activation),
    demoToggle("Sync pending", "syncing"), demoToggle("Simulate sync failure", "syncFailure"),
    demoToggle("Simulate saved archive read failure", "archiveReadFailure"),
    button("Browser export tools", function () {
      var record = archive.find(function (r) { return r.id === selected; });
      if (screen !== "detail" || !record) { notify("Open a match to use the browser export tools."); return; }
      window.DeuceMatePhoneReports.openBrowserExports(phone, record);
    }),
    button("Simulate cloud backup", function () {
      cloudState = "pending"; render();
      cloudBackup = copy(archive).map(function (r) { r.steps = 0; r.kcal = 0; delete r.distanceMeters; delete r.distance; r.stats.forEach(function (p) { delete p.heartRateBPM; delete p.stepsCumulative; }); return r; });
      setTimeout(function () { cloudState = "uploaded"; persist(); render(); notify("Demo backup saved locally, without health measurements."); }, 650);
    }),
    button("Preview cloud restore", function () {
      if (!cloudBackup) { notify("Create a simulated cloud backup first."); return; }
      showSheet("Restore matches from iCloud?", h("div", {}, note("Found a simulated backup with " + cloudBackup.length + " matches. Restore it to this iPhone?"), button("Restore", function () { cloudBackup.forEach(upsert); closeSheet(); persist(); render(); }), button("Not Now", closeSheet)), { presentation: "alert" });
    }),
    button("Show a Watch-only match", function () {
      var rec = S.history.find(function (r) { return r.id !== S.liveId; });
      if (!rec) { notify("Create a match first."); return; }
      archive = archive.filter(function (r) { return r.id !== rec.id; }); watchOnlyIDs.add(rec.id); persist(); navigate("matches");
    }),
    button("Reset demo", function () { confirm("Reset this demo?", "Restore the sample archive and default settings in this browser.", "Reset demo", function () { resetting = true; localStorage.removeItem(storageKey); location.reload(); }); }));
  host.append(experiments);
})();
