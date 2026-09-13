# Changelog

Tutte le modifiche notevoli a questo progetto saranno documentate in questo file.

## [1.36.0] - 2026-09-11

### 🔐 Ripristino dopo reinstallazione (fix perdita messaggi)
- L'app non genera più una coppia di chiavi RSA all'avvio: su un telefono reinstallato la chiave nuova veniva scambiata dal Ripristino per il certificato "già presente", il pairing creava una nuova chat e i vecchi messaggi restavano indecifrabili. Le chiavi si creano solo nel flusso "Nuovo pairing".
- Ripristino: "Certificato già presente" solo se completo (chiave + partner); il pulsante "Incolla certificato" è sempre disponibile; la chiave pubblica viene sempre derivata dalla privata incollata; il ripristino cloud viene tentato anche se in locale c'è una chiave orfana.
- Backup: il certificato copiato include sempre chiave pubblica e (se presente) chiave del partner; dopo un ripristino dal cloud la strategia "cloud" viene riattivata; a pairing completato, con backup manuale, un promemoria invita a risalvare il certificato.
- Spiegazione in-app prima della richiesta dei permessi posizione, microfono e fotocamera (richiesta da Google Play).
- **Impostazioni → "Verifica backup"**: riscrive e rilegge il backup cloud (o controlla la copia manuale) e dice se è presente, completo e quando è stato salvato.
- **Promemoria backup manuale**: se il certificato è cambiato dopo l'ultima copia (es. dopo un pairing) un banner in chat invita a ricopiarlo, con accesso diretto alla pagina Backup.
- **"Condividi come file"**: il certificato manuale si può salvare come file di testo (Files, gestore di password, AirDrop) oltre che copiarlo negli appunti.
- **iOS: backup cloud reale su iCloud Keychain.** La scelta "cloud" ora salva il certificato in un elemento del Keychain sincronizzato con iCloud: cambiando iPhone (stesso Apple ID, iCloud Keychain attivo) il certificato c'è già. Prima l'opzione non salvava nulla e funzionava solo perché il Keychain locale sopravvive alla disinstallazione.
- Backup cloud Android più robusto: se il salvataggio nel Block Store fallisce l'utente viene avvisato (prima passava in silenzio); il blob viene riscritto a ogni avvio; la lettura viene ritentata se Play Services non è pronto; i backup nel formato di giugno 2026 (senza marcatore) vengono ripristinati invece di essere cancellati.

### 📤 Condivisione verso TuyJo (link/foto da altre app)
- **iOS: link condiviso arrivava due volte in chat.** L'AppDelegate inviava il testo a Flutter e lo teneva anche per la richiesta successiva (`getInitialSharedText`): entrambi finivano in un messaggio. Allineato ad Android, che era già corretto.
- L'estensione di condivisione gestisce il contenuto una sola volta e si chiude sempre dopo aver aperto l'app (prima restava viva e poteva rimandare il contenuto).
- Lato Flutter: lo stesso testo condiviso ricevuto entro 20 s viene ignorato; l'handler del canale viene rimosso alla chiusura della chat.
- I file copiati dalla Share Extension nel container dell'App Group vengono cancellati dopo l'uso (prima restavano in chiaro per sempre).
- Nel foglio di condivisione iOS l'estensione si chiama "Tuijo" invece di "ShareExtension".
- **Più foto insieme**: l'estensione iOS ora accoda tutti gli elementi condivisi (fino a 10 immagini, documenti, testo) invece di prendere solo il primo; due condivisioni ravvicinate non si sovrascrivono più.
- Rimosso il trucco con API private per aprire l'app dall'estensione (rischio App Review): se l'apertura non riesce, un avviso invita ad aprire Tuijo e il contenuto viene inserito al primo avvio.
- Il contenuto in attesa nel container condiviso è protetto con NSFileProtectionComplete e cancellato dopo la lettura; niente più log di debug accumulato.
- Se non sei abbinato o la chat non è pronta, la condivisione non sparisce più in silenzio: un avviso spiega cosa è successo (contenuto lasciato nel campo messaggio / abbina prima i telefoni).
- Android: dichiarata la condivisione multipla di testo (`SEND_MULTIPLE text/*`), i testi arrivano in un unico messaggio.
- Rimossa la dipendenza inutilizzata `receive_sharing_intent`.

