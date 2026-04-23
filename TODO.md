# 📋 TODO - YouAndMe App

Lista task e miglioramenti futuri per l'app di messaggistica.

---

## 🧹 Prima della prossima release NON-TestFlight (App Store produzione)

### Rimuovere i log diagnostici `TuyJo.archive`
**Aggiunti in 1.31.0+37** per capire perché il pagination archivio si blocca
a 100 messaggi dopo update TestFlight. Usano `developer.log` che va su os_log
(iOS) / logcat (Android): sono visibili anche in build release/TestFlight.

Costo in produzione: basso (poche chiamate per pagina di 100 messaggi), ma
comunque rumore non necessario e leggera pressione sul logger di sistema.

**Da fare prima del prossimo invio in review App Store:**

1. **Log diagnostici** (`chat_service.dart`):
   - helper `_archiveLog()` + buffer `_archiveLogBuffer`
   - getter `archiveLogBuffer` e `archiveDiagnostics`
   - import `dart:developer`
   - Rimpiazza le chiamate a `_archiveLog(...)` con `if (kDebugMode) print(...)`
     (come era prima di 1.31.0+37).

2. **Pannello debug in-app** (`media_screen.dart`):
   - metodo `_showArchiveDebugSheet(...)`
   - `GestureDetector(onLongPress: ...)` che avvolge `_buildTabSelector()`
   - import `package:flutter/services.dart` (se non usato altrove)

Grep per trovare tutto:
```bash
grep -n "_archiveLog\|archiveLogBuffer\|archiveDiagnostics\|_showArchiveDebugSheet\|TuyJo.archive\|dart:developer" flutter-app/lib/services/chat_service.dart flutter-app/lib/screens/media_screen.dart
```

---

## 🚨 Priorità Alta

### 🌐 Niente spunta se offline
**Problema:** Le spunte di consegna/lettura vengono mostrate anche quando il dispositivo è offline, causando confusione.

**Soluzione:**
- Implementare `connectivity_plus` package per rilevare stato connessione
- Listener real-time per cambio stato (online/offline)
- UI indicator visivo (banner/icon) quando offline
- Bloccare invio spunte quando offline
- Queue delle spunte da inviare quando torna online
- Gray-out delle spunte durante offline

**File da modificare:**
- `pubspec.yaml`: Aggiungere `connectivity_plus: ^6.1.2`
- `chat_service.dart`: Aggiungere `_isOnline` state + connectivity listener
- `chat_screen.dart`: UI indicator offline + disable read receipts
- `message.dart`: Flag temporaneo `pendingReadReceipt`

