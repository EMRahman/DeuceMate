/* Step-by-step setup guide (setup.html) — tiny vanilla JS, no dependencies.
   By default every step is on one long page, and a sticky bar tracks the
   reader's place as they scroll: "Step 8 of 28", the chapter, how many steps
   are left, and a bar that fills towards the end. A button switches to one
   step at a time (Back / Next, ← →). The "jump to" menu works in both modes,
   and a #step-N address lands on that step. With JS off the long page shows
   without the bar. */
(function () {
  "use strict";

  var guide = document.querySelector("[data-guide]");
  if (!guide) return;
  var steps = Array.prototype.slice.call(guide.querySelectorAll(".step"));
  if (!steps.length) return;

  var prev = guide.querySelector("[data-prev]");
  var next = guide.querySelector("[data-next]");
  var text = guide.querySelector("[data-progress-text]");
  var left = guide.querySelector("[data-progress-left]");
  var bar = guide.querySelector("[data-progress-bar]");
  var jump = guide.querySelector("[data-jump]");
  var modeBtn = guide.querySelector("[data-mode]");
  var print = guide.querySelector("[data-print]");
  var current = -1;

  steps.forEach(function (step, i) {
    step.id = "step-" + (i + 1);
    var opt = document.createElement("option");
    var chapter = step.querySelector(".step-chapter");
    var title = step.querySelector("h2");
    opt.value = String(i);
    opt.textContent = (i + 1) + ". " + (title ? title.textContent : "") +
      (chapter ? " (" + chapter.textContent + ")" : "");
    jump.appendChild(opt);
  });

  function isPaged() { return guide.classList.contains("paged"); }

  /* Updates the bar for step i. `fraction` (0–1) fills the bar; in the long
     page it follows the scroll position so it moves smoothly. */
  function setCurrent(i, fraction) {
    i = Math.max(0, Math.min(steps.length - 1, i));
    var remaining = steps.length - 1 - i;
    bar.style.width = Math.round(fraction * 100) + "%";
    if (i === current) return;
    current = i;
    var chapter = steps[i].querySelector(".step-chapter");
    text.textContent = "Step " + (i + 1) + " of " + steps.length;
    left.textContent = (chapter ? chapter.textContent + " · " : "") +
      (remaining === 0 ? "last step" : remaining === 1 ? "1 step left" : remaining + " steps left");
    jump.value = String(i);
    if (history.replaceState) history.replaceState(null, "", "#step-" + (i + 1));
  }

  /* --- Long page: follow the scroll ------------------------------------- */
  function onScroll() {
    if (isPaged()) return;
    // The step whose top has passed 40% of the way down the screen.
    var line = window.innerHeight * 0.4;
    var i = 0;
    for (var k = 0; k < steps.length; k++) {
      if (steps[k].getBoundingClientRect().top <= line) i = k; else break;
    }
    var first = steps[0].getBoundingClientRect().top + window.scrollY;
    var last = steps[steps.length - 1];
    var end = last.getBoundingClientRect().bottom + window.scrollY - window.innerHeight;
    var fraction = end > first ? (window.scrollY - first + line) / (end - first + line) : 1;
    setCurrent(i, Math.max(0, Math.min(1, fraction)));
  }
  var ticking = false;
  window.addEventListener("scroll", function () {
    if (ticking) return;
    ticking = true;
    window.requestAnimationFrame(function () { ticking = false; onScroll(); });
  }, { passive: true });
  window.addEventListener("resize", onScroll);

  /* --- One step at a time ----------------------------------------------- */
  function showOne(i, focus) {
    i = Math.max(0, Math.min(steps.length - 1, i));
    steps.forEach(function (s, k) { s.classList.toggle("current", k === i); });
    setCurrent(i, (i + 1) / steps.length);
    prev.disabled = i === 0;
    next.textContent = i === steps.length - 1 ? "Start again ↺" : "Next →";
    if (focus) {
      guide.querySelector(".guide-bar").scrollIntoView({ block: "start" });
      var heading = steps[i].querySelector("h2");
      if (heading) { heading.setAttribute("tabindex", "-1"); heading.focus({ preventScroll: true }); }
    }
  }

  function goTo(i) {
    if (isPaged()) { showOne(i, true); return; }
    steps[i].scrollIntoView({ block: "start", behavior: "smooth" });
  }

  prev.addEventListener("click", function () { showOne(current - 1, true); });
  next.addEventListener("click", function () {
    showOne(current === steps.length - 1 ? 0 : current + 1, true);
  });
  jump.addEventListener("change", function () { goTo(parseInt(jump.value, 10)); });
  modeBtn.addEventListener("click", function () {
    var at = current;
    var paged = guide.classList.toggle("paged");
    modeBtn.textContent = paged ? "Show all steps on one page" : "Show one step at a time";
    if (paged) { showOne(at, true); } else { current = -1; steps[at].scrollIntoView({ block: "start" }); onScroll(); }
  });
  if (print) print.addEventListener("click", function () { window.print(); });

  document.addEventListener("keydown", function (e) {
    if (!isPaged()) return;
    var tag = (e.target && e.target.tagName) || "";
    if (tag === "SELECT" || tag === "INPUT" || tag === "TEXTAREA") return;
    if (e.target && e.target.closest && e.target.closest(".watch-demo")) return;
    if (e.key === "ArrowRight") { showOne(current + 1, true); e.preventDefault(); }
    if (e.key === "ArrowLeft") { showOne(current - 1, true); e.preventDefault(); }
  });

  guide.classList.add("js");
  var fromHash = /^#step-(\d+)$/.exec(location.hash);
  if (fromHash) {
    var target = steps[Math.min(steps.length, Math.max(1, parseInt(fromHash[1], 10))) - 1];
    target.scrollIntoView({ block: "start" });
  }
  onScroll();
})();
