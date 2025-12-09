# Family Chat Backend - Firestore Realtime

Backend Node.js per app di messaggistica con E2E encryption e Firestore realtime.

## Architettura

- **Backend Node.js**: Gestisce autenticazione e scrittura messaggi
- **Firestore**: Storage e canale realtime per messaggi
- **Firebase Custom Tokens**: Autenticazione client a Firebase
- **E2EE**: Messaggi cifrati end-to-end con `K_family`

## Struttura Firestore

```
users/{userId}
  ├─ public_key: string
  └─ created_at: timestamp

users/{userId}/inbox/{messageId}
  ├─ ciphertext: string (base64)
  ├─ nonce: string (base64)
  ├─ tag: string (base64)
  └─ created_at: timestamp
```

Dove `userId = SHA-256(publicKey)` in formato hex.

## API Endpoints

### Autenticazione

#### POST /api/auth/register
Registra un nuovo utente.

**Request:**
```json
{
  "publicKey": "-----BEGIN PUBLIC KEY-----\n..."
}
```

**Response:**
```json
{
  "backend_token": "jwt_token_for_backend_api",
  "firebase_token": "custom_token_for_firebase_auth",
  "user": {
    "id": "sha256_hash",
    "public_key": "..."
  }
}
```

#### POST /api/auth/login
Login con chiave pubblica.

**Request:**
```json
{
  "publicKey": "-----BEGIN PUBLIC KEY-----\n..."
}
```

**Response:** Stesso formato del register.

### Messaggi

#### POST /api/messages
Invia un messaggio cifrato.

**Headers:**
```
Authorization: Bearer <backend_token>
```

**Request:**
```json
{
  "recipient_id": "sha256_hash_destinatario",
  "ciphertext": "base64...",
  "nonce": "base64...",
  "tag": "base64..."
}
```

**Response:**
```json
{
  "success": true,
  "message_id": "uuid",
  "created_at": 1733400000
}
```

#### GET /api/messages
Ottieni tutti i messaggi della propria inbox.

**Headers:**
```
Authorization: Bearer <backend_token>
```

**Response:**
```json
[
  {
    "id": "uuid",
    "ciphertext": "base64...",
    "nonce": "base64...",
    "tag": "base64...",
    "created_at": 1733400000
  }
]
```

#### DELETE /api/messages/:messageId
Elimina un messaggio dalla propria inbox.

### Utenti

#### GET /api/users
Ottieni lista utenti (escluso se stesso).

#### GET /api/users/:userId
Ottieni un utente specifico.

#### POST /api/users/fcm-token
Aggiorna token FCM per notifiche push.

## Environment Variables

```env
# Server
PORT=3000
NODE_ENV=production

# JWT per autenticazione backend
JWT_SECRET=your_jwt_secret_here

# Firebase Admin SDK
GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
GOOGLE_CLOUD_PROJECT_ID=your-project-id
```

## Firestore Security Rules

Le regole permettono:
- Lettura solo della propria inbox
- Scritture solo dal backend (Admin SDK)

Deploy delle regole:
```bash
firebase deploy --only firestore:rules
```

## Client Integration

### 1. Autenticazione
```dart
// 1. Login al backend
final response = await http.post('/api/auth/login', body: {
  'publicKey': myPublicKey
});

final backendToken = response['backend_token'];
final firebaseToken = response['firebase_token'];

// 2. Autentica a Firebase
await FirebaseAuth.instance.signInWithCustomToken(firebaseToken);
```

### 2. Ricezione messaggi realtime
```dart
FirebaseFirestore.instance
  .collection('users')
  .doc(myUserId)
  .collection('inbox')
  .orderBy('created_at', descending: false)
  .snapshots()
  .listen((snapshot) {
    for (var change in snapshot.docChanges) {
      if (change.type == DocumentChangeType.added) {
        final data = change.doc.data();
        // Decifra con K_family
        final message = decryptMessage(
          data['ciphertext'],
          data['nonce'],
          data['tag']
        );
      }
    }
  });
```

### 3. Invio messaggi
```dart
// Cifra con K_family
final encrypted = encryptMessage(plaintext);

// Invia al backend
await http.post('/api/messages',
  headers: {'Authorization': 'Bearer $backendToken'},
  body: {
    'recipient_id': recipientUserId,
    'ciphertext': encrypted.ciphertext,
    'nonce': encrypted.nonce,
    'tag': encrypted.tag
  }
);
```

## Deployment

```bash
# Install dependencies
npm install

# Start server
npm start

# Development with auto-reload
npm run dev
```

## TODO

- [ ] Implementare challenge/response con firma RSA per login sicuro
- [ ] Rate limiting sugli endpoint
- [ ] Monitoraggio e logging
- [ ] Gestione errori avanzata
