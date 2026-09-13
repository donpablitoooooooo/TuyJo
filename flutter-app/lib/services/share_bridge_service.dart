import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Ponte verso la Share Extension iOS.
///
/// L'estensione invia i messaggi condivisi da sola (senza aprire l'app):
/// per cifrare le serve SOLO materiale pubblico, che l'app copia in un
/// access group del Keychain condiviso con l'estensione (l'App Group).
/// La chiave privata non lascia mai lo storage dell'app.
///
/// Da chiamare a ogni avvio e dopo ogni cambiamento di pairing: se non si
/// è accoppiati le copie vengono rimosse e l'estensione ripiega
/// sull'apertura dell'app.
class ShareBridgeService {
  static const String accessGroup = 'group.com.privatemessaging.tuyjo';
  static const String _service = 'tuyjo_share';
  static const IOSOptions _opts = IOSOptions(
    groupId: accessGroup,
    accountName: _service,
    accessibility: KeychainAccessibility.unlocked,
  );

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<void> sync() async {
    if (!Platform.isIOS) return;
    try {
      final myPub = await _storage.read(key: 'rsa_public_key');
      final partnerPub = await _storage.read(key: 'partner_public_key');
      if (myPub == null || partnerPub == null) {
        await _storage.delete(key: 'my_public_key', iOptions: _opts);
        await _storage.delete(key: 'partner_public_key', iOptions: _opts);
        if (kDebugMode) print('🔗 [SHARE-BRIDGE] identity cleared (not paired)');
        return;
      }
      await _storage.write(key: 'my_public_key', value: myPub, iOptions: _opts);
      await _storage.write(
          key: 'partner_public_key', value: partnerPub, iOptions: _opts);
      if (kDebugMode) {
        final family = sha256
            .convert(utf8.encode(([myPub, partnerPub]..sort()).join('|')))
            .toString();
        print('🔗 [SHARE-BRIDGE] identity synced (family ${family.substring(0, 8)}…)');
      }
    } catch (e) {
      if (kDebugMode) print('⚠️ [SHARE-BRIDGE] sync failed: $e');
    }
  }
}
