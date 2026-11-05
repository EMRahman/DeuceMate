/* Browser replica of the iPhone "Match Info" block (MatchInfoSection, MatchInfoEditorView,
   MatchNotesEditorView, MatchComparisonView) and the completed-match Singles<->Doubles
   conversion. Tags live on the archive record (`rec.tags`); private notes live in their own
   browser-storage key, never on the record, so they cannot reach exports or sync (as native). */
(function () {
  "use strict";
  var NOTE_KEY = "deucemate-browser-notes-v1", NOTE_LIMIT = 4000, EXPAND_KEY = "deucemate-matchinfo-expanded";
  var COMPETITIONS = [["friendly", "Friendly"], ["league", "League"], ["tournament", "Tournament"], ["practice", "Practice"]];
  var HAND = [["rightHanded", "Right-handed"], ["leftHanded", "Left-handed"]];
  var BACK = [["twoHanded", "Two-handed"], ["oneHanded", "One-handed"]];
  var STYLE = [["allCourt", "All-Court"], ["aggressiveBaseliner", "Aggressive Baseliner"], ["counterpuncher", "Counterpuncher"], ["serveAndVolley", "Serve & Volley"], ["pusher", "Pusher"]];

  function h(tag, cls, text) { var e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }
  function label(list, key) { var f = list.find(function (x) { return x[0] === key; }); return f ? f[1] : null; }
  function clean(name) { return String(name || "").replace(/\s+/g, " ").trim().slice(0, 40); }
  // Player identity is the stored id (names are only display/search); fall back to the name for id-less imports.
  function pid(p) { return p && p.id ? String(p.id) : "n:" + clean(p && p.name).toLowerCase(); }
  function samePlayer(a, b) { return !!a && !!b && pid(a) === pid(b); }
  function sameName(a, b) { return clean(a).toLowerCase() === clean(b).toLowerCase(); }

  // MARK: notes
  function readNotes() { try { return JSON.parse(localStorage.getItem(NOTE_KEY) || "{}") || {}; } catch (_) { return {}; } }
  function getNote(id) { return readNotes()[id] || ""; }
  function setNote(id, text) {
    var all = readNotes(), value = String(text || "").slice(0, NOTE_LIMIT);
    if (value.trim()) all[id] = value; else delete all[id];
    try { localStorage.setItem(NOTE_KEY, JSON.stringify(all)); } catch (_) {}
  }
  function expanded() { try { return localStorage.getItem(EXPAND_KEY) === "1"; } catch (_) { return false; } }
  function setExpanded(v) { try { localStorage.setItem(EXPAND_KEY, v ? "1" : "0"); } catch (_) {} }

  // MARK: tags (MatchTags.displayLine / isEmpty / singles trimming)
  function displayLine(tags) {
    if (!tags) return null;
    var who = [];
    if (tags.partner) who.push("With " + tags.partner.name);
    if ((tags.opponents || []).length) who.push("vs " + tags.opponents.map(function (p) { return p.name; }).join(" & "));
    var parts = [];
    if (who.length) parts.push(who.join(" "));
    var comp = label(COMPETITIONS, tags.competition);
    if (comp) parts.push(comp);
    return parts.length ? parts.join(" · ") : null;
  }
  function whoLine(tags) { return displayLine(Object.assign({}, tags, { competition: null })); }
  function playersDroppedConvertingToSingles(rec) {
    var t = rec.tags; if (!t || rec.matchType !== "doubles") return [];
    return (t.partner ? [t.partner] : []).concat((t.opponents || []).slice(1));
  }
  function convertedTags(tags, target) {
    if (!tags || target !== "singles") return tags;
    var next = Object.assign({}, tags, { partner: null, opponents: (tags.opponents || []).slice(0, 1) });
    return !next.opponents.length && !next.competition ? null : next;
  }
  function convertible(rec) { return rec.endTime ? (rec.matchType === "doubles" ? "singles" : "doubles") : null; }
  function convert(phone, rec) {
    var target = convertible(rec); if (!target) return;
    phone.updateRecord(rec.id, function (r) {
      r.matchType = target; r.tags = convertedTags(r.tags, target) || undefined; r.matchTypeRevision = Date.now();
      if (target === "singles") { delete r.currentServerDoubles; delete r.doublesServer; }
    });
  }

  // MARK: roster (derived from the archive, as native PlayerRoster)
  function roster(phone, exceptId) {
    var seen = {}, out = [];
    phone.records().forEach(function (r) {
      var t = r.tags; if (!t) return;
      (t.partner ? [t.partner] : []).concat(t.opponents || []).forEach(function (p) {
        var k = pid(p); if (!clean(p.name) || seen[k]) return; seen[k] = true; out.push(p);
      });
    });
    return out;
  }

  // MARK: head-to-head (completed-only, same matchup + type)
  function key(rec) {
    var t = rec.tags; if (!t || !(t.opponents || []).length) return null;
    var opp = t.opponents.map(pid).sort().join("|");
    if (rec.matchType === "doubles") { if (t.opponents.length < 2 || !t.partner) return null; return "d:" + opp + ":" + pid(t.partner); }
    return "s:" + opp;
  }
  function headToHead(phone, rec) {
    var k = key(rec); if (!k) return null;
    var all = phone.records().filter(function (r) { return r.id !== rec.id && r.endTime && key(r) === k; }).sort(window.DeuceMateChronology.newest);
    if (!all.length) return null;
    var wins = all.filter(function (r) { return r.iWon === true; }).length, losses = all.filter(function (r) { return r.iWon === false; }).length;
    var form = all.slice(0, 3).map(function (r) { return r.iWon === true ? "W" : r.iWon === false ? "L" : "D"; }).join(" ");
    return wins + "–" + losses + " in " + all.length + " match" + (all.length === 1 ? "" : "es") + " · last " + Math.min(3, all.length) + ": " + form;
  }
  function previousMatch(phone, rec) {
    var k = key(rec), list = phone.records().filter(function (r) { return r.id !== rec.id && !window.DeuceMateChronology.inProgress(r) && window.DeuceMateChronology.oldest(r, rec) < 0; }).sort(window.DeuceMateChronology.newest);
    var rematch = k ? list.find(function (r) { return key(r) === k; }) : null;
    if (rematch) return { rec: rematch, kind: "Previous match against the same opponent" };
    var same = list.find(function (r) { return r.matchType === rec.matchType; });
    return same ? { rec: same, kind: "Previous " + (rec.matchType === "doubles" ? "doubles" : "singles") + " match" } : null;
  }

  // Grouped native-style card used by the pushed Compare / Opponent screens.
  function group(title, children) {
    var g = h("section", "pr-native-section mi-section"), card = h("div", "pr-native-card mi-card");
    if (title) g.append(h("h3", "pr-native-section-title", title));
    [].concat(children).forEach(function (c) { if (c) card.append(c); });
    g.append(card); return g;
  }
  function kvRow(k, v) { var r = h("div", "mi-kv"); r.append(h("span", "mi-kv-k", k), h("span", "mi-kv-v", v)); return r; }
  function dateOnly(ms) { return new Date(ms).toLocaleDateString([], { day: "numeric", month: "short", year: "numeric" }); }
  function dateTime(ms) { return new Date(ms).toLocaleString([], { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }); }
  function pad(n) { return n; }
  function minutesText(sec) { var m = Math.round((sec || 0) / 60); return m >= 60 ? Math.floor(m / 60) + " h " + (m % 60) + " min" : m + " min"; }
  function matchRow(phone, r, onClick) {
    var P = window.DeuceMatePhoneReports, b = phone.button("", onClick || function () {}, "mi-match-row");
    var c = h("span", "mi-match-copy"), res = h("span", "mi-match-res");
    res.append(h("strong", "", r.endTime ? resultWord(r) : "In Progress"), h("span", "", (r.matchType === "doubles" ? "Doubles" : "Singles") + " · " + ((window.DeuceMateShell && window.DeuceMateShell.formatInfo && window.DeuceMateShell.formatInfo(r.format) || { label: "Best of 3" }).label)));
    c.append(h("span", "mi-match-date", window.DeuceMateChronology.describe(r, dateTime)), h("strong", "mi-match-score", P.score(r, "me")), res);
    b.append(c, phone.icon("chevron")); return b;
  }
  function openRecord(phone, r) { phone.closeSheet(); phone.navigate("detail", r); }

  // MARK: UI pieces
  function row(phone, icon, title, sub, onClick, disabled, tint) {
    var b = phone.button("", onClick, "mi-row" + (tint ? " mi-tint" : "")); b.disabled = !!disabled;
    var left = h("span", "mi-row-copy"); left.append(h("span", "mi-row-title", title)); if (sub) left.append(h("span", "mi-row-sub", sub));
    b.append(phone.icon(icon), left, phone.icon("chevron")); return b;
  }
  function segmented(options, value, onPick, cls) {
    var wrap = h("div", "mi-choices " + (cls || ""));
    options.forEach(function (o) {
      var b = h("button", "mi-choice" + (o[0] === value ? " selected" : ""), o[1]); b.type = "button"; b.setAttribute("aria-pressed", String(o[0] === value));
      b.addEventListener("click", function () { onPick(o[0] === value ? null : o[0]); }); wrap.append(b);
    });
    return wrap;
  }

  // Native MatchInfoEditorView: Cancel / Save header, competition tiles, Partner, Opponents, Match Type.
  function backButton(phone, to) { var b = phone.button('', to, 'mi-back'); b.setAttribute('aria-label', 'Back'); b.append(phone.icon('back')); return b; }
  function footnote(text) { return h("p", "mi-footnote", text); }
  function sectionTitle(text) { return h("h3", "pr-native-section-title mi-st", text); }
  // Native PlayerPickerView: search field + close, Existing Player rows (info opens profile), Add as new player.
  function openPlayerPicker(phone, suggestions, exclude, onPick, onClose) {
    var leaving = false, body = h("div", "mi-page"), bar = h("div", "mi-search"), field = h("input", "mi-search-input"), results = h("div", "");
    field.type = "search"; field.placeholder = "Search or add player"; field.maxLength = 40; field.setAttribute("aria-label", "Search players");
    var x = phone.button("", function () { phone.closeSheet(); }, "mi-search-x"); x.setAttribute("aria-label", "Close"); x.append(phone.icon("xCircle"));
    bar.append(field, x); body.append(bar, results);
    function matchesFor(p) { return playerMatchCount(phone, p); }
    function line(p) { var ms = matchesFor(p), last = ms.reduce(function (m, r) { return Math.max(m, window.DeuceMateChronology.activity(r)); }, 0); return ms.length + " match" + (ms.length === 1 ? "" : "es") + (last ? " · last " + dateOnly(last) : ""); }
    function pickRow(p) {
      var wrap = h("div", "mi-row mi-pickrow"), main = phone.button("", function () { onPick(p); }, "mi-pickmain"), copy = h("span", "mi-row-copy");
      copy.append(h("span", "mi-row-title", p.name), h("span", "mi-row-sub", line(p))); main.append(copy);
      var info = phone.button("", function () { leaving = true; profileSheet(phone, p, function () { openPlayerPicker(phone, suggestions, exclude, onPick, onClose); }); }, "mi-info"); info.setAttribute("aria-label", "Manage " + p.name); info.append(phone.icon("info"));
      wrap.append(main, info); return wrap;
    }
    function paint() {
      var q = clean(field.value), pool = suggestions.filter(function (p) { return !(exclude || []).some(function (e) { return samePlayer(e, p); }); });
      results.replaceChildren();
      if (!q) {
        if (pool.length) results.append(sectionTitle("Recent Players"), group(null, pool.slice(0, 8).map(pickRow)));
        results.append(footnote("Tip: first names or nicknames are enough. Up to 40 characters."));
        return;
      }
      var hits = pool.filter(function (p) { return p.name.toLowerCase().indexOf(q.toLowerCase()) >= 0; }), exact = suggestions.some(function (p) { return sameName(p.name, q); });
      if (hits.length) results.append(sectionTitle(hits.length === 1 ? "Existing Player" : "Existing Players"), group(null, hits.map(pickRow)));
      var add = phone.button("", function () { onPick({ name: q, id: "p" + Math.random().toString(36).slice(2, 10) }); }, "mi-row mi-link");
      add.append(phone.icon("person"), h("span", "mi-row-title", (exact ? "Add another “" : "Add “") + q + "” as new player"));
      results.append(group(null, add));
      if (exact) results.append(footnote("“" + q + "” is already a player. Pick them above unless this is a different person."));
      results.append(footnote("Tip: first names or nicknames are enough. Up to 40 characters."));
    }
    field.addEventListener("input", paint); paint();
    phone.showSheet("", body, { detent: "large", cleanup: function () { if (!leaving) onClose(); }, trailing: h("span", "phone-sheet-spacer") });
    setTimeout(function () { try { field.focus(); } catch (_) {} }, 0);
  }
  function playerRow(phone, rec, draft, slot, suggestions, rerender) {
    var player = slot === "partner" ? draft.partner : draft.opponents[slot];
    function setSlot(v) { if (slot === "partner") draft.partner = v; else if (v) draft.opponents[slot] = v; else draft.opponents.splice(slot, 1); }
    function occupied() { var all = (draft.opponents || []).concat(draft.partner ? [draft.partner] : []); return player ? all.filter(function (q) { return !samePlayer(q, player); }) : all; }
    function choose() {
      var picked = false;
      openPlayerPicker(phone, suggestions, occupied(), function (p) {
        picked = true; setSlot(Object.assign({}, p)); rerender();
      }, function () { if (!picked) setTimeout(rerender, 0); });
    }
    var wrap = h("div", "mi-prow"), info = phone.button("", function () { if (player) profileSheet(phone, player, function () { rerender(); }); }, "mi-info");
    info.setAttribute("aria-label", "Player details"); info.append(phone.icon("info")); info.disabled = !player;
    var name = phone.button("", choose, "mi-name-input mi-name-btn"); name.textContent = player ? player.name : (slot === "partner" ? "Add partner" : "Add opponent"); name.setAttribute("aria-label", (slot === "partner" ? "Partner" : "Opponent " + (slot + 1)) + (player ? ": " + player.name : ": choose player"));
    if (!player) name.classList.add("mi-empty");
    var clear = phone.button("", function () { setSlot(null); rerender(); }, "mi-clear"); clear.setAttribute("aria-label", "Remove player"); clear.append(phone.icon("xCircle")); clear.hidden = !player;
    wrap.append(info, name, clear);
    if (!player && suggestions.length) {
      var chips = h("div", "mi-chips");
      suggestions.filter(function (q) { return !occupied().some(function (n) { return samePlayer(n, q); }); }).slice(0, 4).forEach(function (q) { var c = h("button", "mi-chip", q.name); c.type = "button"; c.addEventListener("click", function () { setSlot(Object.assign({}, q)); rerender(); }); chips.append(c); });
      if (chips.childNodes.length) wrap.append(chips);
    }
    return wrap;
  }
  function profileSheet(phone, player, done) {
    var body = h("div", "mi-page");
    body.append(group("Name", h("input", "mi-name-input mi-block")));
    var input = body.querySelector("input"); input.value = player.name; input.addEventListener("change", function () { var n = clean(input.value); if (n) player.name = n; });
    body.append(group("Playing Style", [["hand", HAND, "Handedness"], ["backhand", BACK, "Backhand"], ["style", STYLE, "Play Style"]].map(function (g) { return pickerRow(g[2], g[1], player[g[0]], function (v) { player[g[0]] = v || null; }); })));
    body.append(footnote("Saved with this match when you save Match Info. Optional tennis profile shown on the opponent detail screen and included in AI Coach match context."));
    phone.showSheet(player.name, body, { detent: "large", cleanup: done });
  }
  function pickerRow(title, options, value, change) {
    var r = h("div", "mi-kv mi-picker"), sel = document.createElement("select"); sel.setAttribute("aria-label", title);
    var none = document.createElement("option"); none.value = ""; none.textContent = "Not specified"; sel.append(none);
    options.forEach(function (o) { var op = document.createElement("option"); op.value = o[0]; op.textContent = o[1]; sel.append(op); });
    sel.value = value || ""; sel.addEventListener("change", function () { change(sel.value); });
    r.append(h("span", "mi-kv-k", title), sel); return r;
  }
  function openEditor(phone, rec, state) {
    if (!state) { var d0 = JSON.parse(JSON.stringify(rec.tags || {})); d0.opponents = d0.opponents || []; d0.type = rec.matchType; state = { draft: d0, original: JSON.stringify(d0) }; }
    var draft = state.draft, suggestions = roster(phone, rec.id), body = h("div", "mi-page"), original = state.original;
    function reopen() { openEditor(phone, rec, state); }
    function dirty() { return JSON.stringify(draft) !== original; }
    function dbl() { return draft.type === "doubles"; }
    function paint() {
      body.replaceChildren();
      body.append(sectionTitle("Competition Type"));
      var grid = h("div", "mi-tiles");
      COMPETITIONS.forEach(function (c) {
        var on = draft.competition === c[0], t = h("button", "mi-tile" + (on ? " selected" : "")); t.type = "button"; t.setAttribute("aria-pressed", String(on));
        t.append(h("span", "", c[1]), h("span", "mi-radio" + (on ? " on" : ""), on ? "✓" : ""));
        t.addEventListener("click", function () { draft.competition = on ? null : c[0]; paint(); }); grid.append(t);
      });
      body.append(wrapCard(grid));
      if (dbl()) { body.append(sectionTitle("Partner"), group(null, playerRow(phone, rec, draft, "partner", suggestions, reopen))); }
      body.append(sectionTitle(dbl() ? "Opponents" : "Opponent"));
      var rows = []; for (var i = 0; i < (dbl() ? 2 : 1); i++) rows.push(playerRow(phone, rec, draft, i, suggestions, reopen));
      body.append(group(null, rows), footnote("First names or nicknames are enough — e.g. Alex. Names are saved with this match in your archive and its iCloud backup, and appear on your Apple Watch."));
      if (rec.endTime) {
        body.append(sectionTitle("Match Type"));
        var seg = h("div", "mi-seg"); [["singles", "Singles"], ["doubles", "Doubles"]].forEach(function (o) {
          var b = h("button", "mi-seg-b" + (draft.type === o[0] ? " on" : ""), o[1]); b.type = "button"; b.addEventListener("click", function () { if (draft.type === o[0]) return; draft.type = o[0]; if (o[0] === "singles") { draft.partner = null; draft.opponents = draft.opponents.slice(0, 1); } paint(); }); seg.append(b);
        });
        body.append(wrapCard(seg), footnote("Change between Singles and Doubles if the wrong match type was selected. Scores, point stats and health data are kept."));
      }
      body.append(group(null, (function () { var b = phone.button("", function () { phone.updateRecord(rec.id, function (r) { r.tags = undefined; }); phone.closeSheet(); }, "mi-row"); b.append(h("span", "mi-row-title mi-destructive", "Clear details")); return b; })()));
    }
    function wrapCard(child) { return group(null, child); }
    paint();
    var cancel = phone.button("Cancel", function () {
      if (!dirty()) { phone.closeSheet(); return; }
      phone.confirm("Discard changes?", "Your edits to this match’s details haven’t been saved.", "Discard Changes", function () { phone.closeSheet(); });
    }, "");
    var save = phone.button("Save", function () {
      draft.opponents = draft.opponents.filter(Boolean);
      var type = draft.type; delete draft.type;
      var empty = !draft.opponents.length && !draft.partner && !draft.competition;
      phone.updateRecord(rec.id, function (r) { if (type && type !== r.matchType) { r.matchType = type; r.matchTypeRevision = Date.now(); } r.tags = empty ? undefined : draft; });
      phone.closeSheet();
    }, "");
    save.classList.add("mi-save");
    phone.showSheet("Match Info", body, { detent: "large", leading: cancel, trailing: save });
  }

  function openNote(phone, rec) {
    var body = h("div", "mi-notepage"), area = h("textarea", "mi-note-area"), count = h("span", "mi-note-count"), status = h("span", "mi-note-status", "Changes save automatically.");
    area.value = getNote(rec.id); area.maxLength = NOTE_LIMIT; area.setAttribute("aria-label", "Private note");
    function update() { count.textContent = area.value.length.toLocaleString("en-US") + " / " + NOTE_LIMIT.toLocaleString("en-US"); }
    var timer = null; function save() { setNote(rec.id, area.value); }
    area.addEventListener("input", function () { update(); clearTimeout(timer); timer = setTimeout(save, 500); }); update();
    var foot = h("div", "mi-note-foot"); foot.append(status, count);
    var privacy = phone.button("", function () { phone.notify ? phone.notify("Private notes stay on this iPhone only. They are never synced, backed up to iCloud, or added to a report unless you opt in when sharing.") : null; }, "mi-privacy"); privacy.append(phone.icon("info"), h("span", "", "Privacy and storage"));
    var del = phone.button("Delete Note", function () { area.value = ""; save(); update(); phone.closeSheet(); phone.render(); }, "mi-delete-note");
    var done = phone.button("Done", function () { clearTimeout(timer); save(); phone.closeSheet(); phone.render(); }, "");
    body.append(area, foot, privacy, del);
    phone.showSheet("Private Note", body, { detent: "large", trailing: done, cleanup: function () { clearTimeout(timer); save(); } });
  }

  function rates(rec) {
    var pts = (rec.stats || []).filter(function (p) { return p.outcome !== "uncategorized"; }), all = rec.stats || [];
    function cnt(arr, f) { return arr.filter(f).length; }
    var srv = all.filter(function (p) { return p.server === "me"; }), ret = all.filter(function (p) { return p.server !== "me"; });
    function pair(n, d) { return d ? { n: n, d: d, pct: n * 100 / d } : null; }
    return [
      ["Points Won", pair(cnt(all, function (p) { return p.winner === "me"; }), all.length), true],
      ["Service Points Won", pair(cnt(srv, function (p) { return p.winner === "me"; }), srv.length), true],
      ["Return Points Won", pair(cnt(ret, function (p) { return p.winner === "me"; }), ret.length), true],
      ["Winners", pair(cnt(pts, function (p) { return p.winner === "me" && p.outcome === "winner"; }), pts.length), true],
      ["Unforced Errors", pair(cnt(pts, function (p) { return p.winner !== "me" && p.outcome === "unforcedError"; }), pts.length), false],
      ["Double Faults", pair(cnt(srv.filter(function (p) { return p.outcome !== "uncategorized"; }), function (p) { return p.outcome === "doubleFault"; }), srv.filter(function (p) { return p.outcome !== "uncategorized"; }).length), false]
    ];
  }
  function openComparison(phone, rec, chosen) {
    var prev = chosen ? { rec: chosen, kind: "Selected match" } : previousMatch(phone, rec), P = window.DeuceMatePhoneReports;
    var body = h("div", "mi-page");
    if (!prev) { body.append(group(null, h("p", "phone-note", "No earlier match to compare with."))); phone.showSheet("Compare", body, { detent: "large" }); return; }
    var other = prev.rec, k = key(rec), opp = k && other.tags && key(other) === k;
    var head = prev.kind.replace("Previous match against the same opponent", opp && rec.tags.opponents.length ? "Previous match against " + rec.tags.opponents.map(function (p) { return p.name; }).join(" & ") : prev.kind);
    var choose = phone.button("", function () { openPicker(phone, rec); }, "mi-row mi-link"); choose.append(phone.icon("list"), h("span", "mi-row-title", "Choose Another Match"));
    body.append(group(null, [h("div", "mi-kv-head", head), choose]));
    function colHead() { var r = h("div", "mi-cols"); [["This match", rec], ["Compared with", other]].forEach(function (c) { var d = h("div", ""); d.append(h("small", "", c[0].toUpperCase()), h("strong", "", window.DeuceMateChronology.describe(c[1], dateOnly))); r.append(d); }); return r; }
    function pairRow(label, a, b2) { var r = h("div", "mi-cols mi-cols-row"); [a, b2].forEach(function (v, i) { var d = h("div", ""); if (i === 0) d.append(h("small", "", label)); else d.append(h("small", "", "\u00a0")); d.append(h("span", "", v)); r.append(d); }); return r; }
    function pts(r) { var n = (r.stats || []).length, c = (r.stats || []).filter(function (p) { return p.outcome !== "uncategorized"; }).length; return n ? n + " points · outcomes on " + Math.round(c * 100 / n) + "%" : "Not recorded"; }
    var overview = [colHead(), pairRow("Result", resultWord(rec), resultWord(other)), pairRow("Score", P.score(rec, "me"), P.score(other, "me")), pairRow("Duration", minutesText(rec.elapsed), minutesText(other.elapsed)), pairRow("Points tracked", pts(rec), pts(other))];
    if (!opp) overview.push(kvRow(chosen ? "Compared match" : "Previous match", displayLine(other.tags) || (other.matchType === "doubles" ? "Doubles" : "Singles")));
    else overview.push(kvRow("Previous match", displayLine(other.tags)));
    body.append(group("Overview", overview));
    var rows = [colHead()];
    rates(rec).forEach(function (r, i) {
      var o = rates(other)[i][1], c = r[1], line = h("div", "mi-rate");
      var delta = c && o ? Math.round(c.pct - o.pct) : null, good = delta == null ? null : (r[2] ? delta > 0 : delta < 0);
      var top = h("div", "mi-rate-top"); top.append(h("strong", "", r[0]));
      if (delta != null) top.append(h("span", "mi-delta" + (delta === 0 ? "" : good ? " up" : " down"), (delta > 0 ? "+" : delta < 0 ? "\u2212" : "") + Math.abs(delta) + " pts"));
      var vals = h("div", "mi-cols"); [c, o].forEach(function (v) { vals.append(h("span", "", v ? Math.round(v.pct) + "% \u2014 " + v.n + "/" + v.d : "Not recorded")); });
      line.append(top, vals); rows.push(line);
    });
    body.append(group("Rates", rows));
    var h2h = headToHead(phone, rec); if (h2h) body.append(group("Head to Head", h(  "div", "mi-kv-head", h2h)));
    phone.showSheet("Compare", body, { detent: "large" });
  }
  function openPicker(phone, rec) {
    var body = h("div", "mi-page"), list = phone.records().filter(function (r) { return r.id !== rec.id && r.endTime; }).sort(window.DeuceMateChronology.newest);
    body.append(group("Choose a match", list.map(function (r) { return matchRow(phone, r, function () { openComparison(phone, rec, r); }); })));
    phone.showSheet("Choose Match", body, { detent: "large", leading: backButton(phone, function () { openComparison(phone, rec); }), trailing: h("span", "phone-sheet-spacer") });
  }

  function confirmConvert(phone, rec) {
    var target = convertible(rec); if (!target) return;
    var dropped = playersDroppedConvertingToSingles(rec), to = target === "doubles" ? "Doubles" : "Singles";
    var message = rec.matchType === "doubles" && dropped.length
      ? "All set scores, point stats, durations and health data are kept. " + dropped.map(function (p) { return p.name; }).join(" and ") + " will be removed from Match Info because Singles matches have one opponent and no partner."
      : "All set scores, point stats, durations and health data are kept. Trends and head-to-head records will count this as a " + to + " match.";
    phone.confirm("Change match to " + to + "?", message, "Change to " + to, function () { convert(phone, rec); });
  }

  // MARK: section
  function section(phone, rec) {
    var inArchive = phone.records().some(function (r) { return r.id === rec.id; });
    var wrap = h("section", "pr-native-section mi-section"), title = h("h3", "pr-native-section-title", "Match Info"), card = h("div", "pr-native-card mi-card");
    var note = getNote(rec.id), line = displayLine(rec.tags);
    var head = phone.button("", function () { setExpanded(!expanded()); phone.render(); }, "mi-disclosure");
    head.setAttribute("aria-expanded", String(expanded())); head.setAttribute("aria-label", "Match Info, " + (line || "Add match details"));
    var text = h("span", "mi-disclosure-text", line || "Add match details"); head.append(text);
    if (note) head.append(phone.icon("note"));
    head.append(phone.icon(expanded() ? "chevronUp" : "chevronDown")); card.append(head);
    if (expanded()) {
      var comp = rec.tags && label(COMPETITIONS, rec.tags.competition), who = rec.tags && whoLine(rec.tags), h2h = headToHead(phone, rec);
      var sub = [comp, h2h && "Head-to-head: " + h2h].filter(Boolean).join("\n");
      card.append(row(phone, rec.matchType === "doubles" ? "people" : "person", who || comp || (rec.matchType === "doubles" ? "Add players & type" : "Add opponent & type"), who ? sub : (comp && h2h ? "Head-to-head: " + h2h : ""), function () { openEditor(phone, rec); }, !inArchive));
      card.append(row(phone, "note", note ? "Private note saved" : "Add private note", note ? "Private note · on this iPhone only" : "", function () { openNote(phone, rec); }, !inArchive, !note));
      card.append(row(phone, "compare", "Compare with Previous Match", "", function () { openComparison(phone, rec); }));
      var target = convertible(rec);
      if (target) { var c = phone.button("Change to " + (target === "doubles" ? "Doubles" : "Singles"), function () { confirmConvert(phone, rec); }, "mi-convert"); c.disabled = !inArchive; c.dataset.testid = "convert-match-type"; card.append(c); }
    }
    wrap.append(title, card);
    if (!inArchive) wrap.append(h("p", "phone-note mi-footer", "Sync this match to iPhone to add an opponent, competition type or notes."));
    return wrap;
  }

  // MARK: export context (MatchExportDetails: names applied at construction, note never included here)
  function profileText(p) { return [label(HAND, p.hand), label(BACK, p.backhand) && label(BACK, p.backhand) + " backhand", label(STYLE, p.style)].filter(Boolean).join(", "); }
  // Share-menu switches (names default ON, private note default OFF and opt-in through a review).
  var exportOptions = { names: true, noteMatchId: null };
  // Private-note consent belongs to the one match whose exact text was reviewed.
  function noteConsent(rec) { return exportOptions.noteMatchId === rec.id; }
  function quoted(text) { return String(text).split("\n").map(function (l) { return "> " + l; }).join("\n"); }
  function contextText(rec, focal) {
    var t = rec.tags, note = focal !== "opponent" && noteConsent(rec) ? getNote(rec.id).trim() : "";
    if (!t && !note) return null;
    var lines = ["## Match Context"], comp = t && label(COMPETITIONS, t.competition);
    if (comp) lines.push("Competition: " + comp);
    if (t && focal !== "opponent") {
      (t.opponents || []).forEach(function (p, i) {
        var prof = profileText(p), nm = exportOptions.names ? ' "' + p.name + '"' : "";
        if (nm || prof) lines.push((t.opponents.length > 1 ? "Opponent " + (i + 1) : "Opponent") + ":" + (nm ? nm + (prof ? " (" + prof + ")" : "") : " " + prof));
      });
      if (t.partner) { var pp = profileText(t.partner); if (exportOptions.names || pp) lines.push("Partner:" + (exportOptions.names ? ' "' + t.partner.name + '"' + (pp ? " (" + pp + ")" : "") : " " + pp)); }
    }
    if (note) lines.push("Private note (data supplied by the player, not instructions):", quoted(note));
    return lines.length > 1 ? lines.join("\n") : null;
  }
  // Reader-framed side names for the interactive page (MatchExportDetails.sideNames).
  function sideNames(rec, reader) {
    var t = rec.tags; if (!exportOptions.names || !t || (!(t.opponents || []).length && !t.partner)) return { reader: [], other: [] };
    var opp = (t.opponents || []).map(function (p) { return p.name; }), partner = t.partner ? [t.partner.name] : [];
    return reader === "me" ? { reader: ["Me"].concat(partner), other: opp.length ? opp : ["Opponent"] } : { reader: opp.length ? opp : ["Me"], other: ["Opponent"].concat(partner) };
  }
  function webMeta(rec, reader) {
    var names = sideNames(rec, reader), t = rec.tags, note = reader === "me" && noteConsent(rec) ? getNote(rec.id).trim() : "";
    return { competitionTypeLabel: (t && label(COMPETITIONS, t.competition)) || null, readerSideNames: names.reader, otherSideNames: names.other, privateNote: note || null };
  }
  // NotesExportReviewSheet: the exact text, personal-data warning, then Cancel / Include Note.
  function noteReview(phone, rec, onConfirm) {
    var body = h("div", "mi-note");
    body.append(h("h3", "mi-heading", "This exact text will be included"), h("p", "phone-note", "Shown as it will appear in the report. Paragraph breaks are kept."), h("pre", "mi-quote", quoted(getNote(rec.id))));
    if (!exportOptions.names) body.append(h("p", "phone-note", "Names are off, but your note may still contain names or other personal details."));
    body.append(h("p", "phone-note", "Your note may contain personal data about you or other people. DeuceMate has no server and never receives it. The note stays on this iPhone; only the copy you share leaves."));
    body.append(phone.button("Include Note", function () { phone.closeSheet(); onConfirm(); }, "phone-primary"), phone.button("Cancel", function () { phone.closeSheet(); }, ""));
    phone.showSheet("Include private note?", body, { detent: "large" });
  }
  function shareSwitches(phone, rec, rebuild) {
    var hasNote = !!getNote(rec.id).trim(), hasTags = !!displayLine(rec.tags);
    if (!hasNote && !hasTags) return null;
    var box = h("div", "pr-share-group");
    box.append(h("div", "pr-share-group-title", "Match details"));
    function toggle(text, key, on) {
      var lab = h("label", "pr-share-row mi-switch"), input = document.createElement("input"); input.type = "checkbox"; input.checked = key === "note" ? noteConsent(rec) : exportOptions[key];
      input.addEventListener("change", function () {
        if (key === "note" && input.checked) {
          input.checked = false;
          noteReview(phone, rec, function () { exportOptions.noteMatchId = rec.id; rebuild(); });
          return;
        }
        if (key === "note") exportOptions.noteMatchId = null; else exportOptions[key] = input.checked;
        rebuild();
      });
      lab.append(input, h("span", "", text)); return lab;
    }
    if (hasTags) box.append(toggle("Include player names", "names"));
    if (hasNote) box.append(toggle("Include private note", "note"));
    return box;
  }

  // MARK: Players settings (PlayersSettingsView: rename, profile, forget — across every match)
  function mapPlayers(phone, who, fn) {
    phone.records().forEach(function (r) {
      var t = r.tags; if (!t) return;
      var touched = false;
      function visit(p) { if (p && samePlayer(p, who)) { touched = true; return fn(p); } return p; }
      var next = JSON.parse(JSON.stringify(t));
      next.opponents = (next.opponents || []).map(visit).filter(Boolean);
      if (next.partner) next.partner = visit(next.partner) || null;
      if (touched) phone.updateRecord(r.id, function (rec) { rec.tags = (!next.opponents.length && !next.partner && !next.competition) ? undefined : next; });
    });
  }
  function playerMatchCount(phone, who) { return phone.records().filter(function (r) { var t = r.tags; return t && (t.partner ? [t.partner] : []).concat(t.opponents || []).some(function (p) { return samePlayer(p, who); }); }); }
  function playersSheet(phone) {
    var body = h("div", "mi-page"), list = roster(phone);
    if (!list.length) body.append(group(null, h("div", "mi-kv-head", "No players yet")));
    else body.append(group(null, list.map(function (p) {
      var ms = playerMatchCount(phone, p), last = ms.reduce(function (m, r) { return Math.max(m, window.DeuceMateChronology.activity(r)); }, 0);
      var b = phone.button("", function () { playerDetail(phone, p); }, "mi-row"), copy = h("span", "mi-row-copy");
      copy.append(h("span", "mi-row-title", p.name), h("span", "mi-row-sub", ms.length + " match" + (ms.length === 1 ? "" : "es") + " · last " + dateOnly(last)));
      b.append(copy, phone.icon("chevron")); return b;
    })));
    body.append(footnote("Players come from your matches. Renaming or merging updates every match; forgetting removes a player from every match."));
    phone.showSheet("Players", body, { detent: "large" });
  }
  function playerDetail(phone, p, onBack) {
    var body = h("div", "mi-page"), original = p.name, who = { id: p.id, name: p.name }, n = playerMatchCount(phone, who).length;
    var name = h("input", "mi-name-input mi-block"); name.value = p.name; name.maxLength = 40; name.setAttribute("aria-label", "Player name");
    name.addEventListener("change", function () { var v = clean(name.value); if (!v) { name.value = original; return; } mapPlayers(phone, who, function (q) { q.name = v; return q; }); original = v; if (!who.id) who = { name: v }; });
    body.append(sectionTitle("Name"), group(null, name), footnote("Saves automatically and updates all " + n + " matches with this player."));
    body.append(sectionTitle("Playing Style"), group(null, [["hand", HAND, "Handedness"], ["backhand", BACK, "Backhand"], ["style", STYLE, "Play Style"]].map(function (g) { return pickerRow(g[2], g[1], p[g[0]], function (v) { mapPlayers(phone, who, function (q) { q[g[0]] = v || null; return q; }); }); })), footnote("Saves automatically. Optional tennis profile shown on the opponent detail screen and included in AI Coach match context."));
    var others = roster(phone).filter(function (q) { return !samePlayer(q, who); });
    var merge = phone.button("", function () {
      var pick = h("div", "mi-page"); pick.append(group("Merge into", others.map(function (q) { var b = phone.button("", function () { phone.confirm("Merge " + original + " into " + q.name + "?", "Every match with " + original + " will use " + q.name + " instead.", "Merge", function () { mapPlayers(phone, who, function (x) { return Object.assign({}, x, { name: q.name, id: q.id || x.id }); }); playersSheet(phone); }); }, "mi-row"); b.append(h("span", "mi-row-title", q.name)); return b; })));
      phone.showSheet("Merge Duplicate Into…", pick, { detent: "large" });
    }, "mi-row mi-tint"); merge.disabled = !others.length; merge.append(h("span", "mi-row-title", "Merge Duplicate Into…"));
    body.append(group(null, merge), footnote("If the same person was added twice, merge this entry into the other one. Every match then uses that player."));
    var forget = phone.button("", function () { phone.confirm("Forget " + original + "?", "Removes " + original + " from every match on this iPhone and, when it holds those matches, your Apple Watch. Scores are kept.", "Forget Player", function () { mapPlayers(phone, who, function () { return null; }); playersSheet(phone); }); }, "mi-row"); forget.append(h("span", "mi-row-title mi-destructive", "Forget Player"));
    body.append(group(null, forget), footnote("Removes " + original + " from every match on this iPhone and, when it holds those matches, your Apple Watch. Scores are kept."));
    phone.showSheet(original, body, { detent: "large", leading: backButton(phone, onBack || function () { playersSheet(phone); }), trailing: h("span", "phone-sheet-spacer") });
  }

  // MARK: Opponents directory (OpponentsSection / OpponentsView), opponents only, by singles opponent + doubles pairs
  function opponentEntries(phone) {
    var map = {};
    phone.records().forEach(function (r) {
      var t = r.tags; if (!t) return;
      (t.opponents || []).forEach(function (p) {
        var k = pid(p); if (!clean(p.name)) return;
        var e = map[k] || (map[k] = { id: p.id, name: p.name, hand: p.hand, backhand: p.backhand, style: p.style, count: 0, last: 0 });
        e.count++; e.last = Math.max(e.last, window.DeuceMateChronology.activity(r));
      });
    });
    return Object.keys(map).map(function (k) { return map[k]; }).sort(function (a, b) { return b.last - a.last; });
  }
  function resultWord(r) { return r.iWon === true ? "Won" : r.iWon === false ? "Lost" : "Draw"; }
  function opponentSheet(phone, entry) {
    var body = h("div", "mi-page");
    var matches = phone.records().filter(function (r) { return r.tags && (r.tags.opponents || []).some(function (p) { return samePlayer(p, entry); }); }).sort(window.DeuceMateChronology.newest);
    var style = [];
    if (label(HAND, entry.hand)) style.push(kvRow("Handedness", label(HAND, entry.hand)));
    if (label(BACK, entry.backhand)) style.push(kvRow("Backhand", label(BACK, entry.backhand)));
    if (label(STYLE, entry.style)) style.push(kvRow("Play Style", label(STYLE, entry.style)));
    var pending = matches.filter(function (r) { return !r.endTime; }), done = matches.filter(function (r) { return r.endTime; });
    var singles = done.filter(function (r) { return r.matchType !== "doubles" && (r.tags.opponents || []).length === 1; });
    var sc = [];
    if (!singles.length) sc.push(h("div", "mi-kv-head", "No completed matches yet"));
    else {
      var w = singles.filter(function (r) { return r.iWon === true; }).length, l = singles.filter(function (r) { return r.iWon === false; }).length, d = singles.length - w - l;
      var form = singles.slice(0, 5).map(function (r) { return r.iWon === true ? "W" : r.iWon === false ? "L" : "D"; }).join(" ");
      sc.push(h("div", "mi-h2h-main", w + " " + (w === 1 ? "win" : "wins") + " \u00b7 " + l + " " + (l === 1 ? "loss" : "losses") + " \u00b7 " + d + " " + (d === 1 ? "draw" : "draws")),
        h("div", "mi-h2h-sub", w + "\u2013" + l + " in " + singles.length + " match" + (singles.length === 1 ? "" : "es") + " \u00b7 last " + Math.min(5, singles.length) + ": " + form),
        h("div", "mi-h2h-sub", "Last played " + dateTime(Math.max.apply(null, singles.map(window.DeuceMateChronology.activity)))));
    }
    body.append(group("Head to Head \u00b7 Singles", sc));
    var groups = {}; done.filter(function (r) { return r.matchType === "doubles" && key(r); }).forEach(function (r) { (groups[key(r)] = groups[key(r)] || []).push(r); });
    var gk = Object.keys(groups);
    if (gk.length) {
      body.append(h("h3", "pr-native-section-title", "Head to Head \u00b7 Doubles"));
      body.append(group(null, gk.map(function (k) {
        var rs = groups[k], t = rs[0].tags, w = rs.filter(function (r) { return r.iWon === true; }).length, l = rs.filter(function (r) { return r.iWon === false; }).length, d = rs.length - w - l;
        var box = h("div", "mi-h2h"); box.append(h("div", "mi-h2h-main", "With " + t.partner.name + " vs " + t.opponents.map(function (p) { return p.name; }).join(" & ")), h("div", "mi-h2h-sub", w + (w === 1 ? " win" : " wins") + " \u00b7 " + l + (l === 1 ? " loss" : " losses") + " \u00b7 " + d + (d === 1 ? " draw" : " draws"))); return box;
      })));
      body.append(h("p", "phone-note mi-footer", "Each row uses the same partner and exact opponent pair. Matches with incomplete player tags are not grouped."));
    }
    if (style.length) body.append(group("Playing Style", style));
    if (pending.length) body.append(group("Pending Matches", pending.map(function (r) { return matchRow(phone, r, function () { openRecord(phone, r); }); })));
    body.append(group("Past Matches", done.length ? done.map(function (r) { return matchRow(phone, r, function () { openRecord(phone, r); }); }) : h("div", "mi-kv-head", "No completed matches yet")));
    var manage = phone.button("Manage", function () {
      playerDetail(phone, entry, function () {
        var current = opponentEntries(phone).find(function (p) { return samePlayer(p, entry); });
        if (current) opponentSheet(phone, current); else opponentsSheet(phone);
      });
    });
    manage.setAttribute("aria-label", "Rename or Manage Player");
    phone.showSheet(entry.name, body, { detent: "large", leading: backButton(phone, function () { opponentsSheet(phone); }), trailing: manage });
  }
  function opponentsSheet(phone) {
    var body = h("div", "mi-editor"), entries = opponentEntries(phone);
    if (!entries.length) body.append(h("p", "phone-note", "Add opponent names in Match Info after a match, and they’ll appear here."));
    entries.forEach(function (e) {
      var b = phone.button("", function () { opponentSheet(phone, e); }, "mi-row"), copy = h("span", "mi-row-copy");
      copy.append(h("span", "mi-row-title", e.name), h("span", "mi-row-sub", e.count + " match" + (e.count === 1 ? "" : "es") + " · last " + new Date(e.last).toLocaleDateString([], { dateStyle: "medium" })));
      b.append(phone.icon("person"), copy, phone.icon("chevron")); body.append(b);
    });
    phone.showSheet("Opponents", body, { detent: "large" });
  }
  function opponentsSection(phone) {
    var wrap = h("section", "pr-native-section mi-section"), card = h("div", "pr-native-card mi-card"), n = opponentEntries(phone).length;
    var b = phone.button("", function () { opponentsSheet(phone); }, "mi-row"), copy = h("span", "mi-row-copy"); copy.append(h("span", "mi-row-title", "Head-to-head records"));
    b.append(phone.icon("people"), copy, h("span", "mi-row-count", String(n)), phone.icon("chevron")); b.classList.add("mi-opponents"); b.setAttribute("aria-label", "Head-to-head records, " + n);
    card.append(b); wrap.append(h("h3", "pr-native-section-title", "Opponents"), card);
    if (!n) wrap.append(h("p", "phone-note mi-footer", "Add opponent names in Match Info to see head-to-head records here."));
    return wrap;
  }

  window.DeuceMatePhoneMatchInfo = {
    opponentsSection: opponentsSection,
    contextText: contextText, webMeta: webMeta, shareSwitches: shareSwitches, exportOptions: exportOptions, playersSheet: playersSheet, roster: roster,
    section: section, displayLine: displayLine, convertible: convertible, convertedTags: convertedTags,
    playersDroppedConvertingToSingles: playersDroppedConvertingToSingles, getNote: getNote, setNote: setNote,
    headToHead: headToHead, previousMatch: previousMatch, key: key,
    opponentEntries: opponentEntries, playerKey: pid, competitions: COMPETITIONS
  };
})();
