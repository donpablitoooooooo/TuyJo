# 🔐 Family Chat - Guida al Pairing con QR Code

Questa guida descrive come funziona il pairing tra dispositivi usando QR code per condividere K_family.

## Architettura Pairing

### Concetti chiave

1. **Chiavi RSA personali**:
   - Ogni utente genera la propria coppia RSA (pubblica/privata)
   - `userId = SHA-256(publicKey)`
   - Usate solo per identità, NON per cifratura messaggi

2. **K_family** (chiave simmetrica):
   - Chiave AES-256 condivisa tra i membri della famiglia
   - Generata dal primo utente che crea la famiglia
   - Condivisa tramite QR code
   - Usata per cifrare TUTTI i messaggi (E2EE)

3. **Firestore**:
   - Backend storage per messaggi cifrati
   - Struttura: `users/{userId}/inbox/{messageId}`
   - Realtime updates automatici

## Flusso Pairing

### Setup Iniziale

Entrambi gli utenti devono prima:
```dart
// 1. Registrarsi e generare chiavi RSA personali
await authService.register();

// Questo genera:
// - RSA key pair (personale)
// - userId = SHA-256(publicKey)
// - Backend token + Firebase custom token
```

### Opzione 1: Creo io la chiave famiglia

**Utente A (creatore)**:

1. Naviga a `PairingChoiceScreen`
2. Seleziona "Creo io la chiave famiglia"
3. App genera K_family:
   ```dart
   // Genera 32 byte random (AES-256)
   final kFamily = await pairingService.generateFamilyKey();
   ```

4. App crea QR data:
   ```json
   {
     "k_family": "base64_encoded_k_family",
     "creator_public_key": "base64_encoded_public_key"
   }
   ```

5. Mostra QR code sullo schermo

**Cosa viene salvato**:
```
flutter_secure_storage:
  - k_family: <base64>
  - public_key: <own_public_key>
```

### Opzione 2: Leggo la chiave famiglia

**Utente B (scanner)**:

1. Naviga a `PairingChoiceScreen`
2. Seleziona "Leggo la chiave famiglia"
3. Scanner si apre automaticamente
4. Inquadra QR code di Utente A
5. App importa K_family:
   ```dart
   await pairingService.importFamilyKeyFromQR(qrData);
   ```

**Cosa viene salvato**:
```
flutter_secure_storage:
  - k_family: <base64> (stesso di A)
  - partner_public_key: <creator_public_key>
  - public_key: <own_public_key>
```

### Risultato

Entrambi gli utenti ora hanno:
- ✅ K_family condivisa (identica)
- ✅ Propria identità RSA (diversa)
- ✅ Public key del partner

## Invio Messaggi

### Cifratura

```dart
// 1. Costruisci plaintext
final plaintext = {
  'sender': senderId,
  'timestamp': 1733400000,
  'type': 'text',
  'body': 'Ciao!'
};

// 2. Ottieni K_family
final kFamily = await pairingService.getFamilyKey();

// 3. Cifra con K_family (AES-256-GCM)
final encrypted = encryptionService.encryptWithFamilyKey(
  json.encode(plaintext),
  kFamily
);

// Risultato:
{
  'ciphertext': 'base64...',
  'nonce': 'base64...',      // 12 byte random
  'tag': 'base64...',        // 16 byte auth tag
}

// 4. Invia al backend
POST /api/messages {
  recipient_id: recipientUserId,
  ciphertext: ...,
  nonce: ...,
  tag: ...
}
```

### Backend

```javascript
// Backend scrive in Firestore (Admin SDK)
users/{recipientId}/inbox/{messageId} = {
  ciphertext: ...,
  nonce: ...,
  tag: ...,
  created_at: timestamp
}
```

### Ricezione Realtime

```dart
// Listener Firestore automatico
firestore
  .collection('users')
  .doc(myUserId)
  .collection('inbox')
  .snapshots()
  .listen((snapshot) {
    // Nuovo messaggio!
    final message = Message.fromFirestore(...);

    // Decifra con K_family
    final kFamily = await pairingService.getFamilyKey();
    final plaintext = encryptionService.decryptWithFamilyKey(
      message.ciphertext,
      message.nonce,
      message.tag,
      kFamily
    );

    // Mostra in UI
  });
```

