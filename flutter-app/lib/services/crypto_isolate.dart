import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:asn1lib/asn1lib.dart';
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:image/image.dart' as img;

// Top-level helpers usable inside Isolate/compute (no instance state).
// Mirror of the decode/crypto logic in EncryptionService, kept in sync.

RSAPublicKey _decodePublicKeyStatic(String publicKeyStr) {
  final bytes = base64Decode(publicKeyStr);
  final topLevelSeq = ASN1Parser(bytes).nextObject() as ASN1Sequence;
  final bitString = topLevelSeq.elements![1] as ASN1BitString;
  final keySequenceBytes = bitString.valueBytes().sublist(1);
  final publicKeySeq = ASN1Parser(keySequenceBytes).nextObject() as ASN1Sequence;
  final modulus = (publicKeySeq.elements![0] as ASN1Integer).valueAsBigInteger!;
  final exponent = (publicKeySeq.elements![1] as ASN1Integer).valueAsBigInteger!;
  return RSAPublicKey(modulus, exponent);
}

RSAPrivateKey _decodePrivateKeyStatic(String privateKeyStr) {
  final bytes = base64Decode(privateKeyStr);
  final privateKeySeq = ASN1Parser(bytes).nextObject() as ASN1Sequence;
  final modulus = (privateKeySeq.elements![1] as ASN1Integer).valueAsBigInteger!;
  final privateExponent = (privateKeySeq.elements![3] as ASN1Integer).valueAsBigInteger!;
  final p = (privateKeySeq.elements![4] as ASN1Integer).valueAsBigInteger!;
  final q = (privateKeySeq.elements![5] as ASN1Integer).valueAsBigInteger!;
  return RSAPrivateKey(modulus, privateExponent, p, q);
}

Uint8List _rsaEncryptStatic(Uint8List data, RSAPublicKey publicKey) {
  final encryptor = OAEPEncoding(RSAEngine())
    ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));
  return _processInBlocksStatic(encryptor, data);
}

Uint8List _rsaDecryptStatic(Uint8List data, RSAPrivateKey privateKey) {
  final decryptor = OAEPEncoding(RSAEngine())
    ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
  return _processInBlocksStatic(decryptor, data);
}

