/* DeuceMate home page: opens the browser demo in place, only when asked.

   try.html stays the single source of the demo. Its markup, stylesheets and
   scripts are read from that page on demand, so the two can't drift and
   visitors who never open the demo don't download it. If anything fails, the
   visitor goes to try.html, which is also where the links lead without JS. */
(function () {
  "use strict";

  var section = document.getElementById("try");
  if (!section) return;
  var host = section.querySelector("[data-home-try-host]");
  var launch = section.querySelector("[data-home-try-launch]");
  var status = section.querySelector("[data-home-try-status]");
  var links = section.querySelectorAll("[data-home-try]");
  var loading = false;

  function loadStylesheet(href) {
    return new Promise(function (resolve, reject) {
      var link = document.createElement("link");
      link.rel = "stylesheet";
      link.href = href;
      link.onload = resolve;
      link.onerror = function () { reject(new Error("Could not load " + href)); };
      document.head.appendChild(link);
    });
  }

  /* The demo's scripts expect to run one after another, as they do on try.html. */
  function loadScript(src) {
    return new Promise(function (resolve, reject) {
      var script = document.createElement("script");
      script.src = src;
      script.async = false;
      script.onload = resolve;
      script.onerror = function () { reject(new Error("Could not load " + src)); };
      document.body.appendChild(script);
    });
  }

  function attributes(page, selector, name, skip) {
    return Array.prototype.map.call(page.querySelectorAll(selector), function (node) {
      return node.getAttribute(name);
    }).filter(function (value) { return value !== skip; });
  }

  function loadDemo() {
    return fetch("try.html").then(function (response) {
      if (!response.ok) throw new Error("try.html returned " + response.status);
      return response.text();
    }).then(function (html) {
      var page = new DOMParser().parseFromString(html, "text/html");
      var demo = page.querySelector(".companion-demo");
      var jump = page.querySelector(".device-jump");
      var about = page.querySelector(".about-demo");
      if (!demo || !about) throw new Error("try.html no longer has the demo");

      /* On this page the arrow keys must keep scrolling until the visitor is
         actually using the Watch. */
      var watch = demo.querySelector("#watch-demo");
      if (watch) watch.setAttribute("data-keyboard", "scoped");

      var styles = attributes(page, 'link[rel="stylesheet"]', "href", "assets/site.css");
      var scripts = attributes(page, "script[src]", "src", "assets/site.js");

      return Promise.all(styles.map(loadStylesheet)).then(function () {
        if (jump) host.appendChild(document.adoptNode(jump));
        host.appendChild(document.adoptNode(demo));
        host.appendChild(document.adoptNode(about));
        host.hidden = false;
        return scripts.reduce(function (done, src) {
          return done.then(function () { return loadScript(src); });
        }, Promise.resolve());
      });
    });
  }

  function hasCoachingInsights() {
    return Array.prototype.some.call(host.querySelectorAll(".pr-native-section"), function (group) {
      var title = group.querySelector(".pr-native-section-title");
      return title && title.textContent.indexOf("Coaching Insights") === 0 && group.querySelector(".pr-coach-line");
    });
  }

  /* Opens the newest finished match that has insights, scrolled to them. Tagged
     samples aren't guaranteed to be first, and a returning visitor's archive may
     have changed, so this checks what actually rendered. */
  function openCoachingReport() {
    var phone = window.DeuceMatePhone;
    if (!phone) return false;
    var finished = phone.records().filter(function (record) { return !!record.endTime; });
    for (var i = 0; i < finished.length; i++) {
      phone.navigate("detail", finished[i]);
      if (hasCoachingInsights()) {
        var scroller = host.querySelector(".phone-body");
        var groups = host.querySelectorAll(".pr-native-section");
        for (var g = 0; g < groups.length; g++) {
          var title = groups[g].querySelector(".pr-native-section-title");
          if (title && title.textContent.indexOf("Coaching Insights") === 0) {
            scroller.scrollTop += groups[g].getBoundingClientRect().top - scroller.getBoundingClientRect().top - 12;
            break;
          }
        }
        return true;
      }
    }
    phone.navigate("matches");
    return false;
  }

  function reveal(target) {
    var panel = host.querySelector(target === "report" ? "#panel-iphone" : "#panel-watch");
    var focusTarget = target === "report" ? panel : host.querySelector("[data-screen]");
    if (panel) panel.scrollIntoView({ block: "start" });
    if (focusTarget) {
      if (!focusTarget.hasAttribute("tabindex")) focusTarget.setAttribute("tabindex", "-1");
      focusTarget.focus({ preventScroll: true });
    }
  }

  function open(target) {
    if (loading) return;
    loading = true;
    section.setAttribute("aria-busy", "true");
    status.textContent = "Loading the demo…";
    loadDemo().then(function () {
      launch.hidden = true;
      section.removeAttribute("aria-busy");
      status.textContent = "";
      if (target === "report" && !openCoachingReport()) status.textContent = "Open any match on the iPhone to see its report.";
      reveal(target);
    }).catch(function () {
      window.location.href = "try.html";
    });
  }

  Array.prototype.forEach.call(links, function (link) {
    link.addEventListener("click", function (event) {
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      event.preventDefault();
      open(link.getAttribute("data-home-try"));
    });
  });
})();
