# 💬 YouAndMe - App di Messaggistica Privata E2E

App di messaggistica privata per due persone con crittografia end-to-end e pairing tramite QR code.

[![Status](https://img.shields.io/badge/status-v1.0--stable-success)](./MILESTONE.md)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-blue)](https://flutter.dev)
[![Firebase](https://img.shields.io/badge/Firebase-Firestore-orange)](https://firebase.google.com)

---

## ✨ Caratteristiche Principali

- 🔐 **Crittografia End-to-End** con AES-256-GCM
- 📱 **Pairing tramite QR Code** - zero configurazione
- 🔑 **Chiave famiglia condivisa (K_family)** - un solo QR per entrambi i dispositivi
- ☁️ **Firestore real-time** - sincronizzazione istantanea
- 🚫 **Zero backend** - nessun server, solo database cloud
- 🔒 **Storage sicuro** - chiavi memorizzate con flutter_secure_storage
- 📲 **Cross-platform** - iOS e Android

---

## 🏗️ Architettura

### Stack Tecnologico
- **Frontend:** Flutter 3.x
- **Database:** Google Cloud Firestore (real-time)
- **Crittografia:** AES-256-GCM (PointyCastle)
- **Storage Locale:** flutter_secure_storage
- **QR Code:** qr_flutter + mobile_scanner
- **State Management:** Provider

### Build System
- **Gradle:** 8.11.1
- **Android Gradle Plugin:** 8.9.1
- **Kotlin:** 2.1.0
- **AndroidX:** abilitato

---

## 🔐 Sistema di Sicurezza

### Crittografia K_family (Chiave Famiglia)

L'app utilizza un sistema semplificato basato su una **chiave famiglia condivisa**:

1. **Generazione K_family**
   - Un dispositivo genera una chiave AES-256 casuale (K_family)
   - La chiave viene codificata in un QR code

2. **Pairing**
   - Il secondo dispositivo scansiona il QR code
   - Entrambi memorizzano K_family localmente in modo sicuro

3. **Chat ID condiviso**
   - `family_chat_id = SHA-256(K_family)`
   - Entrambi i dispositivi usano lo stesso chat ID su Firestore

4. **Messaggi cifrati**
   - Ogni messaggio viene cifrato con AES-256-GCM usando K_family
   - Nonce unico per ogni messaggio (12 bytes)
   - Tag di autenticazione (16 bytes)
   - Formato: `{ciphertext, nonce, tag}`

5. **Storage Firestore**
   ```
   families/{family_chat_id}/messages/{message_id}
   ```
   - Solo messaggi cifrati vengono salvati
   - Nessuna informazione in chiaro
   - Il server NON può decifrare i messaggi

---

## 📁 Struttura del Progetto

```
youandme/
├── README.md                    # Questo file
├── MILESTONE.md                 # Documentazione v1.0 stable
├── flutter-app/                 # App Flutter
│   ├── lib/
│   │   ├── main.dart           # Entry point + AuthWrapper
│   │   ├── models/
│   │   │   └── message.dart    # Message data model
│   │   ├── screens/
│   │   │   ├── chat_screen.dart              # Main chat UI
│   │   │   ├── pairing_choice_screen.dart    # Scelta metodo pairing
│   │   │   ├── qr_display_screen.dart        # Mostra QR (creator)
│   │   │   └── qr_scanner_screen.dart        # Scansiona QR (joiner)
│   │   └── services/
│   │       ├── pairing_service.dart          # K_family + QR logic
│   │       ├── chat_service.dart             # Firestore messaging
│   │       └── encryption_service.dart       # AES-256-GCM
│   ├── android/                 # Configurazione Android
│   │   ├── app/
│   │   │   ├── build.gradle
│   │   │   └── google-services.json         # Firebase config
│   │   ├── gradle.properties                 # AndroidX enabled
│   │   └── settings.gradle                   # AGP + Kotlin versions
│   └── pubspec.yaml             # Flutter dependencies
└── _archive/                    # Vecchi file (backend Node.js, docs obsolete)
```

---

## 🚀 Setup

### Prerequisiti
- Flutter 3.x (stable channel)
- Android Studio / Xcode
- Progetto Firebase con Firestore abilitato

### 1. Clone e Setup Flutter

```bash
git clone https://github.com/donpablitoooooooo/youandme.git
cd youandme/flutter-app
flutter pub get
```

### 2. Configurazione Firebase

1. Vai su [Firebase Console](https://console.firebase.google.com)
2. Crea un nuovo progetto (o usa uno esistente)
3. Abilita **Firestore Database**
4. Scarica `google-services.json` (Android) e mettilo in `android/app/`
5. Scarica `GoogleService-Info.plist` (iOS) e mettilo in `ios/Runner/`

### 3. Firestore Security Rules

Imposta le regole di sicurezza in Firebase Console:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Allow read/write to family messages
    match /families/{familyId}/messages/{messageId} {
      allow read, write: if true;
    }
  }
}
```

> **Nota:** Queste regole sono permissive per semplicità. Per produzione, aggiungi autenticazione Firebase.

### 4. Build e Run

```bash
# Android
flutter run

# iOS (solo su macOS)
flutter run -d ios

# Build APK release
flutter build apk --release
```

---

## 📱 Come Usare l'App

### Primo avvio - Pairing

1. **Sul primo telefono:**
   - Apri l'app
   - Premi "Creo io la chiave famiglia"
   - Mostra il QR code

2. **Sul secondo telefono:**
   - Apri l'app
   - Premi "Leggo la chiave famiglia"
   - Scansiona il QR code

3. **Entrambi i telefoni:**
   - Verranno automaticamente portati alla chat
   - Ora potete inviarvi messaggi cifrati!

### Invio Messaggi

- Scrivi il messaggio nella casella di testo
- Premi il pulsante di invio
- Il messaggio viene automaticamente cifrato con K_family
- Appare istantaneamente sull'altro telefono (decifrato)

---

## 🔧 Configurazione Milestone v1.0

Per dettagli completi sulla configurazione stabile (versioni Gradle, bug fix, etc.), consulta:

📖 **[MILESTONE.md](./MILESTONE.md)**

---

## 🛠️ Troubleshooting

### Build fallisce con errori Gradle

La configurazione corretta è documentata in [MILESTONE.md](./MILESTONE.md). Verifica:
- Gradle 8.11.1
- AGP 8.9.1
- Kotlin 2.1.0
- AndroidX abilitato

Per ripristinare configurazione funzionante:
```bash
git checkout v1.0-stable
```

### Messaggi non si decifrano

Verifica che:
1. Entrambi i dispositivi abbiano scansionato lo stesso QR code
2. K_family sia presente in entrambi: verifica i log
3. Firestore security rules permettano accesso a `families/{familyId}/messages`

### Firestore Permission Denied

Aggiorna le security rules come indicato nella sezione Setup.

---

## 📊 Features Status

### ✅ Implementato (v1.0)
- [x] Generazione K_family (AES-256)
- [x] QR code pairing
- [x] Encryption/Decryption AES-256-GCM
- [x] Firestore real-time messaging
- [x] Chat UI con messaggi cifrati
- [x] Navigazione post-pairing
- [x] Storage sicuro chiavi
- [x] Build Android funzionante

### 🚧 Roadmap Future
- [ ] Autenticazione Firebase (optional)
- [ ] Supporto media (foto, video)
- [ ] Notifiche push
- [ ] Indicatori lettura/consegna
- [ ] Multiple device support
- [ ] iOS build completo

---

## 🐛 Bug Fix Critici (v1.0)

La versione stabile include fix per:

1. **GCM Tag Extraction** - Tag estratto dalla posizione corretta usando output size effettivo
2. **Decryption Truncation** - Aggiunto return value di `doFinal()` all'offset
3. **QR Creator Navigation** - `popUntil()` invece di `pop()` per routing corretto
4. **isPaired State** - Auto-set quando K_family viene generata
5. **BigInt Conversion** - Uso di `valueAsBigInteger!` invece di `intValue`

Dettagli completi in [MILESTONE.md](./MILESTONE.md#4-errori-e-fix).

---

## 📄 License

Uso privato personale.

---

## 🤝 Supporto

Per problemi o domande:
1. Verifica [MILESTONE.md](./MILESTONE.md) per configurazione e troubleshooting
2. Controlla la sezione [Troubleshooting](#-troubleshooting)
3. Verifica i log Flutter: `flutter logs`

---

**Versione:** 1.0 Stable
**Ultima modifica:** 2025-12-10
**Commit milestone:** `9f6cd74`