Uint8List _processInBlocksStatic(AsymmetricBlockCipher engine, Uint8List input) {
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

// ============================================================================
// Message batch decrypt — used on first Firestore snapshot to avoid UI jank
// ============================================================================

class BatchDecryptArgs {
  final String privateKeyBase64;
  final List<String> encryptedPayloads;
  const BatchDecryptArgs(this.privateKeyBase64, this.encryptedPayloads);
}

/// Isolate entry point: decrypts N encrypted payloads using a single
/// decode of the RSA private key. Returns list of plaintexts (same order),
/// with null for payloads that failed.
List<String?> batchDecryptMessagesEntry(BatchDecryptArgs args) {
  final privateKey = _decodePrivateKeyStatic(args.privateKeyBase64);
  final results = <String?>[];
  for (final payload in args.encryptedPayloads) {
    try {
      final payloadJson = json.decode(utf8.decode(base64Decode(payload))) as Map<String, dynamic>;
      final encryptedAesKey = base64Decode(payloadJson['encryptedKey'] as String);
      final aesKey = _rsaDecryptStatic(encryptedAesKey, privateKey);
      final key = encrypt_lib.Key(aesKey);
      final iv = encrypt_lib.IV.fromBase64(payloadJson['iv'] as String);
      final encrypter = encrypt_lib.Encrypter(encrypt_lib.AES(key));
      final encrypted = encrypt_lib.Encrypted.fromBase64(payloadJson['message'] as String);
      results.add(encrypter.decrypt(encrypted, iv: iv));
    } catch (_) {
      results.add(null);
    }
  }
  return results;
}

// ============================================================================
// File dual encryption — moves AES(big file) + 2x RSA(AES key) off main isolate
// ============================================================================

class EncryptFileDualArgs {
  final Uint8List fileBytes;
  final String senderPublicKey;
  final String recipientPublicKey;
  const EncryptFileDualArgs(this.fileBytes, this.senderPublicKey, this.recipientPublicKey);
}

class EncryptFileDualResult {
  final Uint8List encryptedFileBytes;
  final String encryptedKeyRecipient;
  final String encryptedKeySender;
  final String iv;
  final Uint8List aesKey;
  const EncryptFileDualResult({
    required this.encryptedFileBytes,
    required this.encryptedKeyRecipient,
    required this.encryptedKeySender,
    required this.iv,
    required this.aesKey,
  });
}

EncryptFileDualResult encryptFileDualEntry(EncryptFileDualArgs args) {
  final aesKey = encrypt_lib.Key.fromSecureRandom(32).bytes;
  final key = encrypt_lib.Key(aesKey);
  final iv = encrypt_lib.IV.fromSecureRandom(16);
  final encrypter = encrypt_lib.Encrypter(encrypt_lib.AES(key));
  final encryptedFile = encrypter.encryptBytes(args.fileBytes, iv: iv);

  final senderPubKey = _decodePublicKeyStatic(args.senderPublicKey);
  final recipientPubKey = _decodePublicKeyStatic(args.recipientPublicKey);
  final encryptedKeySender = base64Encode(_rsaEncryptStatic(aesKey, senderPubKey));
  final encryptedKeyRecipient = base64Encode(_rsaEncryptStatic(aesKey, recipientPubKey));

  return EncryptFileDualResult(
    encryptedFileBytes: Uint8List.fromList(encryptedFile.bytes),
    encryptedKeyRecipient: encryptedKeyRecipient,
    encryptedKeySender: encryptedKeySender,
    iv: iv.base64,
    aesKey: aesKey,
  );
}

class EncryptWithExistingKeyArgs {
  final Uint8List fileBytes;
  final Uint8List aesKey;
  final String ivBase64;
  const EncryptWithExistingKeyArgs(this.fileBytes, this.aesKey, this.ivBase64);
}

Uint8List encryptFileWithExistingKeyEntry(EncryptWithExistingKeyArgs args) {
  final key = encrypt_lib.Key(args.aesKey);
  final iv = encrypt_lib.IV.fromBase64(args.ivBase64);
  final encrypter = encrypt_lib.Encrypter(encrypt_lib.AES(key));
  final encryptedFile = encrypter.encryptBytes(args.fileBytes, iv: iv);
  return Uint8List.fromList(encryptedFile.bytes);
}

// ============================================================================
// File decryption — RSA decrypt AES key + AES decrypt big file on isolate
// ============================================================================

class DecryptFileArgs {
  final Uint8List encryptedBytes;
  final String encryptedAesKeyBase64;
  final String ivBase64;
  final String privateKeyBase64;
  const DecryptFileArgs(
    this.encryptedBytes,
    this.encryptedAesKeyBase64,
    this.ivBase64,
    this.privateKeyBase64,
  );
}

Uint8List decryptFileEntry(DecryptFileArgs args) {
  final privateKey = _decodePrivateKeyStatic(args.privateKeyBase64);
  final encryptedAesKey = base64Decode(args.encryptedAesKeyBase64);
  final aesKey = _rsaDecryptStatic(encryptedAesKey, privateKey);

  final key = encrypt_lib.Key(aesKey);
  final iv = encrypt_lib.IV.fromBase64(args.ivBase64);
  final encrypter = encrypt_lib.Encrypter(encrypt_lib.AES(key));
  final encrypted = encrypt_lib.Encrypted(args.encryptedBytes);
  return Uint8List.fromList(encrypter.decryptBytes(encrypted, iv: iv));
}

// ============================================================================
// Thumbnail generation — decode + center-crop + re-encode in isolate
// ============================================================================

/// Center-crops a square from the image and re-encodes as high quality JPEG.
/// The final 300x300 resize is done on main (FlutterImageCompress uses a
/// native thread), but the pure-Dart image ops stay off the main isolate.
Uint8List? thumbnailCropEntry(Uint8List imageBytes) {
  final image = img.decodeImage(imageBytes);
  if (image == null) return null;

  final int cropSize = image.width < image.height ? image.width : image.height;
  final int offsetX = (image.width - cropSize) ~/ 2;
  final int offsetY = (image.height - cropSize) ~/ 2;

  final cropped = img.copyCrop(
    image,
    x: offsetX,
    y: offsetY,
    width: cropSize,
    height: cropSize,
  );

  return Uint8List.fromList(img.encodeJpg(cropped, quality: 95));
}
