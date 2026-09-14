import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'encryption_service.dart';

/// Recupero della chat tramite il partner (o il vecchio telefono).
///
/// Modello: i messaggi stanno sul server, cifrati; per rileggerli serve solo
/// il certificato (chiave privata + chiave pubblica + chiave del partner).
/// Il partner può già leggere ogni messaggio della chat, quindi affidargli il
/// certificato non gli dà nulla che non abbia. Perciò:
///
/// 1. **Deposito**: a pairing completato ogni telefono cifra il proprio
///    certificato per il partner (AES casuale avvolta con la chiave pubblica
///    del partner, stesso schema dei messaggi) e lo salva in
///    `families/{fid}/escrow/{myUserId}`. Solo il partner può aprirlo.
/// 2. **Richiesta**: il telefono nuovo genera una coppia di chiavi
///    temporanea e mostra un QR con `{id, pub}`; crea
///    `recovery_requests/{id}` e resta in ascolto.
/// 3. **Risposta**: il telefono che aiuta scansiona il QR (solo in presenza:
///    l'id è casuale e non viene mai comunicato in altro modo), apre il
///    deposito del partner con la propria chiave privata (oppure usa il
///    proprio certificato, se è il vecchio telefono dello stesso utente), lo
///    ricifra per la chiave temporanea e lo scrive nella richiesta.
/// 4. Il telefono nuovo decifra, installa il certificato originale e
///    ricompone la famiglia con lo stesso ID: i messaggi tornano.
class RecoveryService {
  static const int version = 1;
  static const Duration requestTtl = Duration(minutes: 10);
  static const String qrType = 'tuyjo_recovery';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _kPriv = 'rsa_private_key';
  static const String _kPub = 'rsa_public_key';
  static const String _kPartner = 'partner_public_key';

  static String userIdOf(String publicKey) =>
      sha256.convert(utf8.encode(publicKey)).toString();

  static String familyIdOf(String a, String b) {
    final keys = [a, b]..sort();
    return sha256.convert(utf8.encode(keys.join('|'))).toString();
  }

  CollectionReference<Map<String, dynamic>> _escrowRef(String familyId) =>
      _firestore.collection('families').doc(familyId).collection('escrow');

  DocumentReference<Map<String, dynamic>> _requestRef(String id) =>
      _firestore.collection('recovery_requests').doc(id);

  // ───────────────────────────── Deposito ─────────────────────────────

  /// Salva (o aggiorna) il mio certificato cifrato per il partner.
  /// Idempotente: se il deposito sul server ha già la stessa impronta non
  /// riscrive nulla. Ritorna true se il deposito è presente e aggiornato.
  Future<bool> depositForPartner() async {
    try {
      final priv = await _storage.read(key: _kPriv);
      final pub = await _storage.read(key: _kPub);
      final partner = await _storage.read(key: _kPartner);
      if (priv == null || pub == null || partner == null) return false;

      final myUserId = userIdOf(pub);
      final partnerUserId = userIdOf(partner);
      final familyId = familyIdOf(pub, partner);
      final fingerprint = RecoveryCrypto.fingerprint(priv, pub, partner);
      final ref = _escrowRef(familyId).doc(myUserId);

      try {
        final existing = await ref.get(const GetOptions(source: Source.server));
        final d = existing.data();
        if (d != null &&
            d['fingerprint'] == fingerprint &&
            d['for_user'] == partnerUserId) {
          return true;
        }
      } on FirebaseException {
        // offline: si prova comunque a scrivere (va in coda)
      }

      final bundle = RecoveryCrypto.bundleJson(priv: priv, pub: pub, partner: partner);
      final sealed = RecoveryCrypto.seal(bundle, partner);
      await ref.set({
        'v': version,
        'for_user': partnerUserId,
        'fingerprint': fingerprint,
        ...sealed,
        'updated_at': FieldValue.serverTimestamp(),
      });
      if (kDebugMode) print('🗝️ [RECOVERY] Deposito aggiornato per il partner');
      return true;
    } catch (e) {
      if (kDebugMode) print('⚠️ [RECOVERY] deposit failed: $e');
      return false;
    }
  }

  /// Cancella il mio deposito (unpair esplicito).
  Future<void> deleteMyDeposit() async {
    try {
      final pub = await _storage.read(key: _kPub);
      final partner = await _storage.read(key: _kPartner);
      if (pub == null || partner == null) return;
      await _escrowRef(familyIdOf(pub, partner)).doc(userIdOf(pub)).delete();
    } catch (e) {
      if (kDebugMode) print('⚠️ [RECOVERY] deleteMyDeposit failed: $e');
    }
  }

