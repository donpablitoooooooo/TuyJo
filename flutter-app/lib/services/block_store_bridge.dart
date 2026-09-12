import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridge verso Google Block Store (solo Android): salva/recupera un blob nel
/// cloud dell'account Google, ripristinabile sul nuovo dispositivo. Su iOS/altro
/// è no-op: lì BackupService usa un item Keychain sincronizzato con iCloud.
class BlockStoreBridge {
  static const MethodChannel _channel =
      MethodChannel('com.privatemessaging.tuyjo/blockstore');

  static bool get isSupported => defaultTargetPlatform == TargetPlatform.android;

  /// Salva [json] nel Block Store (con backup su cloud). True se ok.
  static Future<bool> store(String json) async {
    if (!isSupported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('store', {'json': json});
      return ok ?? false;
    } catch (e) {
      if (kDebugMode) print('⚠️ [BLOCKSTORE] store failed: $e');
      return false;
    }
  }

  /// Recupera il blob dal Block Store, o null se assente/errore.
  static Future<String?> retrieve() async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>('retrieve');
    } catch (e) {
      if (kDebugMode) print('⚠️ [BLOCKSTORE] retrieve failed: $e');
      return null;
    }
  }

  /// Cancella il blob dal Block Store (copia locale + cloud). True se ok.
  /// Va chiamato quando l'utente NON vuole il backup cloud (es. sceglie
  /// "Manuale"), altrimenti un blob residuo verrebbe ripristinato a ogni
  /// reinstallazione — il Block Store sopravvive alla disinstallazione.
  static Future<bool> clear() async {
    if (!isSupported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('clear');
      return ok ?? false;
    } catch (e) {
      if (kDebugMode) print('⚠️ [BLOCKSTORE] clear failed: $e');
      return false;
    }
  }
}
