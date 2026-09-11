# Screenshot per App Store e Google Play

Gli screenshot degli store vengono generati da `src/index.html`: una pagina HTML
che riproduce le schermate reali dell'app (colori, raggi, icone Material e
stringhe dei file `.arb`) dentro una cornice di dispositivo, con i titoli e la
palette del sito (`public/styles.css`: carta, teal, ciliegia; font Bricolage
Grotesque, Hanken Grotesk, Instrument Serif).

## Output (`out/`)

| Cartella | Formato | Dove si carica |
|---|---|---|
| `ios/iphone-6.9/<lingua>/` | 1320 × 2868 px | App Store Connect → iPhone 6,9" (Apple lo riadatta ai formati minori) |
| `ios/iphone-6.5/<lingua>/` | 1284 × 2778 px | App Store Connect → iPhone 6,5" (se la scheda chiede questo formato) |
| `ios/ipad-13/<lingua>/` | 2064 × 2752 px | App Store Connect → iPad 13" |
| `android/phone/<lingua>/` | 1080 × 1920 px (9:16) | Play Console → Screenshot telefono |
| `android/tablet-10/<lingua>/` | 1600 × 2560 px | Play Console → Screenshot tablet 10" |
| `android/feature-graphic/<lingua>/` | 1024 × 500 px | Play Console → Immagine in evidenza |

Lingue: `it`, `en`, `es`, `ca`. Sei schermate per lingua, nell'ordine
consigliato per la scheda: chat, chiamata vocale, posizione live, promemoria
condivisi, galleria, abbinamento QR.

## Rigenerare

Servono Node 18+ e Playwright con Chromium:

```bash
npm i -g playwright
npx playwright install chromium
cd store/screenshots/src
node render.js                       # tutto
node render.js --lang it --target ios --shot 1,2   # sottoinsieme
```

Opzioni: `--lang it,en,es,ca`, `--target ios,ios-6.5,ipad,android,android-tablet,feature`,
`--shot 1..6`, `--out <cartella>`. Con `PLAYWRIGHT_CHROMIUM_PATH` si indica un
eseguibile Chromium alternativo.

Per controllare una schermata nel browser:
`src/index.html?device=iphone&lang=it&shot=3` (device: `iphone`, `android`,
`ipad`, `tablet`, `feature`).

## Modificare testi o schermate

- Titoli marketing: oggetto `COPY` in `index.html` (per lingua e schermata);
  la parte tra `<em>…</em>` viene resa in corsivo serif come sul sito.
- Testi dentro l'app: oggetto `UI` (stringhe reali dell'app + messaggi demo).
- Schermate: funzioni `chatScreen`, `callScreen`, `locationScreen`,
  `calendarScreen`, `mediaScreen`, `pairingScreen`. Le misure sono in px
  logici Flutter (larghezza 390 su telefono) e vengono scalate con `zoom`.
- Font e icone sono in `src/fonts/` (Google Fonts + Material Icons, uso offline).
