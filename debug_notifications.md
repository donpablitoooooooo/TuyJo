# 🐛 Debug Notifiche Push - Guida Completa

## Checklist Debug

### ✅ 1. Verifica Log Flutter

Esegui l'app e cerca questi messaggi nei log:

```bash
flutter logs | grep -E "FCM|notification|Notification|🔑|✅|❌"
```

**Messaggi da cercare:**
- `✅ User granted notification permission` → Permessi concessi
- `🔑 FCM Token: eyJh...` → Token FCM generato
- `✅ FCM token saved to Firestore for user: <userId>` → Token salvato in Firestore
- `📨 Foreground message received` → Notifica ricevuta in foreground
- `🔔 App opened from notification` → App aperta da notifica

**Errori comuni:**
- `❌ User declined notification permission` → Utente ha rifiutato i permessi
- `❌ Error saving FCM token` → Errore nel salvare il token
- `FirebaseException` → Problema configurazione Firebase

---

### ✅ 2. Verifica Permessi Android

**Sul telefono:**
1. Impostazioni → App → YouAndMe (o "private_messaging")
2. Notifiche → **Devono essere ABILITATE**
3. Se disabilitate, abilitale manualmente

**Richiesta permessi nel codice:**
- L'app richiede i permessi all'avvio in `NotificationService.initialize()`
- Se già negati, l'utente deve abilitarli manualmente dalle impostazioni

---

### ✅ 3. Verifica Token FCM in Firestore

1. **Firebase Console** → https://console.firebase.google.com
2. Seleziona progetto
3. **Firestore Database**
4. Naviga a: `/families/{familyChatId}/users/{userId}`

**Cosa cercare:**
```json
{
  "fcm_token": "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9...",
  "updated_at": "2025-12-10T20:30:00Z"
}
```

**Se il token NON c'è:**
- Controlla i log per errori di salvataggio
- Verifica che `familyChatId` e `userId` siano corretti
- Controlla le regole di sicurezza Firestore (devono permettere write)

---

### ✅ 4. Verifica Cloud Functions Deployate

**Controlla se le Cloud Functions sono deployate:**

```bash
firebase functions:list
```

**Output atteso:**
```
┌───────────────────────────┬────────────────┬────────┐
│ Function Name             │ Region         │ Status │
├───────────────────────────┼────────────────┼────────┤
│ sendMessageNotification   │ us-central1    │ ACTIVE │
└───────────────────────────┴────────────────┴────────┘
```

**Se NON sono deployate, deployale ora:**

```bash
cd functions
npm install
firebase deploy --only functions
```

**Verifica billing Firebase:**
- Le Cloud Functions richiedono il piano **Blaze** (pay-as-you-go)
- Vai su Firebase Console → ⚙️ Impostazioni → Utilizzo e fatturazione
- Se sei sul piano Spark (gratuito), passa a Blaze

---

### ✅ 5. Verifica Log Cloud Functions

**Dopo aver inviato un messaggio, controlla i log della Cloud Function:**

```bash
firebase functions:log --only sendMessageNotification
```

**Messaggi da cercare:**
- `📨 New message detected` → Funzione attivata
- `📤 Sending notifications to N recipients` → Notifica in invio
- `✅ Notification sent successfully` → Notifica inviata con successo
- `❌ Error sending notification` → Errore invio

**Errori comuni:**
- `No users found in this family` → Nessun utente nella collezione `/families/{id}/users/`
- `No recipients with FCM tokens found` → Token FCM mancante
- `messaging/invalid-registration-token` → Token FCM non valido
- `messaging/registration-token-not-registered` → Token FCM scaduto/invalido

---

### ✅ 6. Test Notifica Manuale (Firebase Console)

Invia una notifica di test direttamente dalla Firebase Console:

1. **Firebase Console** → Cloud Messaging
2. **"Send your first message"** o **"New notification"**
3. Compila:
   - **Notification title:** "Test"
   - **Notification text:** "Notifica di test"
4. Clicca **"Send test message"**
5. **Aggiungi il token FCM** (copialo dai log o da Firestore)
6. Clicca **"Test"**

**Risultati:**
- ✅ Notifica arriva → FCM funziona, problema nelle Cloud Functions
- ❌ Notifica NON arriva → Problema configurazione FCM/app

---

### ✅ 7. Verifica google-services.json

