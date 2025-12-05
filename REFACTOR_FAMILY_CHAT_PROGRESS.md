# 🚀 Family Chat - Refactoring Progress

## ✅ LAVORO COMPLETATO

### 📦 Backend (100% completato)

**File modificati:**
- `messaging-app/backend/services/userService.js` ✅
- `messaging-app/backend/services/messageService.js` ✅
- `messaging-app/backend/routes/auth.js` ✅
- `messaging-app/backend/routes/messages.js` ✅
- `messaging-app/backend/server.js` ✅
- `messaging-app/backend/package.json` ✅
- `messaging-app/backend/firestore.indexes.json` ✅ (nuovo)

**Modifiche implementate:**

#### 1. **Identità utente**
- ✅ `user_id = SHA-256(pubKey)` invece di UUID random
- ✅ Rimosso campo `username` completamente
- ✅ Database: solo `user_id`, `public_key`, `created_at`

#### 2. **Autenticazione challenge/response**
- ✅ `POST /api/auth/register` - registra con solo publicKey
- ✅ `POST /api/auth/request` - genera challenge (32 byte, scadenza 2 min)
- ✅ `POST /api/auth/verify` - verifica firma RSA-SHA256, rilascia JWT (30 giorni)
- ✅ Collection `challenges` in Firestore per challenge temporanei

#### 3. **Formato messaggi cifrati**
- ✅ Nuovo schema: `{recipient_id, ciphertext, nonce, tag, created_at}`
- ✅ Rimosso `senderId` (privacy - non visibile al server)
- ✅ `POST /api/messages` - invia messaggio cifrato
- ✅ `GET /api/messages/inbox` - ricevi messaggi

#### 4. **WebSocket real-time**
- ✅ Sostituito Socket.io con WebSocket puro (`ws` library)
- ✅ Autenticazione JWT via query param `?token=JWT`
- ✅ Heartbeat ogni 30 secondi per detect broken connections
- ✅ Notifica real-time quando arriva nuovo messaggio

#### 5. **Database**
- ✅ Indice composito Firestore: `recipient_id ASC, created_at DESC`
- ✅ File `firestore.indexes.json` creato

---

### 📱 Frontend (75% completato)

**File modificati:**
- `messaging-app/flutter-app/pubspec.yaml` ✅
- `messaging-app/flutter-app/lib/services/encryption_service.dart` ✅
- `messaging-app/flutter-app/lib/services/pairing_service.dart` ✅ (nuovo)
- `messaging-app/flutter-app/lib/services/auth_service.dart` ✅

**Modifiche implementate:**

#### 1. **Dipendenze aggiornate**
- ✅ Rimosso: `socket_io_client`, `encrypt`, `firebase_core`, `firebase_messaging`
- ✅ Aggiunto: `web_socket_channel`, `qr_flutter`, `mobile_scanner`
- ✅ Mantenuto: `pointycastle`, `crypto`, `flutter_secure_storage`

#### 2. **EncryptionService (encryption_service.dart)**
- ✅ RSA-2048 keypair generation
- ✅ `generateKFamily()` - genera chiave simmetrica K_family (32 byte)
- ✅ `encryptMessage()` - AES-256-GCM con K_family → {ciphertext, nonce, tag}
- ✅ `decryptMessage()` - AES-256-GCM decryption
- ✅ `signChallenge()` - firma RSA-SHA256 per challenge/response
- ✅ `getUserId(publicKey)` - calcola SHA-256(pubKey)
- ✅ Storage e loading di K_family

#### 3. **PairingService (pairing_service.dart)**
- ✅ `generateQRData()` - crea JSON per QR code: `{user_id, k_family}`
- ✅ `generatePartnerQRData()` - crea JSON QR secondo utente: `{user_id}`
- ✅ `scanFirstUserQR()` - scansiona QR primo utente, salva K_family + partner_user_id
- ✅ `scanPartnerQR()` - scansiona QR secondo utente, salva partner_user_id
- ✅ `savePartnerNickname()` - salva nickname locale per partner
- ✅ Storage sicuro: `k_family`, `partner_user_id`, `partner_nickname`

#### 4. **AuthService (auth_service.dart)**
- ✅ `register()` - genera RSA keypair, registra, ritorna `{user_id, private_key}`
- ✅ `login(privateKey)` - challenge/response authentication
  - Richiede challenge dal server
  - Firma challenge con RSA-SHA256
  - Verifica firma e ottiene JWT
- ✅ Rimosso completamente concetto di username
- ✅ Storage: `user_id`, `jwt_token`, `private_key`

---

## 🚧 LAVORO RIMANENTE

### Frontend (25% rimanente)

