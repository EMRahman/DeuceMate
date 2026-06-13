/* DeuceMate marketing site — tiny vanilla JS, no dependencies.
   1) sticky-nav shadow on scroll
   2) mobile nav toggle
   3) reveal-on-scroll via IntersectionObserver
   Degrades gracefully: with JS off, nav links stay visible and all
   .reveal content is shown (see the <noscript> rule in the <head>). */
(function () {
  "use strict";

  var nav = document.querySelector(".nav");

  /* 1) Add a frosted background to the nav once the page scrolls. */
  function onScroll() {
    if (!nav) return;
    nav.classList.toggle("scrolled", window.scrollY > 12);
  }
  window.addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  /* 2) Mobile menu toggle. */
  var toggle = document.querySelector(".nav-toggle");
  if (toggle && nav) {
    toggle.addEventListener("click", function () {
      var open = nav.classList.toggle("open");
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
    });
    // Close the menu after tapping a link.
    nav.querySelectorAll(".nav-links a").forEach(function (a) {
      a.addEventListener("click", function () {
        nav.classList.remove("open");
        toggle.setAttribute("aria-expanded", "false");
      });
    });
  }

  /* 3) Reveal elements as they enter the viewport. */
  var reduced = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var items = document.querySelectorAll(".reveal");

  if (reduced || !("IntersectionObserver" in window)) {
    items.forEach(function (el) { el.classList.add("in"); });
    return;
  }

  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (entry.isIntersecting) {
        entry.target.classList.add("in");
        io.unobserve(entry.target);
      }
    });
  }, { rootMargin: "0px 0px -8% 0px", threshold: 0.12 });

  items.forEach(function (el) { io.observe(el); });
})();
