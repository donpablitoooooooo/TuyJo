import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'block_store_bridge.dart';

/// Rete di sicurezza SILENZIOSA per la reinstallazione sullo stesso telefono.
///
/// Non è il backup dell'utente: quello è il recupero tramite il partner
/// (RecoveryService). Qui, su Android, il certificato viene copiato nel
/// Block Store di Google Play Services, che sopravvive alla disinstallazione
/// dell'app; alla reinstallazione le chiavi tornano da sole, anche offline.
/// Su iOS non serve: il Keychain sopravvive già alla disinstallazione, quindi
/// le chiavi in secure storage sono ancora lì.
class BackupService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const String _kPriv = 'rsa_private_key';
  static const String _kPub = 'rsa_public_key';
  static const String _kPartner = 'partner_public_key';

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Copia le 3 chiavi identità nel Block Store. Idempotente: va richiamato
  /// a ogni avvio e dopo ogni pairing/recupero (include la chiave partner).
  Future<bool> cloudBackupNow() async {
    if (!_isAndroid) return true;
    final priv = await _storage.read(key: _kPriv);
    if (priv == null) return true; // niente da salvare ancora
    final pub = await _storage.read(key: _kPub);
    final partner = await _storage.read(key: _kPartner);
    final json = jsonEncode({
      'v': 1,
      'priv': priv,
      'pub': pub,
      'partner': partner,
      'saved_at': DateTime.now().toIso8601String(),
    });
    final ok = await BlockStoreBridge.store(json);
    if (kDebugMode) print('☁️ [BACKUP] cloudBackupNow stored=$ok');
    return ok;
  }

  /// All'avvio: se le chiavi mancano in locale, riprendile dal Block Store.
  /// Ritorna true se ha ripristinato la chiave privata.
  Future<bool> cloudRestoreIfNeeded() async {
    if (!_isAndroid) return false;
    if (await _storage.read(key: _kPriv) != null) return false;
    // Subito dopo l'installazione Play Services può non essere ancora pronto:
    // qualche tentativo distanziato evita di concludere "nessun backup" per
    // un errore transitorio.
    String? json;
    for (var attempt = 0; attempt < 3 && json == null; attempt++) {
      if (attempt > 0) await Future.delayed(Duration(seconds: attempt));
      json = await BlockStoreBridge.retrieve();
    }
    if (json == null) return false;
    try {
      final obj = jsonDecode(json) as Map<String, dynamic>;
      final priv = obj['priv'] as String?;
      if (priv == null) {
        await BlockStoreBridge.clear(); // blob senza chiave: residuo inutile
        return false;
      }
      await _storage.write(key: _kPriv, value: priv);
      final pub = obj['pub'] as String?;
      if (pub != null) await _storage.write(key: _kPub, value: pub);
      final partner = obj['partner'] as String?;
      if (partner != null) {
        await _storage.write(key: _kPartner, value: partner);
      } else {
        await _storage.delete(key: _kPartner);
      }
      if (kDebugMode) print('☁️ [BACKUP] restored keys from Block Store');
      return true;
    } catch (e) {
      if (kDebugMode) print('⚠️ [BACKUP] restore parse failed: $e');
      return false;
    }
  }

  /// Rimuove la copia nel Block Store ("Elimina tutto" / unpair esplicito
  /// non la toccano: serve alla reinstallazione; la cancella solo chi vuole
  /// davvero dimenticare l'identità).
  Future<void> clear() async {
    if (!_isAndroid) return;
    await BlockStoreBridge.clear();
  }
}
