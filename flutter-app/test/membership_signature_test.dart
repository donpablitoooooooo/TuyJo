import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:private_messaging/services/encryption_service.dart';
import 'package:private_messaging/services/membership_service.dart';

/// joinFamily (functions/membership.js) verifica una firma RSA-SHA256 sul
/// testo joinMessage: qui si controlla che l'app firmi quel testo, nel
/// formato giusto, con la chiave privata caricata.
void main() {
  test('il testo firmato è quello che si aspetta la Cloud Function', () {
    expect(MembershipService.joinMessage('fam', 'uid', 1700000000000),
        'tuijo-join|v1|fam|uid|1700000000000');
    expect(MembershipService.familyIdOf('b', 'a'), MembershipService.familyIdOf('a', 'b'));
  });

  test('firma RSA PKCS#1 v1.5 SHA-256 deterministica, 2048 bit', () async {
    final enc = EncryptionService();
    final keys = await enc.generateKeyPair();
    final message = MembershipService.joinMessage('fam', 'uid', 1700000000000);
    final signature = enc.signSha256(message, privateKeyStr: keys['privateKey']);

    // Con TUIJO_SIGNATURE_FIXTURE=<file> scrive chiave, testo e firma: è
    // così che è nato functions/test-fixture-dart-signature.json, che
    // functions/test-membership.js verifica con Node.
    final out = Platform.environment['TUIJO_SIGNATURE_FIXTURE'];
    if (out != null) {
      File(out).writeAsStringSync(
          '{"publicKey":"${keys['publicKey']}","message":"$message","signature":"$signature"}');
    }

    enc.loadPrivateKey(keys['privateKey']!);
    expect(enc.signSha256(message), signature); // PKCS#1 v1.5 è deterministica
    expect(base64Decode(signature).length, 256); // RSA-2048
  });
}
