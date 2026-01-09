# 💬 YouAndMe - App di Messaggistica Privata E2E

App di messaggistica privata per due persone con crittografia end-to-end e pairing tramite QR code.

[![Status](https://img.shields.io/badge/status-v1.11.0--stable-success)](./README.md)
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
- ✓✓ **Read Receipts** - spunte singole/doppie (consegnato/letto) in tempo reale
- ⌨️ **Typing Indicator** - "Sta scrivendo..." quando il partner digita
- 📅 **To Do & Reminders** - promemoria cifrati con notifiche schedulate 1h prima
- 📆 **Calendario TODO Integrato** - vista calendario con range date e marker visivi
- 📎 **TODO con Allegati** - foto e documenti allegabili ai TODO con E2E encryption
- 📎 **Message Attachments** - foto, video, documenti cifrati E2E con thumbnail
- 🖼️ **Fullscreen Viewer** - visualizzatore immagini con zoom e overlay tap-to-toggle
- 💑 **Couple Selfie** - foto di coppia sincronizzata con crop circolare
- 💾 **SQLite Cache** - caricamento istantaneo con lazy loading (100 messaggi iniziali)
- 📜 **Infinite Scroll** - carica automaticamente 50 messaggi vecchi scrollando in alto
- ⚡ **Performance Ottimizzate** - reverse ListView + ordine DESC per zero lag
- 🚫 **Zero backend** - solo Cloud Functions serverless
- 🔒 **Storage sicuro** - chiavi memorizzate con flutter_secure_storage
- 📲 **Cross-platform** - iOS e Android
- 📑 **Bottom Navigation** - tab Chat e Impostazioni

---

## 🏗️ Architettura

### Stack Tecnologico
- **Frontend:** Flutter 3.x
- **Database Cloud:** Google Cloud Firestore (real-time sync)
- **Database Locale:** SQLite (sqflite 2.3.0) per message cache
- **Crittografia:** RSA-2048 + AES-256 (PointyCastle 3.9.1)
- **Storage Locale:** flutter_secure_storage 10.0.0 (chiavi RSA)
- **Notifiche:** Firebase Cloud Messaging + flutter_local_notifications 19.5.0
- **Cloud Functions:** Node.js 18 (serverless)
- **QR Code:** qr_flutter + mobile_scanner 7.1.4
- **State Management:** Provider 6.1.5

### Build System & SDK
- **Gradle:** 8.11.1
- **Android Gradle Plugin:** 8.9.1
- **Kotlin:** 2.1.0
- **Java:** 17 (LTS)
- **AndroidX:** abilitato
- **Firebase BOM:** 34.6.0
- **Firebase Core:** 4.3.0
- **Firebase Auth:** 6.1.3
- **Cloud Firestore:** 6.1.1
- **Firebase Messaging:** 16.1.0

---

## 📦 Aggiornamenti Recenti (Gennaio 2026)

### 🎯 v1.11.0 - TODO & Calendar Enhancement (9 Gennaio 2026)

**Nuove Feature:**

1. **📆 Calendario TODO Integrato**
   - Vista calendario dedicata per visualizzare tutti i TODO
   - Selezione multipla date per TODO a range (es. "dal 25 al 31 gennaio")
   - Marker visivi per giorni con TODO
   - TODO a range visualizzati come "linea" su tutte le date del periodo
   - Filtro automatico: solo TODO (non reminder) visibili nel calendario
   - TODO completati con grafica differenziata (opacità, grigio, check icon)

2. **📎 Supporto Allegati per TODO**
   - Possibilità di allegare foto/documenti ai TODO
   - Thumbnail allegati visualizzati nelle bubble TODO (chat)
   - Allegati completamente interattivi nel calendario
   - Click su foto/doc apre visualizzazione a schermo pieno
   - Cifratura E2E mantenuta per tutti gli allegati

3. **🔧 Widget Riutilizzabili**
   - `TodoMessageBubble`: widget condiviso tra chat e calendario
   - `AttachmentImage`, `AttachmentVideo`, `AttachmentDocument`: widget allegati riutilizzabili
   - Future modifiche ai widget si riflettono automaticamente ovunque
   - Colori differenziati: viola/blu per i tuoi TODO, grigio per quelli del partner

4. **🎨 UI/UX Improvements**
   - Separatori data colloquiali: "Oggi", "Ieri", "Lunedì 6 gennaio"
   - Formato date range intelligente: "dal 25 al 31 gennaio" (no ripetizioni)
   - Sezione Media con scroll automatico in basso per foto recenti
   - TODO nel calendario con stessa grafica della chat

**Miglioramenti Tecnici:**

- ✅ Refactoring architetturale con cartella `widgets/` per componenti riutilizzabili
- ✅ `AttachmentService` inizializzato correttamente con flag `_isInitialized`
- ✅ `ScrollController` per posizionamento automatico scroll nella sezione Media
- ✅ Gestione completa TODO range con date normalizzate
- ✅ Separatori data visibili solo tra messaggi visibili (esclude TODO futuri/completati)

**File Modificati:**
- `pubspec.yaml`: Version 1.10.0+11 → **1.11.0+12**
- `CHANGELOG.md`: Documentazione completa release
- `flutter-app/lib/widgets/`: NUOVA cartella con widget riutilizzabili
  - `todo_bubble.dart`: TodoMessageBubble condiviso
  - `attachment_widgets.dart`: AttachmentImage, AttachmentVideo, AttachmentDocument, FullscreenImageViewer
  - `README.md`: Documentazione tecnica widget
- `calendar_screen.dart`: Usa TodoMessageBubble, colori differenziati, allegati interattivi
- `chat_screen.dart`: Separatori data colloquiali, formato range ottimizzato
- `media_screen.dart`: Ordine invertito (vecchi in alto), scroll automatico in basso

**UX Flow Calendario:**
- 📅 Apri calendario → vedi tutti i TODO con marker
- 📆 Tap su data → lista TODO del giorno con bubble colorate
- 💜 Viola/blu = tuo TODO, grigio = TODO del partner
- 📎 Click allegato → fullscreen viewer con zoom
- ⏳ Long press su TODO → completa
- ✅ TODO completato → grafica grigia con check

---

### 📸 v1.10.0 - Couple Profile Photo Complete Redesign (23 Dicembre 2025)

**Filosofia:** ONE photo on server, synchronized across devices

**Nuove Feature:**

1. **✅ Single Photo Enforcement**
   - Fixed filename: `couple_selfie.jpg` (nessun timestamp)
   - Delete old photo prima dell'upload (garantisce una sola foto)
   - Real-time sync automatico aggiorna cache locale
   - Problema risolto: niente più foto multiple accumulate

2. **🗑️ Unpair Photo Logic Corretta**
   - **Mode 'all'**: Elimina foto da Storage + Firestore + cache locale
   - **Mode 'mine'**: Mantiene foto server, pulisce solo cache locale (Cambio Telefono)
   - **Mode 'partner'**: Mantiene foto, triggera solo cleanup flag
   - Fix bug: mode 'mine' e 'partner' non eliminano più foto dal server

3. **💜 Gray Heart Icon Logic**
   - Check `isPaired` PRIMA di mostrare foto
   - Soluzione: foto appare solo se paired AND cached
   - Fix bug: cuore grigio non mostra più foto dopo unpair

**File Modificati:**
- `couple_selfie_service.dart`:
  - Delete old photo prima upload
  - Fixed filename senza timestamp
  - Check `isPaired` per mostrare foto
- `settings_screen.dart`:
  - Mode 'mine' e 'partner' non eliminano foto server
- `main_screen.dart`:
  - Check `isPaired` prima di mostrare cached selfie
- `pubspec.yaml`: Version 1.9.0+10 → **1.10.0+11**

**Bug Fix:**
- ✅ Una sola foto garantita su server
- ✅ Foto non eliminata durante "Cambio Telefono"
- ✅ Cuore grigio non mostra foto se non paired
- ✅ Real-time sync funziona correttamente

---

### 🔄 v1.8.0 - Unpair Logic Redesign + Smart Cache Cleanup (22 Dicembre 2025)

**Nuove Feature:**

1. **🗑️ Tre Opzioni Unpair**
   - **Elimina Tutti i Messaggi**: cancella messaggi e foto dal server Firestore (per entrambi)
   - **Elimina i Miei Messaggi**: cancella solo cache locale (Cambio Telefono scenario)
   - **Elimina Messaggi del Partner**: triggera pulizia cache remota quando partner cambia telefono

2. **🧹 Auto Cache Cleanup**
   - Quando telefono A fa "Elimina Tutti", telefono B rileva e pulisce automaticamente la sua cache
   - Controllo smart: verifica presenza messaggi su server per distinguere tra "Cambio Telefono" vs "Elimina Tutto"
   - Callback `onPartnerDeletedAll` configurato in `main.dart` per pulizia automatica

3. **📱 Remote Cache Deletion**
   - Flag `delete_cache_requested` in Firestore per comunicare tra dispositivi
   - Listener real-time in `PairingService` per rilevare richiesta e agire
   - Utile quando partner ha cambiato telefono senza fare unpair

4. **🛡️ Robust Pairing Logic**
   - Fix: auto-unpair ora elimina anche documento `users` da Firestore (non solo cache locale)
   - Fix: gestione graceful quando documento famiglia non esiste durante unpair
   - Previene loop "famiglia corrotta" durante secondo pairing

**Miglioramenti UX:**

- ✅ Dialog con 3 opzioni chiare (Tutti / I Miei / Del Partner)
- ✅ Messaggi di conferma specifici per ogni modalità
- ✅ Pulizia cache automatica quando partner elimina tutto
- ✅ Nessun documento residuo dopo unpair
- ✅ Secondo pairing funziona senza errori

**File Modificati:**
- `settings_screen.dart`:
  - Redesign `_deletePairing()` con parametro `mode` ('all'|'mine'|'partner')
  - Dialog aggiornato con 3 opzioni distinte
  - Logic per scrivere flag `delete_cache_requested` su Firestore
- `pairing_service.dart`:
  - Callback `onPartnerDeletedAll` per pulizia cache
  - Listener per flag `delete_cache_requested` nel documento partner
  - Auto-unpair ora elimina documento users da Firestore
  - Fix: controllo messaggi server per distinguere "Elimina Tutto" vs "Cambio Telefono"
- `chat_service.dart`:
  - Fix: `deleteMessagesAndCoupleSelfie()` gestisce gracefully documento mancante
  - Try-catch per errore NOT_FOUND di Firestore
- `main.dart`:
  - Configurazione callback `onPartnerDeletedAll`
  - Cleanup automatico cache messaggi + foto quando partner elimina tutto

**UX Flow "Elimina Messaggi del Partner":**
- 📱 Telefono A fa "Elimina Messaggi del Partner"
- 🔥 Scrive flag `delete_cache_requested: true` nel documento di B su Firestore
- 📲 Telefono B apre app → listener rileva flag
- 🗑️ B automaticamente: unpair + pulisce cache messaggi + pulisce foto coppia
- ✅ Flag rimosso, B pronto per nuovo pairing pulito

**Bug Fix:**
- ✅ Auto-unpair ora elimina documento Firestore (non solo cache)
- ✅ Gestione NOT_FOUND quando documento famiglia non esiste
- ✅ Nessun loop "famiglia corrotta" durante re-pairing
- ✅ Cache sempre sincronizzata tra i due dispositivi

---

### 🎨 v1.7.0 - UI Redesign Purple/White + Couple Selfie (21 Dicembre 2025)

**Design Completo Rinnovato:**

1. **💜 Purple/White Theme**
   - Gradiente viola (#667eea → #764ba2) in tutta l'app
   - Design minimalista e moderno
   - Card bianche con ombre e bordi arrotondati
   - Palette colori coerente in tutte le schermate

2. **🍔 Hamburger Menu + Floating Icons**
   - Rimossa bottom navigation bar
   - Menu hamburger in alto a sinistra (floating)
   - Drawer con gradiente viola
   - Tondino pairing status in alto a destra (floating)
   - Massimo spazio per la chat

3. **🚀 Smart Pairing Wizard**
   - Design completamente ridisegnato con tema viola/bianco
   - QR code viola personalizzato
   - **Step 1**: Completamento automatico quando il QR è generato
   - **Step 2**: Scansione QR partner
   - **Smart Button**: Si illumina quando ENTRAMBI completano il pairing
     - Grigio + ⏳ "In attesa..." quando non pronto
     - Viola + 💬 "Vai alla Chat" quando pronto
   - Listener real-time su Firestore per sincronizzazione

4. **💑 Couple Selfie Feature**
   - Tap sul tondino in alto a destra → scatta/scegli selfie di coppia
   - **Crop circolare** con editor dedicato per centrare le facce
   - Foto appare su **entrambi i dispositivi** automaticamente
   - Sincronizzazione real-time via Firebase Storage + Firestore
   - Sostituisce il cuoricino quando caricata
   - Il **primo** che carica vince

5. **📱 Multi-Architecture Support**
   - Supporto dispositivi 32-bit (armeabi-v7a)
   - Supporto dispositivi 64-bit (arm64-v8a)
   - Fix crash su telefoni vecchi
   - NDK filters configurati correttamente

6. **🎯 Miglioramenti Chat**
   - + icona allegati grigia (stile calendario)
   - Icona diventa viola quando allegati selezionati
   - Send button abilitato per testo, todo O allegati
   - Immagini full-width con BoxFit.cover
   - Testo todo opzionale

**Miglioramenti Tecnici:**

- ✅ `image_cropper: ^8.0.2` per crop circolare
- ✅ `CoupleSelfieService` per gestione foto condivisa
- ✅ Firebase Storage rules aggiornate per couple_selfie_*
- ✅ Firestore rules aggiornate per campo `couple_selfie_url`
- ✅ UCropActivity dichiarata in AndroidManifest
- ✅ Consumer2 per pairing + selfie service
- ✅ Listener Firestore per smart button nel wizard
- ✅ Layout centered per QR code

**File Modificati/Creati:**
- `pubspec.yaml`: Versione 1.6.0+7 → **1.7.0+8**
  - Added `image_cropper: ^8.0.2`
- `main.dart`: Provider per CoupleSelfieService
- `main_screen.dart`:
  - Rimossa BottomNavigationBar
  - Aggiunto Drawer con gradiente
  - Floating hamburger menu (top-left)
  - Floating couple selfie/status (top-right con foto)
  - Consumer2 per real-time selfie updates
- `pairing_wizard_screen.dart`:
  - Complete redesign con purple/white theme
  - Removed manual checkbox for step 1
  - Smart button con Firestore listener
  - QR code centrato e styled in viola
  - Auto-navigation rimossa (manuale con button)
- `chat_screen.dart`:
  - Removed AppBar
  - Gray + icon (purple when selected)
  - Full-width image bubbles
  - Optional todo text
- `settings_screen.dart`:
  - Purple gradient buttons
  - White sections con shadows
  - Nuovo pairing flow (Nuovo/Ripristino)
- `couple_selfie_screen.dart`: NEW - Camera/gallery + crop screen
- `couple_selfie_service.dart`: NEW - Firebase sync service
- `storage.rules`: Regole per couple_selfie_url
- `firestore.rules`: Write permission per families/{familyId}
- `android/app/build.gradle`: NDK abiFilters
- `AndroidManifest.xml`: UCropActivity declaration

**UX Flow Selfie:**
- 📸 Tap tondino (quando paired) → apre CoupleSelfieScreen
- 📷 Scatta foto o scegli da galleria
- ✂️ Editor circolare per centrare facce
- ☁️ Upload automatico su Firebase
- 🔄 Sync su entrambi i dispositivi
- 💜 Foto appare nel tondino in tempo reale

**UX Flow Pairing:**
- 🔑 Step 1: Genera QR → ✅ auto-completato
- 📱 Step 2: Scansiona QR partner → ✅ completato quando scansioni
- ⏳ Button grigio "In attesa..." → aspetta il partner
- 💜 Button si illumina quando ENTRAMBI hanno completato
- 💬 Tap "Vai alla Chat" → inizia a messaggiare!

---

### 📎 v1.6.0 - Message Attachments with E2E Encryption (20 Dicembre 2025)

**Nuove Feature:**

1. **📎 Message Attachments - E2E Encrypted**
   - Supporto completo per **foto, video, documenti**
   - Cifratura end-to-end con **dual encryption** (AES-256 + RSA-2048)
   - Upload su Firebase Storage con file completamente cifrati
   - Metadata di cifratura separati per mittente e destinatario
   - Picker nativo per galleria, fotocamera, documenti

2. **🖼️ Smart Thumbnail System**
   - Generazione automatica thumbnail **150px** per foto
   - Thumbnail cifrate con **stesse chiavi AES** del full image
   - Riduzione ~70% banda per gallery/chat views
   - Upload separato su Firebase Storage (path `/thumbnails/`)
   - Quality JPEG ottimizzata (80) per performance

3. **💾 Attachment Cache Service**
   - Cache locale a **due livelli**: memoria + disco
   - Evita ri-download e ri-decifratura di file già visti
   - Cache key MD5 per thumbnail vs full resolution
   - Persistenza su filesystem con `path_provider`
   - Inizializzazione automatica al primo utilizzo

4. **📱 Fullscreen Image Viewer**
   - Visualizzatore fullscreen con **InteractiveViewer** (zoom 0.5x-4x)
   - **Tap-to-toggle overlay** con animazione fade (200ms)
   - Background nero per vista immersiva
   - Info file cifrato (nome, dimensione, lock icon)
   - Carica full resolution solo quando aperto

5. **🎨 UX Improvements**
   - Modal allegati con **gradiente viola** (stile calendario)
   - Icone bianche su cerchi semitrasparenti
   - Thumbnail in chat con **aspect ratio** preservato (BoxFit.contain)
   - ConstrainedBox invece di dimensioni fisse
   - MediaScreen con griglia 3 colonne per gallery

6. **🗄️ SQLite Attachments Support**
   - Database v4 con colonna `attachments_json`
   - Serializzazione/deserializzazione automatica JSON
   - Migration automatica da v3 → v4
   - Fix critico: messaggi con media persistono dopo restart
   - Batch save per performance

**Miglioramenti Tecnici:**

- ✅ Firebase Storage rules aggiornate per path con wildcards
- ✅ `file_picker` aggiornato a v8.1.6 (fix deprecation v1 embedding)
- ✅ `image` package v4.1.7 per thumbnail generation
- ✅ Dependency injection per `AttachmentService` (shared `EncryptionService`)
- ✅ Try-catch robusto per parsing attachments (no crash se errori)
- ✅ Thumbnail generation con `img.copyResize` (aspect ratio preservato)
- ✅ Dual encryption anche per thumbnail (stesso IV + chiave AES)

**File Modificati:**
- `pubspec.yaml`: Version 1.5.0+6 → **1.6.0+7**
  - `file_picker: ^6.1.1` → `^8.1.6`
  - `image_picker: ^1.0.4` → `^1.1.2`
  - Added `image: ^4.1.7`
- `storage.rules`: Path pattern con `{allPaths=**}` per thumbnails
- `attachment_service.dart`: Thumbnail generation, dual encryption, cache integration
- `attachment_cache_service.dart`: NEW - Two-tier cache (memory + disk)
- `encryption_service.dart`: New method `encryptFileWithExistingKey()`
- `message_cache_service.dart`: DB v4 con `attachments_json` column
- `chat_screen.dart`: Fullscreen viewer, attachment picker redesign, aspect ratio fix
- `media_screen.dart`: Gallery integration, fullscreen viewer, thumbnail usage
- `message.dart`: Try-catch for attachment parsing (error resilience)
- `chat_service.dart`: Debug logging for attachment messages

**Security Model:**
- 🔐 File cifrati **prima** dell'upload (AES-256)
- 🔐 Chiave AES cifrata **due volte** con RSA (sender + recipient)
- 🔐 Thumbnail cifrate con **stesse chiavi** del full image
- 🔐 Firebase Storage contiene **solo file binari cifrati**
- 🔐 Metadata cifratura salvati in Firestore (encrypted_key_sender/recipient, iv)

**UX Flow:**
- 📎 Tap allegato → modal viola si apre
- 📸 Scegli foto/video/documento
- 🔐 File cifrato automaticamente
- 🖼️ Thumbnail generata e cifrata (solo foto)
- ⬆️ Upload su Firebase Storage
- 💬 Messaggio inviato con attachments array
- 👁️ Thumbnail mostrata in chat (aspect ratio preservato)
- 🔍 Tap immagine → fullscreen viewer (zoom + overlay tap-to-toggle)
- 💾 Cache automatica (no ri-download)

---

### 📅 v1.5.0 - Todo System Complete Redesign (19 Dicembre 2025)

**Nuove Feature:**

1. **🎨 Inline Date/Time Picker - All Purple Design**
   - Modale completamente viola con gradiente pulito
   - Calendario integrato con tema custom bianco su viola
   - Scroll wheels iOS-style per ore e minuti (0-23 / 0-59)
   - Layout compatto (70% altezza schermo)
   - Zero spazi vuoti, design ottimizzato

2. **📝 Smart Placeholder System**
   - "Scrivi un messaggio..." → modalità normale
   - "Nuovo todo" → quando calendario selezionato
   - Sempre grigio, mai invadente
   - Feedback visivo chiaro ma discreto

3. **✓ Check Button Riposizionato**
   - Spostato da header a lato del time picker
   - Più comodo e raggiungibile
   - Cerchio bianco semitrasparente di background
   - Dimensione ottimizzata (36px)

4. **❌ X Button Intelligente**
   - Header solo con X in alto a sinistra
   - Se nessuna data → chiude la modale
   - Se data selezionata → cancella e chiude
   - Riclicca calendario per modificare/cancellare

5. **📱 UX Streamlined**
   - Rimossa X inline nel campo testo
   - Solo icona calendario (viola quando attiva)
   - Invio con tastiera (Enter)
   - Messaggi vuoti OK se c'è data selezionata
   - Flow pulito: seleziona → conferma → scrivi (opzionale) → invia

**Miglioramenti Tecnici:**

- ✅ SQLite schema v3: aggiunto campo `is_reminder` per distinguere todo da reminder
- ✅ Fix: reminder non mostrava più campanellino dopo riavvio app
- ✅ Database migration automatica (v2 → v3)
- ✅ CupertinoPicker per scroll nativo iOS-style
- ✅ Theme override per calendario bianco su viola
- ✅ Sentinel value per distinguere clear vs close
- ✅ Controllers properly disposed (no memory leaks)

**File Modificati:**
- `pubspec.yaml`: Version bump 1.4.0+5 → 1.5.0+6
- `message_cache_service.dart`:
  - Schema SQLite v3 con `is_reminder` column
  - Migration handler per upgrade automatico
  - Save/load `isReminder` field in cache
- `chat_screen.dart`:
  - Complete date/time picker redesign
  - All-purple modal design
  - Inline calendar icon (no separate button)
  - Smart placeholder logic
  - X button clear logic with sentinel value
  - Check button repositioned next to time picker

**UX Flow:**
- 📅 Tap calendario → modale viola si apre
- 📆 Seleziona data dal calendario integrato
- ⏰ Scroll ore/minuti con ruote iOS
- ✓ Tap check a lato → conferma e chiude
- 💜 Icona calendario diventa viola
- ✍️ Scrivi todo (o lascia vuoto)
- 📤 Enter → invia con reminder automatico (1h prima)

**Design Philosophy:**
- Minimal e pulito (no testi inutili)
- Tutto viola per coerenza visiva
- Controlli dove servono (check vicino ai picker)
- Feedback immediato (icona viola = attivo)
- Gesture naturali (riclicca per modificare)

---

### 💬 v1.5.0-beta - WhatsApp-Style Message Indicators (19 Dicembre 2025)

**Nuove Feature:**

1. **✓✓ Read Receipts (Spunte Letto/Consegnato)**
   - **Spunta singola (✓)** grigia: messaggio consegnato al server
   - **Doppie spunte (✓✓)** blu: messaggio letto dal destinatario
   - Aggiornamento **in tempo reale** (no refresh necessario)
   - Funziona anche con app aperta su entrambi i dispositivi
   - Approccio document-based per performance ottimali

2. **⌨️ Typing Indicator**
   - Indicatore "Sta scrivendo..." quando il partner digita
   - Scompare automaticamente dopo 2 secondi di inattività
   - Animazione circolare discreta
   - Aggiornamento real-time tramite Firestore
   - Controllo stale updates (ignora status > 5 secondi fa)

3. **🔧 Architettura Real-Time**
   - Collezione `/read_receipts` dedicata (come typing indicator)
   - Listener Firestore per aggiornamenti istantanei
   - 1 scrittura batch invece di N update individuali
   - Pattern "a razzo" 🚀 per performance eccellenti

**Miglioramenti Tecnici:**

- ✅ SQLite schema v2: aggiunti campi `delivered`, `read`, `read_at`
- ✅ Firestore security rules aggiornate per `/read_receipts`
- ✅ Auto-mark messaggi come letti quando arrivano (chat aperta)
- ✅ Lifecycle observer per marcare messaggi quando app ritorna in foreground
- ✅ Enhanced logging per debugging real-time updates

**File Modificati:**
- `message.dart`: Aggiunti campi read receipts al modello
- `message_cache_service.dart`: Schema SQLite v2 con migration
- `chat_service.dart`:
  - `_startReadReceiptsListener()` per real-time updates
  - `markAllMessagesAsRead()` con approccio document-based
  - `setTypingStatus()` e `_listenToPartnerTyping()` per typing indicator
- `chat_screen.dart`:
  - Checkmarks visivi in `_MessageBubble`
  - Typing indicator UI con CircularProgressIndicator
  - WidgetsBindingObserver per lifecycle events
  - Auto-mark on new message arrival (real-time)
- `firestore.rules`: Aggiunte regole per `/read_receipts` collection

**UX WhatsApp-Style:**
- ✅ Spunte solo sui messaggi inviati (non su quelli ricevuti)
- ✅ Colore blu per messaggi letti
- ✅ Dimensione 14px per icone discrete
- ✅ Indicatore typing posizionato sopra la text field
- ✅ Performance "a razzo" come il typing indicator

---

### 🎨 v1.4.0 - Todo UX Redesign & Smart Reminders (17 Dicembre 2025)

**Nuove Feature:**

1. **📅 Todo Redesign - Stile Messaggi**
   - Todo con aspetto identico ai messaggi normali (stesso gradiente, bordi, padding)
   - Rimossa intestazione "To Do" per UI più pulita
   - Icone dinamiche: 📅 calendario (evento) o 🔔 campanello (reminder)
   - Integrazione perfetta nel flusso di chat

2. **🔔 Smart Reminder System**
   - **Due messaggi automatici** quando crei un todo:
     - Messaggio principale (📅) - visibile subito con data evento
     - Messaggio reminder (🔔) - nascosto fino al momento del reminder
   - Reminder appare automaticamente in chat quando scatta (1h prima evento)
   - Timestamp dinamico: reminder si aggiorna all'ora corrente quando diventa visibile
   - Resta sempre "fresco" in cima alla chat, non bloccato nel passato

3. **👆 Long Press per Completare**
   - Rimosso bottone ingombrante "Completa"
   - Tieni premuto il messaggio todo → completato ✅
   - Hint discreto "Tieni premuto per completare"
   - UI più intuitiva e minimalista

4. **🎯 Smart Auto-Scroll**
   - Chat rimane ferma dopo long press (no scroll indesiderato)
   - Auto-scroll solo per messaggi veri, non per completamenti
   - Migliore UX quando si completa un todo

5. **🛡️ Cancellazione Automatica Reminder**
   - Completi todo → notifica locale cancellata automaticamente
   - Il reminder non partirà se hai già completato l'attività

**Miglioramenti UX:**
- ✅ Todo visivamente indistinguibili dai messaggi normali
- ✅ Reminder appare "magicamente" quando scatta
- ✅ Long press naturale e intuitivo
- ✅ Chat stabile (no scroll involontario)
- ✅ Icone corrette per mittente E destinatario

**File Modificati:**
- `message.dart`: Aggiunto campo `isReminder` per distinguere i due tipi
- `chat_service.dart`:
  - Nuovo metodo `sendTodoReminder()` per messaggio campanello
  - Auto-update timestamp reminder quando diventa visibile
  - Handler eventi `modified` per aggiornamenti Firestore
- `chat_screen.dart`:
  - Redesign completo `_TodoMessageBubble` (long press + icone dinamiche)
  - Filtro reminder futuri (nasconde fino al momento giusto)
  - Smart auto-scroll (skip per `todo_completed`)
- `pubspec.yaml`: Versione 1.3.0+4 → 1.4.0+5

---

### 🚀 v1.3.0 - Lazy Loading & Performance (17 Dicembre 2025)

**Nuove Feature:**

1. **💾 SQLite Message Cache**
   - Database locale per messaggi decriptati
   - Caricamento istantaneo all'avvio (< 100ms)
   - Elimina lag iniziale di decriptazione
   - Schema ottimizzato con indici per performance

2. **📜 Infinite Scroll**
   - Carica solo 100 messaggi iniziali (lazy loading)
   - Auto-carica 50 messaggi vecchi scrollando verso l'alto
   - Indicatore di caricamento visivo
   - Scalabile a migliaia di messaggi senza lag

3. **⚡ Reverse ListView Architecture**
   - ListView con `reverse: true` (indice 0 in basso)
   - Messaggi ordinati DESC (nuovi→vecchi)
   - **Zero auto-scroll** necessario al caricamento
   - Elimina completamente il "visual glitch" dopo app restart

**Miglioramenti Performance:**
- ✅ App restart: da ~2s a **< 100ms** per mostrare messaggi
- ✅ Build release: performance eccellenti (debug mode più lento)
- ✅ Scroll fluido anche con 1000+ messaggi
- ✅ Zero "salti" visivi durante caricamento

**File Modificati:**
- `chat_service.dart`: Aggiunto `loadOlderMessages()` + ordinamento DESC
- `message_cache_service.dart`: Implementato SQLite cache
- `chat_screen.dart`: Reverse ListView + infinite scroll listener
- `message.dart`: Campi cache aggiunti al modello

---

### 🚀 Major Dependencies Update

Tutte le dipendenze sono state aggiornate alle ultime versioni stabili:

**Android/Gradle:**
- Firebase BOM: 32.7.0 → **34.6.0** (latest stable)
- Google Services: 4.4.0 → **4.4.4**
- Java: 8 → **17 (LTS)**
- Kotlin JVM Target: 1.8 → **17**
- desugar_jdk_libs: 2.0.4 → **2.1.4**

**Flutter - Firebase:**
- firebase_core: 2.24.2 → **4.3.0** (+2 major versions)
- firebase_auth: 4.15.3 → **6.1.3** (+2 major versions)
- cloud_firestore: 4.13.6 → **6.1.1** (+2 major versions)
- firebase_messaging: 14.7.9 → **16.1.0** (+2 major versions)

**Flutter - Core Packages:**
- provider: 6.1.1 → **6.1.5**
- http: 1.1.0 → **1.6.0**
- shared_preferences: 2.2.2 → **2.5.4**
- flutter_secure_storage: 9.0.0 → **10.0.0**
- intl: 0.18.1 → **0.20.2**
- timezone: 0.9.2 → **0.10.1**
- flutter_local_notifications: 17.0.0 → **19.5.0**
- mobile_scanner: 3.5.2 → **7.1.4**
- flutter_chat_ui: 1.6.10 → **2.11.1**
- flutter_lints: 3.0.0 → **6.0.0**

**Totale:** 17 pacchetti aggiornati

### ✅ Deprecation & API Updates

**Rimossi:**
- ❌ `android.enableJetifier` (deprecato con AndroidX moderno)
- ❌ `package=` attribute in AndroidManifest (usa `namespace` da build.gradle)
- ❌ `uiLocalNotificationDateInterpretation` (deprecato in flutter_local_notifications 19.x)

**Aggiornati:**
- ✅ Storage permissions modernizzati per Android 13+
  - `READ/WRITE_EXTERNAL_STORAGE` limitati ad Android ≤12
  - Aggiunti `READ_MEDIA_IMAGES` e `READ_MEDIA_VIDEO` per Android 13+
- ✅ mobile_scanner API aggiornata (controller.value.torchState)

**Risultato:** ✨ Zero warnings, zero API deprecate, build pulito!

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

## 📅 To Do & Reminders Feature

L'app include un sistema di promemoria per eventi importanti (compleanni, anniversari, appuntamenti) completamente integrato con la crittografia end-to-end.

### Caratteristiche

- 📝 **To Do cifrati**: i promemoria sono messaggi speciali con crittografia E2E
- 🔔 **Notifiche duali**:
  - **Instant**: FCM push quando il partner crea un todo (`📅 Nuovo To Do`)
  - **Scheduled**: notifica locale 1 ora prima dell'evento (`🔔 Nuovo To Do`)
- 🎨 **UI distintiva**: bordo arancione (attivo), rosso (scaduto), verde (completato)
- ✅ **Completamento bidirezionale**: entrambi i partner possono marcare come completato
- 🧪 **Modalità test**: slider 10-3600 secondi per testing rapido
- 🌍 **Timezone auto-detection**: rileva automaticamente timezone del dispositivo

### Come usare

1. Nella chat, tap sull'icona **calendario** 📅
2. Inserisci il nome del todo (es. "Compleanno di Elena")
3. Seleziona data e ora dell'evento
4. Crea → il partner riceve una notifica instant
5. **1 ora prima** → entrambi ricevono il reminder schedulato

### Architettura

I todo sono **messaggi speciali** con:
- `messageType: 'todo'` (non cifrato, per filtrare le notifiche)
- `dueDate`: data/ora dell'evento
- `body`: contenuto cifrato E2E (RSA-2048 + AES-256)

Le notifiche scheduled usano `flutter_local_notifications` con:
- **Inexact alarms** (nessun permesso extra richiesto)
- **allowWhileIdle** (funzionano anche con schermo spento)
- Precisione: ±15 minuti (accettabile per reminder 1h prima)

Per la documentazione completa: **[TODO_FEATURE.md](./TODO_FEATURE.md)**

---

## 📁 Struttura del Progetto

```
youandme/
├── README.md                    # Questo file
├── MILESTONE.md                 # Documentazione v1.2 stable
├── TODO_FEATURE.md              # Documentazione To Do & Reminders feature
├── flutter-app/                 # App Flutter
│   ├── lib/
│   │   ├── main.dart           # Entry point + bottom navigation
│   │   ├── models/
│   │   │   └── message.dart    # Message model (dual encryption + todo fields)
│   │   ├── screens/
│   │   │   ├── chat_screen.dart              # Main chat UI + TodoMessageBubble + CreateTodoDialog
│   │   │   ├── settings_screen.dart          # Settings tab
│   │   │   ├── pairing_wizard_screen.dart    # Wizard pairing con checklist
│   │   │   ├── qr_display_screen.dart        # Mostra QR (public key)
│   │   │   └── qr_scanner_screen.dart        # Scansiona QR (public key)
│   │   └── services/
│   │       ├── pairing_service.dart          # RSA pairing logic
│   │       ├── chat_service.dart             # Firestore messaging + dual encryption + todo scheduling
│   │       ├── encryption_service.dart       # RSA-2048 + AES-256
│   │       └── notification_service.dart     # FCM + notifiche locali + scheduled reminders
│   ├── android/                 # Configurazione Android
│   │   ├── app/
│   │   │   ├── build.gradle
│   │   │   ├── google-services.json         # Firebase config
│   │   │   └── src/main/AndroidManifest.xml # Permessi + receivers per scheduled notifications
│   │   ├── gradle.properties                 # AndroidX enabled
│   │   └── settings.gradle                   # AGP + Kotlin versions
│   └── pubspec.yaml             # Flutter dependencies (+ timezone, flutter_local_notifications)
├── functions/                   # Cloud Functions per notifiche push
│   ├── index.js                # Funzioni Firebase (sendMessageNotification + todo filtering)
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

### 3. Firestore Security Rules (Production Ready v1.5)

Imposta le regole di sicurezza compartmentalizzate in Firebase Console (o usa `firebase deploy --only firestore:rules`):

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    match /families/{familyId} {
      // ❌ BLOCCA list() - Non puoi enumerare tutte le famiglie
      allow list: if false;

      // ✅ PERMETTI get() - Puoi leggere SE conosci il familyId
      allow get: if true;

      match /messages/{messageId} {
        // ✅ Leggi/scrivi messaggi SE conosci familyId
        allow read, write: if true;
      }

      match /users/{userId} {
        // ✅ Leggi/scrivi FCM tokens SE conosci familyId
        allow read, write: if true;
      }

      match /read_receipts/{userId} {
        // ✅ Leggi/scrivi read receipts SE conosci familyId
        // Usato per tracciare quali messaggi sono stati letti
        allow read, write: if true;
      }
    }
  }
}
```

#### Security Model (3 Layer)

**Layer 1 - Compartmentalization:**
- ❌ Impossibile enumerare tutte le famiglie (mass scraping bloccato)
- ✅ Accesso solo con `familyId` specifico
- 🛡️ `familyId = SHA256(pubKeys)` = 2^256 = impossibile brute force

**Layer 2 - Firebase Protection:**
- 🛡️ Rate limiting automatico + Abuse detection + IP blocking

**Layer 3 - E2E Encryption:**
- 🔐 Messaggi cifrati RSA-2048 (stesso standard di internet)
- 🔐 Senza chiavi private = dati inutili

> **Risultato:** Mass data scraping IMPOSSIBILE + Security by design (encryption + compartmentalization)

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

### ✅ Implementato (v1.5)
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
- [x] **To Do & Reminders** (notifiche schedulate 1h prima)
- [x] **Smart Reminder Messages** (appaiono automaticamente in chat quando scattano)
- [x] **Todo UX Redesign** (stile messaggi + icone dinamiche)
- [x] **Long Press to Complete** (gesture intuitivo)
- [x] **Dynamic Timestamps** (reminder sempre freschi)
- [x] **Smart Auto-Scroll** (no scroll dopo completamento)
- [x] **Modalità test** per developer testing
- [x] **SQLite Message Cache** (caricamento istantaneo)
- [x] **Lazy Loading** (100 messaggi iniziali)
- [x] **Infinite Scroll** (auto-carica 50 messaggi vecchi)
- [x] **Reverse ListView** (zero visual glitches)
- [x] **Read Receipts** (spunte letto/consegnato WhatsApp-style)
- [x] **Typing Indicator** ("Sta scrivendo..." real-time)
- [x] **Real-time Updates** (aggiornamenti istantanei senza refresh)
- [x] **Message Attachments** (foto, video, documenti cifrati E2E)
- [x] **Thumbnail System** (150px con cache locale)
- [x] **Fullscreen Viewer** (zoom + tap-to-toggle overlay)
- [x] **Attachment Cache** (memoria + disco, two-tier)
- [x] **Unpair Logic Redesign** (3 opzioni: Tutti/Miei/Partner)
- [x] **Auto Cache Cleanup** (quando partner fa "Elimina Tutto")
- [x] **Remote Cache Deletion** (triggera pulizia su altro dispositivo)
- [x] **Couple Selfie Redesign** (filename fisso + unpair logic corretta)
- [x] **Calendario TODO** (vista calendario con range e marker)
- [x] **TODO con Allegati** (foto/doc allegabili con E2E encryption)
- [x] **Widget Riutilizzabili** (TodoMessageBubble + AttachmentWidgets)
- [x] **Separatori Data Colloquiali** (Oggi, Ieri, formato italiano)
- [x] **Date Range Ottimizzato** (no ripetizioni mese)
- [x] **Media Scroll Bottom** (scroll automatico alle foto recenti)

### 🚧 Roadmap Future
- [ ] Autenticazione anonima Firebase + regole DB/Storage aggiornate
- [ ] Niente spunta se offline (gestione stato connessione)
- [ ] Prima botta di grafica (redesign UI/UX)
- [ ] Multiple device support
- [ ] iOS build completo
- [ ] Message deletion / editing
- [ ] Key rotation
- [ ] Recurring reminders
- [ ] AI todo extraction da messaggi
- [ ] Voice messages
- [ ] Group chats (3+ people)

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

**Versione:** 1.11.0+12
**Ultima modifica:** 2026-01-09
**Architettura:** RSA-only + Dual Encryption + SQLite Cache + Smart Reminders + Real-time Indicators + E2E Attachments + Couple Selfie Sync + Smart Unpair System + Reusable Widgets
**Performance:** ⚡ Instant load (< 100ms) + Zero visual glitches + Scalable to 1000+ messages + Real-time updates "a razzo" 🚀 + Thumbnail caching + Multi-architecture (32/64-bit) + Auto cache sync + Auto scroll media
**UX:** 🎨 Purple/White Modern Design + Hamburger Menu + Floating Icons + Smart Pairing Button + Couple Selfie with Circular Crop + WhatsApp-style indicators + Dynamic Timestamps + Fullscreen viewer + 3-way Unpair Options + Calendario TODO + Colloquial Date Separators + Smart Date Range Format
**Security:** 🔐 AES-256 + RSA-2048 dual encryption for messages AND files + Firebase Storage with encrypted binaries + Compartmentalized security rules + Robust pairing validation + TODO attachments encrypted E2E
**Dependencies:** ✅ Updated to latest stable versions (Jan 2026) + image_cropper for circular crop + table_calendar ^3.1.2
**Reliability:** 🛡️ Graceful error handling + Auto cleanup on unpair + No corrupted families + Second pairing always works + Fixed couple photo logic
**Widgets:** 🧩 Reusable TodoMessageBubble + AttachmentWidgets (Image/Video/Document) + Shared across chat and calendar + Consistent UI/UX everywhere
