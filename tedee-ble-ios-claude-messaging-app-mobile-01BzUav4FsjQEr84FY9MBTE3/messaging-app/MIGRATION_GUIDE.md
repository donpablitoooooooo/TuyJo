# Migration Guide: Socket.io → Firestore Realtime

Questa guida documenta le modifiche architetturali apportate al sistema di messaggistica.

## Riepilogo modifiche

### Backend (Node.js)

**Rimosso:**
- ❌ Socket.io server e websocket connections
- ❌ Username/password authentication
- ❌ Struttura messaggi flat (collezione `messages`)

**Aggiunto:**
- ✅ Firebase Custom Token generation
- ✅ Public key-based authentication
- ✅ Inbox-based message structure (`users/{userId}/inbox/{messageId}`)
- ✅ POST /api/messages endpoint
- ✅ SHA-256(publicKey) come userId
- ✅ Firestore security rules

**File modificati:**
- `package.json` - rimosso socket.io, aggiunto uuid
- `server.js` - rimossa logica Socket.io
- `middleware/auth.js` - rimossa authenticateSocket
- `routes/auth.js` - nuovo sistema auth con publicKey e Firebase Custom Tokens
- `routes/messages.js` - aggiunto POST endpoint per invio messaggi
- `routes/users.js` - aggiornati endpoint per nuova struttura
- `services/userService.js` - userId = SHA-256(publicKey)
- `services/messageService.js` - struttura inbox invece di flat

**File nuovi:**
- `utils/crypto.js` - utility per SHA-256
- `firestore.rules` - regole di sicurezza Firestore
- `README.md` - documentazione completa API

### Flutter Client

**Rimosso:**
- ❌ socket_io_client dependency
- ❌ Username/password login
- ❌ Socket.io connection handling

**Aggiunto:**
- ✅ firebase_auth + cloud_firestore dependencies
- ✅ Firebase Custom Token authentication
- ✅ Firestore realtime listeners
- ✅ Nuovo modello Message (ciphertext, nonce, tag)
- ✅ Struttura User senza username

**File modificati:**
- `pubspec.yaml` - dipendenze aggiornate
- `lib/models/message.dart` - nuovo schema Message e User
- `lib/services/auth_service.dart` - Firebase Custom Tokens
- `lib/services/chat_service.dart` - Firestore listeners invece Socket.io

**File nuovi:**
- `README.md` - documentazione Flutter

## Differenze chiave

### 1. Autenticazione

#### Prima (Socket.io)
```javascript
// Backend
POST /api/auth/register
{ username, password, publicKey }
→ JWT token

// Flutter
await authService.register(username, password);
socket.io.connect(jwtToken);
```

#### Dopo (Firestore)
```javascript
// Backend
POST /api/auth/register
{ publicKey }
→ backend_token + firebase_token

// Flutter
await authService.register(); // genera chiavi automaticamente
// Firebase Auth automatico con custom token
```

### 2. Identificazione utenti

#### Prima
```
userId = UUID random
```

#### Dopo
```
userId = SHA-256(publicKey)
```

### 3. Invio messaggi

#### Prima (Socket.io)
```dart
// Flutter
socket.emit('send_message', {
  receiverId: '...',
  encryptedContent: '...'
});

// Backend salva in collezione "messages" flat
```

#### Dopo (Firestore)
```dart
// Flutter
POST /api/messages {
  recipient_id: '...',
  ciphertext: '...',
  nonce: '...',
  tag: '...'
}

// Backend scrive in users/{recipientId}/inbox/{messageId}
```

### 4. Ricezione messaggi

#### Prima (Socket.io)
```dart
socket.on('new_message', (data) {
  final message = Message.fromJson(data);
  // Aggiorna UI
});
```

#### Dopo (Firestore)
```dart
FirebaseFirestore.instance
  .collection('users')
  .doc(myUserId)
  .collection('inbox')
  .snapshots()
  .listen((snapshot) {
    for (var change in snapshot.docChanges) {
      if (change.type == DocumentChangeType.added) {
        final message = Message.fromFirestore(...);
        // Aggiorna UI automaticamente
      }
    }
  });
```

### 5. Struttura dati Firestore

#### Prima
```
messages/{messageId}
  - id
  - senderId
  - receiverId
  - encryptedContent
  - timestamp
  - isDelivered
  - isRead
```

#### Dopo
```
users/{userId}
  - public_key
  - created_at

users/{userId}/inbox/{messageId}
  - ciphertext
  - nonce
  - tag
  - created_at
```

## Breaking Changes

### API Changes

1. **POST /api/auth/register**
   - ❌ Rimosso: `username`, `password`
   - ✅ Richiesto: `publicKey`
   - ✅ Risposta: `backend_token`, `firebase_token`

2. **POST /api/auth/login**
   - ❌ Rimosso: `username`, `password`
   - ✅ Richiesto: `publicKey`

3. **POST /api/messages** (nuovo)
   - ✅ Body: `recipient_id`, `ciphertext`, `nonce`, `tag`

4. **GET /api/users/partner** (rimosso)
   - ✅ Sostituito da: GET /api/users

### Flutter Changes

1. **AuthService**
   - `register()` - no params (genera chiavi automaticamente)
   - `login(publicKey)` - richiede publicKey salvata
   - `getUsers()` - nuovo metodo
   - `getPartner()` - rimosso

2. **ChatService**
   - `connect()` - rimosso
   - `disconnect()` - rimosso
   - `startListening(userId)` - nuovo
   - `stopListening()` - nuovo
   - `sendMessage(content, recipientId, token)` - signature cambiata
   - `decryptMessage(Message)` - signature cambiata

3. **Message Model**
   - ❌ Rimosso: `senderId`, `receiverId`, `encryptedContent`, `isDelivered`, `isRead`
   - ✅ Aggiunto: `ciphertext`, `nonce`, `tag`

## Passi per migrare

### Backend

1. Installa nuove dipendenze:
   ```bash
   cd backend
   npm install
   ```

2. Deploy regole Firestore:
   ```bash
   firebase deploy --only firestore:rules
   ```

3. Aggiorna variabili ambiente:
   ```env
   JWT_SECRET=your_secret
   GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
   GOOGLE_CLOUD_PROJECT_ID=your-project-id
   ```

4. Restart server:
   ```bash
   npm start
   ```

### Flutter

1. Pulisci dipendenze old:
   ```bash
   cd flutter-app
   flutter clean
   ```

2. Installa nuove dipendenze:
   ```bash
   flutter pub get
   ```

3. Configura Firebase:
   - Aggiungi `google-services.json` (Android)
   - Aggiungi `GoogleService-Info.plist` (iOS)

4. Aggiorna UI:
   - Rimuovi username/password input
   - Cambia `chatService.connect()` → `chatService.startListening()`
   - Aggiorna chiamate `sendMessage()` e `decryptMessage()`

5. Test:
   ```bash
   flutter run
   ```

## Vantaggi

✅ **Performance**: Firestore realtime più efficiente di Socket.io
✅ **Scalabilità**: Firestore gestisce automaticamente la scalabilità
✅ **Sicurezza**: Regole Firestore granulari per ogni utente
✅ **Offline**: Firestore supporta cache offline nativa
✅ **Semplicità**: No server websocket custom da gestire
✅ **Identità**: userId basato su chiave pubblica (più sicuro)

## Supporto

Per domande o problemi con la migrazione:
1. Leggi `backend/README.md` per documentazione API
2. Leggi `flutter-app/README.md` per documentazione Flutter
3. Controlla i TODO nei file per funzionalità da completare
