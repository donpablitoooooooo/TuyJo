import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt_lib;

class EncryptionService {
  AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>? _keyPair;

  // Genera una coppia di chiavi RSA (pubblica/privata)
  Future<Map<String, String>> generateKeyPair() async {
    final keyGen = RSAKeyGenerator()
      ..init(ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
        _getSecureRandom(),
      ));

    _keyPair = keyGen.generateKeyPair();

    final publicKey = _keyPair!.publicKey as RSAPublicKey;
    final privateKey = _keyPair!.privateKey as RSAPrivateKey;

    return {
      'publicKey': _encodePublicKey(publicKey),
      'privateKey': _encodePrivateKey(privateKey),
    };
  }

  // Carica la chiave privata
  void loadPrivateKey(String privateKeyStr) {
    _keyPair = AsymmetricKeyPair(
      _decodePublicKey(''), // Placeholder, not used
      _decodePrivateKey(privateKeyStr),
    );
  }

  // Cripta un messaggio usando la chiave pubblica del destinatario
  String encryptMessage(String message, String recipientPublicKey) {
    try {
      // Genera una chiave AES casuale per questo messaggio
      final aesKey = _generateRandomKey(32);

      // Cripta il messaggio con AES
      final key = encrypt_lib.Key(aesKey);
      final iv = encrypt_lib.IV.fromSecureRandom(16);
      final encrypter = encrypt_lib.Encrypter(encrypt_lib.AES(key));
      final encryptedMessage = encrypter.encrypt(message, iv: iv);

      // Cripta la chiave AES con RSA usando la chiave pubblica del destinatario
      final recipientPubKey = _decodePublicKey(recipientPublicKey);
      final encryptedAesKey = _rsaEncrypt(aesKey, recipientPubKey);

      // Combina tutto in un JSON
      final payload = {
        'encryptedKey': base64Encode(encryptedAesKey),
        'iv': iv.base64,
        'message': encryptedMessage.base64,
      };

      return base64Encode(utf8.encode(json.encode(payload)));
    } catch (e) {
      throw Exception('Encryption failed: $e');
    }
  }

  // Decripta un messaggio usando la propria chiave privata
  String decryptMessage(String encryptedPayload) {
    try {
      final payloadJson = json.decode(utf8.decode(base64Decode(encryptedPayload)));

      // Decripta la chiave AES con la propria chiave privata RSA
      final encryptedAesKey = base64Decode(payloadJson['encryptedKey']);
      final aesKey = _rsaDecrypt(encryptedAesKey);

      // Decripta il messaggio con AES
      final key = encrypt_lib.Key(aesKey);
      final iv = encrypt_lib.IV.fromBase64(payloadJson['iv']);
      final encrypter = encrypt_lib.Encrypter(encrypt_lib.AES(key));
      final encrypted = encrypt_lib.Encrypted.fromBase64(payloadJson['message']);

      return encrypter.decrypt(encrypted, iv: iv);
    } catch (e) {
      throw Exception('Decryption failed: $e');
    }
  }

  // ========== Helper Methods ==========

  Uint8List _generateRandomKey(int length) {
    final random = Random.secure();
    return Uint8List.fromList(List<int>.generate(length, (i) => random.nextInt(256)));
  }

  Uint8List _rsaEncrypt(Uint8List data, RSAPublicKey publicKey) {
    final encryptor = OAEPEncoding(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));
    return encryptor.process(data);
  }

  Uint8List _rsaDecrypt(Uint8List data) {
    final decryptor = OAEPEncoding(RSAEngine())
      ..init(false, PrivateKeyParameter<RSAPrivateKey>(_keyPair!.privateKey as RSAPrivateKey));
    return decryptor.process(data);
  }

  SecureRandom _getSecureRandom() {
    final secureRandom = FortunaRandom();
    final random = Random.secure();
    final seeds = List<int>.generate(32, (_) => random.nextInt(256));
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));
    return secureRandom;
  }

  String _encodePublicKey(RSAPublicKey publicKey) {
    final modulus = publicKey.modulus!.toRadixString(16);
    final exponent = publicKey.exponent!.toRadixString(16);
    return base64Encode(utf8.encode('$modulus:$exponent'));
  }

  String _encodePrivateKey(RSAPrivateKey privateKey) {
    final modulus = privateKey.modulus!.toRadixString(16);
    final exponent = privateKey.exponent!.toRadixString(16);
    return base64Encode(utf8.encode('$modulus:$exponent'));
  }

  RSAPublicKey _decodePublicKey(String encoded) {
    final parts = utf8.decode(base64Decode(encoded)).split(':');
    return RSAPublicKey(
      BigInt.parse(parts[0], radix: 16),
      BigInt.parse(parts[1], radix: 16),
    );
  }

  RSAPrivateKey _decodePrivateKey(String encoded) {
    final parts = utf8.decode(base64Decode(encoded)).split(':');
    return RSAPrivateKey(
      BigInt.parse(parts[0], radix: 16),
      BigInt.parse(parts[1], radix: 16),
    );
  }
}
