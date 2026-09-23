/* Step-by-step setup guide (setup.html) — tiny vanilla JS, no dependencies.
   Turns the long list of .step sections into one step at a time with
   Back / Next, a progress bar, a "jump to" menu, the ← → keys, and a
   #step-N address so a reload or shared link lands on the same step.
   With JS off every step stays visible as one long page. */
(function () {
  "use strict";

  var guide = document.querySelector("[data-guide]");
  if (!guide) return;
  var steps = Array.prototype.slice.call(guide.querySelectorAll(".step"));
  if (!steps.length) return;

  var prev = guide.querySelector("[data-prev]");
  var next = guide.querySelector("[data-next]");
  var text = guide.querySelector("[data-progress-text]");
  var bar = guide.querySelector("[data-progress-bar]");
  var jump = guide.querySelector("[data-jump]");
  var showAll = guide.querySelector("[data-show-all]");
  var current = 0;

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

  function show(i, focus) {
    current = Math.max(0, Math.min(steps.length - 1, i));
    steps.forEach(function (s, k) { s.classList.toggle("current", k === current); });
    text.textContent = "Step " + (current + 1) + " of " + steps.length;
    bar.style.width = ((current + 1) / steps.length * 100) + "%";
    jump.value = String(current);
    prev.disabled = current === 0;
    next.textContent = current === steps.length - 1 ? "Start again ↺" : "Next →";
    if (history.replaceState) history.replaceState(null, "", "#step-" + (current + 1));
    if (focus) {
      var heading = steps[current].querySelector("h2");
      guide.scrollIntoView({ block: "start" });
      if (heading) { heading.setAttribute("tabindex", "-1"); heading.focus({ preventScroll: true }); }
    }
  }

  guide.classList.add("paged");
  var fromHash = /^#step-(\d+)$/.exec(location.hash);
  show(fromHash ? parseInt(fromHash[1], 10) - 1 : 0, false);

  prev.addEventListener("click", function () { show(current - 1, true); });
  next.addEventListener("click", function () {
    show(current === steps.length - 1 ? 0 : current + 1, true);
  });
  jump.addEventListener("change", function () { show(parseInt(jump.value, 10), true); });
  showAll.addEventListener("click", function () {
    var paged = guide.classList.toggle("paged");
    showAll.textContent = paged ? "Show all steps on one page" : "Show one step at a time";
    if (paged) show(current, true);
  });

  var print = guide.querySelector("[data-print]");
  if (print) print.addEventListener("click", function () { window.print(); });

  document.addEventListener("keydown", function (e) {
    if (!guide.classList.contains("paged")) return;
    var tag = (e.target && e.target.tagName) || "";
    if (tag === "SELECT" || tag === "INPUT" || tag === "TEXTAREA") return;
    if (e.target && e.target.closest && e.target.closest(".watch-demo")) return;
    if (e.key === "ArrowRight") { show(current + 1, true); e.preventDefault(); }
    if (e.key === "ArrowLeft") { show(current - 1, true); e.preventDefault(); }
  });
})();
