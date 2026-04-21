# Changelog

Tutte le modifiche notevoli a questo progetto saranno documentate in questo file.

## [1.30.0] - 2026-04-21

### ⚡ Performance

#### Crittografia
- **Backend nativo AES-GCM**: switch a `cryptography_flutter` per usare AES-GCM nativo su iOS/Android
- **Crypto fuori dal main isolate**: cifratura/decifratura pesante spostata in isolate dedicato per UI fluida stile WhatsApp
- **Decrypt batch dei messaggi vecchi** durante lo scroll infinito per ridurre i jank

#### Invio foto e allegati
- **Pipeline upload parallela**: invio foto 3-5x più veloce
- **Generazione thumbnail nativa**: collassata in una singola chiamata `FlutterImageCompress`
- **Pre-populate cache allegati** dopo l'upload per evitare il download di ritorno
- **Prevenzione upload duplicati paralleli** dello stesso allegato
- **Logging TIMING fase-per-fase** sul flusso send foto

#### Firestore / Auth
- **Cap snapshot Firestore iniziale** e batch delle update di read-receipt
- **Eliminata cascata di retry** del token di autenticazione Firebase
- **Fix timing** sul tracciamento upload completo

#### Chat e Media
- **Scroll infinito messaggi storici**: `loadOlderMessages` è ora collegato allo scroll listener; quando arrivi vicino al top carichi 50 messaggi dalla cache SQLite (fallback Firestore se serve), con spinner di caricamento in cima
- **Galleria media con archivio completo**: entrando nella sezione Media idratiamo tutti i messaggi dalla cache locale (one-shot per sessione), così foto/link/documenti storici sono visibili senza dover scrollare tutta la chat. Zero costo di rete, zero decrypt extra.

### 🐛 Bug Fix
- **Avvio lento dell'app** e **PDF condivisi trattati come URL**: corretti
- **Bolla foto che lampeggiava vuota** nella transizione pending → sent: risolto

### 🔧 Modifiche Tecniche
- Aggiunta dipendenza `cryptography_flutter` per backend nativo
- Refactor del pipeline di encryption/decryption per essere isolate-safe
- Build number incrementato a 33

## [1.13.2] - 2026-01-18

### 🐛 Bug Fix

#### Notifiche
- **Fix badge notifiche persistente**: Risolto problema del badge che rimaneva visibile anche dopo aver letto tutti i messaggi
  - Aggiunto metodo `clearBadge()` in `NotificationService`
  - Badge si azzera automaticamente quando l'app viene aperta
  - Badge si azzera quando l'app ritorna in foreground (resumed)
  - Cancellazione automatica di tutte le notifiche dalla barra notifiche
  - File modificati: `notification_service.dart:209-218`, `chat_screen.dart:249,383`

#### Android
- **Rimossa autorizzazione AD_ID**: Eliminata autorizzazione pubblicitaria non necessaria
  - Aggiunto `tools:node="remove"` per AD_ID in AndroidManifest
  - TuyJo non usa pubblicità né tracciamento
  - Risolve warning Google Play Console
  - File modificato: `AndroidManifest.xml:52-54`

### 🔧 Modifiche Tecniche
- Integrazione `FlutterLocalNotificationsPlugin.cancelAll()` per pulizia notifiche
- Chiamate automatiche a `clearBadge()` nei lifecycle hooks dell'app
- Sincronizzazione tra stato "messaggio letto" e pulizia badge OS
- Rimozione esplicita autorizzazioni pubblicitarie da manifest Android

## [1.8.0] - 2024-12-22

### 🍎 Supporto iOS

#### Nuova Piattaforma
- ✅ **Supporto completo iOS 15.0+**
- Build e deployment su dispositivi iOS e simulatore
- Configurazione Xcode con code signing automatico
- Firebase configurato per iOS (Authentication, Firestore, Storage, Messaging)
- CocoaPods setup con deployment target iOS 15.0

#### Configurazione
- Podfile configurato con iOS 15.0 minimum deployment
- Info.plist con permessi camera, foto libreria, notifiche
- Support for URL schemes (http, https)
- Document types per immagini, video e PDF

#### Documentazione
- BUILD_NOTES.md aggiornato con istruzioni complete iOS
- README.md aggiornato con requisiti e setup iOS
- Istruzioni per build release e distribuzione TestFlight

### 📦 Infrastruttura
- Incrementata versione a 1.8.0 (Build 9)
- Configurazione multi-piattaforma Android + iOS
- Setup Firebase per entrambe le piattaforme

## [1.7.0] - 2024-12-21

### ✨ Nuove Funzionalità

#### URL e Indirizzi Cliccabili
- Rilevamento automatico di URL e indirizzi nei messaggi
- Link sottolineati (bianco per messaggi inviati, blu per ricevuti)
- Apertura link in browser/app esterne con un tap
- Funziona sia nei messaggi normali che nei todo
- Package: `flutter_linkify`, `url_launcher`

