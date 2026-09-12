import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'block_store_bridge.dart';

/// Strategia di backup delle chiavi scelta dall'utente.
/// - [cloud]  : chiavi sincronizzate nel cloud dell'account (iCloud Keychain su
///              iOS, Block Store su Android) → cambio telefono automatico.
/// - [manual] : l'utente custodisce la chiave (copia/condividi) e la reimporta.
enum BackupStrategy { cloud, manual }

/// Gestisce la preferenza di backup. Nelle fasi successive applicherà la
/// strategia ai 3 item identità (rsa_private_key, rsa_public_key,
/// partner_public_key): iCloud Keychain (iOS) / Block Store (Android).
class BackupService {
  static const String _prefKey = 'backup_strategy';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// La strategia scelta, oppure null se l'utente non ha ancora scelto.
  Future<BackupStrategy?> getStrategy() async {
    final value = await _storage.read(key: _prefKey);
    for (final s in BackupStrategy.values) {
      if (s.name == value) return s;
    }
    return null;
  }

  Future<bool> hasChosen() async => (await getStrategy()) != null;

  /// Ritorna false se la strategia è "cloud" ma il salvataggio nel Block
  /// Store non è riuscito (Play Services / account Google assenti): il
  /// chiamante deve avvisare l'utente, altrimenti crede di avere un backup.
  Future<bool> setStrategy(BackupStrategy strategy) async {
    await _storage.write(key: _prefKey, value: strategy.name);
    if (strategy == BackupStrategy.cloud) {
      return cloudBackupNow();
    } else {
      // Manuale: il certificato NON deve stare nel cloud. Cancella eventuali
      // backup Block Store residui (es. lasciati da una scelta "cloud"
      // precedente): il Block Store sopravvive alla disinstallazione e a
      // android:allowBackup="false", quindi senza questa pulizia le chiavi
      // verrebbero ripristinate da sole a ogni reinstallazione.
      await BlockStoreBridge.clear();
      return true;
    }
  }

  static const String _kPriv = 'rsa_private_key';
  static const String _kPub = 'rsa_public_key';
  static const String _kPartner = 'partner_public_key';

  /// Salva le 3 chiavi identità nel cloud (Android Block Store) se la strategia
  /// è "cloud". No-op altrove. Idempotente e auto-gated: va richiamato anche
  /// dopo il pairing per includere la chiave del partner.
  ///
  /// Ritorna true se il blob è stato salvato (o se non c'era nulla da fare).
  Future<bool> cloudBackupNow() async {
    if (await getStrategy() != BackupStrategy.cloud) return true;
    final priv = await _storage.read(key: _kPriv);
    if (priv == null) return true; // niente da salvare ancora
    final pub = await _storage.read(key: _kPub);
    final partner = await _storage.read(key: _kPartner);
    // Il marker 'strategy':'cloud' identifica un blob scritto volontariamente
    // come backup cloud. cloudRestoreIfNeeded ripristina SOLO i blob con questo
    // marker, così i residui di vecchi test non riportano su le chiavi.
    final json = jsonEncode(
        {'v': 1, 'strategy': 'cloud', 'priv': priv, 'pub': pub, 'partner': partner});
    final ok = await BlockStoreBridge.store(json);
    if (kDebugMode) print('☁️ [BACKUP] cloudBackupNow stored=$ok');
    return ok;
  }

  /// All'avvio: se le chiavi mancano in locale, prova a recuperarle dal cloud
  /// (Block Store) SOLO se il blob è un backup cloud volontario (marker
  /// 'strategy':'cloud'). Ritorna true se ha ripristinato la chiave privata.
  ///
  /// [force]: tenta il ripristino anche se in locale c'è già una chiave privata
  /// (es. chiave "orfana" senza partner generata da un wizard abbandonato).
  Future<bool> cloudRestoreIfNeeded({bool force = false}) async {
    final existing = await _storage.read(key: _kPriv);
    if (existing != null && !force) return false; // già presenti in locale
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
        // Blob senza chiave: residuo inutile, puliscilo.
        await BlockStoreBridge.clear();
        return false;
      }
      // Un blob senza marker 'strategy':'cloud' è nel formato della prima
      // versione del backup cloud (giugno 2026): è comunque un backup scelto
      // dall'utente, quindi va ripristinato. Verrà riscritto col marker al
      // primo avvio (cloudBackupNow in main.dart).
      if (obj['strategy'] != 'cloud' && kDebugMode) {
        print('☁️ [BACKUP] Block Store blob legacy senza marker: ripristino');
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
      // La preferenza vive nel secure storage, azzerato dalla disinstallazione:
      // riarmala, altrimenti dopo il ripristino i backup cloud non ripartono.
      await _storage.write(key: _prefKey, value: BackupStrategy.cloud.name);
      if (kDebugMode) print('☁️ [BACKUP] restored keys from cloud');
      return true;
    } catch (e) {
      if (kDebugMode) print('⚠️ [BACKUP] cloud restore parse failed: $e');
      return false;
    }
  }
}
