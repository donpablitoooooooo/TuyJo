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

Due target non vanno negli store ma nel **sito** (`public/assets/`), e per questo
si lanciano con `--out ../../../public/assets`:

| Target | Formato | A cosa serve |
|---|---|---|
| `web` | PNG trasparente, ritagliato sul telefono | `assets/shots/<lingua>/0N-<lingua>.png` — una schermata per sezione del sito |
| `web-card` | PNG trasparente, ritaglio largo | `assets/shots/<lingua>/card-0N-<lingua>.png` — una porzione di schermata senza cornice (oggi: la galleria) |
| `web-pair` | PNG trasparente, due telefoni | `assets/shots/<lingua>/pair-01-<lingua>.png` — apertura della homepage |
| `og` | 1200 × 630 px | `assets/og-<lingua>.png` — anteprima social (`og:image`) |

Le schermate **7, 8, 9 e 10** (`--shot 7,8,9,10`) esistono solo per il sito e
servono alla scena dell'abbinamento. Sono tutte schermate vere dell'app
(`pairing_wizard_screen.dart`), non disegni:

| # | Cosa mostra |
|---|---|
| 7 | Lo scanner (`_buildQRScanner`) mentre cerca: dentro la fotocamera c'è il telefono dell'altra persona, di sbieco e fuori fuoco |
| 8 | Lo stesso scanner con il telefono inquadrato e a fuoco |
| 9 | Il wizard con il secondo passo completato (`_step2Completed`): pillola "Completato" e snackbar di conferma |
| 10 | La chat vista **dall'altro telefono**: i lati si scambiano, le spunte seguono chi guarda, e al posto di "sta scrivendo" c'è la bozza nella barra di scrittura |

Il telefono dentro la fotocamera è la stessa funzione `pairingScreen()`,
rimpicciolita e inclinata in 3D: quello che la fotocamera inquadra coincide con
il telefono che il sito mostra lì accanto. Gli store si fermano a sei schermate,
quindi il target predefinito non genera queste quattro.

## Alleggerire per il web

I PNG del sito pesano troppo (13,8 MB per quattro lingue). `webp.js` li converte
in WebP usando Chromium come codificatore — così non serve installare `cwebp` —
e cancella i PNG:

```bash
node webp.js ../../../public/assets/shots      # 13,8 MB → 2,4 MB
```

Va rilanciato ogni volta che si rigenerano le immagini `web*`. Gli screenshot
per gli store restano PNG: Play Console e App Store Connect vogliono quelli.

A differenza degli screenshot per gli store, le immagini `web` **non contengono
il titolo marketing**: sul sito il testo è HTML, così resta selezionabile,
traducibile e indicizzabile. L'ombra non è cotta nell'immagine, la disegna il CSS
(`filter: drop-shadow`) seguendo l'alpha del PNG.

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

Opzioni: `--lang it,en,es,ca`, `--target ios,ios-6.5,ipad,android,android-tablet,feature,web,web-pair,og`,
`--shot 1..6`, `--out <cartella>`. Con `PLAYWRIGHT_CHROMIUM_PATH` si indica un
eseguibile Chromium alternativo.

Per controllare una schermata nel browser:
`src/index.html?device=iphone&lang=it&shot=3` (device: `iphone`, `android`,
`ipad`, `tablet`, `feature`, `web`, `webpair`, `og`).

## Modificare testi o schermate

- Titoli marketing: oggetto `COPY` in `index.html` (per lingua e schermata);
  la parte tra `<em>…</em>` viene resa in corsivo serif come sul sito. Il target
  `og` usa invece l'oggetto `OG`, allineato al claim del sito.
- Testi dentro l'app: oggetto `UI` (stringhe reali dell'app + messaggi demo).
- Schermate: funzioni `chatScreen`, `callScreen`, `locationScreen`,
  `calendarScreen`, `mediaScreen`, `pairingScreen`, `scannerScreen` (la settima,
  solo per il sito). Le misure sono in px
  logici Flutter (larghezza 390 su telefono) e vengono scalate con `zoom`.
- Font e icone sono in `src/fonts/` (Google Fonts + Material Icons, uso offline).
