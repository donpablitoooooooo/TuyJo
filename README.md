# 💬 YouAndMe - App di Messaggistica Privata E2E

App di messaggistica privata per due persone con crittografia end-to-end e pairing tramite QR code.

[![Status](https://img.shields.io/badge/status-v1.2--stable-success)](./MILESTONE.md)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-blue)](https://flutter.dev)
[![Firebase](https://img.shields.io/badge/Firebase-Firestore-orange)](https://firebase.google.com)

---

## ✨ Caratteristiche Principali

- 🔐 **Crittografia End-to-End** con RSA-2048 + AES-256
- 🔑 **Architettura RSA-only** - QR code contiene solo chiavi pubbliche (SICURO)
- 🔄 **Dual Encryption** - mittente e destinatario possono sempre decifrare i loro messaggi
- 📱 **Pairing tramite QR Code** - wizard guidato con checklist
- ☁️ **Firestore real-time** - sincronizzazione istantanea
- 🔔 **Notifiche Push** - Firebase Cloud Messaging per nuovi messaggi
- 🚫 **Zero backend** - solo Cloud Functions serverless
- 🔒 **Storage sicuro** - chiavi memorizzate con flutter_secure_storage
- 📲 **Cross-platform** - iOS e Android
- 📑 **Bottom Navigation** - tab Chat e Impostazioni

---

## 🏗️ Architettura

### Stack Tecnologico
- **Frontend:** Flutter 3.x
- **Database:** Google Cloud Firestore (real-time)
- **Crittografia:** RSA-2048 + AES-256 (PointyCastle)
- **Storage Locale:** flutter_secure_storage
- **Notifiche:** Firebase Cloud Messaging + flutter_local_notifications
- **Cloud Functions:** Node.js 18 (serverless)
- **QR Code:** qr_flutter + mobile_scanner
- **State Management:** Provider

### Build System
- **Gradle:** 8.11.1
- **Android Gradle Plugin:** 8.9.1
- **Kotlin:** 2.1.0
- **AndroidX:** abilitato

---

## 🔐 Sistema di Sicurezza (v1.2)

### Architettura RSA-only con Dual Encryption

L'app utilizza un sistema **ibrido RSA + AES** completamente sicuro:

#### 1. **Generazione Chiavi RSA**
- Ogni dispositivo genera una coppia RSA-2048 (pubblica + privata)
- La chiave privata NON viene mai condivisa
- Solo la chiave pubblica viene scambiata tramite QR code

#### 2. **Pairing Sicuro**
- **Dispositivo A:** Mostra QR con la propria chiave pubblica RSA
- **Dispositivo B:** Scansiona il QR e importa la chiave pubblica di A
- **Dispositivo B:** Mostra il proprio QR con la sua chiave pubblica RSA
- **Dispositivo A:** Scansiona il QR e importa la chiave pubblica di B
- ✅ Nessuna chiave simmetrica condivisa nel QR (SICURO!)

#### 3. **Chat ID Condiviso**
- `family_chat_id = SHA-256(sorted([publicKey_A, publicKey_B]))`
- Entrambi i dispositivi calcolano lo stesso ID deterministicamente

#### 4. **Hybrid Encryption + Dual Encryption**

Ogni messaggio:
1. Genera una **chiave AES-256 casuale** univoca
2. Cifra il messaggio con **AES-256** (veloce)
3. Cifra la chiave AES **DUE volte** con RSA:
   - Una volta con la chiave pubblica del **mittente** → `encrypted_key_sender`
   - Una volta con la chiave pubblica del **destinatario** → `encrypted_key_recipient`
4. Salva su Firestore:
   ```json
   {
     "encrypted_key_sender": "...",    // Per il mittente
     "encrypted_key_recipient": "...", // Per il destinatario
     "iv": "...",
     "message": "..."                  // Cifrato con AES
   }
   ```

#### 5. **Decifrazione**
- Il **mittente** usa `encrypted_key_sender` + la propria chiave privata RSA
- Il **destinatario** usa `encrypted_key_recipient` + la propria chiave privata RSA
- Entrambi possono decifrare usando la stessa chiave AES
- ✅ Funziona anche dopo riavvio app (no cache!)

#### 6. **Vantaggi Sicurezza**
- ✅ **Zero chiavi simmetriche nel QR** (nessun rischio di intercettazione)
- ✅ **Forward secrecy** (ogni messaggio ha chiave AES univoca)
- ✅ **Dual encryption** (mittente può rileggere i propri messaggi)
- ✅ **Nessuna cache in chiaro** (tutto cifrato con RSA/AES)

---

## 🔔 Sistema di Notifiche Push

L'app implementa un sistema completo di notifiche push per avvisare gli utenti di nuovi messaggi:

### Architettura Notifiche

1. **Client (Flutter App)**
   - Richiede permessi per notifiche all'avvio
   - Ottiene un token FCM (Firebase Cloud Messaging) univoco per il dispositivo
   - Salva il token in Firestore: `/families/{familyChatId}/users/{userId}/fcm_token`
   - Mostra notifiche locali quando l'app è in foreground

2. **Server (Cloud Function)**
   - Trigger: creazione nuovo messaggio in `/families/{familyChatId}/messages/{messageId}`
   - Recupera il token FCM del destinatario (utente che NON ha inviato il messaggio)
   - Invia notifica push tramite Firebase Cloud Messaging
   - Gestisce token invalidi (li rimuove automaticamente dal database)

3. **Notifiche Locali**
   - Quando l'app è aperta (foreground), mostra notifiche locali
   - Quando l'app è in background, riceve notifiche push da FCM
   - Quando l'app è chiusa, riceve notifiche push che la possono riaprire

### Privacy e Sicurezza

- ✅ Le notifiche contengono solo metadati generici
- ✅ Il contenuto del messaggio NON viene mai incluso nella notifica
- ✅ Il messaggio rimane crittografato end-to-end
- ✅ Solo il titolo generico "💬 Nuovo messaggio" viene mostrato

### Gestione Token FCM

- I token vengono salvati automaticamente quando l'utente entra nella chat
- I token vengono aggiornati automaticamente quando cambiano
- I token invalidi vengono rimossi dalla Cloud Function

---

## 📁 Struttura del Progetto

```
youandme/
├── README.md                    # Questo file
├── MILESTONE.md                 # Documentazione v1.2 stable
├── flutter-app/                 # App Flutter
│   ├── lib/
│   │   ├── main.dart           # Entry point + bottom navigation
│   │   ├── models/
│   │   │   └── message.dart    # Message model (dual encryption)
│   │   ├── screens/
│   │   │   ├── chat_screen.dart              # Main chat UI
│   │   │   ├── settings_screen.dart          # Settings tab
│   │   │   ├── pairing_wizard_screen.dart    # Wizard pairing con checklist
│   │   │   ├── qr_display_screen.dart        # Mostra QR (public key)
│   │   │   └── qr_scanner_screen.dart        # Scansiona QR (public key)
│   │   └── services/
│   │       ├── pairing_service.dart          # RSA pairing logic
│   │       ├── chat_service.dart             # Firestore messaging + dual encryption
│   │       ├── encryption_service.dart       # RSA-2048 + AES-256
│   │       └── notification_service.dart     # FCM + notifiche locali
│   ├── android/                 # Configurazione Android
│   │   ├── app/
│   │   │   ├── build.gradle
│   │   │   └── google-services.json         # Firebase config
│   │   ├── gradle.properties                 # AndroidX enabled
│   │   └── settings.gradle                   # AGP + Kotlin versions
│   └── pubspec.yaml             # Flutter dependencies
├── functions/                   # Cloud Functions per notifiche push
│   ├── index.js                # Funzioni Firebase (sendMessageNotification)
│   ├── package.json            # Dipendenze Node.js
│   └── README.md               # Guida deploy Cloud Functions
├── firebase.json                # Configurazione Firebase
└── _archive/                    # Vecchi file (backend Node.js, docs obsolete)
```

---

## 🚀 Setup

### Prerequisiti
- Flutter 3.x (stable channel)
- Android Studio / Xcode
- Progetto Firebase con Firestore abilitato
- Firebase CLI (per deploy Cloud Functions): `npm install -g firebase-tools`
- Node.js 18+ (per Cloud Functions)

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
    // Allow read/write to FCM tokens
    match /families/{familyId}/users/{userId} {
      allow read, write: if true;
    }
  }
}
```

> **Nota:** Queste regole sono permissive per semplicità. Per produzione, aggiungi autenticazione Firebase.

### 4. Deploy Cloud Functions (per notifiche push)

```bash
# Installare dipendenze
cd functions
npm install

# Login a Firebase
firebase login

# Deploy delle Cloud Functions
firebase deploy --only functions
```

Per dettagli completi, consulta [functions/README.md](./functions/README.md).

### 5. Build e Run

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

### Primo avvio - Pairing (v1.2)

1. **Sul primo telefono:**
   - Apri l'app
   - Vai nella tab "Impostazioni"
   - Premi "Pairing guidato"
   - **Step 1:** Mostra il tuo QR code (chiave pubblica RSA)
   - Fai scansionare il QR al tuo partner
   - ✅ Step 1 completato

2. **Sul secondo telefono:**
   - Apri l'app
   - Vai nella tab "Impostazioni"
   - Premi "Pairing guidato"
   - **Step 2:** Premi "Scansiona QR del partner"
   - Scansiona il QR mostrato dal primo telefono
   - ✅ Step 2 completato

3. **Sul primo telefono (di nuovo):**
   - **Step 2:** Premi "Scansiona QR del partner"
   - Scansiona il QR del secondo telefono
   - ✅ Pairing completato!

4. **Entrambi i telefoni:**
   - Tornano automaticamente alla tab "Chat"
   - Ora potete inviarvi messaggi cifrati!

### Invio Messaggi

- Scrivi il messaggio nella casella di testo
- Premi il pulsante di invio
- Il messaggio viene automaticamente cifrato con RSA + AES hybrid encryption + dual encryption
- Appare istantaneamente sull'altro telefono (decifrato)
- Entrambi possono rileggere i messaggi anche dopo riavvio app

---

## 🔧 Configurazione Milestone v1.2

Per dettagli completi sulla configurazione stabile (dual encryption, RSA-only, bug fix, etc.), consulta:

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
git checkout v1.2-stable
```

### Messaggi non si decifrano

Verifica che:
1. Entrambi i dispositivi abbiano completato il pairing (scambiato le chiavi pubbliche RSA)
2. I log mostrino "✅ Message sent successfully with dual encryption"
3. Firestore security rules permettano accesso a `families/{familyId}/messages`

### Sender non può decifrare i propri messaggi

Se vedi `[Messaggio non decifrabile]` sui tuoi messaggi inviati:
1. Verifica che il messaggio sia stato inviato con dual encryption (v1.2+)
2. I vecchi messaggi (pre-v1.2) non sono decifrabili dal mittente

### Firestore Permission Denied

Aggiorna le security rules come indicato nella sezione Setup.

---

## 📊 Features Status

### ✅ Implementato (v1.2)
- [x] Architettura RSA-only (no chiavi simmetriche nel QR)
- [x] Dual encryption (sender + recipient access)
- [x] RSA-2048 key generation
- [x] Hybrid encryption (RSA + AES-256)
- [x] QR code pairing con chiavi pubbliche
- [x] Pairing wizard con checklist UI
- [x] Bottom navigation (Chat / Impostazioni)
- [x] Firestore real-time messaging
- [x] Chat UI con messaggi cifrati
- [x] Storage sicuro chiavi RSA
- [x] Build Android funzionante
- [x] **Notifiche push** (Firebase Cloud Messaging)
- [x] **Notifiche locali** (foreground + background)
- [x] **Cloud Functions** per invio notifiche automatico

### 🚧 Roadmap Future
- [ ] Autenticazione Firebase (optional)
- [ ] Supporto media (foto, video)
- [ ] Indicatori lettura/consegna
- [ ] Multiple device support
- [ ] iOS build completo
- [ ] Notifiche programmate e reminder
- [ ] Message deletion / editing
- [ ] Key rotation

---

## 🐛 Bug Fix Critici (v1.2)

La versione 1.2 include fix per:

1. **Dual Encryption Bug** - AES key encrypting mismatch
   - Problema: `encryptMessage()` chiamato due volte creava due chiavi AES diverse
   - Fix: Nuovo metodo `encryptMessageDual()` che genera UNA chiave AES e la cifra DUE volte
   - Risultato: Sender e recipient usano la stessa chiave AES (cifrata diversamente con RSA)

2. **ASN1 Public Key Parsing** - BitString decoding error
   - Problema: Errore nell'estrarre la chiave RSA dalla struttura ASN1 X.509
   - Fix: Usare `valueBytes()` e skippare solo il primo byte (padding)

3. **EncryptionService Dependency Injection**
   - Problema: ChatService creava nuova istanza senza chiavi caricate
   - Fix: Passare EncryptionService via constructor da main.dart

Dettagli completi in [MILESTONE.md](./MILESTONE.md#-bug-fix-critici).

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

**Versione:** 1.2 Stable
**Ultima modifica:** 2025-12-11
**Architettura:** RSA-only + Dual Encryption
