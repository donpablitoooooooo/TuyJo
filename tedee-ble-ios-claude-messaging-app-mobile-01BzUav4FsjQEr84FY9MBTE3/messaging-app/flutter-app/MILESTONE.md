# Milestone v1.0 - Configurazione Stabile

**Data:** 2025-12-10
**Branch:** claude/fix-message-display-015u1ySaW5pTwCPhkFtXoYU8
**Tag:** v1.0-stable
**Commit:** d04c5b3

---

## 🎯 Versioni Critiche (NON MODIFICARE)

### Build System
- **Gradle:** 8.11.1 (`android/gradle/wrapper/gradle-wrapper.properties`)
- **Android Gradle Plugin (AGP):** 8.9.1 (`android/settings.gradle`)
- **Kotlin:** 2.1.0 (`android/settings.gradle`)
- **AndroidX:** abilitato (`android/gradle.properties`)

### Flutter & Dependencies
- **Flutter:** stable channel
- **Dart SDK:** >=3.5.4 <4.0.0
- **Key packages:**
  - `firebase_core: ^3.8.1`
  - `cloud_firestore: ^5.5.0`
  - `pointycastle: ^3.9.1` (encryption)
  - `qr_flutter: ^4.1.0` (QR generation)
  - `mobile_scanner: ^5.2.3` (QR scanning)
  - `flutter_secure_storage: ^9.2.2`

---

## ✅ Funzionalità Implementate

### 1. Sistema di Pairing QR Code
- ✅ Generazione K_family (chiave AES-256 condivisa)
- ✅ QR code display con chiave famiglia
- ✅ Scansione QR e import K_family
- ✅ Auto-navigazione alla chat per entrambi i telefoni
- ✅ Stato `isPaired` persistente

### 2. Crittografia End-to-End
- ✅ AES-256-GCM per messaggi
- ✅ SHA-256 per family_chat_id
- ✅ Tag authentication corretto (16 bytes)
- ✅ Nonce unico per ogni messaggio
- ✅ Storage sicuro con flutter_secure_storage

### 3. Messaging System
- ✅ Architettura famiglia-based: `families/{family_chat_id}/messages`
- ✅ Firestore real-time listener
- ✅ Invio messaggi cifrati
- ✅ Ricezione e decifrazione messaggi
- ✅ Display corretto dei messaggi in chat
- ✅ Timestamp e sender ID

### 4. Bug Fix Critici Risolti
- ✅ **GCM Tag Extraction:** Fixed extraction using actual output size (not buffer size)
- ✅ **Decryption Truncation:** Added `doFinal()` return value to offset
- ✅ **QR Creator Navigation:** popUntil() instead of pop() for proper routing
- ✅ **isPaired State:** Auto-set when K_family generated
- ✅ **BigInt Conversion:** Using `valueAsBigInteger!` instead of `intValue`

---

## 📁 File Chiave

### Configurazione Build (CRITICI!)
```
android/settings.gradle           → AGP 8.9.1, Kotlin 2.1.0
android/gradle/wrapper/gradle-wrapper.properties → Gradle 8.11.1
android/gradle.properties          → AndroidX abilitato
android/app/build.gradle           → minSdk 21, targetSdk 34
```

### Core Services
```
lib/services/pairing_service.dart      → K_family generation, QR data, pairing state
lib/services/chat_service.dart         → Firestore messaging, encryption/decryption
lib/services/encryption_service.dart   → AES-256-GCM implementation
```

### Screens
```
lib/screens/chat_screen.dart           → Main chat UI
lib/screens/qr_display_screen.dart     → QR creator (mostra QR)
lib/screens/qr_scanner_screen.dart     → QR scanner (legge QR)
lib/screens/pairing_choice_screen.dart → Scelta pairing method
```

### Models
```
lib/models/message.dart                → Message data model
```

### Main
```
lib/main.dart                          → App entry, AuthWrapper routing
```

---

## 🔧 Come Ripristinare Questa Versione

### Opzione 1: Checkout del tag
```bash
git checkout v1.0-stable

# Per creare un nuovo branch da qui
git checkout v1.0-stable
git checkout -b claude/nuova-feature-XYZ
```