#### Condivisione File da Altre App
- Supporto completo share intent su Android
- Condividi foto, video, PDF e documenti da qualsiasi app
- Comparsa automatica come opzione di condivisione nel sistema
- Supporto condivisione multipla di file
- File condivisi vengono aggiunti automaticamente agli allegati
- Package: `receive_sharing_intent`

#### Viewer PDF Integrato
- Visualizzazione PDF direttamente nell'app
- Zoom e scroll per navigare i documenti
- Supporto multi-pagina
- Altri formati di documento si aprono con app esterne
- Package: `pdfx`, `open_filex`

#### Pagina Media Unificata
- Rimosso menu di selezione foto/video/documenti
- Tutti i media mostrati insieme in una griglia 3x3
- Layout compatto per documenti con icona e badge estensione
- Thumbnail per foto e video
- Tap per aprire a schermo intero o nel viewer

#### Cache Offline Foto Profilo
- Foto profilo coppia salvata in cache locale
- Cache a due livelli: memoria RAM + storage disco
- Visibile anche offline dopo il primo caricamento
- Caricamento automatico all'avvio

### 🚀 Miglioramenti

#### Ottimizzazione UI/UX
- Messaggi con allegati mostrano placeholder durante il caricamento
- Bubble messaggio appare immediatamente (optimistic UI)
- Layout documenti migliorato con titoli troncati (ellipsis)
- Gestione robusta file condivisi con `PostFrameCallback`

#### Performance
- Ridotto uso risorse con cache intelligente
- Caricamento progressivo messaggi (infinite scroll)
- Gestione memoria ottimizzata per allegati

#### Build e Configurazione
- Configurazione JVM unificata per tutti i subprojects
- Validazione JVM target impostata a warning per compatibilità
- Supporto Java 17 per tutto il progetto
- Fix incompatibilità build con package esterni

### 🐛 Bug Fix

#### Condivisione File
- **Fix schermo bianco**: Risolto problema quando si condividevano PDF da altre app
  - Implementato `WidgetsBinding.instance.addPostFrameCallback`
  - Aggiunto controllo `mounted` prima di `setState`
  - Garantisce widget completamente inizializzato

#### Layout Documenti
- **Fix titoli lunghi**: Documenti con nomi lunghi non rompono più il layout
  - Usato `Expanded` widget per contenere il testo
  - Aggiunto `maxLines: 2` e `overflow: TextOverflow.ellipsis`

#### Cache Foto Profilo
- **Fix offline**: Foto profilo ora visibile anche offline dopo kill app
  - Implementata cache disco con `path_provider`
  - Cache memoria per accesso veloce
  - Caricamento da cache all'avvio se disponibile

#### Apertura URL
- **Fix permessi**: Configurati permessi necessari per aprire URL esterni
  - Android: Aggiunte queries per intent VIEW http/https
  - iOS: Aggiunto LSApplicationQueriesSchemes
  - Gestione errori con try-catch invece di canLaunchUrl

### 🔧 Modifiche Tecniche

#### Android
- Aggiornate configurazioni `AndroidManifest.xml`:
  - Intent-filter per SEND e SEND_MULTIPLE
  - Queries per url_launcher
  - Supporto mimeTypes: image/*, video/*, application/*, text/*
- Configurato `build.gradle` per JVM 17 su tutti i subprojects
- Aggiunto `kotlin.jvm.target.validation.mode=warning` in `gradle.properties`

#### iOS
- Aggiornato `Info.plist`:
  - CFBundleDocumentTypes per immagini, video, PDF
  - LSApplicationQueriesSchemes per http/https
  - LSHandlerRank impostato a "Alternate"

#### Dipendenze Aggiunte
```yaml
flutter_linkify: ^6.0.0
url_launcher: ^6.3.1
receive_sharing_intent: ^1.8.0
pdfx: ^2.7.0
open_filex: ^4.5.0
```

### 📝 Note Tecniche

#### Compatibilità JVM
- Progetto configurato per Java/Kotlin 17
- Package `pdfx` usa Java 11 internamente
- Validazione JVM impostata a warning per permettere versioni miste
- Build funziona correttamente nonostante il warning

#### Limitazioni iOS
- Condivisione file da altre app ha supporto base
- Per pieno supporto share extension su iOS serve configurazione Xcode
- Apertura documenti funziona, condivisione completa richiede setup aggiuntivo

---

## [1.6.0] - 2024-XX-XX

### Funzionalità Base
- Messaggistica end-to-end criptata (RSA 2048 + AES 256)
- Pairing con QR code
- Todo e reminder condivisi
- Condivisione foto e video
- Typing indicator
- Read receipts
- Notifiche push
- Infinite scroll messaggi

---

## Formato

Il formato è basato su [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
e questo progetto aderisce a [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

### Categorie
- **✨ Nuove Funzionalità** - per nuove feature
- **🚀 Miglioramenti** - per miglioramenti di funzionalità esistenti
- **🐛 Bug Fix** - per bug fix
- **🔧 Modifiche Tecniche** - per modifiche tecniche/refactoring
- **📝 Note Tecniche** - per note importanti sulla release