### 🖼️ Store e localizzazione
- **Android**: rimossa `FOREGROUND_SERVICE_CAMERA` (dichiarata dal plugin CallKit per le videochiamate, che TuyJo non ha). Build 45.
- **Nuovi screenshot per App Store e Google Play** (iPhone 6,9", iPad 13", telefono e tablet Android, immagine in evidenza) in it/en/es/ca, generati da `store/screenshots/` con lo stile del sito.
- Indicatore "sta scrivendo" neutro in en/es/ca ("Typing..." / "Escribiendo..." / "Escrivint...").
- Calendario: in catalano le iniziali dei giorni erano tutte "D"; ora mostra "DL DT DC DJ DV DS DG".

### 📞 Chiamate vocali: riscrittura del motore peer-to-peer
- **ICE restart automatico**: un cambio di rete (Wi-Fi ↔ 4G, ascensore, cambio cella) non chiude più la chiamata. Dopo 4 s di grace period il caller rinegozia (fino a 3 tentativi); il callee, se è lui a perdere la rete, chiede il restart via signaling. Stato "riconnessione…" in UI.
- **Pop-up "Chiamata non disponibile in peer to peer"**: se i due telefoni non trovano un percorso diretto (NAT simmetrico / CGNAT) compare un avviso grande e chiaro con il suggerimento di cambiare rete, invece di uno squillo infinito.
- **Signaling cifrato end-to-end**: offer, answer e candidati ICE sono cifrati con AES-256-GCM e una chiave di sessione avvolta con la chiave RSA del partner. Firestore non vede più SDP, fingerprint DTLS né indirizzi IP: niente MITM da chi conosce il familyChatId.
- **Coda dei candidati ICE**: i candidati arrivati prima della remote description non vengono più scartati (connessione più rapida e affidabile).
- **`callId` univoco per chiamata**: il documento `calls/current` viene sovrascritto (non più merge), i candidati residui di chiamate precedenti vengono ignorati. Niente più answer "fantasma" dopo un crash.
- **Data channel di controllo P2P**: riaggancio e stato muto viaggiano direttamente tra i telefoni (istantanei, senza passare da Firestore). Il documento eliminato viene trattato come riaggancio.
- **Annullamento chiamata**: se il caller riaggancia mentre squilla, il telefono del partner smette subito di squillare (push `call_cancelled` + listener sul documento). Timeout allineati a 30 s su entrambi i lati.
- **Qualità audio**: Opus con FEC in-band, mono, 40 kbps, fullband 48 kHz; vincoli espliciti AEC / noise suppression / AGC / highpass; sessione audio nativa in modalità voce (`voiceChat` + 48 kHz su iOS, `inCommunication` + `voiceCommunication` su Android) con supporto Bluetooth.
- **Indicatore di qualità** (RTT, jitter, perdita pacchetti da `getStats()`) e percorso di rete (host / srflx) mostrati durante la chiamata. "Il partner è in muto" visibile in UI.
- **iOS: PushKit VoIP**: le chiamate in arrivo arrivano via push VoIP (APNs diretto dalla Cloud Function) e squillano anche ad app chiusa o in Low Power Mode. Le chiamate in uscita sono registrate in CallKit (lock screen, sessione audio gestita dal sistema). Ringback tone anche su iOS.
- **Android: foreground service** con tipo microphone durante la chiamata (in uscita e in entrata): il microfono resta attivo con app in background o schermo spento. Ripristino della chiamata accettata se l'app viene avviata da CallKit.
- Aggiornate `flutter_webrtc` 1.6.2 (libwebrtc 150) e `flutter_callkit_incoming` 3.1.5.
- Rimossi i pulsanti accetta/rifiuta in-app (codice morto: la risposta avviene sempre dalla UI nativa). Il timer parte alla connessione ICE reale, non al segnale Firestore.
- **Sensore di prossimità**: lo schermo si spegne quando il telefono è all'orecchio e si riaccende quando lo allontani (wake lock proximity su Android, proximity monitoring su iOS). Attivo solo a chiamata connessa e con altoparlante spento.
### 📍 Condivisione posizione
- **La tua condivisione non si spegne più se il partner chiude la schermata** o perde il GPS: termina solo con lo stop manuale o alla scadenza. Aggiunto un timer di scadenza (prima scattava solo se ti muovevi).
- **"Vieni qua" manda la posizione una volta sola**: prima continuava a trasmettere in tempo reale come "Sto arrivando".
- **Tolto il permesso "posizione sempre"**: non serviva (foreground service Android e background mode iOS bastano con "mentre usi l'app"), causava un prompt in inglese e la revisione dedicata su Google Play. Rimosso `ACCESS_BACKGROUND_LOCATION` dal manifest.
- Schermata di navigazione: avvio a transizione conclusa (niente più schermo a metà), stream GPS con filtro di distanza al posto del fix ogni 5 secondi, scritture del ricevente al massimo ogni 10 s, pulsante per interrompere la condivisione, testo "Condivisione avviata" per chi condivide con suggerimento a non chiudere l'app dal task switcher.
- Lo stop non resta più bloccato se il documento non esiste; un errore di decifratura non uccide più il listener del partner; mai più coordinate scritte in chiaro.
- iOS: abilitate le macro `PERMISSION_*` di permission_handler nel Podfile. Senza, la richiesta della fotocamera per il pairing via QR rispondeva "negato" senza mai mostrare il prompt.
- Modalità di condivisione rinominate "Tempo reale" / "Questa posizione".

