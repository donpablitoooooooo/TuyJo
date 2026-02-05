# Changelog

All notable changes to TuyJo app will be documented in this file.

## [1.24.0] - 2026-02-05

### 🔐 Encrypted Location Sharing & Voice Calls

#### ✨ New Features

- **Coordinate Encryption (AES-256)**
  - GPS coordinates (latitude, longitude, accuracy, speed, heading) encrypted with per-session AES-256 key
  - Location encryption key distributed via E2E encrypted chat message (RSA+AES dual-encrypted)
  - Zero plaintext GPS data on Firestore - all coordinate fields replaced with `encrypted_location` + `location_iv`
  - Backward compatible: falls back to unencrypted reads for old sessions

- **Initial Coordinates in Message**
  - Sender's GPS coordinates embedded in E2E encrypted location_share message body
  - Receiver can navigate immediately without waiting for sender's Firestore data
  - Body format: `location_share|expiresAt|sessionId|locationKey|mode|lat,lng`

- **Full-Screen Location Setup Page**
  - Dedicated `LocationShareSetupPage` with live GPS acquisition and pulse animation
  - Mode selection: Live (continuous updates) or Static (single position)
  - Duration picker: 1 hour or 8 hours
  - GPS accuracy display and coordinates preview

- **WebRTC Voice Calls**
  - Peer-to-peer audio calls via WebRTC with Firestore signaling
  - Native CallKit (iOS) and ConnectionService (Android) for incoming calls
  - Call screen with mute, speaker, accept/decline controls
  - Live duration timer (MM:SS) during connected calls
  - Dark-themed UI with animated partner avatar
  - STUN NAT traversal via Google servers
  - Automatic cleanup of call data and ICE candidates

#### 🔧 Technical Changes

- `EncryptionService`: Added `generateLocationKey()`, `encryptLocationData()`, `decryptLocationData()`
- `ChatService.sendLocationShare()`: Returns `Map<String, String>` with `messageId` + `locationKey`
- `LocationService`: Now requires `EncryptionService` dependency, encrypts/decrypts coordinates
- `LocationShare.fromEncryptedFirestore()`: New factory for decrypting Firestore documents
- `LocationSharingScreen`: Added `initialLatitude`/`initialLongitude` parameters
- Location key persisted in `FlutterSecureStorage` for app restart recovery
- `.set()` without merge prevents plaintext coordinate leakage in Firestore
- New `WebRTCService` for call management with Firestore signaling
- New `VoiceCallScreen` with call state management and animated UI
- `NotificationService` extended with CallKit/ConnectionService callbacks

#### 🐛 Bug Fixes

- ✅ Fixed plaintext coordinates remaining in Firestore alongside encrypted data (merge: true → set without merge)
- ✅ Fixed body format parser indices after adding locationKey and mode fields

### 📝 Files Modified

- `flutter-app/lib/services/encryption_service.dart` (+ 3 location crypto methods)
- `flutter-app/lib/services/chat_service.dart` (sendLocationShare return type + params)
- `flutter-app/lib/services/location_service.dart` (encryption/decryption + EncryptionService dep)
- `flutter-app/lib/services/webrtc_service.dart` (new - WebRTC call management)
- `flutter-app/lib/models/location_share.dart` (+ fromEncryptedFirestore factory)
- `flutter-app/lib/screens/location_sharing_screen.dart` (+ initial coords, recipient encryption)
- `flutter-app/lib/screens/location_share_setup_page.dart` (+ coordinates + Map return handling)
- `flutter-app/lib/screens/voice_call_screen.dart` (new - call UI)
- `flutter-app/lib/screens/chat_screen.dart` (6-part body parsing + Map handling)
- `flutter-app/lib/widgets/attachment_widgets.dart` (updated format indices)
- `flutter-app/lib/main.dart` (LocationService(encryptionService) + call callbacks)
- `flutter-app/pubspec.yaml` (1.23.0+26 → 1.24.0+27)

---

## [1.23.0] - 2026-02-03

### 🔧 Offline Attachments & Fixes

- **Offline Attachment Handling**: Improved retry logic for attachments sent while offline
- **Pending Messages**: Reuse `_MessageBubble` for identical look and feel with sent messages

---

## [1.22.0] - 2026-01-31

### 📞 Voice Call Integration

