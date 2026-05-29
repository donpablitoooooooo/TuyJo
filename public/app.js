/* TuyJo site interactions */
(function () {
  "use strict";

  /* ---- Nav background on scroll ---- */
  const nav = document.querySelector(".nav");
  const onScroll = () => {
    if (window.scrollY > 30) nav.classList.add("scrolled");
    else nav.classList.remove("scrolled");
  };
  window.addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  /* ---- Reveal on scroll ---- */
  const io = new IntersectionObserver(
    (entries) => {
      entries.forEach((e) => {
        if (e.isIntersecting) {
          e.target.classList.add("in");
          io.unobserve(e.target);
        }
      });
    },
    { threshold: 0.12, rootMargin: "0px 0px -8% 0px" }
  );
  document.querySelectorAll(".reveal").forEach((el) => io.observe(el));

  /* ---- Subtle parallax on floating cherries ---- */
  const floats = document.querySelectorAll("[data-parallax]");
  let ticking = false;
  window.addEventListener(
    "scroll",
    () => {
      if (ticking) return;
      ticking = true;
      requestAnimationFrame(() => {
        const y = window.scrollY;
        floats.forEach((el) => {
          const speed = parseFloat(el.getAttribute("data-parallax")) || 0.1;
          const rot = el.getAttribute("data-rot") || "0deg";
          el.style.transform = `translateY(${y * speed}px) rotate(${rot})`;
        });
        ticking = false;
      });
    },
    { passive: true }
  );

  /* ---- Animated chat sequence inside the phone ---- */
  const chat = document.querySelector(".chat-body");
  if (chat) {
    const items = Array.from(chat.children);
    let started = false;
    const playChat = () => {
      if (started) return;
      started = true;
      let delay = 400;
      items.forEach((el) => {
        if (el.classList.contains("typing")) {
          // show typing, then hide before next bubble
          setTimeout(() => el.classList.add("show"), delay);
          setTimeout(() => el.classList.remove("show"), delay + 1100);
          delay += 1100;
        } else {
          setTimeout(() => el.classList.add("show"), delay);
          delay += 750;
        }
      });
    };
    const chatIO = new IntersectionObserver(
      (entries) => {
        entries.forEach((e) => { if (e.isIntersecting) playChat(); });
      },
      { threshold: 0.4 }
    );
    chatIO.observe(chat);
  }

  /* ---- FAQ: close others when one opens (accordion) ---- */
  const faqs = document.querySelectorAll(".faq");
  faqs.forEach((d) => {
    d.addEventListener("toggle", () => {
      if (d.open) faqs.forEach((o) => { if (o !== d) o.open = false; });
    });
  });

  /* ---- Year ---- */
  const yr = document.getElementById("year");
  if (yr) yr.textContent = new Date().getFullYear();
})();
