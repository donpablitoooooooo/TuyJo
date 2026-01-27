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

1. User condivide un link da Safari/app → Share sheet
2. Tocca "Tuijo"
3. ShareExtension salva il link nell'App Group
4. Apre l'app principale con URL scheme `ShareMedia://open`
5. AppDelegate legge il link dall'App Group
6. Chiama `handleSharedText()` per processare il link
7. Flutter riceve il link e mostra la preview

## Debugging:

Se non funziona:
- Verifica che App Groups sia configurato su **entrambi** i target
- Controlla che l'URL scheme `ShareMedia` sia in Info.plist
- Guarda i log in Console.app filtrando per "ShareMedia" o "App Group"
