# Changelog

All notable changes to YouAndMe app will be documented in this file.

## [1.3.0] - 2025-12-17

### 🚀 Added
- **SQLite Message Cache**: Database locale per caricamento istantaneo dei messaggi (< 100ms)
- **Lazy Loading**: Carica solo 100 messaggi iniziali invece di tutti
- **Infinite Scroll**: Auto-carica 50 messaggi vecchi quando scrolli verso l'alto
- **Reverse ListView**: Architettura ottimizzata con messaggi ordinati DESC (nuovi→vecchi)
- **Loading Indicator**: Indicatore visivo durante caricamento messaggi vecchi

### ⚡ Performance
- App restart: migliorato da ~2s a **< 100ms** per mostrare messaggi
- Scroll fluido anche con 1000+ messaggi in cache
- Zero visual glitches o "salti" durante caricamento iniziale
- Build release: performance eccellenti (debug mode più lento ma usabile)

### 🔧 Technical Changes
- Implementato `MessageCacheService` con SQLite
- Aggiunto metodo `loadOlderMessages()` in `ChatService`
- ListView con `reverse: true` (indice 0 = messaggio nuovo in basso)
- Messaggi ordinati DESC invece di ASC
- Auto-scroll trigger a `maxScrollExtent - 100px`
- Metodo `_scrollToBottom()` aggiornato per reverse ListView (scroll a 0 invece di max)

### 📝 Files Modified
- `flutter-app/lib/services/chat_service.dart`
- `flutter-app/lib/services/message_cache_service.dart` (new)
- `flutter-app/lib/screens/chat_screen.dart`
- `flutter-app/lib/models/message.dart`
- `flutter-app/pubspec.yaml` (version bump)
- `README.md` (documentation update)

---

## [1.2.0] - 2025-12-16

### 🚀 Added
- **To Do & Reminders**: Promemoria cifrati con notifiche schedulate 1h prima
- **Dual Encryption**: Mittente e destinatario possono decifrare i loro messaggi
- **Notifiche Push**: Firebase Cloud Messaging per nuovi messaggi
- **Cloud Functions**: Funzioni serverless per invio notifiche automatico

### 🔧 Fixed
- Bug dual encryption: AES key encrypting mismatch
- Bug ASN1 public key parsing: BitString decoding error
- Dependency injection di EncryptionService

### 📦 Updated
- Tutte le dipendenze aggiornate alle ultime versioni stabili (Dicembre 2025)
- Firebase BOM: 32.7.0 → 34.6.0
- Firebase packages: +2 major versions
- Java: 8 → 17 (LTS)
- Kotlin JVM Target: 1.8 → 17

---

## [1.1.0] - 2025-12-15

### 🚀 Added
- Architettura RSA-only (no chiavi simmetriche nel QR)
- Pairing wizard con checklist UI
- Bottom navigation (Chat / Impostazioni)
- Storage sicuro chiavi RSA

---

## [1.0.0] - 2025-12-14

### 🚀 Initial Release
- Crittografia End-to-End con RSA-2048 + AES-256
- QR code pairing con chiavi pubbliche
- Firestore real-time messaging
- Chat UI con messaggi cifrati
- Build Android funzionante
