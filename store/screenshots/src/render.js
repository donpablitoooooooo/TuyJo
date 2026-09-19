#!/usr/bin/env node
/**
 * Genera gli screenshot per App Store / Google Play a partire da index.html.
 *
 * Uso:  node render.js [--lang it,en] [--target ios,android] [--shot 1,2] [--out ../out]
 * Richiede Playwright (npm i -g playwright) e Chromium. Con
 * PLAYWRIGHT_CHROMIUM_PATH si può indicare l'eseguibile di Chromium.
 */
const path = require('path');
const fs = require('fs');

function resolvePlaywright() {
  try { return require('playwright'); } catch (_) {}
  const { execSync } = require('child_process');
  const root = execSync('npm root -g').toString().trim();
  return require(path.join(root, 'playwright'));
}
const { chromium } = resolvePlaywright();

// Formati richiesti dagli store (larghezza × altezza in pixel reali).
const TARGETS = {
  ios: { w: 1320, h: 2868, dpr: 3, device: 'iphone', dir: 'ios/iphone-6.9' },        // iPhone 6.9"
  'ios-6.5': { w: 1284, h: 2778, dpr: 3, device: 'iphone', dir: 'ios/iphone-6.5' },  // iPhone 6.5" (1284×2778)
  ipad: { w: 2064, h: 2752, dpr: 2, device: 'ipad', dir: 'ios/ipad-13' },            // iPad 13"
  android: { w: 1080, h: 1920, dpr: 3, device: 'android', dir: 'android/phone' },    // 9:16
  'android-tablet': { w: 1600, h: 2560, dpr: 2, device: 'tablet', dir: 'android/tablet-10' },
  feature: { w: 1024, h: 500, dpr: 1, device: 'feature', dir: 'android/feature-graphic' },
  // Anteprima social del sito (og:image).
  og: { w: 1200, h: 630, dpr: 1, device: 'og', dir: '', flat: true, single: true },
  // Ritagli a scheda: una porzione di schermata, per variare la forma delle immagini.
  'web-card': { w: 980, h: 720, dpr: 2, device: 'card', dir: 'shots', transparent: true, prefix: 'card-', clipSel: '.uicard' },
  // Immagini per il sito: solo il dispositivo, sfondo trasparente, senza titolo.
  web: { w: 1000, h: 2140, dpr: 2, device: 'web', dir: 'shots', transparent: true },
  'web-pair': { w: 1700, h: 1980, dpr: 2, device: 'webpair', dir: 'shots', transparent: true, prefix: 'pair-', single: true },
};

const args = process.argv.slice(2);
const opt = (name, def) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : def;
};
const langs = opt('lang', 'it,en,es,ca').split(',');
const targets = opt('target', Object.keys(TARGETS).join(',')).split(',');
const shots = opt('shot', '1,2,3,4,5,6').split(',').map(Number);
const outRoot = path.resolve(__dirname, opt('out', '../out'));

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.PLAYWRIGHT_CHROMIUM_PATH || undefined,
  });
  const html = 'file://' + path.join(__dirname, 'index.html');
  for (const t of targets) {
    const cfg = TARGETS[t];
    if (!cfg) throw new Error(`target sconosciuto: ${t}`);
    const ctx = await browser.newContext({
      viewport: { width: cfg.w / cfg.dpr, height: cfg.h / cfg.dpr },
      deviceScaleFactor: cfg.dpr,
    });
    const page = await ctx.newPage();
    const list = t === 'feature' ? [0] : cfg.single ? [shots[0]] : shots;
    for (const lang of langs) {
      const dir = path.join(outRoot, cfg.dir, cfg.flat ? '' : lang);
      fs.mkdirSync(dir, { recursive: true });
      for (const shot of list) {
        const shot2 = cfg.device === 'webpair' ? `&shot2=${shot === 1 ? 4 : 1}` : '';
        // quanto scendere dentro la schermata per inquadrare la parte interessante
        const CARD_OFF = { 5: 192, 11: 192, 12: 192 };
        const off = cfg.device === 'card' ? `&off=${CARD_OFF[shot] || 0}` : '';
        // foto vere per la galleria, se qualcuno ne ha messe in src/img/photos/
        const photoDir = path.join(__dirname, 'img', 'photos');
        const real = fs.existsSync(photoDir)
          ? fs.readdirSync(photoDir).filter((f) => /\.(jpe?g|png|webp)$/i.test(f)).sort()
          : [];
        const photos = real.length ? `&photos=${real.join(',')}` : '';
        const url = `${html}?device=${cfg.device}&lang=${lang}&shot=${shot}${shot2}${off}${photos}`;
        await page.addInitScript((sel) => { window.__clipSel = sel; }, cfg.clipSel || '.device');
        await page.goto(url, { waitUntil: 'load' });
        await page.evaluate(() => document.fonts.ready);
        await page.waitForTimeout(150);
        const name = t === 'feature' ? `feature-graphic-${lang}.png`
          : cfg.flat ? `${t}-${lang}.png`
          : `${cfg.prefix || ''}${String(shot).padStart(2, '0')}-${lang}.png`;
        const file = path.join(dir, name);
        // Per il sito ritaglio sul bounding box dei dispositivi: l'immagine non
        // porta margini vuoti e l'ombra la mette il CSS del sito.
        const clip = cfg.transparent ? await page.evaluate((m) => {
          const r = [...document.querySelectorAll(window.__clipSel)].map((e) => e.getBoundingClientRect());
          const x = Math.min(...r.map((b) => b.left)) - m, y = Math.min(...r.map((b) => b.top)) - m;
          return {
            x: Math.max(0, x), y: Math.max(0, y),
            width: Math.max(...r.map((b) => b.right)) + m - Math.max(0, x),
            height: Math.max(...r.map((b) => b.bottom)) + m - Math.max(0, y),
          };
        }, 2) : undefined;
        await page.screenshot({ path: file, fullPage: false, clip, omitBackground: !!cfg.transparent });
        console.log('✓', path.relative(outRoot, file));
      }
    }
    await ctx.close();
  }
  await browser.close();
})().catch((e) => { console.error(e); process.exit(1); });