**Riferimenti:**
- [connectivity_plus](https://pub.dev/packages/connectivity_plus)
- WhatsApp UX: mostra "In attesa di rete..." quando offline

---

### 🔐 Autenticazione anonima + Regole DB/Storage

**Problema:** Attualmente l'app non usa Firebase Auth, le regole sono `allow read, write: if true` (troppo permissive).

**Soluzione:**
1. **Firebase Anonymous Auth**
   - Sign in anonimo all'avvio app
   - Associare `userId` a UID Firebase Auth
   - Persistenza automatica (no re-login)

2. **Firestore Rules Aggiornate**
   ```javascript
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /families/{familyId} {
         allow list: if false; // Blocca enumerazione
         allow get: if request.auth != null; // Solo autenticati

         match /messages/{messageId} {
           allow read: if request.auth != null;
           allow write: if request.auth != null;
         }

         match /users/{userId} {
           allow read: if request.auth != null;
           allow write: if request.auth != null && request.auth.uid == userId;
         }

         match /read_receipts/{userId} {
           allow read: if request.auth != null;
           allow write: if request.auth != null && request.auth.uid == userId;
         }
       }
     }
   }
   ```

3. **Firebase Storage Rules Aggiornate**
   ```
   rules_version = '2';
   service firebase.storage {
     match /b/{bucket}/o {
       match /families/{familyChatId}/attachments/{type}/{allPaths=**} {
         // Autenticazione richiesta
         allow read: if request.auth != null;
         allow write: if request.auth != null;
       }
       match /{allPaths=**} {
         allow read, write: if false;
       }
     }
   }
   ```

**File da modificare:**
- `pubspec.yaml`: Verificare `firebase_auth: ^6.1.3` (già presente)
- `main.dart`: Sign in anonimo all'avvio
- `pairing_service.dart`: Usare `FirebaseAuth.instance.currentUser.uid` come userId
- `firestore.rules`: Aggiornare come sopra
- `storage.rules`: Aggiornare come sopra

**Testing:**
- ✅ Verifica accesso solo con auth
- ✅ Test offline → online (auto re-auth)
- ✅ Test uninstall → reinstall (nuovo UID anonimo, nuovo pairing)

**Riferimenti:**
- [Firebase Anonymous Auth](https://firebase.google.com/docs/auth/flutter/anonymous-auth)
- [Security Rules Best Practices](https://firebase.google.com/docs/rules/basics)

---

## 🎨 Media

### Prima botta di grafica (UI/UX Redesign)

**Obiettivo:** Modernizzare l'interfaccia con design professionale e coerente.

**Aree da migliorare:**

1. **🎨 Color Scheme & Branding**
   - Definire palette colori principale (non solo viola gradiente)
   - Typography system (font families, sizes, weights)
   - Iconografia consistente (Material vs Custom)
   - Dark mode support

2. **💬 Chat Screen Redesign**
   - Bubble messaggi più moderne (bordi, ombre, padding)
   - Avatar utenti (generati o iniziali)
   - Animazioni subtle per nuovi messaggi
   - Floating Action Button per scroll to bottom
   - Gesture swipe-to-reply (optional)

3. **📱 Bottom Navigation**
   - Icone custom invece di Material Icons base
   - Animazioni tab switching
   - Badge count per notifiche non lette
   - Haptic feedback

4. **⚙️ Settings Screen**
   - Card-based layout
   - Sezioni organizzate (Account, Privacy, Notifiche, Avanzate)
   - Toggle switches con animazioni
   - About section (versione, licenza, credits)

5. **📎 Attachments UI**
   - Preview più grandi in chat (max 300px invece di 200px?)
   - Video player inline (non solo icon)
   - Document preview con icone tipo-specifiche
   - Progress indicator durante upload

6. **🔔 Notifiche & Feedback**
   - Snackbar messages customizzate
   - Toast notifications per azioni (messaggio inviato, todo completato)
   - Shimmer loading invece di CircularProgressIndicator
   - Skeleton screens

**Riferimenti Design:**
- [Material Design 3](https://m3.material.io/)
- [Telegram UI/UX](https://telegram.org/)
- [Signal App Design](https://signal.org/)

**Tools:**
- Figma per mockup
- Flutter DevTools per performance
- `flutter_svg` per icone custom
- `shimmer` package per loading states

---

## 🚀 Feature Richieste

### 📹 Video Player Inline
- Riproduzione video direttamente in chat
- Controlli play/pause/fullscreen
- Thumbnail video generata da primo frame
- Package: `video_player` o `chewie`

### 🎤 Voice Messages
- Registrazione audio cifrato E2E
- Waveform visualization
- Playback speed (1x, 1.5x, 2x)
- Package: `record` + `just_audio`

### 🔄 Message Editing
- Edit messaggi entro 15 minuti
- Indicator "modificato" visibile
- History edits (optional)

### 🗑️ Message Deletion
- Delete for me / Delete for everyone
- Timeframe limit (es. 1h per delete for everyone)
- Placeholder "[Messaggio eliminato]"

### 🔑 Key Rotation
- Rigenera chiavi RSA periodicamente
- Re-encrypt messaggi con nuove chiavi
- Backup chiavi vecchie per messaggi storici

### 📱 Multiple Devices
- Sync tra più dispositivi dello stesso utente
- QR code per aggiungere device secondario
- End-to-end encryption mantenuta

### 👥 Group Chats (3+ persone)
- Family chat con 3-5 membri
- Dual encryption → Multi-recipient encryption
- Admin controls (add/remove members)

### 🔁 Recurring Reminders
- Todo ripetuti (giornalieri, settimanali, mensili)
- Pattern customizzati (es. ogni lunedì)
- Auto-reschedule dopo completamento

### 🤖 AI Todo Extraction
- Analisi messaggi per estrarre todo automatici
- "Ricordami di comprare il latte domani" → crea todo
- Integration con Gemini/OpenAI API (opzionale)

---

## 🐛 Bug Known

### Minor Issues
- [ ] Typing indicator a volte rimane bloccato se app crasha
- [ ] Read receipts non si aggiornano se messaggio arriva mentre app è killed
- [ ] Infinite scroll a volte carica duplicati (race condition?)

### Da Investigare
- [ ] Performance con 10.000+ messaggi (test stress)
- [ ] Memory leaks con troppi attachment in cache?
- [ ] Battery drain con listener Firestore real-time

---

## 📚 Documentazione

### Da Creare
- [ ] API Documentation (Dart doc comments)
- [ ] Architecture Decision Records (ADR)
- [ ] User Guide completa (con screenshots)
- [ ] Video tutorial setup e pairing
- [ ] Privacy Policy e Terms of Service (se pubblico)

### Da Aggiornare
- [x] README.md con v1.6.0 ✅
- [ ] MILESTONE.md con attachment feature
- [ ] TODO_FEATURE.md aggiornato

---

## 🧪 Testing

### Test da Implementare
- [ ] Unit tests per EncryptionService
- [ ] Unit tests per dual encryption logic
- [ ] Integration tests per pairing flow
- [ ] Widget tests per ChatScreen
- [ ] E2E tests con più dispositivi simulati

### Performance Testing
- [ ] Benchmark encryption/decryption speed
- [ ] Memory profiling con 1000+ messages
- [ ] Network usage monitoring
- [ ] Battery consumption analysis

---

## 🔐 Security Audit

### Da Verificare
- [ ] RSA key storage security (flutter_secure_storage alternatives?)
- [ ] Forward secrecy implementation
- [ ] Perfect forward secrecy (PFS) con Diffie-Hellman?
- [ ] Code obfuscation per release builds
- [ ] Certificate pinning per Firebase connections
- [ ] Vulnerability scanning (dependency check)

---

## 🌍 Internazionalizzazione

### Lingue da Supportare
- [ ] Italiano (già presente inline)
- [ ] Inglese
- [ ] Spagnolo
- [ ] Francese
- [ ] Package: `flutter_localizations` + `intl`

---

## 📊 Analytics & Monitoring

### Da Implementare (opzionale, privacy-friendly)
- [ ] Crash reporting (Firebase Crashlytics)
- [ ] Anonymous usage analytics (quanti messaggi/giorno, etc.)
- [ ] Performance monitoring
- [ ] **IMPORTANTE:** Solo analytics anonime, mai contenuto messaggi

---

**Ultimo aggiornamento:** 2025-12-20
**Versione App:** 1.6.0+7
