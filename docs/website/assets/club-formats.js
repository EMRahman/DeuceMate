/* Tournament presets drive the same Watch scoreboard used on try.html. */
(function () {
  "use strict";

  const scoring = window.DeuceMateScoring;
  const { formats, formatFromQuery } = window.DeuceMateClubScenarios;
  const page = document.querySelector(".club-page");
  const params = new URLSearchParams(window.location.search);
  const options = page.querySelector(".club-options");
  const host = page.querySelector("[data-club-watch]");
  const loading = page.querySelector("[data-club-loading]");
  const formatButtons = [...options.querySelectorAll("[data-format]")];
  const typeButtons = [...options.querySelectorAll("[data-type]")];
  const sceneButtons = [...options.querySelectorAll("[data-scene]")];
  const rules = page.querySelector("#club-rules");
  const caption = page.querySelector("#club-scene-note");
  const next = page.querySelector("#club-next");
  const summary = page.querySelector("#club-score-summary");
  const doublesNames = { me: "You", partner: "Your partner", opponentS1: "Opponent 1", opponentS2: "Opponent 2" };

  let format = formatFromQuery(params) || "fast4";
  let type = params.get("type") === "singles" ? "singles" : "doubles";
  let scene = Object.hasOwn(formats[format].scenes, params.get("scene"))
    ? params.get("scene")
    : formats[format].defaultScene;
  let api;

  function nextServe(state) {
    const server = type === "doubles"
      ? doublesNames[state.doublesServer]
      : state.currentServer === "me" ? "You" : "Opponent";
    const serving = server + (server === "You" ? " serve" : " serves");
    if (scoring.receiverChoosesServiceSide(state)) return serving + ". The receiver chooses the side for the deciding point.";
    const court = scoring.isDeuceSide(state) ? "deuce (right)" : "ad (left)";
    return serving + " from the " + court + " court.";
  }

  function renderStatus() {
    const state = api.stateRef();
    const set = scoring.lastSet(state);
    const winner = scoring.matchWinner(state);
    const points = set.isTieBreak
      ? [set.tieBreakPointsMe, set.tieBreakPointsOpponent]
      : scoring.regularPointStrings(state.currentPointsMe, state.currentPointsOpponent);
    const games = "Games " + set.gamesMe + " to " + set.gamesOpponent + ".";
    const pointScore = (set.isTieBreak ? "Tiebreak points " : "Points ") + points.join(" to ") + ".";
    const score = [state.cfg.playRegularSets && games, (!winner || set.isTieBreak) && pointScore].filter(Boolean).join(" ");
    const prompt = api.phoneState().changeover;
    const status = winner
      ? (winner === "me" ? "Match complete. You win." : "Match complete. Opponent wins.")
      : prompt ? prompt.reason + "." : nextServe(state);
    if (summary.textContent !== score) summary.textContent = score;
    if (next.textContent !== status) next.textContent = status;
  }

  function loadScene(updateUrl) {
    const preset = formats[format];
    const selected = preset.scenes[scene];
    rules.textContent = preset.rules;
    caption.textContent = selected.caption;
    formatButtons.forEach(button => button.setAttribute("aria-pressed", String(button.dataset.format === format)));
    typeButtons.forEach(button => button.setAttribute("aria-pressed", String(button.dataset.type === type)));
    sceneButtons.forEach(button => {
      button.textContent = preset.scenes[button.dataset.scene].label;
      button.setAttribute("aria-pressed", String(button.dataset.scene === scene));
    });
    api.loadScenario({ format, matchType: type, tracking: false, health: true, undoSeededPoints: false }, selected.points);
    renderStatus();

    if (updateUrl) {
      const url = new URL(window.location.href);
      url.search = new URLSearchParams({ format, type, scene }).toString();
      window.history.replaceState(null, "", url);
    }
  }

  async function start() {
    // Read only the Watch markup. The app shell and iPhone stay on try.html.
    const response = await fetch("try.html");
    if (!response.ok) throw new Error("Could not load the Watch demo");
    const demo = new DOMParser().parseFromString(await response.text(), "text/html");
    const watch = demo.querySelector("#watch-demo");
    if (!watch) throw new Error("The Watch demo markup is missing");

    watch.setAttribute("data-keyboard", "scoped");
    const screen = watch.querySelector("[data-screen]");
    screen.classList.add("playing");
    const shell = watch.querySelector("[data-shell]");
    shell.classList.add("is-playing");
    const chrome = document.createElement("div");
    chrome.className = "app-chrome";
    const runIcon = document.createElement("span");
    runIcon.className = "app-run";
    runIcon.setAttribute("aria-label", "Workout in progress");
    runIcon.setAttribute("role", "img");
    runIcon.innerHTML = '<svg viewBox="0 0 24 24" width="13" height="13" fill="currentColor"><path d="M13.5 5.5a2 2 0 1 0 0-4 2 2 0 0 0 0 4zM9.8 8.9 7 23h2.1l1.8-8 2.1 2v6h2v-7.5l-2.1-2 .6-3A7.3 7.3 0 0 0 19 15v-2c-1.6 0-2.9-.9-3.6-2l-1-1.6c-.4-.6-1-1-1.7-1-.3 0-.5.1-.8.1L6 8.3V13h2V9.6l1.8-.7z"/></svg>';
    const clockEl = document.createElement("span");
    clockEl.className = "app-clock";
    const tickClock = () => {
      const d = new Date();
      let parts;
      try {
        parts = new Intl.DateTimeFormat(undefined, { hour: "numeric", minute: "2-digit" }).format(d).replace(/\s?[AP]M/i, "");
      } catch {
        parts = d.getHours() + ":" + ("0" + d.getMinutes()).slice(-2);
      }
      clockEl.textContent = parts;
    };
    tickClock();
    window.setInterval(tickClock, 15000);
    chrome.append(runIcon, clockEl);
    shell.append(chrome);
    watch.querySelector("[data-secondserve]").remove();
    watch.querySelector(".remote-label").remove();
    watch.querySelector("[data-complete-end]").textContent = "Replay scenario";
    host.append(watch);
    api = window.DeuceMateWatchUI.mount(watch);
    api.hooks.endMatch = () => {
      loadScene(false);
      screen.focus();
    };
    loadScene(false);
    api.hooks.change = renderStatus;

    formatButtons.forEach(button => button.addEventListener("click", () => {
      if (format === button.dataset.format) return;
      format = button.dataset.format;
      scene = formats[format].defaultScene;
      loadScene(true);
    }));
    typeButtons.forEach(button => button.addEventListener("click", () => {
      if (type === button.dataset.type) return;
      type = button.dataset.type;
      loadScene(true);
    }));
    sceneButtons.forEach(button => button.addEventListener("click", () => {
      scene = button.dataset.scene;
      loadScene(true);
    }));
    options.querySelector("[data-club-reset]").addEventListener("click", () => loadScene(false));
    options.inert = false;
    loading.hidden = true;
  }

  loading.textContent = "Loading the Watch simulator…";
  start().catch(() => {
    host.replaceChildren();
    loading.textContent = "The Watch simulator could not load.";
    page.querySelector("[data-club-fallback]").hidden = false;
  });
})();
