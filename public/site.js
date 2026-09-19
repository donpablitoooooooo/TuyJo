/* Tuijo — interazioni del sito. Tutto qui: niente librerie. */
(function () {
  "use strict";

  /* Bordo della nav quando si scrolla */
  var nav = document.querySelector(".nav");
  if (nav) {
    var onScroll = function () {
      nav.classList.toggle("scrolled", window.scrollY > 16);
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    onScroll();
  }

  /* Comparsa progressiva delle sezioni */
  var els = document.querySelectorAll(".reveal");
  if (!("IntersectionObserver" in window)) {
    els.forEach(function (el) { el.classList.add("in"); });
  } else {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (!e.isIntersecting) return;
        e.target.classList.add("in");
        io.unobserve(e.target);
      });
    }, { threshold: 0.1, rootMargin: "0px 0px -6% 0px" });
    els.forEach(function (el) { io.observe(el); });
  }

  /* Le immagini scorrono un po' più lentamente del testo che le accompagna */
  var moving = [].slice.call(document.querySelectorAll("[data-move]"));
  var still = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (moving.length && !still) {
    var pending = false;
    var place = function () {
      pending = false;
      var h = window.innerHeight;
      moving.forEach(function (el) {
        var r = el.getBoundingClientRect();
        if (r.bottom < -200 || r.top > h + 200) return;
        var amount = parseFloat(el.getAttribute("data-move")) || 20;
        // -1 quando l'elemento entra dal basso, +1 quando esce dall'alto
        var progress = (h / 2 - (r.top + r.height / 2)) / h;
        el.style.setProperty("--shift", (progress * amount).toFixed(1) + "px");
      });
    };
    var queue = function () {
      if (pending) return;
      pending = true;
      requestAnimationFrame(place);
    };
    window.addEventListener("scroll", queue, { passive: true });
    window.addEventListener("resize", queue, { passive: true });
    place();
  }

  /* Scena dell'abbinamento: lo scorrimento fa avanzare la composizione */
  var scenes = [].slice.call(document.querySelectorAll("[data-scene]"));
  if (scenes.length && !still) {
    scenes.forEach(function (sc) { sc.style.setProperty("--p", "0"); });
    var advance = function () {
      scenes.forEach(function (sc) {
        var track = sc.querySelector(".scene-track");
        var r = track.getBoundingClientRect();
        var run = r.height - window.innerHeight;
        var p = run > 0 ? Math.min(1, Math.max(0, -r.top / run)) : 1;
        sc.style.setProperty("--p", p.toFixed(3));
        sc.setAttribute("data-step", p < 0.38 ? "0" : p < 0.80 ? "1" : "2");
      });
    };
    var scenePending = false;
    var queueScene = function () {
      if (scenePending) return;
      scenePending = true;
      requestAnimationFrame(function () { scenePending = false; advance(); });
    };
    window.addEventListener("scroll", queueScene, { passive: true });
    window.addEventListener("resize", queueScene, { passive: true });
    advance();
  } else {
    scenes.forEach(function (sc) { sc.setAttribute("data-step", "2"); });
  }

  /* FAQ: apre una domanda alla volta */
  var faqs = document.querySelectorAll(".faq");
  faqs.forEach(function (d) {
    d.addEventListener("toggle", function () {
      if (!d.open) return;
      faqs.forEach(function (o) { if (o !== d) o.open = false; });
    });
  });

  /* Banda fotografica: se la foto manca resta il fondo pieno, senza rotture */
  document.querySelectorAll(".band img").forEach(function (img) {
    var fail = function () {
      img.remove();
      img.closest(".band").classList.add("no-photo");
    };
    img.addEventListener("error", fail);
    if (img.complete && img.naturalWidth === 0) fail();
  });

  /* Anno nel footer */
  var yr = document.getElementById("year");
  if (yr) yr.textContent = new Date().getFullYear();
})();