## Sicurezza

### Cosa rimane sul device

```
flutter_secure_storage (criptato):
├─ k_family                 → chiave AES-256 condivisa
├─ private_key              → chiave RSA privata
├─ public_key               → chiave RSA pubblica
├─ partner_public_key       → chiave pubblica partner
├─ backend_token            → JWT per API
└─ user                     → dati utente
```

### Cosa va sul server

**Backend Node.js**:
```
- userId (SHA-256 di public key)
- public_key (solo per identificazione)
- backend token (JWT)
```

**Firestore**:
```
users/{userId}:
  - public_key
  - created_at

users/{userId}/inbox/{messageId}:
  - ciphertext  (cifrato con K_family)
  - nonce
  - tag
  - created_at
```

### K_family NON va mai sul server!

✅ **Sicuro**:
- K_family generata localmente
- Condivisa solo tramite QR (locale)
- Mai trasmessa al backend
- Mai salvata su Firestore

❌ **Se compromesso il server**:
- Attacker vede solo ciphertext
- Non può decifrare senza K_family
- K_family è solo sui dispositivi paired

## Testing

### Test manuale

1. **Setup Device 1**:
   ```bash
   flutter run -d device1
   ```
   - Register nuovo utente
   - Seleziona "Creo io la chiave famiglia"
   - Mostra QR

2. **Setup Device 2**:
   ```bash
   flutter run -d device2
   ```
   - Register nuovo utente
   - Seleziona "Leggo la chiave famiglia"
   - Scansiona QR di Device 1

3. **Test Messaging**:
   - Device 1: Invia "Ciao da Device 1"
   - Device 2: Dovrebbe ricevere in realtime
   - Verifica decifrazione corretta

### Debug

Attiva debug logs:
```dart
// In PairingService
if (kDebugMode) print('K_family: ${kFamily.substring(0, 10)}...');

// In ChatService
if (kDebugMode) print('Message sent: $messageId');
```

## File Structure

```
lib/
├── services/
│   ├── pairing_service.dart       → K_family management
│   ├── encryption_service.dart    → AES-GCM encryption
│   ├── auth_service.dart          → User auth
│   └── chat_service.dart          → Messaging
│
├── screens/
│   ├── pairing_choice_screen.dart → Menu 2 opzioni
│   ├── qr_display_screen.dart     → Mostra QR
│   └── qr_scanner_screen.dart     → Scansiona QR
│
└── models/
    └── message.dart               → Message model
```

## Dependencies

```yaml
dependencies:
  # QR Code
  qr_flutter: ^4.1.0          # Generate QR
  mobile_scanner: ^3.5.2      # Scan QR

  # Encryption
  pointycastle: ^3.9.1        # RSA + AES-GCM
  crypto: ^3.0.3              # Hashing

  # Firebase
  firebase_core: ^2.24.2
  firebase_auth: ^4.15.3
  cloud_firestore: ^4.13.6

  # Storage
  flutter_secure_storage: ^9.0.0
```

## TODO

- [ ] Aggiungere timeout QR scanner (30 sec)
- [ ] Gestire reset pairing (elimina K_family)
- [ ] Aggiungere verifica identità partner
- [ ] UI migliorata per pairing flow
- [ ] Gestire cambio K_family (re-pairing)
- [ ] Backup/restore K_family
- [ ] Multi-device support (stessa K_family su più device)

## Troubleshooting

### QR non viene riconosciuto
- Verifica buona illuminazione
- Controlla permessi camera
- Verifica formato QR data (JSON valid)

### Messaggi non decifrabili
- Verifica K_family uguale su entrambi device
- Controlla log encryption errors
- Verifica nonce/tag non corrotti

### Pairing non completa
- Verifica connessione backend
- Controlla auth Firebase
- Verifica storage permissions

## Risorse

- [AES-GCM Spec](https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-38d.pdf)
- [PointyCastle Docs](https://pub.dev/packages/pointycastle)
- [QR Flutter](https://pub.dev/packages/qr_flutter)
- [Mobile Scanner](https://pub.dev/packages/mobile_scanner)