### 🔴 Badge e messaggi non letti
- **Badge iOS corretto**: il push impostava sempre "1" e l'app non lo azzerava mai. Ora la Cloud Function conta i messaggi del partner non ancora letti e l'app azzera il badge quando leggi. Su Android una sola notifica con il conteggio giusto.
- **Messaggi non più marcati letti in background** su Android: la lettura automatica scatta solo con app in primo piano e chat visibile. Prima risultavano letti col telefono in tasca.

### 🌍 Localizzazione
- Descrizioni dei permessi iOS complete in it/en/es/ca (mancava quella della posizione in background), accenti corretti, `CFBundleLocalizations` dichiarato.
- Chiamata in arrivo: nome chiamante "Il mio amore", pulsanti Accetta/Rifiuta, notifica di chiamata persa e nomi dei canali notifiche Android nella lingua del dispositivo.

### ⚙️ Infrastruttura
- Cloud Functions su Node 22, firebase-functions 6, firebase-admin 13.

## [1.35.0] - 2026-06-15

### 🔔 Notifiche e permessi (le notifiche non sono più obbligatorie)
- **Le notifiche sono ora opzionali**: l'app funziona anche senza (i messaggi arrivano quando l'app è aperta). Niente più messaggio coercivo "le notifiche sono richieste" a ogni avvio.
- Se le notifiche sono disattivate compare un avviso **gentile e ignorabile** con "Apri impostazioni" e "Non voglio le notifiche": scelto una volta, non riappare più (opt-out persistente).
- Rimosso il dialog di sistema "Notification permission is required" che il modulo chiamate (CallKit) riproponeva a ogni avvio.
- Testi dei permessi ammorbiditi in it/en/es/ca: da "necessarie" a "consigliate".

### 📷 Pairing più chiaro
- Se manca il permesso fotocamera, lo scanner del QR mostra una **spiegazione chiara** ("serve per inquadrare il QR del partner") con accesso diretto alle impostazioni, invece di una schermata nera senza indicazioni.

## [1.34.0] - 2026-06-12

### 🔐 Backup del certificato
- **Scelta esplicita della strategia di backup** in una pagina dedicata stile wizard:
  - **Cloud automatico** (Google Block Store / iCloud): cambiando telefono con lo stesso account ritrovi tutto in automatico
  - **Manuale**: anteprima del certificato + bottone copia negli appunti; lo custodisci dove decidi tu (gestore password, nota cifrata, carta) — niente file, niente condivisione, niente cloud
- **Nuova pagina Ripristino**: cerca il certificato da sola (già sul telefono → cloud → incolla dagli appunti) e, se il certificato è completo (include la chiave del partner), **riconnette direttamente alla chat senza rifare il QR**

### 🗑️ Elimina Messaggi ripensato (modello "Dov'è" di Apple)
- Nuova pagina dedicata (non più dialog) con 3 modalità come card selezionabili:
  - **Tutti**: pairing + messaggi eliminati da entrambi i telefoni E dal server — irreversibile, con conferma
  - **I Miei**: svuota solo questo telefono; il partner resta in chat e non si accorge di nulla; rientrando col pairing recuperi tutto dal server
  - **Del Partner**: svuota solo il telefono del partner; tu resti in chat senza interruzioni
- **Fix**: le modalità selettive spaiavano entrambi i telefoni (flag `delete_cache_requested` processato solo con famiglia completa + listener "zombie" mai cancellati che facevano scattare la pulizia famiglia-corrotta)
- Il telefono svuotato non riceve più notifiche per la chat che non ha più (token FCM rimosso, niente ri-registrazione su refresh)

