# 📸 Guida Screenshot per Play Store

## 🎯 Requisiti Google Play Store

**Minimo richiesto:**
- 2 screenshot per lingua
- Dimensioni: min 320px, max 3840px
- Ratio: 16:9 o 9:16 (verticale consigliato)
- Formato: PNG o JPEG (24-bit)

**Consigliato:**
- 4-8 screenshot che mostrano le funzionalità principali
- 1280x720 o 1920x1080 per alta qualità

---

## 🚀 METODO VELOCE - Usa l'emulatore

### 1. Avvia l'app in debug
```bash
cd /home/user/TuyJo/flutter-app
flutter run
```

### 2. Fai screenshot con il tasto S
- Mentre l'app è in esecuzione, premi **S** nel terminale
- Gli screenshot vanno in: `screenshots/screenshot-*.png`
- Oppure usa il comando: `flutter screenshot`

### 3. Screenshot suggeriti per TuyJo:

**Screenshot 1 - Chat**
- Mostra la schermata chat con alcuni messaggi
- Evidenzia la crittografia end-to-end

**Screenshot 2 - TODO Calendar**
- Calendario con alcuni TODO
- Mostra le notifiche e reminder

**Screenshot 3 - Couple Selfie**
- Schermata di pairing con QR code
- Oppure foto profilo condivisa

**Screenshot 4 - Galleria Media**
- Griglia 3x3 con foto/video
- Mostra il visualizzatore integrato

**Screenshot 5 - Menu**
- Drawer aperto con logo TuyJo e colori teal
- Mostra tutte le voci del menu

---

## 🎨 ALTERNATIVA - Dispositivo reale

### Android:
1. Collega il telefono via USB
2. Abilita Debug USB nelle Impostazioni Sviluppatore
3. `flutter run` per installare l'app
4. Usa **Power + Volume Giù** per screenshot
5. Screenshot salvati in Galleria

### iOS:
1. Collega iPhone/iPad
2. `flutter run` per installare
3. Usa **Power + Volume Su** per screenshot
4. Screenshot in app Foto

---

## 📐 METODO PROFESSIONALE - Con frame

Se vuoi screenshot con frame del telefono (più belli):

### Online (facile):
1. Vai su https://screenshots.pro o https://mockuphone.com
2. Carica i tuoi screenshot
3. Scegli modello telefono (Pixel, iPhone, etc.)
4. Scarica con il frame

### Con fastlane (automatico):
```bash
# Installa fastlane
gem install fastlane

# Genera screenshot automaticamente
fastlane snapshot
```

---

## 📊 Risoluzione consigliata per lingua

**Italiano (IT):** 4 screenshot
**English (EN):** 4 screenshot
**Español (ES):** 4 screenshot
**Català (CA):** 4 screenshot

Puoi usare gli **stessi screenshot** per tutte le lingue se i testi nell'app si adattano automaticamente!

---

## ✅ Checklist prima dell'upload

- [ ] Minimo 2 screenshot per lingua
- [ ] Risoluzione minima 320px
- [ ] Formato PNG/JPEG
- [ ] Screenshot mostrano le funzionalità principali
- [ ] Nessuna informazione personale/sensibile visibile
- [ ] Screenshot in verticale (9:16 ratio)

---

## 🎨 BONUS - Feature Graphic (1024x500)

Google richiede anche una **feature graphic** (banner promozionale):

**Opzione 1 - Crea con Canva:**
1. Vai su canva.com
2. Crea design 1024x500
3. Aggiungi logo TuyJo
4. Usa colori teal (#3BA8B0 → #145A60)
5. Testo: "TuyJo - Chat Privata per Coppie"

**Opzione 2 - Uso il logo:**
- Usa `youandme/iconstuyjo/youandme_1024.png`
- Aggiungi sfondo gradiente teal
- Tool online: photopea.com (gratis, come Photoshop)

---

## 🚀 Comando rapido per screenshot

```bash
# Avvia app
flutter run

# In un altro terminale, fai screenshot quando vuoi
flutter screenshot --out=screenshot-$(date +%s).png

# Oppure premi 's' nel terminale dove gira flutter run
```

---

**Ricorda:** Gli screenshot sono **FONDAMENTALI** per convincere gli utenti a scaricare l'app! Mostra le funzionalità migliori! 🎯
