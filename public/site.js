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
