import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import 'package:crypto/crypto.dart';

/// Servizio di crittografia per Family Chat
/// - RSA-2048 per autenticazione (challenge/response)
/// - AES-256-GCM per messaggi (chiave simmetrica K_family)
class EncryptionService {
  AsymmetricKeyPair<PublicKey, PrivateKey>? _keyPair;
  Uint8List? _kFamily;

  // ========== RSA KEY MANAGEMENT ==========

  /// Genera una coppia di chiavi RSA-2048
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

  /// Carica chiave privata da stringa
  void loadPrivateKey(String privateKeyStr) {
    final privateKey = _decodePrivateKey(privateKeyStr);
    _keyPair = AsymmetricKeyPair(
      null, // PublicKey non necessaria per decifratura
      privateKey,
    );
  }

  /// Ottieni chiave pubblica come stringa (per QR code)
  String getPublicKey() {
    if (_keyPair == null) {
      throw Exception('KeyPair not generated yet');
    }
    return _encodePublicKey(_keyPair!.publicKey as RSAPublicKey);
  }

  /// Calcola user_id = SHA-256(publicKey)
  String getUserId(String publicKey) {
    final bytes = utf8.encode(publicKey);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // ========== K_FAMILY MANAGEMENT ==========

  /// Genera chiave simmetrica K_family (32 byte = AES-256)
  String generateKFamily() {
    final random = Random.secure();
    _kFamily = Uint8List.fromList(
      List<int>.generate(32, (i) => random.nextInt(256)),
    );
    return base64Encode(_kFamily!);
  }

  /// Carica K_family da stringa base64
  void loadKFamily(String kFamilyStr) {
    _kFamily = base64Decode(kFamilyStr);
    if (_kFamily!.length != 32) {
      throw Exception('Invalid K_family length: ${_kFamily!.length}');
    }
  }

  /// Verifica se K_family è caricata
  bool get hasKFamily => _kFamily != null;

  // ========== AES-256-GCM ENCRYPTION ==========

  /// Cifra messaggio con AES-256-GCM usando K_family
  /// Ritorna: {ciphertext, nonce, tag} in base64
  Map<String, String> encryptMessage(String plaintext) {
    if (_kFamily == null) {
      throw Exception('K_family not loaded');
    }

    try {
      // Genera nonce casuale (12 byte per GCM)
      final nonce = _generateNonce();

      // Converti plaintext in bytes
      final plaintextBytes = utf8.encode(plaintext);

      // Inizializza AES-GCM
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          true, // encrypt
          AEADParameters(
            KeyParameter(_kFamily!),
            128, // tag size in bits (16 byte)
            nonce,
            Uint8List(0), // no additional data
          ),
        );

      // Cifra
      final ciphertext = Uint8List(plaintextBytes.length + 16); // +16 per tag
      var offset = cipher.processBytes(
        plaintextBytes,
        0,
        plaintextBytes.length,
        ciphertext,
        0,
      );
      cipher.doFinal(ciphertext, offset);

      // Separa ciphertext e tag
      final ciphertextOnly = ciphertext.sublist(0, plaintextBytes.length);
      final tag = ciphertext.sublist(plaintextBytes.length);

      return {
        'ciphertext': base64Encode(ciphertextOnly),
        'nonce': base64Encode(nonce),
        'tag': base64Encode(tag),
      };
    } catch (e) {
      if (kDebugMode) print('❌ Encryption error: $e');
      rethrow;
    }
  }

  /// Decifra messaggio con AES-256-GCM usando K_family
  String decryptMessage({
    required String ciphertext,
    required String nonce,
    required String tag,
  }) {
    if (_kFamily == null) {
      throw Exception('K_family not loaded');
    }

    try {
      final ciphertextBytes = base64Decode(ciphertext);
      final nonceBytes = base64Decode(nonce);
      final tagBytes = base64Decode(tag);

      // Combina ciphertext + tag
      final combined = Uint8List(ciphertextBytes.length + tagBytes.length);
      combined.setAll(0, ciphertextBytes);
      combined.setAll(ciphertextBytes.length, tagBytes);

      // Inizializza AES-GCM
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false, // decrypt
          AEADParameters(
            KeyParameter(_kFamily!),
            128, // tag size in bits
            nonceBytes,
            Uint8List(0), // no additional data
          ),
        );

      // Decifra
      final plaintext = Uint8List(ciphertextBytes.length);
      var offset = cipher.processBytes(
        combined,
        0,
        combined.length,
        plaintext,
        0,
      );
      cipher.doFinal(plaintext, offset);

      return utf8.decode(plaintext);
    } catch (e) {
      if (kDebugMode) print('❌ Decryption error: $e');
      rethrow;
    }
  }

  // ========== CHALLENGE/RESPONSE (RSA-SHA256) ==========

  /// Firma un challenge con la chiave privata RSA (SHA-256)
  String signChallenge(String challenge) {
    if (_keyPair == null) {
      throw Exception('Private key not loaded');
    }

    try {
      final privateKey = _keyPair!.privateKey as RSAPrivateKey;
      final signer = RSASigner(SHA256Digest(), '0609608648016503040201');
      signer.init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));

      final challengeBytes = utf8.encode(challenge);
      final signature = signer.generateSignature(challengeBytes);

      return base64Encode(signature.bytes);
    } catch (e) {
      if (kDebugMode) print('❌ Signature error: $e');
      rethrow;
    }
  }

  // ========== HELPER METHODS ==========

  Uint8List _generateNonce() {
    final random = Random.secure();
    return Uint8List.fromList(List<int>.generate(12, (i) => random.nextInt(256)));
  }

  SecureRandom _getSecureRandom() {
    final secureRandom = FortunaRandom();
    final random = Random.secure();
    final seeds = List<int>.generate(32, (_) => random.nextInt(256));
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));
    return secureRandom;
  }

  // ========== ENCODING/DECODING RSA KEYS ==========

  String _encodePublicKey(RSAPublicKey publicKey) {
    final modulus = publicKey.modulus!.toRadixString(16);
    final exponent = publicKey.exponent!.toRadixString(16);
    final encoded = '$modulus:$exponent';
    return base64Encode(utf8.encode(encoded));
  }

  String _encodePrivateKey(RSAPrivateKey privateKey) {
    final modulus = privateKey.modulus!.toRadixString(16);
    final privateExponent = privateKey.privateExponent!.toRadixString(16);
    final encoded = '$modulus:$privateExponent';
    return base64Encode(utf8.encode(encoded));
  }

  RSAPublicKey _decodePublicKey(String encoded) {
    final decoded = utf8.decode(base64Decode(encoded));
    final parts = decoded.split(':');
    final modulus = BigInt.parse(parts[0], radix: 16);
    final exponent = BigInt.parse(parts[1], radix: 16);
    return RSAPublicKey(modulus, exponent);
  }

  RSAPrivateKey _decodePrivateKey(String encoded) {
    try {
      // Pulisci whitespace
      final cleanEncoded = encoded.trim().replaceAll(RegExp(r'\s+'), '');

      if (kDebugMode) {
        print('🔓 Decoding private key:');
        print('   Original length: ${encoded.length}');
        print('   Cleaned length: ${cleanEncoded.length}');
      }

      final decoded = utf8.decode(base64Decode(cleanEncoded));
      final parts = decoded.split(':');

      final modulus = BigInt.parse(parts[0], radix: 16);
      final privateExponent = BigInt.parse(parts[1], radix: 16);

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
