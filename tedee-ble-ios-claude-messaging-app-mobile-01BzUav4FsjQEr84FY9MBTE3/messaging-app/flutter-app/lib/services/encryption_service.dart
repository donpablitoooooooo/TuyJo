import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt_lib;

class EncryptionService {
  AsymmetricKeyPair<PublicKey, PrivateKey>? _keyPair;

  // Genera una coppia di chiavi RSA (pubblica/privata)
  Future<Map<String, String>> generateKeyPair() async {
    final keyGen = RSAKeyGenerator()
      ..init(ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
        _getSecureRandom(),
      ));

    final pair = keyGen.generateKeyPair();
    _keyPair = pair;

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
    final privateExponent = privateKey.privateExponent!.toRadixString(16);
    final combined = '$modulus:$privateExponent';
    final encoded = base64Encode(utf8.encode(combined));

    if (kDebugMode) {
      print('🔐 Encoding private key:');
      print('   Modulus length: ${modulus.length}');
      print('   PrivateExp length: ${privateExponent.length}');
      print('   Combined length: ${combined.length}');
      print('   Encoded length: ${encoded.length}');
      print('   First 50 chars: ${combined.substring(0, combined.length > 50 ? 50 : combined.length)}');
    }

    return encoded;
  }

  RSAPublicKey _decodePublicKey(String encoded) {
    final parts = utf8.decode(base64Decode(encoded)).split(':');
    return RSAPublicKey(
      BigInt.parse(parts[0], radix: 16),
      BigInt.parse(parts[1], radix: 16),
    );
  }

  RSAPrivateKey _decodePrivateKey(String encoded) {
    try {
      // Trim whitespace e rimuovi newlines
      final cleanEncoded = encoded.trim().replaceAll(RegExp(r'\s+'), '');

      if (cleanEncoded.isEmpty) {
        throw Exception('Private key is empty');
      }

      if (kDebugMode) {
        print('🔓 Decoding private key:');
        print('   Original length: ${encoded.length}');
        print('   Cleaned length: ${cleanEncoded.length}');
        print('   First 50 chars: ${cleanEncoded.substring(0, cleanEncoded.length > 50 ? 50 : cleanEncoded.length)}');
      }

      final decoded = utf8.decode(base64Decode(cleanEncoded));

      if (kDebugMode) {
        print('   Decoded length: ${decoded.length}');
        print('   First 50 chars of decoded: ${decoded.substring(0, decoded.length > 50 ? 50 : decoded.length)}');
      }

      final parts = decoded.split(':');

      if (kDebugMode) {
        print('   Parts count: ${parts.length}');
        if (parts.isNotEmpty) {
          print('   Part[0] length: ${parts[0].length}, first 20 chars: ${parts[0].substring(0, parts[0].length > 20 ? 20 : parts[0].length)}');
        }
        if (parts.length > 1) {
          print('   Part[1] length: ${parts[1].length}, first 20 chars: ${parts[1].substring(0, parts[1].length > 20 ? 20 : parts[1].length)}');
        }
      }

      if (parts.length != 2) {
        throw Exception('Invalid key format: expected 2 parts, got ${parts.length}');
      }

      if (parts[0].isEmpty || parts[1].isEmpty) {
        throw Exception('Invalid key format: empty modulus or exponent');
      }

      if (kDebugMode) {
        print('   Parsing BigInts...');
      }

      final modulus = BigInt.parse(parts[0], radix: 16);
      final privateExponent = BigInt.parse(parts[1], radix: 16);

      if (kDebugMode) {
        print('✅ Private key loaded successfully');
      }

      return RSAPrivateKey(modulus, privateExponent, null, null);
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('❌ Error decoding private key: $e');
        print('   Stack trace: $stackTrace');
      }
      rethrow;
    }
  }
}
