import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Strategia di backup delle chiavi scelta dall'utente.
/// - [cloud]  : chiavi sincronizzate nel cloud dell'account (iCloud Keychain su
///              iOS, Block Store su Android) → cambio telefono automatico.
/// - [manual] : l'utente custodisce la chiave (copia/condividi) e la reimporta.
/// - [none]   : solo locale; se perde il telefono perde tutto.
enum BackupStrategy { cloud, manual, none }

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

  Future<void> setStrategy(BackupStrategy strategy) async {
    await _storage.write(key: _prefKey, value: strategy.name);
    // Fase 2 (iOS iCloud Keychain) / Fase 3 (Android Block Store):
    // qui ri-salveremo le 3 chiavi identità nel posto giusto in base alla scelta.
  }
}
