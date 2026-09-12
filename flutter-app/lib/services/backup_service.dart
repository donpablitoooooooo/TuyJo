import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'block_store_bridge.dart';

/// Su iOS/macOS il backup cloud è un item del Keychain marcato
/// `kSecAttrSynchronizable`: iCloud Keychain lo replica su tutti i dispositivi
/// con lo stesso Apple ID (se iCloud Keychain è attivo), quindi su un iPhone
/// nuovo il certificato c'è già. `first_unlock` (senza ThisDeviceOnly) è
/// obbligatorio perché l'item possa migrare.
const IOSOptions _kAppleSync = IOSOptions(
  synchronizable: true,
  accessibility: KeychainAccessibility.first_unlock,
);
const MacOsOptions _kMacSync = MacOsOptions(
  synchronizable: true,
  accessibility: KeychainAccessibility.first_unlock,
);
const String _kCloudBlobKey = 'tuyjo_cloud_backup';

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
      await _cloudClear();
      return true;
    }
  }

  bool get _isApple =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  /// Scrive il blob nel cloud della piattaforma: Block Store (Android) o
  /// Keychain sincronizzato con iCloud (iOS/macOS). True se salvato.
  Future<bool> _cloudStore(String json) async {
    if (_isApple) {
      try {
        await _storage.write(
          key: _kCloudBlobKey,
          value: json,
          iOptions: _kAppleSync,
          mOptions: _kMacSync,
        );
        return true;
      } catch (e) {
        if (kDebugMode) print('⚠️ [BACKUP] iCloud keychain store failed: $e');
        return false;
      }
    }
    return BlockStoreBridge.store(json);
  }

  Future<String?> _cloudRetrieve() async {
    if (_isApple) {
      try {
        return await _storage.read(
          key: _kCloudBlobKey,
          iOptions: _kAppleSync,
          mOptions: _kMacSync,
        );
      } catch (e) {
        if (kDebugMode) print('⚠️ [BACKUP] iCloud keychain read failed: $e');
        return null;
      }
    }
    return BlockStoreBridge.retrieve();
  }

  Future<void> _cloudClear() async {
    if (_isApple) {
      try {
        await _storage.delete(
          key: _kCloudBlobKey,
          iOptions: _kAppleSync,
          mOptions: _kMacSync,
        );
      } catch (_) {}
      return;
    }
    await BlockStoreBridge.clear();
  }

  static const String _kPriv = 'rsa_private_key';
  static const String _kPub = 'rsa_public_key';
  static const String _kPartner = 'partner_public_key';

  /// Salva le 3 chiavi identità nel cloud (Block Store su Android, Keychain
  /// iCloud su iOS/macOS) se la strategia è "cloud". Idempotente e auto-gated: va richiamato anche
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
    final json = jsonEncode({
      'v': 1,
      'strategy': 'cloud',
      'priv': priv,
      'pub': pub,
      'partner': partner,
      'saved_at': DateTime.now().toIso8601String(),
    });
    final ok = await _cloudStore(json);
    if (kDebugMode) print('☁️ [BACKUP] cloudBackupNow stored=$ok');
    return ok;
  }

  /// All'avvio: se le chiavi mancano in locale, prova a recuperarle dal cloud
  /// (Block Store / Keychain iCloud) SOLO se il blob è un backup cloud volontario (marker
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
      json = await _cloudRetrieve();
    }
    if (json == null) return false;
    try {
      final obj = jsonDecode(json) as Map<String, dynamic>;
      final priv = obj['priv'] as String?;
      if (priv == null) {
        // Blob senza chiave: residuo inutile, puliscilo.
        await _cloudClear();
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

/// Esito della verifica del backup (Impostazioni → Verifica backup).
enum BackupHealth {
  /// Nessuna strategia scelta.
  none,
  /// Cloud: blob presente, stessa identità, chiave del partner inclusa.
  cloudOk,
  /// Cloud: blob presente ma senza la chiave del partner.
  cloudIncomplete,
  /// Cloud: nessun blob leggibile (salvataggio fallito o servizio assente).
  cloudMissing,
  /// Manuale: certificato copiato e ancora aggiornato.
  manualOk,
  /// Manuale: mai copiato, oppure cambiato dopo l'ultima copia.
  manualOutdated,
}

class BackupStatus {
  final BackupStrategy? strategy;
  final BackupHealth health;
  /// Ultimo salvataggio cloud / ultima copia manuale, se noto.
  final DateTime? savedAt;
  const BackupStatus(this.strategy, this.health, this.savedAt);
}

extension BackupHealthCheck on BackupService {
  static const String _kFingerprint = 'backup_manual_fingerprint';
  static const String _kCopiedAt = 'backup_manual_copied_at';

  /// Impronta dell'identità corrente (chiave privata + partner): se cambia,
  /// il certificato copiato a mano non basta più a ripristinare la chat.
  Future<String?> _currentFingerprint() async {
    final priv = await _storage.read(key: BackupService._kPriv);
    if (priv == null) return null;
    final partner = await _storage.read(key: BackupService._kPartner) ?? '';
    return sha256.convert(utf8.encode('$priv|$partner')).toString();
  }

  /// Da chiamare quando l'utente copia/condivide il certificato manuale.
  Future<void> markManualCopied() async {
    final fp = await _currentFingerprint();
    if (fp == null) return;
    await _storage.write(key: _kFingerprint, value: fp);
    await _storage.write(
        key: _kCopiedAt, value: DateTime.now().toIso8601String());
  }

  /// True se la strategia è manuale, l'utente è accoppiato e il certificato
  /// copiato non corrisponde più all'identità corrente (o non è mai stato
  /// copiato): va mostrato un promemoria.
  Future<bool> manualBackupOutdated() async {
    if (await getStrategy() != BackupStrategy.manual) return false;
    final partner = await _storage.read(key: BackupService._kPartner);
    if (partner == null) return false; // non accoppiato: nessun promemoria
    final fp = await _currentFingerprint();
    if (fp == null) return false;
    return await _storage.read(key: _kFingerprint) != fp;
  }

  /// Verifica attiva del backup. Con strategia cloud riscrive il blob e lo
  /// rilegge, controllando che contenga la chiave di QUESTA identità.
  Future<BackupStatus> checkStatus() async {
    final strategy = await getStrategy();
    if (strategy == null) return const BackupStatus(null, BackupHealth.none, null);

    if (strategy == BackupStrategy.manual) {
      final outdated = await manualBackupOutdated();
      final at = await _storage.read(key: _kCopiedAt);
      return BackupStatus(
        strategy,
        outdated ? BackupHealth.manualOutdated : BackupHealth.manualOk,
        at != null ? DateTime.tryParse(at) : null,
      );
    }

    await cloudBackupNow();
    final json = await _cloudRetrieve();
    if (json == null) return BackupStatus(strategy, BackupHealth.cloudMissing, null);
    try {
      final obj = jsonDecode(json) as Map<String, dynamic>;
      final priv = await _storage.read(key: BackupService._kPriv);
      if (obj['priv'] != priv) {
        return BackupStatus(strategy, BackupHealth.cloudMissing, null);
      }
      final savedAt = DateTime.tryParse(obj['saved_at'] as String? ?? '');
      final partner = obj['partner'] as String?;
      return BackupStatus(
        strategy,
        partner == null ? BackupHealth.cloudIncomplete : BackupHealth.cloudOk,
        savedAt,
      );
    } catch (_) {
      return BackupStatus(strategy, BackupHealth.cloudMissing, null);
    }
  }
}
