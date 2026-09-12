import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:private_messaging/services/encryption_service.dart';

/// Il ripristino (certificato incollato / cloud) ricarica SOLO la chiave
/// privata e ne deriva la pubblica: la chiave ricaricata deve decifrare ciò
/// che era stato cifrato per l'identità originale, altrimenti i vecchi
/// messaggi sono persi.
void main() {
  test('chiave privata ricaricata decifra i messaggi della stessa identità',
      () async {
    final original = EncryptionService();
    final keys = await original.generateKeyPair();
    final priv = keys['privateKey']!;
    final pub = keys['publicKey']!;

    // Messaggio cifrato per l'identità originale (come farebbe il partner).
    original.loadPrivateKey(priv);
    final payload = original.encryptMessage('ciao amore 🍒', pub);

    // Nuova installazione: solo la chiave privata dal backup.
    final restored = EncryptionService();
    restored.loadPrivateKey(priv);
    expect(restored.decryptMessage(payload), 'ciao amore 🍒');

    // La chiave AES avvolta con la pubblica originale si apre con la privata
    // ripristinata (stesso meccanismo di encrypted_key_sender/recipient).
    final aesKey = Uint8List.fromList(List.generate(32, (i) => i * 7 % 256));
    final wrapped = restored.encryptAesKeyOnly(aesKey, pub);
    expect(restored.decryptAesKeyOnly(wrapped), aesKey);
  });
}