- **WebRTC Service**: Peer connection management with STUN servers
- **Voice Call Screen**: Animated UI with ringing/connected/ended states
- **CallKit Integration**: Native incoming call UI on iOS and Android
- **Call Button**: Floating call button in chat header (visible when paired)
- **Audio Controls**: Mute and speaker toggle during calls

---

## [1.21.0] - 2026-01-29

### 🔗 Link Preview & TODO Enhancements

- Smart URL detection for www.example.com and bare domain URLs
- Link preview extraction with Open Graph/Twitter meta tags
- TODO alert indicator (🔔 1h, 🔔 2d) visible on bubbles
- TODO editing indicator between calendar and list
- Edit button restricted to own messages (cryptographic security)
- Complete attachment deletion (Firebase Storage + cache)
- Deleted flag persisted in SQLite cache across restarts

---

## [1.20.0] - 2026-01-28

### 🖼️ Media Redesign

- Pinterest-style link gallery with masonry grid layout
- Redesigned media viewers with teal gradient
- Platform-specific share icons (iOS/Android)
- Version display in Settings screen

---

## [1.14.0] - 2026-01-21

### 📍 Location Sharing & Production Ready

- Real-time location sharing with live navigation and compass
- Complete localization - all UI elements in 4 languages (IT, ES, EN, CA)
- Edit and delete pending messages
- Streamlined 3-tab navigation (Chat, Media, Settings)

---

## [1.13.0] - 2026-01-15

### 📱 iOS Photo Sharing

- Native iOS photo sharing from Photos app via Share Extension
- File cleanup timing, build dependencies, localizations fixes
- Caches directory usage, project structure cleanup

---

## [1.12.0] - 2026-01-10

### 🚀 Store Releases

- iOS TestFlight release (Build 14)
- Android Firebase release (Build 13)

---

## [1.11.0] - 2026-01-09

### 🎯 TODO & Calendar Enhancement

#### ✨ New Features

- **Calendario TODO Integrato**
  - Vista calendario dedicata per visualizzare tutti i TODO
  - Selezione multipla date per TODO a range (es. "dal 25 al 31 gennaio")
  - Marker visivi per giorni con TODO
  - TODO a range visualizzati come "linea" su tutte le date del periodo
  - Filtro automatico: solo TODO (non reminder) visibili nel calendario
  - TODO completati mostrati con grafica differenziata (opacità, grigio, check icon)

- **Supporto Allegati per TODO**
  - Possibilità di allegare foto/documenti ai TODO
  - Thumbnail allegati visualizzati nelle bubble TODO (chat)
  - Allegati completamente interattivi nel calendario
  - Click su foto/doc apre visualizzazione a schermo pieno
  - Cifratura E2E mantenuta per tutti gli allegati

- **Widget Riutilizzabili**
  - `TodoMessageBubble`: widget condiviso tra chat e calendario
  - `AttachmentImage`, `AttachmentVideo`, `AttachmentDocument`: widget allegati riutilizzabili
  - Future modifiche ai widget si riflettono automaticamente ovunque
  - Colori differenziati: viola/blu per i tuoi TODO, grigio per quelli del partner

#### 🎨 UI/UX Improvements

- **Separatori Data Colloquiali**
  - Formato italiano naturale: "Oggi", "Ieri", "Lunedì 6 gennaio"
  - Separatori grafici con icona bandiera e gradient
  - Separatori mostrati solo tra messaggi visibili (esclude TODO futuri/completati)

- **Ottimizzazione Formato Date Range**
  - Stesso mese: "dal 25 al 31 gennaio" (non ripete il mese)
  - Mesi consecutivi: "dal 25 dicembre al 3" (omette secondo mese)
  - >1 mese distanza: "dal 25 dicembre al 3 febbraio"
  - Logica applicata sia in chat che nel calendario

- **Sezione Media Migliorata**
  - Ordine invertito: foto vecchie in alto, recenti in basso
  - Scroll posizionato automaticamente in basso all'apertura
  - Accesso immediato alle foto più recenti senza scrollare

#### 🔧 Technical Improvements

- **Refactoring Architetturale**
  - Creata cartella `widgets/` per componenti riutilizzabili
  - Separazione concerns: UI components vs business logic
  - Migliore manutenibilità del codice

