# Share Extension Setup per iOS

Questa directory contiene i file necessari per la Share Extension di TuyJo, che permette di condividere link, testo, immagini e video da altre app direttamente in TuyJo.

## Setup in Xcode

Per abilitare la Share Extension, devi configurarla manualmente in Xcode. Segui questi passaggi:

### 1. Apri il progetto in Xcode

```bash
cd flutter-app/ios
open Runner.xcworkspace
```

### 2. Aggiungi un nuovo Target per la Share Extension

1. Nel Project Navigator, seleziona il progetto **Runner**
2. Clicca sul pulsante **+** in basso nella sezione **TARGETS**
3. Cerca e seleziona **Share Extension**
4. Clicca **Next**
5. Configura il target:
   - **Product Name**: `ShareExtension`
   - **Team**: Seleziona il tuo team di sviluppo
   - **Organization Identifier**: `com.privatemessaging`
   - **Bundle Identifier**: `com.privatemessaging.tuyjo.ShareExtension`
   - **Language**: Swift
6. Clicca **Finish**
7. Se richiesto, **NON** attivare lo scheme (clicca "Cancel")

### 3. Sostituisci i file generati automaticamente

Xcode avrà creato alcuni file di default. Devi sostituirli con quelli in questa directory:

1. Elimina il file `ShareViewController.swift` generato automaticamente
2. Elimina il file `Info.plist` generato automaticamente
3. Elimina la directory `Base.lproj` generata automaticamente
4. Aggiungi i file da questa directory (`ShareExtension`) al target ShareExtension in Xcode:
   - Trascina `ShareViewController.swift` nel target ShareExtension
   - Trascina `Info.plist` nel target ShareExtension
   - Trascina la directory `Base.lproj` (con `MainInterface.storyboard`) nel target ShareExtension

### 4. Configura l'App Group

La Share Extension comunica con l'app principale tramite un App Group condiviso.

#### Per il target principale (Runner):

1. Seleziona il target **Runner**
2. Vai alla tab **Signing & Capabilities**
3. Clicca sul pulsante **+ Capability**
4. Aggiungi **App Groups**
5. Attiva il gruppo: `group.com.privatemessaging.tuyjo`

#### Per il target ShareExtension:

1. Seleziona il target **ShareExtension**
2. Vai alla tab **Signing & Capabilities**
3. Clicca sul pulsante **+ Capability**
4. Aggiungi **App Groups**
5. Attiva lo stesso gruppo: `group.com.privatemessaging.tuyjo`

### 5. Verifica le configurazioni

#### Bundle Identifier:
- Runner: `com.privatemessaging.tuyjo`
- ShareExtension: `com.privatemessaging.tuyjo.ShareExtension`

#### Deployment Target:
- Assicurati che entrambi i target abbiano lo stesso **Deployment Target** (es. iOS 13.0 o superiore)

#### Signing:
- Entrambi i target devono avere lo stesso **Team** di sviluppo
- Entrambi devono avere **Automatically manage signing** abilitato (oppure profili di provisioning manuali configurati correttamente)

### 6. Build e Test

1. Seleziona lo scheme **Runner** (non ShareExtension)
2. Compila il progetto (**Cmd+B**)
3. Esegui l'app su un dispositivo fisico o simulatore
4. Apri Safari (o altra app), seleziona un link o testo
5. Tocca il pulsante **Condividi**
6. Dovresti vedere **Tuijo** nell'elenco delle app di condivisione
7. Tocca **Tuijo** e il link/testo verrà inserito automaticamente nella chat

## Come funziona

### Flusso di condivisione:

1. **Utente condivide** da un'altra app (es. Safari, Chrome, Notes)
2. **iOS apre la ShareExtension** di TuyJo
3. **ShareExtension** riceve il contenuto condiviso:
   - Testo/URL → salvato in UserDefaults condivisi
   - File (immagini/video) → copiato in directory condivisa
4. **ShareExtension** salva i dati nell'App Group (`group.com.privatemessaging.tuyjo`)
5. **ShareExtension** si chiude e ritorna all'app principale (se già aperta)
6. **App principale** (Runner/AppDelegate) legge i dati dall'App Group
7. **AppDelegate** invia i dati a Flutter tramite Method Channel
8. **Flutter (chat_screen.dart)** riceve i dati e li mostra nella chat:
   - Testo → inserito nel campo messaggio
   - File → aggiunti agli allegati

### Comunicazione tra Extension e App:

- **App Group**: `group.com.privatemessaging.tuyjo`
- **UserDefaults Key**: `ShareKey`
- **Method Channel**: `com.privatemessaging.tuyjo/shared_media`

### Metodi del Method Channel:

- `getInitialMedia()` → Restituisce lista di file path condivisi
- `getInitialSharedText()` → Restituisce testo/URL condiviso
- `onMediaShared` → Callback quando file vengono condivisi (app aperta)
- `onTextShared` → Callback quando testo viene condiviso (app aperta)

## Troubleshooting

### L'estensione non appare nel menu Condividi

1. Verifica che l'**App Group** sia configurato correttamente su entrambi i target
2. Controlla che il **Bundle Identifier** della ShareExtension sia corretto
3. Assicurati che entrambi i target siano firmati con lo stesso **Team**
4. Riavvia il dispositivo/simulatore

### I link/file non arrivano all'app

1. Controlla i log di Xcode per errori
2. Verifica che l'App Group abbia lo stesso nome in entrambi i target
3. Controlla che `AppDelegate.swift` chiami `checkSharedData()` correttamente

### Errori di compilazione

1. Assicurati che i file siano aggiunti al target **ShareExtension** (non Runner)
2. Verifica che il Deployment Target sia coerente tra i due target
3. Pulisci la build (**Cmd+Shift+K**) e ricompila

## Note importanti

- La ShareExtension richiede un **dispositivo fisico** o un simulatore con iOS 13+
- L'App Group deve essere configurato sia su **Runner** che su **ShareExtension**
- Il Bundle Identifier della ShareExtension **deve** essere una sotto-estensione di quello principale:
  - ✅ Corretto: `com.privatemessaging.tuyjo.ShareExtension`
  - ❌ Sbagliato: `com.privatemessaging.ShareExtension`

## File nella directory ShareExtension

- **ShareViewController.swift**: Controller Swift che gestisce il contenuto condiviso
- **Info.plist**: Configurazione dell'estensione (tipi di file supportati, etc.)
- **Base.lproj/MainInterface.storyboard**: Interfaccia UI dell'estensione (opzionale)
- **README.md**: Questo file con le istruzioni

## Supporto

Per problemi o domande, consulta la documentazione ufficiale di Apple:
- [App Extensions Programming Guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/index.html)
- [Share Extension](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html)
