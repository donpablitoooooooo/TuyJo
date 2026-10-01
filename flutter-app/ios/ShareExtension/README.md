# iOS Share Extension Setup

Questi file implementano la Share Extension per iOS che permette di condividere link da Safari e altre app direttamente in Tuijo.

## File inclusi:

1. **ShareViewController.swift** - Controller della Share Extension che usa App Groups
2. **AppDelegate.swift** (aggiornato) - Gestisce il recupero dei dati dall'App Group

## Come usare:

### In Xcode:

1. Apri il file `ShareExtension/ShareViewController.swift` nel tuo progetto Xcode
2. **Sostituisci tutto il contenuto** con il file `ShareViewController.swift` di questo branch
3. Apri il file `Runner/AppDelegate.swift` nel tuo progetto Xcode
4. **Sostituisci tutto il contenuto** con il file `AppDelegate.swift` di questo branch

### Verifica App Groups:

Assicurati che **entrambi** i target (Runner e ShareExtension) abbiano:
- **Signing & Capabilities** → **App Groups** → `group.com.privatemessaging.tuyjo` ✓

## Come funziona:

1. L'utente condivide testo, link, foto o documenti → Share sheet → "Tuijo".
2. L'estensione legge dal Keychain condiviso (access group
   `group.com.privatemessaging.tuyjo`, servizio `tuyjo_share`) le due chiavi
   pubbliche e il refresh token del login anonimo dell'app, scritti da
   `ShareBridgeService` (Dart).
3. Scambia il refresh token con un ID token (`securetoken.googleapis.com`):
   le regole di Firestore e Storage fanno scrivere in una chat solo i login
   che ne sono membri, e il login dell'app lo è (vedi `functions/membership.js`).
4. Cifra e invia da sola: messaggio su Firestore via REST
   (`Authorization: Bearer`), file su Storage via REST
   (`Authorization: Firebase`).
5. Senza rete o se l'invio fallisce, mette tutto in coda nell'App Group e apre
   l'app con `ShareMedia://open`: ci pensa l'app a spedire.

## Debugging:

Se non funziona:
- Verifica che App Groups sia configurato su **entrambi** i target
- Controlla che l'URL scheme `ShareMedia` sia in Info.plist
- Guarda i log in Console.app filtrando per "ShareMedia" o "App Group"