- **Gestione State Calendar**
  - `AttachmentService` inizializzato correttamente con flag `_isInitialized`
  - `ScrollController` per posizionamento automatico scroll
  - Gestione completa TODO range con date normalizzate

#### 📱 User Experience

- **Calendar Screen**
  - Spazio superiore (80px) per non coprire menu e foto profilo
  - Formattazione intelligente date basata su locale
  - Long press su TODO per completarlo
  - Hint visivo: "Tieni premuto per completare"

- **Chat Screen**
  - TODO bubble con stesso design di messaggi normali
  - Allegati visualizzati per primi (full width), poi testo
  - ClipRRect per bordi arrotondati eleganti
  - Icons differenziati: campanello (reminder) vs calendario (TODO)

#### 🐛 Bug Fixes

- Corretto import `Attachment` in `attachment_widgets.dart` (da `message.dart`)
- Separatori data non più mostrati "in mezzo ai messaggi"
- AttachmentService correttamente passato a tutti i widget che ne hanno bisogno

## [1.10.0] - 2025-12-23

### 📸 Couple Profile Photo - Complete Redesign

**Core Philosophy**: ONE photo on server, synchronized across devices

#### 🔧 Fixed - Single Photo Enforcement

- **Problem**: Each upload created new file with timestamp → multiple photos
  ```
  Before: couple_selfie_1234567890.jpg + couple_selfie_9876543210.jpg
  Now:    couple_selfie.jpg (ALWAYS)
  ```
- **Solution**: Fixed filename + delete old before upload
  - Upload always uses `couple_selfie.jpg` (no timestamp)
  - Delete previous photo from Storage before uploading new one
  - One photo rule: guaranteed via code architecture
  - Real-time sync automatically updates local cache

#### 🔧 Fixed - Unpair Photo Logic

- **Mode 'all'** (Delete Everything):
  - ✅ Deletes photo from Storage + Firestore
  - ✅ Cleans local cache

- **Mode 'mine'** (Device Change):
  - ✅ Keeps photo on server (partner needs it)
  - ✅ Only cleans local cache
  - ❌ Before: deleted from server (bug)

- **Mode 'partner'** (Partner Changed Device):
  - ✅ Keeps photo on server
  - ✅ Only triggers partner cleanup flag
  - ❌ Before: deleted own messages + photo (bug)

#### 🔧 Fixed - Gray Heart Icon Logic

- **Problem**: Photo showed even when unpaired (cache remained)
- **Solution**: Check `isPaired` BEFORE showing photo
  ```dart
  // Before: showed if cached
  hasSelfie && cachedSelfieBytes != null

  // Now: show ONLY if paired
  isPaired && hasSelfie && cachedSelfieBytes != null
  ```
- **Result**:
  - Unpaired → ALWAYS gray heart (even if cached)
  - Paired + photo → show photo
  - Paired + no photo → blue heart

#### 🔧 Fixed - Re-pairing Photo Reload

- **Problem**: Photo not reloaded from server after re-pairing
  - CoupleSelfieService.initialize() called only in initState()
  - Re-pairing didn't trigger reload

- **Solution**: Listener monitors pairing state changes
  ```dart
  void _onPairingChanged() {
    if (isPaired && !_wasPaired) {
      // Reinitialize CoupleSelfieService
      // Load photo from server
      // Switch to Chat tab
    }
  }
  ```
- **Result**: Both devices reload photo automatically after pairing

#### 🔧 Fixed - Photo Crop Fallback

- **Problem**: If user presses OK without modifying crop → photo not set
  - image_cropper returns null when no modifications made

- **Solution**: Manual crop fallback
  - If cropper returns file: use it
  - If cropper returns null: auto-crop to square (center)
  - Function `_cropImageToSquare()`:
    - Takes smallest dimension (width or height)
    - Crops from center
    - Saves as JPEG quality 95

#### 🔧 Fixed - Automatic Photo Message

- **Problem**: Automatic message failed with "Provider<AttachmentService> not found"

- **Solution**: Added AttachmentService to Provider tree
  - Created instance in main.dart
  - Added to MultiProvider
  - Now message with photo attachment sends correctly

#### 🔧 Fixed - Localization Build Errors

- **Problem**: ARB files had invalid keys starting with underscore
  ```
  Error: Invalid ARB resource name "_comment_app"
  ```

