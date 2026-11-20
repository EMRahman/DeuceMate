/* Club-format practice uses the same scoring reducer as the Watch demo. */
(function () {
  "use strict";

  const scoring = window.DeuceMateScoring;
  const { formats, formatFromQuery } = window.DeuceMateClubScenarios;
  const page = document.querySelector(".club-page");
  const params = new URLSearchParams(window.location.search);
  let format = formatFromQuery(params) || "fast4";
  let type = params.get("type") === "singles" ? "singles" : "doubles";
  let scene = Object.hasOwn(formats[format].scenes, params.get("scene"))
    ? params.get("scene")
    : formats[format].defaultScene;
  let state, history;

  const formatButtons = Array.from(page.querySelectorAll("[data-format]"));
  const typeButtons = Array.from(page.querySelectorAll("[data-type]"));
  const sceneButtons = Array.from(page.querySelectorAll("[data-scene]"));
  const awardButtons = Array.from(page.querySelectorAll("[data-award]"));
  const undoButton = page.querySelector("[data-undo]");
  const gamesCells = Array.from(page.querySelectorAll("[data-games]"));
  const pointCells = Array.from(page.querySelectorAll("[data-points]"));
  const pointsHeading = page.querySelector("[data-points-heading]");
  const rules = page.querySelector("#club-rules");
  const caption = page.querySelector("#club-scene-note");
  const next = page.querySelector("#club-next");
  const result = page.querySelector("#club-result");
  const doublesNames = { me: "You", partner: "Your partner", opponentS1: "Opponent 1", opponentS2: "Opponent 2" };

  function nextServe() {
    const server = type === "doubles"
      ? doublesNames[state.doublesServer]
      : state.currentServer === "me" ? "You" : "Opponent";
    const serving = server + (server === "You" ? " serve" : " serves");
    if (scoring.receiverChoosesServiceSide(state)) return serving + ". The receiver chooses the side for the deciding point.";
    const court = scoring.isDeuceSide(state) ? "deuce (right)" : "ad (left)";
    return `${serving} from the ${court} court.`;
  }

  function renderScore(message) {
    const set = scoring.lastSet(state);
    const winner = scoring.matchWinner(state);
    const points = set.isTieBreak
      ? [set.tieBreakPointsMe, set.tieBreakPointsOpponent]
      : scoring.regularPointStrings(state.currentPointsMe, state.currentPointsOpponent);
    pointsHeading.textContent = set.isTieBreak ? "Tiebreak points" : "Points";
    gamesCells.forEach(cell => { cell.hidden = !state.cfg.playRegularSets; });
    gamesCells[1].textContent = set.gamesMe;
    gamesCells[2].textContent = set.gamesOpponent;
    pointCells.forEach((cell, index) => { cell.textContent = winner && !set.isTieBreak ? "–" : points[index]; });

    next.textContent = winner
      ? (winner === "me" ? "Match complete. You win." : "Match complete. Opponent wins.")
      : nextServe();
    result.textContent = message;
    awardButtons.forEach(button => { button.disabled = Boolean(winner); });
    undoButton.disabled = history.length === 0;
  }

  function loadScene(updateUrl) {
    const preset = formats[format];
    const selected = preset.scenes[scene];
    state = scoring.freshState(format, "me");
    if (type === "doubles") scoring.applyDoublesSetup(state, "me");
    for (const winner of selected.points) state = scoring.pointWon(state, winner).state;
    history = [];

    rules.textContent = preset.rules;
    caption.textContent = selected.caption;
    formatButtons.forEach(button => button.setAttribute("aria-pressed", String(button.dataset.format === format)));
    typeButtons.forEach(button => button.setAttribute("aria-pressed", String(button.dataset.type === type)));
    sceneButtons.forEach(button => {
      button.textContent = preset.scenes[button.dataset.scene].label;
      button.setAttribute("aria-pressed", String(button.dataset.scene === scene));
    });
    renderScore("Choose who wins the next point.");

    if (updateUrl) {
      const url = new URL(window.location.href);
      url.search = new URLSearchParams({ format, type, scene }).toString();
      window.history.replaceState(null, "", url);
    }
  }

  function awardPoint(winner) {
    history.push(state);
    const played = scoring.pointWon(state, winner);
    state = played.state;
    const game = played.events.find(event => event.t === "gameWon");
    const change = played.events.find(event => event.t === "changeover");
    const side = winner === "me" ? "You win" : "Opponent wins";
    const pointResult = side + (game ? " the game." : " the point.");
    const changeover = change && !scoring.isMatchComplete(state) ? scoring.changeoverReasonText(change) : "";
    renderScore(changeover ? pointResult + " " + changeover + "." : pointResult);
  }

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
  awardButtons.forEach(button => button.addEventListener("click", () => awardPoint(button.dataset.award)));
  undoButton.addEventListener("click", () => {
    state = history.pop();
    renderScore("Last point undone.");
  });
  page.querySelector("[data-reset]").addEventListener("click", () => loadScene(false));
  loadScene(false);
})();
