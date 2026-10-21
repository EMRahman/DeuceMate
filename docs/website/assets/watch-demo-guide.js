/* ==========================================================================
   DeuceMate — the animated guide for the browser watch replica.

   Ports WalkthroughSession.swift / WalkthroughFixtures.swift (nine scripted
   situations, run on the real scoring engine) and WalkthroughView.swift (the
   scoreboard replica, tap-to-play commentary, gesture / double-tap overlays,
   category and live-stats previews, changeover card). Like the watch, it never
   touches the real match, settings or history. Heart rate and calories on its
   screens are the scripted demo values the watch uses too.
   ========================================================================== */
(function () {
  "use strict";
  var S = window.DeuceMateShell;
  if (!S) return;
  var h = S.h, icon = S.icon, api = S.api;
  var Scoring = window.DeuceMateScoring, T = window.DeuceMateTracking, UI = window.DeuceMateStatsUI, W = window.DeuceMateWatchUI;
  var reduceMotion = !!(window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches);

  /* ---- Fixtures ------------------------------------------------------------------ */
  var STEPS = [
    null,
    { key: "winPoint", intro: "Swipe up when you win a point", say: "Swipe up when you win a point." },
    { key: "losePoint", intro: "Swipe down when you lose a point", say: "Swipe down when you lose a point." },
    { key: "undoPoint", intro: "Swipe left to undo the last point", say: "Made a mistake? Swipe left to undo the last point." },
    { key: "unforcedError", intro: "If point tracking enabled; record your loss for an unforced error during a rally.", say: "" },
    { key: "secondServe", intro: "If point tracking enabled; double tap to record a second serve", say: "" },
    { key: "doubleFault", intro: "If point tracking enabled; double fault can be logged.", say: "" },
    { key: "findStat", intro: "If point tracking enabled; swipe right to open Live Stats", say: "" },
    { key: "winGame", intro: "40–0 at 1–0. One point wins the game", say: "" },
    { key: "oddSet", intro: "40–0 at 5–3. One point wins the set. Notice the sticky reminder until the next point", say: "" }
  ];
  var COUNT = 9;
  var METRICS = { 1: [128, 18, 492], 2: [131, 19, 514], 3: [132, 20, 529], 4: [135, 21, 546], 5: [136, 22, 560], 6: [137, 23, 574], 7: [138, 24, 587], 8: [143, 68, 1902], 9: [151, 192, 5285] };
  var RECENT = { 1: [], 2: ["me"], 3: ["me", "opponent"], 4: [], 5: ["opponent"], 6: ["opponent"], 7: ["opponent", "opponent"], 8: ["opponent", "me", "me", "me"], 9: ["opponent", "me", "me", "me"] };

  function fixtureState(step) {
    var st = Scoring.freshState("standard", "me");
    switch (step) {
      case 2: st.currentPointsMe = 1; break;
      case 3: st.currentPointsMe = 1; st.currentPointsOpponent = 1; break;
      case 5: case 6: st.currentPointsOpponent = 1; break;
      case 7: st.currentPointsOpponent = 2; break;
      case 8: st.sets[0].gamesMe = 1; st.currentPointsMe = 3; st.gameCount = 1; break;
      case 9: st.sets[0].gamesMe = 5; st.sets[0].gamesOpponent = 3; st.currentPointsMe = 3; st.gameCount = 8; break;
    }
    return st;
  }
  var ERROR_POINT = { setIndex: 0, server: "me", winner: "opponent", outcome: "unforcedError", isSecondServe: false, isBreakPoint: false, endingShot: "rally", gameScoreAtStart: { server: 0, returner: 0, isTiebreak: false } };
  var DF_POINT = { setIndex: 0, server: "me", winner: "opponent", outcome: "doubleFault", isSecondServe: true, isBreakPoint: false, endingShot: "serve", gameScoreAtStart: { server: 0, returner: 1, isTiebreak: false } };

  /* ---- WalkthroughSession ----------------------------------------------------------- */
  var gens = 0;
  function Session(step) {
    this.step = step;
    this.state = fixtureState(step);
    this.points = step === 5 || step === 6 ? [ERROR_POINT] : step === 7 ? [ERROR_POINT, DF_POINT] : [];
    this.recent = RECENT[step].slice();
    this.pending = null; this.changeover = null; this.phase = "situation";
    this.isOnSecondServe = step === 6;
    this.generation = ++gens;
  }
  var P = Session.prototype;
  P.reminder = function () { return Scoring.nextSetRequiresEndsSwitch(this.state); };
  P.isDeuceSide = function () { return (this.state.currentPointsMe + this.state.currentPointsOpponent) % 2 === 0; };
  P.finished = function () { return this.phase === "result" || this.phase === "stats" || this.phase === "done"; };
  P.gesture = function () {
    if (this.phase === "nextSetGesture") return "win";
    switch (this.step) {
      case 1: case 8: case 9: return "win";
      case 2: case 4: case 6: return "lose";
      case 5: return "lose";
      case 3: return "undo";
      case 7: return "stats";
    }
    return "win";
  };
  P.pointLabel = function (p) { return p === 0 ? "0" : p === 1 ? "15" : p === 2 ? "30" : "40"; };
  P.scoreDescription = function () {
    var st = this.state;
    return "Games " + st.sets.map(function (s) { return s.gamesMe + "–" + s.gamesOpponent; }).join(", ") + ". Points " +
      this.pointLabel(st.currentPointsMe) + "–" + this.pointLabel(st.currentPointsOpponent) + ". Next: " + (st.currentServer === "me" ? "Me" : "Opp") + " serves" + (this.isOnSecondServe ? ", on a second serve" : "") + ".";
  };
  P.feedback = function () {
    switch (this.phase) {
      case "situation": return STEPS[this.step].say || STEPS[this.step].intro;
      case "secondServeTap": return "Double tap the score to mark the second serve.";
      case "gesture": return { win: "Showing swipe up.", lose: "Showing swipe down.", undo: "Showing swipe left to undo.", stats: "Showing swipe right for live stats." }[this.gesture()];
      case "outcome": return this.step === 6 ? "Double Fault is selected for your second serve." : "Unforced Error is selected for you, the losing player.";
      case "endingShot": return "Rally is selected for the shot you hit out.";
      case "stats": return "Live Stats. Unforced Errors: Me 1, Opp 0. Double Faults: Me 1, Opp 0.";
      case "changeover": return this.changeover ? Scoring.changeoverReasonText(this.changeover) : "";
      case "postChangeoverScore": return this.scoreDescription();
      case "reminder": return "OK closes the message. The reminder stays until the first point of the new set.";
      case "nextSetGesture": return "An upward swipe scores the first point of set two. Watch the reminder clear.";
      case "done": return "Ready to play. Enable Track point outcome in Settings to collect error stats.";
      case "result":
        return [null, "15–0. You still serve, now from left/ad. The ball marks who serves next.",
          "15–15. You still serve, now from right/deuce. Swipes award points regardless of who served.",
          "Back to 15–0 and left/ad. Undo restores score, server and tracked stats together.",
          "0–15. One rally unforced error recorded for Me. Your real tracking settings haven’t changed.",
          "Second serve marked. The score remains 0–15.", "0–30. One double fault recorded for Me.",
          "Unforced Errors and Double Faults: Me 1, Opp 0 each.",
          "Games 2–0; points 0–0. Opp serves next. Players stay; get the balls to Opp.",
          "6–3: nine games, so players change ends. Opp serves set two. Its first point clears the sticky reminder."][this.step];
    }
    return "";
  };
  P.beginExample = function () { if (this.phase === "situation") this.phase = this.step === 5 ? "secondServeTap" : "gesture"; };
  P.score = function (winner) {
    if (this.step === 4 || this.step === 6) {
      this.pending = { server: this.state.currentServer || "me", winner: winner, setIndex: this.state.sets.length - 1, isSecondServe: this.isOnSecondServe,
        isBreakPoint: Scoring.isBreakPoint(this.state), gameScoreAtStart: T.gameScoreSnapshot(this.state) };
    }
    var res = Scoring.pointWon(this.state, winner);
    this.state = res.state;
    this.isOnSecondServe = false;
    this.recent.push(winner); this.recent = this.recent.slice(-8);
    this.changeover = null;
    for (var i = 0; i < res.events.length; i++) if (res.events[i].t === "changeover") { this.changeover = res.events[i]; break; }
  };
  P.advance = function () {
    switch (this.phase) {
      case "secondServeTap": this.isOnSecondServe = true; this.phase = "result"; break;
      case "gesture": {
        var g = this.gesture();
        if (g === "stats") this.phase = "stats";
        else if (g === "undo") { this.state = fixtureState(2); this.recent.pop(); this.phase = "result"; }
        else { this.score(g === "win" ? "me" : "opponent"); this.phase = (this.step === 4 || this.step === 6) ? "outcome" : (this.changeover ? "changeover" : "result"); }
        break;
      }
      case "outcome":
        if (this.step === 6 && this.pending) {
          this.points = this.points.concat([{ setIndex: this.pending.setIndex, server: this.pending.server, winner: this.pending.winner, outcome: "doubleFault",
            isSecondServe: this.pending.isSecondServe, isBreakPoint: this.pending.isBreakPoint, endingShot: "serve", gameScoreAtStart: this.pending.gameScoreAtStart }]);
          this.pending = null; this.phase = "result";
        } else this.phase = "endingShot";
        break;
      case "endingShot":
        if (!this.pending) return;
        this.points = [{ setIndex: this.pending.setIndex, server: this.pending.server, winner: this.pending.winner, outcome: "unforcedError",
          isSecondServe: false, isBreakPoint: this.pending.isBreakPoint, endingShot: "rally", gameScoreAtStart: this.pending.gameScoreAtStart }];
        this.pending = null; this.phase = "result";
        break;
      case "changeover": this.changeover = null; this.phase = this.step === 9 ? "postChangeoverScore" : "result"; break;
      case "postChangeoverScore": this.phase = "reminder"; break;
      case "reminder": this.phase = "nextSetGesture"; break;
      case "nextSetGesture": this.score("me"); this.phase = "result"; break;
    }
  };

  /* ---- View ------------------------------------------------------------------------------ */
  var run = null;   // the live guide: {session, timers, host}
  function clearTimers() { if (run) { run.timers.forEach(clearTimeout); run.timers = []; } }
  function later(fn, ms) { var id = setTimeout(fn, ms); run.timers.push(id); return id; }

  function beatMs(phase) {
    switch (phase) {
      case "secondServeTap": case "gesture": case "nextSetGesture": return reduceMotion ? 1800 : 1200;
      case "outcome": case "endingShot": return 2000;
      case "changeover": return 3000;
      case "reminder": return 1000;
      default: return 1000;
    }
  }

  function courtEl(deuce, server) {
    var court = h("div", { class: "w-court", "data-server": server || "none", "aria-hidden": "true" });
    var onLeft = !server ? false : (server === "me" ? !deuce : deuce);
    [["opponent", 0], ["me", 1]].forEach(function (p, idx) {
      if (idx === 1) court.appendChild(h("div", { class: "cs-line" }));
      var isServer = server === p[0], isRecv = !isServer && !!server, left = isServer ? onLeft : !onLeft;
      var dot = h("span", { class: "cs-dot" + (isServer ? " server" : isRecv ? " receiver" : "") });
      dot.style.left = left ? "calc(7 * var(--pt))" : "calc(33 * var(--pt))";
      court.appendChild(h("div", { class: "cs-row" }, dot));
    });
    return court;
  }
  function hrEl(bpm) {
    var band = bpm >= 170 ? "max" : bpm >= 150 ? "high" : bpm >= 120 ? "mod" : "low";
    return h("div", { class: "w-hr band-" + band, "aria-label": "Demo heart rate: " + bpm + " beats per minute" },
      h("span", { class: "hr-heart", text: "❤️" }), h("span", { class: "hr-val", text: String(bpm) }), h("span", { class: "hr-unit", text: "BPM" }));
  }
  function fmtDur(secs) {
    var m = Math.floor(secs / 60), s = secs % 60, hh = Math.floor(m / 60), rm = m % 60;
    return hh > 0 ? hh + " h " + rm + " m " + s + " s" : m + " m " + s + " s";
  }

  function scoreboard(session) {
    var st = session.state, card = h("div", { class: "w-card", role: "img", "aria-label": session.scoreDescription() });
    ["me", "opponent"].forEach(function (p) {
      var row = h("div", { class: "w-row " + (p === "me" ? "me" : "opp") });
      var srv = h("span", { class: "w-server idle" });
      W.setServerIcon(srv, st.currentServer === p, st.currentServer === p && session.isOnSecondServe, null);
      var cells = h("span", { class: "w-cells" }); W.buildCells(cells, st, p);
      row.appendChild(srv); row.appendChild(h("span", { class: "w-name", text: p === "me" ? "Me" : "Op" })); row.appendChild(cells);
      row.appendChild(h("span", { class: "w-pts", text: session.pointLabel(p === "me" ? st.currentPointsMe : st.currentPointsOpponent) }));
      card.appendChild(row);
    });
    return card;
  }

  function momentum(session) {
    var rem = session.reminder();
    if (rem !== null) return h("div", { class: "w-reminder " + (rem ? "players" : "balls"), text: rem ? "🔁 👥  Players change ends" : "🔁 🎾  Balls change ends" });
    var m = h("div", { class: "w-momentum", "aria-hidden": "true" });
    for (var i = 0; i < 8; i++) {
      var idx = session.recent.length - 8 + i, pip = h("span", { class: "w-pip" });
      if (idx >= 0) pip.classList.add(session.recent[idx] === "me" ? "me" : "opp");
      m.appendChild(pip);
    }
    return m;
  }

  function gestureOverlay(action) {
    var v = { win: [0, -46], lose: [0, 46], undo: [-72, 0], stats: [72, 0] }[action];
    var arrow = { win: "↑", lose: "↓", undo: "←", stats: "→" }[action];
    var wrap = h("div", { class: "wt-gesture", "aria-hidden": "true" });
    var cx = 50, cy = 50;   // percent of the scoreboard card
    var trail = h("div", { class: "wt-trail" });
    var horizontal = v[0] !== 0;
    trail.style.cssText = horizontal ? "left:calc(50% - " + Math.abs(v[0]) / 2 + "px);top:calc(50% - 1.5px);width:" + Math.abs(v[0]) + "px;height:3px;background-image:linear-gradient(90deg,currentColor 50%,transparent 50%);background-size:8px 3px;"
      : "left:calc(50% - 1.5px);top:calc(50% - " + Math.abs(v[1]) / 2 + "px);width:3px;height:" + Math.abs(v[1]) + "px;background-image:linear-gradient(180deg,currentColor 50%,transparent 50%);background-size:3px 8px;";
    wrap.appendChild(trail);
    if (reduceMotion) {
      wrap.appendChild(h("div", { class: "wt-hand", style: "left:50%;top:50%;font-weight:800;font-family:system-ui", text: arrow }));
    } else {
      var hand = h("div", { class: "wt-hand", text: "👆" });
      hand.style.left = "calc(50% + " + (-v[0] / 2) + "px)"; hand.style.top = "calc(50% + " + (-v[1] / 2) + "px)";
      wrap.appendChild(hand);
      requestAnimationFrame(function () { requestAnimationFrame(function () {
        hand.style.left = "calc(50% + " + (v[0] / 2) + "px)"; hand.style.top = "calc(50% + " + (v[1] / 2) + "px)";
      }); });
    }
    return wrap;
  }
  function doubleTapOverlay() {
    return h("div", { class: "wt-gesture", "aria-hidden": "true", style: "display:flex;align-items:center;justify-content:center" },
      h("div", { class: "wt-dbl" }, h("span", { class: "hand", text: "👆" }), h("span", { text: "×2" })));
  }

  function tile(label, chosen, cap, marker) {
    var t = h("div", { class: "wt-tile" + (chosen ? " chosen" : "") + (cap ? " cap" : "") }, label);
    if (chosen && marker) t.appendChild(h("span", { class: "mk", text: reduceMotion ? "✓" : "👆" }));
    return t;
  }
  function categoryPreview(session, chosen) {
    var outcome = session.phase === "outcome", df = session.step === 6;
    var box = h("div", { class: "wt-preview" });
    var title = h("div", { class: "ptitle" }, h("span", { text: outcome ? "Lost — Your serve" : "Shot of the error?" }));
    if (df && outcome) title.appendChild(h("span", { class: "badge2", text: "2nd" }));
    box.appendChild(title);
    if (outcome) {
      if (df) {
        box.appendChild(h("div", { class: "wt-tiles" }, tile("Double Fault", chosen, false, true), tile("Unforced Error", false)));
        box.appendChild(h("div", { class: "wt-tiles" }, tile("Forced Error", false), tile("Winner", false)));
      } else {
        box.appendChild(h("div", { class: "wt-tiles" }, tile("Unforced Error", chosen, false, true), tile("Forced Error", false)));
        box.appendChild(h("div", { class: "wt-tiles" }, tile("Winner", false)));
      }
    } else box.appendChild(h("div", { class: "wt-tiles" }, tile("S+1", false), tile("Rally", chosen, false, true)));
    return box;
  }
  function statsPreview(session) {
    var body = h("div", { class: "stats-body" });
    UI.content(body, session.points, "singles");
    var scroll = h("div", { class: "scroll" }, body);
    var box = h("div", { class: "wt-stats" }, h("div", { class: "ptitle", text: "Live Stats" }), scroll);
    later(function () {
      var target = null;
      body.querySelectorAll(".cmp-label").forEach(function (l) { if (l.textContent === "Unforced Errors") target = l.closest(".cmp-row"); });
      if (!target) return;
      var to = Math.max(0, target.offsetTop - 2);
      if (reduceMotion) { scroll.scrollTop = to; return; }
      var from = scroll.scrollTop, t0 = performance.now();
      (function stepFn(now) {
        var k = Math.min(1, (now - t0) / 800), e = k < .5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2;
        scroll.scrollTop = from + (to - from) * e;
        if (k < 1 && run) requestAnimationFrame(stepFn);
      })(t0);
    }, 500);
    return box;
  }
  function changeoverOverlay(session, chosen) {
    var co = session.changeover;
    return h("div", { class: "wt-co" }, h("div", { class: "wt-co-card" },
      co ? h("div", { class: "sym", text: co.symbol }) : null,
      co ? h("div", { class: "rsn", text: Scoring.changeoverReasonText(co) }) : null,
      tile("OK", chosen, true, true)));
  }

  /* One render of the guide for the current session phase. */
  function paint() {
    if (!run) return;
    var session = run.session, host = run.host;
    host.innerHTML = "";
    if (session.phase === "done") {
      host.appendChild(h("div", { class: "wt-done" }, h("div", { class: "ok" }, icon("check", 28)), h("div", { text: "Ready to play" })));
      return;
    }
    var m = METRICS[session.step];
    var body = h("div", { class: "wt-body" });
    var board = scoreboard(session);
    board.style.position = "relative";
    if (session.phase === "secondServeTap") board.appendChild(doubleTapOverlay());
    else if (session.phase === "gesture" || session.phase === "nextSetGesture") board.appendChild(gestureOverlay(session.gesture()));
    body.appendChild(board);
    var mom = momentum(session); body.appendChild(mom);
    body.appendChild(h("div", { class: "w-info" }, courtEl(session.isDeuceSide(), session.state.currentServer), hrEl(m[0])));
    var foot = h("div", { class: "w-foot", "aria-label": "Demo calories: " + m[1] + " kilocalories. Elapsed time: " + fmtDur(run.elapsed) }, "🔥 " + m[1] + " kcal · 🕐 " + fmtDur(run.elapsed));
    foot.setAttribute("data-wt-foot", ""); body.appendChild(foot);
    host.appendChild(body);

    var demo = null;
    if (session.phase === "outcome" || session.phase === "endingShot") demo = categoryPreview(session, run.selected);
    else if (session.phase === "stats") demo = statsPreview(session);
    if (demo) host.appendChild(h("div", { class: "wt-overlay" }, demo));
    if (session.phase === "changeover") host.appendChild(changeoverOverlay(session, run.selected));

    if (session.phase === "situation") {
      host.appendChild(h("div", { class: "wt-dim" }));
      host.appendChild(h("button", { type: "button", class: "wt-intro", "aria-label": STEPS[session.step].intro + " Play example.", onclick: beginExample },
        h("div", { class: "wt-intro-card" }, h("div", { class: "tx", text: STEPS[session.step].intro }), h("div", { class: "go", text: "▶ Tap to play" }))));
    }
    host.appendChild(h("div", { class: "wt-header" },
      h("button", { type: "button", "aria-label": "Close guide", onclick: close }, icon("close", 15)),
      h("span", { class: "demo", text: "DEMO" }), h("span", { text: session.step + "/" + COUNT })));
    host.appendChild(h("div", { class: "sr-only", "aria-live": "polite", style: "position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0)", text: run.announce || "" }));
  }

  function selectAnimation() {
    later(function () { if (!run) return; run.selected = true; paint(); }, 650);
  }

  /* The presenter: beats run until the demonstration finishes, then the result
     is held and the guide moves itself to the next situation. */
  function schedule() {
    if (!run) return;
    var gen = run.session.generation, session = run.session, phase = session.phase;
    run.announce = session.feedback();
    if (phase === "situation") { paint(); return; }
    if (phase === "result" || phase === "stats" || phase === "done") {
      var delay = phase === "result" ? (reduceMotion ? 0 : 250) : phase === "stats" ? (reduceMotion ? 550 : 1300) : 0;
      var hold = 1000 + (phase === "result" && session.step === 8 ? 1000 : 0);
      paint();
      later(function () {
        if (!run || run.session.generation !== gen || run.session.phase !== phase) return;
        if (phase === "done") { close(); return; }
        advancePage();
      }, delay + hold);
      return;
    }
    if (phase === "outcome" || phase === "endingShot" || phase === "changeover") { run.selected = false; paint(); selectAnimation(); }
    else paint();
    later(function () {
      if (!run || run.session.generation !== gen) return;
      session.advance();
      schedule();
    }, beatMs(phase));
  }
  function advancePage() {
    var next = run.session.step + 1;
    if (next > COUNT) { run.session.phase = "done"; run.session.generation = ++gens; }
    else run.session = new Session(next);
    run.elapsed = METRICS[run.session.step] ? METRICS[run.session.step][2] : run.elapsed;
    schedule();
  }
  function beginExample() {
    if (!run || run.session.phase !== "situation") return;
    run.session.beginExample();
    schedule();
  }
  function close() {
    if (run) { clearTimers(); clearInterval(run.tick); }
    run = null;
    S.walkthroughSeen = true;
    S.popAll();
    evaluateOffer();
  }

  S.closeWalkthrough = function () { close(); };
  S.screens.walkthrough = function (entry) {
    S.walkthroughSeen = true;
    var host = h("div", { class: "wt-layer" });
    if (entry.offer && !entry.started) {
      host.appendChild(h("div", { class: "app-scroll noscroll" }, h("div", { class: "wt-intro-offer" },
        h("div", { class: "t", text: "Learn the controls" }),
        h("div", { class: "d", text: "Tap to start each example, then watch its gesture and result. No match or workout is saved." }),
        h("button", { type: "button", class: "bordered", onclick: function () { entry.started = true; S.render(); } }, "Show guide"),
        h("button", { type: "button", class: "bordered", onclick: function () { S.popAll(); } }, "Not now"))));
      return host;
    }
    if (run) { clearTimers(); clearInterval(run.tick); }
    run = { session: new Session(1), timers: [], host: host, elapsed: METRICS[1][2], selected: false, announce: "" };
    run.tick = setInterval(function () {
      if (!run) return;
      run.elapsed += 1;
      var f = run.host.querySelector("[data-wt-foot]");
      var m = METRICS[run.session.step];
      if (f && m) f.textContent = "🔥 " + m[1] + " kcal · 🕐 " + fmtDur(run.elapsed);
    }, 1000);
    // paint after the layer is in the DOM
    setTimeout(function () { if (run && run.host === host) schedule(); }, 0);
    return host;
  };

  /* ---- First-use offer (walkthrough.shouldOffer) --------------------------------------------
     The watch offers the guide once, when it is idle with no history. With the
     starter matches present it stays quiet; delete them all and close Past
     Matches to see it. */
  function evaluateOffer() {
    if (S.walkthroughSeen || S.history.length || api.active() || S.stack.length || S.alert) return;
    S.walkthroughSeen = true;
    S.push({ id: "walkthrough", offer: true });
  }
  S.afterRender = evaluateOffer;

  S.boot();
})();
