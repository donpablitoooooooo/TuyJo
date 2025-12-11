import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:asn1lib/asn1lib.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class EncryptionService {
  AsymmetricKeyPair<PublicKey, PrivateKey>? _keyPair;
  final _storage = const FlutterSecureStorage();

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

  // Genera e salva keypair in secure storage
  Future<void> generateAndStoreKeyPair() async {
    // Verifica se esiste già
    final existingPublicKey = await _storage.read(key: 'rsa_public_key');
    if (existingPublicKey != null) {
      // Keypair già esistente, carica la privata
      final privateKey = await _storage.read(key: 'rsa_private_key');
      if (privateKey != null) {
        loadPrivateKey(privateKey);
      }
      return;
    }

    // Genera nuova coppia di chiavi
    final keys = await generateKeyPair();

    // Salva in secure storage
    await _storage.write(key: 'rsa_public_key', value: keys['publicKey']!);
    await _storage.write(key: 'rsa_private_key', value: keys['privateKey']!);
  }

  // Ottiene la chiave pubblica dal secure storage
  Future<String?> getPublicKey() async {
    return await _storage.read(key: 'rsa_public_key');
  }

  // Deriva la chiave pubblica dalla chiave privata caricata e la salva
  Future<String?> deriveAndSavePublicKey() async {
    if (_keyPair == null) {
      return null;
    }

    final publicKey = _keyPair!.publicKey as RSAPublicKey;
    final encodedPublicKey = _encodePublicKey(publicKey);

    // Salva in secure storage
    await _storage.write(key: 'rsa_public_key', value: encodedPublicKey);

    return encodedPublicKey;
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
      print('🔍 DEBUG _decodePublicKey:');
      print('   Input length: ${publicKeyStr.length}');
      print('   First 30: ${publicKeyStr.substring(0, 30)}');

      final bytes = base64Decode(publicKeyStr);
      print('   Decoded bytes length: ${bytes.length}');

      final asn1Parser = ASN1Parser(bytes);
      final topLevelObj = asn1Parser.nextObject();
      print('   Top level object type: ${topLevelObj.runtimeType}');

      final topLevelSeq = topLevelObj as ASN1Sequence;
      print('   Top level seq elements: ${topLevelSeq.elements?.length}');

      if (topLevelSeq.elements == null || topLevelSeq.elements!.length < 2) {
        throw FormatException('Invalid public key ASN.1 structure - expected at least 2 elements, got ${topLevelSeq.elements?.length}');
      }

      print('   Element 0 type: ${topLevelSeq.elements![0].runtimeType}');
      print('   Element 1 type: ${topLevelSeq.elements![1].runtimeType}');

      final publicKeyBitString = topLevelSeq.elements![1] as ASN1BitString;

      // In X.509 SubjectPublicKeyInfo, il BitString contiene:
      // byte 0: numero di bit di padding (solitamente 0x00)
      // byte 1+: sequenza della chiave pubblica (modulus, exponent)
      final bitStringValueBytes = publicKeyBitString.valueBytes();
      print('   BitString valueBytes length: ${bitStringValueBytes.length}');
      print('   First byte (padding): 0x${bitStringValueBytes[0].toRadixString(16)}');

      // Skippa il primo byte (padding) per ottenere la sequenza della chiave
      final keySequenceBytes = bitStringValueBytes.sublist(1);
      print('   Key sequence bytes length: ${keySequenceBytes.length}');

      final publicKeySeq = ASN1Parser(keySequenceBytes).nextObject() as ASN1Sequence;
      print('   Public key seq elements: ${publicKeySeq.elements?.length}');

      if (publicKeySeq.elements == null || publicKeySeq.elements!.length < 2) {
        throw FormatException('Invalid public key sequence structure');
      }

      final modulus = (publicKeySeq.elements![0] as ASN1Integer).valueAsBigInteger!;
      final exponent = (publicKeySeq.elements![1] as ASN1Integer).valueAsBigInteger!;

      print('   ✅ Decoded successfully');

      return RSAPublicKey(modulus, exponent);
    } catch (e, stackTrace) {
      print('   ❌ Decoding failed: $e');
      print('   Stack trace: $stackTrace');
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

  // ========== K_family Encryption Methods (AES-GCM) ==========

  /// Cifra un messaggio con K_family usando AES-256-GCM
  /// Restituisce una Map con ciphertext, nonce, tag (tutti in base64)
  Map<String, String> encryptWithFamilyKey(String plaintext, String kFamilyBase64) {
    try {
      // Decode K_family da base64
      final kFamily = base64Decode(kFamilyBase64);

      // Genera un nonce random (12 byte per GCM)
      final nonce = _generateRandomKey(12);

      // Converti plaintext in bytes
      final plaintextBytes = utf8.encode(plaintext);

      // Setup GCM cipher
      final cipher = GCMBlockCipher(AESEngine());
      final params = AEADParameters(
        KeyParameter(kFamily),
        128, // tag size in bits
        nonce,
        Uint8List(0), // no additional authenticated data
      );

      cipher.init(true, params);

      // Cifra
      final outputBuffer = Uint8List(cipher.getOutputSize(plaintextBytes.length));
      var offset = cipher.processBytes(plaintextBytes, 0, plaintextBytes.length, outputBuffer, 0);
      offset += cipher.doFinal(outputBuffer, offset);

      // Il buffer contiene: ciphertext + tag
      // Estrai le parti (tag è gli ultimi 16 byte)
      final actualOutput = outputBuffer.sublist(0, offset);
      final ciphertextOnly = actualOutput.sublist(0, actualOutput.length - 16);
      final tag = actualOutput.sublist(actualOutput.length - 16);

      return {
        'ciphertext': base64Encode(ciphertextOnly),
        'nonce': base64Encode(nonce),
        'tag': base64Encode(tag),
      };
    } catch (e) {
      throw Exception('K_family encryption failed: $e');
    }
  }

  /// Decifra un messaggio con K_family usando AES-256-GCM
  String decryptWithFamilyKey(
    String ciphertextBase64,
    String nonceBase64,
    String tagBase64,
    String kFamilyBase64,
  ) {
    try {
      // Decode tutto da base64
      final kFamily = base64Decode(kFamilyBase64);
      final nonce = base64Decode(nonceBase64);
      final ciphertextOnly = base64Decode(ciphertextBase64);
      final tag = base64Decode(tagBase64);

      // Ricombina ciphertext + tag per GCM
      final ciphertext = Uint8List.fromList([...ciphertextOnly, ...tag]);

      // Setup GCM cipher
      final cipher = GCMBlockCipher(AESEngine());
      final params = AEADParameters(
        KeyParameter(kFamily),
        128, // tag size in bits
        nonce,
        Uint8List(0), // no additional authenticated data
      );

      cipher.init(false, params);

      // Decifra
      final plaintext = Uint8List(cipher.getOutputSize(ciphertext.length));
      var offset = cipher.processBytes(ciphertext, 0, ciphertext.length, plaintext, 0);
      offset += cipher.doFinal(plaintext, offset);

      // Estrai solo i byte effettivi (GCM non usa padding)
      final actualPlaintext = plaintext.sublist(0, offset);

      return utf8.decode(actualPlaintext);
    } catch (e) {
      throw Exception('K_family decryption failed: $e');
    }
  }
}
