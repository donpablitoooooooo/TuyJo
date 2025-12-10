import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:asn1lib/asn1lib.dart';
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
    final privateKey = _decodePrivateKey(privateKeyStr);
    // Create a placeholder public key derived from the private key
    final publicKey = RSAPublicKey(
      (privateKey as RSAPrivateKey).modulus!,
      (privateKey).publicExponent!,
    );
    _keyPair = AsymmetricKeyPair(publicKey, privateKey);
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

  SecureRandom _getSecureRandom() {
    final secureRandom = FortunaRandom();
    final seedSource = Random.secure();
    final seeds = List<int>.generate(32, (_) => seedSource.nextInt(256));
    secureRandom.seed(KeyParameter(Uint8List.fromList(seeds)));
    return secureRandom;
  }

  Uint8List _generateRandomKey(int length) {
    final random = Random.secure();
    return Uint8List.fromList(List<int>.generate(length, (_) => random.nextInt(256)));
  }

  String _encodePublicKey(RSAPublicKey publicKey) {
    final algorithmSeq = ASN1Sequence();
    final objectId = ASN1ObjectIdentifier([1, 2, 840, 113549, 1, 1, 1]); // rsaEncryption OID
    algorithmSeq.add(objectId);
    algorithmSeq.add(ASN1Null());

    final publicKeySeq = ASN1Sequence();
    publicKeySeq.add(ASN1Integer(publicKey.modulus!));
    publicKeySeq.add(ASN1Integer(publicKey.exponent!));

    final publicKeySeqBitString = ASN1BitString(publicKeySeq.encodedBytes);

    final topLevelSeq = ASN1Sequence();
    topLevelSeq.add(algorithmSeq);
    topLevelSeq.add(publicKeySeqBitString);

    return base64Encode(topLevelSeq.encodedBytes);
  }

  String _encodePrivateKey(RSAPrivateKey privateKey) {
    final privateKeySeq = ASN1Sequence();
    
    // Validate required fields
    if (privateKey.p == null || privateKey.q == null) {
      throw ArgumentError('Private key must have p and q values');
    }
    
    final dP = privateKey.privateExponent! % (privateKey.p! - BigInt.one);
    final dQ = privateKey.privateExponent! % (privateKey.q! - BigInt.one);
    final qInv = privateKey.q!.modInverse(privateKey.p!);
    
    privateKeySeq.add(ASN1Integer(BigInt.zero)); // version
    privateKeySeq.add(ASN1Integer(privateKey.modulus!));
    privateKeySeq.add(ASN1Integer(privateKey.publicExponent!));
    privateKeySeq.add(ASN1Integer(privateKey.privateExponent!));
    privateKeySeq.add(ASN1Integer(privateKey.p!));
    privateKeySeq.add(ASN1Integer(privateKey.q!));
    privateKeySeq.add(ASN1Integer(dP));
    privateKeySeq.add(ASN1Integer(dQ));
    privateKeySeq.add(ASN1Integer(qInv));

    return base64Encode(privateKeySeq.encodedBytes);
  }

  RSAPublicKey _decodePublicKey(String publicKeyStr) {
    if (publicKeyStr.isEmpty) {
      throw ArgumentError('Public key string cannot be empty');
    }
    
    try {
      final bytes = base64Decode(publicKeyStr);
      final asn1Parser = ASN1Parser(bytes);
      final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;
      
      if (topLevelSeq.elements == null || topLevelSeq.elements!.length < 2) {
        throw FormatException('Invalid public key ASN.1 structure');
      }
      
      final publicKeyBitString = topLevelSeq.elements![1] as ASN1BitString;
      
      final publicKeySeq = ASN1Parser(publicKeyBitString.valueBytes()).nextObject() as ASN1Sequence;
      
      if (publicKeySeq.elements == null || publicKeySeq.elements!.length < 2) {
        throw FormatException('Invalid public key sequence structure');
      }
      
      final modulus = (publicKeySeq.elements![0] as ASN1Integer).valueAsBigInteger!;
      final exponent = (publicKeySeq.elements![1] as ASN1Integer).valueAsBigInteger!;

      return RSAPublicKey(modulus, exponent);
    } catch (e) {
      throw FormatException('Failed to decode public key: $e');
    }
  }

  RSAPrivateKey _decodePrivateKey(String privateKeyStr) {
    try {
      final bytes = base64Decode(privateKeyStr);
      final asn1Parser = ASN1Parser(bytes);
      final privateKeySeq = asn1Parser.nextObject() as ASN1Sequence;

      // PKCS#1 RSAPrivateKey requires 9 elements: version, n, e, d, p, q, dP, dQ, qInv
      if (privateKeySeq.elements == null || privateKeySeq.elements!.length < 9) {
        throw FormatException('Invalid private key ASN.1 structure - requires 9 elements');
      }

      final modulus = (privateKeySeq.elements![1] as ASN1Integer).valueAsBigInteger!;
      final publicExponent = (privateKeySeq.elements![2] as ASN1Integer).valueAsBigInteger!;
      final privateExponent = (privateKeySeq.elements![3] as ASN1Integer).valueAsBigInteger!;
      final p = (privateKeySeq.elements![4] as ASN1Integer).valueAsBigInteger!;
      final q = (privateKeySeq.elements![5] as ASN1Integer).valueAsBigInteger!;

      // Check if the RSAPrivateKey constructor expects different parameter order
      // Standard: RSAPrivateKey(modulus, privateExponent, p, q)
      return RSAPrivateKey(modulus, privateExponent, p, q);
    } catch (e) {
      throw FormatException('Failed to decode private key: $e');
    }
  }

  Uint8List _rsaEncrypt(Uint8List data, RSAPublicKey publicKey) {
    final encryptor = OAEPEncoding(RSAEngine())
      ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));
    return _processInBlocks(encryptor, data);
  }

  Uint8List _rsaDecrypt(Uint8List data) {
    final privateKey = _keyPair!.privateKey as RSAPrivateKey;
    final decryptor = OAEPEncoding(RSAEngine())
      ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    return _processInBlocks(decryptor, data);
  }

  Uint8List _processInBlocks(AsymmetricBlockCipher engine, Uint8List input) {
    final numBlocks = (input.length + engine.inputBlockSize - 1) ~/ engine.inputBlockSize;

    final output = BytesBuilder();

    for (var i = 0; i < numBlocks; i++) {
      final start = i * engine.inputBlockSize;
      final end = (start + engine.inputBlockSize <= input.length) 
          ? start + engine.inputBlockSize 
          : input.length;

      output.add(engine.process(input.sublist(start, end)));
    }

    return output.toBytes();
  }
}
