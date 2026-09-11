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
  ipad: { w: 2064, h: 2752, dpr: 2, device: 'ipad', dir: 'ios/ipad-13' },            // iPad 13"
  android: { w: 1080, h: 1920, dpr: 3, device: 'android', dir: 'android/phone' },    // 9:16
  'android-tablet': { w: 1600, h: 2560, dpr: 2, device: 'tablet', dir: 'android/tablet-10' },
  feature: { w: 1024, h: 500, dpr: 1, device: 'feature', dir: 'android/feature-graphic' },
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
    const list = t === 'feature' ? [0] : shots;
    for (const lang of langs) {
      const dir = path.join(outRoot, cfg.dir, lang);
      fs.mkdirSync(dir, { recursive: true });
      for (const shot of list) {
        const url = `${html}?device=${cfg.device}&lang=${lang}&shot=${shot}`;
        await page.goto(url, { waitUntil: 'load' });
        await page.evaluate(() => document.fonts.ready);
        await page.waitForTimeout(150);
        const file = path.join(dir, t === 'feature' ? `feature-graphic-${lang}.png` : `${String(shot).padStart(2, '0')}-${lang}.png`);
        await page.screenshot({ path: file, fullPage: false });
        console.log('✓', path.relative(outRoot, file));
      }
    }
    await ctx.close();
  }
  await browser.close();
})().catch((e) => { console.error(e); process.exit(1); });
