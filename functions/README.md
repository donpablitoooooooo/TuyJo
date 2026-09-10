# Cloud Functions per Notifiche Push

Queste Cloud Functions gestiscono l'invio delle notifiche push quando arrivano nuovi messaggi.

## Configurazione

### 1. Installare le dipendenze

```bash
cd functions
npm install
```

### 2. Configurare Firebase

Assicurati di avere Firebase CLI installato:

```bash
npm install -g firebase-tools
```

Effettua il login:

```bash
firebase login
```

### 3. Inizializzare Firebase (se non già fatto)

Se non hai ancora un file `firebase.json` nella root del progetto:

```bash
cd /home/user/youandme
firebase init functions
```

Seleziona:
- Il tuo progetto Firebase esistente
- JavaScript come linguaggio
- ESLint per il linting
- Installa le dipendenze con npm

### 4. Deploy delle Cloud Functions

```bash
firebase deploy --only functions
```

Oppure, per deployare solo una funzione specifica:

```bash
firebase deploy --only functions:sendMessageNotification
```

## Funzioni Disponibili

### `sendMessageNotification`

**Trigger:** Firestore onCreate su `/families/{familyChatId}/messages/{messageId}`

**Descrizione:** Invia automaticamente una notifica push al partner quando viene creato un nuovo messaggio.

**Flusso:**
1. Rileva un nuovo messaggio nella chat famiglia
2. Recupera tutti gli utenti della famiglia da Firestore
3. Trova il destinatario (utente che NON è il sender)
4. Recupera il token FCM del destinatario
5. Invia la notifica push tramite Firebase Cloud Messaging
6. Se il token è invalido, lo rimuove automaticamente dal database

**Payload della notifica:**
```json
{
  "notification": {
    "title": "💬 Nuovo messaggio",
    "body": "Hai ricevuto un nuovo messaggio crittografato"
  },
  "data": {
    "familyChatId": "...",
    "messageId": "...",
    "senderId": "..."
  }
}
```

### `cleanupExpiredTokens`

**Trigger:** HTTP Request (opzionale)

**Descrizione:** Funzione per pulire i token FCM scaduti. Può essere chiamata manualmente o schedulata con Cloud Scheduler.

## Testing Locale

Per testare le funzioni localmente con Firebase Emulator:

```bash
cd functions
npm run serve
```

Questo avvierà l'emulatore Firebase sulla porta 5001.

## Monitoraggio

Per vedere i log delle funzioni in produzione:

```bash
firebase functions:log
```

Oppure per una funzione specifica:

```bash
firebase functions:log --only sendMessageNotification
```

## Struttura dei Dati Firestore

Le Cloud Functions si aspettano questa struttura in Firestore:

```
/families/{familyChatId}
  /messages/{messageId}
    - sender_id: string
    - ciphertext: string
    - nonce: string
    - tag: string
    - created_at: timestamp
  /users/{userId}
    - fcm_token: string
    - updated_at: timestamp
```

## Note sulla Sicurezza

- Le notifiche contengono solo metadati, non il contenuto del messaggio
- Il contenuto crittografato rimane end-to-end encrypted
- I token FCM vengono automaticamente rimossi se invalidi
- La funzione verifica che il destinatario NON sia il sender del messaggio

## Troubleshooting

### La notifica non arriva

1. Verifica che il token FCM sia salvato correttamente in Firestore
2. Controlla i log della Cloud Function: `firebase functions:log`
3. Verifica che l'app abbia i permessi per le notifiche
4. Controlla che il canale Android `high_importance_channel` sia creato

### Errori di deploy

Se ricevi errori durante il deploy:
- Verifica di aver effettuato il login: `firebase login`
- Controlla che il progetto sia corretto: `firebase use --add`
- Assicurati che il billing sia abilitato sul progetto Firebase (richiesto per le Cloud Functions)

### Token invalidi

I token FCM possono diventare invalidi se:
- L'app viene disinstallata
- L'app viene reinstallata (genera un nuovo token)
- L'app viene aggiornata e chiama `deleteToken()`

La funzione `sendMessageNotification` rimuove automaticamente i token invalidi.


## Chiamate vocali: push VoIP iOS (PushKit)

Su iOS le chiamate in arrivo squillano solo tramite push VoIP (PushKit),
inviate direttamente ad APNs da `sendCallNotification`. FCM non può
inviarle. Senza questa configurazione la funzione ripiega su un push FCM
in background, che iOS non consegna ad app terminata.

1. Apple Developer → *Certificates, Identifiers & Profiles* → *Keys* →
   crea una chiave con **Apple Push Notifications service (APNs)** abilitato
   e scarica il file `.p8` (si scarica una volta sola).
2. Imposta i secret (una volta, nel progetto Firebase):

```bash
firebase functions:secrets:set APNS_AUTH_KEY   # incolla il contenuto del .p8, righe BEGIN/END incluse
firebase functions:secrets:set APNS_KEY_ID     # Key ID della chiave (10 caratteri)
firebase functions:secrets:set APNS_TEAM_ID    # PW2GC2RTH2
```

3. Deploy: `firebase deploy --only functions`

La funzione prova prima l'ambiente APNs production e, se il token è di un
build di sviluppo (`BadDeviceToken`), riprova su sandbox. Il bundle id è
fissato in `IOS_BUNDLE_ID` (`com.privatemessaging.tuyjo`, topic `.voip`).

Su Xcode il target Runner deve avere la capability **Push Notifications** e
**Background Modes → Voice over IP** (già presente in `Info.plist`).