- **Solution**: Removed all `_comment_*` keys from ARB files
  - Cherry-picked fixes from localization branch
  - Added synthetic-package support
  - Fixed bracket/syntax errors in screens

### 📝 Files Modified

**Core Photo Logic**:
- `flutter-app/lib/services/couple_selfie_service.dart`
  - Single photo enforcement (fixed filename)
  - Delete old photo before upload
  - Smart removeCoupleSelfie() with parameters

**Unpair & Icon Logic**:
- `flutter-app/lib/screens/settings_screen.dart`
  - Fixed mode 'partner' (no local cleanup)
  - Correct photo handling per mode

- `flutter-app/lib/screens/main_screen.dart`
  - Gray heart when unpaired
  - Listener for re-pairing detection
  - Auto-reload photo after pairing

**Photo Upload & Crop**:
- `flutter-app/lib/screens/couple_selfie_screen.dart`
  - Manual crop fallback
  - Better error handling
  - AttachmentService integration

**Provider Setup**:
- `flutter-app/lib/main.dart`
  - AttachmentService in Provider tree
  - Proper dependency injection

**Localization**:
- `flutter-app/lib/l10n/app_*.arb` (EN, IT, ES, CA)
  - Removed invalid _comment_ keys
  - Clean ARB files

**Version**:
- `flutter-app/pubspec.yaml` (1.9.0+10 → 1.10.0+11)

### 🎯 Scenarios - All Fixed

✅ **Scenario 1**: Upload photo → Both see same photo
✅ **Scenario 2**: A unpairs (partner mode) → A sees gray heart, messages preserved
✅ **Scenario 3**: A unpairs (mine mode) → Both see gray heart
✅ **Scenario 4**: Re-pairing → Both reload photo from server
✅ **Scenario 5**: Upload without crop changes → Photo still uploads (auto-crop)
✅ **Scenario 6**: Photo change → Automatic message with attachment sent

### 🏗️ Architecture Improvements

- **Single Source of Truth**: ONE photo on server, period
- **Idempotent Uploads**: Same filename = overwrite (no duplicates)
- **Smart Caching**: Cache follows server state
- **Reactive UI**: Icons update instantly on pairing changes
- **Graceful Fallbacks**: Manual crop when native cropper fails
- **Provider Pattern**: All services properly injected

### 🐛 Bug Fixes Summary

- ✅ Multiple photos on server (ONE photo enforcement)
- ✅ Unpair partner deletes own messages (fixed logic)
- ✅ Photo shows when unpaired (gray heart check)
- ✅ Photo not reloaded after re-pairing (listener added)
- ✅ Crop without changes fails (manual fallback)
- ✅ Automatic message not sent (Provider fix)
- ✅ Build errors from ARB files (localization cleanup)

---

## [1.8.0] - 2025-12-22

### 🔄 Unpair Logic Redesign + Smart Cache Cleanup

#### 🗑️ Added - Three Unpair Options

- **Elimina Tutti i Messaggi**: Cancella messaggi e foto dal server Firestore (per entrambi gli utenti)
  - Cleanup completo del server + cache locale
  - Entrambi i dispositivi perdono tutti i dati
  - Irreversibile

- **Elimina i Miei Messaggi**: Cancella solo cache locale (scenario Cambio Telefono)
  - Il partner mantiene tutti i suoi dati
  - Utile quando cambi telefono ma partner resta sullo stesso
  - Server intatto

- **Elimina Messaggi del Partner**: Triggera pulizia cache remota
  - Scrive flag `delete_cache_requested` in Firestore
  - Partner riceve richiesta al prossimo accesso
  - Utile quando partner ha cambiato telefono senza fare unpair

#### 🧹 Added - Auto Cache Cleanup

- **Smart Detection**: Sistema automatico di pulizia cache quando partner fa "Elimina Tutti"
  - Telefono A elimina tutto → telefono B rileva e pulisce automaticamente
  - Controllo intelligente: verifica esistenza messaggi su server
  - Distingue tra "Cambio Telefono" (messaggi presenti) vs "Elimina Tutto" (messaggi assenti)

- **Callback System**: Architettura basata su callback per pulizia
  - `onPartnerDeletedAll` configurato in `main.dart`
  - Pulizia automatica cache messaggi (ChatService)
  - Pulizia automatica foto coppia (CoupleSelfieService)

