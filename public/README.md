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
| `privacy-it.html` | Privacy policy italiana |
| `privacy-en.html` | Privacy policy inglese |
| `privacy-es.html` | Privacy policy spagnola |
| `privacy-ca.html` | Privacy policy catalana |
| `logo.png` | Logo app |

## Checklist Prima del Deploy

- [ ] Aggiornare versione in tutti i 4 file HTML (index, en, es, ca)
- [ ] Aggiornare box "Novita'" con nuove features
- [ ] Aggiornare footer con versione corrente
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
