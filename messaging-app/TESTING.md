# 🧪 Guida al Testing

Istruzioni passo-passo per testare l'app di messaggistica.

## Problemi Risolti

✅ URL backend configurato (`http://localhost:3000`)
✅ AuthService inizializzato correttamente
✅ Firebase reso opzionale (non serve per testing iniziale)
✅ Logging dettagliato aggiunto sia su backend che frontend
✅ Database in-memory per sviluppo locale (non serve Firestore subito)
✅ Fix UUID nel backend

## Step 1: Avvia il Backend

```bash
cd messaging-app/backend

# Installa dipendenze (se non l'hai già fatto)
npm install

# Avvia il server in modalità development
npm run dev
```

**Output atteso:**
```
💾 Using in-memory database (development mode)
🚀 Server running on port 3000
📱 Environment: development
```

Se vedi questo output, il backend funziona! ✅

## Step 2: Testa il Backend (Opzionale ma Consigliato)

### Test Registrazione

Apri un nuovo terminale e esegui:

```bash
curl -X POST http://localhost:3000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "test1",
    "password": "password123",
    "publicKey": "fake-public-key-for-testing"
  }'
```

**Output atteso (nel terminale del backend):**
```
📝 Richiesta registrazione ricevuta
👤 Username: test1
🔍 Controllo se utente esiste...
🔒 Hash password...
💾 Creazione utente...
✅ Utente creato con ID: xxx-xxx-xxx
🎫 Generazione JWT token...
✅ Registrazione completata con successo!
```

**Output nella risposta:**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIs...",
  "user": {
    "id": "xxx-xxx-xxx",
    "username": "test1",
    "publicKey": "fake-public-key-for-testing"
  }
}
```

### Test Login

```bash
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "test1",
    "password": "password123"
  }'
```

**Output atteso:**
```
🔐 Richiesta login ricevuta
👤 Username: test1
🔍 Ricerca utente nel database...
✅ Utente trovato: xxx-xxx-xxx
🔑 Verifica password...
✅ Password corretta
🎫 Generazione JWT token...
✅ Login completato con successo!
```

Se il backend risponde correttamente, procedi! ✅

## Step 3: Configura Flutter

### iOS

```bash
cd messaging-app/flutter-app

# Installa dipendenze
flutter pub get

# Verifica configurazione
flutter doctor

# Avvia su simulatore iOS
flutter run -d ios
```

### Android

```bash
cd messaging-app/flutter-app

# Installa dipendenze
flutter pub get

# Avvia su emulatore Android
flutter run -d android
```

## Step 4: Testa l'App

### Primo Utente

1. L'app si apre sulla schermata di login
2. Clicca su "Non hai un account? Registrati"
3. Inserisci:
   - Username: `mario`
   - Password: `password123`
4. Clicca "Registrati"

**Guarda i log Flutter** (nel terminale dove hai lanciato `flutter run`):

```
🔐 Registrazione in corso per: mario
🔑 Generazione chiavi RSA...
✅ Chiavi RSA generate
📡 Chiamata API: http://localhost:3000/api/auth/register
📥 Risposta server: 201
📄 Body: {"token":"...","user":{...}}
✅ Registrazione completata con successo!
```

Se vedi questo, la registrazione funziona! ✅

### Secondo Utente (su altro dispositivo/simulatore)

1. Avvia un secondo emulatore/simulatore
2. Lancia l'app: `flutter run -d <device-id>`
3. Registra un secondo utente:
   - Username: `luigi`
   - Password: `password123`

### Prova il Login

1. Nell'app di Mario, fai logout (icona in alto a destra)
2. Fai login di nuovo con:
   - Username: `mario`
   - Password: `password123`

**Guarda i log:**

```
🔐 Login in corso per: mario
📡 Chiamata API: http://localhost:3000/api/auth/login
📥 Risposta server: 200
📄 Body: {"token":"...","user":{...}}
🔑 Chiave privata caricata
✅ Login completato con successo!
```

## Step 5: Testa la Chat

1. Invia un messaggio da Mario a Luigi
2. Il messaggio dovrebbe apparire su entrambi i dispositivi
3. Controlla che:
   - ✅ Messaggio criptato (il server non può leggerlo)
   - ✅ Messaggio decriptato correttamente sul destinatario
   - ✅ Timestamp visualizzato
   - ✅ Icone di consegna/lettura

## 🐛 Troubleshooting

### "Login fallito" / "Registrazione fallita"

1. **Backend non in esecuzione**
   ```bash
   # Controlla se il backend è attivo
   curl http://localhost:3000/health

   # Dovresti vedere: {"status":"ok","timestamp":"..."}
   ```

2. **URL sbagliato**
   - Verifica che in `lib/services/auth_service.dart` ci sia:
   ```dart
   static const String baseUrl = 'http://localhost:3000';
   ```

3. **Problemi con iOS Simulator**
   - iOS Simulator usa `localhost` direttamente ✅
   - Verifica che il backend sia su porta 3000

4. **Problemi con Android Emulator**
   - Android Emulator usa `10.0.2.2` invece di `localhost`
   - Cambia URL in `auth_service.dart`:
   ```dart
   static const String baseUrl = 'http://10.0.2.2:3000';
   ```

5. **Errore: "Connection refused"**
   - Il backend non è avviato
   - Firewall blocca la porta 3000
   - Porta già in uso

### App va in logout da sola

**Causa:** L'AuthService controlla se c'è un token salvato all'avvio.

**Soluzione:**
- Questo è ora RISOLTO con il nuovo `AuthWrapper` che inizializza correttamente
- Se ancora accade, guarda i log per vedere quale errore viene stampato

### Generazione chiavi RSA lenta

È normale! La generazione di chiavi RSA-2048 richiede 2-5 secondi.

### "Firebase not configured"

Non è un problema! Firebase serve solo per le notifiche push, che sono opzionali.
L'app funziona perfettamente senza Firebase.

## 📋 Checklist Test Completo

- [ ] Backend avviato e risponde a `/health`
- [ ] Registrazione utente 1 (es. mario)
- [ ] Registrazione utente 2 (es. luigi)
- [ ] Login utente 1
- [ ] Login utente 2
- [ ] Invio messaggio da utente 1 a utente 2
- [ ] Ricezione messaggio su utente 2
- [ ] Messaggio decriptato correttamente
- [ ] Logout e re-login funziona
- [ ] Token persiste (non fa logout da solo)

## 📊 Log Utili

### Backend
Guarda il terminale dove hai eseguito `npm run dev`

### Flutter
Guarda il terminale dove hai eseguito `flutter run`

### Debug Mode Flutter
Per vedere TUTTI i log:
```bash
flutter run -v
```

## 🎉 Successo!

Se tutti i test passano, hai un'app di messaggistica privata funzionante con crittografia E2E!

## Prossimi Passi

1. ✅ Test locale completato
2. [ ] Configura Firebase per notifiche push (opzionale)
3. [ ] Deploy backend su Google Cloud Run
4. [ ] Build app per dispositivi fisici
5. [ ] Test end-to-end su rete reale

---

## 🆘 Hai ancora problemi?

Se dopo aver seguito questa guida hai ancora problemi:

1. Controlla i log del backend
2. Controlla i log di Flutter
3. Verifica che l'URL sia corretto per la tua piattaforma (iOS vs Android)
4. Assicurati che il backend sia avviato PRIMA di lanciare l'app

**Tip:** Lascia sempre aperto il terminale del backend per vedere cosa succede in tempo reale!
