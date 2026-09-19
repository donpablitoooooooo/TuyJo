# Tuijo Website - Deployment Guide

## Quick Deploy

```bash
firebase deploy --only hosting
```

## Step-by-Step

### 1. Login (se non sei loggato)
```bash
firebase login
```

### 2. Verifica il progetto attivo
```bash
firebase projects:list
```
Deve essere selezionato: `youandme-b3b4c`

### 3. Deploy del sito
```bash
firebase deploy --only hosting
```

### 4. Verifica online
Il sito sara' disponibile su:
- https://youandme-b3b4c.web.app
- https://youandme-b3b4c.firebaseapp.com

## File del Sito

| File | Descrizione |
|------|-------------|
| `index.html` | Homepage italiana (default) |
| `en.html` | Homepage inglese |
| `es.html` | Homepage spagnola |
| `ca.html` | Homepage catalana |
| `site.css` / `site.js` | Stile e interazioni delle **quattro homepage** |
| `styles.css` / `app.js` | Stile e interazioni delle **pagine privacy** (impianto precedente) |
| `assets/shots/<lingua>/` | Schermate dell'app per il sito (WebP), generate da `store/screenshots` |
| `assets/og-<lingua>.png` | Immagine di anteprima social (`og:image`), 1200 × 630 |
| `assets/photo/` | Slot per la foto della banda — vedi il README lì dentro |
| `privacy-it-v1.1.html` | Privacy policy italiana |
| `privacy-en-v1.1.html` | Privacy policy inglese |
| `privacy-es-v1.1.html` | Privacy policy spagnola |
| `privacy-ca-v1.1.html` | Privacy policy catalana |

Le privacy policy hanno la versione nel nome del file (Play Console e App Store
vogliono un URL nuovo a ogni modifica). Per una nuova versione: copia i quattro
file con il nuovo suffisso, aggiorna i link in `index/en/es/ca.html` e nel
selettore lingua delle pagine privacy, e cambia i redirect in `firebase.json`
(i vecchi URL `privacy-<lingua>.html` restano validi).

## Modificare i testi delle homepage

Le quattro homepage **non si modificano a mano una per una**: sono generate da
un'unica struttura di testi, così le lingue non divergono. Lo script è
`store/site/build_site.py`:

```bash
python3 store/site/build_site.py     # riscrive index/en/es/ca.html
```

Le immagini delle schermate si rigenerano dal progetto degli screenshot:

```bash
cd store/screenshots/src
node render.js --target web,web-pair,web-card,og --out ../../../public/assets
node render.js --target web --shot 7,8,9,10 --out ../../../public/assets   # scena abbinamento
node webp.js ../../../public/assets/shots                                  # PNG → WebP
```

L'ultimo passaggio non è facoltativo: senza, le immagini del sito pesano sei
volte tanto. L'`og:image` resta PNG, perché non tutti i servizi di anteprima
social leggono WebP.

## Checklist Prima del Deploy

- [ ] Testi aggiornati in `store/site/build_site.py` e script rilanciato
- [ ] Schermate rigenerate se l'interfaccia dell'app è cambiata
- [ ] Testare in locale (opzionale): `firebase serve`

## Preview Locale (Opzionale)

```bash
firebase serve --only hosting
```
Apri http://localhost:5000

## Troubleshooting

**Errore "not logged in":**
```bash
firebase login
```

**Errore "project not found":**
```bash
firebase use youandme-b3b4c
```

**Vedere lo stato del deploy:**
```bash
firebase hosting:channel:list
```
