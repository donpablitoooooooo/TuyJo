import 'package:flutter_test/flutter_test.dart';
import 'package:private_messaging/services/encryption_service.dart';
import 'package:private_messaging/services/link_preview_crypto.dart';

/// L'anteprima di un link non deve finire in chiaro su Firestore: si cifra
/// per entrambi i telefoni e ognuno la apre con la propria chiave.
void main() {
  test('anteprima cifrata: la aprono mittente e destinatario, niente in chiaro',
      () async {
    final sender = EncryptionService();
    final senderKeys = await sender.generateKeyPair();
    sender.loadPrivateKey(senderKeys['privateKey']!);

    final recipient = EncryptionService();
    final recipientKeys = await recipient.generateKeyPair();
    recipient.loadPrivateKey(recipientKeys['privateKey']!);

    const url = 'https://example.com/ristorante-da-mario';
    const title = 'Da Mario — trattoria';
    const description = 'Prenota un tavolo per due';

    final stored = LinkPreviewCrypto.encrypt(
      sender,
      url: url,
      title: title,
      description: description,
      myPublicKey: senderKeys['publicKey']!,
      partnerPublicKey: recipientKeys['publicKey']!,
    );

    // Quello che va su Firestore non contiene niente di leggibile.
    final everything = stored.values.join(' ');
    for (final secret in ['example.com', 'Mario', 'Prenota']) {
      expect(everything.contains(secret), isFalse);
    }

    for (final (who, iAmSender) in [(sender, true), (recipient, false)]) {
      final payload = LinkPreviewCrypto.payload(stored, iAmSender: iAmSender);
      final preview = LinkPreviewCrypto.decode(who.decryptMessage(payload!));
      expect(preview?.url, url);
      expect(preview?.title, title);
      expect(preview?.description, description);
    }
  });

  test('campo assente o incompleto: nessun payload', () {
    expect(LinkPreviewCrypto.payload(null, iAmSender: true), isNull);
    expect(LinkPreviewCrypto.payload({'iv': 'x'}, iAmSender: false), isNull);
    expect(LinkPreviewCrypto.decode('non è json'), isNull);
  });
}