#### 📱 Added - Remote Cache Deletion

- **Firestore Flag**: Comunicazione tra dispositivi via flag
  - Flag `delete_cache_requested: true` scritto nel documento partner
  - Timestamp `delete_cache_requested_at` per tracking
  - Listener real-time in `PairingService` rileva flag

- **Auto Execution**: Pulizia automatica quando rilevato
  - Unpair automatico + pulizia cache completa
  - Rimozione flag dopo completamento
  - Log dettagliati per debugging

### 🛡️ Fixed - Robust Pairing Logic

- **Auto-unpair Cleanup**: Ora elimina documento `users` da Firestore (non solo cache locale)
  - Previene documenti residui che causavano loop "famiglia corrotta"
  - Secondo pairing funziona sempre senza errori
  - Family state completamente pulito dopo unpair

- **Graceful Error Handling**: Gestione NOT_FOUND quando documento famiglia non esiste
  - Try-catch in `deleteMessagesAndCoupleSelfie()`
  - Log informativi invece di errori fatali
  - Scopo raggiunto anche se documento assente

### 🔧 Technical Changes

#### Settings Screen
- Redesign `_deletePairing()` con parametro `mode` ('all'|'mine'|'partner')
- Dialog aggiornato con 3 opzioni chiare e distinte
- Messaggi di conferma specifici per ogni modalità
- Import `cloud_firestore` aggiunto per accesso diretto Firestore

#### Pairing Service
- Callback `onPartnerDeletedAll` per notifiche di pulizia
- Listener per flag `delete_cache_requested` nel documento partner
- Controllo esistenza messaggi server per distinguere tipi di unpair
- Auto-cleanup documento Firestore durante auto-unpair (linea 464-475)

#### Chat Service
- Fix gestione graceful quando documento famiglia non esiste
- Try-catch per errore NOT_FOUND di Firestore (linea 1112-1118)
- Log dettagliati per debugging

#### Main App
- Configurazione callback `onPartnerDeletedAll` per pulizia automatica (linea 34-45)
- ChatService e CoupleSelfieService passati via constructor
- ChangeNotifierProvider.value invece di create per servizi pre-inizializzati

### 📝 Files Modified

- `flutter-app/lib/screens/settings_screen.dart`
  - Redesign `_deletePairing()` con 3 modalità
  - Dialog con 3 opzioni (Tutti / I Miei / Del Partner)
  - Logic flag `delete_cache_requested` su Firestore
  - Import cloud_firestore

- `flutter-app/lib/services/pairing_service.dart`
  - Callback `onPartnerDeletedAll`
  - Listener flag `delete_cache_requested`
  - Auto-cleanup documento users in auto-unpair
  - Controllo messaggi server per smart detection

- `flutter-app/lib/services/chat_service.dart`
  - Fix NOT_FOUND in `deleteMessagesAndCoupleSelfie()`
  - Try-catch graceful error handling

- `flutter-app/lib/main.dart`
  - Configurazione callback pulizia cache
  - Dependency injection ChatService e CoupleSelfieService

- `flutter-app/pubspec.yaml` (version 1.7.0+8 → 1.8.0+9)
- `README.md` (documentation v1.8.0)
- `CHANGELOG.md` (this file)

### 🎯 UX Flow - "Elimina Messaggi del Partner"

1. 📱 Telefono A seleziona "Elimina Messaggi del Partner"
2. 🔥 Scrive flag `delete_cache_requested: true` nel documento di B su Firestore
3. ⏳ A fa unpair completo + pulisce la sua cache
4. 📲 Telefono B apre app → listener rileva flag
5. 🗑️ B automaticamente: unpair + pulisce cache messaggi + pulisce foto coppia
6. ✅ Flag rimosso, B pronto per nuovo pairing pulito

### 🐛 Bug Fixes

- ✅ Fix: auto-unpair elimina documento Firestore (non solo cache)
- ✅ Fix: gestione NOT_FOUND quando documento famiglia non esiste
- ✅ Fix: nessun loop "famiglia corrotta" durante re-pairing
- ✅ Fix: cache sempre sincronizzata tra i due dispositivi
- ✅ Fix: documenti residui in Firestore dopo unpair

---

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