#### 1. **WebSocketService** (da creare)
```dart
// messaging-app/flutter-app/lib/services/websocket_service.dart
- Connessione WebSocket con JWT
- Gestione eventi new_message
- Auto-reconnect
- Heartbeat/pong
```

#### 2. **UI Screens** (da creare/modificare)

**Pairing Screen** (nuovo)
```dart
// messaging-app/flutter-app/lib/screens/pairing_screen.dart
- Mostra QR code con {user_id, k_family} (primo utente)
- Scanner QR code del partner
- Doppia scansione (Alice scansiona Bob, Bob scansiona Alice)
- Input nickname per partner
```

**Start Screen** (nuovo)
```dart
// messaging-app/flutter-app/lib/screens/start_screen.dart
- Bottone "Nuova Registrazione" → genera keypair, mostra QR, salva
- Bottone "Login con Chiave" → incolla chiave privata
- Bottone "Pairing" → vai a pairing screen se già registrato
```

**Chat Screen** (da modificare)
```dart
// messaging-app/flutter-app/lib/screens/chat_screen.dart
- Usare WebSocketService invece di Socket.io
- Cifrare messaggi con encryptionService.encryptMessage()
- Inviare via POST /messages con {recipient_id, ciphertext, nonce, tag}
- Decifrare messaggi ricevuti
- Mostrare nickname partner invece di username
```

---

## 📋 COMMIT EFFETTUATI

1. **ba19306** - `Refactor: Implementa architettura Family Chat backend`
2. **b262a0f** - `Fix: Rimuovi whitespace da chiave privata incollata`
3. **37847d6** - `WIP: Frontend refactor - encryption + pairing services`
4. **f5d17a5** - `Refactor: AuthService con challenge/response`

---

## 🎯 PROSSIMI STEP

### 1. Completare frontend
- [ ] Creare `websocket_service.dart`
- [ ] Creare `pairing_screen.dart`
- [ ] Creare `start_screen.dart`
- [ ] Modificare `chat_screen.dart`
- [ ] Commit finale frontend

### 2. Testing
- [ ] Testare registrazione Alice
- [ ] Testare registrazione Bob
- [ ] Testare pairing (doppia scansione QR)
- [ ] Testare invio/ricezione primo messaggio
- [ ] Testare real-time WebSocket
- [ ] Testare login con chiave privata

### 3. Deploy
- [ ] Deploy backend su Cloud Run
- [ ] Testare con backend production

---

## 🗄️ SCHEMA DATABASE FINALE

### Firestore Collections:

**users:**
```json
{
  "user_id": "sha256(publicKey)",
  "public_key": "base64...",
  "created_at": "2025-12-05T10:00:00Z"
}
```

**messages:**
```json
{
  "message_id": "uuid",
  "recipient_id": "sha256(publicKey)",
  "ciphertext": "base64...",
  "nonce": "base64 (12 byte)",
  "tag": "base64 (16 byte)",
  "created_at": "2025-12-05T10:00:00Z"
}
```

**challenges:**
```json
{
  "user_id": "sha256(publicKey)", // document ID
  "challenge": "base64 (32 byte)",
  "expires_at": "2025-12-05T10:02:00Z",
  "created_at": "2025-12-05T10:00:00Z"
}
```

---

## 🔒 SECURITY FEATURES IMPLEMENTATE

- ✅ Zero username/email/password
- ✅ Identità basata su chiave pubblica
- ✅ Challenge/response authentication (RSA-SHA256)
- ✅ End-to-end encryption (AES-256-GCM con K_family)
- ✅ Server non conosce mai K_family
- ✅ Server non conosce mittente messaggi
- ✅ JWT con scadenza 30 giorni
- ✅ Challenge scadono dopo 2 minuti
- ✅ Storage sicuro chiavi (Keychain/KeyStore)

---

## 📱 FLUSSO UTENTE FINALE

### Prima volta (Onboarding):

**Alice (primo utente):**
1. Apre app → "Nuova Registrazione"
2. App genera RSA keypair + K_family
3. App mostra QR code: `{user_id_A, k_family}`
4. App mostra chiave privata con bottone "Copia"
5. Alice salva chiave privata (foto/appunti)

**Bob (secondo utente):**
1. Apre app → "Nuova Registrazione"
2. App genera RSA keypair
3. Bob scansiona QR di Alice → riceve K_family + user_id_A
4. App mostra QR con `{user_id_B}`
5. Alice scansiona QR di Bob → riceve user_id_B
6. ✅ Pairing completato! Entrambi hanno K_family + user_id partner

### Dopo setup:
- Login con chiave privata (incolla o carica)
- Chat cifrata con K_family
- Real-time via WebSocket

---

**Lavoro svolto da Claude mentre l'utente era a prendere la piccola a scuola** 🚸
