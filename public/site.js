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

  /* Sequenze: le schermate si alternano finché la sezione è in vista */
  [].slice.call(document.querySelectorAll("[data-reel]")).forEach(function (reel) {
    var frames = [].slice.call(reel.querySelectorAll(".fr"));
    if (frames.length < 2 || still) return;
    var i = 0, timer = null;
    var hold = function (n) { return parseInt(frames[n].getAttribute("data-hold"), 10) || 2400; };
    var step = function () {
      frames[i].classList.remove("on");
      i = (i + 1) % frames.length;
      frames[i].classList.add("on");
      timer = setTimeout(step, hold(i));
    };
    new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting && !timer) timer = setTimeout(step, hold(i));
        if (!e.isIntersecting && timer) { clearTimeout(timer); timer = null; }
      });
    }, { threshold: 0.3 }).observe(reel);
  });

  /* Scena dell'abbinamento: ogni bottone mostra la schermata del suo passo */
  [].slice.call(document.querySelectorAll("[data-scene]")).forEach(function (sc) {
    var frames = [].slice.call(sc.querySelectorAll(".scene-phone .fr"));
    var buttons = [].slice.call(sc.querySelectorAll("[data-go]"));
    var show = function (step) {
      frames.forEach(function (f, n) { f.classList.toggle("on", n === step); });
      buttons.forEach(function (b, n) {
        b.setAttribute("aria-pressed", String(n === step));
        b.classList.toggle("next", n === step + 1);
      });
    };
    buttons.forEach(function (b, n) { b.addEventListener("click", function () { show(n); }); });
    show(0);
  });

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
