import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:private_messaging/services/encryption_service.dart';
import 'package:private_messaging/services/recovery_service.dart';

void main() {
  test('deposito: solo il partner apre il certificato', () {
    final crypto = EncryptionService();
    final me = crypto.generateEphemeralKeyPair();
    final partner = crypto.generateEphemeralKeyPair();
    final stranger = crypto.generateEphemeralKeyPair();

    final bundle = RecoveryCrypto.bundleJson(
      priv: me['privateKey']!,
      pub: me['publicKey']!,
      partner: partner['publicKey']!,
    );
    final sealed = RecoveryCrypto.seal(bundle, partner['publicKey']!);
    expect(sealed.keys, containsAll(['encrypted_key', 'iv', 'payload']));
    expect(sealed['payload'], isNot(contains(me['privateKey'])));

    final opened = RecoveryCrypto.openWith(
      sealed,
      (w) => crypto.rsaDecryptWithPrivateKey(partner['privateKey']!, w),
    );
    final b = RecoveryBundle.fromJson(opened);
    expect(b.priv, me['privateKey']);
    expect(b.pub, me['publicKey']);
    expect(b.partner, partner['publicKey']);

    expect(
      () => RecoveryCrypto.openWith(
        sealed,
        (w) => crypto.rsaDecryptWithPrivateKey(stranger['privateKey']!, w),
      ),
      throwsA(anything),
    );
  });

  test('risposta: ricifrata per la chiave temporanea del telefono nuovo', () {
    final crypto = EncryptionService();
    final me = crypto.generateEphemeralKeyPair();
    final partner = crypto.generateEphemeralKeyPair();
    final temp = crypto.generateEphemeralKeyPair();

    final bundle = RecoveryCrypto.bundleJson(
      priv: partner['privateKey']!,
      pub: partner['publicKey']!,
      partner: me['publicKey']!,
    );
    final answer = RecoveryCrypto.seal(bundle, temp['publicKey']!);
    final opened = RecoveryCrypto.openWith(
      answer,
      (w) => crypto.rsaDecryptWithPrivateKey(temp['privateKey']!, w),
    );
    final b = RecoveryBundle.fromJson(opened);
    // Il telefono nuovo ricostruisce la STESSA famiglia
    expect(
      RecoveryService.familyIdOf(b.pub, b.partner),
      RecoveryService.familyIdOf(me['publicKey']!, partner['publicKey']!),
    );
  });

  test('parseQr accetta solo QR di recupero ben formati', () {
    final id = List.filled(64, 'a').join();
    final ok = jsonEncode({'t': 'tuyjo_recovery', 'v': 1, 'id': id, 'pub': 'X'});
    expect(RecoveryService.parseQr(ok)?.id, id);
    expect(RecoveryService.parseQr(jsonEncode({'public_key': 'X', 'version': '2.0'})), isNull);
    expect(RecoveryService.parseQr(jsonEncode({'t': 'tuyjo_recovery', 'id': 'short', 'pub': 'X'})), isNull);
    expect(RecoveryService.parseQr('garbage'), isNull);
  });
}