  /// Cancella tutti i depositi della famiglia ("Elimina tutto").
  Future<void> deleteAllDeposits(String familyId) async {
    try {
      final snap = await _escrowRef(familyId).get();
      for (final d in snap.docs) {
        await d.reference.delete();
      }
    } catch (e) {
      if (kDebugMode) print('⚠️ [RECOVERY] deleteAllDeposits failed: $e');
    }
  }

  // ───────────────────────────── Richiesta ─────────────────────────────

  /// Crea una richiesta di recupero: chiavi temporanee + documento sul
  /// server. Il QR contiene id e chiave pubblica temporanea.
  Future<RecoveryRequest> createRequest(EncryptionService crypto) async {
    final keys = crypto.generateEphemeralKeyPair();
    final id = _randomHex(32);
    final expiresAt = DateTime.now().add(requestTtl);
    await _requestRef(id).set({
      'v': version,
      'status': 'pending',
      'temp_public_key': keys['publicKey'],
      'created_at': FieldValue.serverTimestamp(),
      'expires_at': Timestamp.fromDate(expiresAt),
    });
    final qr = jsonEncode({
      't': qrType,
      'v': version,
      'id': id,
      'pub': keys['publicKey'],
    });
    return RecoveryRequest(
      id: id,
      tempPrivateKey: keys['privateKey']!,
      tempPublicKey: keys['publicKey']!,
      qrData: qr,
      expiresAt: expiresAt,
    );
  }

  /// Emette il certificato appena il telefono che aiuta risponde.
  /// Null finché la richiesta è in attesa.
  Stream<RecoveryBundle?> watchRequest(
    RecoveryRequest request,
    EncryptionService crypto,
  ) {
    return _requestRef(request.id).snapshots().map((snap) {
      final d = snap.data();
      if (d == null || d['status'] != 'answered') return null;
      final json = RecoveryCrypto.openWith(
        d,
        (data) => crypto.rsaDecryptWithPrivateKey(request.tempPrivateKey, data),
      );
      return RecoveryBundle.fromJson(json);
    });
  }

  Future<void> deleteRequest(String id) async {
    try {
      await _requestRef(id).delete();
    } catch (_) {}
  }

  /// Installa il certificato ricevuto come identità di questo telefono.
  Future<void> installBundle(RecoveryBundle bundle) async {
    await _storage.write(key: _kPriv, value: bundle.priv);
    await _storage.write(key: _kPub, value: bundle.pub);
    await _storage.write(key: _kPartner, value: bundle.partner);
  }

  // ───────────────────────────── Risposta ─────────────────────────────