### 🧹 Impostazioni ripulite
- Non accoppiato: solo **Nuovo Pairing** e **Ripristino**
- Accoppiato: solo **Ripristino Partner** e **Backup Certificato**
- Rimossi bottoni e flussi legacy (copia chiave negli appunti, ripristino a dialog con file picker, dialog morti) e 20 chiavi di traduzione orfane

### 📅 Todo e calendario
- Chip **"+ Aggiungi"** stile Calendario Apple nella vista calendario
- Avvisi allineati ovunque (rotella + scheda Nuovo todo): Nessuno / 1h / 2h / 8h / 1 giorno / 2 giorni / **1 settimana**

### 🌍 Localizzazione completa
- Audit su tutta l'app: ~55 nuove stringhe localizzate in it/en/es/ca (pagine backup e ripristino, scheda Nuovo todo, notifiche locali, placeholder "[Messaggio non decifrabile]", notifica del GPS in background, ecc.)
- Il formato data dei todo segue la lingua dell'app (era forzato a italiano)

### 🐛 Correzioni
- **La tastiera del partner non si chiude più** quando l'altro sta scrivendo (l'indicatore "sta scrivendo" ricreava la barra di input per mancanza di key)
- **"Condividi posizione" non si apre più a metà schermo** (richiesta permesso GPS spostata a transizione conclusa + snapshotting della route disattivato)

## [1.33.0] - 2026-05-29

### ✨ Nuova interfaccia calendario (todo)
Il selettore di data/ora per i todo passa da modale a tutto schermo a **overlay inline** nella chat:
- **Non copre più la barra di input**: puoi continuare a scrivere e leggere il testo del todo mentre scegli il giorno.
- **Consapevole della tastiera**: aprendo la tastiera l'overlay si nasconde, richiudendola riappare nello stesso stato.
- **Invio in un solo passo**: premendo "invia" la selezione (data + ora + alert) viene applicata al messaggio e l'overlay si chiude.
- **Box riepilogo dinamico** in alto: mostra giorno/intervallo, ora e alert; tap per modificare ora/alert inline, ✕ rossa per azzerare la data tenendo il calendario aperto.
- Pulsante di chiusura ✕ spostato in alto a sinistra (coerente con le schermate media) e **alert predefinito a 2 ore** prima per i nuovi todo.

### 🧹 Pulizia tecnica
- Rimossi gli **screen QR pairing legacy** ormai inutilizzati (codice morto).
- Migrazione `withOpacity()` → `withValues(alpha:)` su tutto il codice (deprecazione Flutter 3.27+).

### 📝 Note
- Include tutte le migliorie di prestazioni e i fix della 1.32.0 (sotto), tra cui lo **scroll infinito dei messaggi** e il **fix del limite a 100 messaggi**.
- Annullato il restyle grafico sperimentale: mantenuto il design visivo originale.

## [1.32.0] - 2026-04-23

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

#### Firestore / Auth
- **Cap snapshot Firestore iniziale** e batch delle update di read-receipt
- **Eliminata cascata di retry** del token di autenticazione Firebase
- **Fix timing** sul tracciamento upload completo

#### Chat e Media
- **Scroll infinito messaggi storici**: la chat parte veloce con gli ultimi 100 messaggi; scrollando in alto si caricano progressivamente quelli più vecchi. Spinner in cima durante il caricamento.
- **Archivio completo in background**: al primo avvio di una chat lunga, idratazione completa dei messaggi storici (cache SQLite + paginazione Firestore via cursor `startAfterDocument`), senza bloccare la UI.
- **Galleria media completa**: foto, link e documenti di tutta la cronologia sono visibili nella sezione Media, non solo degli ultimi 100 messaggi.

### 🐛 Bug Fix
- **Fix critico migration SQLite**: dopo aggiornamento da versione precedente, la migration del database falliva con `duplicate column name: deleted` se la colonna era già stata creata in una release precedente. Conseguenza: la galleria Media e lo scroll storico restavano bloccati a 100 messaggi. Ora tutte le `ALTER TABLE ADD COLUMN` sono idempotenti (check via `PRAGMA table_info`).
- **Avvio lento dell'app** e **PDF condivisi trattati come URL**: corretti
- **Bolla foto che lampeggiava vuota** nella transizione pending → sent: risolto

### 🔧 Modifiche Tecniche
- Aggiunta dipendenza `cryptography_flutter` per backend nativo
- Refactor del pipeline di encryption/decryption per essere isolate-safe
- Pagination Firestore cursor-based (robusto a tipi misti di `created_at`)
- Helper `_addColumnIfMissing` per migration SQLite safe su upgrade

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
