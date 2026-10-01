# Tuijo

**Una chat privata per due.** Messaggi, promemoria condivisi, foto e documenti,
posizione e chiamate vocali fra due telefoni abbinati con un QR, cifrati
end-to-end. Nessun account, nessun numero di telefono.

| | |
|---|---|
| Versione app | **1.37.0** (build 47) — vedi [`flutter-app/CHANGELOG.md`](flutter-app/CHANGELOG.md) |
| Piattaforme | iOS 15+ · Android 6+ (API 23) |
| Lingue | italiano, inglese, spagnolo, catalano |
| Sito | <https://tuijo.app> |
| Store | [App Store](https://apps.apple.com/it/app/tuijo/id6757800731) · [Google Play](https://play.google.com/store/apps/details?id=com.privatemessaging.private_messaging) |
| Contatti | info@tuijo.app |

---

## Indice

1. [Cosa fa l'app](#cosa-fa-lapp)
2. [Come funziona la cifratura](#come-funziona-la-cifratura)
3. [Struttura del repository](#struttura-del-repository)
4. [Sviluppo](#sviluppo)
5. [Backend Firebase](#backend-firebase)
6. [Sito e screenshot degli store](#sito-e-screenshot-degli-store)
7. [Rilascio](#rilascio)
8. [Debito tecnico noto](#debito-tecnico-noto)
9. [Storico versioni](#storico-versioni)

---

## Cosa fa l'app

### Abbinamento
- Due passi nel wizard (`pairing_wizard_screen.dart`): ognuno mostra il proprio
  QR (contiene solo la chiave pubblica) e inquadra quello dell'altro.
- Le chiavi RSA nascono solo durante un nuovo abbinamento, mai all'avvio.
- Prima dell'abbinamento la chat mostra una modalità demo.

### Chat
- Testo con link cliccabili, **risposta** a un messaggio, **modifica** e
  **cancellazione** dei propri messaggi, una **reazione** per messaggio.
- Indicatore "sta scrivendo", conferme di consegna e lettura, badge con il
  numero reale di non letti.
- Scorrimento infinito oltre gli ultimi 100 messaggi, cache locale SQLite,
  decifratura in un isolate.

### Allegati
- Foto dalla galleria (più di una alla volta) o dalla fotocamera, documenti,
  anteprime dei link (Open Graph). Le foto sono ridotte a 4096 px, con
  miniatura cifrata a parte.
- Coda offline: se manca la rete l'upload riparte dopo, e il messaggio viene
  scritto solo a upload finito.
- PDF in un visore interno, gli altri file con l'app di sistema.
- **Video:** arrivano solo dalla condivisione Android; non c'è ancora un
  selettore né un player in app.

### Condivisione da altre app
- **iOS — Share Extension** (`ios/ShareExtension/`): testo, link, fino a 10
  foto o documenti. Cifra e invia da sola, senza aprire l'app; senza rete mette
  in coda nell'App Group.
- **Android — intent** `SEND` / `SEND_MULTIPLE` per immagini, video, PDF,
  testo e documenti (`MainActivity.kt`).

### Promemoria e calendario
- Un promemoria ha una data (o un intervallo) e un avviso: nessuno, 1 h, 2 h
  (predefinito), 8 h, 1 giorno, 2 giorni, 1 settimana.
- Calendario verticale in sovrimpressione sulla chat
  (`widgets/vertical_calendar.dart`), con allegati sui promemoria.
- Pressione lunga = completato.
- Due avvisi distinti: un messaggio in chat all'ora scelta e una notifica
  locale **1 ora prima** su entrambi i telefoni (questa ignora l'avviso scelto).

### Galleria
- Tre schede su tutta la storia della chat: foto (per mese), link (masonry),
  documenti.

### Posizione
- Durata 1 o 8 ore, due modi: **in tempo reale** o **solo questa posizione**.
- Schermata di navigazione con bussola, distanza, tempo dall'ultimo
  aggiornamento e link alle indicazioni di Google Maps. Niente mappa in app.
- Basta il permesso "mentre usi l'app": in background va avanti con il
  foreground service su Android e la modalità location su iOS.

### Chiamate vocali
- WebRTC solo audio (Opus mono 40 kbps con FEC), peer-to-peer.
- UI di sistema: CallKit + PushKit VoIP su iOS, ConnectionService con
  foreground service su Android.
- Segnalazione cifrata, ICE restart (fino a 3 tentativi), canale dati per
  riaggancio e muto, indicatore di qualità, sensore di prossimità.
- **Solo STUN, nessun TURN:** se i due telefoni non riescono a parlarsi
  direttamente compare "Chiamata non disponibile in peer-to-peer".

### Recupero e backup
- **Telefono nuovo:** Impostazioni → *Recupera i messaggi*, dal partner o da
  un altro proprio telefono. Il telefono nuovo mostra un QR valido 10 minuti,
  l'altro lo inquadra e gli manda il certificato cifrato.
- **Reinstallazione sullo stesso telefono:** su Android le chiavi tornano dal
  Google Block Store; su iOS sono ancora nel Keychain.

### Altro
- **Cancellazione messaggi** a tre livelli: solo questo telefono, solo il
  telefono del partner, oppure tutto (entrambi i telefoni e il server).
- **Selfie di coppia** cifrato, mostrato nel tondo in alto a destra.
- **Notifiche** facoltative, con testo generico localizzato (il contenuto è
  cifrato). Spiegazione in app prima di chiedere posizione, microfono e
  fotocamera.

---

## Come funziona la cifratura

Il codice è in `flutter-app/lib/services/encryption_service.dart`.

### Identità
- Ogni telefono ha una coppia **RSA-2048**, salvata con
  `flutter_secure_storage` (Keychain su iOS, Keystore su Android).
- `userId = SHA-256(chiave pubblica)`.
- L'id della chat è `SHA-256` delle due chiavi pubbliche ordinate: è il
  documento `families/{id}` su Firestore.

### Cosa si cifra e come

| Cosa | Cifrario | Chiave |
|---|---|---|
| Messaggi, promemoria, posizione condivisa | AES-256 in modalità CTR (`encrypt`, default SIC) | Nuova chiave per messaggio, chiusa con RSA-OAEP per mittente e destinatario |
| Allegati e miniature nuovi (`gcm-v1`) | AES-256-GCM nativo (`cryptography_flutter`) | Nuova chiave per file, chiusa come sopra |
| Allegati vecchi, selfie di coppia | AES-256-CTR | Come sopra |
| Coordinate della posizione | AES-256-CTR | Chiave di sessione, che viaggia dentro il messaggio cifrato |
| Segnalazione delle chiamate | AES-256-GCM | Chiave per chiamata, chiusa con RSA-OAEP |
| Certificato per il recupero (escrow) | AES-256-CTR | Chiusa con la chiave pubblica del partner |

### Cosa resta in chiaro su Firestore

Va saputo, e non va promesso il contrario su sito o store:

- metadati dei messaggi: mittente, orari, tipo, stato di lettura, reazione;
- **il testo citato nelle risposte** (`reply_to_text`);
- **URL, titolo e descrizione delle anteprime dei link**;
- nome, peso e tipo dei file allegati;
- token FCM/VoIP, piattaforma e lingua dei telefoni.

### Escrow del certificato
Per il recupero, ogni telefono salva il proprio certificato (chiave privata
compresa) **cifrato per il partner** in `families/{id}/escrow/{userId}`. Quindi
la chiave privata non resta mai *solo* sul telefono: sul server ce n'è una copia
che solo il partner può aprire.

### Regole di sicurezza
`firestore.rules` e `storage.rules` sono **aperte** (`if true`), tranne
`list` su `families`, `recovery_requests` e `pairing_signals`. La protezione
si regge su due cose: gli id non sono indovinabili (hash di chiavi) e tutto il
contenuto è cifrato. `firebase_auth` serve solo per il login anonimo richiesto
dall'SDK di Storage.

---

## Struttura del repository

```
TuyJo/
├── flutter-app/                 App Flutter (pacchetto private_messaging)
│   ├── lib/
│   │   ├── main.dart            Avvio: Firebase, ripristino Block Store, provider
│   │   ├── models/              Message, Attachment, Reaction, LocationShare
│   │   ├── services/            Logica (vedi sotto)
│   │   ├── screens/             Schermate
│   │   ├── widgets/             Bolle promemoria, calendario, reazioni, allegati
│   │   ├── l10n/                File .arb (en è il template)
│   │   └── generated/l10n/      Codice generato dalle traduzioni
│   ├── ios/
│   │   ├── Runner/              AppDelegate (PushKit, canali nativi), SceneDelegate
│   │   └── ShareExtension/      Estensione di condivisione (Swift)
│   ├── android/                 MainActivity.kt: condivisione, Block Store, toni, prossimità
│   ├── test/                    Test su cifratura, recupero, SDP
│   └── scripts/                 Controllo delle build phase di Xcode
├── functions/                   Cloud Functions (notifiche, push VoIP)
├── firestore.rules · storage.rules · firestore.indexes.json · firebase.json
├── public/                      Sito tuijo.app (Firebase Hosting)
├── store/
│   ├── site/build_site.py       Genera le pagine del sito
│   └── screenshots/             Genera gli screenshot di store e sito
└── CLAUDE.md                    Procedura di rilascio passo per passo
```

### Servizi principali (`lib/services/`)

| File | Cosa fa |
|---|---|
| `encryption_service` · `crypto_isolate` | RSA, AES, GCM; decifratura in isolate |
| `chat_service` | Messaggi, promemoria, reazioni, modifica e cancellazione, letture |
| `message_cache_service` | Cache SQLite |
| `attachment_service` · `attachment_cache_service` · `pending_upload_service` | Allegati: scelta, compressione, cifratura, upload, coda offline |
| `link_metadata_service` | Anteprime dei link |
| `pairing_service` | Abbinamento, ascolto della famiglia, disabbinamento |
| `recovery_service` | Escrow e recupero via QR |
| `backup_service` · `block_store_bridge` | Ripristino delle chiavi su Android |
| `share_bridge_service` | Chiavi pubbliche nel Keychain dell'App Group (Share Extension) |
| `notification_service` | FCM, notifiche locali, CallKit, token VoIP, badge |
| `webrtc_service` | Chiamate |
| `location_service` | Posizione condivisa |
| `couple_selfie_service` | Selfie di coppia cifrato |

---

## Sviluppo

### Requisiti
- Flutter **3.38.4+** (Dart 3.11+, richiesto dal `pubspec.lock`)
- Android: JDK 17, SDK 36; AGP 8.12.1, Gradle 8.14.3, Kotlin 2.2.0
- iOS: macOS con Xcode e CocoaPods; deployment target 15.0, team `PW2GC2RTH2`

### Identificativi

| | |
|---|---|
| Progetto Firebase | `youandme-b3b4c` |
| Android applicationId | `com.privatemessaging.private_messaging` |
| iOS bundle id | `com.privatemessaging.tuyjo` (+ `.ShareExtension`) |
| App Group | `group.com.privatemessaging.tuyjo` |

Non vanno cambiati: l'app non sarebbe più riconosciuta come la stessa dagli
store, dal Keychain e dall'App Group.

### Avvio

```bash
git clone https://github.com/donpablitoooooooo/TuyJo.git
cd TuyJo/flutter-app
flutter pub get
cd ios && pod install && cd ..   # solo per iOS
flutter run
```

### Test

```bash
cd flutter-app
flutter test
```

Coprono la cifratura con chiave ricaricata, l'escrow e la crittografia del
recupero, e la regolazione Opus dell'SDP.

### Traduzioni
Le stringhe stanno in `lib/l10n/app_{en,it,es,ca}.arb` (en è il template) e
vengono generate in `lib/generated/l10n` con `flutter gen-l10n`. Le stringhe
native di iOS sono nei `*.lproj` di `ios/Runner`.

### Problemi di build iOS
Se Xcode si lamenta dell'ordine di *Thin Binary* / *Embed Frameworks*:
`flutter-app/scripts/check_xcode_build_phases.sh` lo verifica,
`fix_xcode_build_phases.sh` lo corregge. Per cache strane, la pulizia completa
di Pod e DerivedData è descritta in [`CLAUDE.md`](CLAUDE.md).

---

## Backend Firebase

### Cloud Functions (`functions/index.js`)
Node 22, regione `europe-west1`.

| Funzione | Quando parte | Cosa fa |
|---|---|---|
| `sendMessageNotification` | Nuovo documento in `families/{id}/messages` | Notifica FCM con testo generico localizzato e badge dei non letti; salta i promemoria completati; toglie i token non validi |
| `sendCallNotification` | Scrittura su `families/{id}/calls/current` | Chiamata in arrivo: push VoIP diretta ad APNs su iOS, push FCM ad alta priorità su Android; avviso se il chiamante riaggancia |
| `cleanupExpiredTokens` | HTTP | Segnaposto, non fa niente |

La push VoIP richiede i secret `APNS_AUTH_KEY`, `APNS_KEY_ID` e `APNS_TEAM_ID`.

### Collezioni Firestore
`families/{id}` con le sottocollezioni `messages`, `users`, `read_receipts`,
`locations`, `escrow`, `calls`; in radice `recovery_requests` (scadono dopo 10
minuti: serve la **policy TTL su `expires_at`** attiva in console) e
`pairing_signals`.

### Deploy

```bash
firebase deploy --only functions
firebase deploy --only firestore:rules,storage
firebase deploy --only hosting
```

---

## Sito e screenshot degli store

Il sito <https://tuijo.app> è in `public/` ed è servito da Firebase Hosting.

- **Pagine:** home in 4 lingue (`index.html` è l'italiano) e privacy
  `privacy-<lingua>-v1.1.html`; i vecchi `privacy-<lingua>.html` fanno 301.
- **Non si modificano a mano:** le genera `store/site/build_site.py` da
  un'unica struttura di testi. Il testo legale delle privacy invece si modifica
  nel file, lo script ne rigenera solo la cornice.
- **Schermate:** vengono da `store/screenshots`, che ridisegna le schermate
  dell'app in HTML e le esporta con Playwright, sia per gli store sia per il
  sito.

```bash
python3 store/site/build_site.py                      # pagine del sito
cd store/screenshots/src
node render.js --target web --out ../../../public/assets   # schermate del sito
node webp.js ../../../public/assets/shots
node render.js                                        # screenshot degli store
```

Dettagli in [`public/README.md`](public/README.md),
[`store/screenshots/README.md`](store/screenshots/README.md) e
[`store/screenshots/src/img/photos/README.md`](store/screenshots/src/img/photos/README.md)
(foto usate e licenze).

---

## Rilascio

La procedura completa — bump di versione in `pubspec.yaml` e nel `project.pbxproj`,
pulizia, build, upload su Play Console e App Store Connect, tag — è in
[`CLAUDE.md`](CLAUDE.md). In breve:

1. `version: X.Y.Z+N` in `flutter-app/pubspec.yaml`, più `MARKETING_VERSION` e
   `CURRENT_PROJECT_VERSION` nel pbxproj (6 + 6 occorrenze)
2. `flutter-app/CHANGELOG.md` e `flutter-app/release-notes.txt`
3. `flutter build appbundle --release` · `flutter build ipa --release`
4. Tag `vX.Y.Z` dopo l'invio agli store

I rilasci del sito si segnano con un tag `sito-AAAA-MM-GG`.

---

## Debito tecnico noto

- **Codice morto:** `services/auth_service.dart` (vecchio backend JWT, ancora
  registrato come provider ma inutilizzato), `screens/login_screen.dart`, le
  chiavi `login*`, `qrDisplay*`, `pairingChoice*` negli .arb,
  `flutter-app/test_read_db.dart`.
- **Dipendenze dichiarate ma non usate:** `flutter_chat_ui`, `table_calendar`.
- **Commenti fuorvianti:** in più punti il codice parla di AES-CBC, ma la
  modalità effettiva è CTR (SIC); il commento in `block_store_bridge.dart` cita
  un Keychain iCloud che non esiste; in `pubspec.yaml` il vincolo di
  `flutter_callkit_incoming` è descritto come "<3.1.0" ma è `^3.1.5`.
- **iOS:** `aps-environment` è `development` in `Runner.entitlements`;
  `Info.plist` ha ancora `CFBundleDocumentTypes` e le chiavi
  `NSLocationAlways*`.
- **Documenti vecchi in radice:** `CHANGELOG.md` (fermo alla 1.24, quello vivo
  è `flutter-app/CHANGELOG.md`), `MILESTONE.md`, `TODO*.md`,
  `PULL_REQUEST_v1.5.0.md`, `debug_notifications.md`, `share-extension.patch`,
  `youandme/`, `_archive/`.

---

## Storico versioni

Il dettaglio è in [`flutter-app/CHANGELOG.md`](flutter-app/CHANGELOG.md).

| Versione | Data | In breve |
|---|---|---|
| **1.37.0** (47) | 14/09/2026 | Recupero dal partner o dal proprio telefono con QR; via backup manuale e pagina Ripristino; Share Extension che invia da sola, anche più foto; motore delle chiamate riscritto (segnalazione cifrata, PushKit, ICE restart); posizione senza permesso "sempre" e con "solo questa posizione"; badge corretto |
| 1.35.0 | 15/06/2026 | Notifiche facoltative; spiegazione prima del permesso fotocamera |
| 1.34.0 | 12/06/2026 | Cancellazione messaggi a tre livelli; avviso a 1 settimana; impostazioni riordinate |
| 1.33.0 | 29/05/2026 | Calendario in sovrimpressione per i promemoria |
| 1.32.0 | 23/04/2026 | AES-GCM nativo per gli allegati; upload 3-5 volte più veloci; scorrimento infinito e galleria completa |

---

Software proprietario, tutti i diritti riservati.