### Opzione 2: Checkout del branch stabile
```bash
git checkout stable/v1.0-working

# Per creare un nuovo branch
git checkout stable/v1.0-working
git checkout -b claude/altra-feature-ABC
```

### Opzione 3: Confronta differenze
Se qualcosa si rompe, confronta con la milestone:
```bash
# Vedi cosa è cambiato nei file di build
git diff v1.0-stable -- android/settings.gradle
git diff v1.0-stable -- android/gradle/wrapper/gradle-wrapper.properties
git diff v1.0-stable -- android/gradle.properties

# Vedi tutti i cambiamenti
git diff v1.0-stable
```

### Opzione 4: Ripristina file specifici
```bash
# Ripristina solo la configurazione Gradle dalla milestone
git checkout v1.0-stable -- android/settings.gradle
git checkout v1.0-stable -- android/gradle/wrapper/gradle-wrapper.properties
git checkout v1.0-stable -- android/gradle.properties
```

---

## 📋 Checklist Pre-Build

Prima di ogni build, verifica:

- [ ] Gradle wrapper = 8.11.1
- [ ] AGP in settings.gradle = 8.9.1
- [ ] Kotlin in settings.gradle = 2.1.0
- [ ] `android.useAndroidX=true` in gradle.properties
- [ ] `google-services.json` presente in `android/app/`
- [ ] Flutter version stable channel
- [ ] `flutter pub get` eseguito senza errori

---

## 🚨 Firestore Security Rules

**IMPORTANTE:** Le regole Firestore devono permettere accesso a `families` collection:

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

---

## 🎓 Lezioni Apprese

### Errori da NON ripetere:
1. ❌ Non modificare le versioni in `settings.gradle` senza controllare compatibilità
2. ❌ Non disabilitare AndroidX una volta abilitato
3. ❌ Non usare `intValue` per BigInt in PointyCastle (usare `valueAsBigInteger!`)
4. ❌ Non dimenticare di aggiungere `doFinal()` return value all'offset in GCM
5. ❌ Non estrarre GCM tag dalla dimensione buffer (usare output effettivo)

### Best Practices:
1. ✅ Sempre creare milestone dopo fix critici
2. ✅ Testare encryption/decryption con debug logging prima di rimuoverlo
3. ✅ Verificare navigation flow completo su entrambi i telefoni
4. ✅ Mantenere versioni Gradle/AGP/Kotlin allineate in settings.gradle
5. ✅ Usare `popUntil()` per navigation a root, non `pop()` multipli

---

## 📊 Test Status

### ✅ Testato e Funzionante
- [x] Compilazione Android (debug APK)
- [x] Generazione K_family e QR code
- [x] Scansione QR code
- [x] Navigazione post-pairing (entrambi i telefoni)
- [x] Invio messaggio cifrato
- [x] Ricezione e decifrazione messaggio
- [x] Display messaggio in chat UI
- [x] Firestore persistence

### ⏳ Non Testato
- [ ] Build release (release APK con signing)
- [ ] Performance con molti messaggi (100+)
- [ ] Network error handling
- [ ] Multiple device pairs (>2 dispositivi)

---

## 🔄 Workflow Future Development

### Quando iniziare nuova feature:
```bash
# 1. Parti dalla milestone stabile
git checkout v1.0-stable

# 2. Crea branch per la feature
git checkout -b claude/feature-nome-XYZ

# 3. Lavora sulla feature...

# 4. Se funziona, crea nuova milestone
git tag -a v1.1-stable -m "Added feature X"
git push origin v1.1-stable
```

### Se qualcosa si rompe:
```bash
# Torna alla milestone precedente
git checkout v1.0-stable

# Oppure resetta il branch corrente
git reset --hard v1.0-stable
```

---

**NOTA FINALE:** Questa configurazione è stata testata e funziona correttamente al 2025-12-10. Ogni modifica a Gradle, AGP, Kotlin o AndroidX deve essere testata approfonditamente prima di creare una nuova milestone.
