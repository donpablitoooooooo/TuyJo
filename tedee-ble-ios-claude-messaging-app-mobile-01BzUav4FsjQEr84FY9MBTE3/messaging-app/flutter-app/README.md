# Family Chat Flutter App - Firestore Realtime

App Flutter per messaggistica con E2E encryption e Firestore realtime.

## Architettura

- **Flutter Client**: UI e gestione E2EE
- **Firebase Auth**: Autenticazione con Custom Tokens
- **Cloud Firestore**: Storage e realtime messaging
- **Backend Node.js**: API REST per messaggi e autenticazione

## Struttura Firestore

I messaggi sono organizzati come inbox personali:

```
users/{userId}/inbox/{messageId}
  ├─ ciphertext: string (base64)
  ├─ nonce: string (base64)
  ├─ tag: string (base64)
  └─ created_at: timestamp
```

Dove `userId = SHA-256(publicKey)`.

## Setup

### 1. Installa dipendenze

```bash
flutter pub get
```

### 2. Configura Firebase

1. Crea un progetto Firebase
2. Aggiungi app Android/iOS al progetto
3. Scarica `google-services.json` (Android) e `GoogleService-Info.plist` (iOS)
4. Posiziona i file nelle directory corrette:
   - Android: `android/app/google-services.json`
   - iOS: `ios/Runner/GoogleService-Info.plist`

### 3. Deploy regole Firestore

```bash
firebase deploy --only firestore:rules
```

Usa il file `firestore.rules` dal backend.

### 4. Configura Backend URL

Modifica `baseUrl` in:
- `lib/services/auth_service.dart`
- `lib/services/chat_service.dart`

## Flusso di autenticazione

### 1. Registrazione

```dart
final authService = Provider.of<AuthService>(context);

// Genera automaticamente chiavi RSA
await authService.register();

// Ricevi:
// - backend_token (per API REST)
// - firebase_token (per Firebase Auth)
// - userId (SHA-256 della chiave pubblica)
```

### 2. Login

```dart
// Usa la chiave pubblica salvata
final publicKey = await storage.read(key: 'public_key');
await authService.login(publicKey);
```

### 3. Autenticazione Firebase

```dart
// Automatico dopo register/login
// FirebaseAuth.instance.currentUser.uid == userId
```

## Flusso messaggi

### 1. Avvia listener Firestore

```dart
final chatService = Provider.of<ChatService>(context);
final userId = authService.currentUser!.id;

// Inizia ad ascoltare la propria inbox
chatService.startListening(userId);
```

### 2. Invia messaggio

```dart
await chatService.sendMessage(
  'Ciao!',                          // contenuto
  recipientId,                      // destinatario
  authService.backendToken!,        // token backend
);
```

Il messaggio viene:
1. Cifrato con `K_family` (AES-GCM)
2. Inviato al backend via POST /api/messages
3. Scritto da backend in `users/{recipientId}/inbox/{messageId}`
4. Ricevuto in realtime dal destinatario via Firestore listener

### 3. Ricezione messaggi

```dart
// Automatica tramite listener
chatService.messages.forEach((message) {
  final plaintext = chatService.decryptMessage(message);
  print('Messaggio: $plaintext');
});
```

## Servizi principali

### AuthService

- `register()`: Registra nuovo utente con chiavi RSA
- `login(publicKey)`: Login con chiave pubblica
- `logout()`: Logout e pulizia
- `getUsers()`: Lista utenti disponibili
- `getUserById(userId)`: Ottieni utente specifico

### ChatService

- `startListening(userId)`: Avvia listener Firestore inbox
- `stopListening()`: Ferma listener
- `sendMessage(content, recipientId, token)`: Invia messaggio cifrato
- `decryptMessage(message)`: Decifra messaggio ricevuto
- `loadMessages(token)`: Carica cronologia da API
- `clearMessages()`: Pulisci cache locale

### EncryptionService

- `generateKeyPair()`: Genera coppia chiavi RSA
- `encryptMessageWithSharedKey(plaintext)`: Cifra con K_family
- `decryptMessageWithSharedKey(ciphertext, nonce, tag)`: Decifra con K_family
- `loadPrivateKey(pem)`: Carica chiave privata

## Modelli dati

### Message

```dart
class Message {
  final String id;
  final String ciphertext;   // base64
  final String nonce;         // base64
  final String tag;           // base64
  final DateTime timestamp;
  final String? senderId;     // estratto dal plaintext
}
```

### User

```dart
class User {
  final String id;            // SHA-256(publicKey)
  final String publicKey;     // PEM or base64
}
```

## Sicurezza

### E2EE con K_family

Tutti i messaggi sono cifrati end-to-end:

1. **Plaintext** (prima della cifratura):
   ```json
   {
     "sender": "user_id_mittente",
     "timestamp": 1733400000,
     "type": "text",
     "body": "Contenuto del messaggio"
   }
   ```

2. **Cifrato con K_family** (AES-256-GCM)
3. **Storage**: Solo `ciphertext`, `nonce`, `tag` in Firestore
4. **Decifratura**: Solo client con `K_family` può leggere

### Regole Firestore

- Lettura: Solo proprietario dell'inbox
- Scrittura: Solo backend con Admin SDK
- Nessun accesso diretto tra client

## TODO

- [ ] Implementare derivazione `K_family` da chiavi RSA
- [ ] Aggiornare UI per nuova autenticazione (no username/password)
- [ ] Implementare challenge/response per login sicuro
- [ ] Gestire errori di cifratura/decifratura
- [ ] Aggiungere supporto messaggi multimediali
- [ ] Implementare eliminazione messaggi
- [ ] Gestire notifiche push

## Run

```bash
# Debug
flutter run

# Release
flutter build apk
flutter build ios
```

## Note importanti

⚠️ **BREAKING CHANGES**:
- Rimosso Socket.io → Firestore realtime
- Rimosso username/password → Solo publicKey
- Cambiata struttura messaggi → Inbox-based
- JWT backend + Firebase Custom Token

⚠️ **Migration**:
Se stai aggiornando da versione precedente, dovrai:
1. Pulire dati locali (flutter_secure_storage)
2. Rifare registrazione
3. Aggiornare UI per nuovi flussi auth