Il file deve essere in: `flutter-app/android/app/google-services.json`

**Verifica package_name:**

```bash
grep "package_name" android/app/google-services.json
```

**Output atteso:**
```json
"package_name": "com.privatemessaging.private_messaging"
```

Deve corrispondere a `applicationId` in `android/app/build.gradle`:
```gradle
applicationId "com.privatemessaging.private_messaging"
```

---

### ✅ 8. Verifica Firestore Security Rules

Le regole devono permettere la scrittura dei token FCM:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Permetti lettura/scrittura messaggi famiglia
    match /families/{familyId}/messages/{messageId} {
      allow read, write: if true;
    }

    // Permetti scrittura token utenti
    match /families/{familyId}/users/{userId} {
      allow read, write: if true;
    }
  }
}
```

**Aggiorna le regole su Firebase Console:**
1. Firestore Database → Rules
2. Aggiungi la regola per `/families/{familyId}/users/{userId}`
3. Clicca **"Publish"**

---

## 🧪 Test Completo End-to-End

### Scenario: Due dispositivi

**Dispositivo A (Creatore):**
1. Apri app → "Creo io la chiave famiglia"
2. Mostra QR code
3. Controlla log: deve apparire `✅ FCM token saved to Firestore`
4. Controlla Firestore: deve esistere `/families/{familyChatId}/users/{userIdA}/fcm_token`

**Dispositivo B (Joiner):**
1. Apri app → "Leggo la chiave famiglia"
2. Scansiona QR code
3. Controlla log: deve apparire `✅ FCM token saved to Firestore`
4. Controlla Firestore: deve esistere `/families/{familyChatId}/users/{userIdB}/fcm_token`

**Test notifica:**
1. Da **Dispositivo A**, invia un messaggio
2. Su **Dispositivo B**:
   - Se app in **foreground**: deve apparire notifica locale in alto
   - Se app in **background**: deve apparire notifica push standard Android
   - Se app **chiusa**: deve apparire notifica push che riapre l'app
3. Controlla log Cloud Function: `firebase functions:log`

---

## 🔧 Soluzioni Errori Comuni

### Errore: "User declined notification permission"

**Soluzione:**
- Vai in Impostazioni → App → YouAndMe → Notifiche → Abilita
- Oppure disinstalla e reinstalla l'app, poi accetta i permessi

### Errore: "FCM token is null"

**Possibili cause:**
- Firebase non inizializzato correttamente
- google-services.json mancante o errato
- Connessione internet assente

**Soluzione:**
- Verifica `google-services.json` esista in `android/app/`
- Riavvia l'app
- Controlla connessione internet

### Errore: "No users found in this family"

**Causa:** La collezione `/families/{familyChatId}/users/` è vuota

**Soluzione:**
- Verifica che `saveTokenToFirestore()` venga chiamata in `ChatScreen._initialize()`
- Controlla i log per errori di salvataggio
- Verifica le regole Firestore permettano write su `/families/{familyId}/users/{userId}`

### Errore: "Invalid registration token"

**Causa:** Token FCM scaduto o non valido

**Soluzione:**
- La Cloud Function rimuove automaticamente token invalidi
- Reinstalla l'app per generare un nuovo token
- Controlla che il token in Firestore sia recente

---

## 📊 Debug Avanzato: Strumenti

### 1. Flutter DevTools

```bash
flutter pub global activate devtools
flutter pub global run devtools
```

Poi da Android Studio: View → Tool Windows → Flutter DevTools

### 2. Firebase Emulator (test locale)

```bash
cd functions
firebase emulators:start --only functions,firestore
```

Poi configura l'app per usare l'emulatore locale.

### 3. Android Studio Logcat con filtri

**Filtro per notifiche:**
```
package:com.privatemessaging.private_messaging tag:flutter
```

**Filtro solo errori:**
```
package:com.privatemessaging.private_messaging level:error
```

---

## 📞 Supporto

Se hai ancora problemi, raccogli queste informazioni:

1. **Log Flutter completi** (primi 5 minuti dall'avvio)
2. **Log Cloud Function** (dopo aver inviato un messaggio)
3. **Screenshot Firestore** (struttura dati `/families/...`)
4. **Screenshot permessi app** (Impostazioni Android)
5. **Versione Flutter:** `flutter --version`
6. **Versione Android device:** Impostazioni → Info sul telefono

---

**Buon debug! 🚀**