  /// Interpreta un QR di recupero. Null se non è un QR di recupero.
  static RecoveryQr? parseQr(String raw) {
    try {
      final obj = jsonDecode(raw);
      if (obj is! Map || obj['t'] != qrType) return null;
      final id = obj['id'];
      final pub = obj['pub'];
      if (id is! String || pub is! String) return null;
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(id)) return null;
      return RecoveryQr(id: id, tempPublicKey: pub);
    } catch (_) {
      return null;
    }
  }

  /// Risponde a una richiesta. [role] dice cosa inviare:
  /// - [RecoveryRole.helpPartner]: il certificato del PARTNER, preso dal suo
  ///   deposito e aperto con la mia chiave privata;
  /// - [RecoveryRole.transferSelf]: il MIO certificato (vecchio telefono).
  Future<RecoveryAnswerResult> answerRequest({
    required RecoveryQr qr,
    required RecoveryRole role,
    required EncryptionService crypto,
  }) async {
    try {
      final priv = await _storage.read(key: _kPriv);
      final pub = await _storage.read(key: _kPub);
      final partner = await _storage.read(key: _kPartner);
      if (priv == null || pub == null || partner == null) {
        return RecoveryAnswerResult.notPaired;
      }

      final reqSnap = await _requestRef(qr.id).get(const GetOptions(source: Source.server));
      final req = reqSnap.data();
      if (req == null) return RecoveryAnswerResult.expired;
      final expires = (req['expires_at'] as Timestamp?)?.toDate();
      if (req['status'] != 'pending' ||
          (expires != null && expires.isBefore(DateTime.now()))) {
        return RecoveryAnswerResult.expired;
      }
      // La chiave temporanea vale solo se è quella del QR fisicamente
      // inquadrato: una richiesta manomessa sul server non viene servita.
      if (req['temp_public_key'] != qr.tempPublicKey) {
        return RecoveryAnswerResult.invalid;
      }

      String bundleJson;
      if (role == RecoveryRole.transferSelf) {
        bundleJson = RecoveryCrypto.bundleJson(priv: priv, pub: pub, partner: partner);
      } else {
        final familyId = familyIdOf(pub, partner);
        final partnerUserId = userIdOf(partner);
        final escrow = await _escrowRef(familyId)
            .doc(partnerUserId)
            .get(const GetOptions(source: Source.server));
        final d = escrow.data();
        if (d == null || d['for_user'] != userIdOf(pub)) {
          return RecoveryAnswerResult.noDeposit;
        }
        crypto.loadPrivateKey(priv);
        bundleJson = RecoveryCrypto.openWith(d, crypto.decryptAesKeyOnlyBytes);
        // Sanity: il deposito deve essere davvero del partner.
        final b = RecoveryBundle.fromJson(bundleJson);
        if (b.pub != partner || b.partner != pub) {
          return RecoveryAnswerResult.noDeposit;
        }
      }

      final sealed = RecoveryCrypto.seal(bundleJson, qr.tempPublicKey);
      await _requestRef(qr.id).update({
        'status': 'answered',
        ...sealed,
        'answered_at': FieldValue.serverTimestamp(),
      });
      if (kDebugMode) print('🗝️ [RECOVERY] Risposta inviata (${role.name})');
      return RecoveryAnswerResult.sent;
    } catch (e) {
      if (kDebugMode) print('❌ [RECOVERY] answerRequest failed: $e');
      return RecoveryAnswerResult.error;
    }
  }

  static String _randomHex(int bytes) {
    final rnd = Random.secure();
    return List.generate(bytes, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}

enum RecoveryRole { helpPartner, transferSelf }

enum RecoveryAnswerResult { sent, notPaired, expired, invalid, noDeposit, error }

class RecoveryQr {
  final String id;
  final String tempPublicKey;
  const RecoveryQr({required this.id, required this.tempPublicKey});
}

class RecoveryRequest {
  final String id;
  final String tempPrivateKey;
  final String tempPublicKey;
  final String qrData;
  final DateTime expiresAt;
  const RecoveryRequest({
    required this.id,
    required this.tempPrivateKey,
    required this.tempPublicKey,
    required this.qrData,
    required this.expiresAt,
  });
}

class RecoveryBundle {
  final String priv;
  final String pub;
  final String partner;
  const RecoveryBundle({required this.priv, required this.pub, required this.partner});

  factory RecoveryBundle.fromJson(String json) {
    final obj = jsonDecode(json) as Map<String, dynamic>;
    final priv = obj['priv'];
    final pub = obj['pub'];
    final partner = obj['partner'];
    if (priv is! String || pub is! String || partner is! String) {
      throw const FormatException('bundle incompleto');
    }
    return RecoveryBundle(priv: priv, pub: pub, partner: partner);
  }
}

/// Primitive pure (testabili senza Firestore): busta = AES-256 (SIC/PKCS7,
/// come i messaggi) sul JSON del certificato + chiave AES avvolta con
/// RSA-OAEP per il destinatario.
class RecoveryCrypto {
  static String bundleJson({
    required String priv,
    required String pub,
    required String partner,
  }) =>
      jsonEncode({'v': RecoveryService.version, 'priv': priv, 'pub': pub, 'partner': partner});

  static String fingerprint(String priv, String pub, String partner) =>
      sha256.convert(utf8.encode('$priv|$pub|$partner')).toString();

  /// Ritorna i campi `encrypted_key`, `iv`, `payload` (tutti base64).
  static Map<String, String> seal(String plaintext, String recipientPublicKey) {
    final crypto = EncryptionService();
    final aesKey = Uint8List.fromList(
        List<int>.generate(32, (_) => Random.secure().nextInt(256)));
    final iv = encrypt_lib.IV.fromSecureRandom(16);
    final encrypter = encrypt_lib.Encrypter(encrypt_lib.AES(encrypt_lib.Key(aesKey)));
    final payload = encrypter.encrypt(plaintext, iv: iv);
    return {
      'encrypted_key': crypto.encryptAesKeyOnly(aesKey, recipientPublicKey),
      'iv': iv.base64,
      'payload': payload.base64,
    };
  }

  /// Apre una busta usando [unwrapKey] per decifrare la chiave AES.
  static String openWith(
    Map<String, dynamic> fields,
    Uint8List Function(Uint8List wrapped) unwrapKey,
  ) {
    final aesKey = unwrapKey(base64Decode(fields['encrypted_key'] as String));
    final encrypter = encrypt_lib.Encrypter(encrypt_lib.AES(encrypt_lib.Key(aesKey)));
    return encrypter.decrypt(
      encrypt_lib.Encrypted.fromBase64(fields['payload'] as String),
      iv: encrypt_lib.IV.fromBase64(fields['iv'] as String),
    );
  }
}
