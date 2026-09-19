#!/usr/bin/env node
/**
 * Converte in WebP i PNG delle immagini per il sito.
 *
 * In questo ambiente non c'è cwebp, ma Chromium sa codificare WebP: carichiamo
 * ogni PNG in una pagina, lo disegniamo su una canvas e lo riesportiamo. La
 * trasparenza viene mantenuta. I PNG originali vengono rimossi: la sorgente
 * vera sono le schermate generate da render.js, non questi file.
 *
 * Uso:  node webp.js ../../../public/assets/shots [qualità 0-1]
 */
const fs = require('fs');
const path = require('path');

function resolvePlaywright() {
  try { return require('playwright'); } catch (_) {}
  const { execSync } = require('child_process');
  return require(path.join(execSync('npm root -g').toString().trim(), 'playwright'));
}
const { chromium } = resolvePlaywright();

const root = path.resolve(process.argv[2] || '../../../public/assets/shots');
const quality = parseFloat(process.argv[3] || '0.92');

function walk(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const p = path.join(dir, e.name);
    return e.isDirectory() ? walk(p) : p.endsWith('.png') ? [p] : [];
  });
}

(async () => {
  const files = walk(root);
  if (!files.length) return console.log('niente da convertire in', root);
  const browser = await chromium.launch({ executablePath: process.env.PLAYWRIGHT_CHROMIUM_PATH || undefined });
  const page = await browser.newPage();
  let before = 0, after = 0;
  for (const file of files) {
    const png = fs.readFileSync(file);
    const data = await page.evaluate(async (b64) => {
      const img = new Image();
      img.src = 'data:image/png;base64,' + b64;
      await img.decode();
      const canvas = document.createElement('canvas');
      canvas.width = img.naturalWidth;
      canvas.height = img.naturalHeight;
      canvas.getContext('2d').drawImage(img, 0, 0);
      return canvas.toDataURL('image/webp', 0.92).split(',')[1];
    }, png.toString('base64')).catch((e) => { throw e; });
    const webp = Buffer.from(data, 'base64');
    fs.writeFileSync(file.replace(/\.png$/, '.webp'), webp);
    fs.unlinkSync(file);
    before += png.length; after += webp.length;
    console.log('✓', path.relative(root, file).replace(/\.png$/, '.webp'),
      `${(png.length / 1024).toFixed(0)} → ${(webp.length / 1024).toFixed(0)} KB`);
  }
  await browser.close();
  console.log(`\nTotale: ${(before / 1048576).toFixed(1)} MB → ${(after / 1048576).toFixed(1)} MB`);
})().catch((e) => { console.error(e); process.exit(1); });
