import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:pointycastle/asn1.dart';
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
    algorithmSeq.add(ASN1ObjectIdentifier.fromName('rsaEncryption'));
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
    privateKeySeq.add(ASN1Integer(BigInt.zero)); // version
    privateKeySeq.add(ASN1Integer(privateKey.modulus!));
    privateKeySeq.add(ASN1Integer(privateKey.publicExponent!));
    privateKeySeq.add(ASN1Integer(privateKey.privateExponent!));
    privateKeySeq.add(ASN1Integer(privateKey.p!));
    privateKeySeq.add(ASN1Integer(privateKey.q!));
    privateKeySeq.add(ASN1Integer(privateKey.privateExponent! % (privateKey.p! - BigInt.one)));
    privateKeySeq.add(ASN1Integer(privateKey.privateExponent! % (privateKey.q! - BigInt.one)));
    privateKeySeq.add(ASN1Integer(privateKey.q!.modInverse(privateKey.p!)));

    return base64Encode(privateKeySeq.encodedBytes);
  }

  RSAPublicKey _decodePublicKey(String publicKeyStr) {
    if (publicKeyStr.isEmpty) {
      return RSAPublicKey(BigInt.zero, BigInt.zero);
    }
    
    final bytes = base64Decode(publicKeyStr);
    final asn1Parser = ASN1Parser(bytes);
    final topLevelSeq = asn1Parser.nextObject() as ASN1Sequence;
    final publicKeyBitString = topLevelSeq.elements[1] as ASN1BitString;
    
    final publicKeySeq = ASN1Parser(publicKeyBitString.contentBytes()).nextObject() as ASN1Sequence;
    final modulus = (publicKeySeq.elements[0] as ASN1Integer).valueAsBigInteger;
    final exponent = (publicKeySeq.elements[1] as ASN1Integer).valueAsBigInteger;

    return RSAPublicKey(modulus!, exponent!);
  }

  RSAPrivateKey _decodePrivateKey(String privateKeyStr) {
    final bytes = base64Decode(privateKeyStr);
    final asn1Parser = ASN1Parser(bytes);
    final privateKeySeq = asn1Parser.nextObject() as ASN1Sequence;

    final modulus = (privateKeySeq.elements[1] as ASN1Integer).valueAsBigInteger;
    final privateExponent = (privateKeySeq.elements[3] as ASN1Integer).valueAsBigInteger;
    final p = (privateKeySeq.elements[4] as ASN1Integer).valueAsBigInteger;
    final q = (privateKeySeq.elements[5] as ASN1Integer).valueAsBigInteger;

    return RSAPrivateKey(modulus!, privateExponent!, p, q);
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
    final numBlocks = input.length ~/ engine.inputBlockSize + 
        ((input.length % engine.inputBlockSize != 0) ? 1 : 0);

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
