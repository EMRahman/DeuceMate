/* Step-by-step setup guide (setup.html) — tiny vanilla JS, no dependencies.
   Every step is on one long page, and a rail down the right edge tracks the
   reader's place as they scroll: it fills downwards, and a label riding at the
   end of the fill says "8 of 28", the chapter and how many steps are left.
   A #step-N address lands on that step. With JS off the long page shows
   without the rail. */
(function () {
  "use strict";

  var guide = document.querySelector("[data-guide]");
  if (!guide) return;
  var steps = Array.prototype.slice.call(guide.querySelectorAll(".step"));
  if (!steps.length) return;

  var text = guide.querySelector("[data-progress-text]");
  var left = guide.querySelector("[data-progress-left]");
  var chapterText = guide.querySelector("[data-progress-chapter]");
  var rail = guide.querySelector("[data-rail]");
  var label = guide.querySelector("[data-rail-label]");
  var bar = guide.querySelector("[data-progress-bar]");
  var current = -1;

  steps.forEach(function (step, i) { step.id = "step-" + (i + 1); });

  rail.setAttribute("aria-valuemax", String(steps.length));

  /* Updates the rail for step i. `fraction` (0–1) fills it, following the
     scroll position so it moves smoothly. */
  function setCurrent(i, fraction) {
    i = Math.max(0, Math.min(steps.length - 1, i));
    var remaining = steps.length - 1 - i;
    var pct = Math.round(fraction * 1000) / 10;
    bar.style.height = pct + "%";
    // Keep the label fully on screen at both ends of the rail.
    label.style.top = "clamp(" + label.offsetHeight / 2 + "px, " + pct + "%, calc(100% - " + label.offsetHeight / 2 + "px))";
    if (i === current) return;
    current = i;
    var chapter = steps[i].querySelector(".step-chapter");
    text.textContent = (i + 1) + " of " + steps.length;
    chapterText.textContent = chapter ? chapter.textContent : "";
    left.textContent = remaining === 0 ? "last step" : remaining === 1 ? "1 left" : remaining + " left";
    rail.setAttribute("aria-valuenow", String(i + 1));
    rail.setAttribute("aria-valuetext", "Step " + (i + 1) + " of " + steps.length);
    if (history.replaceState) history.replaceState(null, "", "#step-" + (i + 1));
  }

  /* --- Follow the scroll ------------------------------------------------- */
  function onScroll() {
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
  // On phones the label is only visible (.active) while scrolling.
  var idleTimer = null;
  function markActive() {
    rail.classList.add("active");
    clearTimeout(idleTimer);
    idleTimer = setTimeout(function () { rail.classList.remove("active"); }, 1500);
  }
  var ticking = false;
  window.addEventListener("scroll", function () {
    markActive();
    if (ticking) return;
    ticking = true;
    window.requestAnimationFrame(function () { ticking = false; onScroll(); });
  }, { passive: true });
  window.addEventListener("resize", onScroll);

  guide.classList.add("js");
  var fromHash = /^#step-(\d+)$/.exec(location.hash);
  if (fromHash) {
    var target = steps[Math.min(steps.length, Math.max(1, parseInt(fromHash[1], 10))) - 1];
    target.scrollIntoView({ block: "start" });
  }
  onScroll();
  markActive();
})();
