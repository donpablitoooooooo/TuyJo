# Changelog

All notable changes to YouAndMe app will be documented in this file.

## [1.5.0] - 2025-12-19

### 🎨 Added - Complete Todo System Redesign

- **Inline Date/Time Picker**: Modale completamente viola con gradiente pulito
  - Calendario integrato con tema custom bianco su viola
  - CupertinoPicker iOS-style per scroll ore/minuti (0-23 / 0-59)
  - Layout compatto (70% altezza schermo, zero spazi vuoti)
  - Check button riposizionato a lato del time picker (più comodo)

- **Smart Placeholder System**: Feedback visivo discreto
  - "Scrivi un messaggio..." quando nessuna data selezionata
  - "Nuovo todo" quando calendario attivo
  - Sempre grigio, mai invadente

- **Streamlined UX**: Flow pulito e intuitivo
  - Solo icona calendario nel campo testo (viola quando attiva)
  - X button intelligente: cancella data se presente, altrimenti chiude
  - Riclicca calendario per modificare/cancellare
  - Messaggi vuoti OK se c'è data selezionata
  - Invio con tastiera (Enter)

### 🐛 Fixed - Critical SQLite Bug

- **is_reminder Field Missing**: Reminder mostrava icona calendario invece di campanellino dopo riavvio app
  - Root cause: campo `is_reminder` non era salvato nella cache SQLite
  - Fix: Aggiunto campo `is_reminder INTEGER` allo schema (v2 → v3)
  - Database migration automatica per utenti esistenti
  - Save/load `isReminder` field in `saveMessage()`, `saveMessages()`, `_messageFromMap()`

### 🔧 Technical Changes

- SQLite schema upgrade: v2 → v3 (added `is_reminder` column)
- Migration handler in `_upgradeDatabase()` for seamless upgrade
- CupertinoPicker integration for native iOS-style scroll wheels
- Theme override for calendar: white text on purple background
- Sentinel value (DateTime(1970)) to distinguish clear vs close actions
- FixedExtentScrollController properly disposed to prevent memory leaks
- Dynamic placeholder logic based on `_selectedTodoDate` state

### 📝 Files Modified

- `flutter-app/pubspec.yaml` (version 1.4.0+5 → 1.5.0+6)
- `flutter-app/lib/services/message_cache_service.dart`:
  - Schema v3: added `is_reminder INTEGER DEFAULT 0`
  - Migration v2→v3 in `_upgradeDatabase()`
  - Save/load `isReminder` in cache operations
- `flutter-app/lib/screens/chat_screen.dart`:
  - Complete date/time picker redesign (all-purple modal)
  - Removed old dialog (`_CreateTodoDialog`)
  - Removed inline X button for date clearing
  - X button in modal now clears if date exists
  - Check button moved next to time picker
  - Smart placeholder ("Nuovo todo" when date selected)
  - CupertinoPicker scroll wheels (hour/minute)
- `README.md` (documentation v1.5.0)
- `CHANGELOG.md` (this file)

### 🎯 UX Flow

1. 📅 Tap calendario → modale viola si apre
2. 📆 Seleziona data dal calendario integrato
3. ⏰ Scroll ore/minuti con ruote iOS
4. ✓ Tap check a lato → conferma e chiude
5. 💜 Icona calendario diventa viola
6. ✍️ Scrivi todo (o lascia vuoto)
7. 📤 Enter → invia con reminder automatico (1h prima)

### 🏗️ Design Philosophy

- **Minimal**: No testi inutili, solo quello che serve
- **Coerente**: Tutto viola per visual harmony
- **Intuitivo**: Controlli dove servono (check vicino ai picker)
- **Immediato**: Feedback istantaneo (icona viola = attivo)
- **Naturale**: Gesture familiari (riclicca per modificare)

---

## [1.4.0] - 2025-12-17

### 🎨 Added - UX Redesign
- **Todo Message Redesign**: Todo con aspetto identico ai messaggi normali (stesso gradiente, bordi arrotondati, padding)
- **Dynamic Icons**: Icone adattive - 📅 calendario per evento, 🔔 campanello per reminder
- **Smart Reminder Messages**: Sistema dual-message - messaggio principale + messaggio reminder che appare automaticamente quando scatta
- **Long Press to Complete**: Gesture intuitivo per completare todo (sostituisce bottone ingombrante)
- **Hint Text**: Indicazione discreta "Tieni premuto per completare" (scompare quando completato)

### ⚡ Performance & UX
- **Dynamic Timestamps**: Reminder si auto-aggiorna all'ora corrente quando diventa visibile (resta sempre "fresco" in cima)
- **Smart Auto-Scroll**: Chat rimane ferma dopo completamento todo (no scroll indesiderato)
- **Automatic Reminder Cancellation**: Completi todo → notifica locale cancellata automaticamente

### 🔧 Technical Changes
- Aggiunto campo `isReminder` al modello `Message` per distinguere evento da reminder
- Nuovo metodo `sendTodoReminder()` in `ChatService` per inviare messaggio campanello
- Metodo `_updateReminderTimestamp()` per aggiornare timestamp reminder su Firestore
- Handler eventi `DocumentChangeType.modified` nel listener per gestire update timestamp
- Filtro reminder futuri basato su `message.timestamp` (nasconde fino al momento giusto)
- Smart scroll: controlla `messageType != 'todo_completed'` prima di scrollare

### 📝 Files Modified
- `flutter-app/lib/models/message.dart` (+ campo `isReminder`)
- `flutter-app/lib/services/chat_service.dart` (+ `sendTodoReminder()`, + `_updateReminderTimestamp()`, + handler modified)
- `flutter-app/lib/screens/chat_screen.dart` (redesign `_TodoMessageBubble`, + long press, + smart scroll)
- `flutter-app/pubspec.yaml` (version 1.3.0+4 → 1.4.0+5)
- `README.md` (documentation v1.4.0)
- `CHANGELOG.md` (this file)

### 🐛 Fixed
- Recipient icon bug: icona calendario anche per reminder (ora mostra campanello correttamente)
- Timestamp final field error: rimosso assegnazione diretta (ora usa Firestore update + listener)
- Auto-scroll after completion: disabilitato per messaggi `todo_completed`

---

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
